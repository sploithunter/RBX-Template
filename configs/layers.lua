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
        portals = {
            { part = "Portal_Halo1", layer = "heaven_1", action = "Enter Heaven" },
            { part = "Portal_Horn1", layer = "hell_1", action = "Enter Hell" },
        },
    },

    -- Client lighting skin per realm (RealmAtmosphere). Same map, retinted: heaven = radiant
    -- gold, hell = ember dark, neutral = unchanged. tint is a ColorCorrection TintColor (0-1 RGB).
    atmosphere = {
        tween_seconds = 1.0,
        neutral = { tint = { 1, 1, 1 }, brightness = 0, contrast = 0, clock_time = 14 },
        heaven = { tint = { 1, 0.96, 0.82 }, brightness = 0.12, contrast = 0.1, clock_time = 16 },
        hell = { tint = { 1, 0.62, 0.5 }, brightness = -0.08, contrast = 0.22, clock_time = 4 },
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
}
