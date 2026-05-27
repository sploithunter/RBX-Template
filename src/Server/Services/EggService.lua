--[[
    EggService - Following working game pattern
    
    Simple egg purchase handling using RemoteFunction like the working game.
    Matches their EggHandler pattern exactly.
--]]

local EggService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Locations = require(ReplicatedStorage.Shared.Locations)
local petConfig = Locations.getConfig("pets")
local eggSystemConfig = Locations.getConfig("egg_system")

-- Logger setup using singleton pattern
local Logger
local loggerSuccess, loggerResult = pcall(function()
    return require(Locations.Logger)
end)

if loggerSuccess and loggerResult then
    Logger = loggerResult -- Use singleton directly
else
    Logger = {
        Info = function(self, message, context)
            print("[INFO]", message, context)
        end,
        Warn = function(self, message, context)
            warn("[WARN]", message, context)
        end,
        Error = function(self, message, context)
            warn("[ERROR]", message, context)
        end,
        Debug = function(self, message, context)
            print("[DEBUG]", message, context)
        end,
    }
end

-- Player cooldowns
local playerCooldowns = {}

-- RemoteFunction for egg purchases
local eggRemoteFunction = nil

-- Player current egg tracking (for persistence)
local playerCurrentEggs = {}

-- === HELPER FUNCTIONS ===

function EggService:IsOnCooldown(player)
    local playerId = player.UserId
    local lastPurchase = playerCooldowns[playerId] or 0
    local cooldownTime = eggSystemConfig.cooldowns.purchase_cooldown
    local currentTime = tick()

    if currentTime - lastPurchase < cooldownTime then
        return true, cooldownTime - (currentTime - lastPurchase)
    end

    playerCooldowns[playerId] = currentTime
    return false, 0
end

function EggService:HasEnoughCurrency(player, currency, cost)
    if self._dataService then
        return self._dataService:CanAfford(player, currency, cost),
            self._dataService:GetCurrency(player, currency)
    else
        -- Fallback to attributes if DataService not available
        local currentAmount = player:GetAttribute(currency) or 0
        return currentAmount >= cost, currentAmount
    end
end

function EggService:DeductCurrency(player, currency, cost)
    if self._dataService then
        return self._dataService:RemoveCurrency(player, currency, cost, "egg_hatch")
    else
        -- Fallback to attributes if DataService not available
        local currentAmount = player:GetAttribute(currency) or 0
        if currentAmount >= cost then
            player:SetAttribute(currency, currentAmount - cost)
            return true
        end
        return false
    end
end

function EggService:IsPlayerNearEgg(player, eggType)
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end

    local playerPosition = player.Character.HumanoidRootPart.Position

    -- Find the egg model
    local eggModel = nil
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") then
            local objEggType = obj:GetAttribute("EggType")
            local eggInfo = obj:FindFirstChild("EggType")
            if eggInfo then
                objEggType = eggInfo.Value
            end

            if objEggType == eggType then
                eggModel = obj
                break
            end
        end
    end

    if not eggModel then
        return false
    end

    -- Use EggSpawnPoint as anchor (referenced in SpawnPoint ObjectValue)
    local spawnPointRef = eggModel:FindFirstChild("SpawnPoint")
    local anchor = spawnPointRef and spawnPointRef.Value

    -- Fallback to PrimaryPart or any Part if no SpawnPoint reference
    if not anchor then
        anchor = eggModel.PrimaryPart or eggModel:FindFirstChildOfClass("Part")
    end

    if not anchor then
        return false
    end

    local distance = (playerPosition - anchor.Position).Magnitude
    return distance <= eggSystemConfig.proximity.max_distance
end

-- === MAIN HANDLER (following working game pattern) ===

