-- Player progression tuning.
-- Player level is durable profile state; this config defines how that level
-- affects gameplay without putting special math inside feature services.

return {
    version = "1.0.0",
    enabled = true,

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
