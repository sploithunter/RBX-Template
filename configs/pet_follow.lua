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

        -- Attack FLOURISH layered on the base pivot while engaged (src/Shared/Game/AttackAnim.lua),
        -- the time-driven companion to the walk gait. Chosen by target type: `mining` plays on
        -- breakables/ore, `combat` on enemies. Styles:
        --   "pounce" — periodic jab toward the target + recoil (looks like striking it)
        --   "peck"   — repeated downward dip toward the target (headbutt/pickaxe); peck_speed,
        --              bob_height set the rhythm + dip depth
        --   "none"   — no flourish, just face the target
        --   "spin"   — whirl about up (available, but looked sloppy for mining — not used)
        -- More styles drop into AttackAnim.STYLES; add a config block here. Swap mining.style
        -- below to "peck" or "none" to taste.
        anim = {
            mining = { style = "pounce", pounce_depth = 1.5, pounce_period = 0.5 },
            combat = { style = "none" }, -- enemies: face them for now; pounce/etc. later
        },
    },

    -- Client movement smoothing (frame-rate-independent exponential approach;
    -- higher = snappier, lower = more momentum/float). Used by PetFollowController.
    movement = {
        follow_lerp_rate = 10,
        attack_lerp_rate = 16,

        -- Hard cap on how fast (studs/sec) a pet can physically travel toward its
        -- goal. Without this the exponential lerp above covers any distance almost
        -- instantly, so a pet "teleports" onto a new mining target. The cap makes
        -- pets visibly FLY OVER to a target (so move speed matters + mining DPS
        -- ramps as they arrive). Scaled by the same move-speed multiplier below;
        -- raise it for a snappier feel, lower it for slower, more deliberate travel.
        max_travel_speed = 26,

        -- Pet move speed multiplies the lerp rates + travel cap above. Driven by the
        -- player attribute `PetMoveSpeed` (a stat/upgrade, default 1.0) and an optional
        -- per-pet model attribute `MoveSpeedMult` (for unique fast pets); the two
        -- multiply against `base`, clamped to [min, max].
        speed = { base = 1.0, min = 0.25, max = 4.0 },

        -- Smoothing for OTHER players' pets (server-relayed at ~10Hz): the client lerps them
        -- toward each relayed transform so they read smooth despite the lower update rate. Your
        -- OWN pets never use this — they're driven locally at full framerate.
        remote_lerp_rate = 14,

        -- Catch-up safety: if a pet ends up further than this (studs) from its target —
        -- the player teleported (zone/realm change) — snap it there instead of crawling
        -- across the map. INVARIANT: keep this ABOVE auto_systems.lua
        -- auto_target.max_target_distance (120) so a pet only ever snaps for a real
        -- teleport, never to reach a normal far target (which it should travel to).
        catchup_distance = 200,

        -- Facing: a pet turns to face the direction it's actually MOVING whenever it's
        -- travelling faster than face_move_speed (studs/sec) — so returning/repositioning
        -- pets head forward instead of moonwalking. Below that speed it settles onto its
        -- "rest facing" (player-forward when following, the target when attacking).
        -- face_turn_rate is the exponential turn smoothing (higher = snaps to heading faster).
        face_turn_rate = 12,
        face_move_speed = 2,
    },

    -- Procedural walk gait (client, PetFollowController) — the SAME system enemies use
    -- (src/Shared/Game/Gait.lua). Pets get a waddle/march/hop/etc. layered on their
    -- follow/attack movement, driven by distance travelled so it scales with speed and
    -- rests when still. `gait` is the default for every pet; `gait_by_type` overrides it
    -- per pet PetType so different species move differently. Styles: waddle (bob + L/R
    -- bank), march (stiff stomp), hop (one bounce/stride), slither (heading wiggle).
    gait = {
        enabled = true,
        style = "waddle",
        bob_height = 0.4, -- pets are smaller + already float; keep the bob gentle
        tilt_degrees = 10,
        stride_length = 4,
        ref_speed = 12, -- pets travel faster than enemies; reach full waddle around here
        ease_rate = 9,
    },
    gait_by_type = {
        bunny = { style = "hop", bob_height = 0.9, tilt_degrees = 0, stride_length = 3 },
        bear = { style = "waddle", bob_height = 0.5, tilt_degrees = 13, stride_length = 4.5 },
    },

    -- Ranged pets (pet_roles role == "ranged") fire a cosmetic lightning bolt from the
    -- pet to its target while attacking — the same procedural bolt as the enchanter
    -- (src/Shared/Effects/EnchantLightning). `interval` is the client-side cadence; the
    -- rest are EnchantLightning params tuned for a short, snappy combat zap (no thunder
    -- per shot). Purely visual; damage stays server-side via the mining tick.
    ranged_bolt = {
        enabled = true,

        -- Which ranged visual to fire (RangedFX dispatcher). `kind` is the default for every
        -- ranged pet; `by_type` overrides it per PetType so you can test one pet in isolation.
        -- Kinds: "lightning" (arc) | "fireball"/"plasma"/"frost"/"ice_shard"/"poison" (themed
        -- projectile orbs, params under `projectile`) | "beam" (laser) | "rock" (desert boulder).
        -- Area/element flavour map (assign per pet, or auto-pick by element later):
        --   grass  -> "lightning"      lava   -> "fireball"
        --   ice    -> "frost"/"ice_shard"   desert -> "rock"
        kind = "lightning",
        by_type = {
            colorado = "fireball", -- TEST: colorado throws a fireball instead of lightning
        },

        interval = 0.55, -- seconds between bolts while engaged
        -- Gap-close counter: after firing, the ranged pet is movement-locked this long
        -- (it's "casting"), so it can't freely kite — a melee enemy gets a window to
        -- close. Keep < interval so it frees up briefly between shots.
        cast_lock_seconds = 0.45,
        duration = 0.3,
        thickness = 0.22,
        segments = 16,
        origin_limit = 1,
        strands_per_origin = 1,
        min_radius = 0,
        max_radius = 0.6,
        curve_size0 = 2,
        curve_size1 = 2,
        animation_speed = 9,
        flicker = 0.4,
        fade_out_seconds = 0.12,
        target_offset = { 0, 1.5, 0 }, -- {x,y,z} aim mid-body (client builds the Vector3)
        colors = { { 120, 150, 255 }, { 200, 235, 255 } }, -- electric blue/white

        -- Library impact played at the lightning strike point (RangedFX.IMPACTS), tinted with the
        -- electric colours above: "none" (arc + EnchantLightning's own flash only) | "small" |
        -- "medium" | "big". `impact` is the normal-hit tier; `impact_crit` fires when the server
        -- flags a crit (LastHitCrit on the pet) — so crits land a bigger blast. impact_scale /
        -- impact_sparks (normal) and crit_scale / crit_sparks (crit) optionally override defaults.
        impact = "small",
        impact_crit = "big",

        -- Projectile themes (kind = "fireball"/"plasma"/"frost"/"poison"): one travelling-orb
        -- engine, themed by colour/size/speed/burst. colors = { core, trail+burst }. travel_time
        -- = seconds orb takes to reach the target (keep < interval); burst = impact flash size;
        -- sparks = ember/shard bits the impact explosion sprays outward (0 = flash only). Each
        -- theme also supports impact / impact_crit (RangedFX.IMPACTS tier names) — default normal
        -- "small", crit "big" — so crits (server LastHitCrit) auto-land a bigger blast.
        projectile = {
            fireball = { colors = { { 255, 150, 40 }, { 255, 90, 20 } }, size = 1.6, travel_time = 0.18, burst = 3.5, sparks = 9, impact = "small", impact_crit = "big" },
            plasma = { colors = { { 150, 90, 255 }, { 210, 170, 255 } }, size = 1.3, travel_time = 0.13, burst = 3, sparks = 7 },
            -- ICE themes use the "shatter" impact (frost ring + glass shards) instead of embers.
            frost = { colors = { { 150, 220, 255 }, { 225, 245, 255 } }, size = 1.4, travel_time = 0.2, burst = 3, sparks = 8, impact = "shatter", impact_crit = "big" },
            ice_shard = { colors = { { 170, 225, 255 }, { 235, 250, 255 } }, size = 1.1, travel_time = 0.13, burst = 3, sparks = 6, impact = "shatter", impact_crit = "big" },
            poison = { colors = { { 120, 230, 90 }, { 175, 255, 120 } }, size = 1.5, travel_time = 0.22, burst = 3.5, sparks = 8 },
        },
        -- Beam theme (kind = "beam"): instant laser that flashes + fades.
        beam = { colors = { { 255, 70, 70 } }, thickness = 0.5, duration = 0.18, sparks = 5 },
        -- Rock throw (kind = "rock"): summons a tumbling boulder and hurls it, landing with a
        -- "dust" impact (tan cloud + rubble). DESERT theme. colors = { rock, rubble/dust }.
        rock = { colors = { { 120, 105, 90 }, { 170, 145, 110 } }, size = 2.2, travel_time = 0.3, impact = "dust", impact_crit = "big" },
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

    -- Mining impact FX — OPT-IN previewer for the impact library (RangedFX.IMPACTS). When enabled,
    -- each ore being mined plays a named impact on a cadence, so you can audit ANY impact (small /
    -- big / future entries) just by walking up to ore — no enemy or attack needed. Off by default:
    -- ranged pets already fire their real projectile at crystals/coins (the proper mining visual),
    -- so this is a tuning/preview tool, not gameplay. Flip enabled = true to A/B impacts.
    mining_fx = {
        enabled = false,
        impact = "big", -- "small" (projectile hit) | "medium" (shockwave + smoke) | "big" (really big)
        interval = 0.7, -- seconds between impacts per ore
        colors = { { 255, 150, 40 }, { 255, 90, 20 } }, -- fiery; swap per taste
        scale = 6,
        sparks = 16,
    },

    -- Client -> server pet position reporting (drives the mining gate; foundation for multiplayer
    -- pet visibility). Throttled to keep bandwidth modest.
    replication = {
        interval = 0.1, -- seconds between position reports (~10 Hz)
        stale_seconds = 0.5, -- a report older than this is ignored (gate falls back to "allow")
    },
}
