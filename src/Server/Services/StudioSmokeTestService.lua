--[[
    StudioSmokeTestService

    Studio-only RemoteFunction bridge used by MCP smoke tests. This lets tests
    coordinate real client UI behavior while keeping currency, inventory, and
    server-authoritative gameplay assertions on the server.
]]

local StudioSmokeTestService = {}
StudioSmokeTestService.__index = StudioSmokeTestService

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local REMOTE_NAME = "StudioSmokeTest"

local logger
local configLoader
local dataService
local inventoryService
local economyService
local worldBindingService
local zoneService
local upgradeService
local breakableSpawner

local sessions = {}
local travelSessions = {}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

local function countPets(petsBucket)
    local total = 0
    local items = petsBucket and petsBucket.items
    if type(items) ~= "table" then
        return total
    end

    for _, item in pairs(items) do
        total += tonumber(item.quantity) or 1
    end

    return total
end

local function findEggByType(eggType)
    for _, instance in ipairs(workspace:GetChildren()) do
        if instance:IsA("Model") then
            local modelEggType = instance:GetAttribute("EggType")
            local eggTypeValue = instance:FindFirstChild("EggType")
            if eggTypeValue then
                modelEggType = eggTypeValue.Value
            end

            if modelEggType == eggType then
                return instance
            end
        end
    end

    return nil
end

local function getEggAnchor(egg)
    if not egg then
        return nil
    end

    local spawnPointRef = egg:FindFirstChild("SpawnPoint")
    local anchor = spawnPointRef and spawnPointRef.Value
    if anchor then
        return anchor
    end

    return egg.PrimaryPart or egg:FindFirstChildOfClass("BasePart")
end

local function getRootPart(player)
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function movePlayer(player, position)
    local rootPart = getRootPart(player)
    if not rootPart then
        return false, "HumanoidRootPart not ready"
    end

    rootPart.CFrame = CFrame.new(position)
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
    return true
end

function StudioSmokeTestService:Init()
    logger = self._modules.Logger
    configLoader = self._modules.ConfigLoader
    dataService = self._modules.DataService
    inventoryService = self._modules.InventoryService
    economyService = self._modules.EconomyService
    worldBindingService = self._modules.WorldBindingService
    zoneService = self._modules.ZoneService
    upgradeService = self._modules.UpgradeService
    breakableSpawner = self._modules.BreakableSpawner
end

function StudioSmokeTestService:Start()
    if not RunService:IsStudio() then
        return
    end

    local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
    if existing then
        existing:Destroy()
    end

    local remote = Instance.new("RemoteFunction")
    remote.Name = REMOTE_NAME
    remote.OnServerInvoke = function(player, action, payload)
        return self:_handleRequest(player, action, payload or {})
    end
    remote.Parent = ReplicatedStorage

    Players.PlayerRemoving:Connect(function(player)
        sessions[player.UserId] = nil
        travelSessions[player.UserId] = nil
    end)

    logger:Info("Studio smoke test bridge ready", {
        context = "StudioSmokeTestService",
        remote = REMOTE_NAME,
    })
end

function StudioSmokeTestService:_handleRequest(player, action, payload)
    if not RunService:IsStudio() then
        return {
            ok = false,
            error = "Studio smoke bridge is disabled outside Studio",
        }
    end

    if action == "BeginEggProximity" then
        return self:_beginEggProximity(player, payload)
    elseif action == "MoveEggProximity" then
        return self:_moveEggProximity(player, payload)
    elseif action == "HatchEggProximity" then
        return self:_hatchEggProximity(player, payload)
    elseif action == "RestoreEggProximity" then
        return self:_restoreEggProximity(player)
    elseif action == "BeginTravelSmoke" then
        return self:_beginTravelSmoke(player, payload)
    elseif action == "UseTravelSmoke" then
        return self:_useTravelSmoke(player)
    elseif action == "UnlockTravelSmoke" then
        return self:_unlockTravelSmoke(player)
    elseif action == "RestoreTravelSmoke" then
        return self:_restoreTravelSmoke(player)
    elseif action == "CheckSpawnSafetySmoke" then
        return self:_checkSpawnSafetySmoke(player, payload)
    elseif action == "RunPhase2ProgressionSmoke" then
        return self:_runPhase2ProgressionSmoke(player, payload)
    elseif action == "RunMeadowBreakableSmoke" then
        return self:_runMeadowBreakableSmoke(player, payload)
    elseif action == "RunSyntheticExpansionSmoke" then
        return self:_runSyntheticExpansionSmoke(player, payload)
    end

    return {
        ok = false,
        error = "Unknown smoke action: " .. tostring(action),
    }
end

