--[[
    Area (AoE) effects — Halo & Horns [PROTOTYPE].

    Config for src/Shared/Effects/AreaFX.lua. Two variants per element:
      self     — a burst AROUND the caster (ground ring + dome + rising motes)
      targeted — a strike AT a point with a cast beam + ground telegraph, then an eruption

    Elements: grass / desert / ice / lava. `color` is the core, `color2` the accent/motes.
    `material` is the part Material name (Neon glows; Glass = icy; SmoothPlastic = earthy sand).
    Read client-side; purely visual (gameplay/damage live elsewhere).
]]

return {
    -- Self burst (point-blank AoE around the caster).
    self = {
        radius = 12, -- studs the ground ring/dome reach
        rise = 8, -- how high the motes float
        motes = 16,
        duration = 0.6,
    },
    -- Targeted strike (cast at a ground point).
    targeted = {
        radius = 9,
        cast_time = 0.18, -- seconds of cast beam + telegraph before the eruption
        rise = 7,
        motes = 12,
        debris = 16,
        duration = 0.6,
    },

    themes = {
        -- Grassy nature burst — green growth + leafy motes.
        grass = { color = { 90, 200, 80 }, color2 = { 170, 240, 130 }, material = "Neon" },
        -- Desert sandstorm — tan dust + rubble (earthy, non-glowing).
        desert = { color = { 205, 180, 130 }, color2 = { 150, 125, 90 }, material = "SmoothPlastic" },
        -- Ice nova — pale blue + white, glassy.
        ice = { color = { 150, 220, 255 }, color2 = { 235, 250, 255 }, material = "Glass" },
        -- Lava eruption — orange/red molten glow.
        lava = { color = { 255, 110, 30 }, color2 = { 255, 200, 90 }, material = "Neon" },
    },
}
