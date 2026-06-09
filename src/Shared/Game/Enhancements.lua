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
    if def.requires_aoe then
        local aoe = cfg.aoe_targets or {}
        if not (powerDef.target and aoe[powerDef.target]) then
            return false, "not_aoe"
        end
    end
    return true
end

-- Aggregate a power's slot list into per-axis bonus fractions: { damage = 0.66, recharge = 0.33 }.
-- Additive within an axis (two singles on one axis = 2 × values.single). Empty/inherent slots and
-- malformed records contribute nothing.
function Enhancements.aggregate(cfg, slots)
    local axes = {}
    for _, slot in ipairs(type(slots) == "table" and slots or {}) do
        local rec = type(slot) == "table" and slot.enh
        if rec and Enhancements.isValid(cfg, rec) then
            local def = typeDef(cfg, rec.type)
            if def and def.axis then
                axes[def.axis] = (axes[def.axis] or 0) + Enhancements.value(cfg, rec)
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

return Enhancements
