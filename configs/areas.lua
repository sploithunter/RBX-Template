return {
    zones = {
        spawn_world = {
            id = "spawn_world",
            kind = "world",
            display_name = "Spawn World",
            order = 1,
        },
        spawn_island = {
            id = "spawn_island",
            kind = "island",
            parent = "spawn_world",
            display_name = "Spawn Island",
            order = 1,
            primary_area = "Spawn",
        },
        meadow_island = {
            id = "meadow_island",
            kind = "island",
            parent = "spawn_world",
            display_name = "Meadow Island",
            order = 2,
            primary_area = "Meadow",
        },
        Spawn = {
            id = "Spawn",
            kind = "area",
            mining_currency = "grass_coins", -- what the zone's ore PAYS (area_coins rewards resolve here)
            parent = "spawn_island",
            display_name = "Spawn Area",
            order = 1,
            unlock = {
                unlocked_by_default = true,
            },
            boosts = {},
            synthetic = {
                center = { x = 0, y = 0, z = 0 },
                size = { x = 160, y = 4, z = 160 },
                floor_y = 0,
                spawn_position = { x = 0, y = 3, z = 0 },
                egg_stands = {
                    {
                        egg_id = "earth_egg",
                        spawn_id = "BasicEarth",
                        position = { x = 0, y = 0.5, z = -22 },
                    },
                },
            },
        },
        Meadow = {
            id = "Meadow",
            kind = "area",
            mining_currency = "grass_coins", -- what the zone's ore PAYS (area_coins rewards resolve here)
            parent = "meadow_island",
            display_name = "Meadow",
            order = 2,
            unlock = {
                required_zone = "Spawn",
                unlocked_by_default = false,
                currency = "crystals",
                -- Meadow grants a PERMANENT +10% coins boost, so it must not be near-free.
                -- ~3 min of grass mining at the fresh-squad rate.
                cost = 2000,
            },
            boosts = {
                coins = 1.1,
            },
            synthetic = {
                center = { x = 220, y = 0, z = 0 },
                size = { x = 160, y = 4, z = 160 },
                floor_y = 0,
                spawn_position = { x = 220, y = 4, z = 0 },
                egg_stands = {},
            },
        },
        lava_island = {
            id = "lava_island",
            kind = "island",
            parent = "spawn_world",
            display_name = "Lava Island",
            order = 3,
            primary_area = "Lava",
        },
        Lava = {
            id = "Lava",
            kind = "area",
            mining_currency = "lava_coins", -- what the zone's ore PAYS (area_coins rewards resolve here)
            parent = "lava_island",
            display_name = "Lava Fields",
            order = 3,
            unlock = {
                unlocked_by_default = false,
                required_zone = "Ice",
                currency = "ice_coins",
                cost = 18000, -- ~15 min of ice mining (see Ice unlock note + design doc §10)
            },
            boosts = {},
            -- Real authored "Lava" baseplate (Home.Lava): center ~(-207,0,68), top ~Y0.5.
            synthetic = {
                center = { x = -207, y = 0, z = 68 },
                size = { x = 360, y = 4, z = 458 },
                floor_y = 0.5,
                spawn_position = { x = -207, y = 5, z = 68 },
                egg_stands = {},
            },
        },
        ice_island = {
            id = "ice_island",
            kind = "island",
            parent = "spawn_world",
            display_name = "Ice Island",
            order = 4,
            primary_area = "Ice",
        },
        Ice = {
            id = "Ice",
            kind = "area",
            mining_currency = "ice_coins", -- what the zone's ore PAYS (area_coins rewards resolve here)
            parent = "ice_island",
            display_name = "Ice Fields",
            order = 4,
            -- Unlock chain (ring order): grass(Spawn) -> Ice -> Lava -> Desert. Each biome is paid
            -- for with the PREVIOUS biome's coins, so you mine one zone to afford the next.
            -- PACING PRINCIPLE (see design doc §10/§11): a gate should cost a real *chapter* in the
            -- current zone (~10-20 min fresh farming, a fraction of the ~20k-coin graduate arc), not
            -- be trivially cheap. Tune the "minutes per zone" by scaling these. At ~10 cps fresh
            -- grass, 8000 ~= 13 min.
            unlock = {
                unlocked_by_default = false,
                required_zone = "Spawn",
                currency = "grass_coins",
                cost = 8000,
            },
            boosts = {},
            -- Real authored "Ice" baseplate (Home.Ice): center ~(-375,0,377).
            synthetic = {
                center = { x = -375, y = 0, z = 377 },
                size = { x = 318, y = 4, z = 326 },
                floor_y = 0.5,
                spawn_position = { x = -375, y = 5, z = 377 },
                egg_stands = {},
            },
        },
        desert_island = {
            id = "desert_island",
            kind = "island",
            parent = "spawn_world",
            display_name = "Desert Island",
            order = 5,
            primary_area = "Desert",
        },
        Desert = {
            id = "Desert",
            kind = "area",
            mining_currency = "desert_coins", -- what the zone's ore PAYS (area_coins rewards resolve here)
            parent = "desert_island",
            display_name = "Desert Fields",
            order = 5,
            unlock = {
                unlocked_by_default = false,
                required_zone = "Lava",
                currency = "lava_coins",
                cost = 35000, -- ~23 min of lava mining; last homeworld gate, biggest commitment
            },
            boosts = {},
            -- Real authored "Desert" baseplate (Home.Desert): center ~(-127,1,475).
            synthetic = {
                center = { x = -127, y = 1, z = 475 },
                size = { x = 330, y = 4, z = 301 },
                floor_y = 1.5,
                spawn_position = { x = -127, y = 6, z = 475 },
                egg_stands = {},
            },
        },
    },
}
