local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Libraries.Signal)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)
local fireGameEvent = require(ReplicatedStorage.Shared.Network.FireGameEvent)

local AchievementsService = {}
AchievementsService.__index = AchievementsService

function AchievementsService:Init()
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    self._dataService = self._modules.DataService
    self._statsService = self._modules.StatsService
    self._economyService = self._modules.EconomyService

    self._config = self._configLoader:LoadConfig("achievements")
    self.Completed = Signal.new()

    if self._statsService and self._statsService.CounterChanged then
        self._statsConnection = self._statsService.CounterChanged:Connect(
            function(player, counterId, newValue)
                self:_onCounterChanged(player, counterId, newValue)
            end
        )
    end

    self._logger:Info("AchievementsService initialized", {
        context = "AchievementsService",
        achievements = self:_countAchievements(),
    })
end

function AchievementsService:Start()
    Players.PlayerAdded:Connect(function(player)
        task.spawn(function()
            self:_waitForDataAndEvaluate(player)
        end)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            self:_waitForDataAndEvaluate(player)
        end)
    end
end

function AchievementsService:_waitForDataAndEvaluate(player)
    local deadline = os.clock() + 15
    while player.Parent and not self._dataService:IsDataLoaded(player) and os.clock() < deadline do
        task.wait(0.2)
    end

    if player.Parent and self._dataService:IsDataLoaded(player) then
        self:EvaluateAll(player)
    end
end

function AchievementsService:_countAchievements()
    local count = 0
    for _ in pairs(self._config.achievements or {}) do
        count += 1
    end
    return count
end

function AchievementsService:_ensureAchievements(data)
    data.Achievements = data.Achievements or {}
    data.Achievements.Completed = data.Achievements.Completed or {}
    return data.Achievements
end

-- Runtime locator (RewardService is registered in boot; no boot-time dep cycle).
function AchievementsService:_service(name)
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get(name)
    end)
    return ok and service or nil
end

-- Translate an achievement tier reward into a RewardBundle. Supports the legacy
-- currency shape ({ type="currency", currency, amount }) and a forward-looking full
-- bundle ({ bundle = { currencies/pets/items/effects/slots } }) so achievements can
-- award anything the reward spine can grant.
local function rewardToBundle(reward)
    if type(reward) ~= "table" then
        return nil
    end
    if type(reward.bundle) == "table" then
        return reward.bundle
    end
    if reward.type == "currency" and reward.currency then
        local amount = tonumber(reward.amount) or 0
        if amount > 0 then
            return { currencies = { [reward.currency] = amount } }
        end
    end
    return nil
end

function AchievementsService:_grantReward(player, reward, source)
    local bundle = rewardToBundle(reward)
    if not bundle then
        return false, "Unsupported reward type"
    end

    -- Prefer the unified reward spine: one audited grant terminal that also handles
    -- items/pets/effects/slots, not just currency.
    local rewardService = self:_service("RewardService")
    if rewardService then
        local res = rewardService:Grant(player, bundle, source or "achievement_reward")
        if res and res.ok then
            return true
        end
    end

    -- Fallback: legacy currency-only path if RewardService is unavailable.
    if reward.type == "currency" then
        local amount = tonumber(reward.amount) or 0
        if amount <= 0 then
            return false, "Invalid reward amount"
        end
        if self._economyService and self._economyService.AddCurrency then
            return self._economyService:AddCurrency(
                player,
                reward.currency,
                amount,
                source or "achievement_reward"
            )
        end
        if self._dataService and self._dataService.AddCurrency then
            return self._dataService:AddCurrency(
                player,
                reward.currency,
                amount,
                source or "achievement_reward"
            )
        end
    end

    return false, "No reward grant service available"
end

function AchievementsService:_grantTier(player, achievement, tier, value)
    local data = self._dataService:GetData(player)
    if not data then
        return false
    end

    local state = self:_ensureAchievements(data)
    state.Completed[achievement.id] = state.Completed[achievement.id] or {}
    if state.Completed[achievement.id][tier.id] then
        return false
    end

    local ok, reason =
        self:_grantReward(player, tier.reward, "achievement_" .. achievement.id .. "_" .. tier.id)
    if not ok then
        self._logger:Warn("Failed to grant achievement reward", {
            context = "AchievementsService",
            player = player.Name,
            achievement = achievement.id,
            tier = tier.id,
            reason = reason,
        })
        return false
    end

    state.Completed[achievement.id][tier.id] = {
        completed_at = os.time(),
        stat = achievement.stat,
        goal = tier.goal,
        value = value,
    }

    local payload = {
        achievementId = achievement.id,
        tierId = tier.id,
        stat = achievement.stat,
        goal = tier.goal,
        value = value,
        reward = tier.reward,
        -- display text for the game_events float (Jason heard the jingle with NOTHING
        -- on screen — "what's going on?"): "🏆 Egg Hatchery 10"
        name = "🏆 " .. tostring(achievement.display_name or achievement.id) .. " " .. tostring(
            tier.goal
        ),
    }

    self.Completed:Fire(player, payload)
    Signals.AchievementCompleted:FireClient(player, payload)
    fireGameEvent(player, "achievement_completed", payload) -- config-driven fanfare (game_events)
    self._dataService:RequestSave(player, "achievement_completed", { critical = true })
    return true
end

function AchievementsService:_evaluateAchievement(player, achievement, value)
    local granted = {}
    for _, tier in ipairs(achievement.tiers or {}) do
        if value >= tier.goal and self:_grantTier(player, achievement, tier, value) then
            table.insert(granted, tier.id)
        end
    end
    return granted
end

function AchievementsService:_onCounterChanged(player, counterId, newValue)
    for _, achievement in pairs(self._config.achievements or {}) do
        if achievement.stat == counterId then
            self:_evaluateAchievement(player, achievement, newValue)
        end
    end
end

function AchievementsService:EvaluateAll(player)
    local result = {}
    for achievementId, achievement in pairs(self._config.achievements or {}) do
        local value = self._statsService:Get(player, achievement.stat)
        result[achievementId] = self:_evaluateAchievement(player, achievement, value)
    end
    return result
end

function AchievementsService:GetAchievements(player)
    local data = self._dataService:GetData(player)
    local state = data and self:_ensureAchievements(data) or { Completed = {} }
    local result = {}

    for achievementId, achievement in pairs(self._config.achievements or {}) do
        local value = self._statsService:Get(player, achievement.stat)
        result[achievementId] = {
            id = achievement.id,
            display_name = achievement.display_name,
            stat = achievement.stat,
            value = value,
            tiers = achievement.tiers,
            completed = state.Completed[achievement.id] or {},
        }
    end

    return result
end

return AchievementsService
