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
        Info = function(self, message, context) print("[INFO]", message, context) end,
        Warn = function(self, message, context) warn("[WARN]", message, context) end,
        Error = function(self, message, context) warn("[ERROR]", message, context) end,
        Debug = function(self, message, context) print("[DEBUG]", message, context) end,
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
        return self._dataService:CanAfford(player, currency, cost), self._dataService:GetCurrency(player, currency)
    else
        -- Fallback to attributes if DataService not available
        local currentAmount = player:GetAttribute(currency) or 0
        return currentAmount >= cost, currentAmount
    end
end

function EggService:DeductCurrency(player, currency, cost)
    if self._dataService then
        return self._dataService:RemoveCurrency(player, currency, cost)
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
            if eggInfo then objEggType = eggInfo.Value end
            
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
        purchaseType = purchaseType
    })
    
    -- Validate egg type
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        Logger:Warn("Invalid egg type", {player = player.Name, eggType = eggType})
        return nil, "Invalid egg type"
    end
    
    -- Check cooldown
    local onCooldown, remainingTime = self:IsOnCooldown(player)
    if onCooldown then
        Logger:Debug("Player on cooldown", {player = player.Name, remainingTime = remainingTime})
        return "Error", "Please wait before purchasing again"
    end
    
    -- Check distance (server-side validation)
    if not self:IsPlayerNearEgg(player, eggType) then
        Logger:Warn("Player too far from egg", {player = player.Name, eggType = eggType})
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
        dataServiceAvailable = self._dataService ~= nil
    })
    
    if not hasEnough then
        Logger:Warn("🚫 INSUFFICIENT CURRENCY", {
            player = player.Name,
            currency = eggData.currency,
            required = eggData.cost,
            current = currentAmount
        })
        return "Error", "Insufficient " .. eggData.currency
    end
    
    -- Deduct currency
    local deductSuccess = self:DeductCurrency(player, eggData.currency, eggData.cost)
    if not deductSuccess then
        Logger:Error("Failed to deduct currency", {player = player.Name})
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
    
    local hatchResult = petConfig.simulateHatch(eggType, playerData)
    if not hatchResult then
        Logger:Error("Hatching failed", {player = player.Name, eggType = eggType})
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
        power = hatchResult.petData.power
    })
    
    -- 🐾 ADD PET TO INVENTORY
    if self._inventoryService then
        local petData = {
            id = hatchResult.pet,                    -- Pet type (bear, bunny, etc.)
            variant = hatchResult.variant,           -- basic, golden, rainbow
            obtained_at = tick(),                    -- Current timestamp
            level = 1,                               -- Starting level
            exp = 0,                                 -- Starting experience
            stats = {
                power = hatchResult.petData.power,   -- Power from pet config
                health = hatchResult.petData.health or 100,
                speed = hatchResult.petData.speed or 1.0
            },
            nickname = "",                           -- Empty by default
            locked = false                           -- Not locked by default
        }
        
        local uid = self._inventoryService:AddItem(player, "pets", petData)
        if uid then
            Logger:Info("Pet added to inventory", {
                player = player.Name,
                uid = uid,
                pet = hatchResult.pet,
                variant = hatchResult.variant
            })
        else
            Logger:Error("Failed to add pet to inventory", {
                player = player.Name,
                pet = hatchResult.pet,
                variant = hatchResult.variant
            })
        end
    else
        Logger:Warn("InventoryService not available - pet not saved to inventory", {
            player = player.Name,
            pet = hatchResult.pet
        })
    end
    
    -- Return result in working game format
    return {
        Pet = hatchResult.pet,
        PetNum = hatchResult.pet, -- Use pet name as number for now
        Type = hatchResult.variant,
        Power = hatchResult.petData.power,
        success = true
    }
end

-- === CURRENT EGG TRACKING (for persistence) ===

function EggService:SetLastEgg(player, eggType)
    local playerId = player.UserId
    playerCurrentEggs[playerId] = eggType
    
    Logger:Debug("Set last egg for player", {
        player = player.Name,
        eggType = eggType or "nil"
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