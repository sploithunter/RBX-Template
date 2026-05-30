--[[
    Pet follow / movement — Halo & Horns + template [PROTOTYPE] (issue #4).

    Config-as-code for the service-owned pet-follow loop (PetFollowService), which
    replaces the legacy cloned per-pet PetScripts/Follow + FollowBox scripts. The
    pure formation math lives in `src/Shared/Game/PetFormation.lua`; this file
    holds every tuning knob that used to be hardcoded across the cloned scripts
    (FOLLOW_SPACING, PET_CIRCLE_RADIUS, responsiveness 200/75, float, etc.).

    service_owned: the rollout flag (issue #4). While false, the legacy cloned
    scripts drive movement exactly as before and PetFollowService is inert. When
    true, PetFollowService owns movement and the cloned scripts no-op. This lets
    us verify live and roll back instantly.
]]

return {
    service_owned = true,

    -- How pets arrange behind/around the player.
    formation = {
        mode = "rows", -- "rows" (marching grid) | "circle" (arc behind)
        follow_distance = 6, -- studs behind the player to the first row / arc center
        height = 2, -- studs above the player's root

        -- rows mode
        per_row = 3,
        row_spacing = 4,
        col_spacing = 4,

        -- circle mode
        radius = 8,
        arc_degrees = 120,
    },

    -- Gentle vertical bob (replaces the legacy globalPetFloat oscillator).
    float = {
        amplitude = 0.5,
        period = 2,
    },

    -- AlignPosition/AlignOrientation tuning (parity with the legacy values).
    align = {
        follow_responsiveness = 200,
        follow_max_force = 1e9,
        attack_responsiveness = 75,
    },

    -- Attack mode: pets SURROUND the target in an animated ring (client-driven
    -- visualization). Switch `style` to experiment.
    --   leash_distance — how far the PLAYER can walk before a pet abandons its
    --                    target and returns to following (server-authoritative).
    --   style          — "orbit" (ring spins), "static_ring" (held ring),
    --                    "lunge" (ring slots jab toward the center).
    attack = {
        leash_distance = 45,
        style = "orbit",
        ring_radius = 6,
        ring_height = 3,
        orbit_speed = 2.5, -- radians/sec wheel spin (orbit)
        lunge_distance = 3, -- jab depth toward center (lunge)
        lunge_speed = 6,
    },

    -- Client movement smoothing (movement is a CLIENT-side visualization; the
    -- pet position is lerped toward its target each frame). 0..1 per frame.
    movement = {
        follow_lerp = 0.18,
        attack_lerp = 0.35,
    },

    -- Server tick throttle (seconds) for the authoritative work: target leash +
    -- the mining damage tick. Movement is NOT done here (it's client-side).
    update_interval = 0.1,
}
