-- Pet enchant configuration.
--
-- This is the single source of truth for both:
-- 1. how enchants roll: rarity profiles, roll counts, weights, strength ranges;
-- 2. what enchants do: modifier stage/kind/currency/combine/amount mappings.
--
-- Saved pets should store only rolled state such as `{ id = "scholar",
-- strength = 2 }`. Do not put enchant behavior on pet configs or individual pet
-- records. To rebalance or redefine an enchant, edit `effects` below.
--
-- For an effect to be live, some gameplay system must resolve the matching
-- modifier context through ModifierService. Current live contexts include
-- `kind = "breakable_reward"` and `kind = "pet_xp"`. Other example kinds are
-- template contracts for future systems.

return {
    version = "1.0.0",
    enabled = true,

    hatch_rolls = {
        enabled = true,
        require_unlocked_slot = true,
    },

    reroll = {
        enabled = true,
        default_slot = 1,
        cost = {
            currency = "gems",
            amount = 5,
        },
    },

    rarity_profiles = {
        legendary = "legendary",
        mythic = "mythical",
        secret = "secret",
        exclusive = "exclusive",
        huge = "huge",
    },

    effects = {
        home_world = {
            display_name = "Home World",
            description = "Increases breakable rewards while the pet is useful in the current world.",
            modifier = {
                stage = "enchants",
                kind = "breakable_reward",
                combine = "multiply",
                amount_per_strength = 0.02,
            },
        },
        efficiency = {
            display_name = "Efficiency",
            description = "Template effect for faster pet work or attack cadence.",
            modifier = {
                stage = "enchants",
                kind = "pet_efficiency",
                combine = "add",
                amount_per_strength = 0.01,
            },
        },
        tactics = {
            display_name = "Tactics",
            description = "Template effect for pet damage or target efficiency.",
            modifier = {
                stage = "enchants",
                kind = "pet_damage",
                combine = "multiply",
                amount_per_strength = 0.015,
            },
        },
        leadership = {
            display_name = "Leadership",
            description = "Template effect for team-wide pet power bonuses.",
            modifier = {
                stage = "enchants",
                kind = "team_power",
                combine = "multiply",
                amount_per_strength = 0.015,
            },
        },
        luck = {
            display_name = "Luck",
            description = "Template effect for general hatch luck.",
            modifier = {
                stage = "enchants",
                kind = "hatch_luck",
                combine = "add",
                amount_per_strength = 0.01,
            },
        },
        secret_luck = {
            display_name = "Secret Luck",
            description = "Template effect for secret-pet hatch luck.",
            modifier = {
                stage = "enchants",
                kind = "secret_hatch_luck",
                combine = "add",
                amount_per_strength = 0.005,
            },
        },
        crystal_finder = {
            display_name = "Crystal Finder",
            description = "Increases crystal rewards from breakables.",
            modifier = {
                stage = "enchants",
                kind = "breakable_reward",
                currency = "crystals",
                combine = "multiply",
                amount_per_strength = 0.015,
            },
        },
        coin_finder = {
            display_name = "Coin Finder",
            description = "Increases coin rewards from breakables.",
            modifier = {
                stage = "enchants",
                kind = "breakable_reward",
                currency = "coins",
                combine = "multiply",
                amount_per_strength = 0.015,
            },
        },
        scholar = {
            display_name = "Scholar",
            description = "Increases pet XP earned from breakables.",
            modifier = {
                stage = "enchants",
                kind = "pet_xp",
                combine = "multiply",
                amount_per_strength = 0.02,
            },
        },
    },

    roll_profiles = {
        legendary = {
            min_rolls = 1,
            max_rolls = 1,
            initial_roll_chance = 1.0,
            prevent_duplicate_effects = true,
            chances = {
                { effect = "home_world", weight = 10, strength = { low = 1, high = 3, scale = 3 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 5 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 5 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 30 } },
                { effect = "leadership", weight = 1, strength = { low = 1, high = 5, scale = 5 } },
                { effect = "secret_luck", weight = 0.1, strength = { low = 1, high = 10, scale = 30 } },
            },
        },
        mythical = {
            min_rolls = 1,
            max_rolls = 1,
            initial_roll_chance = 0.35,
            prevent_duplicate_effects = true,
            chances = {
                { effect = "crystal_finder", weight = 12, strength = { low = 1, high = 3, scale = 3 } },
                { effect = "coin_finder", weight = 8, strength = { low = 1, high = 3, scale = 3 } },
                { effect = "home_world", weight = 10, strength = { low = 1, high = 3, scale = 3 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 5 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 5 } },
                { effect = "scholar", weight = 2, strength = { low = 1, high = 4, scale = 5 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 20 } },
                { effect = "secret_luck", weight = 0.1, strength = { low = 1, high = 10, scale = 20 } },
            },
        },
        secret = {
            min_rolls = 1,
            max_rolls = 2,
            initial_roll_chance = 0.65,
            prevent_duplicate_effects = true,
            chances = {
                { effect = "crystal_finder", weight = 12, strength = { low = 1, high = 4, scale = 3 } },
                { effect = "coin_finder", weight = 8, strength = { low = 1, high = 4, scale = 3 } },
                { effect = "home_world", weight = 10, strength = { low = 1, high = 3, scale = 3 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 4 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 4 } },
                { effect = "scholar", weight = 2, strength = { low = 1, high = 5, scale = 4 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 6 } },
                { effect = "leadership", weight = 1, strength = { low = 1, high = 5, scale = 4 } },
                { effect = "secret_luck", weight = 0.1, strength = { low = 1, high = 10, scale = 6 } },
            },
        },
        exclusive = {
            min_rolls = 1,
            max_rolls = 2,
            initial_roll_chance = 1.0,
            prevent_duplicate_effects = true,
            chances = {
                { effect = "crystal_finder", weight = 12, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "coin_finder", weight = 8, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "home_world", weight = 10, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 5 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "scholar", weight = 2, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 3 } },
                { effect = "leadership", weight = 1, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "secret_luck", weight = 0.1, strength = { low = 1, high = 10, scale = 4 } },
            },
        },
        huge = {
            min_rolls = 1,
            max_rolls = 3,
            initial_roll_chance = 1.0,
            prevent_duplicate_effects = true,
            chances = {
                { effect = "crystal_finder", weight = 12, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "coin_finder", weight = 8, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "home_world", weight = 10, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 5 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "scholar", weight = 2, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 3 } },
                { effect = "leadership", weight = 1, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "secret_luck", weight = 0.1, strength = { low = 1, high = 10, scale = 4 } },
            },
        },
        colossal = {
            min_rolls = 2,
            max_rolls = 4,
            initial_roll_chance = 1.0,
            prevent_duplicate_effects = true,
            chances = {
                { effect = "crystal_finder", weight = 12, strength = { low = 2, high = 7, scale = 2 } },
                { effect = "coin_finder", weight = 8, strength = { low = 2, high = 7, scale = 2 } },
                { effect = "home_world", weight = 10, strength = { low = 2, high = 7, scale = 2 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 4, scale = 4 } },
                { effect = "tactics", weight = 2, strength = { low = 2, high = 7, scale = 3 } },
                { effect = "scholar", weight = 2, strength = { low = 2, high = 7, scale = 3 } },
                { effect = "luck", weight = 1, strength = { low = 2, high = 12, scale = 3 } },
                { effect = "leadership", weight = 1, strength = { low = 2, high = 7, scale = 3 } },
                { effect = "secret_luck", weight = 0.1, strength = { low = 2, high = 12, scale = 4 } },
            },
        },
    },
}
