--[[
    Quests — Halo & Horns MISSIONS.

    PARALLEL THEMED TRACKS (Jason 2026-06-21: "expand it quite extensively" — a L14 character
    had no new quest since ~L8). The old design was ONE strictly-linear chain: a single quest
    active at a time, the next locked until the current was CLAIMED. After the early steps that
    left the player on one big grind for many levels, so the system felt empty.

    Now quests are grouped into independent TRACKS (Hatchery / Mining / Warpath / Collector /
    Ascension / Trailblazer). Each track is its own ordered chain, but tracks run IN PARALLEL —
    so several quests are active at once (one head per track) and leveling/playing always has
    something in progress. QuestService gates per-track via Shared/Game/QuestChain.

    This stays distinct from achievements (configs/achievements.lua = long-lived tiered totals);
    quests are the guided "do this next" missions and reach into the endgame (L30+, rebirths,
    1M coins, 25k eggs).

    Conditions ride the same stat counters the rest of the game increments (configs/stats.lua);
    rewards go through the reward spine (Condition + ClaimLogic + RewardService). Claim-once
    unless `repeatable`.

    since_start = true: the mission measures FORWARD progress from the moment it becomes its
    track's active head (QuestService stamps a per-mission baseline). Milestones that read a
    TOTAL (reach Level N, unlock N areas, own N distinct pets, rebirth N times) stay ABSOLUTE —
    no since_start — so an existing high-level character can immediately claim the ones it has
    already passed (catch-up), then keep the deeper since_start grinds as long-term goals.

    NOTE: existing quest ids are preserved (live characters' QuestClaims/QuestBaselines key off
    them) — they were only assigned a track + intra-track order; new ids extend each track.
]]

