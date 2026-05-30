--[[
    Layer config — Halo & Horns [PROTOTYPE].

    Stacked vertical layers: base, Heaven 1-3, Hell 1-3. Owns the reward economics
    (Feature 4), element/realm mapping (Feature 5/6), and access gating
    (Feature 3: Soul magnitude + token cost, validated server-side). Geometry
    (Y-offsets) and the visual portals are authored map work; this config is the
    contract those bind to.

    `multipliers`     : reward scaling per layer (base = 1.0).
    `token_currency`  : side-reward / access token per layer.
    `realm_alignment` : "neutral"/"heaven"/"hell" (drives element resonance).
    `hatch_element`   : element a pet is born with when hatched on the layer.
    `access`          : per-layer { y_offset, requires_soul, token_cost }.
                        base has no requirement; Heaven needs soul >= requires_soul
                        (positive), Hell needs soul <= requires_soul (negative).
]]

return {
    multipliers = {
        base = 1.0,
        heaven_1 = 1.5,
        heaven_2 = 2.0,
        heaven_3 = 2.5,
        hell_1 = 1.5,
        hell_2 = 2.0,
        hell_3 = 2.5,
    },

    token_currency = {
        heaven_1 = "light_tokens",
        heaven_2 = "light_tokens",
        heaven_3 = "light_tokens",
        hell_1 = "shadow_tokens",
        hell_2 = "shadow_tokens",
        hell_3 = "shadow_tokens",
    },

    realm_alignment = {
        base = "neutral",
        heaven_1 = "heaven",
        heaven_2 = "heaven",
        heaven_3 = "heaven",
        hell_1 = "hell",
        hell_2 = "hell",
        hell_3 = "hell",
    },

    hatch_element = {
        base = "neutral",
        heaven_1 = "light",
        heaven_2 = "light",
        heaven_3 = "light",
        hell_1 = "shadow",
        hell_2 = "shadow",
        hell_3 = "shadow",
    },

    -- requires_soul: Heaven layers need soul >= value; Hell layers need soul <=
    -- value (negative). base has no requirement. token_cost is paid in the
    -- layer's token_currency.
    access = {
        base = { y_offset = 0, requires_soul = nil, token_cost = 0 },
        heaven_1 = { y_offset = 2000, requires_soul = 20, token_cost = 100 },
        heaven_2 = { y_offset = 4000, requires_soul = 40, token_cost = 250 },
        heaven_3 = { y_offset = 6000, requires_soul = 60, token_cost = 500 },
        hell_1 = { y_offset = -2000, requires_soul = -20, token_cost = 100 },
        hell_2 = { y_offset = -4000, requires_soul = -40, token_cost = 250 },
        hell_3 = { y_offset = -6000, requires_soul = -60, token_cost = 500 },
    },
}
