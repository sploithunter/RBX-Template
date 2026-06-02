--[[
    CombatFX — client effect FACADE for Halo & Horns.

    One entry point that turns an effect SPEC into the right visual, so powers/pets declare
    intent and don't hand-pick modules:

        CombatFX.play({
            pattern  = "st_attack" | "st_aoe" | "pbaoe" | "attached",
            origin   = "ranged" | "upfront",                 -- caster delivery (st_* only)
            category = "damage" | "heal" | "buff" | "debuff" | "shield",
            element  = "grass" | "lava" | "ice" | "desert",  -- biome origin (its own look)
            crit     = bool,                                  -- st_attack impact tier
            duration = number,                                -- attached lifetime
        }, { caster = Instance, target = Instance, point = Vector3 })

    Routing:
      st_attack -> RangedFX (ranged = element projectile/bolt; upfront = "melee" impact)
      st_aoe    -> AreaFX targeted (cast at a point)
      pbaoe     -> AreaFX self (burst around the caster)
      attached  -> CombatFX's own follow-an-entity engine below (auras + shield bubble)

    The `attached` pattern is the new capability: a continual effect welded/parented to an
    entity for a duration. Returns a handle { stop() } so callers can end it early.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RangedFX = require(ReplicatedStorage.Shared.Effects.RangedFX)
local AreaFX = require(ReplicatedStorage.Shared.Effects.AreaFX)

local CombatFX = {}

local config = require(ReplicatedStorage.Configs:WaitForChild("combat_fx"))
-- RangedFX/AreaFX read their own existing configs; the facade just passes them through.
local rangedCfg = require(ReplicatedStorage.Configs:WaitForChild("pet_follow")).ranged_bolt
local areaCfg = require(ReplicatedStorage.Configs:WaitForChild("area_fx"))

-- element biome -> ranged projectile kind (damage). Upfront/melee + heal handled separately.
local RANGED_KIND = { grass = "lightning", lava = "fireball", ice = "frost", desert = "rock" }

local function toColor(rgb, fallback)
    if typeof(rgb) == "Color3" then
        return rgb
    end
    if type(rgb) == "table" and rgb[1] then
        return Color3.fromRGB(rgb[1], rgb[2] or 0, rgb[3] or 0)
    end
    return fallback or Color3.fromRGB(255, 255, 255)
end

local function partOf(inst)
    if typeof(inst) ~= "Instance" then
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

-- ===== Attached pattern: aura (buff/debuff/damage/heal) =====
-- A ParticleEmitter parented to the entity's body part, so it follows the model automatically.
-- rise = float up (buff/heal) or sink (debuff). Runs for `duration`, then stops + GCs.
local function spawnAura(pp, theme, duration)
    local c1 = toColor(theme.colors and theme.colors[1])
    local c2 = toColor(theme.colors and theme.colors[2], c1)
    local rise = theme.rise ~= false
    local e = Instance.new("ParticleEmitter")
    e.Color = ColorSequence.new(c1, c2)
    e.LightEmission = theme.light_emission or 0.4
    e.Lifetime = NumberRange.new(theme.life_min or 0.6, theme.life_max or 1.2)
    e.Rate = theme.rate or 14
    e.Speed = NumberRange.new(theme.speed_min or 2, theme.speed_max or 5)
    e.SpreadAngle = Vector2.new(theme.spread or 18, theme.spread or 18)
    e.Rotation = NumberRange.new(0, 360)
    e.Acceleration = Vector3.new(0, rise and 3 or -3, 0)
    e.EmissionDirection = rise and Enum.NormalId.Top or Enum.NormalId.Bottom
    local sz = theme.size or 0.8
    e.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, sz),
        NumberSequenceKeypoint.new(1, 0),
    })
    e.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    e.Parent = pp

    local stopped = false
    local function stop()
        if stopped then
            return
        end
        stopped = true
        e.Enabled = false
        Debris:AddItem(e, (theme.life_max or 1.2) + 0.25) -- let in-flight particles finish
    end
    if duration and duration > 0 then
        task.delay(duration, stop)
    end
    return { stop = stop }
