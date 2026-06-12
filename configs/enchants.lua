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
-- `breakable_reward`, `pet_xp`, `hatch_luck`, `secret_hatch_luck`,
-- `pet_damage`, `team_power`, and `pet_efficiency`.

return {
    version = "1.0.0",
    enabled = true,

    -- FOREGROUND DISPLAY (Jason, 2026-06-12: enchants were the only buff system with
    -- zero visible presence — "we need a foreground use of it"). Enchant badges use
    -- the SAME visual alphabet as auras/powers (disc symbol = what it does) on the
    -- NEUTRAL (white) disc, with the RING METAL carrying strength 1-5. Cards place
    -- enchants lower-LEFT (per-copy identity) vs auras lower-RIGHT (species role).
    display = {
        -- effect id -> disc symbol (power_icons neutral disc set)
        symbols = {
            coin_finder = "coins_up",
            crystal_finder = "magnet",
            scholar = "xp_up",
            luck = "clover_lucky",
            secret_luck = "clover_huge",
            efficiency = "chevrons_up",
            tactics = "target",
            leadership = "star_sparkle",
            home_world = "portal",
        },
        -- METAL RING per strength (copper -> bronze -> silver -> gold -> onyx).
        -- `asset` = Jason's ring art (drop the rbxassetid in when it lands); until
        -- then the grayscale enhancement ring is tinted with `tint`. Copper/bronze
        -- are deliberately separated by VALUE (light warm vs dark warm) so they
        -- read apart at badge size; onyx carries a faint purple cast so a black
        -- ring never vanishes against dark card chrome.
        -- Jason's metal ring art (assets/ui/enchant_rings, uploaded 2026-06-12);
        -- tint remains as the fallback if an asset ever fails to load.
        ring_tiers = {
            { name = "Copper", tint = { 196, 120, 70 }, asset = "rbxassetid://98395799121019" },
            { name = "Bronze", tint = { 110, 74, 42 }, asset = "rbxassetid://100659029330565" },
            { name = "Silver", tint = { 201, 209, 220 }, asset = "rbxassetid://127566698062573" },
            { name = "Gold", tint = { 240, 196, 60 }, asset = "rbxassetid://94783967669881" },
            { name = "Onyx", tint = { 38, 32, 56 }, asset = "rbxassetid://119998247389513" },
        },
    },

    hatch_rolls = {
        enabled = true,
        require_unlocked_slot = true,
    },

    -- PERMANENT ENCHANTS (Jason, 2026-06-12): huge-and-above are FATED, not crafted —
    -- "once a huge is hatched its first enchant is permanent", and each slot a pet
    -- level-up unlocks auto-rolls on the spot (the level-up IS the reveal, with a
    -- celebration) and locks forever. No Enchanter station access. Secrets and
    -- exclusives stay re-enchantable — that's what makes them the craftable,
    -- highly-tradeable tier. Future top classes (titan/colossal) add their flag here.
    permanent = {
        huge = true, -- the huge TRAIT on the record, not a rarity
        categories = { creator = true }, -- species categories that also lock
    },

    reroll = {
        enabled = true,
        requires_station = true,
        station_grace_seconds = 12,
        default_slot = 1,
        cost = {
            currency = "gems",
            amount = 5,
        },
    },

    stations = {
        basic_enchanter = {
            display_name = "Enchanter",
            touch_part_name = "EnchantTouchPart",
            prompt = {
                enabled = true,
                action_text = "Enchant Pets",
                object_text = "Enchanter",
                key = "E",
                max_distance = 14,
                hold_duration = 0,
            },
            animation = {
                enabled = true,
                script_name = "FloatingCoinScript",
                active_when_near = false,
                lightning = {
                    enabled = true,
                    center_part_name = "EnchantTouchPart",
                    center_offset = Vector3.new(0, 1.5, 0),
                    origin_part_name = "Rune",
                    origin_part_paths = {
                        "RuneStone1.Rune",
                        "RuneStone2.Rune",
                        "RuneStone3.Rune",
                        "RuneStone4.Rune",
                    },
                    origin_limit = 4,
                    strands_per_origin = 5,
                    segments = 40,
                    jitter = 1.0,
                    min_radius = 0,
                    max_radius = 1,
                    thickness = 0.42,
                    min_thickness_multiplier = 0.2,
                    max_thickness_multiplier = 1,
                    frequency = 1,
                    animation_speed = 7,
                    curve_size0 = 10,
                    curve_size1 = 15,
                    flicker = 0.35,
                    neon_lift = 0.2,
                    core_enabled = true,
                    core_thickness_multiplier = 0.32,
                    core_opacity_multiplier = 1,
                    fade_out_seconds = 0.35,
                    duration = 2.8,
                    result_delay_seconds = 2.95,
                    sound_name = "enchant_thunder",
                    sound_id = "rbxassetid://71266985896124",
                    volume = 0.9,
                    playback_speed = 0.85,
                    sound_lifetime_seconds = 16,
                    display_pet = {
                        enabled = true,
                        offset = Vector3.new(0, -2.4, 0),
                        yaw_degrees = 180,
                        scale = 1.15,
                        huge_scale = 1.65,
                        lifetime_seconds = 3.2,
                    },
                    colors = {
                        Color3.fromRGB(80, 255, 255),
                        Color3.fromRGB(120, 145, 255),
                        Color3.fromRGB(255, 95, 240),
                        Color3.fromRGB(255, 245, 120),
                    },
                },
            },
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
                {
                    effect = "secret_luck",
                    weight = 0.1,
                    strength = { low = 1, high = 10, scale = 30 },
                },
            },
        },
        mythical = {
            min_rolls = 1,
            max_rolls = 1,
            initial_roll_chance = 0.35,
            prevent_duplicate_effects = true,
            chances = {
                {
                    effect = "crystal_finder",
                    weight = 12,
                    strength = { low = 1, high = 3, scale = 3 },
                },
                { effect = "coin_finder", weight = 8, strength = { low = 1, high = 3, scale = 3 } },
                { effect = "home_world", weight = 10, strength = { low = 1, high = 3, scale = 3 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 5 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 5 } },
                { effect = "scholar", weight = 2, strength = { low = 1, high = 4, scale = 5 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 20 } },
                {
                    effect = "secret_luck",
                    weight = 0.1,
                    strength = { low = 1, high = 10, scale = 20 },
                },
            },
        },
        secret = {
            min_rolls = 1,
            max_rolls = 2,
            initial_roll_chance = 0.65,
            prevent_duplicate_effects = true,
            chances = {
                {
                    effect = "crystal_finder",
                    weight = 12,
                    strength = { low = 1, high = 4, scale = 3 },
                },
                { effect = "coin_finder", weight = 8, strength = { low = 1, high = 4, scale = 3 } },
                { effect = "home_world", weight = 10, strength = { low = 1, high = 3, scale = 3 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 4 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 4 } },
                { effect = "scholar", weight = 2, strength = { low = 1, high = 5, scale = 4 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 6 } },
                { effect = "leadership", weight = 1, strength = { low = 1, high = 5, scale = 4 } },
                {
                    effect = "secret_luck",
                    weight = 0.1,
                    strength = { low = 1, high = 10, scale = 6 },
                },
            },
        },
        exclusive = {
            min_rolls = 1,
            max_rolls = 2,
            initial_roll_chance = 1.0,
            prevent_duplicate_effects = true,
            chances = {
                {
                    effect = "crystal_finder",
                    weight = 12,
                    strength = { low = 1, high = 5, scale = 2 },
                },
                { effect = "coin_finder", weight = 8, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "home_world", weight = 10, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 5 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "scholar", weight = 2, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 3 } },
                { effect = "leadership", weight = 1, strength = { low = 1, high = 5, scale = 3 } },
                {
                    effect = "secret_luck",
                    weight = 0.1,
                    strength = { low = 1, high = 10, scale = 4 },
                },
            },
        },
        huge = {
            min_rolls = 1,
            max_rolls = 3,
            initial_roll_chance = 1.0,
            prevent_duplicate_effects = true,
            chances = {
                {
                    effect = "crystal_finder",
                    weight = 12,
                    strength = { low = 1, high = 5, scale = 2 },
                },
                { effect = "coin_finder", weight = 8, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "home_world", weight = 10, strength = { low = 1, high = 5, scale = 2 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 3, scale = 5 } },
                { effect = "tactics", weight = 2, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "scholar", weight = 2, strength = { low = 1, high = 5, scale = 3 } },
                { effect = "luck", weight = 1, strength = { low = 1, high = 10, scale = 3 } },
                { effect = "leadership", weight = 1, strength = { low = 1, high = 5, scale = 3 } },
                {
                    effect = "secret_luck",
                    weight = 0.1,
                    strength = { low = 1, high = 10, scale = 4 },
                },
            },
        },
        colossal = {
            min_rolls = 2,
            max_rolls = 4,
            initial_roll_chance = 1.0,
            prevent_duplicate_effects = true,
            chances = {
                {
                    effect = "crystal_finder",
                    weight = 12,
                    strength = { low = 2, high = 7, scale = 2 },
                },
                { effect = "coin_finder", weight = 8, strength = { low = 2, high = 7, scale = 2 } },
                { effect = "home_world", weight = 10, strength = { low = 2, high = 7, scale = 2 } },
                { effect = "efficiency", weight = 5, strength = { low = 1, high = 4, scale = 4 } },
                { effect = "tactics", weight = 2, strength = { low = 2, high = 7, scale = 3 } },
                { effect = "scholar", weight = 2, strength = { low = 2, high = 7, scale = 3 } },
                { effect = "luck", weight = 1, strength = { low = 2, high = 12, scale = 3 } },
                { effect = "leadership", weight = 1, strength = { low = 2, high = 7, scale = 3 } },
                {
                    effect = "secret_luck",
                    weight = 0.1,
                    strength = { low = 2, high = 12, scale = 4 },
                },
            },
        },
    },
}
