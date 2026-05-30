--[[
    HotbarService — Feature 16 (Hotbar / Command Bar).

    Owns profile.Hotbar (string slot index -> bind { type, target }). New players
    are initialized with archetype defaults on first read. Rebinds persist. Pure
    rules: `src/Shared/Game/HotbarLogic.lua`. (Key-press firing is client/[studio].)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HotbarLogic = require(ReplicatedStorage.Shared.Game.HotbarLogic)
local ArchetypeLogic = require(ReplicatedStorage.Shared.Game.ArchetypeLogic)

local HotbarService = {}
HotbarService.__index = HotbarService

function HotbarService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._config = self._configLoader:LoadConfig("hotbar")
    self._archetypesConfig = self._configLoader:LoadConfig("archetypes")
end

local function isEmptyMap(t)
    if type(t) ~= "table" then
        return true
    end
    for _ in pairs(t) do
        return false
    end
    return true
end

-- Initialize archetype defaults into a string-keyed hotbar (once, when empty).
function HotbarService:_ensureDefaults(data)
    if type(data.Hotbar) ~= "table" then
        data.Hotbar = {}
    end
    if isEmptyMap(data.Hotbar) and data.Archetype then
        local available = ArchetypeLogic.availablePowers(data.Archetype, self._archetypesConfig)
        for index, bind in pairs(HotbarLogic.defaultBindings(available, self._config)) do
            data.Hotbar[tostring(index)] = bind
        end
    end
    return data.Hotbar
end

function HotbarService:GetState(player)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    return { ok = true, hotbar = self:_ensureDefaults(data), slot_count = self._config.slot_count }
end

-- Rebind a slot. `bind` is { type, target } or nil to clear.
function HotbarService:Rebind(player, index, bind)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    local decision = HotbarLogic.canRebind(index, bind, self._config)
    if not decision.ok then
        return { ok = false, reason = decision.reason }
    end
    local hotbar = self:_ensureDefaults(data)
    hotbar[tostring(index)] = bind -- nil clears
    self._dataService:RequestSave(player, "hotbar_rebind", { critical = false })
    return { ok = true, hotbar = hotbar }
end

return HotbarService
