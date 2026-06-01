--[[
    RangedFX — client-side ranged attack visuals for pets (and, later, enemies).

    A small dispatcher over interchangeable procedural effects so a pet's ranged "bolt"
    can be swapped from config without touching code. PetFollowController calls
    RangedFX.Play(originInstance, config, targetInstance, kind) on the firing cadence;
    `kind` selects the look:

      "lightning"                  -> the existing EnchantLightning arc (delegated)
      "fireball"/"plasma"/"frost"/
      "poison" (+ any config theme) -> a travelling glowing orb + trail + impact burst
                                       (one engine, themed by config.projectile[kind])
      "beam"                       -> an instant laser/energy beam that flashes + fades

    Add a theme by adding a block under config.ranged_bolt.projectile; add a whole new
    style by adding a branch here. Pure visual: damage + targeting stay server-side.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnchantLightning = require(ReplicatedStorage.Shared.Effects.EnchantLightning)

local RangedFX = {}

local function partOf(inst)
    if not inst then
        return nil
    end
    if inst:IsA("BasePart") then
        return inst
    end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
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

local function toVec(t)
    if typeof(t) == "Vector3" then
        return t
    end
    if type(t) == "table" then
        return Vector3.new(t[1] or 0, t[2] or 0, t[3] or 0)
    end
    return Vector3.new(0, 0, 0)
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

-- ===================== Impact library =====================
-- A catalogue of named impact effects (RangedFX.IMPACTS), each played at a hit point. Grow
-- this table to build the library; reference an entry by name from a projectile theme
-- (theme.impact) or from mining_fx. Shared spawn helpers below keep each entry small.
--   c1 = core colour, c2 = debris/secondary colour, opts.scale + opts.sparks tune size/count.

-- A neon flash sphere that snaps out and fades, with a quick PointLight pop.
local function spawnFlash(pos, color, lightColor, size, life)
    local flash = Instance.new("Part")
    flash.Shape = Enum.PartType.Ball
    flash.Material = Enum.Material.Neon
    flash.Color = color
    flash.Anchored = true
    flash.CanCollide = false
    flash.CanQuery = false
    flash.CastShadow = false
    flash.Size = Vector3.new(0.5, 0.5, 0.5)
    flash.CFrame = CFrame.new(pos)
    flash.Parent = fxFolder()
    local light = Instance.new("PointLight")
    light.Color = lightColor
    light.Brightness = 7
    light.Range = size * 2.5
    light.Parent = flash
    TweenService:Create(flash, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(size, size, size),
        Transparency = 1,
    }):Play()
    TweenService:Create(light, TweenInfo.new(life * 0.9), { Brightness = 0 }):Play()
    Debris:AddItem(flash, life + 0.1)
end

-- A radial spray of neon bits that fly outward (with upward lift), shrink + fade.
local function spawnSparks(pos, c1, c2, count, bitSize, spread, life)
    count = math.max(0, math.floor(count))
    for i = 1, count do
        local ang = (i / count) * math.pi * 2 + math.random() * 0.6
        local elev = 0.2 + math.random() * 0.6
        local dir = Vector3.new(math.cos(ang), elev, math.sin(ang)).Unit
        local bit = Instance.new("Part")
        bit.Shape = Enum.PartType.Ball
        bit.Material = Enum.Material.Neon
        bit.Color = (i % 2 == 0) and c1 or c2
        bit.Anchored = true
        bit.CanCollide = false
        bit.CanQuery = false
        bit.CastShadow = false
        bit.Size = Vector3.new(bitSize, bitSize, bitSize)
        bit.CFrame = CFrame.new(pos)
        bit.Parent = fxFolder()
        local dist = spread * (0.7 + math.random() * 0.9)
        local dest = pos + dir * dist - Vector3.new(0, spread * 0.25, 0)
        TweenService:Create(bit, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            CFrame = CFrame.new(dest),
            Size = Vector3.new(0.05, 0.05, 0.05),
            Transparency = 1,
        }):Play()
        Debris:AddItem(bit, life + 0.1)
    end
end

-- A flat neon disc that expands outward + fades — a ground shockwave.
local function spawnShockwave(pos, color, diameter, life)
    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder
    ring.Material = Enum.Material.Neon
    ring.Color = color
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CastShadow = false
    ring.Transparency = 0.2
    ring.Size = Vector3.new(0.4, 1, 1) -- X = thin height; Y/Z = diameter
    ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)) -- lay flat (X -> up)
    ring.Parent = fxFolder()
    TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(0.2, diameter, diameter),
        Transparency = 1,
    }):Play()
    Debris:AddItem(ring, life + 0.1)
end

