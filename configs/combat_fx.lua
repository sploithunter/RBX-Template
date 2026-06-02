--[[
    Combat FX facade — Halo & Horns [PROTOTYPE].

    Config for src/Shared/Effects/CombatFX.lua, the facade that routes a single effect spec
        { pattern, origin, category, element, ... }
    to the right effect module:
      pattern "st_attack" / "st_aoe" / "pbaoe" -> RangedFX / AreaFX (existing)
      pattern "attached"                       -> CombatFX's own follow-an-entity engine (below)

    The `attached` pattern is the new capability: a continual effect that FOLLOWS an entity for a
    duration — auras (buff/debuff/damage/heal) and the shield bubble. Categories:
      buff   -> rising aura on an ally        debuff -> sinking aura on an enemy
      shield -> ForceField bubble on a target damage/heal -> ambient aura
    `element` is the biome origin (grass/lava/ice/desert) — each gets its OWN look (not a recolor).
    This slice ships LAVA end-to-end; other elements fill in the same shape.
]]

return {
    -- Combat element origin (CombatOrigin.resolve). Canonical elements = the four biomes:
    -- grass / lava / ice / desert. Hybrid + configurable:
    --   unify_to_player = false -> each pet fights as its OWN biome origin (collection variety)
    --   unify_to_player = true  -> the whole squad fights as the PLAYER's archetype element
    -- archetype_element maps each archetype's theme onto a canonical element (earth -> grass).
    origin = {
        unify_to_player = false,
        default_element = "grass",
        archetype_element = {
            geomancer = "grass", -- "earth" theme reconciled to grass
            pyromancer = "lava",
            cryomancer = "ice",
            sandwalker = "desert",
        },

        -- Interim pet-element source: until the hatch biome is persisted onto the pet record,
        -- the pet's combat element is read from its PetType (the model already carries this attr).
        -- Tune freely; missing/unknown types fall back to default_element. (Swap to a true
        -- hatch-biome OriginElement attribute later without touching the resolver.)
        pettype_element = {
            bunny = "grass",
            doggy = "grass",
            bear = "grass",
            kitty = "ice",
            dragon = "lava",
            colorado = "lava",
        },

        -- Canonical element -> ranged projectile kind (damage). Melee + heal are routed
        -- separately (RangedFX melee_by_element / heal_<element>). Mirrors CombatFX.RANGED_KIND.
        element_kind = {
            grass = "lightning",
            lava = "fireball",
            ice = "frost",
            desert = "rock",
        },

        -- Element -> armor reskin (configs/combat_fx.lua reskins): when a pet gains a shield in
        -- live combat, CombatAuraController stones it out in its biome armor (grass->stone slate,
        -- lava->cracked lava, ice->glacier, desert->sandstone) under the shield bubble.
        element_reskin = {
            grass = "stone",
            lava = "lava",
            ice = "ice",
            desert = "sand",
        },

        -- Per-element STAT modifiers (CombatOrigin.statMod). These give each origin a combat
        -- identity on top of its look, kept in a TIGHT band so no element dominates (avg ~1.0):
        --   attack_mult — multiplies the pet's outgoing damage (PetFollowService:_mine)
        --   taken_mult  — multiplies incoming damage to the pet (EnemyService); lower = tankier
        -- grass  = neutral baseline (nature/geomancer)
        -- lava   = glass cannon (pyro): hits hardest, also takes the most
        -- ice    = durable controller (cryo): softer hits, tankiest
        -- desert = sturdy skirmisher (sand): slightly under on offense, mildly tanky
        element_stats = {
            grass = { attack_mult = 1.00, taken_mult = 1.00 },
            lava = { attack_mult = 1.15, taken_mult = 1.12 },
            ice = { attack_mult = 0.90, taken_mult = 0.88 },
            desert = { attack_mult = 0.97, taken_mult = 0.95 },
        },
    },

    -- Armor reskins: temporarily retexture the WHOLE pet for a defensive (shield) effect — the
    -- four armor origins. CombatFX.attach reads spec.reskin = one of these. material = a Roblox
    -- Material name (real materials sell each look); color = the tint. (Variant pets re-apply
    -- their own colour each frame so the Material reads on them; plain pets reskin fully.)
    --   stone -> Geomancer (stone_skin)   lava -> Pyromancer (ember_ward)
    --   ice   -> Cryomancer (ice_armor)   sand -> Sandwalker (dune_shield)
    reskins = {
        stone = { material = "Slate", color = { 120, 114, 105 } },
        lava = { material = "CrackedLava", color = { 95, 45, 30 } }, -- molten crust w/ glowing cracks
        ice = { material = "Glacier", color = { 190, 228, 255 } },
        sand = { material = "Sandstone", color = { 214, 184, 130 } },
    },

    attached = {
        duration = 5, -- default seconds an attached effect lasts (spec.duration overrides)

        -- Per-element, per-category skins. colors = { core, accent }. rate = particles/sec;
        -- rise = float up (buff/heal) vs sink (debuff); size = particle studs. shield uses a
        -- ForceField bubble (transparency/colors). Add grass/ice/desert blocks the same way.
        themes = {
            lava = {
                -- ally damage-up buff: rising embers, hot orange
                buff = {
                    colors = { { 255, 150, 40 }, { 255, 215, 120 } },
                    rate = 18,
                    rise = true,
                    size = 0.7,
                    light_emission = 0.5,
                },
                -- enemy debuff (e.g. burn/vuln): sinking ash + dark ember
                debuff = {
                    colors = { { 120, 55, 20 }, { 60, 40, 35 } },
                    rate = 14,
                    rise = false,
                    size = 0.8,
                    light_emission = 0.2,
                },
                -- shield bubble: fiery ForceField sphere
                shield = { colors = { { 255, 140, 50 } }, transparency = 0.5, light_emission = 0.4 },
                -- damage aura (burning): dense embers streaming up
                damage = {
                    colors = { { 255, 110, 30 }, { 255, 200, 90 } },
                    rate = 24,
                    rise = true,
                    size = 0.8,
                    light_emission = 0.6,
                },
                -- heal aura: warm restorative gold (heal reads warm even from a lava origin)
                heal = {
                    colors = { { 255, 220, 120 }, { 180, 255, 170 } },
                    rate = 14,
                    rise = true,
                    size = 0.7,
                    light_emission = 0.5,
                },
            },
            grass = {
                -- nature growth — rising leafy green motes
                buff = {
                    colors = { { 90, 210, 80 }, { 180, 245, 130 } },
                    rate = 18,
                    rise = true,
                    size = 0.8,
                    light_emission = 0.35,
                },
                -- wither — sinking sickly brown/yellow
                debuff = {
                    colors = { { 110, 130, 50 }, { 70, 80, 40 } },
                    rate = 14,
                    rise = false,
                    size = 0.8,
                    light_emission = 0.1,
                },
                shield = { colors = { { 110, 220, 90 } }, transparency = 0.5, light_emission = 0.3 },
                damage = {
                    colors = { { 120, 230, 90 }, { 200, 255, 140 } },
                    rate = 22,
                    rise = true,
                    size = 0.7,
                    light_emission = 0.4,
                },
                heal = {
                    colors = { { 130, 240, 130 }, { 220, 255, 200 } },
                    rate = 14,
                    rise = true,
                    size = 0.7,
                    light_emission = 0.5,
                },
            },
            ice = {
                -- frost — rising pale crystals
                buff = {
                    colors = { { 150, 220, 255 }, { 235, 250, 255 } },
                    rate = 18,
                    rise = true,
                    size = 0.7,
                    light_emission = 0.45,
                },
                -- chill — sinking deep-blue mist
                debuff = {
                    colors = { { 60, 110, 170 }, { 120, 160, 200 } },
                    rate = 14,
                    rise = false,
                    size = 0.9,
                    light_emission = 0.2,
                },
                shield = {
                    colors = { { 170, 225, 255 } },
                    transparency = 0.45,
                    light_emission = 0.45,
                },
                damage = {
                    colors = { { 140, 215, 255 }, { 225, 245, 255 } },
                    rate = 22,
                    rise = true,
                    size = 0.8,
                    light_emission = 0.55,
                },
                heal = {
                    colors = { { 190, 245, 220 }, { 230, 255, 235 } },
                    rate = 14,
                    rise = true,
                    size = 0.7,
                    light_emission = 0.5,
                },
            },
            desert = {
                -- sand uplift — rising tan grains (earthy, low glow)
                buff = {
                    colors = { { 215, 185, 120 }, { 245, 225, 170 } },
                    rate = 18,
                    rise = true,
                    size = 0.8,
                    light_emission = 0.15,
                },
                -- sandblast debuff — sinking dusty brown
                debuff = {
                    colors = { { 150, 120, 80 }, { 90, 70, 50 } },
                    rate = 16,
                    rise = false,
                    size = 0.9,
                    light_emission = 0.1,
                },
                shield = {
                    colors = { { 205, 175, 120 } },
                    transparency = 0.4,
                    light_emission = 0.15,
                },
                damage = {
                    colors = { { 200, 165, 110 }, { 235, 205, 150 } },
                    rate = 20,
                    rise = true,
                    size = 0.85,
                    light_emission = 0.2,
                },
                heal = {
                    colors = { { 235, 220, 150 }, { 215, 255, 190 } },
                    rate = 14,
                    rise = true,
                    size = 0.7,
                    light_emission = 0.4,
                },
            },
        },
    },
}
