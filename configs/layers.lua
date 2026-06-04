--[[
    Layer config — Halo & Horns.

    Stacked vertical layers: base, Heaven 1-5, Hell 1-5. Owns the reward economics
    (Feature 4), element/realm mapping (Feature 5/6), and access gating
    (Feature 3 + World S3: Soul magnitude + token cost + player level, validated
    server-side). Geometry (Y-offsets) and the visual portals are authored map work;
    this config is the contract those bind to.

    `multipliers`     : reward scaling per layer (base = 1.0).
    `token_currency`  : side-reward / access token per layer.
    `realm_alignment` : "neutral"/"heaven"/"hell" (drives element resonance).
    `hatch_element`   : element a pet is born with when hatched on the layer.
    `access`          : per-layer { y_offset, requires_soul, token_cost, requires_level }.
                        base has no requirement; Heaven needs soul >= requires_soul
                        (positive), Hell needs soul <= requires_soul (negative);
                        requires_level gates by the player's earned Level (World S3).

    Retention note (design doc §12/§14): these layers are the NON-terminal endgame —
    `token_cost` is a recurring traversal SINK (LayerService:UseLayer deducts per move),
    not a one-time unlock. Deeper = higher soul + level + token cost AND richer rewards.
]]

return {
    -- Traversal sink shape (design doc §14, fork 2 — gameplay-tunable knob):
    --   "deeper_only" = free to retreat toward base/neutral; pay the target layer's token_cost
    --                   only when moving to a DEEPER layer (greater magnitude depth). [default]
    --   "every_move"  = pay the target's token_cost on every layer change (the original behavior).
    -- The recurring token sink that anchors the realm economy; flip live to compare feel.
    traversal = {
        charge_on = "deeper_only",
    },

    -- Token-earning loop (design doc §14, fork 1 — feeds the traversal sink above).
    -- Light/shadow tokens are earned only while in a realm layer (heaven -> light,
    -- hell -> shadow). income_cut converts that fraction of biome-coin income into the
    -- realm token (income_min floors a positive trickle); conquest/hatch are flat grants.
    earning = {
        income_cut = 0.1,
        income_min = 1,
        conquest_tokens = 25,
        hatch_tokens = 2,
    },

    -- Depth = desirability (design doc §12/§15): deeper realm layers add hatch luck on top of
    -- the player's own entitlements, so the rarest pulls (golden/rainbow/eternal) live deep.
    -- hatch_luck_per_depth is added per layer depth (heaven_3 / hell_3 -> +0.3, the 5s -> +0.5).
    depth_rewards = {
        hatch_luck_per_depth = 0.1,
    },

    -- TEST portals (RealmPortalService): named workspace parts you walk up to, mapped to a realm
    -- layer. Toggling enters that realm (or returns to base if already in it). `bypass_access`
    -- skips the soul/level/token gate so the realm is reachable for testing before the economy
    -- is grindable — flip false once gating is being verified. Reuses the same map (the
    -- RealmAtmosphere client skin retints the world); not the production realm-geometry path.
    realm_portals = {
        bypass_access = true,
        prompt_hold = 0,
        max_distance = 14,
        -- Portal_Halo1-5 -> heaven_1-5, Portal_Horn1-5 -> hell_1-5. Each jumps DIRECTLY to its
        -- layer (touch again while standing on it to return to base), so you can hop base ->
        -- Halo3 -> Halo5 to test any depth.
        portals = {
            { part = "Portal_Halo1", layer = "heaven_1", action = "Enter Heaven 1" },
            { part = "Portal_Halo2", layer = "heaven_2", action = "Enter Heaven 2" },
            { part = "Portal_Halo3", layer = "heaven_3", action = "Enter Heaven 3" },
            { part = "Portal_Halo4", layer = "heaven_4", action = "Enter Heaven 4" },
            { part = "Portal_Halo5", layer = "heaven_5", action = "Enter Heaven 5" },
            { part = "Portal_Horn1", layer = "hell_1", action = "Enter Hell 1" },
            { part = "Portal_Horn2", layer = "hell_2", action = "Enter Hell 2" },
            { part = "Portal_Horn3", layer = "hell_3", action = "Enter Hell 3" },
            { part = "Portal_Horn4", layer = "hell_4", action = "Enter Hell 4" },
            { part = "Portal_Horn5", layer = "hell_5", action = "Enter Hell 5" },
        },
    },

    -- Client realm skin (RealmAtmosphere, World S3 A1) — DEPTH-SCALED. The client captures the
    -- map's real base lighting and blends base -> the realm's `deep` anchor below by t = depth /
    -- max_depth (RealmTheme): layer 1 = a faint 20% wash, the deepest layer = the full `deep` look.
    -- So each descent step intensifies; the most dramatic look is reserved for layer 5.
    -- `tint` is a ColorCorrection TintColor (0-1); ambient / fog / atmosphere colors are 0-255 RGB.
    -- (Only the `deep` endpoint is configured — the shallow end is the live captured base.)
    atmosphere = {
        tween_seconds = 1.2,
        max_depth = 5,
        -- Heaven deep (layer 5): blinding, radiant celestial.
        heaven = {
            tint = { 1, 0.99, 0.92 },
            brightness = 0.2,
            contrast = 0.05,
            clock_time = 14,
            ambient = { 200, 195, 170 },
            outdoor_ambient = { 235, 228, 200 },
            fog_color = { 250, 248, 235 },
            fog_end = 4000,
            atmosphere = {
                density = 0.4,
                offset = 0.05,
                color = { 252, 248, 235 },
                decay = { 245, 238, 215 },
                glare = 0.7,
                haze = 2.0,
            },
        },
        -- Hell deep (layer 5): red, oppressive MOOD — but lit enough to see your own character +
        -- the ground (the dark/dramatic SKY now comes from the per-layer skybox, so the lighting
        -- doesn't need to crush the world). Enemies can still lurk in the red murk.
        hell = {
            tint = { 1, 0.58, 0.5 },
            brightness = 0.02,
            contrast = 0.12,
            clock_time = 2,
            ambient = { 0, 0, 0 }, -- ambient OFF — pitch-black hell (user: "it was black, the red wash is wrong")
            outdoor_ambient = { 0, 0, 0 },
            fog_color = { 45, 14, 12 },
            fog_end = 1000,
            atmosphere = {
                density = 0.35, -- was 0.55 — thin the murk so you're not lost in it
                offset = 0.2,
                color = { 120, 40, 32 },
                decay = { 80, 22, 16 },
                glare = 0.2,
                haze = 2.2,
            },
        },
        -- Per-LAYER skybox swap (RealmAtmosphere). One sky per layer — base + heaven_1-5 +
        -- hell_1-5 — so the sky escalates with depth alongside the lighting (Hell 1 = brooding red
        -- clouds -> Hell 5 = the eyes-in-the-abyss). Authoring: generate an equirectangular 2:1
        -- panorama per layer, convert to 6 cubemap faces, upload, and drop the asset ids below
        -- (numbers or "rbxassetid://..."). `textures = { ft, bk, lf, rt, up, dn, sun?, moon? }`.
        -- A layer left nil keeps the map's base sky (captured + restored), so fill them in as you
        -- generate each. Applied per layer; the lighting ramp above scales intensity within it.
        sky = {
            per_layer = {
                -- base = nil means "don't swap" — RealmAtmosphere leaves the place's own Sky alone
                -- (so whatever sky you set in the map shows in Play too). The ORIGINAL aurora sky
                -- is RECORDED here for restore (not active, so it can't override your tests):
                --   aurora faces: ft=340908468 bk=340908398 lf=340908504 rt=340908530
                --                 up=340908586 dn=340908450  (CelestialBodiesShown=false, StarCount=5000)
                --   aurora mood: Atmosphere Density 0.28 / Color (0.247,0.635,0.220) green / Haze 1;
                --                Lighting ClockTime 13 / Brightness 1.88 / FogEnd 100000.
                -- To make a layer use a sky, fill its `textures = { ft, bk, lf, rt, up, dn, ... }`.
                base = { textures = nil },
                heaven_1 = { textures = nil },
                heaven_2 = { textures = nil },
                heaven_3 = { textures = nil },
                heaven_4 = { textures = nil },
                heaven_5 = { textures = nil },
                hell_1 = {
                    textures = {
                        ft = 72553765826706,
                        bk = 92241207750302,
                        lf = 138038201122541,
                        rt = 94865800916028,
                        up = 89930062014588,
                        dn = 97468777327797,
                        celestial_bodies_shown = false,
                    },
                },
                hell_2 = {
                    textures = {
                        ft = 104546429898763,
                        bk = 99960987517987,
                        lf = 102019268027119,
                        rt = 106724041487205,
                        up = 130939998101973,
                        dn = 127294774735759,
                        celestial_bodies_shown = false,
                    },
                },
                -- Hyper3D "nightmarish demon-infested hellscape, glowing red eyes, jagged spired
                -- cities" — dramatic mid-hell (you can still see). One-line move to hell_2 if shallower.
                hell_3 = {
                    textures = {
                        ft = 136769467498269,
                        bk = 76076955500596,
                        lf = 96726444149379,
                        rt = 128315364827628,
                        up = 128070223417654,
                        dn = 80101487417158,
                    },
                },
                hell_4 = {
                    textures = {
                        ft = 115778938011231,
                        bk = 140409478026965,
                        lf = 106621185787267,
                        rt = 133932701501959,
                        up = 121688909163908,
                        dn = 82579821400928,
                        celestial_bodies_shown = false, -- custom sky: hide the default sun/moon
                    },
                },
                hell_5 = {
                    textures = {
                        ft = 102213954263406,
                        bk = 100049080158700,
                        lf = 74423796663126,
                        rt = 86898675313846,
                        up = 138010467678345,
                        dn = 70514714416769,
                        celestial_bodies_shown = false, -- the abyss: custom sky, no default sun/moon
                    },
                },
            },
        },
    },

    multipliers = {
        base = 1.0,
        heaven_1 = 1.5,
        heaven_2 = 2.0,
        heaven_3 = 2.5,
        heaven_4 = 3.0,
        heaven_5 = 3.5,
        hell_1 = 1.5,
        hell_2 = 2.0,
        hell_3 = 2.5,
        hell_4 = 3.0,
        hell_5 = 3.5,
    },

    token_currency = {
        heaven_1 = "light_tokens",
        heaven_2 = "light_tokens",
        heaven_3 = "light_tokens",
        heaven_4 = "light_tokens",
        heaven_5 = "light_tokens",
        hell_1 = "shadow_tokens",
        hell_2 = "shadow_tokens",
        hell_3 = "shadow_tokens",
        hell_4 = "shadow_tokens",
        hell_5 = "shadow_tokens",
    },

    realm_alignment = {
        base = "neutral",
        heaven_1 = "heaven",
        heaven_2 = "heaven",
        heaven_3 = "heaven",
        heaven_4 = "heaven",
        heaven_5 = "heaven",
        hell_1 = "hell",
        hell_2 = "hell",
        hell_3 = "hell",
        hell_4 = "hell",
        hell_5 = "hell",
    },

    hatch_element = {
        base = "neutral",
        heaven_1 = "light",
        heaven_2 = "light",
        heaven_3 = "light",
        heaven_4 = "light",
        heaven_5 = "light",
        hell_1 = "shadow",
        hell_2 = "shadow",
        hell_3 = "shadow",
        hell_4 = "shadow",
        hell_5 = "shadow",
    },

    -- requires_soul: Heaven layers need soul >= value; Hell layers need soul <=
    -- value (negative). requires_level: the player's earned Level must be >= value
    -- (skipped when the caller doesn't supply a level — the pure module stays judgable).
    -- token_cost is paid in the layer's token_currency EVERY traversal (recurring sink).
    -- base has no requirement.
    access = {
        base = { y_offset = 0, requires_soul = nil, token_cost = 0, requires_level = nil },

        heaven_1 = { y_offset = 2000, requires_soul = 20, token_cost = 100, requires_level = 10 },
        heaven_2 = { y_offset = 4000, requires_soul = 40, token_cost = 250, requires_level = 20 },
        heaven_3 = { y_offset = 6000, requires_soul = 60, token_cost = 500, requires_level = 30 },
        heaven_4 = { y_offset = 8000, requires_soul = 80, token_cost = 1000, requires_level = 40 },
        heaven_5 = {
            y_offset = 10000,
            requires_soul = 100,
            token_cost = 2000,
            requires_level = 50,
        },

        hell_1 = { y_offset = -2000, requires_soul = -20, token_cost = 100, requires_level = 10 },
        hell_2 = { y_offset = -4000, requires_soul = -40, token_cost = 250, requires_level = 20 },
        hell_3 = { y_offset = -6000, requires_soul = -60, token_cost = 500, requires_level = 30 },
        hell_4 = { y_offset = -8000, requires_soul = -80, token_cost = 1000, requires_level = 40 },
        hell_5 = {
            y_offset = -10000,
            requires_soul = -100,
            token_cost = 2000,
            requires_level = 50,
        },
    },

    -- Giant demon head looming in the Hell sky (RealmHellFaces). The server LoadAssets the model
    -- once into ReplicatedStorage.RealmModels at boot; the client clones it, scales it huge, and
    -- hangs it OFF TO ONE SIDE up in the sky (NOT straight overhead — Roblox cameras hate looking
    -- straight up), facing the player. The face body is darkened so it recedes into shadow; two
    -- raycast-seated Neon eyes glow from deep in the sockets. Hell-only; client-side per player.
    -- Tuned live (off-to-side placement, recessed glowing eyes) — see commit history.
    hell_faces = {
        enabled = true,
        model_asset_id = 87113428787101,
        template_name = "HellFace", -- runtime cache under ReplicatedStorage.RealmModels

        scale = 240, -- target max-dimension in studs (huge, looming presence)
        -- Placement is player-relative on Hell entry: off to one side, high, facing the player.
        height = 350, -- studs above the player (so it sits ~35-40 deg up, a natural camera pitch)
        distance = 450, -- horizontal offset to the side
        azimuth_deg = 0, -- which world compass direction it sits (0 = +X; spin it to taste)
        base_count = 1, -- one hero face
        per_depth_count = 0, -- 0 = single face at every depth; >0 rings extra faces with depth

        -- Face body: dark so only the eyes read (the head silhouettes against the skybox).
        face_color = { 35, 12, 10 },
        face_material = "SmoothPlastic",

        -- Glowing eyes, raycast-seated into the actual mesh sockets and recessed for a sunken look.
        eyes = {
            enabled = true,
            size = 34, -- orb diameter (studs)
            up = 30, -- studs above head center (brow height)
            side = 35, -- half-separation between the eyes
            recess = 30, -- how deep into the sockets they sit (+ = deeper; raycast-seated)
            color = { 255, 30, 12 }, -- Neon orb color (red, ~max for red Neon)
            light_color = { 255, 40, 18 }, -- bloom halo color
            light_brightness = 14, -- bloom intensity
            light_range = 95, -- bloom reach
        },

        -- Legacy per-face interior light (off now; the eyes carry the glow). Kept for back-compat.
        light_color = { 255, 45, 25 },
        light_brightness = 0,
        light_range = 100,
        pulse_brightness = 0,
        pulse_seconds = 2.4,
    },
}
