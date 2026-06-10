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
        -- Jason 2026-06-10: the tutorial already walks hatch-1/equip/first-coins, so the
        -- chain STARTS where the tutorial hands off. "Mine 8,000 Coins" lines up with the
        -- XP needed for level 2. Rewards are GEMS to start (config — tune freely).
        egg_collector = {
            order = 1,
            name = "Hatch 10 Eggs",
            description = "Spend your coins on eggs and grow the collection.",
            condition = { type = "counter_at_least", counter = "eggs_hatched", value = 10 },
            reward = { currencies = { gems = 3 } },
        },
        egg_hoarder = {
            order = 2,
            name = "Hatch 100 Eggs",
            description = "Keep hatching — duplicates make your team stronger.",
            condition = { type = "counter_at_least", counter = "eggs_hatched", value = 100 },
            reward = { currencies = { gems = 10 } },
        },
        coin_miner = {
            order = 3,
            name = "Mine 8,000 Coins",
            description = "Mining earns XP too — this pace lands you at Level 2.",
            condition = {
                type = "counter_at_least",
                counter = "coins_earned_lifetime",
                value = 8000,
            },
            reward = { currencies = { gems = 15 } },
        },
        empowered = {
            order = 4,
            name = "Cast 5 Powers",
            description = "Use your hotbar powers — number keys or tap.",
            condition = { type = "counter_at_least", counter = "powers_cast", value = 5 },
            reward = { currencies = { gems = 5 } },
        },
        gear_hunter = {
            order = 5,
            name = "Find an Enhancement",
            description = "Crystals and enemies sometimes drop glowing cogs — grab one!",
            condition = { type = "counter_at_least", counter = "enhancements_found", value = 1 },
            reward = { currencies = { gems = 5 } },
        },
        crystal_crusher = {
            order = 6,
            name = "Break 50 Crystals",
            description = "Keep the mining train rolling.",
            condition = { type = "counter_at_least", counter = "breakables_broken", value = 50 },
            reward = { currencies = { gems = 8 } },
        },
    },
}