end

-- ===== Attached pattern: shield bubble =====
-- A ForceField sphere sized to the model, WeldConstraint'd to its body so it follows. Pops
-- (expand + fade) on stop / when the duration ends.
local function spawnShield(pp, theme, duration)
    local model = pp.Parent
    local diam = 6
    local okE, sz = pcall(function()
        return model and model:IsA("Model") and model:GetExtentsSize()
    end)
    if okE and sz then
        diam = math.max(sz.X, sz.Y, sz.Z) * 1.25
    end
    local bubble = Instance.new("Part")
    bubble.Shape = Enum.PartType.Ball
    bubble.Material = Enum.Material.ForceField
    bubble.Color = toColor(theme.colors and theme.colors[1])
    bubble.Transparency = theme.transparency or 0.5
    bubble.Anchored = false
    bubble.CanCollide = false
    bubble.CanQuery = false
    bubble.CastShadow = false
    bubble.Massless = true
    bubble.Size = Vector3.new(diam, diam, diam)
    bubble.CFrame = (okE and model:GetPivot()) or pp.CFrame
    bubble.Parent = model
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = pp
    weld.Part1 = bubble
    weld.Parent = bubble

    local full = bubble.Size
    bubble.Size = full * 0.2
    TweenService:Create(bubble, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = full,
    }):Play()

    local stopped = false
    local function stop()
        if stopped then
            return
        end
        stopped = true
        TweenService:Create(bubble, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = full * 1.25,
            Transparency = 1,
        }):Play()
        Debris:AddItem(bubble, 0.4)
    end
    if duration and duration > 0 then
        task.delay(duration, stop)
    end
    return { stop = stop }
end

-- Attach a continual effect to an entity for a duration. Returns { stop() } or nil.
function CombatFX.attach(entity, spec)
    spec = spec or {}
    local pp = partOf(entity)
    if not pp then
        return nil
    end
    local cfg = config.attached or {}
    local theme = cfg.themes and cfg.themes[spec.element] and cfg.themes[spec.element][spec.category]
    if not theme then
        return nil -- no skin for this element/category yet
    end
    local duration = spec.duration or cfg.duration or 5
    if spec.category == "shield" then
        return spawnShield(pp, theme, duration)
    end
    return spawnAura(pp, theme, duration)
end

-- Resolve the RangedFX kind for a single-target attack spec.
local function rangedKind(spec)
    if spec.origin == "upfront" then
        return "melee"
    end
    -- TODO(heal): a dedicated heal-bolt kind; for now ranged heal falls back to the element bolt.
    return RANGED_KIND[spec.element] or "fireball"
end

-- Play a one-shot or attached effect from a spec. ctx = { caster, target, point }.
function CombatFX.play(spec, ctx)
    spec = type(spec) == "table" and spec or {}
    ctx = type(ctx) == "table" and ctx or {}
    local pattern = spec.pattern

    if pattern == "attached" then
        return CombatFX.attach(ctx.target or ctx.caster, spec)
    end

    local casterPart = ctx.caster and partOf(ctx.caster)
    local targetPart = ctx.target and partOf(ctx.target)

    if pattern == "st_attack" then
        if not (ctx.caster and ctx.target) then
            return false
        end
        return RangedFX.Play(ctx.caster, rangedCfg, ctx.target, rangedKind(spec), spec.crit == true)
    elseif pattern == "st_aoe" then
        local cp = (casterPart and casterPart.Position) or ctx.point
        local tp = ctx.point or (targetPart and targetPart.Position) or cp
        if not tp then
            return false
        end
        return AreaFX.Play(areaCfg, spec.element, "targeted", cp or tp, tp)
    elseif pattern == "pbaoe" then
        local cp = (casterPart and casterPart.Position) or ctx.point
        if not cp then
            return false
        end
        return AreaFX.Play(areaCfg, spec.element, "self", cp)
    end

    return false
end

return CombatFX