-- A dark puff that swells + rises + fades — lingering smoke.
local function spawnSmoke(pos, diameter, life)
    local s = Instance.new("Part")
    s.Shape = Enum.PartType.Ball
    s.Material = Enum.Material.SmoothPlastic
    s.Color = Color3.fromRGB(60, 55, 50)
    s.Anchored = true
    s.CanCollide = false
    s.CanQuery = false
    s.CastShadow = false
    s.Transparency = 0.45
    s.Size = Vector3.new(diameter * 0.4, diameter * 0.4, diameter * 0.4)
    s.CFrame = CFrame.new(pos + Vector3.new(0, diameter * 0.2, 0))
    s.Parent = fxFolder()
    TweenService:Create(s, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(diameter, diameter, diameter),
        Transparency = 1,
        CFrame = CFrame.new(pos + Vector3.new(0, diameter * 0.7, 0)),
    }):Play()
    Debris:AddItem(s, life + 0.1)
end

-- A vertical neon pillar that shoots up from the hit point and thins out as it fades.
local function spawnColumn(pos, color, height, life)
    local col = Instance.new("Part")
    col.Shape = Enum.PartType.Cylinder
    col.Material = Enum.Material.Neon
    col.Color = color
    col.Anchored = true
    col.CanCollide = false
    col.CanQuery = false
    col.CastShadow = false
    col.Transparency = 0.15
    local diam = height * 0.18
    col.Size = Vector3.new(1, diam, diam) -- X = length (vertical once rotated); Y/Z = diameter
    col.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
    col.Parent = fxFolder()
    TweenService:Create(col, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(height, diam * 0.3, diam * 0.3),
        Transparency = 1,
        CFrame = CFrame.new(pos + Vector3.new(0, height * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
    }):Play()
    Debris:AddItem(col, life + 0.1)
end

RangedFX.IMPACTS = {
    -- small: a flash + light pop + a handful of embers (the original projectile impact).
    small = function(pos, c1, c2, opts)
        local scale = (opts and tonumber(opts.scale)) or 3
        local sparks = (opts and tonumber(opts.sparks)) or 7
        spawnFlash(pos, c2, c1, scale, 0.25)
        spawnSparks(pos, c1, c2, sparks, scale * 0.2, scale, 0.32)
    end,
    -- medium: a fat double flash + bright light + shockwave disc + heavy ember spray + smoke puff.
    medium = function(pos, c1, c2, opts)
        local scale = (opts and tonumber(opts.scale)) or 7
        local sparks = (opts and tonumber(opts.sparks)) or 18
        spawnFlash(pos, c2, c1, scale, 0.35)
        spawnFlash(pos, c1, c1, scale * 0.6, 0.22) -- inner core
        spawnShockwave(pos, c2, scale * 2.4, 0.4)
        spawnSparks(pos, c1, c2, sparks, scale * 0.22, scale * 1.6, 0.45)
        spawnSmoke(pos, scale * 1.2, 0.6)
    end,
    -- big: a really big blast — double flash + huge bright light + DOUBLE shockwave ring + a
    -- rising energy pillar + a thick ember storm + a big lingering smoke cloud.
    big = function(pos, c1, c2, opts)
        local scale = (opts and tonumber(opts.scale)) or 12
        local sparks = (opts and tonumber(opts.sparks)) or 32
        spawnFlash(pos, c2, c1, scale, 0.45)
        spawnFlash(pos, c1, c1, scale * 0.6, 0.3) -- inner core
        spawnShockwave(pos, c2, scale * 2.2, 0.45) -- inner ring
        spawnShockwave(pos, c1, scale * 3.6, 0.65) -- outer, wider, slower ring
        spawnColumn(pos, c1, scale * 2.2, 0.5) -- rising pillar
        spawnSparks(pos, c1, c2, sparks, scale * 0.22, scale * 2.0, 0.6)
        spawnSmoke(pos, scale * 1.7, 0.85)
    end,
}

-- Play a named impact at `pos`. c1/c2 accept Color3 or {r,g,b}. Unknown name -> small.
function RangedFX.playImpact(name, pos, c1, c2, opts)
    local fn = RangedFX.IMPACTS[name] or RangedFX.IMPACTS.small
    local col1 = toColor(c1)
    fn(pos, col1, toColor(c2, col1), opts)
end

-- Travelling orb (fireball / plasma / frost / poison): an emissive ball flies origin->target
-- with a colour trail, then bursts. Themed entirely by `theme` (colors/size/travel_time/burst).
-- isCrit -> a bigger orb + the crit impact tier (theme.impact_crit, default "big").
local function playProjectile(originPart, endPos, theme, isCrit)
    local c1 = toColor(theme.colors and theme.colors[1], Color3.fromRGB(255, 150, 40))
    local c2 = toColor(theme.colors and theme.colors[2], c1)
    local size = (tonumber(theme.size) or 1.5) * (isCrit and 1.4 or 1)
    local travel = math.max(0.05, tonumber(theme.travel_time) or 0.18)
    local startPos = originPart.Position + Vector3.new(0, 1, 0)

    local orb = Instance.new("Part")
    orb.Shape = Enum.PartType.Ball
    orb.Material = Enum.Material.Neon
    orb.Color = c1
    orb.Anchored = true
    orb.CanCollide = false
    orb.CanQuery = false
    orb.CastShadow = false
    orb.Size = Vector3.new(size, size, size)
    orb.CFrame = CFrame.new(startPos)
    orb.Parent = fxFolder()

    local light = Instance.new("PointLight")
    light.Color = c1
    light.Brightness = 4
    light.Range = 12
    light.Parent = orb

    local a0 = Instance.new("Attachment")
    a0.Position = Vector3.new(0, 0, size * 0.5)
    a0.Parent = orb
    local a1 = Instance.new("Attachment")
    a1.Position = Vector3.new(0, 0, -size * 0.5)
    a1.Parent = orb
    local trail = Instance.new("Trail")
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.Lifetime = 0.2
    trail.WidthScale = NumberSequence.new(1, 0)
    trail.Color = ColorSequence.new(c1, c2)
    trail.Transparency = NumberSequence.new(0.1, 1)
    trail.FaceCamera = true
    trail.Parent = orb

    local tween = TweenService:Create(
        orb,
        TweenInfo.new(travel, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { CFrame = CFrame.new(endPos) }
    )
    tween.Completed:Connect(function()
        if isCrit then
            -- Crit: the crit tier at its own (bigger) default size.
            RangedFX.playImpact(theme.impact_crit or "big", endPos, c1, c2, {
                scale = theme.crit_scale,
                sparks = theme.crit_sparks,
            })
        else
            RangedFX.playImpact(theme.impact or "small", endPos, c1, c2, {
                scale = (tonumber(theme.burst) or 3) * (size / 1.5),
                sparks = theme.sparks,
            })
        end
        orb:Destroy()
    end)
    tween:Play()
    Debris:AddItem(orb, travel + 0.6)
    return true
end

-- Instant laser/energy beam: a neon cylinder spanning origin->target that flashes then fades.
-- isCrit -> the crit impact tier at its end (theme.impact_crit, default "big").
local function playBeam(originPart, endPos, theme, isCrit)
    local c1 = toColor(theme.colors and theme.colors[1], Color3.fromRGB(255, 70, 70))
    local thickness = tonumber(theme.thickness) or 0.5
    local duration = math.max(0.06, tonumber(theme.duration) or 0.18)
    local startPos = originPart.Position + Vector3.new(0, 1, 0)
    local dist = (endPos - startPos).Magnitude
    if dist < 0.1 then
        return false
    end

    local beam = Instance.new("Part")
    beam.Shape = Enum.PartType.Cylinder
    beam.Material = Enum.Material.Neon
    beam.Color = c1
    beam.Anchored = true
    beam.CanCollide = false
    beam.CanQuery = false
    beam.CastShadow = false
    beam.Size = Vector3.new(dist, thickness, thickness)
    beam.CFrame = CFrame.lookAt(startPos:Lerp(endPos, 0.5), endPos) * CFrame.Angles(0, math.rad(90), 0)
    beam.Parent = fxFolder()

    TweenService:Create(beam, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Transparency = 1,
        Size = Vector3.new(dist, 0.05, 0.05),
    }):Play()
    Debris:AddItem(beam, duration + 0.1)
    if isCrit then
        RangedFX.playImpact(theme.impact_crit or "big", endPos, c1, c1, {
            scale = theme.crit_scale,
            sparks = theme.crit_sparks,
        })
    else
        RangedFX.playImpact(theme.impact or "small", endPos, c1, c1, {
            scale = tonumber(theme.burst) or 2.5,
            sparks = theme.sparks or 5,
        })
    end
    return true
end

-- Fire a ranged effect of `kind` from origin to target. Falls back to lightning for an
-- unknown kind. config is the ranged_bolt block (target_offset already a Vector3 from caller).
-- isCrit (from the server's LastHitCrit on the firing pet) bumps the impact to its crit tier.
function RangedFX.Play(origin, config, target, kind, isCrit)
    config = type(config) == "table" and config or {}
    kind = kind or config.kind or "lightning"

    if kind == "lightning" then
        local ok = EnchantLightning.Play(origin, config, target)
        -- Also play a library impact at the strike point, tinted with the bolt's electric colours.
        -- Normal -> config.impact (none/small/medium/big); crit -> config.impact_crit (default big).
        local impactName = isCrit and (config.impact_crit or "big") or config.impact
        if impactName and impactName ~= "none" then
            local targetPart = partOf(target)
            if targetPart then
                local cols = config.colors or {}
                local opts = isCrit and { scale = config.crit_scale, sparks = config.crit_sparks }
                    or { scale = config.impact_scale, sparks = config.impact_sparks }
                RangedFX.playImpact(
                    impactName,
                    targetPart.Position + toVec(config.target_offset),
                    cols[1] or { 120, 150, 255 },
                    cols[2] or { 200, 235, 255 },
                    opts
                )
            end
        end
        return ok
    end

    local originPart = partOf(origin)
    local targetPart = partOf(target)
    if not originPart or not targetPart then
        return false
    end
    local endPos = targetPart.Position + toVec(config.target_offset)

    if kind == "beam" then
        return playBeam(originPart, endPos, config.beam or {}, isCrit)
    end

    -- Projectile family: theme comes from config.projectile[kind] (fireball/plasma/frost/...).
    local theme = (config.projectile and config.projectile[kind]) or {}
    return playProjectile(originPart, endPos, theme, isCrit)
end

return RangedFX
