local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local AdminToolsService = {}
AdminToolsService.__index = AdminToolsService

function AdminToolsService.new()
    local self = setmetatable({}, AdminToolsService)
    self._logger = nil
    self._adminService = nil
    self._dataService = nil
    self._inventoryService = nil
    self._configLoader = nil
    self._eventService = nil
    self._zoneService = nil
    self._petGrantService = nil
    self._petsConfig = nil
    self._inventoryConfig = nil
    return self
end

function AdminToolsService:Init()
    self._logger = self._modules.Logger
    self._adminService = self._modules.AdminService
    self._dataService = self._modules.DataService
    self._inventoryService = self._modules.InventoryService
    self._configLoader = self._modules.ConfigLoader
    self._eventService = self._modules.EventService
    self._zoneService = self._modules.ZoneService
    self._petGrantService = self._modules.PetGrantService

    self._petsConfig = self._configLoader:LoadConfig("pets")
    self._inventoryConfig = self._configLoader:LoadConfig("inventory")

    Signals.Admin_GetPlayerSnapshot.OnServerEvent:Connect(function(player, data)
        self:_handleSnapshot(player, data)
    end)

    Signals.Admin_ForceSave.OnServerEvent:Connect(function(player, data)
        self:_handleForceSave(player, data)
    end)

    Signals.Admin_GrantPet.OnServerEvent:Connect(function(player, data)
        self:_handleGrantPet(player, data)
    end)

    Signals.Admin_SetZoneLock.OnServerEvent:Connect(function(player, data)
        self:_handleSetZoneLock(player, data)
    end)

    Signals.Admin_EventCommand.OnServerEvent:Connect(function(player, data)
        self:_handleEventCommand(player, data)
    end)

    self._logger:Info("AdminToolsService initialized")
end

function AdminToolsService:_handleEventCommand(adminPlayer, data)
    data = type(data) == "table" and data or {}

    local authorized, reason =
        self._adminService:ValidateAdminAction(adminPlayer, "globalEffects", data, "client")
    if not authorized then
        self:_sendResult(adminPlayer, {
            kind = "event_command",
            success = false,
            message = reason or "Not authorized",
        })
        return
    end

    if not self._eventService then
        self:_sendResult(adminPlayer, {
            kind = "event_command",
            success = false,
            message = "EventService unavailable",
        })
        return
    end

    local command = tostring(data.command or "")
    local eventId = tostring(data.eventId or "")
    local success = false
    local message = "Unknown event command"

    if command == "start" then
        success, message = self._eventService:StartGlobalEvent(eventId, {
            durationSeconds = tonumber(data.durationSeconds),
            reason = data.reason or ("Admin: " .. adminPlayer.Name),
        })
        if success then
            message = "Started global event: " .. eventId
        end
    elseif command == "stop" then
        success, message = self._eventService:StopGlobalEvent(eventId)
        if success then
            message = "Stopped global event: " .. eventId
        end
    elseif command == "clear" then
        local cleared = self._eventService:ClearGlobalEvents()
        success = true
        message = "Cleared " .. tostring(cleared) .. " global events"
    elseif command == "snapshot" then
        success = true
        message = "Global event snapshot loaded"
    end

    self:_sendResult(adminPlayer, {
        kind = "event_command",
        success = success == true,
        message = message,
        events = self._eventService:GetActiveGlobalEvents(),
        modifiers = self._eventService:GetAllModifiers(),
    })
end

function AdminToolsService:Start() end

function AdminToolsService:_sendResult(adminPlayer, payload)
    Signals.AdminToolResult:FireClient(adminPlayer, payload)
end

function AdminToolsService:_resolveTarget(adminPlayer, actionName, data)
    data = type(data) == "table" and data or {}

    local authorized, reason, targetPlayer =
        self._adminService:ValidateAdminAction(adminPlayer, actionName, data, "client")
    if not authorized then
        return nil, reason or "Not authorized"
    end

    return targetPlayer or adminPlayer, nil
end

function AdminToolsService:_countPets(playerData)
    local petsBucket = playerData.Inventory and playerData.Inventory.pets
    local totalPets = 0
    local uniqueEntries = 0

    if petsBucket and petsBucket.items then
        for _, item in pairs(petsBucket.items) do
            uniqueEntries += 1
            totalPets += tonumber(item.quantity) or 1
        end
    end

    return totalPets, uniqueEntries
end