function StudioSmokeTestService:_beginEggProximity(player, payload)
    local eggType = payload.eggType or "basic_egg"
    local petsConfig = configLoader:LoadConfig("pets")
    local eggSystemConfig = configLoader:LoadConfig("egg_system")
    local eggData = petsConfig.egg_sources[eggType]
    if not eggData then
        return {
            ok = false,
            error = "Unknown egg type: " .. tostring(eggType),
        }
    end

    local egg = findEggByType(eggType)
    local anchor = getEggAnchor(egg)
    if not anchor then
        return {
            ok = false,
            error = "Egg anchor not found for " .. tostring(eggType),
        }
    end

    local data = dataService:GetData(player)
    if not data or not data.Inventory then
        return {
            ok = false,
            error = "Player data not loaded",
        }
    end

    local originalCurrency = dataService:GetCurrency(player, eggData.currency)
    local originalPetsBucket = deepCopy(data.Inventory.pets or { items = {} })
    local requiredCurrency = eggData.cost + math.max(25, math.floor(eggData.cost * 0.1))

    dataService:SetCurrency(player, eggData.currency, requiredCurrency, "egg_smoke_setup")

    local maxDistance = eggSystemConfig.proximity.max_distance
    local anchorPosition = anchor.Position

    sessions[player.UserId] = {
        eggType = eggType,
        currency = eggData.currency,
        cost = eggData.cost,
        originalCurrency = originalCurrency,
        originalPetsBucket = originalPetsBucket,
        originalPetCount = countPets(originalPetsBucket),
        farPosition = anchorPosition + Vector3.new(maxDistance + 80, 4, 0),
        nearPosition = anchorPosition + Vector3.new(0, 4, 0),
        cooldown = eggSystemConfig.cooldowns.purchase_cooldown or 0,
    }

    return {
        ok = true,
        eggType = eggType,
        currency = eggData.currency,
        cost = eggData.cost,
        maxDistance = maxDistance,
        originalCurrency = originalCurrency,
        originalPetCount = sessions[player.UserId].originalPetCount,
        currentCurrency = dataService:GetCurrency(player, eggData.currency),
    }
end

function StudioSmokeTestService:_moveEggProximity(player, payload)
    local session = sessions[player.UserId]
    if not session then
        return {
            ok = false,
            error = "Egg proximity smoke session has not started",
        }
    end

    local placement = payload.placement or "near"
    local position = placement == "far" and session.farPosition or session.nearPosition
    local success, errorMessage = movePlayer(player, position)
    return {
        ok = success,
        error = errorMessage,
        placement = placement,
    }
end

function StudioSmokeTestService:_hatchEggProximity(player)
    local session = sessions[player.UserId]
    if not session then
        return {
            ok = false,
            error = "Egg proximity smoke session has not started",
        }
    end

    local EggService = require(ServerScriptService.Server.Services.EggService)
    local beforeCurrency = dataService:GetCurrency(player, session.currency)
    local data = dataService:GetData(player)
    local beforePetCount = countPets(data.Inventory and data.Inventory.pets)
    local hatchResult, hatchMessage =
        EggService:HandleEggPurchase(player, session.eggType, "Single")
    local afterData = dataService:GetData(player)

    return {
        ok = true,
        resultType = type(hatchResult),
        result = hatchResult,
        message = hatchMessage,
        beforeCurrency = beforeCurrency,
        afterCurrency = dataService:GetCurrency(player, session.currency),
        beforePetCount = beforePetCount,
        afterPetCount = countPets(afterData.Inventory and afterData.Inventory.pets),
        currency = session.currency,
        cost = session.cost,
        cooldown = session.cooldown,
    }
end

function StudioSmokeTestService:_restoreEggProximity(player)
    local session = sessions[player.UserId]
    if not session then
        return {
            ok = true,
            restored = false,
        }
    end

    dataService:SetCurrency(player, session.currency, session.originalCurrency, "egg_smoke_restore")

    local data = dataService:GetData(player)
    if data and data.Inventory then
        data.Inventory.pets = deepCopy(session.originalPetsBucket)
        if inventoryService and inventoryService._updateBucketFolders then
            inventoryService:_updateBucketFolders(player, "pets")
        end
    end

    dataService:RequestSave(player, "egg_smoke_restore", { critical = true })
    sessions[player.UserId] = nil

    return {
        ok = true,
        restored = true,
        currency = session.currency,
        restoredCurrency = session.originalCurrency,
        restoredPetCount = session.originalPetCount,
    }
end

local function removeArrayValue(values, target)
    if type(values) ~= "table" then
        return {}
    end

    local result = {}
    for key, value in pairs(values) do
        if type(key) == "number" then
            if value ~= target then
                table.insert(result, value)
            end
        elseif key ~= target then
            result[key] = value
        end
    end
    return result
