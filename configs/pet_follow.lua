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
    -- false: the legacy cloned Follow/FollowBox scripts own pet movement (they
    -- include the teleport-watchdog + tuned forces that keep pets from falling
    -- off the map — issue #4's known 10-months-ago bug). PetFollowService stays
    -- inert. Damage still routes through CombatService (the legacy Follow calls
    -- CombatService:ResolvePetDamage). A service-owned movement loop can only take
    -- over once it ports that anti-fall machinery — see issue #4 / CURRENT_STATUS.
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

    -- Attack mode: pets SURROUND the target in an animated ring (client-driven).
    -- Switch `style` to experiment (also live via the PetAttackStyle attribute).
    --   leash_distance — how far the PLAYER can walk before a pet abandons its
    --                    target and follows again (server-authoritative).
    --   style          — "orbit" (ring spins), "static_ring", "lunge" (jab in).
    attack = {
        leash_distance = 45,
        style = "orbit",
        ring_radius = 6,
        ring_height = 3,
        orbit_speed = 2.5, -- radians/sec wheel spin (orbit)
        lunge_distance = 3, -- jab depth toward center (lunge)
        lunge_speed = 6,
    },

    -- Client movement smoothing (frame-rate-independent exponential approach;
    -- higher = snappier, lower = more momentum/float). Used by PetFollowController.
    movement = {
        follow_lerp_rate = 10,
        attack_lerp_rate = 16,
    },

    -- Server tick throttle (seconds): target leash + the mining damage tick only.
    -- Movement is client-side (PetFollowController), not done here.
    update_interval = 0.1,
}