function AdminToolsService:_countEquippedPets(playerData)
    local equippedPets = playerData.Equipped and playerData.Equipped.pets
    local count = 0

    if equippedPets then
        for _, uid in pairs(equippedPets) do
            if uid ~= nil and uid ~= "" then
                count += 1
            end
        end
    end

    return count
end

function AdminToolsService:_getPetEquipLimit(targetPlayer)
    local configured = self._inventoryConfig.equipped and self._inventoryConfig.equipped.pets
    local configuredSlots = configured and configured.slots or 3

    if self._inventoryService and self._inventoryService._getMaxEquippedSlots then
        return self._inventoryService:_getMaxEquippedSlots(targetPlayer, "pets", configuredSlots)
    end

    return configuredSlots
end

function AdminToolsService:_buildSnapshot(targetPlayer)
    local playerData = self._dataService:GetData(targetPlayer)
    local saveState = self._dataService.SaveRequests
        and self._dataService.SaveRequests[targetPlayer]
    local totalPets, petEntries = self:_countPets(playerData or {})
    local equippedPets = self:_countEquippedPets(playerData or {})
    local freeTarget = targetPlayer:FindFirstChild("FreeTarget")
    local paidTarget = targetPlayer:FindFirstChild("PaidTarget")

    return {
        userId = targetPlayer.UserId,
        name = targetPlayer.Name,
        displayName = targetPlayer.DisplayName,
        dataLoaded = self._dataService:IsDataLoaded(targetPlayer),
        persistenceEnabled = ReplicatedStorage:GetAttribute("ProfilePersistenceEnabled") == true,
        dataStoreState = ReplicatedStorage:GetAttribute("ProfileStoreDataState") or "Unknown",
        currencies = playerData and playerData.Currencies or {},
        petCount = totalPets,
        petEntryCount = petEntries,
        equippedPetCount = equippedPets,
        equippedPetLimit = self:_getPetEquipLimit(targetPlayer),
        extraPetSlots = playerData and playerData.Perks and playerData.Perks.extra_pet_slots or 0,
        autoTarget = {
            low = freeTarget and freeTarget.Value == true or false,
            high = paidTarget and paidTarget.Value == true or false,
        },
        save = {
            dirty = saveState and saveState.dirty == true or false,
            scheduled = saveState and saveState.scheduled == true or false,
            inFlight = saveState and saveState.inFlight == true or false,
            lastReason = saveState and saveState.lastReason or "none",
            lastRequestedAt = saveState and saveState.lastRequestedAt or nil,
            lastConfirmedAt = saveState and saveState.lastConfirmedAt or nil,
        },
    }
end

function AdminToolsService:_handleSnapshot(adminPlayer, data)
    local targetPlayer, errorMessage = self:_resolveTarget(adminPlayer, "viewDebugInfo", data)
    if not targetPlayer then
        self:_sendResult(adminPlayer, {
            kind = "snapshot",
            success = false,
            message = errorMessage,
        })
        return
    end

    self:_sendResult(adminPlayer, {
        kind = "snapshot",
        success = true,
        message = "Snapshot loaded for " .. targetPlayer.Name,
        snapshot = self:_buildSnapshot(targetPlayer),
    })
end

function AdminToolsService:_handleForceSave(adminPlayer, data)
    local targetPlayer, errorMessage = self:_resolveTarget(adminPlayer, "forceSaveData", data)
    if not targetPlayer then
        self:_sendResult(adminPlayer, {
            kind = "force_save",
            success = false,
            message = errorMessage,
        })
        return
    end

    local ok = self._dataService:RequestSave(targetPlayer, "admin_force_save", {
        debounceSeconds = 0,
        critical = true,
    })

    self:_sendResult(adminPlayer, {
        kind = "force_save",
        success = ok == true,
        message = ok and ("Force save requested for " .. targetPlayer.Name)
            or ("Force save failed for " .. targetPlayer.Name),
        snapshot = self:_buildSnapshot(targetPlayer),
    })
end

function AdminToolsService:_parseGrantData(data)
    data = type(data) == "table" and data or {}
    local petType = tostring(data.petType or ""):lower()
    local variant = tostring(data.variant or "basic"):lower()
    local quantity = math.clamp(math.floor(tonumber(data.quantity) or 1), 1, 99)
    local traits = {
        huge = data.huge == true,
    }

    return petType, variant, quantity, traits
end

