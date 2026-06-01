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

        -- === Size-aware formations (PetFormation.resolve; wired in Stage 2+) ===
        -- Pets are sorted smallest -> front, huge -> back, and gaps scale with each
        -- pet's footprint. `default_mode` is the fallback; each player overrides it
        -- with their saved choice (Stage 3). Modes: "conga" | "risers" | "arc".
        default_mode = "risers",
        size = {
            default_footprint = 4, -- studs, used when a pet's model extents are unknown
            gap = 1.5, -- base gap added between neighbours, on top of their radii
        },
        -- conga: single file (uses follow_distance + size.gap)
        -- risers: tiered rows; huge anchored in the back row
        risers = { per_row = 3, row_gap = 2, col_spacing = 3 },
        -- arc: concave cradle; huge curling back at the horns
        arc = { radius = 11, arc_step_degrees = 20, spread_factor = 0.15, depth_factor = 0.1 },
    },

    -- Gentle vertical bob (replaces the legacy globalPetFloat oscillator).
    float = {
        amplitude = 0.5,
        period = 2,
    },

    -- Attack mode: pets arrange around the target while attacking (client-driven, purely
    -- visual). `style` is the default; players override it with a saved PetAttackStyle setting,
    -- live-switchable via the PetAttackStyle attribute.
    --   "orbit" (ring spins) | "static_ring" | "lunge" (jab in) | "spiral" (vortex) |
    --   "pincer" (two arcs squeeze) | "firing_line" (row, recoil volley) | "swarm" (jitter cloud)
    -- (No distance leash: AutoTargetService owns target selection + range; the pet clears its
    --  target only when the breakable is mined out, like the legacy.)
    attack = {
        style = "orbit",
        ring_radius = 6,
        ring_height = 3,
        orbit_speed = 2.5, -- radians/sec wheel spin (orbit)
        lunge_distance = 3, -- jab depth toward center (lunge)
        lunge_speed = 6,

        -- spiral (rotating mining vortex): inner -> outer arm, rises with t. The spin rate
        -- lerps inner -> outer, so the inner ring whirls faster than the rim; set
        -- spiral_outer_speed negative to make the two rings counter-rotate instead.
        spiral_turns = 1.5,
        spiral_inner_speed = 3.0, -- rad/sec at the centre
        spiral_outer_speed = 1.5, -- rad/sec at the rim (half the inner -> inner spins ~2x)
        spiral_rise = 2,
        -- pincer (two arcs clamping the target)
        pincer_arc = 80, -- degrees each arc spans
        pincer_squeeze = 2, -- studs the clamp pulses in/out
        pincer_speed = 3,
        -- firing line (a row facing the target, staggered recoil volley)
        line_spacing = 2.5,
        line_recoil = 2,
        line_speed = 5,
        -- swarm (jitter cloud)
        swarm_radius_frac = 0.85,
        swarm_speed = 3,
        swarm_bob = 1.2,
    },

    -- Client movement smoothing (frame-rate-independent exponential approach;
    -- higher = snappier, lower = more momentum/float). Used by PetFollowController.
    movement = {
        follow_lerp_rate = 10,
        attack_lerp_rate = 16,

        -- Pet move speed multiplies the lerp rates above. Driven by the player
        -- attribute `PetMoveSpeed` (a stat/upgrade, default 1.0) and an optional
        -- per-pet model attribute `MoveSpeedMult` (for unique fast pets); the two
        -- multiply against `base`, clamped to [min, max].
        speed = { base = 1.0, min = 0.25, max = 4.0 },

        -- Smoothing for OTHER players' pets (server-relayed at ~10Hz): the client lerps them
        -- toward each relayed transform so they read smooth despite the lower update rate. Your
        -- OWN pets never use this — they're driven locally at full framerate.
        remote_lerp_rate = 14,

        -- Catch-up safety: if a pet ends up further than this (studs) from its target — the
        -- player teleported (zone/realm change) — snap it there instead of slowly crawling
        -- across the whole map. Normal walking never opens a gap this large.
        catchup_distance = 60,
    },

    -- Server tick throttle (seconds): target leash + the mining damage tick only.
    -- Movement is client-side (PetFollowController), not done here.
    update_interval = 0.1,

    -- Enemy spawning (Feature 10 combat). distance = studs in front of the player a test enemy
    -- spawns (slice 1a: admin-spawned, stationary; pets engage it like a breakable).
    enemy_spawn = {
        distance = 16,
    },

    -- Mining gate: a pet only deals mining damage once it's within `range` studs of its target,
    -- so move speed affects mining throughput (DPS ramps as pets arrive). The server reads
    -- per-pet positions the owning client reports (see `replication`). If a pet has no reported
    -- position yet, mining is allowed — the gate never breaks the legacy "near = mines" behaviour.
    mining = {
        range = 9,
    },

    -- Client -> server pet position reporting (drives the mining gate; foundation for multiplayer
    -- pet visibility). Throttled to keep bandwidth modest.
    replication = {
        interval = 0.1, -- seconds between position reports (~10 Hz)
        stale_seconds = 0.5, -- a report older than this is ignored (gate falls back to "allow")
    },
}
