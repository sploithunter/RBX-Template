--[[
    Combat tuning + spawners — Halo & Horns [PROTOTYPE] (Feature 10).

    auto_target            — default pet targeting mode ("nearest").
    group_scaling          — enemy HP scaling for multiplayer (Feature 18):
                             scaledHp = baseHp * (1 + per_extra_player * (partySize - 1)).
    pet_down_threshold_factor — a pet has no HP stat; it can absorb
                             power * this_factor accumulated enemy damage before
                             it is downed -> Spirit Form (Feature 7) -> auto-return
                             from the active squad (Feature 9).
    spawners               — zoneId -> { biome, enemies = { {id, count}, ... } }.
                             Marker placement is authored map work ([studio]).

    Read by CombatService; pure math lives in `src/Shared/Game/CombatMath.lua`.
]]

return {
    auto_target = "nearest",

    group_scaling = {
        per_extra_player = 0.5,
    },

    pet_down_threshold_factor = 1.0,

    spawners = {
        hell_1_lava = {
            biome = "lava",
            enemies = {
                { id = "lava_imp", count = 4 },
                { id = "ember_brute", count = 1 },
            },
        },
    },
}
