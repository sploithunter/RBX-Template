--[[
    CombatFX — client effect FACADE for Halo & Horns.

    One entry point that turns an effect SPEC into the right visual, so powers/pets declare
    intent and don't hand-pick modules:

        CombatFX.play({
            pattern    = "st_attack" | "st_aoe" | "pbaoe" | "attached" | "impact",
            origin     = "ranged" | "upfront",                 -- caster delivery (st_* only)
            category   = "damage" | "heal" | "buff" | "debuff" | "shield",
            element    = "grass" | "lava" | "ice" | "desert",  -- biome origin (its own look)
            crit       = bool,                                  -- st_attack impact tier
            duration   = number,                                -- attached lifetime
            variant    = "targeted" | "pit",                    -- st_aoe shape (pit = lingering pool)
            projectile = "rock" | "frost" | "lightning" | …,    -- st_attack: force a specific bolt
            impact     = "shatter" | "dust" | "big" | "bloom",  -- impact pattern: which point-burst
        }, { caster = Instance, target = Instance, point = Vector3 })

    Routing:
      st_attack -> RangedFX (ranged = element projectile/bolt; upfront = "melee" impact)
      st_aoe    -> AreaFX (variant "targeted" = strike at a point; "pit" = lingering pool)
      pbaoe     -> AreaFX self (burst around the caster)
      attached  -> CombatFX's own follow-an-entity engine below (auras + shield bubble)
      impact    -> RangedFX.playImpact (a bare point-burst from the impact library, no projectile)

    The `attached` pattern is the new capability: a continual effect welded/parented to an
    entity for a duration. Returns a handle { stop() } so callers can end it early.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
    TweenService
        :Create(bubble, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = full,
        })
        :Play()

    local stopped = false
    local function stop()
        if stopped then
            return
        end
        stopped = true
        TweenService
            :Create(bubble, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = full * 1.25,
                Transparency = 1,
            })
            :Play()
        Debris:AddItem(bubble, 0.4)
    end
    if duration and duration > 0 then
        task.delay(duration, stop)
    end
    return { stop = stop }
end

