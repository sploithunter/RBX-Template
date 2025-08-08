return {
  -- Breakable objects configuration (crystals, ores, etc.)
  crystals = {
    SmallBlueCrystal = {
      display_name = "Small Blue Crystal",
      asset_id = "rbxassetid://112188519963572",
      health = 100,
      value = 5,
      currency = "crystals",
      -- Some uploaded models import sideways; fix with default orientation at preload time
      default_orientation = { x = -90, y = 0, z = 0 },
    },
    MediumBlueCrystal = {
      display_name = "Medium Blue Crystal",
      asset_id = "rbxassetid://113452230594676",
      health = 500,
      value = 25,
      currency = "crystals",
      default_orientation = { x = -90, y = 0, z = 0 },
    },
    BigBlueCrystal = {
      display_name = "Big Blue Crystal",
      asset_id = "rbxassetid://109710590640681",
      health = 2000,
      value = 100,
      currency = "crystals",
      default_orientation = { x = -90, y = 0, z = 0 },
    },
  },

  -- World-level settings for breakables
  worlds = {
    -- You’re placing spawner parts in Studio under:
    -- Workspace.Game.Breakables.Crystals.Spawn
    Spawn = {
      max = 25, -- Max crystals in this world
      interval = 8, -- seconds between spawn attempts per spawner
      spawn_settings = {
        upright = true,        -- keep crystals upright and only randomize yaw
        embed_ratio = 0.25,    -- portion of crystal height pushed below ground (0-1)
        min_distance = 12,     -- minimum spacing between spawned crystals
        respawn_min_seconds = 5,   -- delay range after a crystal is removed/destroyed
        respawn_max_seconds = 60,
      },
      -- Optional weighted spawn table. If omitted, all crystals are equally likely.
      spawn_table = {
        { name = "SmallBlueCrystal",  weight = 1 },
        { name = "MediumBlueCrystal", weight = 1 },
        { name = "BigBlueCrystal",    weight = 1 },
      },
    },
  },

  -- Fallbacks if a world has no explicit settings
  defaults = {
    max_per_world = 25,
  },
}
