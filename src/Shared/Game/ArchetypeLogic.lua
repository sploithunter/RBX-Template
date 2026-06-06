--[[
    ArchetypeLogic — pure functional core for the archetype system (Feature 13).

    No Roblox APIs; config-driven (configs/archetypes.lua). The service wraps these
    over profile state.

      isValid(archetype, config)            -> boolean
      list(config)                          -> array of archetype keys (sorted)
      availablePowers(archetype, config)    -> array of power ids ({} if invalid/nil)
      hasPower(archetype, powerId, config)  -> boolean (power is in the pool)
]]

local ArchetypeLogic = {}

local function archetypeEntry(archetype, config)
    if not archetype or not config or type(config.archetypes) ~= "table" then
        return nil
    end
    return config.archetypes[archetype]
end

function ArchetypeLogic.isValid(archetype, config)
    return archetypeEntry(archetype, config) ~= nil
end

function ArchetypeLogic.list(config)
    local keys = {}
    if config and type(config.archetypes) == "table" then
        for key in pairs(config.archetypes) do
            table.insert(keys, key)
        end
    end
    table.sort(keys)
    return keys
end

function ArchetypeLogic.availablePowers(archetype, config)
    local entry = archetypeEntry(archetype, config)
    if not entry or type(entry.power_pool) ~= "table" then
        return {}
    end
    local out = {}
    for _, powerId in ipairs(entry.power_pool) do
        table.insert(out, powerId)
    end
    -- Append the GENERIC pool (universal powers any archetype can pick), if defined.
    if type(config) == "table" and type(config.generic_pool) == "table" then
        for _, powerId in ipairs(config.generic_pool) do
            table.insert(out, powerId)
        end
    end
    return out
end

function ArchetypeLogic.hasPower(archetype, powerId, config)
    local entry = archetypeEntry(archetype, config)
    if not entry or type(entry.power_pool) ~= "table" then
        return false
    end
    for _, id in ipairs(entry.power_pool) do
        if id == powerId then
            return true
        end
    end
    -- generic powers are available to every archetype
    if type(config) == "table" and type(config.generic_pool) == "table" then
        for _, id in ipairs(config.generic_pool) do
            if id == powerId then
                return true
            end
        end
    end
    return false
end

return ArchetypeLogic
