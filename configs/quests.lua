--[[
    Quests — Halo & Horns MISSIONS (Jason 2026-06-10): an ORDERED chain that drives the
    player to learn the game early, running IN PARALLEL with the tutorial (two sources
    telling you what to do next). One mission is "up" at a time: `order` ranks them and
    QuestService locks a mission until every lower-order one is CLAIMED.

    This is deliberately NOT the achievements system — achievements (configs/
    achievements.lua) hold the long-lived tiered milestones (hatch 50, break 100…); the
    old placeholder quests duplicated those and are gone.

    Conditions ride the same stat counters the rest of the game increments
    (configs/stats.lua); rewards go through the reward spine (Condition + ClaimLogic +
    RewardService). Claim-once unless `repeatable`.
]]

return {
    defs = {
        first_hatch = {
            order = 1,
            name = "Hatch One Egg",
            description = "Walk to an egg and hatch your first pet.",
            condition = { type = "counter_at_least", counter = "eggs_hatched", value = 1 },
            reward = { currencies = { coins = 100 }, experience = 50 },
        },
        pet_parent = {
            order = 2,
            name = "Equip a Pet",
            description = "Open the Pets menu and click a pet to equip it.",
            condition = { type = "counter_at_least", counter = "pets_equipped", value = 1 },
            reward = { currencies = { coins = 150 }, experience = 50 },
        },
        crystal_breaker = {
            order = 3,
            name = "Break 10 Crystals",
            description = "Let your pets mine — click crystals to boost them.",
            condition = { type = "counter_at_least", counter = "breakables_broken", value = 10 },
            reward = { currencies = { coins = 250 }, experience = 100 },
        },
        egg_collector = {
            order = 4,
            name = "Hatch 10 Eggs",
            description = "Spend your coins on eggs and grow the collection.",
            condition = { type = "counter_at_least", counter = "eggs_hatched", value = 10 },
            reward = { currencies = { coins = 500 }, experience = 150 },
        },
        ascended = {
            order = 5,
            name = "Reach Level 2",
            description = "Fill the XP bar and press ASCEND to claim your level.",
            condition = { type = "level_at_least", value = 2 },
            reward = { currencies = { gems = 3 } },
        },
        empowered = {
            order = 6,
            name = "Cast 5 Powers",
            description = "Use your hotbar powers — number keys or tap.",
            condition = { type = "counter_at_least", counter = "powers_cast", value = 5 },
            reward = { currencies = { coins = 750 }, experience = 200 },
        },
        gear_hunter = {
            order = 7,
            name = "Find an Enhancement",
            description = "Crystals and enemies sometimes drop glowing cogs — grab one!",
            condition = { type = "counter_at_least", counter = "enhancements_found", value = 1 },
            reward = { currencies = { gems = 5 } },
        },
        crystal_crusher = {
            order = 8,
            name = "Break 50 Crystals",
            description = "Keep the mining train rolling.",
            condition = { type = "counter_at_least", counter = "breakables_broken", value = 50 },
            reward = { currencies = { coins = 1500 }, experience = 300 },
        },
    },
}
