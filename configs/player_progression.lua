-- Player progression tuning.
-- Total XP (profile.Stats.Experience) is the single source of truth; the player's
-- LEVEL is derived from it via the `xp` curve below (pure: src/Shared/Game/LevelCurve.lua).
-- This config also defines how that level affects gameplay.

return {
    version = "1.0.0",
    enabled = true,

    -- XP -> level curve. `mode` picks the cost of advancing from level n to n+1:
    --   "linear" (default): per_level * n   (1->2 costs per_level, 2->3 costs 2*per_level, ...)
    --   "flat":             per_level        (every level costs the same)
    -- Total XP to REACH level L is the running sum of the step costs below it.
    xp = {
        mode = "linear",
        per_level = 100,
        max_level = 0, -- 0 = uncapped
    },

    team_power = {
        enabled = true,
        stage = "boosts",
        kind = "team_power",
        start_level = 1,
        percent_per_level = 0.01,
        max_bonus_percent = 1.0,
    },

    level_rewards = {
        equip_slots = {
            pets = {
                enabled = true,
                start_level = 10,
                every_levels = 10,
                slots_per_milestone = 1,
                max_bonus_slots = 3,
            },
        },
    },
}