function AdminToolsService:_handleGrantPet(adminPlayer, data)
    local targetPlayer, errorMessage = self:_resolveTarget(adminPlayer, "giveItems", data)
    if not targetPlayer then
        self:_sendResult(adminPlayer, {
            kind = "grant_pet",
            success = false,
            message = errorMessage,
        })
        return
    end

    local petType, variant, quantity, traits = self:_parseGrantData(data)
    if not (self._petsConfig.getPet and self._petsConfig.getPet(petType, variant)) then
        self:_sendResult(adminPlayer, {
            kind = "grant_pet",
            success = false,
            message = "Unknown pet: " .. tostring(petType) .. ":" .. tostring(variant),
        })
        return
    end

    local result = self._petGrantService:GrantPet(targetPlayer, {
        petType = petType,
        variant = variant,
        quantity = traits.huge and 1 or quantity,
        huge = traits.huge,
        source = "admin_grant_pet",
    })
    if not result.ok then
        self:_sendResult(adminPlayer, {
            kind = "grant_pet",
            success = false,
            message = result.error or "Failed to grant pet",
            snapshot = self:_buildSnapshot(targetPlayer),
        })
        return
    end

    local petData = result.petData

    self._logger:Info("Admin pet granted", {
        admin = adminPlayer.Name,
        target = targetPlayer.Name,
        petType = petType,
        variant = variant,
        quantity = quantity,
        huge = traits.huge == true,
        serial = petData.serial,
        serialKey = petData.serial_key,
        uid = result.uid,
    })

    self:_sendResult(adminPlayer, {
        kind = "grant_pet",
        success = true,
        message = string.format(
            "Granted %dx %s%s %s%s to %s",
            traits.huge and 1 or quantity,
            variant,
            traits.huge and " huge" or "",
            petType,
            petData.serial and (" #" .. tostring(petData.serial)) or "",
            targetPlayer.Name
        ),
        granted = {
            petType = petType,
            variant = variant,
            quantity = quantity,
            uid = result.uid,
            huge = traits.huge == true,
            serial = petData.serial,
            serialKey = petData.serial_key,
        },
        snapshot = self:_buildSnapshot(targetPlayer),
    })
end

function AdminToolsService:_handleSetZoneLock(adminPlayer, data)
    local targetPlayer, errorMessage = self:_resolveTarget(adminPlayer, "unlockZones", data)
    if not targetPlayer then
        self:_sendResult(adminPlayer, {
            kind = "zone_lock",
            success = false,
            message = errorMessage,
        })
        return
    end

    if not self._zoneService then
        self:_sendResult(adminPlayer, {
            kind = "zone_lock",
            success = false,
            message = "ZoneService unavailable",
            snapshot = self:_buildSnapshot(targetPlayer),
        })
        return
    end

    data = type(data) == "table" and data or {}
    local zoneId = tostring(data.zoneId or "")
    if zoneId == "" then
        self:_sendResult(adminPlayer, {
            kind = "zone_lock",
            success = false,
            message = "Missing zone id",
            snapshot = self:_buildSnapshot(targetPlayer),
        })
        return
    end

    local currentUnlocked = self._zoneService:IsZoneUnlocked(targetPlayer, zoneId)
    local locked = data.locked
    if locked == nil then
        locked = currentUnlocked == true
    end

    local result = self._zoneService:SetZoneLocked(targetPlayer, zoneId, locked == true, {
        bypassRequirements = data.bypassRequirements == true,
    })

    local success = result and result.ok == true
    local unlockedAreas = self._zoneService:GetUnlockedZones(targetPlayer)
    local message
    if success then
        if locked == true then
            message = string.format("Locked %s for %s", zoneId, targetPlayer.Name)
        elseif result.alreadyUnlocked then
            message = string.format("%s already has %s unlocked", targetPlayer.Name, zoneId)
        else
            message = string.format("Unlocked %s for %s", zoneId, targetPlayer.Name)
        end
    else
        message = string.format(
            "Failed to unlock %s for %s: %s",
            zoneId,
            targetPlayer.Name,
            tostring(result and result.reason or "unknown")
        )
    end

    self:_sendResult(adminPlayer, {
        kind = "zone_lock",
        success = success,
        message = message,
        zoneLock = result,
        unlockedAreas = unlockedAreas,
        snapshot = self:_buildSnapshot(targetPlayer),
    })
end

return AdminToolsService