function EggService:HandleEggPurchase(player, eggType, purchaseType)
    Logger:Info("Egg purchase request", {
        player = player.Name,
        eggType = eggType,
        purchaseType = purchaseType,
    })

    -- Validate egg type
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        Logger:Warn("Invalid egg type", { player = player.Name, eggType = eggType })
        return nil, "Invalid egg type"
    end

    -- Check cooldown
    local onCooldown, remainingTime = self:IsOnCooldown(player)
    if onCooldown then
        Logger:Debug("Player on cooldown", { player = player.Name, remainingTime = remainingTime })
        return "Error", "Please wait before purchasing again"
    end

    -- Check distance (server-side validation)
    if not self:IsPlayerNearEgg(player, eggType) then
        Logger:Warn("Player too far from egg", { player = player.Name, eggType = eggType })
        return "Error", "Too far away"
    end

    -- Check currency
    local hasEnough, currentAmount = self:HasEnoughCurrency(player, eggData.currency, eggData.cost)

    Logger:Info("🪙 EGG PURCHASE - Currency check", {
        player = player.Name,
        eggType = eggType,
        currency = eggData.currency,
        required = eggData.cost,
        current = currentAmount,
        hasEnough = hasEnough,
        dataServiceAvailable = self._dataService ~= nil,
    })

    if not hasEnough then
        Logger:Warn("🚫 INSUFFICIENT CURRENCY", {
            player = player.Name,
            currency = eggData.currency,
            required = eggData.cost,
            current = currentAmount,
        })
        return "Error", "Insufficient " .. eggData.currency
    end

    -- Deduct currency
    local deductSuccess = self:DeductCurrency(player, eggData.currency, eggData.cost)
    if not deductSuccess then
        Logger:Error("Failed to deduct currency", { player = player.Name })
        return "Error", "Transaction failed"
    end

    -- Perform hatching
    local playerData = {
        level = player:GetAttribute("Level") or 1,
        petsHatched = player:GetAttribute("PetsHatched") or 0,
        hasLuckGamepass = false,
        hasGoldenGamepass = false,
        hasRainbowGamepass = false,
        isVIP = false,
    }

    if self._eventService then
        playerData.luckBoost = self._eventService:GetModifier("egg_luck", 0)
    end

    if self._modifierService and self._modifierService.Resolve then
        local baseLuckBoost = tonumber(playerData.luckBoost) or 0
        local hatchLuck = self._modifierService:Resolve(baseLuckBoost, {
            player = player,
            kind = "hatch_luck",
            eggType = eggType,
            currency = eggData.currency,
            source = "EggService",
        })
        local secretLuck = self._modifierService:Resolve(0, {
            player = player,
            kind = "secret_hatch_luck",
            eggType = eggType,
            currency = eggData.currency,
            source = "EggService",
        })
        playerData.luckBoost = tonumber(hatchLuck) or baseLuckBoost
        playerData.secretLuckBoost = tonumber(secretLuck) or 0
    end

    -- Allow runtime forcing via player attributes for quick testing
    if petConfig.test_mode and petConfig.test_mode.enabled then
        local attrForcePet = player:GetAttribute("ForcePet")
        local attrForceVariant = player:GetAttribute("ForceVariant")
        if attrForcePet or attrForceVariant then
            petConfig.test_mode.force_pet = attrForcePet
            petConfig.test_mode.force_variant = attrForceVariant
            Logger:Info("🐣 Hatch override active", {
                player = player.Name,
                force_pet = attrForcePet,
                force_variant = attrForceVariant,
            })
        else
            Logger:Debug("No hatch override attributes set", { player = player.Name })
        end
    end

    local hatchResult = petConfig.simulateHatch(eggType, playerData)
    if not hatchResult then
        Logger:Error("Hatching failed", { player = player.Name, eggType = eggType })
        -- Refund currency
        local refundAmount = player:GetAttribute(eggData.currency) or 0
        player:SetAttribute(eggData.currency, refundAmount + eggData.cost)
        return "Error", "Hatching failed"
    end

    Logger:Info("Egg hatched successfully", {
        player = player.Name,
        eggType = eggType,
        pet = hatchResult.pet,
        variant = hatchResult.variant,
        power = hatchResult.petData.power,
    })

    -- 🐾 ADD PET TO INVENTORY THROUGH THE SINGLE GRANT BOUNDARY
    if self._petGrantService then
        local grantResult = self._petGrantService:GrantPet(player, {
            petType = hatchResult.pet,
            variant = hatchResult.variant,
            source = "egg_hatch",
        })
        if grantResult.ok then
            Logger:Info("Pet granted from egg hatch", {
                player = player.Name,
                uid = grantResult.uid,
                pet = hatchResult.pet,
                variant = hatchResult.variant,
            })
        else
            Logger:Error("Failed to grant hatched pet", {
                player = player.Name,
                pet = hatchResult.pet,
                variant = hatchResult.variant,
                error = grantResult.error,
            })
            if self._dataService then
                self._dataService:AddCurrency(
                    player,
                    eggData.currency,
                    eggData.cost,
                    "egg_hatch_refund"
                )
            end
            return "Error", "Failed to grant pet"
        end
    else
        Logger:Warn("PetGrantService not available - pet not saved to inventory", {
            player = player.Name,
            pet = hatchResult.pet,
        })
    end

    if self._statsService then
        pcall(function()
            self._statsService:Increment(player, "eggs_hatched", 1)
        end)
    end

    -- Return result in working game format
    return {
        Pet = hatchResult.pet,
        PetNum = hatchResult.pet, -- Use pet name as number for now
        Type = hatchResult.variant,
        Power = hatchResult.petData.power,
        EggType = eggType,
        success = true,
    }
