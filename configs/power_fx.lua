--[[
    Power FX registry — see docs/PET_REALM_POWER_DATA_MODEL.md §7.1.

    FIRST-VISUAL-TEST scaffold. Named effect primitives mapped onto the EXISTING CombatFX facade
    (`CombatFX.play(spec, ctx)`), so the admin FX-probe plays real effects you can eyeball — no new
    renderer to validate blind. Each primitive picks a CombatFX `pattern`; `color`/`light` default to
    "origin" (the element drives them — CombatFX already resolves per-element colour); `sound` is nil
    until audio is authored (drop SoundIds in later, same placeholder→override pattern as art).

    `probe` drives the admin FX-probe sequence: it steps each listed primitive across every element
    so one click shows the full matrix (Casting on the player, Impact on a dummy).

    Patterns available today (from CombatFX): "pbaoe" (burst around the caster), "st_aoe" (strike at
    a point), "st_attack" (ranged bolt → target), "attached" (a following aura/bubble). Expand the
    primitive list + add bespoke `asset`/`sound` per primitive as real art lands.
]]

return {
    primitives = {
        -- caster-anchored point-blank burst (ground ring + dome + rising motes)
        cast_burst = {
            pattern = "pbaoe",
            anchor = "self",
            color = "origin",
            light = nil,
            sound = nil,
        },
        -- target-anchored strike/eruption at a point (origin="upfront" = slam, no cast beam)
        eruption = {
            pattern = "st_aoe",
            anchor = "target",
            origin = "upfront",
            color = "origin",
            sound = nil,
        },
    },

    -- Admin FX-probe sequence (PowerFXProbe). Steps each primitive across every element.
    probe = {
        elements = { "grass", "lava", "ice", "desert" }, -- canonical CombatFX elements (per-colour)
        casting = { "cast_burst" }, -- primitives played ON the player (Casting / Real modes)
        impact = { "eruption" }, -- primitives played at a dummy (Impact / Real modes)
        step_seconds = 1.6, -- pause between effects so each is watchable
        dummy_distance = 16, -- studs in front of the player to place the impact dummy
    },
}
