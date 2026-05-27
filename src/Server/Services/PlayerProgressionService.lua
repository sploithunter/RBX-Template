--[[
    PlayerProgressionService

    Config-driven player-level effects. This owns level-derived modifier
    contributions and level rewards such as extra equipped pet slots.
]]

local PlayerProgressionService = {}
PlayerProgressionService.__index = PlayerProgressionService

function PlayerProgressionService.new()
    local self = setmetatable({}, PlayerProgressionService)
    self._logger = nil
    self._configLoader = nil
    self._dataService = nil
    self._modifierService = nil
    self._config = nil
    return self
end

function PlayerProgressionService:Init()
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    self._dataService = self._modules.DataService
    self._modifierService = self._modules.ModifierService
    self._config = self._configLoader:LoadConfig("player_progression")

    local teamPower = self._config.team_power or {}
    local stage = teamPower.stage or "boosts"
    if self:IsEnabled() and teamPower.enabled ~= false and self._modifierService then
        self._modifierService:RegisterProvider(stage, function(context)
            return self:_getTeamPowerContribution(context)
        end)
    end

    self._logger:Info("PlayerProgressionService initialized", {
        context = "PlayerProgressionService",
        enabled = self:IsEnabled(),
        teamPowerStage = stage,
    })
end

function PlayerProgressionService:IsEnabled()
    return self._config and self._config.enabled ~= false
end

function PlayerProgressionService:GetLevel(player)
    if not player then
        return 1
    end

    local profileLevel
    if self._dataService and self._dataService.GetStat then
        profileLevel = self._dataService:GetStat(player, "Level")
    end
    local attributeLevel = player:GetAttribute("Level")
    return math.max(1, math.floor(tonumber(profileLevel or attributeLevel) or 1))
end

function PlayerProgressionService:_getMilestoneCount(level, rewardConfig)
    if type(rewardConfig) ~= "table" or rewardConfig.enabled == false then
        return 0
    end

    level = math.max(1, math.floor(tonumber(level) or 1))
    local startLevel = math.max(1, math.floor(tonumber(rewardConfig.start_level) or 1))
    local everyLevels = math.max(1, math.floor(tonumber(rewardConfig.every_levels) or 1))
    if level < startLevel then
        return 0
    end

    return math.floor((level - startLevel) / everyLevels) + 1
end

function PlayerProgressionService:GetEquippedPetSlotBonus(player)
    if not self:IsEnabled() then
        return 0
    end

    local rewards = self._config.level_rewards or {}
    local equipSlots = rewards.equip_slots or {}
    local petSlots = equipSlots.pets or {}
    local milestones = self:_getMilestoneCount(self:GetLevel(player), petSlots)
    local perMilestone = math.max(0, math.floor(tonumber(petSlots.slots_per_milestone) or 0))
    local maxBonus = math.max(0, math.floor(tonumber(petSlots.max_bonus_slots) or 0))
    local bonus = milestones * perMilestone
    if maxBonus > 0 then
        bonus = math.min(bonus, maxBonus)
    end
    return math.max(0, bonus)
end

function PlayerProgressionService:_getTeamPowerContribution(context)
    if type(context) ~= "table" or context.kind ~= "team_power" or not context.player then
        return {}
    end

    local teamPower = self._config.team_power or {}
    if teamPower.enabled == false then
        return {}
    end

    local level = self:GetLevel(context.player)
    local startLevel = math.max(1, math.floor(tonumber(teamPower.start_level) or 1))
    local effectiveLevels = math.max(0, level - startLevel)
    local perLevel = tonumber(teamPower.percent_per_level) or 0
    local maxBonus = tonumber(teamPower.max_bonus_percent) or 0
    local bonus = math.max(0, effectiveLevels * perLevel)
    if maxBonus > 0 then
        bonus = math.min(bonus, maxBonus)
    end
    if bonus <= 0 then
        return {}
    end

    return {
        {
            id = "player_level_team_power",
            label = "Player Level",
            combine = "multiply",
            amount = 1 + bonus,
        },
    }
end

return PlayerProgressionService
