local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Libraries.Signal)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local PetIndexService = {}
PetIndexService.__index = PetIndexService

local function petKey(petId, variant)
    return tostring(petId) .. ":" .. tostring(variant or "basic")
end

local function countMapEntries(map)
    local count = 0
    for _ in pairs(map or {}) do
        count += 1
    end
    return count
end

function PetIndexService:Init()
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    self._dataService = self._modules.DataService
    self._statsService = self._modules.StatsService
    self._economyService = self._modules.EconomyService

    self._config = self._configLoader:LoadConfig("pet_index")
    self._petsConfig = self._configLoader:LoadConfig("pets")
    self.IndexChanged = Signal.new()

    self._logger:Info("PetIndexService initialized", {
        context = "PetIndexService",
        milestones = #(self._config.milestones or {}),
    })
end

function PetIndexService:_ensureIndex(data)
    data.PetIndex = data.PetIndex or {}
    data.PetIndex.Discovered = data.PetIndex.Discovered or {}
    data.PetIndex.Milestones = data.PetIndex.Milestones or {}
    return data.PetIndex
end

function PetIndexService:_grantReward(player, reward, source)
    if type(reward) ~= "table" or reward.type ~= "currency" then
        return false, "Unsupported reward type"
    end

    local amount = tonumber(reward.amount) or 0
    if amount <= 0 then
        return false, "Invalid reward amount"
    end

    if self._economyService and self._economyService.AddCurrency then
        return self._economyService:AddCurrency(
            player,
            reward.currency,
            amount,
            source or "pet_index_reward"
        )
    end

    if self._dataService and self._dataService.AddCurrency then
        return self._dataService:AddCurrency(
            player,
            reward.currency,
            amount,
            source or "pet_index_reward"
        )
    end

    return false, "No reward grant service available"
end

function PetIndexService:_evaluateMilestones(player, index)
    local count = countMapEntries(index.Discovered)
    local granted = {}

    for _, milestone in ipairs(self._config.milestones or {}) do
        if count >= milestone.goal and not index.Milestones[milestone.id] then
            local ok, reason =
                self:_grantReward(player, milestone.reward, "pet_index_" .. milestone.id)
            if ok then
                index.Milestones[milestone.id] = {
                    completed_at = os.time(),
                    goal = milestone.goal,
                }
                table.insert(granted, milestone.id)
            else
                self._logger:Warn("Failed to grant pet index milestone reward", {
                    context = "PetIndexService",
                    player = player.Name,
                    milestone = milestone.id,
                    reason = reason,
                })
            end
        end
    end

    return granted
end

function PetIndexService:_syncDistinctCounter(player, count)
    if self._statsService and self._statsService.Set then
        self._statsService:Set(player, "distinct_pets", count)
    elseif self._dataService and self._dataService.SetCounter then
        self._dataService:SetCounter(player, "distinct_pets", count)
    end
end

function PetIndexService:RecordPetObtained(player, petData)
    if type(petData) ~= "table" or type(petData.id) ~= "string" then
        return {
            ok = false,
            error = "Invalid pet data",
        }
    end

    local data = self._dataService:GetData(player)
    if not data then
        return {
            ok = false,
            error = "Player data not loaded",
        }
    end

    local variant = petData.variant or self._config.default_variant or "basic"
    local key = petKey(petData.id, variant)
    local index = self:_ensureIndex(data)
    local entry = index.Discovered[key]
    local isNew = entry == nil

    if isNew then
        index.Discovered[key] = {
            id = petData.id,
            variant = variant,
            discovered_at = os.time(),
        }
    end

    local count = countMapEntries(index.Discovered)
    local granted = {}
    if isNew then
        self:_syncDistinctCounter(player, count)
        granted = self:_evaluateMilestones(player, index)
        self._dataService:RequestSave(player, "pet_index_discovered", { critical = true })
    end

    local snapshot = self:GetIndex(player)
    if isNew then
        self.IndexChanged:Fire(player, snapshot)
        Signals.PetIndexUpdated:FireClient(player, snapshot)
    end

    return {
        ok = true,
        isNew = isNew,
        key = key,
        count = count,
        granted = granted,
    }
end

function PetIndexService:_countConfiguredPets()
    local total = 0
    for _, pet in pairs(self._petsConfig.pets or {}) do
        for _ in pairs(pet.variants or {}) do
            total += 1
        end
    end
    return total
end

function PetIndexService:GetIndex(player)
    local data = self._dataService:GetData(player)
    if not data then
        return {
            count = 0,
            total = self:_countConfiguredPets(),
            discovered = {},
            milestones = {},
        }
    end

    local index = self:_ensureIndex(data)
    return {
        count = countMapEntries(index.Discovered),
        total = self:_countConfiguredPets(),
        discovered = index.Discovered,
        milestones = index.Milestones,
    }
end

return PetIndexService
