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
    local currentAmount = player:GetAttribute(currency) or 0
    return currentAmount >= cost, currentAmount
end

function EggService:DeductCurrency(player, currency, cost)
    local currentAmount = player:GetAttribute(currency) or 0
    if currentAmount >= cost then
        player:SetAttribute(currency, currentAmount - cost)
        return true
    end
    return false
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
    if not hasEnough then
        Logger:Debug("Insufficient currency", {
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

function EggService:Initialize()
    Logger:Info("EggService initializing...")
    
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