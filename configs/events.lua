return {
    tick_seconds = 1,

    workspace = {
        active_folder = "GlobalEvents",
        modifier_folder = "EventModifiers",
        clock_folder = "EventClock",
    },

    modifiers = {
        egg_luck = {
            display_name = "Egg Luck",
            base = 0,
        },
        breakable_reward_multiplier = {
            display_name = "Breakable Reward Multiplier",
            base = 1,
        },
        coin_reward_multiplier = {
            display_name = "Coin Reward Multiplier",
            base = 1,
        },
        crystal_reward_multiplier = {
            display_name = "Crystal Reward Multiplier",
            base = 1,
        },
        secret_luck = {
            display_name = "Secret Luck",
            base = 0,
        },
    },

    global_events = {
        hatch_luck_hour = {
            display_name = "Hatch Luck Hour",
            description = "Improves golden and rainbow hatch odds for everyone.",
            duration_seconds = 3600,
            stacking = "extend_duration",
            icon = "LUCK",
            modifiers = {
                egg_luck = 0.35,
            },
        },

        double_rewards_hour = {
            display_name = "Double Rewards Hour",
            description = "Doubles breakable rewards for everyone.",
            duration_seconds = 3600,
            stacking = "extend_duration",
            icon = "2X",
            modifiers = {
                breakable_reward_multiplier = 1,
            },
        },

        crystal_rush = {
            display_name = "Crystal Rush",
            description = "Boosts crystal rewards from breakables.",
            duration_seconds = 1800,
            stacking = "extend_duration",
            icon = "CRYS",
            modifiers = {
                crystal_reward_multiplier = 0.5,
            },
        },

        coin_shower = {
            display_name = "Coin Shower",
            description = "Boosts coin rewards from breakables.",
            duration_seconds = 1800,
            stacking = "extend_duration",
            icon = "COIN",
            modifiers = {
                coin_reward_multiplier = 0.5,
            },
        },

        lucky_day = {
            display_name = "Lucky Day",
            description = "Scheduled daily hatch luck boost.",
            duration_seconds = -1,
            stacking = "reset",
            icon = "DAY",
            modifiers = {
                egg_luck = 0.1,
            },
        },

        secret_luck_day = {
            display_name = "Secret Luck Day",
            description = "Scheduled daily secret luck boost.",
            duration_seconds = -1,
            stacking = "reset",
            icon = "SECRET",
            modifiers = {
                secret_luck = 0.05,
            },
        },
    },

    scheduled_global_events = {
        lucky_day_tuesday_thursday = {
            event_id = "lucky_day",
            weekdays_utc = { 3, 5 },
            reason = "Scheduled lucky day",
        },

        secret_luck_friday = {
            event_id = "secret_luck_day",
            weekdays_utc = { 6 },
            reason = "Scheduled secret luck day",
        },
    },
}
