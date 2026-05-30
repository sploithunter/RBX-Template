--[[
    PowerService — Feature 14 (Power Selection at Level-Up).

    Owns profile.Powers (ordered list of selected power ids). At each selection
    level the player picks ONE power from their archetype's pool; selections
    accumulate + persist. Pure rules: `src/Shared/Game/PowerSelection.lua`;
    archetype gating via `ArchetypeLogic`. Respec (ArchetypeService) clears the list.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerSelection = require(ReplicatedStorage.Shared.Game.PowerSelection)
local ArchetypeLogic = require(ReplicatedStorage.Shared.Game.ArchetypeLogic)

local PowerService = {}
PowerService.__index = PowerService

function PowerService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._powersConfig = self._configLoader:LoadConfig("powers")
    self._archetypesConfig = self._configLoader:LoadConfig("archetypes")
end

function PowerService:_level(player, override)
    if override then
        return math.max(1, math.floor(override))
    end
    local locator = _G.RBXTemplateServices
    local ok, progression = pcall(function()
        return locator and locator:Get("PlayerProgressionService")
    end)
    if ok and progression and progression.GetLevel then
        return progression:GetLevel(player)
    end
    return 1
end

local function powersList(data)
    if type(data.Powers) ~= "table" then
        data.Powers = {}
    end
    return data.Powers
end

function PowerService:GetState(player, levelOverride)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    local selected = powersList(data)
    local level = self:_level(player, levelOverride)
    local levels = self._powersConfig.selection_levels
    local available = ArchetypeLogic.availablePowers(data.Archetype, self._archetypesConfig)
    return {
        ok = true,
        powers = selected,
        pending = PowerSelection.pendingSelections(level, #selected, levels),
        available = available,
    }
end

function PowerService:Select(player, powerId, levelOverride)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    if not data.Archetype then
        return { ok = false, reason = "no_archetype" }
    end
    local selected = powersList(data)
    local level = self:_level(player, levelOverride)
    local available = ArchetypeLogic.availablePowers(data.Archetype, self._archetypesConfig)
    local decision = PowerSelection.canSelect(
        powerId,
        available,
        selected,
        level,
        self._powersConfig.selection_levels
    )
    if not decision.ok then
        return { ok = false, reason = decision.reason }
    end
    table.insert(selected, powerId)
    self._dataService:RequestSave(player, "power_select", { critical = true })
    return { ok = true, powers = selected }
end

return PowerService