end

local function findTravelPad(sourceAreaId, targetZoneId)
    if not worldBindingService then
        return nil
    end

    for _, pad in ipairs(worldBindingService:GetTeleportPadsForArea(sourceAreaId)) do
        if pad:GetAttribute("TargetZoneId") == targetZoneId then
            return pad
        end
    end
    return nil
end

function StudioSmokeTestService:_beginTravelSmoke(player, payload)
    if not worldBindingService or not zoneService then
        return {
            ok = false,
            error = "Zone smoke dependencies are not loaded",
        }
    end

    local sourceAreaId = payload.sourceAreaId or "Spawn"
    local targetZoneId = payload.targetZoneId or "Meadow"
    local targetAreaId = worldBindingService:GetPrimaryAreaForZone(targetZoneId)
    if not targetAreaId then
        return {
            ok = false,
            error = "Target zone has no primary area: " .. tostring(targetZoneId),
        }
    end

    local pad = findTravelPad(sourceAreaId, targetZoneId)
    if not pad then
        return {
            ok = false,
            error = "TeleportPad not found from " .. tostring(sourceAreaId) .. " to " .. tostring(
                targetZoneId
            ),
        }
    end

    local data = dataService:GetData(player)
    if not data or not data.GameData then
        return {
            ok = false,
            error = "Player data not loaded",
        }
    end

    local originalUnlockedAreas = deepCopy(data.GameData.UnlockedAreas or {})
    data.GameData.UnlockedAreas = removeArrayValue(data.GameData.UnlockedAreas, targetAreaId)
    zoneService:GetUnlockedZones(player)

    local sourceCFrame = worldBindingService:GetSpawnCFrameForZone(sourceAreaId)
    if sourceCFrame then
        movePlayer(player, sourceCFrame.Position)
        worldBindingService:SetActiveArea(player, sourceAreaId)
    end

    travelSessions[player.UserId] = {
        sourceAreaId = sourceAreaId,
        targetZoneId = targetZoneId,
        targetAreaId = targetAreaId,
        pad = pad,
        originalUnlockedAreas = originalUnlockedAreas,
    }

    return {
        ok = true,
        sourceAreaId = sourceAreaId,
        targetZoneId = targetZoneId,
        targetAreaId = targetAreaId,
        pad = pad:GetFullName(),
        unlockedAreas = zoneService:GetUnlockedZones(player),
        activeArea = worldBindingService:GetActiveArea(player),
    }
end

function StudioSmokeTestService:_useTravelSmoke(player)
    local session = travelSessions[player.UserId]
    if not session then
        return {
            ok = false,
            error = "Travel smoke session has not started",
        }
    end

    local result = zoneService:TravelViaHook(player, session.pad)
    local rootPart = getRootPart(player)
    result.activeArea = worldBindingService:GetActiveArea(player)
    result.rootPosition = rootPart and rootPart.Position or nil
    return result
end

function StudioSmokeTestService:_unlockTravelSmoke(player)
    local session = travelSessions[player.UserId]
    if not session then
        return {
            ok = false,
            error = "Travel smoke session has not started",
        }
    end

    local result =
        zoneService:UnlockZone(player, session.targetZoneId, { bypassRequirements = true })
    result.unlockedAreas = zoneService:GetUnlockedZones(player)
    return result
end

function StudioSmokeTestService:_restoreTravelSmoke(player)
    local session = travelSessions[player.UserId]
    if not session then
        return {
            ok = true,
            restored = false,
        }
    end

    local data = dataService:GetData(player)
    if data then
        data.GameData = data.GameData or {}
        data.GameData.UnlockedAreas = deepCopy(session.originalUnlockedAreas)
    end

    local sourceCFrame = worldBindingService:GetSpawnCFrameForZone(session.sourceAreaId)
    if sourceCFrame then
        movePlayer(player, sourceCFrame.Position)
        worldBindingService:SetActiveArea(player, session.sourceAreaId)
    end

    dataService:RequestSave(player, "travel_smoke_restore", { critical = true })
    travelSessions[player.UserId] = nil

    return {
        ok = true,
        restored = true,
        sourceAreaId = session.sourceAreaId,
        targetZoneId = session.targetZoneId,
    }
end

local function raycastDownFrom(position, excludeInstances)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeInstances or {}
    params.IgnoreWater = true
    return workspace:Raycast(position, Vector3.new(0, -500, 0), params)
end

