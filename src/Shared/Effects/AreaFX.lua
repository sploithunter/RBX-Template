--[[
    AreaFX — client-side AREA (AoE) effect library for Halo & Horns.

    The companion to RangedFX (single-target bolts). Two variants per element, themed by
    configs/area_fx.lua:

      self     — a burst AROUND a point (the caster): expanding ground ring + dome + rising
                 motes. Use for self / point-blank AoE.
      targeted — a strike AT a point with a cast tell: a cast beam (origin -> target) + a
                 ground telegraph ring, then (after cast_time) the eruption — ring + dome +
                 a descending column + ground debris + motes.

    Elements (themes): grass / desert / ice / lava. Pure visual; gameplay/damage is elsewhere.

      AreaFX.Play(config, element, "self",     originPos)            -- around originPos
      AreaFX.Play(config, element, "targeted", originPos, targetPos) -- cast at targetPos
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AreaFX = {}

local QUAD_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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

-- A flat disc on the ground that expands outward + fades (ground ring / shockwave / telegraph).
local function groundRing(pos, color, mat, diameter, life, startTransparency)
    local ring = newPart(Enum.PartType.Cylinder, mat, color, startTransparency or 0.2)
    ring.Size = Vector3.new(0.4, 1, 1) -- X = thin height; Y/Z = diameter
    ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)) -- lay flat
    TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(0.2, diameter, diameter),
        Transparency = 1,
    }):Play()
    Debris:AddItem(ring, life + 0.1)
end

-- A translucent dome (ball) that swells over the point + fades — the AoE bubble.
local function dome(pos, color, mat, radius, life)
    local d = newPart(Enum.PartType.Ball, mat, color, 0.45)
    d.Size = Vector3.new(1, 1, 1)
    d.CFrame = CFrame.new(pos)
    TweenService:Create(d, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(radius * 2, radius * 2, radius * 2),
        Transparency = 1,
    }):Play()
    Debris:AddItem(d, life + 0.1)
end

-- A vertical column that strikes/rises at the point + thins out (the eruption beam).
local function column(pos, color, mat, height, life)
    local diam = height * 0.22
    local c = newPart(Enum.PartType.Cylinder, mat, color, 0.1)
    c.Size = Vector3.new(1, diam, diam)
    c.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
    TweenService:Create(c, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(height, diam * 0.3, diam * 0.3),
        Transparency = 1,
        CFrame = CFrame.new(pos + Vector3.new(0, height * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
    }):Play()
    Debris:AddItem(c, life + 0.1)
end

-- A slanted beam between two points (the cast line from caster to target).
local function beam(a, b, color, mat, thickness, life)
    local dist = (b - a).Magnitude
    if dist < 0.1 then
        return
    end
    local bm = newPart(Enum.PartType.Cylinder, mat, color, 0)
    bm.Size = Vector3.new(dist, thickness, thickness)
    bm.CFrame = CFrame.lookAt(a:Lerp(b, 0.5), b) * CFrame.Angles(0, math.rad(90), 0)
    TweenService:Create(bm, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Transparency = 1,
        Size = Vector3.new(dist, 0.05, 0.05),
    }):Play()
    Debris:AddItem(bm, life + 0.1)
end

-- Particles that rise up from around the ring + fade (leaves / embers / snow / sand motes).
local function motes(pos, color, mat, count, radius, rise, life)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2 + math.random() * 0.8
        local r = radius * (0.4 + math.random() * 0.6)
        local start = pos + Vector3.new(math.cos(ang) * r, 0.5, math.sin(ang) * r)
        local m = newPart(Enum.PartType.Ball, mat, color, 0.1)
        local s = 0.3 + math.random() * 0.4
        m.Size = Vector3.new(s, s, s)
        m.CFrame = CFrame.new(start)
        local dest = start + Vector3.new(math.random() - 0.5, rise * (0.6 + math.random() * 0.6), math.random() - 0.5)
        TweenService:Create(m, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            CFrame = CFrame.new(dest),
            Transparency = 1,
            Size = Vector3.new(0.05, 0.05, 0.05),
        }):Play()
        Debris:AddItem(m, life + 0.1)
    end
end

-- Low ground debris flung outward (rubble / sparks at the eruption).
local function debris(pos, c1, c2, mat, count, spread, life)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2 + math.random() * 0.6
        local dir = Vector3.new(math.cos(ang), 0.25 + math.random() * 0.4, math.sin(ang)).Unit
        local b = newPart(Enum.PartType.Ball, mat, (i % 2 == 0) and c1 or c2, 0)
        local s = spread * 0.12
        b.Size = Vector3.new(s, s, s)
        b.CFrame = CFrame.new(pos)
        local dest = pos + dir * (spread * (0.6 + math.random() * 0.7))
        TweenService:Create(b, QUAD_OUT, {
            CFrame = CFrame.new(dest),
            Transparency = 1,
            Size = Vector3.new(0.05, 0.05, 0.05),
        }):Play()
        Debris:AddItem(b, life + 0.1)
    end
end

-- Self burst AROUND `center`: ground ring + dome + rising motes.
local function playSelf(theme, params, center)
    local c1, c2 = toColor(theme.color), toColor(theme.color2, toColor(theme.color))
    local mat = materialOf(theme.material)
    local radius = tonumber(params.radius) or 12
    local life = tonumber(params.duration) or 0.6
    groundRing(center, c1, mat, radius * 2, life)
    groundRing(center, c2, mat, radius * 1.3, life * 0.8)
    dome(center, c1, mat, radius, life)
    motes(center, c2, mat, tonumber(params.motes) or 16, radius, tonumber(params.rise) or 8, life + 0.1)
end

-- Targeted strike AT `targetPos` with a cast tell from `originPos`: cast beam + telegraph,
-- then (after cast_time) the eruption — ring + dome + descending column + debris + motes.
local function playTargeted(theme, params, originPos, targetPos)
    local c1, c2 = toColor(theme.color), toColor(theme.color2, toColor(theme.color))
    local mat = materialOf(theme.material)
    local radius = tonumber(params.radius) or 9
    local castTime = math.max(0.05, tonumber(params.cast_time) or 0.18)
    local life = tonumber(params.duration) or 0.6

    -- Cast tell: a beam from the caster to the target + a faint ground telegraph ring.
    beam(originPos + Vector3.new(0, 2, 0), targetPos + Vector3.new(0, 1, 0), c2, mat, 0.35, castTime + 0.08)
    groundRing(targetPos, c1, mat, radius * 1.6, castTime + 0.12, 0.55)

    task.delay(castTime, function()
        column(targetPos, c2, mat, radius * 1.6, life * 0.7) -- eruption beam
        groundRing(targetPos, c1, mat, radius * 2.4, life, 0.1)
        dome(targetPos, c1, mat, radius * 0.9, life)
        debris(targetPos, c1, c2, mat, tonumber(params.debris) or 16, radius, life)
        motes(targetPos, c2, mat, tonumber(params.motes) or 12, radius, tonumber(params.rise) or 7, life)
    end)
end

-- Play an area effect. element keys config.themes; variant is "self" or "targeted".
function AreaFX.Play(config, element, variant, originPos, targetPos)
    config = type(config) == "table" and config or {}
    local theme = config.themes and config.themes[element]
    if not theme then
        return false
    end
    if variant == "targeted" then
        playTargeted(theme, config.targeted or {}, originPos, targetPos or originPos)
    else
        playSelf(theme, config.self or {}, originPos)
    end
    return true
end

return AreaFX
