--[[
    Enhancements (pure) — rules for CoH-style power enhancements. See configs/enhancements.lua.

    An enhancement record: { type = "damage", origins = { "pyromancer" } or { a, b } }.
    Slot records in data.Slots[powerId]: {} = empty, { inherent = true } = the free first slot,
    { enh = <record> } = filled. Pure: no Roblox APIs; all inputs plain tables.
]]

local Enhancements = {}

local function typeDef(cfg, enhType)
    return cfg and cfg.types and cfg.types[enhType] or nil
end

function Enhancements.isValidType(cfg, enhType)
    return typeDef(cfg, enhType) ~= nil
end

function Enhancements.isSingle(record)
    return type(record) == "table" and type(record.origins) == "table" and #record.origins == 1
end

function Enhancements.isDual(record)
    return type(record) == "table"
        and type(record.origins) == "table"
        and #record.origins == 2
        and record.origins[1] ~= record.origins[2]
end

-- A record is well-formed: known type + 1 or 2 distinct known origins.
function Enhancements.isValid(cfg, record)
    if type(record) ~= "table" or not Enhancements.isValidType(cfg, record.type) then
        return false
    end
    if not (Enhancements.isSingle(record) or Enhancements.isDual(record)) then
        return false
    end
    local known = {}
    for _, o in ipairs(cfg.origins or {}) do
        known[o] = true
    end
    for _, o in ipairs(record.origins) do
        if not known[o] then
            return false
        end
    end
    return true
end

-- Boost fraction this record contributes (single > dual, from config).
function Enhancements.value(cfg, record)
    local values = cfg and cfg.values or {}
    if Enhancements.isSingle(record) then
        return tonumber(values.single) or 0
    elseif Enhancements.isDual(record) then
        return tonumber(values.dual) or 0
    end
    return 0
end

-- Usability: the PLAYER's origin must be among the enhancement's origins.
function Enhancements.usableBy(record, playerArchetype)
    if type(record) ~= "table" or type(record.origins) ~= "table" then
        return false
    end
    for _, o in ipairs(record.origins) do
        if o == playerArchetype then
            return true
        end
    end
    return false
end

