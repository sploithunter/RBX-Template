--[[
    ZoneService

    Server-authoritative area unlock and travel service. WorldBindingService owns
    the map hooks; ZoneService owns whether a player may use them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local ZoneService = {}
ZoneService.__index = ZoneService

local TOUCH_DEBOUNCE_SECONDS = 1
local DEFAULT_START_AREA = "Spawn"

local function asSet(values)
    local set = {}
    if type(values) ~= "table" then
        return set
    end

    for key, value in pairs(values) do
        if type(key) == "number" then
            set[tostring(value)] = true
        elseif value == true then
            set[tostring(key)] = true
        elseif type(value) == "string" then
            set[value] = true
        end
    end

    return set
end

local function setToSortedArray(set)
    local values = {}
    for key, enabled in pairs(set) do
        if enabled == true then
            table.insert(values, key)
        end
    end
    table.sort(values)
    return values
end

local function getRootPart(player)
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function waitForRootPart(player, timeoutSeconds)
    local character = player.Character
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
        or character:WaitForChild("HumanoidRootPart", timeoutSeconds or 5)
end

function ZoneService:Init()
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    self._dataService = self._modules.DataService
    self._worldBindingService = self._modules.WorldBindingService
    self._areasConfig = self._configLoader:LoadConfig("areas")
    self._touchDebounce = {}
end

function ZoneService:Start()
    self:_connectTravelHooks()
    self:_setupNetworkSignals()

    self._worldBindingService.AreaEntered:Connect(function(player, areaId)
        self:_handleAreaEntered(player, areaId)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self._touchDebounce[player] = nil
    end)

    Players.PlayerAdded:Connect(function(player)
        self:_connectCharacterSpawnSafety(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        self:_connectCharacterSpawnSafety(player)
    end
end

function ZoneService:_setupNetworkSignals()
    Signals.UnlockZoneRequest.OnServerEvent:Connect(function(player, payload)
        payload = type(payload) == "table" and payload or {}
        local result = self:UnlockZone(player, payload.zoneId)
        Signals.ZoneUnlockResult:FireClient(player, result)
    end)
end

function ZoneService:_getZone(zoneId)
    return self._areasConfig.zones and self._areasConfig.zones[zoneId]
end

function ZoneService:_resolveAreaId(zoneId)
    return self._worldBindingService:GetPrimaryAreaForZone(zoneId)
end

function ZoneService:_getUnlockSet(player)
    local data = self._dataService:GetData(player)
    if not data then
        return nil
    end

    data.GameData = data.GameData or {}
    local set = asSet(data.GameData.UnlockedAreas)

    for zoneId, zone in pairs(self._areasConfig.zones or {}) do
        if zone.kind == "area" and zone.unlock and zone.unlock.unlocked_by_default == true then
            set[zoneId] = true
        end
    end
    set[DEFAULT_START_AREA] = true

    data.GameData.UnlockedAreas = setToSortedArray(set)
    return set, data
end

function ZoneService:_isParentChainUnlocked(player, zoneId, unlockSet)
    local zone = self:_getZone(zoneId)
    if not zone then
        return false
    end

    local requiredZoneId = zone.unlock and zone.unlock.required_zone
    if requiredZoneId and not self:IsZoneUnlocked(player, requiredZoneId, unlockSet) then
        return false
    end

    if zone.parent then
        return self:_isParentChainUnlocked(player, zone.parent, unlockSet)
    end

    return true
end

function ZoneService:IsZoneUnlocked(player, zoneId, unlockSet)
    local zone = self:_getZone(zoneId)
    if not zone then
        return false
    end

    if zone.unlock and zone.unlock.unlocked_by_default == true then
        return true
    end

    unlockSet = unlockSet or self:_getUnlockSet(player)
    if not unlockSet then
        return false
    end

    local areaId = self:_resolveAreaId(zoneId)
    if zone.kind == "area" and unlockSet[zoneId] ~= true then
        return false
    end
    if zone.kind ~= "area" and areaId and unlockSet[areaId] ~= true then
        return false
    end

    return self:_isParentChainUnlocked(player, zoneId, unlockSet)
end

function ZoneService:GetUnlockedZones(player)
    local unlockSet = self:_getUnlockSet(player)
    if not unlockSet then
        return {}
    end
    return setToSortedArray(unlockSet)
end

function ZoneService:_connectCharacterSpawnSafety(player)
    player.CharacterAdded:Connect(function()
        task.defer(function()
            task.wait(0.2)
            self:PlacePlayerAtZoneSpawn(
                player,
                self._worldBindingService:GetActiveArea(player) or DEFAULT_START_AREA
            )
        end)
    end)

    if player.Character then
        task.defer(function()
            self:PlacePlayerAtZoneSpawn(
                player,
                self._worldBindingService:GetActiveArea(player) or DEFAULT_START_AREA
            )
        end)
    end
end

function ZoneService:PlacePlayerAtZoneSpawn(player, zoneId)
    local spawnCFrame, areaId =
        self._worldBindingService:GetSpawnCFrameForZone(zoneId or DEFAULT_START_AREA)
    if not spawnCFrame then
        return false, "missing_spawn"
    end

    local rootPart = waitForRootPart(player, 5)
    if not rootPart then
        return false, "character_not_ready"
    end

    rootPart.CFrame = spawnCFrame
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
    self._worldBindingService:SetActiveArea(player, areaId)

    local currentWorld = player:FindFirstChild("CurrentWorld")
    if currentWorld and currentWorld:IsA("StringValue") then
        currentWorld.Value = areaId
    end

    return true, nil, areaId
end

function ZoneService:UnlockZone(player, zoneId, options)
    options = options or {}

    local zone = self:_getZone(zoneId)
    if not zone then
        return {
            ok = false,
            reason = "unknown_zone",
            zoneId = zoneId,
        }
    end

    local areaId = self:_resolveAreaId(zoneId)
    if not areaId then
        return {
            ok = false,
            reason = "missing_primary_area",
            zoneId = zoneId,
        }
    end

    local unlockSet, data = self:_getUnlockSet(player)
    if not unlockSet or not data then
        return {
            ok = false,
            reason = "data_not_loaded",
            zoneId = zoneId,
        }
    end

    if unlockSet[areaId] == true then
        return {
            ok = true,
            alreadyUnlocked = true,
            zoneId = zoneId,
            areaId = areaId,
        }
    end

    local unlock = zone.unlock or self:_getZone(areaId).unlock or {}
    if options.bypassRequirements ~= true then
        local requiredZoneId = unlock.required_zone
        if requiredZoneId and not self:IsZoneUnlocked(player, requiredZoneId, unlockSet) then
            return {
                ok = false,
                reason = "required_zone_locked",
                zoneId = zoneId,
                areaId = areaId,
                requiredZoneId = requiredZoneId,
                unlock = self:GetUnlockRequirement(player, zoneId),
            }
        end

        local currency = unlock.currency
        local cost = tonumber(unlock.cost) or 0
        if currency and cost > 0 then
            if not self._dataService:CanAfford(player, currency, cost) then
                return {
                    ok = false,
                    reason = "insufficient_currency",
                    zoneId = zoneId,
                    areaId = areaId,
                    currency = currency,
                    cost = cost,
                    unlock = self:GetUnlockRequirement(player, zoneId),
                }
            end
            self._dataService:RemoveCurrency(player, currency, cost, "zone_unlock")
        end
    end

    unlockSet[areaId] = true
    data.GameData.UnlockedAreas = setToSortedArray(unlockSet)
    self._dataService:RequestSave(player, "zone_unlock", { critical = true })

    self._logger:Info("Zone unlocked", {
        player = player.Name,
        zoneId = zoneId,
        areaId = areaId,
    })

    return {
        ok = true,
        alreadyUnlocked = false,
        zoneId = zoneId,
        areaId = areaId,
    }
end

function ZoneService:GetUnlockRequirement(player, zoneId)
    local zone = self:_getZone(zoneId)
    if not zone then
        return nil
    end

    local areaId = self:_resolveAreaId(zoneId)
    local areaZone = areaId and self:_getZone(areaId) or nil
    local unlock = zone.unlock or (areaZone and areaZone.unlock) or {}
    local currency = unlock.currency
    local cost = tonumber(unlock.cost) or 0
    local requiredZoneId = unlock.required_zone
    local canAfford = currency == nil
        or cost <= 0
        or self._dataService:CanAfford(player, currency, cost)

    return {
        zoneId = zoneId,
        areaId = areaId,
        displayName = zone.display_name or (areaZone and areaZone.display_name) or zoneId,
        currency = currency,
        cost = cost,
        requiredZoneId = requiredZoneId,
        canAfford = canAfford,
    }
end

function ZoneService:TravelToZone(player, targetZoneId, sourceHook)
    local targetAreaId = self:_resolveAreaId(targetZoneId)
    if not targetAreaId then
        return {
            ok = false,
            reason = "missing_primary_area",
            targetZoneId = targetZoneId,
        }
    end

    if not self:IsZoneUnlocked(player, targetZoneId) then
        return {
            ok = false,
            reason = "locked",
            targetZoneId = targetZoneId,
            targetAreaId = targetAreaId,
            unlock = self:GetUnlockRequirement(player, targetZoneId),
        }
    end

    local destinationCFrame = self._worldBindingService:GetSpawnCFrameForZone(targetZoneId)
    if not destinationCFrame then
        return {
            ok = false,
            reason = "missing_spawn",
            targetZoneId = targetZoneId,
            targetAreaId = targetAreaId,
        }
    end

    local rootPart = getRootPart(player)
    if not rootPart then
        return {
            ok = false,
            reason = "character_not_ready",
            targetZoneId = targetZoneId,
            targetAreaId = targetAreaId,
        }
    end

    rootPart.CFrame = destinationCFrame
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
    self._worldBindingService:SetActiveArea(player, targetAreaId)

    local currentWorld = player:FindFirstChild("CurrentWorld")
    if currentWorld and currentWorld:IsA("StringValue") then
        currentWorld.Value = targetAreaId
    end

    self._logger:Info("Player traveled to zone", {
        player = player.Name,
        targetZoneId = targetZoneId,
        targetAreaId = targetAreaId,
        sourceHook = sourceHook and sourceHook:GetFullName() or nil,
    })

    return {
        ok = true,
        targetZoneId = targetZoneId,
        targetAreaId = targetAreaId,
        position = rootPart.Position,
    }
end

function ZoneService:TravelViaHook(player, hook)
    local targetZoneId = hook and hook:GetAttribute("TargetZoneId")
    if type(targetZoneId) ~= "string" or targetZoneId == "" then
        return {
            ok = false,
            reason = "missing_target",
        }
    end

    return self:TravelToZone(player, targetZoneId, hook)
end

function ZoneService:_connectTravelHooks()
    local hooks = {}
    for _, hook in ipairs(self._worldBindingService:GetBound("TeleportPad")) do
        table.insert(hooks, hook)
    end
    for _, hook in ipairs(self._worldBindingService:GetBound("Portal")) do
        table.insert(hooks, hook)
    end

    for _, hook in ipairs(hooks) do
        if not hook:GetAttribute("ZoneServiceConnected") then
            hook:SetAttribute("ZoneServiceConnected", true)
            hook.Touched:Connect(function(hit)
                self:_handleHookTouched(hook, hit)
            end)
        end
    end
end

function ZoneService:_handleHookTouched(hook, hit)
    local character = hit and hit.Parent
    local player = character and Players:GetPlayerFromCharacter(character)
    if not player then
        return
    end

    local now = os.clock()
    local playerDebounce = self._touchDebounce[player] or {}
    self._touchDebounce[player] = playerDebounce
    if playerDebounce[hook] and now - playerDebounce[hook] < TOUCH_DEBOUNCE_SECONDS then
        return
    end
    playerDebounce[hook] = now

    local result = self:TravelViaHook(player, hook)
    Signals.ZoneTravelResult:FireClient(player, result)
end

function ZoneService:_handleAreaEntered(player, areaId)
    if self:IsZoneUnlocked(player, areaId) then
        return
    end

    self._logger:Warn("Player entered locked area; returning to start area", {
        player = player.Name,
        areaId = areaId,
    })

    self:TravelToZone(player, DEFAULT_START_AREA)
end

return ZoneService
