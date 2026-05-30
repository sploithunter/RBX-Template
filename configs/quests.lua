--[[
    Quests — Halo & Horns [PROTOTYPE] (Phase 7).

    Each quest gates a reward bundle behind a pure Condition (over stat counters /
    level / currency). Claim-once unless `repeatable`. Powered by QuestService +
    the reward spine (Condition + ClaimLogic + RewardService). The "Quest" badge =
    count of met-but-unclaimed quests.
]]

return {
    defs = {
        crystal_crusher = {
            name = "Crystal Crusher",
            description = "Break 50 crystals.",
            condition = { type = "counter_at_least", counter = "breakables_broken", value = 50 },
            reward = { currencies = { lava_coins = 500 } },
        },
        egg_enthusiast = {
            name = "Egg Enthusiast",
            description = "Hatch 10 eggs.",
            condition = { type = "counter_at_least", counter = "eggs_hatched", value = 10 },
            reward = {
                currencies = { coins = 1000 },
                items = { { id = "health_potion", qty = 3 } },
            },
        },
        seasoned = {
            name = "Seasoned Soul",
            description = "Reach level 10.",
            condition = { type = "level_at_least", value = 10 },
            reward = { currencies = { gems = 5 } },
        },
        daily_grind = {
            name = "Daily Grind",
            description = "Tap 100 times (repeatable).",
            condition = { type = "counter_at_least", counter = "taps", value = 100 },
            reward = { currencies = { coins = 250 } },
            repeatable = true,
        },
    },
}