-- Compatibility: does this TYPE fit this POWER? powerDef = configs/powers.lua powers[id];
-- effectKinds = configs/powers.lua effect_kinds. Returns (ok, reason).
function Enhancements.compatibleWith(cfg, enhType, powerDef, effectKinds)
    local def = typeDef(cfg, enhType)
    if not def then
        return false, "unknown_type"
    end
    if type(powerDef) ~= "table" then
        return false, "unknown_power"
    end
    local kind = powerDef.effect and effectKinds and effectKinds[powerDef.effect]
    local family = kind and kind.family
    if def.families ~= "*" then
        if not (family and type(def.families) == "table" and def.families[family]) then
            return false, "wrong_family"
        end
    end
    -- always-on powers have nothing to recharge (a vestigial cooldown_seconds in the
    -- power def doesn't change that — the KIND being passive/toggle is the truth)
    if def.excludes_passive and kind and (kind.passive == true or kind.toggle == true) then
        return false, "always_on"
    end
    if def.requires_aoe then
        local aoe = cfg.aoe_targets or {}
        local radiusFamily = family and (cfg.radius_families or {})[family]
        if not (radiusFamily or (powerDef.target and aoe[powerDef.target])) then
            return false, "not_aoe"
        end
    end
    return true
end

-- Aggregate a power's slot list into per-axis bonus fractions: { damage = 0.66, recharge = 0.33 }.
-- Additive within an axis (two singles on one axis = 2 × values.single). Empty/inherent slots and
-- malformed records contribute nothing.
local function scalingCfg(cfg)
    local levels = ((cfg.drops or {}).levels or {})
    return levels.scaling or {}
end

-- CoH-style level factor for a slotted enhancement vs the PLAYER's level:
--   within +/- window: 1 + per_level * (enhLevel - playerLevel)  (above you = stronger)
--   more than window BELOW you: 0 — slotted but DEAD (lost the boost entirely)
--   more than window ABOVE you: 0 (can't normally be slotted; dies if it happens)
-- Records or callers without levels scale at 1 (legacy grace).
function Enhancements.levelFactor(cfg, enhLevel, playerLevel)
    enhLevel = tonumber(enhLevel)
    playerLevel = tonumber(playerLevel)
    if not enhLevel or not playerLevel then
        return 1
    end
    local sc = scalingCfg(cfg)
    local window = tonumber(sc.window) or 2
    local diff = enhLevel - playerLevel
    if diff > window or diff < -window then
        return 0
    end
    return 1 + (tonumber(sc.per_level) or 0) * diff
end

-- Placement gate: you can slot up to `window` levels above yourself, never higher.
function Enhancements.canSlotAtLevel(cfg, enhLevel, playerLevel)
    enhLevel = tonumber(enhLevel)
    playerLevel = tonumber(playerLevel)
    if not enhLevel or not playerLevel then
        return true -- legacy records without levels stay slottable
    end
    local window = tonumber(scalingCfg(cfg).window) or 2
    return enhLevel <= playerLevel + window
end

function Enhancements.aggregate(cfg, slots, playerLevel)
    local axes = {}
    for _, slot in ipairs(type(slots) == "table" and slots or {}) do
        local rec = type(slot) == "table" and slot.enh
        if rec and Enhancements.isValid(cfg, rec) then
            local def = typeDef(cfg, rec.type)
            if def and def.axis then
                local v = Enhancements.value(cfg, rec)
                    * Enhancements.levelFactor(cfg, rec.level, playerLevel)
                if v ~= 0 then
                    axes[def.axis] = (axes[def.axis] or 0) + v
                end
            end
        end
    end
    return axes
end

-- "Pyro Damage" / "Geo/Cryo Recharge" — origin prefix(es) + capitalized type.
function Enhancements.displayName(cfg, record)
    if type(record) ~= "table" then
        return "Enhancement"
    end
    local names = cfg and cfg.origin_names or {}
    local parts = {}
    for _, o in ipairs(record.origins or {}) do
        parts[#parts + 1] = names[o] or o
    end
    local typeName = tostring(record.type or ""):gsub("^%l", string.upper)
    if #parts == 0 then
        return typeName
    end
    return table.concat(parts, "/") .. " " .. typeName
end

-- Visual spec for the badge renderer: disc = type symbol in origins[1]'s color group; ring =
-- the enhancement ring tinted origins[2]'s color (dual) or origins[1]'s (single — same group).
function Enhancements.badgeSpec(cfg, record)
    if type(record) ~= "table" or type(record.origins) ~= "table" then
        return nil
    end
    local def = typeDef(cfg, record.type)
    return {
        symbol = def and def.symbol or "star_sparkle",
        discOrigin = record.origins[1],
        ringOrigin = record.origins[2] or record.origins[1],
        single = Enhancements.isSingle(record),
    }
end

-- Roll a drop LEVEL for an area: uniform in the area's band, +/- jitter, floor 1.
-- rng = Random instance (injectable for tests).
function Enhancements.rollLevel(cfg, areaId, rng)
    rng = rng or Random.new()
    local levels = (cfg.drops or {}).levels or {}
    local bands = levels.bands or {}
    local band = bands[tostring(areaId)] or bands.default or { 1, 1 }
    local lo = math.floor(tonumber(band[1]) or 1)
    local hi = math.max(lo, math.floor(tonumber(band[2]) or lo))
    local jitter = math.floor(tonumber(levels.jitter) or 0)
    local lvl = rng:NextInteger(lo, hi)
    if jitter > 0 then
        lvl += rng:NextInteger(-jitter, jitter)
    end
    return math.max(1, lvl)
end

return Enhancements
