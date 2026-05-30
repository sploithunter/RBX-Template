--[[
    Element resonance — Halo & Horns [PROTOTYPE] (Feature 6).

    Multiplier applied to a pet's power based on its element and the realm
    alignment of the player's current biome/layer. Light and Shadow are STRONGER
    in the opposing realm (dominance); Chaotic is flat across realms; Neutral is
    flat 1.0. Read by `src/Shared/Game/ElementResonance.lua` and `PowerFormula`.
]]

return {
    -- resonance[petElement][realmAlignment] -> multiplier
    resonance = {
        light = { heaven = 1.2, hell = 1.5, neutral = 1.0 },
        shadow = { heaven = 1.5, hell = 1.2, neutral = 1.0 },
        chaotic = { heaven = 1.3, hell = 1.3, neutral = 1.3 },
        neutral = { heaven = 1.0, hell = 1.0, neutral = 1.0 },
    },
}
