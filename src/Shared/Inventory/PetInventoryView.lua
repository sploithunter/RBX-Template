--[[
    PetInventoryView — the single pure projection authority for pet inventory.

    THE TEMPLATE INVARIANT: pet ownership + equip state live ONLY in
    `Inventory.pets.items`, keyed by uid, one record per pet instance:

        items[uid] = {
            uid = "<uid>",          -- redundant copy of the key (projection convenience)
            id = "bear", variant = "golden", obtained_at = <number>,
            equipped_slot = nil | 1..N,   -- THE equip authority; nil = unequipped
            -- progression/identity fields exist only on records that carry them:
            level, exp, enchantments, huge, serial, rarity_id, nickname, locked, ...
        }

    There is no `quantity`, no `id:variant` stack key, no `_kind` discriminator.
    A "stack" is purely a DISPLAY GROUPING computed here at render time. Equipping
    sets `equipped_slot` on the record and never touches ownership, so counts can
    never drift and equipped pets are counted identically to unequipped ones.

    This module is PURE: no Roblox APIs, no `game`/`Instance`/`task`, no `os.time`,
    no globals. Callers pass `config` (the pets bucket config) and timestamps. Server
    and client both require this same code, so their views are byte-identical by
    construction — the strongest "no projection disagrees with the source" guarantee.

    API:
      stackKey(record, config)            -> string (display grouping key)
      normalize(items)                    -> items (idempotent canonical fixups)
      groups(items, config)               -> { {key,total,equippedCount,sampleRecord,uids} }
      equippedSlots(items, maxSlots)      -> slotMap {[n]=uid}, conflicts {uid}
      usedSlots(items, config)            -> integer
      categoryCounts(items, config)       -> { display, total }
      isLevelable(record, capability)     -> boolean
      isEnchantable(record, capability)   -> boolean
]]

local PetInventoryView = {}

local DEFAULT_STACK_FIELDS = { "id", "variant" }

-- Stable ordering shared by every projection so server/client/rebuilds agree exactly.
local function compareRecords(a, b)
    local ao = tonumber(a.obtained_at) or 0
    local bo = tonumber(b.obtained_at) or 0
    if ao ~= bo then
        return ao < bo
    end
    return tostring(a.uid) < tostring(b.uid)
end

-- Collect records into a comparator-sorted array (deterministic).
local function sortedRecords(items)
    local recs = {}
    for _, rec in pairs(items or {}) do
        if type(rec) == "table" then
            recs[#recs + 1] = rec
        end
    end
    table.sort(recs, compareRecords)
    return recs
end

-- Capability check: a record is "special" (per-instance unique, never stacked) when
-- it is huge, or its rarity is in capability.specialRarities, or allowAll. This is the
-- ONE classifier shared by the server (slot accounting, projection routing) and the
-- view, so a pet is grouped/leveled/enchanted identically everywhere.
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

-- Display grouping key. Special records key uniquely by uid (so two huge bears with
-- the same id:variant never merge, and never merge into the common bear stack);
-- commons key by the configured stack fields (id:variant). `capability` is optional —
-- without it every record groups by stack fields (legacy display behaviour).
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

-- Idempotent canonical fixups. Run by migration AND on every load. Never mints or
-- deletes records; only repairs each record's shape.
function PetInventoryView.normalize(items)
    items = items or {}
    for key, rec in pairs(items) do
        if type(rec) == "table" then
            -- uid must equal the key.
            if rec.uid ~= key then
                rec.uid = key
            end
            -- equipped_slot is a positive integer or nil (drop 0/""/false/non-numbers).
            local slot = tonumber(rec.equipped_slot)
            if slot == nil or slot < 1 or slot ~= math.floor(slot) then
                rec.equipped_slot = nil
            else
                rec.equipped_slot = slot
            end
            -- Forbidden legacy fields: ownership is one-record-per-instance.
            rec.quantity = nil
            rec._kind = nil
        end
    end
    return items
end

-- Ordered display groups. Each group's sampleRecord is its comparator-smallest
-- member; uids are comparator-sorted; the array is ordered by sampleRecord.
function PetInventoryView.groups(items, config, capability)
    local order = {}
    local byKey = {}
    for _, rec in ipairs(sortedRecords(items)) do
        local key = PetInventoryView.stackKey(rec, config, capability)
        local group = byKey[key]
        if not group then
            group = {
                key = key,
                total = 0,
                equippedCount = 0,
                unequippedCount = 0,
                isSpecial = capability ~= nil and PetInventoryView.isSpecial(rec, capability)
                    or false,
                sampleRecord = rec,
                uids = {},
            }
            byKey[key] = group
            order[#order + 1] = group
        end
        group.total += 1
        if rec.equipped_slot ~= nil then
            group.equippedCount += 1
        else
            group.unequippedCount += 1
        end
        group.uids[#group.uids + 1] = rec.uid
    end
    return order
end

-- Map equipped slots -> uid. On a slot collision the comparator-smaller record wins;
-- losers are returned in `conflicts` so the caller can clear their equipped_slot.
-- Records with equipped_slot outside [1..maxSlots] are ignored here (the caller
-- clears over-cap slots separately).
function PetInventoryView.equippedSlots(items, maxSlots)
    maxSlots = tonumber(maxSlots) or 0
    local candidates = {}
    for _, rec in pairs(items or {}) do
        local slot = type(rec) == "table" and rec.equipped_slot or nil
        if type(slot) == "number" and slot >= 1 and slot <= maxSlots then
            candidates[#candidates + 1] = rec
        end
    end
    table.sort(candidates, compareRecords)
    local slotMap = {}
    local conflicts = {}
    for _, rec in ipairs(candidates) do
        local slot = rec.equipped_slot
        if slotMap[slot] == nil then
            slotMap[slot] = rec.uid
        else
            conflicts[#conflicts + 1] = rec.uid
        end
    end
    return slotMap, conflicts
end

-- The slot-accounting authority. With count_stacks_as_single (default), one display
-- group costs one slot (preserving the legacy effective capacity); otherwise every
-- instance costs a slot.
function PetInventoryView.usedSlots(items, config, capability)
    if not config or config.count_stacks_as_single ~= false then
        return #PetInventoryView.groups(items, config, capability)
    end
    local n = 0
    for _, rec in pairs(items or {}) do
        if type(rec) == "table" then
            n += 1
        end
    end
    return n
end

function PetInventoryView.categoryCounts(items, config, capability)
    local total = 0
    for _, rec in pairs(items or {}) do
        if type(rec) == "table" then
            total += 1
        end
    end
    return {
        display = #PetInventoryView.groups(items, config, capability),
        total = total,
    }
end

-- Config-driven capability checks replacing the deleted `_kind == "special"` guard.
-- capability = { specialRarities = {[rarity]=true}, allowAll = bool }. Both delegate to
-- isSpecial so "can this pet level / be enchanted" and "is this pet unique-per-instance"
-- are the same predicate by construction.
function PetInventoryView.isLevelable(record, capability)
    return PetInventoryView.isSpecial(record, capability)
end

function PetInventoryView.isEnchantable(record, capability)
    return PetInventoryView.isSpecial(record, capability)
end

return PetInventoryView