function StudioSmokeTestService:_checkSpawnSafetySmoke(player, payload)
    if not worldBindingService or not zoneService then
        return {
            ok = false,
            error = "Zone smoke dependencies are not loaded",
        }
    end

    local zoneId = payload.zoneId or "Spawn"
    local placed, placeError, areaId = zoneService:PlacePlayerAtZoneSpawn(player, zoneId)
    if not placed then
        return {
            ok = false,
            error = placeError or "Failed to place player at zone spawn",
        }
    end

    task.wait(0.2)

    local rootPart = getRootPart(player)
    if not rootPart then
        return {
            ok = false,
            error = "HumanoidRootPart not ready",
        }
    end

    local result = raycastDownFrom(rootPart.Position, { player.Character })
    if not result then
        return {
            ok = false,
            error = "No floor found below spawn position",
            areaId = areaId,
            rootPosition = rootPart.Position,
        }
    end

    local floorDistance = rootPart.Position.Y - result.Position.Y
    local verticalVelocity = rootPart.AssemblyLinearVelocity.Y

    return {
        ok = true,
        areaId = areaId,
        rootPosition = rootPart.Position,
        floorPosition = result.Position,
        floorDistance = floorDistance,
        verticalVelocity = verticalVelocity,
        activeArea = worldBindingService:GetActiveArea(player),
    }
end

function StudioSmokeTestService:_runPhase2ProgressionSmoke(player, payload)
    if not zoneService or not upgradeService then
        return {
            ok = false,
            error = "Phase 2 smoke dependencies are not loaded",
        }
    end

    local targetZoneId = payload.targetZoneId or "Meadow"
    local targetAreaId = worldBindingService:GetPrimaryAreaForZone(targetZoneId) or targetZoneId
    local areasConfig = configLoader:LoadConfig("areas")
    local inventoryConfig = configLoader:LoadConfig("inventory")
    local targetZone = areasConfig.zones[targetZoneId]
    local unlock = targetZone and targetZone.unlock or {}
    local unlockCurrency = unlock.currency or "crystals"
    local unlockCost = tonumber(unlock.cost) or 0

    local data = dataService:GetData(player)
    if not data then
        return {
            ok = false,
            error = "Player data not loaded",
        }
    end

    local original = {
        coins = dataService:GetCurrency(player, "coins"),
        crystals = dataService:GetCurrency(player, "crystals"),
        upgrades = deepCopy(data.Upgrades or {}),
        unlockedAreas = deepCopy(data.GameData and data.GameData.UnlockedAreas or {}),
        petsBucket = deepCopy(data.Inventory and data.Inventory.pets or nil),
    }

    local function restore()
        dataService:SetCurrency(player, "coins", original.coins, "phase2_smoke_restore")
        dataService:SetCurrency(player, "crystals", original.crystals, "phase2_smoke_restore")

        data.Upgrades = deepCopy(original.upgrades)
        data.GameData = data.GameData or {}
        data.GameData.UnlockedAreas = deepCopy(original.unlockedAreas)
        data.Inventory = data.Inventory or {}
        if original.petsBucket then
            data.Inventory.pets = deepCopy(original.petsBucket)
        end

        if inventoryService then
            if inventoryService._updateBucketFolders then
                inventoryService:_updateBucketFolders(player, "pets")
            end
            if inventoryService._updateEquippedFolders then
                inventoryService:_updateEquippedFolders(player, "pets")
            end
        end
        dataService:RequestSave(player, "phase2_smoke_restore", { critical = true })
    end

    local ok, result = pcall(function()
        data.GameData = data.GameData or {}
        data.GameData.UnlockedAreas = removeArrayValue(data.GameData.UnlockedAreas, targetAreaId)
        zoneService:GetUnlockedZones(player)

        dataService:SetCurrency(player, unlockCurrency, 0, "phase2_smoke_setup")
        local lockedUnlock = zoneService:UnlockZone(player, targetZoneId)
        if lockedUnlock.ok or lockedUnlock.reason ~= "insufficient_currency" then
            error("Expected insufficient currency before zone unlock")
        end
        if not lockedUnlock.unlock or lockedUnlock.unlock.cost ~= unlockCost then
            error("Expected locked zone response to include unlock requirement")
        end

        dataService:SetCurrency(player, unlockCurrency, unlockCost, "phase2_smoke_setup")
        local paidUnlock = zoneService:UnlockZone(player, targetZoneId)
        if not paidUnlock.ok then
            error("Expected paid zone unlock to succeed: " .. tostring(paidUnlock.reason))
        end

        local equipCost = upgradeService:GetUpgradeCost(player, "pet_equip_slots")
        dataService:SetCurrency(player, equipCost.currency, equipCost.amount, "phase2_smoke_setup")
        local equipPurchase = upgradeService:PurchaseUpgrade(player, "pet_equip_slots")
        if not equipPurchase.ok then
            error(
                "Expected pet equip upgrade purchase to succeed: " .. tostring(equipPurchase.reason)
            )
        end

        local basePetSlots = inventoryConfig.equipped.pets.slots
        local maxPetSlots = inventoryService:_getMaxEquippedSlots(player, "pets", basePetSlots)
        if maxPetSlots ~= basePetSlots + 1 then
            error("Expected pet equip slots to increase by 1")
        end

        local storageCost = upgradeService:GetUpgradeCost(player, "pet_storage")
        local beforeStorageSlots = data.Inventory.pets.total_slots
        dataService:SetCurrency(
            player,
            storageCost.currency,
            storageCost.amount,
            "phase2_smoke_setup"
        )
        local storagePurchase = upgradeService:PurchaseUpgrade(player, "pet_storage")
        if not storagePurchase.ok then
            error(
                "Expected pet storage upgrade purchase to succeed: "
                    .. tostring(storagePurchase.reason)
            )
        end

        local afterStorageSlots = data.Inventory.pets.total_slots
        if afterStorageSlots <= beforeStorageSlots then
            error("Expected pet storage slots to increase")
        end

        local crystalValueCost = upgradeService:GetUpgradeCost(player, "crystal_value")
        dataService:SetCurrency(
            player,
            crystalValueCost.currency,
            crystalValueCost.amount,
            "phase2_smoke_setup"
        )
        local crystalValuePurchase = upgradeService:PurchaseUpgrade(player, "crystal_value")
        if not crystalValuePurchase.ok then
            error(
                "Expected crystal value upgrade purchase to succeed: "
                    .. tostring(crystalValuePurchase.reason)
            )
        end

        local baseCrystalReward = 100
        local resolvedCrystalReward = economyService:ResolveRewardAmount(baseCrystalReward, {
            player = player,
            kind = "breakable_reward",
            currency = "crystals",
            source = "Phase2ProgressionSmoke",
        })
        if resolvedCrystalReward <= baseCrystalReward then
            error("Expected crystal value upgrade to increase resolved crystal rewards")
        end

        return {
            ok = true,
            targetZoneId = targetZoneId,
            targetAreaId = targetAreaId,
            unlockCurrency = unlockCurrency,
            unlockCost = unlockCost,
            paidUnlock = paidUnlock,
            equipLevel = upgradeService:GetUpgradeLevel(player, "pet_equip_slots"),
            maxPetSlots = maxPetSlots,
            storageLevel = upgradeService:GetUpgradeLevel(player, "pet_storage"),
            beforeStorageSlots = beforeStorageSlots,
            afterStorageSlots = afterStorageSlots,
            crystalValueLevel = upgradeService:GetUpgradeLevel(player, "crystal_value"),
            baseCrystalReward = baseCrystalReward,
            resolvedCrystalReward = resolvedCrystalReward,
        }
    end)

    restore()

    if not ok then
        return {
            ok = false,
            error = tostring(result),
            restored = true,
        }
    end

    result.restored = true
    return result
