--[[
    Archetypes — Halo & Horns [PROTOTYPE] (Feature 13).

    The player picks ONE archetype (at character creation); it gates which power
    pool they can select from (Feature 14). Alignment (Soul) is orthogonal — it
    does not change the archetype or its pool. Archetype can only change via the
    respec ritual (which also resets powers + augmentation slots).

    Config-as-code: add/replace archetypes and their power pools here with no
    service changes (Feature 26). Pure logic lives in
    `src/Shared/Game/ArchetypeLogic.lua`; power definitions live in configs/powers.lua.
]]

return {
    -- No default: a new player must select before play (Feature 13 [studio]).
    default = nil,

    -- Respec ritual cost (changes archetype + resets powers/slots).
    respec_cost = { currency = "shadow_tokens", amount = 100 },

    archetypes = {
        geomancer = {
            display_name = "Geomancer",
            theme = "earth",
            power_pool = { "stone_skin", "bulwark", "mountains_strength" },
        },
        sandwalker = {
            display_name = "Sandwalker",
            theme = "desert",
            power_pool = { "mirage_step", "sandstorm", "dune_shield" },
        },
        cryomancer = {
            display_name = "Cryomancer",
            theme = "ice",
            power_pool = { "frost_bind", "ice_armor", "blizzard" },
        },
        pyromancer = {
            display_name = "Pyromancer",
            theme = "lava",
            -- mark_of_flame/ember_ward/eruption = shared-pool placeholders; wildfire/firestorm/
            -- cataclysm = the exclusive signatures (§17.8), cataclysm the high-level capstone.
            power_pool = {
                "mark_of_flame",
                "ember_ward",
                "eruption",
                "wildfire",
                "firestorm",
                "cataclysm",
            },
        },
    },
}
