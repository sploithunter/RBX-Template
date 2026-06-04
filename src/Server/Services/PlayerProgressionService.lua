--[[
    PlayerProgressionService

    Config-driven player-level effects. This owns level-derived modifier
    contributions and level rewards such as extra equipped pet slots.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LevelCurve = require(ReplicatedStorage.Shared.Game.LevelCurve)

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
    self._xpConfig = self._config.xp or { mode = "linear", per_level = 100 }

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

-- Publish derived level/XP to player attributes so the client HUD can read them
-- without a bespoke remote (Level, XP = xp into current level, XPForNext).
function PlayerProgressionService:Start()
    local function publishLater(player)
        task.spawn(function()
            local deadline = os.clock() + 15
            while
                player.Parent
                and self._dataService
                and self._dataService.IsDataLoaded
                and not self._dataService:IsDataLoaded(player)
                and os.clock() < deadline
            do
                task.wait(0.2)
            end
            if player.Parent then
                self:_publish(player)
            end
        end)
    end
    Players.PlayerAdded:Connect(publishLater)
    for _, player in ipairs(Players:GetPlayers()) do
        publishLater(player)
    end
end

function PlayerProgressionService:GetExperience(player)
    if not player or not self._dataService or not self._dataService.GetStat then
        return 0
    end
    return math.max(0, math.floor(tonumber(self._dataService:GetStat(player, "Experience")) or 0))
end

-- EARNED level — derived from total XP (single source of truth), saturated at the cap.
-- Drives combat/egg "how strong is this player" scaling via the `Level` ATTRIBUTE and the
-- claim gate. NOT the reward-eligibility level (that's claimed — see GetLevel below).
function PlayerProgressionService:GetEarnedLevel(player)
    if not player then
        return 1
    end
    return LevelCurve.levelForXp(self:GetExperience(player), self._xpConfig)
end

-- CLAIMED level — what the player has actually claimed via the level-up sequence (stored
-- stat, default 1, never above earned or the cap). This is the REWARD/ELIGIBILITY level:
-- powers, augment slots, equip-slot milestones and the team-power boost all gate on it
-- (they route through GetLevel), so you don't get a level's benefits until you claim it.
function PlayerProgressionService:GetClaimedLevel(player)
    if not player then
        return 1
    end
    local stored = 1
    if self._dataService and self._dataService.GetStat then
        stored = math.floor(tonumber(self._dataService:GetStat(player, "ClaimedLevel")) or 1)
    end
    local earned = self:GetEarnedLevel(player)
    return math.clamp(math.max(1, stored), 1, math.max(1, earned))
end

-- Reward/eligibility gates read GetLevel -> claimedLevel (the choke-point used by
-- PowerService/AugmentationService/QuestService/InventoryService/team-power, so they become
-- claim-gated with no edits). Combat/egg scaling reads the `Level` attribute = earnedLevel.
function PlayerProgressionService:GetLevel(player)
    return self:GetClaimedLevel(player)
end

function PlayerProgressionService:GetPendingLevels(player)
    return math.max(0, self:GetEarnedLevel(player) - self:GetClaimedLevel(player))
end

-- Progress object at the EARNED level (used by AddExperience/SetLevel return values).
function PlayerProgressionService:GetProgress(player)
    return LevelCurve.progress(self:GetExperience(player), self._xpConfig)
end

-- XP-bar progress relative to the CLAIMED level's window: fills toward the next unclaimed
-- level, so a full bar means "a level-up is waiting to be claimed". Saturates at the cap.
function PlayerProgressionService:_claimedProgress(player, claimed)
    local maxLevel = math.floor(tonumber(self._xpConfig.max_level) or 0)
    if maxLevel > 0 and claimed >= maxLevel then
        return { xpIntoLevel = 0, xpForNext = 0 } -- MAX
    end
    local xp = self:GetExperience(player)
    local base = LevelCurve.xpForLevel(claimed, self._xpConfig)
    local step = LevelCurve.stepCost(claimed, self._xpConfig)
    local into = math.clamp(xp - base, 0, step)
    return { xpIntoLevel = into, xpForNext = step }
end

-- Mirror earned/claimed level + XP onto player attributes for the HUD.
--   Level        = earnedLevel (combat/egg scaling — unchanged from before)
--   ClaimedLevel = the HUD badge / claim gate
--   PendingLevels= earned - claimed (drives the "LEVEL UP!" button), clamped to remaining
--   XP/XPForNext = progress within the next UNCLAIMED level
function PlayerProgressionService:_publish(player)
    if not player then
        return
    end
    local earned = self:GetEarnedLevel(player)
    local claimed = self:GetClaimedLevel(player)
    local maxLevel = math.floor(tonumber(self._xpConfig.max_level) or 0)
    local remaining = maxLevel > 0 and math.max(0, maxLevel - claimed) or math.huge
    local pending = math.min(math.max(0, earned - claimed), remaining)
    local prog = self:_claimedProgress(player, claimed)
    player:SetAttribute("Level", earned)
    player:SetAttribute("ClaimedLevel", claimed)
    player:SetAttribute("PendingLevels", pending)
    player:SetAttribute("XP", prog.xpIntoLevel)
    player:SetAttribute("XPForNext", prog.xpForNext)
end

-- Grant XP (the spine awards XP via RewardService -> here). Returns the new progress.
function PlayerProgressionService:AddExperience(player, amount)
    amount = math.floor(tonumber(amount) or 0)
    if not player or amount <= 0 or not self._dataService then
        return self:GetProgress(player)
    end
    local newXp = self:GetExperience(player) + amount
    self._dataService:SetStat(player, "Experience", newXp)
    self:_publish(player)
    return self:GetProgress(player)
end

-- Set the player to exactly `level` by writing the curve's threshold XP (used by the
-- test override + any admin grant). Level stays a pure function of XP.
function PlayerProgressionService:SetLevel(player, level)
    if not player or not self._dataService then
        return self:GetProgress(player)
    end
    local target = math.max(1, math.floor(tonumber(level) or 1))
    local xp = LevelCurve.xpForLevel(target, self._xpConfig)
    self._dataService:SetStat(player, "Experience", xp)
    -- Admin/reset set-level gives a fully-CLAIMED level (not one owing claims), so the player
    -- immediately has that level's powers/slots/boosts and no pending level-ups.
    self._dataService:SetStat(player, "ClaimedLevel", target)
    self:_publish(player)
    return self:GetProgress(player)
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
