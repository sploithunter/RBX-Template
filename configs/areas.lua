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
                        spawn_id = "BasicEarth",
                        position = { x = 0, y = 0.5, z = -22 },
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
            parent = "lava_island",
            display_name = "Lava Fields",
            order = 3,
            unlock = {
                unlocked_by_default = true,
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
            parent = "ice_island",
            display_name = "Ice Fields",
            order = 4,
            unlock = {
                unlocked_by_default = true,
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
    },
}
