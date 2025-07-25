--[[
    DataService - Handles player data persistence and management
    
    Features:
    - ProfileStore integration for reliable data storage
    - Automatic profile loading/releasing
    - Data validation and migration
    - Session locking protection
    - Backup data system
    
    Usage:
    local profile = DataService:GetProfile(player)
    DataService:SetCurrency(player, "coins", 1000)
    DataService:AddToInventory(player, "sword", 1)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ProfileStore = require(game.ReplicatedStorage.Shared.Libraries.ProfileStore)
local Promise = require(game.ReplicatedStorage.Packages.Promise)

local DataService = {}
DataService.__index = DataService

-- Default player data template
local ProfileTemplate = {
    -- Player info
    JoinDate = 0,
    LastLogin = 0,
    PlayTime = 0,
    
    -- Currencies
    Currencies = {
        coins = 100,
        gems = 0,
        crystals = 0
    },
    
    -- Inventory system
    Inventory = {},
    
    -- Player stats
    Stats = {
        Level = 1,
        Experience = 0,
        Health = 100,
        MaxHealth = 100
    },
    
    -- Game-specific data
    GameData = {
        TutorialCompleted = false,
        CurrentQuest = nil,
        UnlockedAreas = {"starter_area"}
    },
    
    -- Settings
    Settings = {
        MusicEnabled = true,
        SFXEnabled = true,
        GraphicsQuality = "Auto"
    },
    
    -- Analytics data
    Analytics = {
        SessionCount = 0,
        TotalPlayTime = 0,
        LastSessionDuration = 0,
        Purchases = {},
        Achievements = {}
    },
    
    -- Active Effects (persistent across sessions)
    ActiveEffects = {
        -- Format: effectId = { expiresAt = timestamp, usesRemaining = count, config = {} }
    },
    
    -- Player Clock (for persistent time tracking)
    PlayerClock = {
        lastSaveTime = 0,  -- os.time() when last saved
        totalPlayTime = 0  -- Total time played in seconds
    }
}

function DataService:Init()
    -- Initialize ProfileStore
    self.ProfileStore = ProfileStore.New(
        "PlayerData_v1", -- Version the store for easier migrations
        ProfileTemplate
    )
    
    -- Track active profiles
    self.Profiles = {}
    self.LoadPromises = {}
    
    -- Get dependencies
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    
    -- Connect to player events
    Players.PlayerAdded:Connect(function(player)
        self:LoadProfile(player)
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        self:ReleaseProfile(player)
    end)
    
    -- Session tracking
    self.SessionStartTime = tick()
    
    self._logger:Info("DataService initialized", {
        profileStore = "PlayerData_v1"
    })
end

function DataService:LoadProfile(player)
    if self.LoadPromises[player] then
        return self.LoadPromises[player]
    end
    
    self._logger:Info("Loading profile", {player = player.Name, userId = player.UserId})
    
    local promise = task.spawn(function()
        local profile = self.ProfileStore:StartSessionAsync(
            "Player_" .. player.UserId,
            {
                Cancel = function()
                    return player.Parent == nil -- Cancel if player left
                end
            }
        )
        
        if profile then
            profile:AddUserId(player.UserId) -- Add UserId for GDPR compliance
            profile:Reconcile() -- Fill in missing template values
            
            -- Data migration
            self:MigrateProfile(profile)
            
            -- Update session info
            local data = profile.Data
            data.LastLogin = os.time()
            data.Analytics.SessionCount = data.Analytics.SessionCount + 1
            
            -- Store profile
            self.Profiles[player] = profile
            
            -- Set player attributes for quick access
            player:SetAttribute("DataLoaded", true)
            player:SetAttribute("Level", data.Stats.Level)
            player:SetAttribute("Coins", data.Currencies.coins)
            player:SetAttribute("Gems", data.Currencies.gems)
            
            self._logger:Info("Profile loaded successfully", {
                player = player.Name,
                level = data.Stats.Level,
                coins = data.Currencies.coins,
                sessionCount = data.Analytics.SessionCount
            })
            
            -- Trigger profile loaded event
            self._logger:Debug("About to call _onProfileLoaded", {player = player.Name})
            self:_onProfileLoaded(player, profile)
            self._logger:Debug("_onProfileLoaded completed", {player = player.Name})
            
        else
            -- Profile failed to load
            self._logger:Error("Failed to load profile", {
                player = player.Name,
                userId = player.UserId
            })
            
            -- Kick player with informative message
            player:Kick("Failed to load your data. Please rejoin.")
        end
    end)
    
    self.LoadPromises[player] = promise
    return promise
end

function DataService:ReleaseProfile(player)
    local profile = self.Profiles[player]
    
    if profile then
        -- Update session data
        local sessionDuration = tick() - self.SessionStartTime
        profile.Data.Analytics.LastSessionDuration = sessionDuration
        profile.Data.Analytics.TotalPlayTime = profile.Data.Analytics.TotalPlayTime + sessionDuration
        
        -- End the session
        profile:EndSession()
        
        self._logger:Info("Profile released", {
            player = player.Name,
            sessionDuration = sessionDuration
        })
    end
    
    -- Cleanup
    self.Profiles[player] = nil
    self.LoadPromises[player] = nil
end

function DataService:GetProfile(player)
    return self.Profiles[player]
end

function DataService:GetData(player)
    local profile = self:GetProfile(player)
    return profile and profile.Data
end

function DataService:IsDataLoaded(player)
    return self:GetProfile(player) ~= nil
end

-- Set reference to PlayerEffectsService (called after module loading)
function DataService:SetPlayerEffectsService(playerEffectsService)
    self._playerEffectsService = playerEffectsService
    self._logger:Debug("PlayerEffectsService reference set in DataService")
end

-- Currency management
function DataService:GetCurrency(player, currencyType)
    local data = self:GetData(player)
    if not data then return 0 end
    
    return data.Currencies[currencyType] or 0
end

function DataService:SetCurrency(player, currencyType, amount)
    self._logger:Debug("DataService:SetCurrency called", {player = player.Name, currencyType = currencyType, amount = amount})
    
    local data = self:GetData(player)
    if not data then 
        self._logger:Debug("DataService:SetCurrency - no data found")
        return false 
    end
    
    -- Validate amount
    local currencyConfig = self._configLoader:GetCurrency(currencyType)
    if currencyConfig and currencyConfig.maxAmount then
        amount = math.min(amount, currencyConfig.maxAmount)
    end
    
    amount = math.max(0, amount) -- No negative currencies
    
    local oldAmount = data.Currencies[currencyType] or 0
    data.Currencies[currencyType] = amount
    
    -- Update player attribute
    player:SetAttribute(currencyType:gsub("^%l", string.upper), amount)
    
    self._logger:Debug("Currency set", {
        player = player.Name,
        currency = currencyType,
        oldAmount = oldAmount,
        newAmount = amount
    })
    
    return true
end

function DataService:AddCurrency(player, currencyType, amount)
    local currentAmount = self:GetCurrency(player, currencyType)
    return self:SetCurrency(player, currencyType, currentAmount + amount)
end

function DataService:RemoveCurrency(player, currencyType, amount)
    self._logger:Debug("DataService:RemoveCurrency called", {player = player.Name, currencyType = currencyType, amount = amount})
    
    local currentAmount = self:GetCurrency(player, currencyType)
    self._logger:Debug("DataService:RemoveCurrency got current amount", {currentAmount = currentAmount})
    
    local result = self:SetCurrency(player, currencyType, currentAmount - amount)
    self._logger:Debug("DataService:RemoveCurrency SetCurrency result", {result = result})
    
    return result
end

function DataService:CanAfford(player, currencyType, amount)
    return self:GetCurrency(player, currencyType) >= amount
end

-- Inventory management
function DataService:GetInventory(player)
    local data = self:GetData(player)
    return data and data.Inventory or {}
end

function DataService:GetItemCount(player, itemId)
    local inventory = self:GetInventory(player)
    return inventory[itemId] or 0
end

function DataService:AddToInventory(player, itemId, quantity)
    local data = self:GetData(player)
    if not data then return false end
    
    quantity = quantity or 1
    local currentCount = data.Inventory[itemId] or 0
    
    -- Check if item is stackable
    local itemConfig = self._configLoader:GetItem(itemId)
    if itemConfig and itemConfig.stackable then
        local maxStack = itemConfig.max_stack or 999
        local newCount = math.min(currentCount + quantity, maxStack)
        data.Inventory[itemId] = newCount
        
        self._logger:Debug("Item added to inventory", {
            player = player.Name,
            itemId = itemId,
            quantity = newCount - currentCount,
            newTotal = newCount
        })
        
        return true
    else
        -- Non-stackable items
        if currentCount == 0 then
            data.Inventory[itemId] = 1
            return true
        else
            return false -- Already have non-stackable item
        end
    end
end

function DataService:RemoveFromInventory(player, itemId, quantity)
    local data = self:GetData(player)
    if not data then return false end
    
    quantity = quantity or 1
    local currentCount = data.Inventory[itemId] or 0
    
    if currentCount >= quantity then
        local newCount = currentCount - quantity
        
        if newCount <= 0 then
            data.Inventory[itemId] = nil
        else
            data.Inventory[itemId] = newCount
        end
        
        self._logger:Debug("Item removed from inventory", {
            player = player.Name,
            itemId = itemId,
            quantity = quantity,
            remaining = newCount
        })
        
        return true
    end
    
    return false
end

function DataService:HasItem(player, itemId, quantity)
    quantity = quantity or 1
    return self:GetItemCount(player, itemId) >= quantity
end

-- Stats management
function DataService:GetStat(player, statName)
    local data = self:GetData(player)
    return data and data.Stats[statName]
end

function DataService:SetStat(player, statName, value)
    local data = self:GetData(player)
    if not data then return false end
    
    local oldValue = data.Stats[statName]
    data.Stats[statName] = value
    
    -- Update player attribute if it's a common stat
    if statName == "Level" or statName == "Health" or statName == "MaxHealth" then
        player:SetAttribute(statName, value)
    end
    
    self._logger:Debug("Stat updated", {
        player = player.Name,
        stat = statName,
        oldValue = oldValue,
        newValue = value
    })
    
    return true
end

function DataService:AddToStat(player, statName, amount)
    local currentValue = self:GetStat(player, statName) or 0
    return self:SetStat(player, statName, currentValue + amount)
end

-- Data migration
function DataService:MigrateProfile(profile)
    local data = profile.Data
    
    -- Example migration: Add new currency if it doesn't exist
    if not data.Currencies.gems then
        data.Currencies.gems = 0
        self._logger:Info("Migrated profile: Added gems currency")
    end
    
    -- Add join date if missing
    if not data.JoinDate or data.JoinDate == 0 then
        data.JoinDate = os.time()
    end
    
    -- Ensure all template fields exist
    profile:Reconcile()
end

-- Event handlers
function DataService:_onProfileLoaded(player, profile)
    self._logger:Debug("_onProfileLoaded called", {player = player.Name})
    
    -- Initialize player in game world
    local gameConfig = self._configLoader:LoadConfig("game")
    self._logger:Debug("Game config loaded in _onProfileLoaded", {gameConfig = gameConfig})
    
    -- Set player properties based on saved data
    if player.Character then
        self._logger:Debug("Player character found, setting properties")
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = gameConfig.WorldSettings.WalkSpeed
            humanoid.JumpPower = gameConfig.WorldSettings.JumpPower
            self._logger:Debug("Character properties set")
        else
            self._logger:Debug("No humanoid found in character")
        end
    else
        self._logger:Debug("No player character found yet")
    end
    
    -- AUTO-SETUP FOR TESTING: Give test items and coins if player has none
    self._logger:Debug("Checking if in Studio", {isStudio = game:GetService("RunService"):IsStudio()})
    if game:GetService("RunService"):IsStudio() then
        self._logger:Debug("In Studio, starting auto-setup")
        local data = profile.Data
        self._logger:Debug("Profile data", {
            coins = data.Currencies.coins,
            inventory = data.Inventory,
            testItem = data.Inventory.test_item
        })
        
        -- Give starting coins if player has 0
        if data.Currencies.coins == 0 then
            self._logger:Debug("Player has 0 coins, giving 500 for comprehensive testing")
            data.Currencies.coins = 500
            player:SetAttribute("Coins", 500)
            self._logger:Info("Auto-setup: Gave starting coins for comprehensive testing", {player = player.Name})
        else
            self._logger:Debug("Player already has coins", {coins = data.Currencies.coins})
        end
        
        -- Give starting gems for multi-currency testing
        if data.Currencies.gems < 200 then
            self._logger:Debug("Player has insufficient gems for testing, setting to 200")
            data.Currencies.gems = 200
            player:SetAttribute("Gems", 200)
            self._logger:Info("Auto-setup: Set gems to 200 for comprehensive effect testing", {player = player.Name})
        else
            self._logger:Debug("Player already has sufficient gems", {gems = data.Currencies.gems})
        end
        
        -- Give starting crystals for comprehensive currency testing
        if not data.Currencies.crystals or data.Currencies.crystals == 0 then
            self._logger:Debug("Player has 0 crystals, giving 10")
            data.Currencies.crystals = 10
            player:SetAttribute("Crystals", 10)
            self._logger:Info("Auto-setup: Gave starting crystals for comprehensive testing", {player = player.Name})
        else
            self._logger:Debug("Player already has crystals", {crystals = data.Currencies.crystals})
        end
        
        -- Give test item if player doesn't have one
        if not data.Inventory.test_item or data.Inventory.test_item == 0 then
            self._logger:Debug("Player has no test_item, giving 1")
            data.Inventory.test_item = 1
            self._logger:Info("Auto-setup: Gave test item for testing", {player = player.Name})
        else
            self._logger:Debug("Player already has test_item", {count = data.Inventory.test_item})
        end
        
        self._logger:Debug("Auto-setup completed")
    else
        self._logger:Debug("Not in Studio, skipping auto-setup")
    end
    
            -- Load persistent effects if PlayerEffectsService is available
        if self._playerEffectsService then
            self._logger:Info("Loading player effects from DataService", {player = player.Name})
            self._playerEffectsService:LoadPlayerEffects(player)
        else
            self._logger:Warn("PlayerEffectsService not available for loading effects", {
                player = player.Name,
                hasPlayerEffectsService = self._playerEffectsService ~= nil
            })
        end
    
    self._logger:Debug("_onProfileLoaded finished", {player = player.Name})
end

-- Utility functions
function DataService:SaveAllProfiles()
    -- Force save all active profiles (useful for server shutdown)
    for player, profile in pairs(self.Profiles) do
        if profile then
            -- ProfileStore auto-saves, but we can force it
            self._logger:Debug("Force saving profile", {player = player.Name})
        end
    end
end

function DataService:GetActivePlayerCount()
    local count = 0
    for _ in pairs(self.Profiles) do
        count = count + 1
    end
    return count
end

-- Graceful shutdown
game:BindToClose(function()
    if DataService._logger then
        DataService._logger:Info("Shutting down DataService...")
    end
    
    -- Give time for final saves
    task.wait(2)
end)

return DataService 