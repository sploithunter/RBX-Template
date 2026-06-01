--[[
    HotbarService — Feature 16 (Hotbar / Command Bar).

    Owns profile.Hotbar (string slot index -> bind { type, target }). New players
    are initialized with archetype defaults on first read. Rebinds persist. Pure
    rules: `src/Shared/Game/HotbarLogic.lua`. (Key-press firing is client/[studio].)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HotbarLogic = require(ReplicatedStorage.Shared.Game.HotbarLogic)
local ArchetypeLogic = require(ReplicatedStorage.Shared.Game.ArchetypeLogic)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local HotbarService = {}
HotbarService.__index = HotbarService

function HotbarService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._config = self._configLoader:LoadConfig("hotbar")
    self._archetypesConfig = self._configLoader:LoadConfig("archetypes")

    -- Client fires a slot (1-20); we resolve the bind authoritatively + execute.
    Signals.Hotbar_Activate.OnServerEvent:Connect(function(player, payload)
        pcall(function()
            self:Activate(player, payload)
        end)
    end)
    -- Client asks for its bindings to draw the command bar.
    Signals.Hotbar_RequestState.OnServerEvent:Connect(function(player)
        local state = self:GetState(player)
        if state.ok then
            Signals.Hotbar_State:FireClient(player, {
                hotbar = state.hotbar,
                slot_count = state.slot_count,
            })
        end
    end)
end

-- Resolve another service at runtime (avoids boot-order cycles).
function HotbarService:_service(name)
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get(name)
    end)
    return ok and service or nil
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

-- Fire the bind on a hotbar slot. `payload` is the slot index (1-20) or { slot = n }.
-- Authoritative: we read the player's own binding and dispatch by type. Tactical
-- commands run on the squad now; power/roster/pet effects land when those systems do.
function HotbarService:Activate(player, payload)
    local slot = tonumber(type(payload) == "table" and payload.slot or payload)
    if not slot or not HotbarLogic.isValidSlot(slot, self._config) then
        return { ok = false, reason = "invalid_slot" }
    end
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    local bind = HotbarLogic.bindAt(self:_ensureDefaults(data), slot)
    if not bind then
        return { ok = false, reason = "empty_slot" }
    end

    if bind.type == "tactical" then
        local enemy = self:_service("EnemyService")
        if enemy and enemy.ExecuteTactical then
            enemy:ExecuteTactical(player, bind.target)
            return { ok = true, type = "tactical", command = bind.target }
        end
        return { ok = false, reason = "tactical_unavailable" }
    elseif bind.type == "pet" then
        -- Summon/redeploy the bound pet slot (re-uses the squad summon path).
        local enemy = self:_service("EnemyService")
        if enemy and enemy.SummonPet then
            enemy:SummonPet(player, { slot = tonumber(bind.target) })
            return { ok = true, type = "pet", target = bind.target }
        end
        return { ok = false, reason = "summon_unavailable" }
    end

    -- power / roster: effects not wired yet (support-power system is a later slice).
    if self._logger then
        self._logger:Info("Hotbar activate (no effect yet)", {
            type = bind.type,
            target = bind.target,
            slot = slot,
        })
    end
    return { ok = false, reason = "not_implemented", type = bind.type, target = bind.target }
end

return HotbarService