end

function StudioSmokeTestService:_runMeadowBreakableSmoke(player, payload)
    payload = payload or {}
    if not (zoneService and worldBindingService and breakableSpawner and economyService) then
        return {
            ok = false,
            error = "Meadow breakable smoke dependencies are not loaded",
        }
    end

    local sourceAreaId = payload.sourceAreaId or "Spawn"
    local targetZoneId = payload.targetZoneId or "Meadow"
    local targetAreaId = worldBindingService:GetPrimaryAreaForZone(targetZoneId) or targetZoneId
    local breakableId = payload.breakableId or "BigBlueCrystal"
    local data = dataService:GetData(player)
    if not data then
        return {
            ok = false,
            error = "Player data not loaded",
        }
    end

    local crystalsRoot = workspace:FindFirstChild("Game")
        and workspace.Game:FindFirstChild("Breakables")
        and workspace.Game.Breakables:FindFirstChild("Crystals")
    local worldFolder = crystalsRoot and crystalsRoot:FindFirstChild(targetAreaId)
    if not worldFolder then
        return {
            ok = false,
            error = "Missing breakable area folder: " .. tostring(targetAreaId),
        }
    end

    local currentItems = worldFolder:FindFirstChild("CurrentItems")
    local original = {
        coins = dataService:GetCurrency(player, "coins"),
        crystals = dataService:GetCurrency(player, "crystals"),
        upgrades = deepCopy(data.Upgrades or {}),
        unlockedAreas = deepCopy(data.GameData and data.GameData.UnlockedAreas or {}),
        activeArea = worldBindingService:GetActiveArea(player),
        breakablesBroken = dataService:GetCounter(player, "breakables_broken"),
        currentItems = currentItems and currentItems.Value or nil,
    }

    local spawnedModel
    local function restore()
        if spawnedModel and spawnedModel.Parent then
            spawnedModel:Destroy()
            task.wait(0.1)
        end

        dataService:SetCurrency(player, "coins", original.coins, "meadow_breakable_smoke_restore")
        dataService:SetCurrency(
            player,
            "crystals",
            original.crystals,
            "meadow_breakable_smoke_restore"
        )
        data.Upgrades = deepCopy(original.upgrades)
        data.GameData = data.GameData or {}
        data.GameData.UnlockedAreas = deepCopy(original.unlockedAreas)
        dataService:SetCounter(player, "breakables_broken", original.breakablesBroken)

        if currentItems and original.currentItems ~= nil then
            currentItems.Value = original.currentItems
        end

        zoneService:PlacePlayerAtZoneSpawn(player, original.activeArea or sourceAreaId)
        dataService:RequestSave(player, "meadow_breakable_smoke_restore", { critical = true })
    end

    local ok, result = pcall(function()
        data.GameData = data.GameData or {}
        data.GameData.UnlockedAreas = removeArrayValue(data.GameData.UnlockedAreas, targetAreaId)
        zoneService:GetUnlockedZones(player)

        local unlock = zoneService:UnlockZone(player, targetZoneId, { bypassRequirements = true })
        if not unlock.ok then
            error("Expected bypass zone unlock to succeed: " .. tostring(unlock.reason))
        end

        local placed = zoneService:PlacePlayerAtZoneSpawn(player, sourceAreaId)
        if not placed then
            error("Failed to place player at " .. tostring(sourceAreaId))
        end

        local pad = findTravelPad(sourceAreaId, targetZoneId)
        if not pad then
            error(
                "TeleportPad not found from "
                    .. tostring(sourceAreaId)
                    .. " to "
                    .. tostring(targetZoneId)
            )
        end

        local travel = zoneService:TravelViaHook(player, pad)
        if not travel.ok then
            error("Expected travel to Meadow to succeed: " .. tostring(travel.reason))
        end
        if travel.targetAreaId ~= targetAreaId then
            error("Travel reached wrong area: " .. tostring(travel.targetAreaId))
        end

        data.Upgrades = data.Upgrades or {}
        data.Upgrades.crystal_value = 1

        local model, spawnError =
            breakableSpawner:SpawnBreakableForStudioSmoke(targetAreaId, breakableId)
        if not model then
            error("Expected deterministic Meadow breakable spawn: " .. tostring(spawnError))
        end
        spawnedModel = model

        local currency = tostring(model:GetAttribute("Currency") or "crystals")
        local baseValue = tonumber(model:GetAttribute("Value")) or 0
        local maxHp = tonumber(model:GetAttribute("MaxHP")) or 0
        if model:GetAttribute("CrystalName") ~= breakableId then
            error("Spawned wrong breakable: " .. tostring(model:GetAttribute("CrystalName")))
        end
        if maxHp <= 0 or baseValue <= 0 then
            error("Spawned breakable has invalid gameplay attributes")
        end

        local beforeCurrency = dataService:GetCurrency(player, currency)
        local beforeCounter = dataService:GetCounter(player, "breakables_broken")
        local expectedReward = economyService:ResolveRewardAmount(baseValue, {
            player = player,
            kind = "breakable_reward",
            currency = currency,
            breakableId = model:GetAttribute("BreakableId"),
            source = "BreakableSpawner",
        })

        local contrib = model:FindFirstChild("Contrib")
        if not contrib then
            error("Spawned breakable is missing Contrib folder")
        end
        local contribution = Instance.new("NumberValue")
        contribution.Name = tostring(player.UserId)
        contribution.Value = maxHp
        contribution.Parent = contrib

        model:SetAttribute("HP", 0)
        local deadline = os.clock() + 8
        repeat
            task.wait(0.1)
        until not model.Parent or os.clock() >= deadline

        if model.Parent then
            error("Breakable did not destroy after HP reached zero")
        end
        spawnedModel = nil

        local afterCurrency = dataService:GetCurrency(player, currency)
        local afterCounter = dataService:GetCounter(player, "breakables_broken")
        local currencyDelta = afterCurrency - beforeCurrency
        if currencyDelta ~= expectedReward then
            error(
                string.format(
                    "Expected %d %s reward, got %d",
                    expectedReward,
                    currency,
                    currencyDelta
                )
            )
        end
        if afterCounter ~= beforeCounter + 1 then
            error(
                string.format(
                    "Expected breakables_broken %d -> %d, got %d",
                    beforeCounter,
                    beforeCounter + 1,
                    afterCounter
                )
            )
        end

        return {
            ok = true,
            sourceAreaId = sourceAreaId,
            targetZoneId = targetZoneId,
            targetAreaId = targetAreaId,
            breakableId = breakableId,
            currency = currency,
            baseValue = baseValue,
            expectedReward = expectedReward,
            currencyDelta = currencyDelta,
            beforeCurrency = beforeCurrency,
            afterCurrency = afterCurrency,
            counterBefore = beforeCounter,
            counterAfter = afterCounter,
            maxHp = maxHp,
            activeArea = worldBindingService:GetActiveArea(player),
        }
    end)

    restore()

    if not ok then
        return {
            ok = false,
            error = tostring(result),
            restored = true,
        }
    end

    result.restored = true
    return result
