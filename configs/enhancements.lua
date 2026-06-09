--[[
    Enhancements — Halo & Horns (CoH-style power slotting).

    An enhancement is a record { type, origins } that fills one of a power's EMPTY slots
    (data.Slots[powerId], earned at slot levels) and boosts ONE stat axis of THAT power.

    GRADES (Jason's design):
      • SINGLE-origin — { origins = { "pyromancer" } }. Disc + ring in the SAME color group.
        Stronger (values.single), but usable only when the PLAYER's origin matches.
      • DUAL-origin   — { origins = { "pyromancer", "cryomancer" } }. Disc + ring in DIFFERENT
        color groups. Weaker (values.dual), usable by EITHER origin — twice as often useful,
        deliberately less potent.

    Type → axis → families: each type boosts one PowerStats axis and only fits powers whose
    effect FAMILY it makes sense on (families = "*" means any). `requires_aoe` additionally
    blocks the type on non-AoE powers (Range on a melee/single-target power is meaningless).

    Visuals: disc = the type's symbol in origins[1]'s color; ring = the `enhancement` ring
    (power_icons.rings.enhancement, grayscale) tinted origins[2] or origins[1]'s color.
]]

return {
    -- The four origins (archetype ids — usability checks read the player's data.Archetype).
    origins = { "geomancer", "pyromancer", "cryomancer", "sandwalker" },

    -- Short flavor prefix per origin for display names ("Pyro Damage", "Geo/Cryo Recharge").
    origin_names = {
        geomancer = "Geo",
        pyromancer = "Pyro",
        cryomancer = "Cryo",
        sandwalker = "Sand",
    },

    -- Boost fraction by grade: effective axis = base × (1 + Σ values) — recharge divides instead
    -- (base / (1 + Σ)) so a recharge enhancement SHORTENS the cooldown.
    values = {
        single = 0.33,
        dual = 0.20,
    },

    -- type -> { symbol (disc icon key), axis (PowerStats axis), families ("*" or set),
    --           requires_aoe? } — see header. Families list mirrors docs (Jason's table).
    types = {
        damage = {
            symbol = "fist",
            axis = "damage",
            families = {
                vulnerable = true,
                buff = true,
                rage = true,
                amplified_burst = true,
                burn_spread = true,
                team_cleave = true,
            },
        },
        accuracy = {
            symbol = "target",
            axis = "accuracy",
            families = {
                vulnerable = true,
                root = true,
                root_guard = true,
                fear = true,
                taunt = true,
                amplified_burst = true,
                burn_spread = true,
                team_cleave = true,
            },
        },
        recharge = {
            symbol = "history",
            axis = "recharge",
            families = "*", -- almost everything benefits from a shorter cooldown
        },
        armor = {
            symbol = "armor_chest",
            axis = "magnitude",
            families = { defense_buff = true, armor = true, fortify = true },
        },
        shield = {
            symbol = "shield",
            axis = "magnitude",
            families = { absorb = true },
        },
        health = {
            -- broad survivability: boosts the magnitude of any endurance-protecting power
            symbol = "heart",
            axis = "magnitude",
            families = { heal = true, absorb = true, defense_buff = true, armor = true },
        },
        range = {
            symbol = "range",
            axis = "radius",
            families = "*",
            requires_aoe = true, -- blocked on melee / single-target powers
        },
        duration = {
            symbol = "hourglass",
            axis = "duration",
            families = {
                buff = true,
                defense_buff = true,
                armor = true,
                fortify = true,
                absorb = true,
                vulnerable = true,
                root = true,
                root_guard = true,
                fear = true,
                taunt = true,
                luck = true,
                rage = true,
            },
        },
        healing = {
            symbol = "plus",
            axis = "heal",
            families = { heal = true, heal_blind = true },
        },
    },

    -- Power `target` values that count as AoE for `requires_aoe` types.
    aoe_targets = {
        targeted_aoe = true,
        team_aoe = true,
        player_field = true,
        eruption = true,
        single_spread = true,
    },

    -- DROPS: rolled when a breakable/enemy dies (DropService). The MODEL is semi-generic — the
    -- identity (type/origins) is revealed at pickup via the GameEvents float.
    drops = {
        enabled = true,
        -- chance per breakable broken / enemy defeated that an enhancement drops
        breakable_chance = 0.02,
        enemy_chance = 0.08,
        -- grade split for a drop: single is the rarer, better find
        single_chance = 0.35,
        -- relative weight per type (uniform start; tune freely)
        type_weights = {
            damage = 1,
            accuracy = 1,
            recharge = 1,
            armor = 1,
            shield = 1,
            health = 1,
            range = 1,
            duration = 1,
            healing = 1,
        },
        despawn_seconds = 45,
        -- Authored COGWHEEL drop model (Jason, 2026-06-09): ONE shared 3500-tri mesh + 6 color
        -- textures (scripts/cogwheel_model_ids.json). Color hints the ORIGIN on the ground
        -- (the TYPE stays hidden until pickup): singles use their origin's color, duals use
        -- purple (mixed), silver is the fallback/unknown.
        cog = {
            mesh = "rbxassetid://76065631196112",
            size = 1.6, -- widest-side studs (gem-drop scale)
            textures = {
                silver = "rbxassetid://123560213437578",
                green = "rbxassetid://99887919204355",
                blue = "rbxassetid://102909461111791",
                purple = "rbxassetid://88946068227454",
                red = "rbxassetid://108675846735651",
                yellow = "rbxassetid://119007782066562",
            },
            origin_colors = {
                geomancer = "green",
                pyromancer = "red",
                cryomancer = "blue",
                sandwalker = "yellow",
            },
            dual_color = "purple",
            fallback_color = "silver",
        },
        -- Optional override: a Model under ReplicatedStorage.Assets.Models takes precedence
        -- over the cog mesh when set.
        model_name = nil,
        pickup_radius = 8,
    },

    -- Max enhancements held in the inventory (oldest beyond the cap are refused, not deleted).
    inventory_cap = 60,

    -- Replacing an occupied slot DESTROYS the old enhancement (CoH-style commitment).
    replace_destroys = true,
}
