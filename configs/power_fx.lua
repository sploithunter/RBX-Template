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

    -- Sound registry — resolves by [phase][element] (like colour resolves by element). A primitive's
    -- anchor picks the phase (self ⇒ cast, target ⇒ impact); the play element picks the clip. A
    -- random variant is chosen. `seconds` = measured clip length (assets/audio/sfx/manifest.txt) —
    -- the VISUAL-TIMING BASELINE; the renderer can match an effect's length to it. GAPS ARE SILENT:
    -- only lava has impact sounds so far (+ a neutral punch); ice/grass/desert impacts play nothing
    -- until more are authored. Uploaded via scripts/upload_audio.js (ids in scripts/audio_ids.json).
    sounds = {
        cast = {
            grass = {
                { id = "rbxassetid://128882337386374", seconds = 2.0 }, -- earth_magic_casting
                { id = "rbxassetid://71912785258456", seconds = 14.0 }, -- rippling_rock_magic (long tail)
            },
            lava = {
                { id = "rbxassetid://72910842757132", seconds = 3.0 }, -- fireball_launch
            },
            ice = {
                { id = "rbxassetid://127988865093771", seconds = 2.0 }, -- icy_wind_casting
            },
            desert = {
                { id = "rbxassetid://108940406293408", seconds = 14.0 }, -- desert_magic_cast_long (long tail)
                { id = "rbxassetid://135624983070582", seconds = 14.0 }, -- desert_magic_long (long tail)
            },
        },
        impact = {
            -- short, varied per-hit fire impacts (clean for repeated casts). The two long-tail
            -- fireball impacts are uploaded + parked for AoE-specific sounds:
            --   fireball_impact_targeted rbxassetid://87632216595220 (14s)
            --   fireball_impact_aoe      rbxassetid://93387065123336 (14s)
            lava = {
                { id = "rbxassetid://76239838028664", seconds = 1.0 }, -- fire_impact_targeted_1
                { id = "rbxassetid://125017003780089", seconds = 1.0 }, -- fire_impact_targeted_2
                { id = "rbxassetid://117318156254750", seconds = 1.0 }, -- fire_impact_targeted_3
            },
            neutral = {
                { id = "rbxassetid://130629017706281", seconds = 0.48 }, -- single_target_punch
            },
        },
    },
}