-- ===== Attached pattern: AURA FIELD (ground AoE) =====
-- A persistent, ground-hugging field that FOLLOWS the pet — the bear's "get close and everything
-- burns" aura. Built the layered-VFX way (two ParticleEmitters on a flat invisible holder welded to
-- the pet's base) instead of one tweened Neon dome that read as a plastic blob:
--   (1) leafy motes rising across the whole field area  — the body
--   (2) low flecks hugging the ground                   — the edge / footprint
-- Particles emit from the holder's flat box volume (no Disc-shape orientation fuss). Textures default
-- to the soft built-in particle; drop real leaf art in via the config `texture` knob later.
local function spawnAuraField(pp, theme, duration, radius)
    radius = tonumber(radius) or tonumber(theme.radius) or 10
    local model = pp.Parent
    local yoff = 2
    local okE, sz = pcall(function()
        return model and model:IsA("Model") and model:GetExtentsSize()
    end)
    if okE and sz then
        -- sit the emission slab just ABOVE the pet's feet (not at the body centre). Lifting it ~0.5
        -- stud clear of the floor keeps particles from spawning underground + getting occluded.
        yoff = (sz.Y * 0.5) - 0.5
    end
    local c1 = toColor(theme.colors and theme.colors[1])
    local c2 = toColor(theme.colors and theme.colors[2], c1)

    -- flat, invisible emission holder at the pet's feet, welded so the field follows the pet
    local holder = Instance.new("Part")
    holder.Name = "AuraField"
    holder.Anchored = false
    holder.CanCollide = false
    holder.CanQuery = false
    holder.CastShadow = false
    holder.Massless = true
    holder.Transparency = 1
    holder.Size = Vector3.new(radius * 2, 0.3, radius * 2) -- flat disc-ish emission area
    holder.CFrame = pp.CFrame * CFrame.new(0, -yoff, 0)
    holder.Parent = model
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = pp
    weld.Part1 = holder
    weld.Parent = holder

    local function mkEmitter(o)
        local e = Instance.new("ParticleEmitter")
        e.Color = ColorSequence.new(c1, c2)
        e.LightEmission = theme.light_emission or 0.3
        e.LightInfluence = 0 -- keep the green constant under the area's (lava-red) lighting
        e.Texture = o.texture or theme.texture or ""
        e.Lifetime = NumberRange.new(o.life_min, o.life_max)
        e.Rate = o.rate
        e.Speed = NumberRange.new(o.speed_min, o.speed_max)
        e.SpreadAngle = Vector2.new(o.spread or 25, o.spread or 25)
        e.Rotation = NumberRange.new(0, 360)
        e.RotSpeed = NumberRange.new(-60, 60)
        e.Acceleration = Vector3.new(0, o.accel_y or 0, 0)
        e.EmissionDirection = Enum.NormalId.Top
        e.Drag = o.drag or 1.5
        -- grow in, shrink out (never pop); fade both ends (research: 80% of the look is these curves)
        e.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.25, o.size),
            NumberSequenceKeypoint.new(1, 0),
        })
        e.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.2, o.transparency or 0.25),
            NumberSequenceKeypoint.new(0.85, o.transparency or 0.25),
            NumberSequenceKeypoint.new(1, 1),
        })
        e.Parent = holder
        return e
    end

    -- Density scales with the field's AREA (≈ radius²), not its radius — a wide field needs far more
    -- particles to read. Capped so a huge-radius aura can't blow the particle budget.
    local area = radius * radius
    -- (1) body: leafy motes rising across the whole field
    local rises = mkEmitter({
        rate = math.min(280, area * (theme.rate or 1.0)),
        size = theme.size or 1.4,
        life_min = theme.life_min or 0.8,
        life_max = theme.life_max or 1.6,
        speed_min = theme.speed_min or 1.5,
        speed_max = theme.speed_max or 4,
        accel_y = (theme.rise ~= false) and 2 or -2,
        spread = 22,
        transparency = theme.transparency or 0.15,
    })
    -- (2) edge: low flecks hugging the ground for the footprint
    local g = theme.ground or {}
    local floor = mkEmitter({
        rate = math.min(150, area * (g.rate or 0.5)),
        size = g.size or 0.6,
        life_min = g.life_min or 0.4,
        life_max = g.life_max or 0.9,
        speed_min = g.speed_min or 0.5,
        speed_max = g.speed_max or 2,
        accel_y = -1,
        spread = 60,
        transparency = g.transparency or 0.2,
    })

    -- (3) ground disc: a flat textured slab on the floor (EffectTextureMaker WaterTurbulence /
    -- Squiggles), tinted to the element + slowly scrolling so it flows. This is the contrast layer —
    -- a textured footprint reads on ANY ground colour (green motes vanish on green grass). Only built
    -- when a texture id is configured; the grayscale texture tints to the theme colour.
    local disc, scrollConn
    local groundTex = theme.ground_texture
    if type(groundTex) == "string" and groundTex ~= "" then
        if not groundTex:match("^rbxassetid://") then
            groundTex = "rbxassetid://" .. groundTex
        end
        disc = Instance.new("Part")
        disc.Name = "AuraFieldDisc"
        disc.Shape = Enum.PartType.Block
        disc.Anchored = false
        disc.CanCollide = false
        disc.CanQuery = false
        disc.CastShadow = false
        disc.Massless = true
        disc.Transparency = 1 -- the part is invisible; only the top-face Texture shows
        disc.Size = Vector3.new(radius * 2, 0.1, radius * 2)
        disc.CFrame = pp.CFrame * CFrame.new(0, -(yoff + 0.4), 0) -- lie on the floor, under the motes
        disc.Parent = model
        local dweld = Instance.new("WeldConstraint")
        dweld.Part0 = pp
        dweld.Part1 = disc
        dweld.Parent = disc
        local tex = Instance.new("Texture")
        tex.Face = Enum.NormalId.Top
        tex.Texture = groundTex
        tex.Color3 = toColor(theme.ground_color or (theme.colors and theme.colors[1]))
        tex.Transparency = theme.ground_transparency or 0.35
        tex.StudsPerTileU = radius * 2 -- one tile spans the whole field (set < that to repeat)
        tex.StudsPerTileV = radius * 2
        tex.Parent = disc
        local scroll = tonumber(theme.ground_scroll) or 0
        if scroll ~= 0 then
            scrollConn = RunService.Heartbeat:Connect(function(dt)
                tex.OffsetStudsV = tex.OffsetStudsV + scroll * dt
            end)
        end
    end

    local stopped = false
    local function stop()
        if stopped then
            return
        end
        stopped = true
        rises.Enabled = false
        floor.Enabled = false
        if scrollConn then
            scrollConn:Disconnect()
        end
        if disc then
            local t = disc:FindFirstChildOfClass("Texture")
            if t then
                TweenService:Create(t, TweenInfo.new(0.4), { Transparency = 1 }):Play()
            end
            Debris:AddItem(disc, 0.5)
        end
        Debris:AddItem(holder, (theme.life_max or 1.6) + 0.3) -- let in-flight particles finish
    end
    if duration and duration > 0 then
        task.delay(duration, stop)
    end
    return { stop = stop }
