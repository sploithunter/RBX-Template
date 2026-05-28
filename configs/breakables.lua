return {
    -- Breakable objects configuration (crystals, ores, etc.)
    crystals = {
        SmallBlueCrystal = {
            display_name = "Small Blue Crystal",
            asset_id = "rbxassetid://112188519963572",
            scale = 1,
            health = 100,
            value = 5,
            currency = "crystals",
            -- Some uploaded models import sideways; fix with default orientation at preload time
            default_orientation = { x = -90, y = 0, z = 0 },
            placement = {
                height_offset = 1,
                sink_depth = 0.75,
            },
        },
        MediumBlueCrystal = {
            display_name = "Medium Blue Crystal",
            asset_id = "rbxassetid://113452230594676",
            scale = 1,
            health = 500,
            value = 25,
            currency = "crystals",
            default_orientation = { x = -90, y = 0, z = 0 },
            placement = {
                height_offset = 2,
                sink_depth = 1.05,
            },
        },
        BigBlueCrystal = {
            display_name = "Big Blue Crystal",
            asset_id = "rbxassetid://109710590640681",
            scale = 1,
            health = 2000,
            value = 100,
            currency = "crystals",
            default_orientation = { x = -90, y = 0, z = 0 },
            placement = {
                height_offset = 7,
                sink_depth = 1.45,
            },
        },
        CoinStack = {
            display_name = "Coin Stack",
            procedural_asset = "coin_stack",
            scale = 1,
            health = 25,
            value = 25,
            currency = "coins",
            placement = {
                height_offset = 0,
                sink_depth = 0,
                drop_from_height = 16,
                drop_duration = 0.75,
            },
            physics = {
                anchored = true,
                can_collide = false,
                can_touch = false,
                can_query = true,
            },
        },
    },

    -- World-level settings for breakables
    worlds = {
        -- Spawn uses an invisible SpawnArea part under:
        -- Workspace.Game.Breakables.Crystals.Spawn
        Spawn = {
            max = 14, -- Starter area should feel curated, not crowded
            interval = 8, -- seconds between spawn attempts per spawner
            spawn_area = {
                name = "SpawnArea",
                size = { x = 140, y = 1, z = 140 },
                position = { x = 0, y = 0, z = 0 },
            },
            spawn_settings = {
                upright = true, -- keep crystals upright and only randomize yaw
                surface_y = 0, -- SpawnIsland floor surface; SpawnArea provides X/Z
                use_spawner_bounds = true,
                spawn_area_margin = 14,
                spawn_center = { x = 0, z = 0 }, -- fallback if no area-sized part exists
                spawn_radius = 55, -- fallback if no area-sized part exists
                spawn_exclusion_radius = 28, -- keep the player spawn pad readable
                embed_ratio = 0, -- use per-crystal sink_depth for predictable floor placement
                min_distance = 18, -- minimum spacing between spawned crystals
                spawn_attempts = 30,
                respawn_min_seconds = 5, -- delay range after a crystal is removed/destroyed
                respawn_max_seconds = 60,
            },
            -- Optional weighted spawn table. Entries can override scale/health/value/currency/placement per area.
            spawn_table = {
                { name = "SmallBlueCrystal", weight = 5 },
                { name = "MediumBlueCrystal", weight = 1 },
                { name = "CoinStack", weight = 4 },
            },
        },
        Meadow = {
            max = 8,
            interval = 10,
            spawn_area = {
                name = "SpawnArea",
                size = { x = 130, y = 1, z = 130 },
                position = { x = 220, y = 0, z = 0 },
            },
            spawn_settings = {
                upright = true,
                surface_y = 0,
                use_spawner_bounds = true,
                spawn_area_margin = 16,
                spawn_center = { x = 220, z = 0 },
                spawn_radius = 50,
                spawn_exclusion_radius = 24,
                embed_ratio = 0,
                min_distance = 20,
                spawn_attempts = 30,
                respawn_min_seconds = 10,
                respawn_max_seconds = 70,
            },
            spawn_table = {
                { name = "SmallBlueCrystal", weight = 5 },
                { name = "MediumBlueCrystal", weight = 3 },
                { name = "BigBlueCrystal", weight = 1 },
                { name = "CoinStack", weight = 2 },
            },
        },
    },

    -- Workspace structure that can be generated from config for local/dev maps.
    -- Designers can still place real area parts in Studio; this is the code-owned fallback.
    structure = {
        spawn_island = {
            name = "SpawnIsland",
            size = { x = 160, y = 4, z = 160 },
            position = { x = 0, y = -2, z = 0 },
            color = { r = 46, g = 158, b = 74 },
            material = "Grass",
        },
        start_spawn = {
            name = "StartSpawn",
            size = { x = 12, y = 1, z = 12 },
            position = { x = 0, y = 2, z = 0 },
            transparency = 0.25,
            color = { r = 38, g = 115, b = 255 },
        },
        egg_spawn_points = {
            {
                spawn_id = "BasicEarth",
                egg_type = "basic_egg",
                name = "EggSpawnPoint",
                size = { x = 3, y = 1, z = 3 },
                position = { x = 0, y = 0.5, z = -22 },
                transparency = 1,
                color = { r = 255, g = 255, b = 255 },
            },
        },
        defaults = {
            max = 0,
            spawner = {
                name = "Spawner",
                size = { x = 1, y = 1, z = 1 },
                random_position = {
                    x = { min = -50, max = 50 },
                    y = 10,
                    z = { min = -50, max = 50 },
                },
            },
        },
        folders = {
            Breakables = {
                Crystals = {
                    spawners = true,
                    worlds = {
                        "Spawn",
                        "World2",
                        "World3",
                        "Desert",
                        "Anime",
                        "Mine",
                        "Artic",
                        "Ancient",
                        "Magic",
                        "Galaxy",
                        "Swamp",
                        "CorruptedCity",
                        "Blackhole",
                        "SpaceLand",
                        "Careers",
                        "Program",
                        "E100KEVENT",
                    },
                },
                Gold = {
                    max = 25,
                    spawners = { name = "GoldSpawner" },
                    worlds = {
                        "World3",
                        "Ancient",
                        "Magic",
                        "Galaxy",
                        "Steampunk",
                        "Carnival",
                        "Swamp",
                        "CorruptedCity",
                        "Blackhole",
                        "SpaceLand",
                        { name = "PowerMaxBunny", spawners = false },
                        { name = "Easter", spawners = false },
                        { name = "CincoDeMayo", spawners = false },
                        { name = "VisitsEvent", spawners = false },
                    },
                },
                Green = {
                    worlds = {
                        { name = "Spawn", spawners = true },
                        { name = "World2", spawners = false },
                        { name = "World3", spawners = false },
                        { name = "StPatrick", spawners = false },
                    },
                },
                Summer = {
                    worlds = {
                        { name = "Spawn", spawners = false },
                        { name = "World2", spawners = false },
                        { name = "World3", spawners = true },
                        { name = "StPatrick", spawners = false },
                    },
                },
                Clicks = {
                    worlds = {
                        { name = "Spawn", spawners = true },
                    },
                },
            },
            Chaseables = {
                Snowman = {
                    worlds = {
                        { name = "Christmas", spawners = false },
                        { name = "Christmas2", spawners = false },
                    },
                },
                Hearts = {
                    worlds = {
                        { name = "Valentine", spawners = false },
                    },
                },
            },
        },
    },

    -- Fallbacks if a world has no explicit settings
    defaults = {
        max_per_world = 0,
        spawn_settings = {
            upright = true,
            surface_y = 0,
            use_spawner_bounds = true,
            spawn_area_margin = 0,
            spawn_radius = 0,
            spawn_exclusion_radius = 0,
            -- Authored maps can set surface_mode = "surface" or tag a SpawnZone with
            -- SurfaceOnly=true to raycast onto playable geometry instead of using a flat Y.
            spawn_clearance_radius = 0,
            spawn_clearance_height = 10,
            embed_ratio = 0,
            min_distance = 12,
            spawn_attempts = 12,
            respawn_min_seconds = 5,
            respawn_max_seconds = 60,
        },
    },
}
