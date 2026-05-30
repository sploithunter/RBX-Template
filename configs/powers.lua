--[[
    Powers — Halo & Horns [PROTOTYPE] (Feature 14: Power Selection at Level-Up).

    Player-cast support powers, gated by archetype (configs/archetypes.lua power_pool
    references these ids). At each selection level the player picks ONE power from
    their archetype's pool; selections accumulate and persist (profile.Powers).
    Focus cost (Feature 12) + base cooldown live here; augmentation slots (Feature 15)
    modify the effective cooldown. Pure rules: `src/Shared/Game/PowerSelection.lua`.
]]

return {
    -- Levels that grant a power selection (one per level). Tunable.
    selection_levels = { 5, 9, 13, 17, 21, 25 },

    powers = {
        -- Geomancer
        stone_skin = {
            archetype = "geomancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "shield",
        },
        bulwark = {
            archetype = "geomancer",
            focus_cost = 30,
            cooldown_seconds = 45,
            effect = "team_shield",
        },
        mountains_strength = {
            archetype = "geomancer",
            focus_cost = 25,
            cooldown_seconds = 40,
            effect = "damage_buff",
        },
        -- Sandwalker
        mirage_step = {
            archetype = "sandwalker",
            focus_cost = 15,
            cooldown_seconds = 20,
            effect = "dodge",
        },
        sandstorm = {
            archetype = "sandwalker",
            focus_cost = 35,
            cooldown_seconds = 50,
            effect = "aoe_blind",
        },
        dune_shield = {
            archetype = "sandwalker",
            focus_cost = 20,
            cooldown_seconds = 35,
            effect = "shield",
        },
        -- Cryomancer
        frost_bind = {
            archetype = "cryomancer",
            focus_cost = 25,
            cooldown_seconds = 35,
            effect = "root",
        },
        ice_armor = {
            archetype = "cryomancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "shield",
        },
        blizzard = {
            archetype = "cryomancer",
            focus_cost = 40,
            cooldown_seconds = 60,
            effect = "aoe_slow",
        },
        -- Pyromancer
        mark_of_flame = {
            archetype = "pyromancer",
            focus_cost = 20,
            cooldown_seconds = 25,
            effect = "damage_over_time",
        },
        ember_ward = {
            archetype = "pyromancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "shield",
        },
        eruption = {
            archetype = "pyromancer",
            focus_cost = 45,
            cooldown_seconds = 60,
            effect = "aoe_damage",
        },
    },
}
