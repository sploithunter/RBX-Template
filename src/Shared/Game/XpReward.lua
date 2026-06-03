--[[
    XpReward — pure XP-from-activity math (no Roblox APIs).

    "Everything you do grants XP": mining a node, defeating an enemy, etc. all feed the level bar
    (quests/daily/achievements add bigger chunks via RewardService bundles). Each activity converts
    a reward magnitude (ore value, loot total) into XP through a simple, config-driven rate so every
    number stays a dev knob.

      XpReward.fromValue(value, { per_value = number, min = number }) -> integer XP (>= 0)
]]

local XpReward = {}

function XpReward.fromValue(value, cfg)
    cfg = cfg or {}
    value = tonumber(value) or 0
    if value <= 0 then
        return 0
    end
    local perValue = tonumber(cfg.per_value) or 0
    local minXp = tonumber(cfg.min) or 0
    return math.max(minXp, math.floor(value * perValue))
end

return XpReward
