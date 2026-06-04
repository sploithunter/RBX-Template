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
        max_level = 50, -- level cap (City-of-Heroes-style top-out); earnedLevel saturates here
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
        -- Pet EQUIP slots from leveling: base 3 (inventory.lua) + up to +7 here = 10 by ~L41.
        -- Granted as the player's CLAIMED level crosses each milestone (so it's altar/claim
        -- gated like the rest of progression). Cap also bounded by inventory.lua max_slots (10).
        equip_slots = {
            pets = {
                enabled = true,
                start_level = 5,
                every_levels = 6, -- grants at 5,11,17,23,29,35,41 -> +7
                slots_per_milestone = 1,
                max_bonus_slots = 7,
            },
        },
    },
}