end

-- Attach a continual effect to an entity for a duration. Returns { stop() } or nil.
local function materialEnum(name)
    local ok, m = pcall(function()
        return Enum.Material[name]
    end)
    return (ok and m) or Enum.Material.Slate
end

-- Temporarily RESKIN a model (e.g. Stone Skin -> Slate stone): swap every BasePart's Material +
-- Color, strip MeshPart textures + decals, saving originals. Returns a stop() that restores.
-- opts = { material = "Slate", color = {r,g,b}, hide_decals = true }.
-- Note: "rainbow"/"golden" variant pets re-apply their colours each frame, so Color is fought
-- (Material still changes); plain pets stone out fully. Suspending the variant skin is a follow-up.
local function reskinEntity(model, opts)
    opts = opts or {}
    local mat = materialEnum(opts.material or "Slate")
    local color = toColor(opts.color, Color3.fromRGB(120, 114, 105))
    local saved = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            local rec = { inst = d, material = d.Material, color = d.Color }
            d.Material = mat
            d.Color = color
            if d:IsA("MeshPart") and d.TextureID ~= "" then
                rec.texture = d.TextureID
                d.TextureID = ""
            end
            saved[#saved + 1] = rec
        elseif (d:IsA("Decal") or d:IsA("Texture")) and opts.hide_decals ~= false then
            saved[#saved + 1] = { inst = d, transparency = d.Transparency }
            d.Transparency = 1
        end
    end
    local stopped = false
    return function()
        if stopped then
            return
        end
        stopped = true
        for _, rec in ipairs(saved) do
            local d = rec.inst
            if d and d.Parent then
                if rec.material then
                    d.Material = rec.material
                    d.Color = rec.color
                    if rec.texture then
                        d.TextureID = rec.texture
                    end
                else
                    d.Transparency = rec.transparency
                end
            end
        end
    end
end

-- Attach a continual effect to an entity for a duration. Returns { stop() } or nil.
-- spec.reskin (or the theme's reskin) temporarily retextures the whole model (Stone Skin).
function CombatFX.attach(entity, spec)
    spec = spec or {}
    local pp = partOf(entity)
    if not pp then
        return nil
    end
    local cfg = config.attached or {}
    local theme = cfg.themes
        and cfg.themes[spec.element]
        and cfg.themes[spec.element][spec.category]
    local reskinCfg = spec.reskin or (theme and theme.reskin)
    if not theme and not reskinCfg then
        return nil -- nothing to show for this element/category
    end
    local duration = spec.duration or cfg.duration or 5

    local reskinStop = reskinCfg and reskinEntity(pp.Parent, reskinCfg) or nil
    local handle
    if theme then
        if spec.category == "shield" then
            handle = spawnShield(pp, theme, duration)
        elseif spec.category == "aurafield" then
            handle = spawnAuraField(pp, theme, duration, spec.radius)
        else
            handle = spawnAura(pp, theme, duration)
        end
    end

    if not reskinStop then
        return handle
    end
    if duration and duration > 0 then
        task.delay(duration, reskinStop)
    end
    return {
        stop = function()
            if handle and handle.stop then
                handle.stop()
            end
            reskinStop()
        end,
    }
end

-- Resolve the RangedFX kind for a single-target attack spec.
local function rangedKind(spec)
    if spec.category == "heal" then
        -- per-biome heal-bolt tint (heal_lava/...) if defined, else the generic green heal bolt
        local k = "heal_" .. tostring(spec.element)
        if rangedCfg.projectile and rangedCfg.projectile[k] then
            return k
        end
        return "heal"
    end
    if spec.origin == "upfront" then
        return "melee" -- biome-distinct via RangedFX melee_by_element (element passed below)
    end
    return RANGED_KIND[spec.element] or "fireball"
end

-- AreaFX shape for an area spec: heal uses the dedicated "heal" nova/splash shapes; everything
-- else uses the biome element's own effect.
local function areaElement(spec)
    if spec.category == "heal" then
        return "heal"
    end
    return spec.element
end

-- Per-biome heal tint (reuses the heal shapes with a biome colour) so heal honours
-- "every origin unique graphics". nil for non-heal (the biome theme is used as-is).
local function healOverride(spec)
    if spec.category ~= "heal" then
        return nil
    end
    local tints = areaCfg.heal_tints
    return (tints and spec.element and tints[spec.element]) or nil
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
        -- spec.projectile forces a specific RangedFX kind (boulder/frost_shard/arc/laser) regardless
        -- of element; without it the element picks the default projectile.
        local kind = spec.projectile or rangedKind(spec)
        return RangedFX.Play(
            ctx.caster,
            rangedCfg,
            ctx.target,
            kind,
            spec.crit == true,
            spec.element
        )
    elseif pattern == "impact" then
        -- A bare point-impact from the RangedFX library (shatter/dust/big/bloom/…), no projectile —
        -- coloured by the element's area theme. For hit-flashes decoupled from a travelling bolt.
        local tp = ctx.point
            or (targetPart and targetPart.Position)
            or (casterPart and casterPart.Position)
        if not tp then
            return false
        end
        local theme = areaCfg.themes and areaCfg.themes[areaElement(spec)]
        local c1 = toColor(theme and theme.color, Color3.fromRGB(255, 255, 255))
        local c2 = toColor(theme and theme.color2, c1)
        return RangedFX.playImpact(spec.impact or "small", tp, c1, c2, { crit = spec.crit == true })
    elseif pattern == "st_aoe" then
        local tp = ctx.point
            or (targetPart and targetPart.Position)
            or (casterPart and casterPart.Position)
        if not tp then
            return false
        end
        -- Upfront = slam at the adjacent target: origin == target suppresses AreaFX's ranged
        -- cast beam. Ranged keeps the beam from the caster.
        local cp = (spec.origin == "upfront") and tp or ((casterPart and casterPart.Position) or tp)
        -- spec.variant selects the AreaFX shape: "targeted" (slam/eruption, default) or "pit" (a
        -- lingering bubbling pool — DoT/brand ground hazard).
        return AreaFX.Play(
            areaCfg,
            areaElement(spec),
            spec.variant or "targeted",
            cp,
            tp,
            healOverride(spec)
        )
    elseif pattern == "pbaoe" then
        local cp = (casterPart and casterPart.Position) or ctx.point
        if not cp then
            return false
        end
        -- spec.no_ring strips the encircling ground/radial ring, keeping the on-caster core.
        return AreaFX.Play(areaCfg, areaElement(spec), "self", cp, nil, healOverride(spec), {
            no_ring = spec.no_ring,
        })
    end

    return false
end

return CombatFX