end

local function findPortalForZone(sourceZoneId, targetZoneId)
    if not worldBindingService then
        return nil
    end

    for _, portal in ipairs(worldBindingService:GetPortalsForZone(sourceZoneId)) do
        if portal:GetAttribute("TargetZoneId") == targetZoneId then
            return portal
        end
    end
    return nil
end

local function destroySyntheticExpansionArtifacts()
    local syntheticRoot = workspace:FindFirstChild("SyntheticMap")
    if syntheticRoot and syntheticRoot:GetAttribute("GeneratedByWorldBindingService") then
        syntheticRoot:Destroy()
    end

    local crystals = workspace:FindFirstChild("Game")
        and workspace.Game:FindFirstChild("Breakables")
        and workspace.Game.Breakables:FindFirstChild("Crystals")
    local testFolder = crystals and crystals:FindFirstChild("CrystalCavern")
    if testFolder then
        testFolder:Destroy()
    end
end

local function snapshotWorkspaceMarkers()
    local snapshots = {}
    for tagName in pairs(configLoader:LoadConfig("markers").tags or {}) do
        for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
            if instance:IsDescendantOf(workspace) and not snapshots[instance] then
                local snapshot = {
                    attributes = instance:GetAttributes(),
                }
                if instance:IsA("BasePart") then
                    snapshot.basePart = {
                        CFrame = instance.CFrame,
                        Size = instance.Size,
                        Transparency = instance.Transparency,
                        CanCollide = instance.CanCollide,
                        CanTouch = instance.CanTouch,
                        CanQuery = instance.CanQuery,
                        Color = instance.Color,
                        Material = instance.Material,
                    }
                end
                snapshots[instance] = snapshot
            end
        end
    end
    return snapshots
