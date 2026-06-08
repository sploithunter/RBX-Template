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
        -- caster-anchored point-blank burst (ground RING + dome + rising motes) — reads as AoE
        cast_burst = {
            pattern = "pbaoe",
            anchor = "self",
            color = "origin",
            light = nil,
            sound = nil,
        },
        -- caster-anchored EMISSION off the player's body (attached element motes streaming up, brief) —
        -- the default single-target cast tell: small, "emits from the player", NOT a ground AoE. Uses
        -- the per-element `damage` aura theme (embers / leaves / frost / sand), short-lived.
        cast_emit = {
            pattern = "attached",
            anchor = "self",
            category = "damage",
            duration = 0.7,
            color = "origin",
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
        -- caster-anchored rising BUFF aura (attached, follows the entity ~2s) — for buffs/holds
        aura = {
            pattern = "attached",
            anchor = "self",
            category = "buff",
            duration = 2.0,
            color = "origin",
            soundPhase = "buff", -- plays the power-up clip (neutral) rather than the elemental cast
            sound = nil,
        },
        -- caster-anchored SHIELD bubble (attached ForceField look) — for absorbs/wards
        shield_bubble = {
            pattern = "attached",
            anchor = "self",
            category = "shield",
            duration = 2.0,
            color = "origin",
            soundPhase = "shield", -- plays the force-field-raise clip (neutral)
            sound = nil,
        },
        -- ranged BOLT from caster → target (projectile; element picks fireball/frost/rock/lightning)
        ranged_bolt = {
            pattern = "st_attack",
            anchor = "target",
            color = "origin",
            sound = nil,
        },
        -- caster-anchored HEAL nova (green heal pulse via the AreaFX "heal" skin)
        heal_nova = {
            pattern = "pbaoe",
            anchor = "self",
            category = "heal",
            color = "origin",
            sound = nil,
        },

        -- ===== Palette expansion (cheap unlocks over the existing renderers) =====
        -- CAST tells -------------------------------------------------------------------------------
        -- sinking dark motes gathering on the body (debuff aura, rise=false) — an ominous CURSE cast
        cast_channel = {
            pattern = "attached",
            anchor = "self",
            category = "debuff",
            duration = 0.8,
            color = "origin",
            sound = nil,
        },
        -- the ground ERUPTS in a column under the caster (st_aoe at self, no beam) — a heavy/summoning
        -- cast that reads bigger than cast_emit but is still centred on the player
        cast_geyser = {
            pattern = "st_aoe",
            anchor = "self",
            origin = "upfront",
            color = "origin",
            sound = nil,
        },
        -- IMPACTS ----------------------------------------------------------------------------------
        -- a lingering bubbling POOL at the target (st_aoe pit variant, ~4s) — burning/scorched ground
        -- for DoT brands (Mark of Flame, Wildfire). Element-tinted.
        brand_pool = {
            pattern = "st_aoe",
            anchor = "target",
            origin = "upfront",
            variant = "pit",
            color = "origin",
            sound = nil,
        },
        -- bare point-bursts from the RangedFX impact library (no projectile), element-coloured:
        shatter = { pattern = "impact", anchor = "target", impact = "shatter", color = "origin" }, -- ice ring + glass shards
        dust_burst = { pattern = "impact", anchor = "target", impact = "dust", color = "origin" }, -- desert dust plume
        heavy_slam = { pattern = "impact", anchor = "target", impact = "big", color = "origin" }, -- heavy concussion
        -- explicit projectiles (force a specific bolt regardless of element):
        boulder = { pattern = "st_attack", anchor = "target", projectile = "rock", color = "origin" }, -- thrown rock model + dust
        frost_shard = { pattern = "st_attack", anchor = "target", projectile = "ice_shard", color = "origin" }, -- icy shard + shatter
        arc_bolt = { pattern = "st_attack", anchor = "target", projectile = "lightning", color = "origin" }, -- lightning arc
    },

    -- Admin FX-probe sequence (PowerFXProbe). Steps each primitive across every element.
    probe = {
        elements = { "grass", "lava", "ice", "desert" }, -- canonical CombatFX elements (per-colour)
        casting = { "cast_emit", "cast_geyser", "cast_channel", "cast_burst", "aura", "shield_bubble" }, -- played ON the player
        impact = { "eruption", "brand_pool", "shatter", "dust_burst", "heavy_slam", "ranged_bolt", "boulder", "frost_shard", "arc_bolt" }, -- played at a dummy
        step_seconds = 2.8, -- pause between effects so each is watchable (slowed for inspection)
        dummy_distance = 16, -- studs in front of the player to place the impact dummy
    },

    -- Sound registry — resolves by [phase][element] (like colour resolves by element). A primitive's
    -- anchor picks the phase (self ⇒ cast, target ⇒ impact); the play element picks the clip. A
    -- random variant is chosen. `seconds` = measured clip length (assets/audio/sfx/manifest.txt) —
    -- the VISUAL-TIMING BASELINE; the renderer can match an effect's length to it. PowerSound falls
    -- back to `neutral` when an element has no clip for a phase, so non-elemental clips (force-field,
    -- power-up, generic cast) play under any origin. GAPS ARE STILL SILENT where neither exists.
    -- buff/shield phases ride the aura/shield primitives. ambient = LOOPS (zone/sustained), not wired
    -- to the one-shot probe. Uploaded via scripts/upload_audio.js (ids in scripts/audio_ids.json).
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
            neutral = {
                { id = "rbxassetid://128240762228140", seconds = 2.0 }, -- cartoony_spell_cast (generic)
            },
        },
        impact = {
            -- the two long-tail fireball impacts are uploaded + parked for AoE-specific sounds:
            --   fireball_impact_targeted rbxassetid://87632216595220 (14s)
            --   fireball_impact_aoe      rbxassetid://93387065123336 (14s)
            lava = {
                { id = "rbxassetid://76239838028664", seconds = 1.0 }, -- fire_impact_targeted_1
                { id = "rbxassetid://125017003780089", seconds = 1.0 }, -- fire_impact_targeted_2
                { id = "rbxassetid://117318156254750", seconds = 1.0 }, -- fire_impact_targeted_3
            },
            grass = {
                { id = "rbxassetid://99084444950159", seconds = 8.0 }, -- earthen_impact (long-ish tail)
                { id = "rbxassetid://98891214914756", seconds = 8.0 }, -- deep_earthen_impact (long-ish)
            },
            ice = {
                { id = "rbxassetid://96567599651432", seconds = 3.0 }, -- freezing_crack_single_target
            },
            desert = {
                { id = "rbxassetid://121215976414474", seconds = 2.0 }, -- arrow_impact_desert
            },
            neutral = {
                { id = "rbxassetid://130629017706281", seconds = 0.48 }, -- single_target_punch
            },
        },
        -- buff activation (rides the `aura` primitive; neutral ⇒ plays under any origin)
        buff = {
            neutral = {
                { id = "rbxassetid://131694228494794", seconds = 1.0 }, -- power_up_stronger
            },
        },
        -- shield raise (rides the `shield_bubble` primitive)
        shield = {
            neutral = {
                { id = "rbxassetid://125923588431694", seconds = 1.0 }, -- force_field_raise
            },
        },
        -- ambient LOOPS — registered for zone ambience / sustained holds; NOT one-shot. A looping
        -- player (zone or persistent-effect driven) would use these; the FX-probe doesn't.
        ambient = {
            neutral = {
                { id = "rbxassetid://81826046653344", seconds = 3.0 }, -- machine_hum
            },
            ice = {
                { id = "rbxassetid://96154251218473", seconds = 3.0 }, -- deep_winter_wind
            },
        },
    },
}
