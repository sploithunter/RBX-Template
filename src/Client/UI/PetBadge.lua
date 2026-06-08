--[[
    PetBadge — the ONE universal icon-badge renderer. Every archetype/power icon in the game is
    this same two-layer stack: a colored DISC ImageLabel (element of origin) behind a tinted RING
    ImageLabel (plain `aura` ring for archetypes; a directional ring for powers later). No
    per-surface special path — SquadHud, InventoryPanel, hotbar, etc. all call this.

    Data lives in configs/power_icons.lua:
      - discs[element][symbol]  = the pre-baked colored disc Image (element = disc color)
      - role_symbol[roleId]     = which white symbol a role stamps (tank->armor, melee->fist_impact,
                                  ranged->arrow_right, support->star_sparkle, control->hand_stop)
      - rings[shape] + elements[elem].dark = the ring frame + its tint
      - element_alias            = canonical combat element (grass/lava/ice/desert) -> badge key
                                   (earth/fire/desert/ice)

    Two entry points:
      PetBadge.create(parent, opts) -> { holder, disc, ring }   (build once)
      PetBadge.apply(disc, ring, element, role, opts) -> bool    (re-skin existing labels each tick)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local POWER_ICONS = require(Configs:WaitForChild("power_icons"))

local PetBadge = {}

-- Lazily pull the petType -> origin-element map (grass/lava/ice/desert) from combat_fx.
local _pettypeElement
local function pettypeElement()
    if _pettypeElement == nil then
        local ok, cfx = pcall(function()
            return require(Configs:WaitForChild("combat_fx"))
        end)
        _pettypeElement = (ok and cfx and cfx.origin and cfx.origin.pettype_element) or {}
    end
    return _pettypeElement
end

-- Badge element key (earth/fire/desert/ice, else "neutral") for a pet type.
function PetBadge.elementForPetType(petType)
    return POWER_ICONS.elementKey(pettypeElement()[petType or ""])
end

-- Lazy power/archetype configs (for power-slot badges in the hotbar).
local _powers, _archetypes
local function powersCfg()
    if _powers == nil then
        local ok, p = pcall(function()
            return require(Configs:WaitForChild("powers"))
        end)
        _powers = (ok and p) or {}
    end
    return _powers
end
local function archetypesCfg()
    if _archetypes == nil then
        local ok, a = pcall(function()
            return require(Configs:WaitForChild("archetypes"))
        end)
        _archetypes = (ok and a and a.archetypes) or {}
    end
    return _archetypes
end

-- Resolve a power id -> { element, symbol, ring } (ring = a ring SHAPE key), or nil if the power
-- or its effect/glyph has no mapped symbol. Element = the power's element, else its archetype
-- theme. Symbol + targeting come from power_icons.power_effect_badge / glyph / signature maps.
function PetBadge.forPower(powerId)
    local cfg = powersCfg()
    local def = cfg.powers and cfg.powers[powerId]
    if not def then
        return nil
    end
    local rawElement = def.element
    if not rawElement and def.archetype then
        local arch = archetypesCfg()[def.archetype]
        rawElement = arch and arch.theme
    end
    local element = POWER_ICONS.elementKey(rawElement)

    local symbol, targetKind
    if def.signature then
        symbol = POWER_ICONS.power_glyph_symbol[def.glyph or ""]
        targetKind = POWER_ICONS.power_signature_ring[def.target or ""] or "single"
    else
        local spec = POWER_ICONS.power_effect_badge[def.effect or ""]
        if spec then
            symbol = spec.symbol
            targetKind = spec.target
        end
    end
    if not symbol then
        return nil
    end
    -- targeting kind -> ring shape key (aura/target_in/aoe/...)
    local shape = POWER_ICONS.targeting_ring[targetKind or "none"] or "aura"
    return { element = element, symbol = symbol, ring = shape }
end

-- Disc Image (rbxassetid string) for a power's badge, or nil. Shortcut for surfaces that only
-- need the disc (status badges, the floating armor icon) so a buff shows the SAME icon as its power.
function PetBadge.powerDiscImage(powerId)
    if not powerId or powerId == "" then
        return nil
    end
    local b = PetBadge.forPower(powerId)
    return b and POWER_ICONS.discFor(b.element, b.symbol) or nil
end

-- Re-skin pre-existing disc + ring ImageLabels (the reuse path; e.g. SquadHud cards persist).
-- element = canonical or badge token; role = role id; opts.symbol overrides the role symbol;
-- opts.ring = ring shape (default "aura"). Returns true if a disc image was found.
function PetBadge.apply(disc, ring, element, role, opts)
    opts = opts or {}
    local elemKey = POWER_ICONS.elementKey(element)
    local symbol = opts.symbol or POWER_ICONS.symbolForRole(role)
    local discImg = POWER_ICONS.discFor(elemKey, symbol)
    if disc then
        disc.Image = discImg or ""
        disc.Visible = discImg ~= nil
    end
    if ring then
        ring.Image = POWER_ICONS.rings[opts.ring or "aura"] or POWER_ICONS.rings.aura
        ring.ImageColor3 = POWER_ICONS.elementColor3(elemKey, "dark")
    end
    return discImg ~= nil
end

-- Build a full badge (disc inset behind a slightly larger framing ring) into `parent`, filling
-- it. opts = { element, role, symbol, ring, zIndex }. Returns { holder, disc, ring }.
function PetBadge.create(parent, opts)
    opts = opts or {}
    local z = opts.zIndex or 1

    local holder = Instance.new("Frame")
    holder.Name = "PetBadge"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromScale(1, 1)
    holder.ZIndex = z
    holder.Parent = parent

    local disc = Instance.new("ImageLabel")
    disc.Name = "Disc"
    disc.BackgroundTransparency = 1
    disc.AnchorPoint = Vector2.new(0.5, 0.5)
    disc.Position = UDim2.fromScale(0.5, 0.5)
    disc.Size = UDim2.fromScale(0.80, 0.80) -- inset so the ring frames it
    disc.ScaleType = Enum.ScaleType.Fit
    disc.ZIndex = z
    disc.Parent = holder

    local ring = Instance.new("ImageLabel")
    ring.Name = "Ring"
    ring.BackgroundTransparency = 1
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    -- centred at .5,.5, plus a per-ring nudge + scale to compensate off-centre / under-sized source
    -- PNGs (config-driven; see power_icons.ring_centering).
    local off = POWER_ICONS.ringCentering(opts.ring)
    local rscale = off.scale or 1
    ring.Position = UDim2.new(0.5 + (off.x or 0), 0, 0.5 + (off.y or 0), 0)
    ring.Size = UDim2.fromScale(rscale, rscale)
    ring.ScaleType = Enum.ScaleType.Fit
    ring.ZIndex = z + 1
    ring.Parent = holder

    PetBadge.apply(disc, ring, opts.element, opts.role, opts)
    return { holder = holder, disc = disc, ring = ring }
end

return PetBadge