end

-- === CURRENT EGG TRACKING (for persistence) ===

function EggService:SetLastEgg(player, eggType)
    local playerId = player.UserId
    playerCurrentEggs[playerId] = eggType

    Logger:Debug("Set last egg for player", {
        player = player.Name,
        eggType = eggType or "nil",
    })

    -- TODO: Save to player data for persistence across sessions
    -- This would integrate with your DataService to save the current egg

    return true
end

function EggService:GetLastEgg(player)
    local playerId = player.UserId
    return playerCurrentEggs[playerId]
end

-- === INITIALIZATION ===

function EggService:Initialize(moduleLoader)
    Logger:Info("EggService initializing...")

    -- Get services from the module loader
    if moduleLoader then
        self._inventoryService = moduleLoader:Get("InventoryService")
        self._dataService = moduleLoader:Get("DataService")
        self._eventService = moduleLoader:Get("EventService")
        self._statsService = moduleLoader:Get("StatsService")
        self._petGrantService = moduleLoader:Get("PetGrantService")
        self._modifierService = moduleLoader:Get("ModifierService")

        if self._inventoryService then
            Logger:Info("EggService: InventoryService connection established")
        else
            Logger:Warn("EggService: InventoryService not available in module loader")
        end

        if self._dataService then
            Logger:Info("EggService: DataService connection established")
        else
            Logger:Warn("EggService: DataService not available in module loader")
        end

        if self._eventService then
            Logger:Info("EggService: EventService connection established")
        else
            Logger:Warn("EggService: EventService not available in module loader")
        end

        if self._statsService then
            Logger:Info("EggService: StatsService connection established")
        else
            Logger:Warn("EggService: StatsService not available in module loader")
        end

        if self._petGrantService then
            Logger:Info("EggService: PetGrantService connection established")
        else
            Logger:Warn("EggService: PetGrantService not available in module loader")
        end

        if self._modifierService then
            Logger:Info("EggService: ModifierService connection established")
        else
            Logger:Warn("EggService: ModifierService not available in module loader")
        end
    else
        Logger:Warn("EggService: No module loader provided")
    end

    -- Create RemoteFunction (like working game)
    eggRemoteFunction = Instance.new("RemoteFunction")
    eggRemoteFunction.Name = "EggOpened"
    eggRemoteFunction.Parent = ReplicatedStorage

    -- Create setLastEgg RemoteFunction (like working game)
    local setLastEggRemote = Instance.new("RemoteFunction")
    setLastEggRemote.Name = "setLastEgg"
    setLastEggRemote.Parent = eggRemoteFunction

    -- Set up the handlers
    eggRemoteFunction.OnServerInvoke = function(player, eggType, purchaseType)
        return self:HandleEggPurchase(player, eggType, purchaseType)
    end

    setLastEggRemote.OnServerInvoke = function(player, eggType)
        return self:SetLastEgg(player, eggType)
    end

    -- Clean up when players leave
    Players.PlayerRemoving:Connect(function(player)
        playerCooldowns[player.UserId] = nil
        playerCurrentEggs[player.UserId] = nil
    end)

    Logger:Info("EggService initialized with RemoteFunction and setLastEgg tracking")
end

return EggService
