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
                        egg_id = "basic_egg",
                        spawn_id = "BasicEgg",
                        position = { x = -34, y = 0.5, z = -22 },
                    },
                    {
                        egg_id = "golden_egg",
                        spawn_id = "GoldenEgg",
                        position = { x = 34, y = 0.5, z = -22 },
                    },
                },
            },
        },
        Meadow = {
            id = "Meadow",
            kind = "area",
            parent = "meadow_island",
            display_name = "Meadow",
            order = 2,
            unlock = {
                required_zone = "Spawn",
                unlocked_by_default = false,
                currency = "crystals",
                cost = 100,
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
    },
}
