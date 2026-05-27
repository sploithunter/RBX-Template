-- Pet progression tuning for unique pets.
-- Stack pets stay compact and do not carry XP/level state until promoted to unique.

return {
    version = "1.0.0",
    enabled = true,

    unique_only = true,
    default_max_level = 1,

    max_level_by_rarity = {
        mythic = 25,
        secret = 50,
        exclusive = 75,
        huge = 100,
    },

    xp_curve = {
        type = "exponential",
        base = 100,
        growth = 1.18,
    },

    power_scaling = {
        type = "percent_per_level",
        percent_per_level = 0.02,
        max_bonus_percent = 1.0,
    },

    enchant_slots = {
        default_unlocked_slots = 1,
        unlocks_by_rarity = {
            mythic = {
                { level = 1, slots = 1 },
            },
            secret = {
                { level = 1, slots = 1 },
                { level = 25, slots = 2 },
            },
            exclusive = {
                { level = 1, slots = 1 },
                { level = 25, slots = 2 },
            },
            huge = {
                { level = 1, slots = 1 },
                { level = 25, slots = 2 },
                { level = 75, slots = 3 },
            },
        },
    },

    xp_sources = {
        breakable_damage = {
            enabled = false,
            xp_per_damage = 0,
        },
        breakable_destroy = {
            enabled = false,
            xp_by_area = {},
            default_xp = 0,
        },
    },
}
