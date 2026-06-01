--[[
    AreaFX — client-side AREA (AoE) effect library for Halo & Horns.

    The companion to RangedFX (single-target bolts). EIGHT distinct effects — two per element,
    each with its own visual motif so no two look alike:

      grass  self = Bloom      (blades sprout up in a ring)      targeted = Thornfield (angled thorns erupt)
      desert self = Sandstorm  (rising swirl of sand)            targeted = Quake      (ground cracks + burst)
      ice    self = Frost nova (radial ice crystals + ring)      targeted = Icefall    (icicles rain + column)
      lava   self = Fire ring  (flame columns circle the caster) targeted = Meteor     (ball drops + shockwave)

    Themed by configs/area_fx.lua (color / color2 / material per element). Targeted variants lead
    with a cast tell (beam from caster + ground telegraph) before the eruption. Purely visual.

      AreaFX.Play(config, element, "self",     originPos)
      AreaFX.Play(config, element, "targeted", originPos, targetPos)
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AreaFX = {}

local OUT = Enum.EasingStyle.Quad
local DIR_OUT = Enum.EasingDirection.Out
local DIR_IN = Enum.EasingDirection.In

local function ti(t, dir)
    return TweenInfo.new(t, OUT, dir or DIR_OUT)
end

local function toColor(rgb, fallback)
    if typeof(rgb) == "Color3" then
        return rgb
    end
    if type(rgb) == "table" and rgb[1] then
        return Color3.fromRGB(rgb[1], rgb[2] or 0, rgb[3] or 0)
    end
    return fallback or Color3.fromRGB(255, 255, 255)
end

local function materialOf(name)
    local ok, mat = pcall(function()
        return Enum.Material[name]
    end)
    return (ok and mat) or Enum.Material.Neon
end

local function fxFolder()
    local f = Workspace:FindFirstChild("Effects")
    if not f then
        f = Instance.new("Folder")
        f.Name = "Effects"
        f.Parent = Workspace
    end
    return f
end

local function newPart(shape, mat, color, transparency)
    local p = Instance.new("Part")
    p.Shape = shape
    p.Material = mat
    p.Color = color
    p.Transparency = transparency or 0
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CastShadow = false
    p.Parent = fxFolder()
    return p
end

local function tween(inst, t, props, dir)
    TweenService:Create(inst, ti(t, dir), props):Play()
    Debris:AddItem(inst, t + 0.15)
end

-- ===== Shared primitives =====

-- Flat disc on the ground that expands + fades (ring / telegraph / shockwave).
local function groundRing(pos, color, mat, diameter, life, startTransparency)
    local ring = newPart(Enum.PartType.Cylinder, mat, color, startTransparency or 0.15)
    ring.Size = Vector3.new(0.3, 1, 1)
    ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
    tween(ring, life, { Size = Vector3.new(0.2, diameter, diameter), Transparency = 1 })
end

-- Translucent dome that swells over the point + fades.
local function dome(pos, color, mat, radius, life, startTransparency)
    local d = newPart(Enum.PartType.Ball, mat, color, startTransparency or 0.6)
    d.Size = Vector3.new(1, 1, 1)
    d.CFrame = CFrame.new(pos)
    tween(d, life, { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 })
end

-- Vertical column that strikes/rises at the point + thins out.
local function column(pos, color, mat, height, life)
    local diam = height * 0.22
    local c = newPart(Enum.PartType.Cylinder, mat, color, 0.1)
    c.Size = Vector3.new(1, diam, diam)
    c.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
    tween(c, life, {
        Size = Vector3.new(height, diam * 0.3, diam * 0.3),
        Transparency = 1,
        CFrame = CFrame.new(pos + Vector3.new(0, height * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
    })
end

-- Slanted beam between two points (the cast line).
local function beam(a, b, color, mat, thickness, life)
    local dist = (b - a).Magnitude
    if dist < 0.1 then
        return
    end
    local bm = newPart(Enum.PartType.Cylinder, mat, color, 0)
    bm.Size = Vector3.new(dist, thickness, thickness)
    bm.CFrame = CFrame.lookAt(a:Lerp(b, 0.5), b) * CFrame.Angles(0, math.rad(90), 0)
    tween(bm, life, { Transparency = 1, Size = Vector3.new(dist, 0.05, 0.05) })
end

-- Low ground debris flung outward (rubble / sparks).
local function debris(pos, c1, c2, mat, count, spread, life)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2 + math.random() * 0.6
        local dir = Vector3.new(math.cos(ang), 0.3 + math.random() * 0.5, math.sin(ang)).Unit
        local b = newPart(Enum.PartType.Ball, mat, (i % 2 == 0) and c1 or c2, 0)
        local s = spread * 0.12
        b.Size = Vector3.new(s, s, s)
        b.CFrame = CFrame.new(pos)
        tween(b, life, {
            CFrame = CFrame.new(pos + dir * (spread * (0.6 + math.random() * 0.7))),
            Transparency = 1,
            Size = Vector3.new(0.05, 0.05, 0.05),
        })
    end
end

-- ===== Distinct motif primitives =====

-- Vertical bars that grow up from the ground in a ring (grass blades / flame columns).
local function pillarsRing(pos, color, mat, count, radius, height, width, life)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2
        local base = pos + Vector3.new(math.cos(ang) * radius, 0, math.sin(ang) * radius)
        local p = newPart(Enum.PartType.Block, mat, color, 0.1)
        p.Size = Vector3.new(width, 0.4, width)
        p.CFrame = CFrame.new(base + Vector3.new(0, 0.2, 0))
        tween(p, life, {
            Size = Vector3.new(width * 0.4, height, width * 0.4),
            CFrame = CFrame.new(base + Vector3.new(0, height * 0.5, 0)),
            Transparency = 1,
        })
    end
end

-- Elongated spikes pointing outward+up in a ring (ice crystals / thorns).
local function radialSpikes(pos, color, mat, count, radius, len, life, tiltDeg)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2 + math.random() * 0.2
        local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
        local base = pos + dir * (radius * 0.5) + Vector3.new(0, 0.3, 0)
        local face = CFrame.lookAt(base, base + dir) * CFrame.Angles(math.rad(-(tiltDeg or 30)), 0, 0)
        local p = newPart(Enum.PartType.Block, mat, color, 0.1)
        p.Size = Vector3.new(len * 0.18, len * 0.18, 0.4)
        p.CFrame = face
        -- grow along forward (-Z) so it juts outward
        tween(p, life, {
            Size = Vector3.new(len * 0.18, len * 0.18, len),
            CFrame = face * CFrame.new(0, 0, -len * 0.45),
            Transparency = 1,
        })
    end
end

-- Motes that rise in a swirl (sandstorm / embers).
local function swirlMotes(pos, color, mat, count, radius, height, life)
    for i = 1, count do
        local ang0 = (i / count) * math.pi * 2 + math.random() * 0.5
        local r = radius * (0.5 + math.random() * 0.5)
        local start = pos + Vector3.new(math.cos(ang0) * r, 0.5, math.sin(ang0) * r)
        local ang1 = ang0 + 2.2 -- swirl ~125deg as it rises
        local dest = pos + Vector3.new(math.cos(ang1) * r * 0.7, height * (0.6 + math.random() * 0.5), math.sin(ang1) * r * 0.7)
        local m = newPart(Enum.PartType.Ball, mat, color, 0.2)
        local s = 0.3 + math.random() * 0.4
        m.Size = Vector3.new(s, s, s)
        m.CFrame = CFrame.new(start)
        tween(m, life, { CFrame = CFrame.new(dest), Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) })
    end
end

-- Flat cracks radiating along the ground (quake).
local function groundCracks(pos, color, mat, count, len, life)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2 + math.random() * 0.3
        local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
        local g = pos + Vector3.new(0, -0.1, 0)
        local face = CFrame.lookAt(g + dir * 0.5, g + dir)
        local p = newPart(Enum.PartType.Block, mat, color, 0)
        p.Size = Vector3.new(0.35, 0.2, 0.4)
        p.CFrame = face
        tween(p, life, {
            Size = Vector3.new(0.35, 0.2, len),
            CFrame = face * CFrame.new(0, 0, -len * 0.45),
            Transparency = 1,
        })
    end
end

-- Bits that fall from above onto the point (icicles / meteor shards). elongated -> tall slivers.
local function fallingBits(pos, color, mat, count, fromHeight, spread, life, elongated)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2 + math.random()
        local off = Vector3.new(math.cos(ang) * spread * math.random(), 0, math.sin(ang) * spread * math.random())
        local p = newPart(Enum.PartType.Block, mat, color, 0.05)
        p.Size = elongated and Vector3.new(0.4, 2.2, 0.4) or Vector3.new(0.6, 0.6, 0.6)
        p.CFrame = CFrame.new(pos + off + Vector3.new(0, fromHeight, 0))
        tween(p, life, { CFrame = CFrame.new(pos + off + Vector3.new(0, 0.3, 0)), Transparency = 1 }, DIR_IN)
    end
end

-- A ring of REAL Roblox Fire (not procedural) around the point — the lava look.
local function fireRing(pos, count, radius, life, color, color2)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2
        local holder = Instance.new("Part")
        holder.Transparency = 1
        holder.Size = Vector3.new(1, 1, 1)
        holder.Anchored = true
        holder.CanCollide = false
        holder.CanQuery = false
        holder.CastShadow = false
        holder.CFrame = CFrame.new(pos + Vector3.new(math.cos(ang) * radius, 0.5, math.sin(ang) * radius))
        holder.Parent = fxFolder()
        local fire = Instance.new("Fire")
        fire.Size = math.max(4, radius * 0.7)
        fire.Heat = 10
        fire.Color = color
        fire.SecondaryColor = color2
        fire.Parent = holder
        local light = Instance.new("PointLight")
        light.Color = color
        light.Brightness = 3
        light.Range = radius
        light.Parent = holder
        TweenService:Create(fire, ti(life), { Size = 0 }):Play()
        TweenService:Create(light, ti(life), { Brightness = 0 }):Play()
        Debris:AddItem(holder, life + 0.4)
    end
end

-- ===== The eight effects =====

local EFFECTS = {
    -- GRASS self: Bloom — green blades sprout up in a ring + a soft growth dome.
    grass_self = function(pos, c1, c2, mat, radius, life)
        groundRing(pos, c1, mat, radius * 2, life)
        pillarsRing(pos, c1, mat, 12, radius * 0.85, radius * 0.5, 0.5, life)
        dome(pos, c1, mat, radius * 0.6, life, 0.7)
        swirlMotes(pos, c2, mat, 8, radius, radius * 0.6, life + 0.1)
    end,
    -- GRASS targeted: Thornfield — angled thorns erupt outward from the point.
    grass_targeted = function(pos, c1, c2, mat, radius, life)
        radialSpikes(pos, c1, mat, 14, radius, radius * 0.6, life, 55)
        groundRing(pos, c2, mat, radius * 2, life)
        debris(pos, c1, c2, mat, 10, radius, life)
    end,
    -- DESERT self: Sandstorm — a rising swirl of sand + a faint dust ring.
    desert_self = function(pos, c1, c2, mat, radius, life)
        groundRing(pos, c1, mat, radius * 2, life, 0.55)
        swirlMotes(pos, c1, mat, 24, radius, radius * 0.8, life + 0.2)
        swirlMotes(pos, c2, mat, 12, radius * 0.7, radius * 0.6, life + 0.1)
    end,
    -- DESERT targeted: Quake — ground cracks shoot out + rubble bursts up.
    desert_targeted = function(pos, c1, c2, mat, radius, life)
        groundCracks(pos, c2, mat, 10, radius * 1.8, life)
        debris(pos, c1, c2, mat, 18, radius, life)
        dome(pos, c1, mat, radius * 0.5, life, 0.75)
        groundRing(pos, c1, mat, radius * 1.6, life, 0.5)
    end,
    -- ICE self: Frost nova — radial ice crystals form in a ring + a pale flat nova.
    ice_self = function(pos, c1, c2, mat, radius, life)
        groundRing(pos, c2, mat, radius * 2.2, life)
        radialSpikes(pos, c1, mat, 12, radius * 0.7, radius * 0.35, life, 22)
        dome(pos, c2, mat, radius * 0.55, life, 0.7)
    end,
    -- ICE targeted: Icefall — icicles rain down onto the point + an ice column.
    ice_targeted = function(pos, c1, c2, mat, radius, life)
        fallingBits(pos, c2, mat, 12, radius * 1.6, radius, life, true)
        column(pos, c1, mat, radius * 1.4, life * 0.8)
        groundRing(pos, c2, mat, radius * 2, life)
        debris(pos, c1, c2, mat, 10, radius, life)
    end,
    -- LAVA self: Fire ring — a circle of REAL fire around the caster + ember swirl.
    lava_self = function(pos, c1, c2, mat, radius, life)
        groundRing(pos, c1, mat, radius * 1.7, life)
        fireRing(pos, 10, radius * 0.85, life + 0.4, c1, c2)
        swirlMotes(pos, c2, mat, 12, radius, radius * 0.7, life)
    end,
    -- LAVA targeted: Meteor — a ball drops from above, then real fire + shockwave erupt.
    lava_targeted = function(pos, c1, c2, mat, radius, life)
        local meteor = newPart(Enum.PartType.Ball, mat, c1, 0)
        local sz = radius * 0.5
        meteor.Size = Vector3.new(sz, sz, sz)
        meteor.CFrame = CFrame.new(pos + Vector3.new(0, radius * 2, 0))
        TweenService:Create(meteor, TweenInfo.new(0.18, OUT, DIR_IN), { CFrame = CFrame.new(pos) }):Play()
        Debris:AddItem(meteor, 0.4)
        task.delay(0.18, function()
            meteor:Destroy()
            fireRing(pos, 10, radius * 0.9, life + 0.4, c1, c2) -- fire around the impact zone
            column(pos, c2, mat, radius * 1.8, life * 0.7)
            groundRing(pos, c1, mat, radius * 2.6, life)
            groundRing(pos, c2, mat, radius * 3.6, life * 1.2)
            debris(pos, c1, c2, mat, 18, radius * 1.4, life)
        end)
    end,
}

-- Targeted variants lead with a cast tell (beam from caster + ground telegraph), then run.
local function castTell(c2, mat, origin, target, radius, castTime)
    beam(origin + Vector3.new(0, 2, 0), target + Vector3.new(0, 1, 0), c2, mat, 0.35, castTime + 0.08)
    groundRing(target, c2, mat, radius * 1.6, castTime + 0.12, 0.55)
end

-- Play an area effect. element keys config.themes; variant is "self" or "targeted".
function AreaFX.Play(config, element, variant, originPos, targetPos)
    config = type(config) == "table" and config or {}
    local theme = config.themes and config.themes[element]
    if not theme then
        return false
    end
    variant = (variant == "targeted") and "targeted" or "self"
    local fn = EFFECTS[element .. "_" .. variant]
    if not fn then
        return false
    end

    local c1 = toColor(theme.color)
    local c2 = toColor(theme.color2, c1)
    local mat = materialOf(theme.material)
    local params = (variant == "targeted") and (config.targeted or {}) or (config.self or {})
    local radius = tonumber(params.radius) or 10
    local life = tonumber(params.duration) or 0.6

    if variant == "targeted" then
        local target = targetPos or originPos
        local castTime = math.max(0.05, tonumber(params.cast_time) or 0.18)
        castTell(c2, mat, originPos, target, radius, castTime)
        task.delay(castTime, function()
            fn(target, c1, c2, mat, radius, life)
        end)
    else
        fn(originPos, c1, c2, mat, radius, life)
    end
    return true
end

return AreaFX
