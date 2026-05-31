--[[
    PetInventoryView — the single pure projection authority for pet inventory.

    THE TEMPLATE INVARIANT: pet ownership + equip state live ONLY in
    `Inventory.pets.items`. There are exactly two entry shapes, distinguished by whether
    the entry carries a numeric `quantity`:

      COMMON STACK (fungible) — keyed by the stack key "id:variant":
        items["bear:basic"] = {
            id = "bear", variant = "basic",
            quantity = N,                 -- TOTAL owned (equipped + unequipped); never
                                          --   decremented on equip
            equipped_slots = { 3, 7 },    -- which equip slots this kind fills (#≤quantity)
            obtained_at = <number>,
        }
        One entry per kind regardless of count → O(distinct kinds) storage (scales to
        millions of commons without a datastore explosion).

      SPECIAL (unique per instance) — keyed by uid:
        items[uid] = {
            uid = "<uid>", id, variant, obtained_at,
            equipped_slot = nil | 1..N,   -- THE equip authority for this instance
            level, exp, enchantments, huge, serial, rarity_id, nickname, locked, ...
        }

    There is no `_kind` discriminator and equipping NEVER changes ownership — it only adds
    a slot to `equipped_slots` (commons) or sets `equipped_slot` (specials). So counts can
    never drift and equipped pets are counted identically to unequipped ones.

    PURE: no Roblox APIs, no `game`/`Instance`/`task`, no `os.time`, no globals. Server and
    client both require this same code, so their views are byte-identical by construction.

    API:
      isStackEntry(entry)                 -> boolean (true = common stack, false = special)
      isSpecial(record, capability)       -> boolean
      stackKey(record, config, capability)-> string (display grouping key)
      normalize(items)                    -> items (idempotent canonical fixups, both shapes)
      groups(items, config, capability)   -> { {key,total,equippedCount,unequippedCount,
                                                isSpecial,sampleRecord,uids} }
      equippedSlots(items, maxSlots)      -> slotMap {[n]=descriptor}, conflicts {descriptor}
                                             descriptor = {slot, kind="special"|"stack",
                                               uid?|key?, id?, variant?}
      usedSlots(items, config, capability)-> integer
      categoryCounts(items, config, capability) -> { display, total }
      isLevelable(record, capability)     -> boolean
      isEnchantable(record, capability)   -> boolean
]]

local PetInventoryView = {}

local DEFAULT_STACK_FIELDS = { "id", "variant" }

-- Discriminate the two shapes. A common stack is keyed by exactly "id:variant"; a special
-- is keyed by its uid (which never contains ":"). When the key is known we use it (fully
-- robust even if a legacy special still carries a vestigial quantity=1). Without a key we
-- fall back to the self-describing form (stacks have quantity + no uid; specials have uid).
local function isStackEntry(entry, key)
    if type(entry) ~= "table" then
        return false
    end
    if key ~= nil then
        return key == (tostring(entry.id) .. ":" .. tostring(entry.variant or "basic"))
    end
    return type(entry.quantity) == "number" and entry.uid == nil
end
PetInventoryView.isStackEntry = isStackEntry

-- Coerce an equipped-slots value (array {3,7} OR set {[3]=true}) into a sorted, unique,
-- positive-integer array, clamped so at most `quantity` copies can be equipped.
local function toSlotArray(slots, quantity)
    local seen, out = {}, {}
    if type(slots) == "table" then
        for k, v in pairs(slots) do
            local n
            if v == true then
                n = tonumber(k) -- set form {[3]=true}
            else
                n = tonumber(v) -- array form {3,7}
            end
            if n and n >= 1 and n == math.floor(n) and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        end
    end
    table.sort(out)
    if quantity ~= nil then
        local cap = math.max(0, math.floor(tonumber(quantity) or 0))
        while #out > cap do
            table.remove(out) -- drop the highest slots beyond capacity
        end
    end
    return out
end
PetInventoryView.toSlotArray = toSlotArray

function PetInventoryView.isSpecial(record, capability)
    if type(record) ~= "table" then
        return false
    end
    capability = capability or {}
    if capability.allowAll == true then
        return true
    end
    if record.huge == true then
        return true
    end
    local rarity = record.rarity_id or record.variant
    local special = capability.specialRarities
    return special ~= nil and rarity ~= nil and special[rarity] == true
end

-- Display grouping key. Specials key uniquely by uid (never merge with each other or with
-- the common stack of the same id:variant); commons key by the configured stack fields.
function PetInventoryView.stackKey(record, config, capability)
    if capability ~= nil and PetInventoryView.isSpecial(record, capability) then
        return "uid:" .. tostring(record.uid)
    end
    local fields = (config and config.stack_key_fields) or DEFAULT_STACK_FIELDS
    local parts = {}
    for _, field in ipairs(fields) do
        parts[#parts + 1] = tostring(record[field] ~= nil and record[field] or "")
    end
    return table.concat(parts, ":")
end

-- Idempotent canonical fixups for both shapes. Run by migration AND on every load.
function PetInventoryView.normalize(items)
    items = items or {}
    for key, entry in pairs(items) do
        if type(entry) == "table" then
            if isStackEntry(entry, key) then
                -- common stack
                entry.quantity = math.max(0, math.floor(tonumber(entry.quantity) or 0))
                entry.variant = entry.variant or "basic"
                entry.equipped_slots = toSlotArray(entry.equipped_slots, entry.quantity)
                entry.uid = nil
                entry._kind = nil
                entry.equipped_slot = nil
            else
                -- special per-uid
                if entry.uid ~= key then
                    entry.uid = key
                end
                local slot = tonumber(entry.equipped_slot)
                if slot == nil or slot < 1 or slot ~= math.floor(slot) then
                    entry.equipped_slot = nil
                else
                    entry.equipped_slot = slot
                end
                entry.quantity = nil
                entry.equipped_slots = nil
                entry._kind = nil
            end
        end
    end
    return items
end

-- Ordered display groups (deterministic by obtained_at then key). A common stack is one
-- group; each special is its own singleton group.
function PetInventoryView.groups(items, config, capability)
    local entries = {}
    for key, entry in pairs(items or {}) do
        if type(entry) == "table" then
            entries[#entries + 1] = { key = key, entry = entry }
        end
    end
    table.sort(entries, function(a, b)
        local ao = tonumber(a.entry.obtained_at) or 0
        local bo = tonumber(b.entry.obtained_at) or 0
        if ao ~= bo then
            return ao < bo
        end
        return tostring(a.key) < tostring(b.key)
    end)

    local order, byKey = {}, {}
    for _, item in ipairs(entries) do
        local entry, key = item.entry, item.key
        local gkey = PetInventoryView.stackKey(entry, config, capability)
        local group = byKey[gkey]
        if not group then
            group = {
                key = gkey,
                total = 0,
                equippedCount = 0,
                unequippedCount = 0,
                isSpecial = capability ~= nil and PetInventoryView.isSpecial(entry, capability)
                    or false,
                sampleRecord = entry,
                uids = {},
            }
            byKey[gkey] = group
            order[#order + 1] = group
        end
        if isStackEntry(entry, key) then
            local qty = math.max(0, math.floor(tonumber(entry.quantity) or 0))
            local equipped = math.min(qty, #toSlotArray(entry.equipped_slots, qty))
            group.total += qty
            group.equippedCount += equipped
            group.unequippedCount += (qty - equipped)
        else
            group.total += 1
            if entry.equipped_slot ~= nil then
                group.equippedCount += 1
            else
                group.unequippedCount += 1
            end
            group.uids[#group.uids + 1] = entry.uid or key
        end
    end
    return order
end

-- Map equipped slots -> descriptor. On a slot collision the comparator-smaller entry wins;
-- losers are returned in `conflicts` so the caller can clear them. Slots outside
-- [1..maxSlots] are ignored here (the caller clears over-cap slots separately).
function PetInventoryView.equippedSlots(items, maxSlots)
    maxSlots = tonumber(maxSlots) or 0
    local candidates = {}
    for key, entry in pairs(items or {}) do
        if type(entry) == "table" then
            if isStackEntry(entry, key) then
                for _, slot in ipairs(toSlotArray(entry.equipped_slots, entry.quantity)) do
                    if slot >= 1 and slot <= maxSlots then
                        candidates[#candidates + 1] = {
                            slot = slot,
                            kind = "stack",
                            key = key,
                            id = entry.id,
                            variant = entry.variant or "basic",
                            obtained_at = tonumber(entry.obtained_at) or 0,
                            sortKey = key,
                        }
                    end
                end
            else
                local slot = tonumber(entry.equipped_slot)
                if slot and slot >= 1 and slot <= maxSlots and slot == math.floor(slot) then
                    candidates[#candidates + 1] = {
                        slot = slot,
                        kind = "special",
                        uid = entry.uid or key,
                        obtained_at = tonumber(entry.obtained_at) or 0,
                        sortKey = entry.uid or key,
                    }
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.obtained_at ~= b.obtained_at then
            return a.obtained_at < b.obtained_at
        end
        return tostring(a.sortKey) < tostring(b.sortKey)
    end)
    local slotMap, conflicts = {}, {}
    for _, candidate in ipairs(candidates) do
        if slotMap[candidate.slot] == nil then
            slotMap[candidate.slot] = candidate
        else
            conflicts[#conflicts + 1] = candidate
        end
    end
    return slotMap, conflicts
end

-- The slot-accounting authority. With count_stacks_as_single (default), one display group
-- costs one slot; otherwise every instance (quantity-expanded) costs a slot.
function PetInventoryView.usedSlots(items, config, capability)
    if not config or config.count_stacks_as_single ~= false then
        return #PetInventoryView.groups(items, config, capability)
    end
    local n = 0
    for key, entry in pairs(items or {}) do
        if isStackEntry(entry, key) then
            n += math.max(0, math.floor(tonumber(entry.quantity) or 0))
        elseif type(entry) == "table" then
            n += 1
        end
    end
    return n
end

function PetInventoryView.categoryCounts(items, config, capability)
    local total = 0
    for key, entry in pairs(items or {}) do
        if isStackEntry(entry, key) then
            total += math.max(0, math.floor(tonumber(entry.quantity) or 0))
        elseif type(entry) == "table" then
            total += 1
        end
    end
    return {
        display = #PetInventoryView.groups(items, config, capability),
        total = total,
    }
end

-- Config-driven capability checks replacing the deleted `_kind == "special"` guard.
-- Both delegate to isSpecial so "can level / be enchanted" and "is unique-per-instance"
-- are the same predicate by construction.
function PetInventoryView.isLevelable(record, capability)
    return PetInventoryView.isSpecial(record, capability)
end

function PetInventoryView.isEnchantable(record, capability)
    return PetInventoryView.isSpecial(record, capability)
end

return PetInventoryView
