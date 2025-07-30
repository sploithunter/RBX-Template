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

local Locations = require(game.ReplicatedStorage.Shared.Locations)
local ProfileStore = Locations.getPackage("ProfileStore")
local Promise = Locations.getPackage("Promise")

local DataService = {}
DataService.__index = DataService

-- Configuration-driven player data template generator
local function generateProfileTemplate(configLoader)
    local template = {
        -- Player info
        JoinDate = 0,
        LastLogin = 0,
        PlayTime = 0,
        
        -- Currencies (generated from configuration)
        Currencies = {},
        
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
        ActiveEffects = {},
        
        -- Player Clock (for persistent time tracking)
        PlayerClock = {
            lastSaveTime = 0,
            totalPlayTime = 0
        },
        
        -- Game Pass Benefits and Multipliers
        Multipliers = {},
        
        -- Game Pass Features
        Features = {},
        
        -- Game Pass Perks
        Perks = {},
        
        -- Owned Game Passes
        OwnedPasses = {},
        
        -- Purchase History
        PurchaseHistory = {},
        
        -- Premium Status
        PremiumStatus = {
            isPremium = false,
            premiumSince = 0
        },
        
        -- Player Titles
        Titles = {}
    }
    
    -- Load currencies from configuration
    if configLoader then
        local success, currenciesConfig = pcall(function()
            return configLoader:LoadConfig("currencies")
        end)
        
        if success and currenciesConfig then
            for _, currency in ipairs(currenciesConfig) do
                template.Currencies[currency.id] = currency.defaultAmount or 0
            end
        else
            -- Fallback currencies if config fails
            template.Currencies = {
                coins = 100,
                gems = 0,
                crystals = 0
            }
        end
    end
    
    return template
end

-- Get the profile template (will be set during Init)
local ProfileTemplate = {}

