--[[
    Leveling / difficulty scaling — Halo & Horns [PROTOTYPE].

    Combat numbers stay in a tight ~100 band; LEVEL DIFFERENCE does the scaling (see
    src/Shared/Game/LevelScale). Pets level up to out-level enemies (tougher without HP
    inflation); enemies show a difficulty colour relative to YOUR level.
]]

return {
    -- XP rewards: EVERYTHING you do grants XP, not just quests. Mining a node and defeating an
    -- enemy both feed the level bar; quests/daily/achievements add bigger chunks via RewardService.
    -- XP = max(min, floor(value * per_value)) where `value` is the activity's reward magnitude
    -- (ore Value for mining, loot total for combat). All knobs — tune to taste.
    -- per_value = XP as a FRACTION of the activity's coin magnitude (so "5% of the coins
    -- you earned"). Lowered 10x from the first pass (mining 0.5->0.05) because leveling was
    -- far too fast. min = 1 guarantees any successful action grants at least 1 XP, so small
    -- shares that floor to 0 still tick the bar (the "integer" floor — intentional). Tune
    -- freely; raise per_value to level faster, or raise player_progression.xp.per_level to
    -- make each level cost more (slows leveling without touching the per-action grant).
    xp_rewards = {
        mining = { per_value = 0.05, min = 1 }, -- ~5% of the ore's coin share (split per contributor)
        combat = { per_value = 0.1, min = 1 }, -- ~10% of the enemy's loot total
    },

    -- DIMINISHING XP vs out-leveled targets (Jason: "nobody should be able to put on an
    -- auto clicker... and wake up 10-20 levels ahead"; "-3 levels should be almost not
    -- worth it"). Applied via LevelDiffYield.xp to mining (crystal MiningLevel) and
    -- combat (enemy Level). At/above your level = full XP; below = -30%/level, floored
    -- at 10% (-3 levels -> 10%). Combined with the exponential xp curve (each level
    -- costs 1.18x more), parked overnight farming crawls to ~a level or two, not 30.
    xp_level_scale = { per_level_down = 0.30, floor = 0.10 },

    -- COIN payout vs level — a tuning SEAM shipped NEUTRAL (exactly x1 at any diff).
    -- Jason: money stays full at any level because coins fund hatching (more eggs =
    -- the actual game); this lever exists in case income inflation ever needs a brake.
    payout_level_scale = { per_level = 0, min = 1, max = 1 },

    -- Damage multiplier per level of (attacker - defender), clamped. +8% dmg per level up.
    scale = { per_level = 0.08, min = 0.3, max = 2.5 },

    -- Elite rank adds to an enemy's effective level vs its base (keyed by enemies.lua tier):
    -- a lieutenant reads one level higher, a boss one above that.
    rank_offset = {
        trash_mob = 0, -- standard
        mid_tier = 1, -- lieutenant
        boss = 2, -- boss
    },

    -- Difficulty label colour by (enemy effective level - your level). Keys = LevelScale.tier.
    -- {r,g,b}; the client builds the Color3.
    tier_colors = {
        purple = { 180, 95, 230 }, -- +3 or more (deadly)
        red = { 225, 70, 70 }, -- +2
        yellow = { 235, 210, 70 }, -- +1
        white = { 245, 245, 245 }, -- even
        blue = { 95, 170, 235 }, -- -1
        green = { 110, 205, 110 }, -- -2
        gray = { 150, 150, 160 }, -- -3 or less (trivial)
    },
}
