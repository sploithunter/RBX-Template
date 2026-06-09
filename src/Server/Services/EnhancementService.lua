--[[
    EnhancementService — CoH-style enhancements (Jason's design; see configs/enhancements.lua).

    Owns profile.EnhancementInv (uid -> { type, origins }) and SLOTTING into the empty slot
    records of profile.Slots[powerId] (earned via AugmentationService). A filled slot becomes
    { enh = { type, origins } }; the inherent slot can be filled too (it's still a slot).

    Rules enforced here (pure logic in src/Shared/Game/Enhancements.lua):
      • player must own the power; the slot must exist
      • type must be compatible with the power (family / AoE gating)
      • the PLAYER's origin must be among the enhancement's origins (single = exact match,
        dual = either) — the single-vs-dual economy
      • replacing an occupied slot DESTROYS the old enhancement (config replace_destroys)

    Effects apply at cast time: PowerService aggregates the cast power's slots into per-axis
    multipliers (Enhancements.aggregate) and feeds PowerStats.resolveEffective.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Enhancements = require(ReplicatedStorage.Shared.Game.Enhancements)

local EnhancementService = {}
EnhancementService.__index = EnhancementService

function EnhancementService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._config = self._configLoader:LoadConfig("enhancements")
    self._powersConfig = self._configLoader:LoadConfig("powers")
end

local function inv(data)
    if type(data.EnhancementInv) ~= "table" then
        data.EnhancementInv = {}
    end
    return data.EnhancementInv
end

local function invCount(map)
    local n = 0
    for _ in pairs(map) do
        n += 1
    end
    return n
end

local function ownsPower(data, powerId)
    for _, id in ipairs(data.Powers or {}) do
        if id == powerId then
            return true
        end
    end
    return false
end

-- Full client view: inventory (with usability for THIS player) + per-power slotted records.
function EnhancementService:GetState(player)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    local items = {}
    for uid, rec in pairs(inv(data)) do
        items[#items + 1] = {
            uid = uid,
            type = rec.type,
            origins = rec.origins,
            name = Enhancements.displayName(self._config, rec),
            usable = Enhancements.usableBy(rec, data.Archetype),
            single = Enhancements.isSingle(rec),
        }
    end
    table.sort(items, function(a, b)
        return a.name < b.name
    end)
    return {
        ok = true,
        inventory = items,
        slots = data.Slots or {},
        archetype = data.Archetype,
    }
end

-- Grant an enhancement into the inventory (drops + admin). Returns the uid.
function EnhancementService:Grant(player, record)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    if not Enhancements.isValid(self._config, record) then
        return { ok = false, reason = "invalid_record" }
    end
    local map = inv(data)
    local cap = tonumber(self._config.inventory_cap) or 60
    if invCount(map) >= cap then
        return { ok = false, reason = "inventory_full" }
    end
    local uid = HttpService:GenerateGUID(false)
    map[uid] = { type = record.type, origins = record.origins }
    self._dataService:RequestSave(player, "enhancement_grant", { critical = false })
    return {
        ok = true,
        uid = uid,
        name = Enhancements.displayName(self._config, map[uid]),
    }
end

-- Slot an inventory enhancement into slot #slotIndex of an owned power.
function EnhancementService:Slot(player, powerId, slotIndex, uid)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    local map = inv(data)
    local rec = map[uid]
    if not rec then
        return { ok = false, reason = "not_in_inventory" }
    end
    if not ownsPower(data, powerId) then
        return { ok = false, reason = "power_not_owned" }
    end
    local slots = type(data.Slots) == "table" and data.Slots[powerId]
    slotIndex = math.floor(tonumber(slotIndex) or 0)
    local slot = type(slots) == "table" and slots[slotIndex]
    if type(slot) ~= "table" then
        return { ok = false, reason = "no_such_slot" }
    end
    if not Enhancements.usableBy(rec, data.Archetype) then
        return { ok = false, reason = "wrong_origin" }
    end
    local powerDef = self._powersConfig.powers[powerId]
    local okType, why = Enhancements.compatibleWith(
        self._config,
        rec.type,
        powerDef,
        self._powersConfig.effect_kinds
    )
    if not okType then
        return { ok = false, reason = why or "incompatible" }
    end
    if slot.enh ~= nil and self._config.replace_destroys ~= true then
        return { ok = false, reason = "slot_occupied" }
    end
    -- Commit: fill the slot (replace destroys the old record) + consume from inventory.
    slot.enh = { type = rec.type, origins = rec.origins }
    map[uid] = nil
    self._dataService:RequestSave(player, "enhancement_slot", { critical = true })
    return {
        ok = true,
        powerId = powerId,
        slotIndex = slotIndex,
        name = Enhancements.displayName(self._config, slot.enh),
    }
end

-- Roll a random drop record (type by weight; grade by single_chance; origins uniform).
-- `rng` = Random instance (injectable for tests/determinism).
function EnhancementService:RollDrop(rng)
    rng = rng or Random.new()
    local drops = self._config.drops or {}
    local weights = drops.type_weights or {}
    local total = 0
    for t in pairs(self._config.types) do
        total += tonumber(weights[t]) or 1
    end
    local pick, acc = nil, rng:NextNumber() * total
    for t in pairs(self._config.types) do
        acc -= tonumber(weights[t]) or 1
        if acc <= 0 then
            pick = t
            break
        end
    end
    local origins = self._config.origins or {}
    local a = origins[rng:NextInteger(1, #origins)]
    if rng:NextNumber() < (tonumber(drops.single_chance) or 0.35) then
        return { type = pick, origins = { a } }
    end
    local b = a
    while b == a do
        b = origins[rng:NextInteger(1, #origins)]
    end
    return { type = pick, origins = { a, b } }
end

return EnhancementService
