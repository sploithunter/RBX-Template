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
    attached = {
        duration = 5, -- default seconds an attached effect lasts (spec.duration overrides)

        -- Per-element, per-category skins. colors = { core, accent }. rate = particles/sec;
        -- rise = float up (buff/heal) vs sink (debuff); size = particle studs. shield uses a
        -- ForceField bubble (transparency/colors). Add grass/ice/desert blocks the same way.
        themes = {
            lava = {
                -- ally damage-up buff: rising embers, hot orange
                buff = { colors = { { 255, 150, 40 }, { 255, 215, 120 } }, rate = 18, rise = true, size = 0.7, light_emission = 0.5 },
                -- enemy debuff (e.g. burn/vuln): sinking ash + dark ember
                debuff = { colors = { { 120, 55, 20 }, { 60, 40, 35 } }, rate = 14, rise = false, size = 0.8, light_emission = 0.2 },
                -- shield bubble: fiery ForceField sphere
                shield = { colors = { { 255, 140, 50 } }, transparency = 0.5, light_emission = 0.4 },
                -- damage aura (burning): dense embers streaming up
                damage = { colors = { { 255, 110, 30 }, { 255, 200, 90 } }, rate = 24, rise = true, size = 0.8, light_emission = 0.6 },
                -- heal aura: warm restorative gold (heal reads warm even from a lava origin)
                heal = { colors = { { 255, 220, 120 }, { 180, 255, 170 } }, rate = 14, rise = true, size = 0.7, light_emission = 0.5 },
            },
        },
    },
}
