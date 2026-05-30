--[[
    ArchetypeService — Feature 13 (Halo & Horns).

    Owns profile.Archetype (lazy-init nil = unselected). The archetype gates the
    power pool (Feature 14) and is orthogonal to Soul/alignment. It can only change
    via the respec ritual, which also resets profile.Powers + profile.Slots
    (Features 14/15). Pure rules live in `src/Shared/Game/ArchetypeLogic.lua`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArchetypeLogic = require(ReplicatedStorage.Shared.Game.ArchetypeLogic)

local ArchetypeService = {}
ArchetypeService.__index = ArchetypeService

function ArchetypeService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._config = self._configLoader:LoadConfig("archetypes")
end

function ArchetypeService:GetState(player)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    return {
        ok = true,
        archetype = data.Archetype,
        available = ArchetypeLogic.availablePowers(data.Archetype, self._config),
    }
end

function ArchetypeService:List()
    return { ok = true, archetypes = ArchetypeLogic.list(self._config) }
end

-- Select an archetype. One-time: once set, only the respec ritual can change it.
function ArchetypeService:Select(player, archetype)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    if data.Archetype then
        return { ok = false, reason = "already_selected", archetype = data.Archetype }
    end
    if not ArchetypeLogic.isValid(archetype, self._config) then
        return { ok = false, reason = "invalid_archetype" }
    end
    data.Archetype = archetype
    self._dataService:RequestSave(player, "archetype_select", { critical = true })
    return { ok = true, archetype = archetype }
end

-- Respec ritual: reset powers + augmentation slots, and (optionally) pick a new
-- archetype. Without newArchetype, clears the selection so the player re-picks.
function ArchetypeService:Respec(player, newArchetype)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    if newArchetype ~= nil and not ArchetypeLogic.isValid(newArchetype, self._config) then
        return { ok = false, reason = "invalid_archetype" }
    end
    data.Powers = {}
    data.Slots = {}
    data.Hotbar = {} -- fresh hotbar for the new archetype (re-defaults on next read)
    data.Archetype = newArchetype -- nil => must re-select
    self._dataService:RequestSave(player, "archetype_respec", { critical = true })
    return { ok = true, archetype = data.Archetype }
end

return ArchetypeService
