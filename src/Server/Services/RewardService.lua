--[[
    RewardService — Phase 7 (the reward spine's grant terminal).

    The single place a reward bundle becomes real. Quests, daily streaks, shop
    purchases, and achievements all call Grant(player, bundle, source); RewardService
    fans the bundle out to the live systems (currencies → DataService, items →
    InventoryService, pets → PetGrantService, timed effects → PlayerEffectsService,
    capacity → Upgrades) and writes a source-keyed grant-history audit entry (capped,
    mirroring the trade/fusion logs).

    Pure shape rules live in the shared RewardBundle core; this service owns the
    side effects + the ledger.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardBundle = require(ReplicatedStorage.Shared.Game.RewardBundle)

local RewardService = {}
RewardService.__index = RewardService

function RewardService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._config = self._configLoader:LoadConfig("rewards")
    self._grantLog = {} -- append-only, capped at config.grant_log_limit
end

function RewardService:_service(name)
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get(name)
    end)
    return ok and service or nil
end

-- Apply a reward bundle to a live player. `source` is a traceable tag
-- ("quest:crystal_crusher", "daily:3", "shop:starter_pack").
function RewardService:Grant(player, bundle, source)
    local b = RewardBundle.normalize(bundle)
    local granted = { currencies = {}, items = {}, pets = {}, effects = {}, slots = {} }

    -- Currencies
    for currency, amount in pairs(b.currencies) do
        if self._dataService then
            self._dataService:AddCurrency(player, currency, amount, source or "reward_grant")
        end
        granted.currencies[currency] = amount
    end

    -- Items (consumables/resources/tools)
    local inventory = self:_service("InventoryService")
    for _, item in ipairs(b.items) do
        local bucket = item.bucket or self._config.default_item_bucket or "consumables"
        if inventory then
            local uid = inventory:AddItem(player, bucket, {
                id = item.id,
                variant = item.variant or "basic",
                quantity = item.qty or item.quantity or 1,
            })
            table.insert(granted.items, { id = item.id, qty = item.qty or 1, uid = uid })
        else
            table.insert(granted.items, { id = item.id, qty = item.qty or 1 })
        end
    end

    -- Pets
    local petGrant = self:_service("PetGrantService")
    for _, pet in ipairs(b.pets) do
        if petGrant then
            local res = petGrant:GrantPet(player, {
                petType = pet.id,
                variant = pet.variant,
                element = pet.element,
                source = source or "reward_grant",
            })
            table.insert(granted.pets, { id = pet.id, uid = res and res.uid, ok = res and res.ok })
        else
            table.insert(granted.pets, { id = pet.id })
        end
    end

    -- Timed effects
    local effects = self:_service("PlayerEffectsService")
    for _, effect in ipairs(b.effects) do
        if effects then
            pcall(function()
                effects:ApplyEffect(player, effect.id, effect.seconds or 0, {
                    statModifiers = effect.modifiers,
                    stacking = "extend_duration",
                })
            end)
        end
        table.insert(granted.effects, { id = effect.id, seconds = effect.seconds })
    end

    -- Experience (drives the derived player level via PlayerProgressionService).
    if (b.experience or 0) > 0 then
        local progression = self:_service("PlayerProgressionService")
        if progression and progression.AddExperience then
            progression:AddExperience(player, b.experience)
        end
        granted.experience = b.experience
    end

    -- Permanent capacity (upgrade levels), lazy-init on the profile.
    if next(b.slots) ~= nil and self._dataService then
        local data = self._dataService:GetData(player)
        if data then
            data.Upgrades = data.Upgrades or {}
            for upgradeId, amount in pairs(b.slots) do
                data.Upgrades[upgradeId] = (data.Upgrades[upgradeId] or 0) + amount
                granted.slots[upgradeId] = data.Upgrades[upgradeId]
            end
            self._dataService:RequestSave(player, "reward_slots", { critical = true })
        end
    end

    local rec = {
        player = player.UserId,
        source = source or "reward_grant",
        granted = granted,
        timestamp = os.time(),
    }
    self:_appendLog(rec)
    return { ok = true, granted = granted, source = rec.source }
end

function RewardService:_appendLog(rec)
    table.insert(self._grantLog, rec)
    local limit = self._config.grant_log_limit or 200
    while #self._grantLog > limit do
        table.remove(self._grantLog, 1)
    end
end

-- Queryable grant-history audit log (optionally filtered to a userId).
function RewardService:GetGrantLog(userId)
    if not userId then
        return { ok = true, records = self._grantLog }
    end
    local out = {}
    for _, rec in ipairs(self._grantLog) do
        if rec.player == userId then
            table.insert(out, rec)
        end
    end
    return { ok = true, records = out }
end

-- Test/UI affordance: normalize a bundle without applying it.
function RewardService:Simulate(bundle)
    return {
        ok = true,
        bundle = RewardBundle.normalize(bundle),
        empty = RewardBundle.isEmpty(bundle),
    }
end

return RewardService
