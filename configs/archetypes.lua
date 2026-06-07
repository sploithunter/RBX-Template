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

    -- GENERIC pool — universal powers EVERY archetype can pick (farming / luck / utility). White
    -- disc (no element origin). ArchetypeLogic.availablePowers appends these to the archetype pool,
    -- so the player's pickable pool = origin powers + generic ≈ 20 (pick 10).
    generic_pool = {
        "prospector",
        "windfall",
        "fortune",
        "huge_fortune",
        "swift",
        "hasten",
        "revive",
        "recall",
        "world_travel",
        "xp_surge",
        "magnet",
    },

    archetypes = {
        geomancer = {
            display_name = "Geomancer",
            theme = "earth",
            power_pool = {
                "stone_skin",
                "bulwark",
                "mountains_strength",
                "aegis",
                "ironclad",
                "sunder",
                -- signatures (shield/tank identity; gaia_colossus = summon capstone)
                "bastion",
                "seismic_hold",
                "living_mountain",
                "gaia_colossus",
            },
        },
        sandwalker = {
            display_name = "Sandwalker",
            theme = "desert",
            power_pool = {
                "mirage_step",
                "sandstorm",
                "dune_shield",
                "expose",
                "cripple",
                -- signatures (heal/sustain identity; genie_dunes = summon+revive capstone)
                "oasis",
                "mirage_veil",
                "simoom",
                "genie_dunes",
            },
        },
        cryomancer = {
            display_name = "Cryomancer",
            theme = "ice",
            power_pool = {
                "frost_bind",
                "ice_armor",
                "blizzard",
                "disarm",
                "focus_fire",
                -- signatures (control identity; eternal_winter = field-hold capstone)
                "permafrost",
                "shatter",
                "absolute_zero",
                "eternal_winter",
            },
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
                "strike",
                "wildfire",
                "firestorm",
                "cataclysm",
                "inferno_brand",
            },
        },
    },
}
