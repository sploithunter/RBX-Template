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
    -- THE CHAIN (Jason): everyone runs this one ordered line first — "Origin Story."
    -- Hierarchical branches hang off it later (per-origin chapters after the L5
    -- choice); QuestService today runs one chain, so this metadata names it for the
    -- panel/tracker and future branching keys off chain ids.
    chain = { id = "origin_story", title = "Origin Story" },

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
        -- ===== Origin Story, extended (Jason: "it should go a little bit longer") —
        -- walks every system: slotting, the L5 origin choice, combat, and the long
        -- hatching/mining ramps that carry the player into the midgame. =====
        gear_smith = {
            order = 7,
            name = "Slot an Enhancement",
            description = "Open a power in the Powers menu and slot a cog into it.",
            condition = { type = "counter_at_least", counter = "enhancements_slotted", value = 1 },
            reward = { currencies = { gems = 8 } },
        },
        chosen_one = {
            order = 8,
            name = "Reach Level 5 — Choose Your Origin",
            description = "Claim levels at the Ascend altar. Level 5 unlocks your Origin!",
            condition = { type = "counter_at_least", counter = "levels_gained", value = 4 },
            reward = { currencies = { gems = 20 } },
        },
        first_blood = {
            order = 9,
            name = "Defeat 10 Enemies",
            description = "Your squad fights back — let your tank pull and pile on.",
            condition = { type = "counter_at_least", counter = "enemies_defeated", value = 10 },
            reward = { currencies = { gems = 10 } },
        },
        egg_baron = {
            order = 10,
            name = "Hatch 500 Eggs",
            description = "The collection grows. Luck powers make every egg count.",
            condition = { type = "counter_at_least", counter = "eggs_hatched", value = 500 },
            reward = { currencies = { gems = 25 } },
        },
        deep_miner = {
            order = 11,
            name = "Mine 50,000 Coins",
            description = "Big crystals pay big. Yield buffs stack with everything.",
            condition = {
                type = "counter_at_least",
                counter = "coins_earned_lifetime",
                value = 50000,
            },
            reward = { currencies = { gems = 30 } },
        },
        gear_collector = {
            order = 12,
            name = "Find 10 Enhancements",
            description = "Singles only drop in their home world. Duals are everywhere.",
            condition = { type = "counter_at_least", counter = "enhancements_found", value = 10 },
            reward = { currencies = { gems = 25 } },
        },
        egg_legend = {
            order = 13,
            name = "Hatch 1,000 Eggs",
            description = "The Origin Story capstone. Legends are hatched, not born.",
            condition = { type = "counter_at_least", counter = "eggs_hatched", value = 1000 },
            reward = { currencies = { gems = 100 } },
        },
    },
}