function DataService:Init()
    -- Get logger and config loader
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    
    -- Generate configuration-driven ProfileTemplate
    ProfileTemplate = generateProfileTemplate(self._configLoader)
    
    self._logger:Debug("ProfileTemplate generated from configuration", {
        currencyCount = self._configLoader and #(self._configLoader:LoadConfig("currencies") or {}) or 0
    })
    
    -- Initialize ProfileStore
    self.ProfileStore = ProfileStore.New(
        "PlayerData_v1", -- Version the store for easier migrations
        ProfileTemplate
    )
    
    -- Track active profiles
    self.Profiles = {}
    self.LoadPromises = {}
    
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
            
            -- COIN TRACING: Monitor all changes to Coins attribute
            player:GetAttributeChangedSignal("Coins"):Connect(function()
                local newValue = player:GetAttribute("Coins")
                local stackTrace = debug.traceback("", 2)
                
                -- Determine if this change came from our DataService
                local isFromDataService = stackTrace:find("DataService") ~= nil
                local isFromSetCurrency = stackTrace:find("SetCurrency") ~= nil
                
                self._logger:Info("🪙 COIN TRACE - Coins attribute CHANGED", {
                    player = player.Name,
                    newCoinsValue = newValue,
                    changeSource = isFromDataService and "DataService" or "EXTERNAL",
                    viaSetCurrency = isFromSetCurrency,
                    stackTrace = stackTrace:sub(1, 200) -- Truncate for readability
                })
                
                -- If changed externally, this is likely the bug!
                if not isFromDataService then
                    self._logger:Warn("🚨 EXTERNAL COIN CHANGE DETECTED - This may be the bug!", {
                        player = player.Name,
                        externalValue = newValue,
                        fullStackTrace = stackTrace
                    })
                end
            end)
            
            -- Also monitor Gems for completeness
            player:GetAttributeChangedSignal("Gems"):Connect(function()
                local newValue = player:GetAttribute("Gems")
                local stackTrace = debug.traceback("Gems attribute changed", 2)
                self._logger:Info("💎 GEM TRACE - Gems attribute CHANGED", {
                    player = player.Name,
                    newGemsValue = newValue,
                    stackTrace = stackTrace
                })
            end)
            
            self._logger:Info("Profile loaded successfully", {
                player = player.Name,
                level = data.Stats.Level,
                coins = data.Currencies.coins,
                sessionCount = data.Analytics.SessionCount
            })
            
            -- COIN TRACING: Log what was loaded from ProfileStore
            self._logger:Info("🪙 LOADED FROM PROFILESTORE", {
                player = player.Name,
                coins = data.Currencies.coins,
                gems = data.Currencies.gems,
                session = data.Analytics.SessionCount
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
        -- COIN TRACING: Log what we're about to save
        local data = profile.Data
        self._logger:Info("🪙 SAVING TO PROFILESTORE", {
            player = player.Name,
            coins = data.Currencies.coins,
            gems = data.Currencies.gems,
            session = data.Analytics.SessionCount
        })
        
        -- Update session data
        local sessionDuration = tick() - self.SessionStartTime
        profile.Data.Analytics.LastSessionDuration = sessionDuration
        profile.Data.Analytics.TotalPlayTime = profile.Data.Analytics.TotalPlayTime + sessionDuration
        
        -- End the session (this triggers the save)
        profile:EndSession()
        
        self._logger:Info("🪙 COIN TRACE - Profile save triggered via EndSession", {
            player = player.Name,
            sessionDuration = sessionDuration,
            finalCoinsValue = data.Currencies.coins
        })
    else
        self._logger:Warn("🪙 COIN TRACE - No profile found for player during release", {
            player = player.Name
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
    local currencyIcon = currencyType == "coins" and "🪙" or (currencyType == "gems" and "💎" or "💰")
    self._logger:Info(currencyIcon .. " CURRENCY TRACE - SetCurrency called", {
        player = player.Name, 
        currencyType = currencyType, 
        requestedAmount = amount
    })
    
    local data = self:GetData(player)
    if not data then 
        self._logger:Error(currencyIcon .. " CURRENCY TRACE - SetCurrency FAILED - no profile data found")
        return false 
    end
    
    -- Log current state before change
    local oldAmount = data.Currencies[currencyType] or 0
    self._logger:Info(currencyIcon .. " CURRENCY TRACE - Current state before change", {
        player = player.Name,
        currency = currencyType,
        currentProfileValue = oldAmount,
        currentAttributeValue = player:GetAttribute(currencyType:gsub("^%l", string.upper)),
        requestedNewValue = amount
    })
    
    -- Validate amount
    local currencyConfig = self._configLoader:GetCurrency(currencyType)
    if currencyConfig and currencyConfig.maxAmount then
        local originalAmount = amount
        amount = math.min(amount, currencyConfig.maxAmount)
        if amount ~= originalAmount then
            self._logger:Info(currencyIcon .. " CURRENCY TRACE - Currency capped to max", {
                currency = currencyType, 
                originalAmount = originalAmount, 
                cappedAmount = amount,
                maxAmount = currencyConfig.maxAmount
            })
        end
    end
    
    amount = math.max(0, amount) -- No negative currencies
    
    -- Make the changes
    data.Currencies[currencyType] = amount
    
    -- Update player attribute
    local attributeName = currencyType:gsub("^%l", string.upper)
    player:SetAttribute(attributeName, amount)
    
    self._logger:Info(currencyIcon .. " CURRENCY TRACE - Currency updated in profile and attribute", {
        player = player.Name,
        currency = currencyType,
        oldAmount = oldAmount,
        newAmount = amount,
        attributeName = attributeName,
        profileValue = data.Currencies[currencyType],
        attributeValue = player:GetAttribute(attributeName),
        profileMatches = (data.Currencies[currencyType] == amount),
        attributeMatches = (player:GetAttribute(attributeName) == amount)
    })
    
    -- Verify the change took effect
    task.wait(0.1)
    local verifyAmount = self:GetCurrency(player, currencyType)
    local verifyAttribute = player:GetAttribute(attributeName)
    self._logger:Info(currencyIcon .. " CURRENCY TRACE - Post-change verification", {
        player = player.Name,
        currency = currencyType,
        setAmount = amount,
        retrievedFromProfile = verifyAmount,
        retrievedFromAttribute = verifyAttribute,
        profileMatches = (verifyAmount == amount),
        attributeMatches = (verifyAttribute == amount),
        allMatch = (verifyAmount == amount and verifyAttribute == amount)
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

-- Configuration-driven data migration
function DataService:MigrateProfile(profile)
    local data = profile.Data
    local migrationCount = 0
    
    -- 1. Migrate currencies from configuration
    migrationCount = migrationCount + self:_migrateCurrencies(data)
    
    -- 2. Migrate monetization-related sections
    migrationCount = migrationCount + self:_migrateMonetizationSections(data)
    
    -- 3. Migrate core data structure
    migrationCount = migrationCount + self:_migrateCoreData(data)
    
    -- 4. SAFE Reconcile - only adds missing fields, never removes
    profile:Reconcile()
    
    if migrationCount > 0 then
        self._logger:Info("Profile migration completed", {
            player = "Unknown", -- Called before player context
            migrationsApplied = migrationCount
        })
    end
end

function DataService:_migrateCurrencies(data)
    local migrations = 0
    
    -- Load currencies from configuration
    local success, currenciesConfig = pcall(function()
        return self._configLoader:LoadConfig("currencies")
    end)
    
    if success and currenciesConfig then
        -- Ensure Currencies section exists
        if not data.Currencies then
            data.Currencies = {}
            migrations = migrations + 1
        end
        
        -- ONE-TIME MIGRATION: Fix currencies that were incorrectly set by previous AI session
        -- This fixes the issue where coins were set to 70 instead of the correct config value
        if not data._migrations then
            data._migrations = {}
        end
        
        if not data._migrations.fixIncorrectCurrencies then
            self._logger:Info("🪙 COIN TRACE - Running one-time currency fix migration")
            for _, currency in ipairs(currenciesConfig) do
                local configDefault = currency.defaultAmount or 0
                local currentAmount = data.Currencies[currency.id] or 0
                
                self._logger:Info("🪙 COIN TRACE - Migration checking currency", {
                    currency = currency.id,
                    savedValue = currentAmount,
                    configDefault = configDefault,
                    needsFixing = (currentAmount ~= configDefault)
                })
                
                -- Reset to config defaults for all currencies to fix previous AI errors
                if currentAmount ~= configDefault then
                    self._logger:Info("🪙 COIN TRACE - Migration FIXING currency", {
                        currency = currency.id,
                        oldIncorrectValue = currentAmount,
                        newCorrectValue = configDefault
                    })
                    data.Currencies[currency.id] = configDefault
                    migrations = migrations + 1
                else
                    self._logger:Info("🪙 COIN TRACE - Migration SKIPPING currency (already correct)", {
                        currency = currency.id,
                        value = currentAmount
                    })
                end
            end
            data._migrations.fixIncorrectCurrencies = true
            migrations = migrations + 1
            self._logger:Info("🪙 COIN TRACE - Currency fix migration completed", {
                totalMigrations = migrations
            })
        else
            self._logger:Info("🪙 COIN TRACE - Currency fix migration already completed, skipping")
        end
        
        -- Add any new currencies from config (never remove existing ones)
        for _, currency in ipairs(currenciesConfig) do
            if not data.Currencies[currency.id] then
                data.Currencies[currency.id] = currency.defaultAmount or 0
                self._logger:Debug("Added new currency from config", {
                    currency = currency.id,
                    defaultAmount = currency.defaultAmount or 0
                })
                migrations = migrations + 1
            end
        end
    end
    
    return migrations
end

function DataService:_migrateMonetizationSections(data)
    local migrations = 0
    
    -- Add monetization sections if missing (never remove data)
    local monetizationSections = {
        "Multipliers",
        "Features", 
        "Perks",
        "OwnedPasses",
        "PurchaseHistory",
        "PremiumStatus",
        "Titles"
    }
    
    for _, section in ipairs(monetizationSections) do
        if not data[section] then
            if section == "OwnedPasses" or section == "PurchaseHistory" or section == "Titles" then
                data[section] = {}  -- Arrays
            elseif section == "PremiumStatus" then
                data[section] = {
                    isPremium = false,
                    premiumSince = 0
                }
            else
                data[section] = {}  -- Objects
            end
            migrations = migrations + 1
        end
    end
    
    return migrations
end

function DataService:_migrateCoreData(data)
    local migrations = 0
    
    -- Add join date if missing
    if not data.JoinDate or data.JoinDate == 0 then
        data.JoinDate = os.time()
        migrations = migrations + 1
    end
    
    -- Ensure core sections exist
    local coreSections = {
        "Stats",
        "GameData", 
        "Settings",
        "Analytics",
        "ActiveEffects",
        "PlayerClock",
        "Inventory"
    }
    
    for _, section in ipairs(coreSections) do
        if not data[section] then
            data[section] = {}
            migrations = migrations + 1
        end
    end
    
    -- Ensure PlayerClock has required fields
    if not data.PlayerClock.lastSaveTime then
        data.PlayerClock.lastSaveTime = 0
        migrations = migrations + 1
    end
    if not data.PlayerClock.totalPlayTime then
        data.PlayerClock.totalPlayTime = 0
        migrations = migrations + 1
    end
    
    return migrations
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
    
    -- FIRST-TIME PLAYER SETUP: Only give currencies on actual first login (based on config defaults)
    -- This replaces the old testing auto-setup that was overriding admin currency changes
    local data = profile.Data
    local isFirstLogin = (data.Analytics.SessionCount == 1)
    
    if isFirstLogin then
        self._logger:Info("First-time player setup", {
            player = player.Name,
            sessionCount = data.Analytics.SessionCount
        })
        
        -- The currency defaults are already set from ProfileTemplate during profile creation
        -- We don't need to override them here, just log what they started with
        self._logger:Info("New player starting currencies", {
            player = player.Name,
            startingCoins = data.Currencies.coins,
            startingGems = data.Currencies.gems,
            startingCrystals = data.Currencies.crystals
        })
    else
        self._logger:Debug("Returning player - preserving existing currency values", {
            player = player.Name,
            sessionCount = data.Analytics.SessionCount,
            currentCoins = data.Currencies.coins,
            currentGems = data.Currencies.gems,
            currentCrystals = data.Currencies.crystals
        })
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

-- Game Pass and Monetization Methods
function DataService:SetMultiplier(player, statName, multiplier)
    local data = self:GetData(player)
    if not data then return false end
    
    if not data.Multipliers then
        data.Multipliers = {}
    end
    
    data.Multipliers[statName] = multiplier
    self._logger:Debug("Set multiplier", {
        player = player.Name,
        stat = statName,
        multiplier = multiplier
    })
    return true
end

function DataService:GetMultiplier(player, statName)
    local data = self:GetData(player)
    if not data or not data.Multipliers then
        return 1.0  -- Default multiplier
    end
    return data.Multipliers[statName] or 1.0
end

function DataService:SetFeature(player, featureName, enabled)
    local data = self:GetData(player)
    if not data then return false end
    
    if not data.Features then
        data.Features = {}
    end
    
    data.Features[featureName] = enabled
    self._logger:Debug("Set feature", {
        player = player.Name,
        feature = featureName,
        enabled = enabled
    })
    return true
end

function DataService:GetFeature(player, featureName)
    local data = self:GetData(player)
    if not data or not data.Features then
        return false
    end
    return data.Features[featureName] or false
end

function DataService:SetPerk(player, perkName, value)
    local data = self:GetData(player)
    if not data then return false end
    
    if not data.Perks then
        data.Perks = {}
    end
    
    data.Perks[perkName] = value
    self._logger:Debug("Set perk", {
        player = player.Name,
        perk = perkName,
        value = value
    })
    return true
end

function DataService:GetPerk(player, perkName)
    local data = self:GetData(player)
    if not data or not data.Perks then
        return nil
    end
    return data.Perks[perkName]
end

function DataService:SetOwnedPasses(player, passes)
    local data = self:GetData(player)
    if not data then return false end
    
    data.OwnedPasses = passes or {}
    self._logger:Debug("Set owned passes", {
        player = player.Name,
        passCount = #data.OwnedPasses
    })
    return true
end

function DataService:GetOwnedPasses(player)
    local data = self:GetData(player)
    if not data then return {} end
    return data.OwnedPasses or {}
end

function DataService:RecordPurchase(player, purchaseData)
    local data = self:GetData(player)
    if not data then return false end
    
    if not data.PurchaseHistory then
        data.PurchaseHistory = {}
    end
    
    table.insert(data.PurchaseHistory, purchaseData)
    self._logger:Info("Purchase recorded", {
        player = player.Name,
        purchaseType = purchaseData.type,
        purchaseId = purchaseData.id
    })
    return true
end

function DataService:GetPurchaseHistory(player)
    local data = self:GetData(player)
    if not data then return {} end
    return data.PurchaseHistory or {}
end

function DataService:HasMadeAnyPurchase(player)
    local history = self:GetPurchaseHistory(player)
    return #history > 0
end

function DataService:SetPremiumStatus(player, isPremium)
    local data = self:GetData(player)
    if not data then return false end
    
    if not data.PremiumStatus then
        data.PremiumStatus = {
            isPremium = false,
            premiumSince = 0
        }
    end
    
    local wasntPremium = not data.PremiumStatus.isPremium
    data.PremiumStatus.isPremium = isPremium
    
    if isPremium and wasntPremium then
        data.PremiumStatus.premiumSince = os.time()
    end
    
    self._logger:Debug("Set premium status", {
        player = player.Name,
        isPremium = isPremium
    })
    return true
end

function DataService:GetPremiumStatus(player)
    local data = self:GetData(player)
    if not data or not data.PremiumStatus then
        return {isPremium = false, premiumSince = 0}
    end
    return data.PremiumStatus
end

function DataService:GrantTitle(player, title)
    local data = self:GetData(player)
    if not data then return false end
    
    if not data.Titles then
        data.Titles = {}
    end
    
    if not table.find(data.Titles, title) then
        table.insert(data.Titles, title)
        self._logger:Info("Title granted", {
            player = player.Name,
            title = title
        })
    end
    return true
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