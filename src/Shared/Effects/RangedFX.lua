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

-- An expanding, fading neon sphere at `pos` — the impact burst shared by the projectile themes.
local function burst(pos, color, size)
    local b = Instance.new("Part")
    b.Shape = Enum.PartType.Ball
    b.Material = Enum.Material.Neon
    b.Color = color
    b.Anchored = true
    b.CanCollide = false
    b.CanQuery = false
    b.CastShadow = false
    b.Size = Vector3.new(0.5, 0.5, 0.5)
    b.CFrame = CFrame.new(pos)
    b.Parent = fxFolder()
    TweenService:Create(b, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(size, size, size),
        Transparency = 1,
    }):Play()
    Debris:AddItem(b, 0.3)
end

-- Travelling orb (fireball / plasma / frost / poison): an emissive ball flies origin->target
-- with a colour trail, then bursts. Themed entirely by `theme` (colors/size/travel_time/burst).
local function playProjectile(originPart, endPos, theme)
    local c1 = toColor(theme.colors and theme.colors[1], Color3.fromRGB(255, 150, 40))
    local c2 = toColor(theme.colors and theme.colors[2], c1)
    local size = tonumber(theme.size) or 1.5
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
        burst(endPos, c2, (tonumber(theme.burst) or 3) * (size / 1.5))
        orb:Destroy()
    end)
    tween:Play()
    Debris:AddItem(orb, travel + 0.6)
    return true
end

-- Instant laser/energy beam: a neon cylinder spanning origin->target that flashes then fades.
local function playBeam(originPart, endPos, theme)
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
    return true
end

-- Fire a ranged effect of `kind` from origin to target. Falls back to lightning for an
-- unknown kind. config is the ranged_bolt block (target_offset already a Vector3 from caller).
function RangedFX.Play(origin, config, target, kind)
    config = type(config) == "table" and config or {}
    kind = kind or config.kind or "lightning"

    if kind == "lightning" then
        return EnchantLightning.Play(origin, config, target)
    end

    local originPart = partOf(origin)
    local targetPart = partOf(target)
    if not originPart or not targetPart then
        return false
    end
    local endPos = targetPart.Position + toVec(config.target_offset)

    if kind == "beam" then
        return playBeam(originPart, endPos, config.beam or {})
    end

    -- Projectile family: theme comes from config.projectile[kind] (fireball/plasma/frost/...).
    local theme = (config.projectile and config.projectile[kind]) or {}
    return playProjectile(originPart, endPos, theme)
end

return RangedFX
