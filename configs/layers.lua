--[[
    Layer config — Halo & Horns [PROTOTYPE].

    Stacked vertical layers (base / Heaven 1-2 / Hell 1-2). Phase 0 needs only the
    reward economics (Feature 4): each layer scales rewards by a multiplier, and
    Heaven/Hell layers grant a side-reward token currency. Geometry, Soul/token
    access gating, and portals come in Phase 2 (Feature 3).

    `multipliers`    : reward scaling per layer (base = 1.0).
    `token_currency` : side-reward token by layer — Light only in Heaven, Shadow
                       only in Hell, none in base.
]]

return {
    multipliers = {
        base = 1.0,
        heaven_1 = 1.5,
        heaven_2 = 2.0,
        hell_1 = 1.5,
        hell_2 = 2.0,
    },

    token_currency = {
        heaven_1 = "light_tokens",
        heaven_2 = "light_tokens",
        hell_1 = "shadow_tokens",
        hell_2 = "shadow_tokens",
    },
}