return {
    -- Track metadata: id -> { title, order } (order = display priority of the track).
    -- QuestService surfaces trackTitle to the panel; gating is per-track.
    tracks = {
        hatchery = { title = "The Hatchery", order = 1 },
        mining = { title = "Deep Mining", order = 2 },
        warpath = { title = "The Warpath", order = 3 },
        collector = { title = "The Collector", order = 4 },
        ascension = { title = "Ascension", order = 5 },
        crossing = { title = "The Crossing", order = 6 },
        trailblazer = { title = "Trailblazer", order = 7 },
    },

    defs = {
        -- ===================== HATCHERY (eggs + the collection) =====================
        egg_collector = {
            track = "hatchery",
            order = 1,
            name = "Hatch 10 Eggs",
            description = "Spend your crystals on eggs and grow the collection.",
            condition = {
                type = "counter_at_least",
                counter = "eggs_hatched",
                value = 10,
                since_start = true,
            },
            reward = { currencies = { gems = 3 } },
        },
        egg_hoarder = {
            track = "hatchery",
            order = 2,
            name = "Hatch 100 Eggs",
            description = "Keep hatching — duplicates make your team stronger.",
            condition = {
                type = "counter_at_least",
                counter = "eggs_hatched",
                value = 100,
                since_start = true,
            },
            reward = { currencies = { gems = 10 } },
        },
        egg_baron = {
            track = "hatchery",
            order = 3,
            name = "Hatch 500 Eggs",
            description = "The collection grows. Luck powers make every egg count.",
            condition = {
                type = "counter_at_least",
                counter = "eggs_hatched",
                value = 500,
                since_start = true,
            },
            reward = { currencies = { gems = 25 } },
        },
        egg_legend = {
            track = "hatchery",
            order = 4,
            name = "Hatch 1,000 Eggs",
            description = "Legends are hatched, not born.",
            condition = {
                type = "counter_at_least",
                counter = "eggs_hatched",
                value = 1000,
                since_start = true,
            },
            reward = { currencies = { gems = 100 } },
        },
        egg_emperor = {
            track = "hatchery",
            order = 5,
            name = "Hatch 5,000 Eggs",
            description = "An industrial-scale hatchery. The rares are inevitable now.",
            condition = {
                type = "counter_at_least",
                counter = "eggs_hatched",
                value = 5000,
                since_start = true,
            },
            reward = { currencies = { gems = 200, area_coins = 10000 } },
        },
        egg_titan = {
            track = "hatchery",
            order = 6,
            name = "Hatch 10,000 Eggs",
            description = "Five figures of eggs. The dynasty is well underway.",
            condition = {
                type = "counter_at_least",
                counter = "eggs_hatched",
                value = 10000,
                since_start = true,
            },
            reward = { currencies = { gems = 300, area_coins = 25000 } },
        },
        egg_eternal = {
            track = "hatchery",
            order = 7,
            name = "Hatch 25,000 Eggs",
            description = "The Hatchery capstone — a true egg dynasty.",
            condition = {
                type = "counter_at_least",
                counter = "eggs_hatched",
                value = 25000,
                since_start = true,
            },
            reward = {
                currencies = { gems = 500 },
                pets = { { id = "bear", variant = "rainbow" } },
            },
        },

        -- ===================== MINING (crystals + coins) =====================
        -- crystal_crusher is the track HEAD (always unlocked) and ABSOLUTE — the studio
        -- AutomationSuite drives this quest directly on a fresh player.
        crystal_crusher = {
            track = "mining",
            order = 1,
            name = "Break 50 Crystals",
            description = "Start the mining train — smash crystal nodes for crystals and XP.",
            condition = { type = "counter_at_least", counter = "breakables_broken", value = 50 },
            reward = { currencies = { gems = 8 } },
        },
        coin_miner = {
            track = "mining",
            order = 2,
            name = "Mine 8,000 Crystals",
            description = "Mining earns XP too — this pace lands you at Level 2.",
            condition = {
                type = "counter_at_least",
                counter = "coins_earned_lifetime",
                value = 8000,
                since_start = true,
            },
            reward = { currencies = { gems = 15 } },
        },
        crystal_harvester = {
            track = "mining",
            order = 3,
            name = "Break 2,500 Crystals",
            description = "Bigger crystals pay bigger. Yield buffs stack with everything.",
            condition = {
                type = "counter_at_least",
                counter = "breakables_broken",
                value = 2500,
                since_start = true,
            },
            reward = { currencies = { area_coins = 50000 } },
        },
        deep_miner = {
            track = "mining",
            order = 4,
            name = "Mine 50,000 Crystals",
            description = "Deeper veins, deeper pockets.",
            condition = {
                type = "counter_at_least",
                counter = "coins_earned_lifetime",
                value = 50000,
                since_start = true,
            },
            reward = { currencies = { gems = 30 } },
        },
        crystal_magnate = {
            track = "mining",
            order = 5,
            -- Tracks coins_earned_lifetime: the BIOME-coin total (grass/lava/ice/desert all roll up)
            -- that mining actually pays — the abundant currency, NOT the dead `crystals` currency
            -- (capped at 50k, not in the HUD). Jason: the mined biome currency IS "crystals".
            name = "Earn 500,000 Crystals",
            description = "Bank half a million crystals from your mining hauls.",
            condition = {
                type = "counter_at_least",
                counter = "coins_earned_lifetime",
                value = 500000,
                since_start = true,
            },
            reward = { currencies = { gems = 150 } },
        },
        coin_tycoon = {
            track = "mining",
            order = 6,
            name = "Mine 1,000,000 Crystals",
            description = "The Mining capstone — a seven-figure fortune.",
            condition = {
                type = "counter_at_least",
                counter = "coins_earned_lifetime",
                value = 1000000,
                since_start = true,
            },
            reward = {
                currencies = { gems = 300 },
                pets = { { id = "bear", variant = "rainbow" } },
            },
        },

        -- ===================== WARPATH (combat) =====================
        empowered = {
            track = "warpath",
            order = 1,
            name = "Cast 5 Powers",
            description = "Use your hotbar powers — number keys or tap.",
            condition = {
                type = "counter_at_least",
                counter = "powers_cast",
                value = 5,
                since_start = true,
            },
            reward = { currencies = { gems = 5 } },
        },
        -- BRIDGE before the combat grinds: enemies only invade at Level 5 (they don't attack earlier),
        -- so "Defeat 10 Enemies" as the next head was an unbeatable wall right after the tutorial
        -- (Jason). This head holds the slot and tells the player WHY — combat unlocks at 5 — until they
        -- get there; only then does first_blood become the active head.
        to_battle = {
            track = "warpath",
            order = 2,
            name = "Reach Level 5 — To Battle!",
            description = "Enemies invade at Level 5. Keep leveling, then defend your realm.",
            condition = { type = "level_at_least", value = 5 },
            reward = { currencies = { gems = 5 } },
        },
        first_blood = {
            track = "warpath",
            order = 3,
            name = "Defeat 10 Enemies",
            description = "Your squad fights back — let your tank pull and pile on.",
            condition = {
                type = "counter_at_least",
                counter = "enemies_defeated",
                value = 10,
                since_start = true,
            },
            reward = { currencies = { gems = 10 } },
        },
        centurion = {
            track = "warpath",
            order = 4,
            name = "Defeat 100 Enemies",
            description = "Hold the line — a hundred invaders sent back.",
            condition = {
                type = "counter_at_least",
                counter = "enemies_defeated",
                value = 100,
                since_start = true,
            },
            reward = { currencies = { gems = 25 } },
        },
        power_adept = {
            track = "warpath",
            order = 5,
            name = "Cast 100 Powers",
            description = "Powers win fights — keep them on cooldown.",
            condition = {
                type = "counter_at_least",
                counter = "powers_cast",
                value = 100,
                since_start = true,
            },
            reward = { currencies = { gems = 25 }, items = { { id = "health_potion", qty = 3 } } },
        },
        monster_hunter = {
            track = "warpath",
            order = 6,
            name = "Defeat 250 Enemies",
            description = "Clear the patrols. The opposing realm keeps sending more.",
            condition = {
                type = "counter_at_least",
                counter = "enemies_defeated",
                value = 250,
                since_start = true,
            },
            reward = { currencies = { gems = 50 } },
        },
        slayer = {
            track = "warpath",
            order = 7,
            name = "Defeat 2,500 Enemies",
            description = "A reputation built on fallen invaders.",
            condition = {
                type = "counter_at_least",
                counter = "enemies_defeated",
                value = 2500,
                since_start = true,
            },
            reward = { currencies = { gems = 120 } },
        },
        warlord = {
            track = "warpath",
            order = 8,
            name = "Defeat 10,000 Enemies",
            description = "The Warpath capstone — few survive the crossing.",
            condition = {
                type = "counter_at_least",
                counter = "enemies_defeated",
                value = 10000,
                since_start = true,
            },
            reward = {
                currencies = { gems = 300 },
                pets = { { id = "bear", variant = "rainbow" } },
            },
        },

        -- ===================== COLLECTOR (gear + distinct pets) =====================
        gear_hunter = {
            track = "collector",
            order = 1,
            name = "Find an Enhancement",
            description = "Crystals and enemies sometimes drop glowing cogs — grab one!",
            condition = {
                type = "counter_at_least",
                counter = "enhancements_found",
                value = 1,
                since_start = true,
            },
            reward = { currencies = { gems = 5 } },
        },
        gear_smith = {
            track = "collector",
            order = 2,
            name = "Slot an Enhancement",
            description = "Open a power in the Powers menu and slot a cog into it.",
            condition = {
                type = "counter_at_least",
                counter = "enhancements_slotted",
                value = 1,
                since_start = true,
            },
            reward = { currencies = { gems = 8 }, items = { { id = "health_potion", qty = 2 } } },
        },
        gear_collector = {
            track = "collector",
            order = 3,
            name = "Find 10 Enhancements",
            description = "Singles only drop in their home world. Duals are everywhere.",
            condition = {
                type = "counter_at_least",
                counter = "enhancements_found",
                value = 10,
                since_start = true,
            },
            reward = { currencies = { gems = 25 } },
        },
        menagerie = {
            track = "collector",
            order = 4,
            name = "Own 25 Distinct Pets",
            description = "Variety is power — collect 25 different species.",
            condition = { type = "counter_at_least", counter = "distinct_pets", value = 25 },
            reward = { currencies = { area_coins = 25000 } },
        },
        gear_master = {
            track = "collector",
            order = 5,
            name = "Find 50 Enhancements",
            description = "A full toolbox of cogs to tune every power.",
            condition = {
                type = "counter_at_least",
                counter = "enhancements_found",
                value = 50,
                since_start = true,
            },
            reward = { currencies = { gems = 80 } },
        },
        pet_archivist = {
            track = "collector",
            order = 6,
            name = "Own 75 Distinct Pets",
            description = "The Collector capstone — a living encyclopedia.",
            condition = { type = "counter_at_least", counter = "distinct_pets", value = 75 },
            reward = {
                currencies = { gems = 200 },
                pets = { { id = "bear", variant = "rainbow" } },
            },
        },

        -- ===================== ASCENSION (level + the origin choice) =====================
        chosen_one = {
            track = "ascension",
            order = 1,
            name = "Reach Level 5 — Choose Your Origin",
            description = "Claim levels at the Ascend altar. Level 5 unlocks your Origin!",
            condition = { type = "counter_at_least", counter = "levels_gained", value = 4 },
            reward = { currencies = { gems = 20 } },
        },
        ascendant_10 = {
            track = "ascension",
            order = 2,
            name = "Reach Level 10",
            description = "Keep claiming levels — power and reach scale with you.",
            condition = { type = "level_at_least", value = 10 },
            reward = { currencies = { gems = 30 } },
        },
        ascendant_15 = {
            track = "ascension",
            order = 3,
            name = "Reach Level 15",
            description = "The midgame opens up. Push your squad's level.",
            condition = { type = "level_at_least", value = 15 },
            reward = { currencies = { gems = 50 } },
        },
        ascendant_20 = {
            track = "ascension",
            order = 4,
            name = "Reach Level 20",
            description = "Veteran territory — the deeper realms await.",
            condition = { type = "level_at_least", value = 20 },
            reward = { currencies = { gems = 75 } },
        },
        ascendant_25 = {
            track = "ascension",
            order = 5,
            name = "Reach Level 25",
            description = "Few climb this high. The endgame is in sight.",
            condition = { type = "level_at_least", value = 25 },
            reward = { currencies = { gems = 100 } },
        },
        ascendant_30 = {
            track = "ascension",
            order = 6,
            name = "Reach Level 30",
            description = "The Ascension capstone — a true paragon.",
            condition = { type = "level_at_least", value = 30 },
            reward = {
                currencies = { gems = 200 },
                pets = { { id = "bear", variant = "rainbow" } },
            },
        },

        -- ===================== THE CROSSING (heaven / hell journey) =====================
        -- Visits fire on realm ENTRY (ZoneTrackerService); unlocks fire when a Heaven_*/Hell_*
        -- zone is purchased (ZoneService) — both via the event-counter bridge. (No secret-pet
        -- quest here on purpose, Jason: secret pets are too rare to gate progress on — a blocker.)
        go_heaven = {
            track = "crossing",
            order = 1,
            name = "Journey to Heaven",
            description = "Climb past the Desert gate and set foot in a Heaven realm.",
            condition = { type = "counter_at_least", counter = "heaven_visits", value = 1 },
            reward = { currencies = { gems = 20 } },
        },
        go_hell = {
            track = "crossing",
            order = 2,
            name = "Descend into Hell",
            description = "Brave the depths below — reach a Hell realm.",
            condition = { type = "counter_at_least", counter = "hell_visits", value = 1 },
            reward = { currencies = { gems = 20 } },
        },
        heaven_settler = {
            track = "crossing",
            order = 3,
            name = "Unlock an Area in Heaven",
            description = "Claim a stake in the heavens — unlock any Heaven zone.",
            condition = { type = "counter_at_least", counter = "heaven_areas_unlocked", value = 1 },
            reward = { currencies = { gems = 60 } },
        },
        hell_settler = {
            track = "crossing",
            order = 4,
            name = "Unlock an Area in Hell",
            description = "Stake your claim below — unlock any Hell zone.",
            condition = { type = "counter_at_least", counter = "hell_areas_unlocked", value = 1 },
            reward = {
                currencies = { gems = 100 },
                pets = { { id = "bear", variant = "rainbow" } },
            },
        },

        -- ===================== TRAILBLAZER (explore + rebirth) =====================
        pathfinder = {
            track = "trailblazer",
            order = 1,
            name = "Unlock 3 Areas",
            description = "Spread out — each area opens new pets and richer ore.",
            condition = { type = "counter_at_least", counter = "areas_unlocked", value = 3 },
            reward = { currencies = { gems = 15 } },
        },
        socialite = {
            track = "trailblazer",
            order = 2,
            name = "Meet 5 Creators",
            description = "Track down the Creators scattered across the realms.",
            condition = { type = "counter_at_least", counter = "creators_met", value = 5 },
            reward = { currencies = { gems = 25 } },
        },
        world_walker = {
            track = "trailblazer",
            order = 3,
            name = "Unlock 6 Areas",
            description = "Open the gates to the far realms.",
            condition = { type = "counter_at_least", counter = "areas_unlocked", value = 6 },
            reward = { currencies = { gems = 40 } },
        },
        secret_seeker = {
            track = "trailblazer",
            order = 4,
            name = "Find 5 Secrets",
            description = "The realms are full of hidden things for the curious.",
            condition = { type = "counter_at_least", counter = "secrets_found", value = 5 },
            reward = { currencies = { area_coins = 20000 } },
        },
        reborn = {
            track = "trailblazer",
            order = 5,
            name = "Rebirth Once",
            description = "Trade your progress for permanent power. Begin again, stronger.",
            condition = { type = "counter_at_least", counter = "rebirths", value = 1 },
            reward = { currencies = { gems = 100 } },
        },
        ascended_soul = {
            track = "trailblazer",
            order = 6,
            name = "Rebirth 3 Times",
            description = "The Trailblazer capstone — mastery through renewal.",
            condition = { type = "counter_at_least", counter = "rebirths", value = 3 },
            reward = {
                currencies = { gems = 350 },
                pets = { { id = "bear", variant = "rainbow" } },
            },
        },
    },
}