end

local function restoreWorkspaceMarkers(snapshots)
    for instance, snapshot in pairs(snapshots or {}) do
        if instance.Parent then
            local currentAttributes = instance:GetAttributes()
            for key in pairs(currentAttributes) do
                if snapshot.attributes[key] == nil then
                    instance:SetAttribute(key, nil)
                end
            end
            for key, value in pairs(snapshot.attributes) do
                instance:SetAttribute(key, value)
            end

            if snapshot.basePart and instance:IsA("BasePart") then
                instance.CFrame = snapshot.basePart.CFrame
                instance.Size = snapshot.basePart.Size
                instance.Transparency = snapshot.basePart.Transparency
                instance.CanCollide = snapshot.basePart.CanCollide
                instance.CanTouch = snapshot.basePart.CanTouch
                instance.CanQuery = snapshot.basePart.CanQuery
                instance.Color = snapshot.basePart.Color
                instance.Material = snapshot.basePart.Material
            end
        end
    end
end

function StudioSmokeTestService:_runSyntheticExpansionSmoke(player, payload)
    payload = payload or {}
    if not worldBindingService or not zoneService then
        return {
            ok = false,
            error = "Synthetic expansion dependencies are not loaded",
        }
    end

    local data = dataService:GetData(player)
    if not data then
        return {
            ok = false,
            error = "Player data not loaded",
        }
    end

    local original = {
        areasConfig = worldBindingService._areasConfig,
        breakablesConfig = worldBindingService._breakablesConfig,
        mapMode = worldBindingService._mapMode,
        zoneAreasConfig = zoneService._areasConfig,
        unlockedAreas = deepCopy(data.GameData and data.GameData.UnlockedAreas or {}),
        activeArea = worldBindingService:GetActiveArea(player),
        markerSnapshots = snapshotWorkspaceMarkers(),
    }

    local extendedAreas = deepCopy(original.areasConfig)
    extendedAreas.zones = extendedAreas.zones or {}
    extendedAreas.zones.crystal_world = {
        id = "crystal_world",
        kind = "world",
        display_name = "Crystal World",
        order = 2,
        primary_area = "CrystalCavern",
    }
    extendedAreas.zones.crystal_island = {
        id = "crystal_island",
        kind = "island",
        parent = "crystal_world",
        display_name = "Crystal Island",
        order = 1,
        primary_area = "CrystalCavern",
    }
    extendedAreas.zones.CrystalCavern = {
        id = "CrystalCavern",
        kind = "area",
        parent = "crystal_island",
        display_name = "Crystal Cavern",
        order = 3,
        unlock = {
            required_zone = "Spawn",
            unlocked_by_default = false,
            currency = "crystals",
            cost = 250,
        },
        boosts = {
            crystals = 1.25,
        },
        synthetic = {
            center = { x = 440, y = 0, z = 0 },
            size = { x = 160, y = 4, z = 160 },
            floor_y = 0,
            spawn_position = { x = 440, y = 4, z = 0 },
            egg_stands = {},
        },
    }

    local extendedBreakables = deepCopy(original.breakablesConfig)
    extendedBreakables.worlds = extendedBreakables.worlds or {}
    extendedBreakables.worlds.CrystalCavern = {
        max = 3,
        interval = 30,
        spawn_area = {
            name = "SpawnArea",
            size = { x = 120, y = 1, z = 120 },
            position = { x = 440, y = 0, z = 0 },
        },
        spawn_settings = {
            upright = true,
            surface_y = 0,
            use_spawner_bounds = true,
            spawn_area_margin = 16,
            spawn_center = { x = 440, z = 0 },
            spawn_radius = 48,
            spawn_exclusion_radius = 20,
            embed_ratio = 0,
            min_distance = 18,
            spawn_attempts = 20,
            respawn_min_seconds = 15,
            respawn_max_seconds = 90,
        },
        spawn_table = {
            { name = "MediumBlueCrystal", weight = 4 },
            { name = "BigBlueCrystal", weight = 1 },
        },
    }

    local ok, result = pcall(function()
        destroySyntheticExpansionArtifacts()
        worldBindingService._areasConfig = extendedAreas
        worldBindingService._breakablesConfig = extendedBreakables
        worldBindingService._mapMode = "synthetic"
        zoneService._areasConfig = extendedAreas
        worldBindingService:RebuildBindings()

        local portal = findPortalForZone("spawn_world", "crystal_world")
        if not portal then
            error("Expected synthetic cross-world portal from spawn_world to crystal_world")
        end

        local spawnZones = worldBindingService:GetSpawnZonesForArea("CrystalCavern")
        if #spawnZones == 0 then
            error("Expected synthetic CrystalCavern SpawnZone")
        end

        local unlock =
            zoneService:UnlockZone(player, "crystal_world", { bypassRequirements = true })
        if not unlock.ok or unlock.areaId ~= "CrystalCavern" then
            error("Expected synthetic crystal_world unlock to target CrystalCavern")
        end

        local placed = zoneService:PlacePlayerAtZoneSpawn(player, "Spawn")
        if not placed then
            error("Failed to place player at Spawn before synthetic portal travel")
        end

        local travel = zoneService:TravelViaHook(player, portal)
        if not travel.ok then
            error(
                "Expected synthetic cross-world portal travel to succeed: "
                    .. tostring(travel.reason)
            )
        end
        if travel.targetAreaId ~= "CrystalCavern" then
            error("Synthetic portal reached wrong area: " .. tostring(travel.targetAreaId))
        end

        return {
            ok = true,
            sourceZoneId = "spawn_world",
            targetZoneId = "crystal_world",
            targetAreaId = travel.targetAreaId,
            portal = portal:GetFullName(),
            spawnZoneCount = #spawnZones,
            activeArea = worldBindingService:GetActiveArea(player),
        }
    end)

    data.GameData = data.GameData or {}
    data.GameData.UnlockedAreas = deepCopy(original.unlockedAreas)
    worldBindingService._areasConfig = original.areasConfig
    worldBindingService._breakablesConfig = original.breakablesConfig
    worldBindingService._mapMode = original.mapMode
    zoneService._areasConfig = original.zoneAreasConfig
    restoreWorkspaceMarkers(original.markerSnapshots)
    destroySyntheticExpansionArtifacts()
    worldBindingService:RebuildBindings()
    zoneService:PlacePlayerAtZoneSpawn(player, original.activeArea or "Spawn")
    dataService:RequestSave(player, "synthetic_expansion_smoke_restore", { critical = true })

    if not ok then
        return {
            ok = false,
            error = tostring(result),
            restored = true,
        }
    end

    result.restored = true
    return result
end

return StudioSmokeTestService
