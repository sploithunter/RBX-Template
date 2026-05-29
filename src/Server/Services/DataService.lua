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

local PROFILE_STORE_NAME = "PlayerData_v2_mixedPets"
local PROFILESTORE_AUTO_SAVE_PERIOD_SECONDS = 60
local DEFAULT_SAVE_DEBOUNCE_SECONDS = 15
local CRITICAL_SAVE_DEBOUNCE_SECONDS = 1
local PERIODIC_SAVE_SECONDS = 60
local SAVE_CONFIRM_TIMEOUT_SECONDS = 10
local CURRENT_SCHEMA_VERSION = 4

local function countInventoryItems(inventory)
    local counts = {}
    for bucketName, bucket in pairs(inventory or {}) do
        local count = 0
        if type(bucket) == "table" and type(bucket.items) == "table" then
            for _ in pairs(bucket.items) do
                count += 1
            end
        end
        counts[bucketName] = count
    end
    return counts
end

-- Configuration-driven player data template generator
local function generateProfileTemplate(configLoader)
    local template = {
        SchemaVersion = CURRENT_SCHEMA_VERSION,

        -- Player info
        JoinDate = 0,
        LastLogin = 0,
        PlayTime = 0,

        -- Currencies (generated from configuration)
        Currencies = {},

        -- Inventory system (generated from configuration)
        Inventory = {},

        -- Equipped items (generated from configuration)
        Equipped = {},

        -- Permanent player upgrades (generated from configuration)
        Upgrades = {},

        -- Player stats
        Stats = {
            Level = 1,
            Experience = 0,
            Health = 100,
            MaxHealth = 100,
            Counters = {},
        },

        Ledger = {
            CurrencySources = {},
            CurrencySinks = {},
        },

        PetIndex = {
            Discovered = {},
            Milestones = {},
        },

        Achievements = {
            Completed = {},
        },

        -- Game-specific data
        GameData = {
            TutorialCompleted = false,
            CurrentQuest = nil,
            UnlockedAreas = { "Spawn" },
        },

        -- Settings
        Settings = {
            MusicEnabled = true,
            SFXEnabled = true,
            GraphicsQuality = "Auto",
            -- Display preferences for UI elements
            DisplayPreferences = {
                inventory = "images",
                egg_preview = "images",
                shop_display = "images",
            },
            AutoSystems = {
                auto_target = {
                    enabled = false,
                    mode = "nearest",
                    selected_currency = "crystals",
                },
                auto_delete = {
                    enabled = false,
                    rarities = {},
                    pet_types = {},
                    variants = {},
                },
                hatch = {
                    selected_count = 1,
                    modes = {},
                },
            },
        },

        -- Analytics data
        Analytics = {
            SessionCount = 0,
            TotalPlayTime = 0,
            LastSessionDuration = 0,
            Purchases = {},
            Achievements = {},
        },

        -- Active Effects (persistent across sessions)
        ActiveEffects = {},

        -- Player Clock (for persistent time tracking)
        PlayerClock = {
            lastSaveTime = 0,
            totalPlayTime = 0,
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
            premiumSince = 0,
        },

        -- Player Titles
        Titles = {},
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
                crystals = 0,
            }
        end

        -- Load inventory configuration and generate buckets
        local inventorySuccess, inventoryConfig = pcall(function()
            return configLoader:LoadConfig("inventory")
        end)

        if inventorySuccess and inventoryConfig then
            -- 🛡️ SAFETY PRINCIPLE: Only ADD new buckets from config, NEVER remove existing ones
            -- This prevents accidental data loss if buckets are temporarily disabled in config

            for bucketName, enabled in pairs(inventoryConfig.enabled_buckets) do
                if enabled and inventoryConfig.buckets[bucketName] then
                    local bucketConfig = inventoryConfig.buckets[bucketName]

                    -- Only create bucket if it doesn't exist (never overwrite)
                    if not template.Inventory[bucketName] then
                        template.Inventory[bucketName] = {
                            items = {}, -- Will store item UID -> item data
                            total_slots = bucketConfig.base_limit,
                            used_slots = 0,
                        }

                        -- Quiet console: keep traces disabled by default
                    else
                        -- Quiet console: keep traces disabled by default
                    end
                end
            end

            -- Log any buckets that exist in template but are not in current config
            -- (This helps detect accidentally disabled buckets)
            for existingBucket in pairs(template.Inventory) do
                if not inventoryConfig.enabled_buckets[existingBucket] then
                    -- Quiet console: keep traces disabled by default
                end
            end

            -- Generate equipped slots from configuration
            for equipCategory, equipConfig in pairs(inventoryConfig.equipped or {}) do
                if type(equipConfig.slots) == "number" then
                    -- Simple slot count (e.g., pets = 3 slots)
                    template.Equipped[equipCategory] = {}
                    for i = 1, equipConfig.slots do
                        template.Equipped[equipCategory]["slot_" .. i] = nil -- Empty slot
                    end

                    -- Quiet console: keep traces disabled by default
                elseif type(equipConfig.slots) == "table" then
                    -- Named slots (e.g., armor = {helmet=1, chest=1, etc.})
                    template.Equipped[equipCategory] = {}
                    for slotName, slotCount in pairs(equipConfig.slots) do
                        if slotCount == 1 then
                            template.Equipped[equipCategory][slotName] = nil -- Single slot
                        else
                            -- Multiple slots (future expansion)
                            for i = 1, slotCount do
                                template.Equipped[equipCategory][slotName .. "_" .. i] = nil
                            end
                        end
                    end

                    -- Quiet console: keep traces disabled by default
                end
            end

            -- Quiet console: keep traces disabled by default
        else
            warn("📦 INVENTORY TRACE - Failed to load inventory config, using minimal fallback")
            -- Minimal fallback inventory structure
            template.Inventory = {
                pets = {
                    items = {},
                    total_slots = 50,
                    used_slots = 0,
                },
            }
            template.Equipped = {
                pets = {
                    slot_1 = nil,
                    slot_2 = nil,
                    slot_3 = nil,
                },
            }
        end

        local statsSuccess, statsConfig = pcall(function()
            return configLoader:LoadConfig("stats")
        end)

        if statsSuccess and statsConfig and statsConfig.counters then
            for counterId, counterConfig in pairs(statsConfig.counters) do
                template.Stats.Counters[counterId] = counterConfig.default or 0
            end
        end

        local autoSuccess, autoConfig = pcall(function()
            return configLoader:LoadConfig("auto_systems")
        end)
        if autoSuccess and autoConfig then
            local autoTarget = autoConfig.auto_target or {}
            local autoDelete = autoConfig.auto_delete or {}
            local selectedHatchCount = 1
            local eggSuccess, eggConfig = pcall(function()
                return configLoader:LoadConfig("egg_system")
            end)
            if eggSuccess and type(eggConfig) == "table" then
                local hatching = eggConfig.hatching or {}
                local panel = eggConfig.ui and eggConfig.ui.hatch_panel or {}
                selectedHatchCount = tonumber(panel.default_selected_count)
                    or tonumber(hatching.default_requested_count)
                    or selectedHatchCount
            end
            template.Settings.AutoSystems = {
                auto_target = {
                    enabled = autoTarget.default_enabled == true,
                    mode = autoTarget.default_mode or "nearest",
                    selected_currency = autoTarget.default_selected_currency or "crystals",
                },
                auto_delete = {
                    enabled = autoDelete.default_enabled == true,
                    rarities = autoDelete.defaults and autoDelete.defaults.rarities or {},
                    pet_types = autoDelete.defaults and autoDelete.defaults.pet_types or {},
                    variants = autoDelete.defaults and autoDelete.defaults.variants or {},
                },
                hatch = {
                    selected_count = math.max(1, math.floor(tonumber(selectedHatchCount) or 1)),
                    modes = {},
                },
            }
        end

        local upgradesSuccess, upgradesConfig = pcall(function()
            return configLoader:LoadConfig("upgrades")
        end)

        if upgradesSuccess and upgradesConfig and upgradesConfig.upgrades then
            for upgradeId in pairs(upgradesConfig.upgrades) do
                template.Upgrades[upgradeId] = 0
            end
        end
    end

    return template
end

-- Get the profile template (will be set during Init)
local ProfileTemplate = {}
local SchemaMigrations = {}

SchemaMigrations[0] = function(self, data)
    local migrations = 0

    if not data.Stats then
        data.Stats = {}
        migrations += 1
    end

    if not data.Stats.Counters then
        data.Stats.Counters = {}
        migrations += 1
    end

    if not data.Ledger then
        data.Ledger = {
            CurrencySources = {},
            CurrencySinks = {},
        }
        migrations += 1
    else
        if not data.Ledger.CurrencySources then
            data.Ledger.CurrencySources = {}
            migrations += 1
        end
        if not data.Ledger.CurrencySinks then
            data.Ledger.CurrencySinks = {}
            migrations += 1
        end
    end

    self:_backfillStatCounters(data)

    data.SchemaVersion = 1
    return migrations + 1
end

SchemaMigrations[1] = function(self, data)
    local migrations = self:_migrateUpgrades(data)
    data.SchemaVersion = 2
    return migrations + 1
end

SchemaMigrations[2] = function(self, data)
    local migrations = self:_migratePhase3Collections(data)
    data.SchemaVersion = 3
    return migrations + 1
end

SchemaMigrations[3] = function(self, data)
    local migrations = self:_migrateAutoSystemSettings(data)
    data.SchemaVersion = 4
    return migrations + 1
end

function DataService:Init()
    -- Get logger and config loader
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader

    -- Generate configuration-driven ProfileTemplate
    ProfileTemplate = generateProfileTemplate(self._configLoader)

    self._logger:Debug("ProfileTemplate generated from configuration", {
        currencyCount = self._configLoader and #(self._configLoader:LoadConfig("currencies") or {})
            or 0,
    })

    local constantSuccess, constantError = pcall(function()
        ProfileStore.SetConstant("AUTO_SAVE_PERIOD", PROFILESTORE_AUTO_SAVE_PERIOD_SECONDS)
    end)

    if not constantSuccess then
        self._logger:Warn("Failed to tune ProfileStore auto-save period", {
            context = "DataService",
            error = tostring(constantError),
        })
    end

    -- Initialize ProfileStore
    self.ProfileStore = ProfileStore.New(PROFILE_STORE_NAME, ProfileTemplate)

    -- Track active profiles
    self.Profiles = {}
    self.LoadPromises = {}
    self.CurrencySignalConnections = {}
    self.SaveRequests = {}
    self.PersistenceWarningsIssued = {}
    self.AutoSaveLoopRunning = false

    -- Connect to player events
    Players.PlayerAdded:Connect(function(player)
        self:LoadProfile(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:ReleaseProfile(player)
    end)

    -- Session tracking
    self.SessionStartTime = tick()

    task.spawn(function()
        local state = self:_waitForProfileStoreState(8)
        self:_publishPersistenceState(state)
    end)

    self._logger:Info("DataService initialized", {
        profileStore = PROFILE_STORE_NAME,
        profileStoreAutoSaveSeconds = PROFILESTORE_AUTO_SAVE_PERIOD_SECONDS,
        periodicSaveSeconds = PERIODIC_SAVE_SECONDS,
    })
end

function DataService:Start()
    self:_startAutoSaveLoop()

    for _, player in ipairs(Players:GetPlayers()) do
        if not self.Profiles[player] then
            self:LoadProfile(player)
        end
    end
end

function DataService:_waitForProfileStoreState(timeoutSeconds)
    local timeout = tonumber(timeoutSeconds) or 0
    local startTime = tick()

    while ProfileStore.DataStoreState == "NotReady" and tick() - startTime < timeout do
        task.wait(0.1)
    end

    return ProfileStore.DataStoreState or "Unknown"
end

function DataService:_publishPersistenceState(state)
    local canPersist = state == "Access"
    ReplicatedStorage:SetAttribute("ProfileStoreDataState", state)
    ReplicatedStorage:SetAttribute("ProfilePersistenceEnabled", canPersist)

    if canPersist then
        self._logger:Info("Profile persistence is active", {
            context = "DataService",
            profileStore = PROFILE_STORE_NAME,
            dataStoreState = state,
        })
    else
        self._logger:Warn(
            "Profile persistence is NOT active; Studio is using temporary mock data",
            {
                context = "DataService",
                profileStore = PROFILE_STORE_NAME,
                dataStoreState = state,
                fix = "Publish the experience and enable Studio Access to API Services in Game Settings > Security.",
            }
        )
    end
end

function DataService:_getSaveState(player)
    self.SaveRequests[player] = self.SaveRequests[player]
        or {
            dirty = false,
            scheduled = false,
            inFlight = false,
            pendingAfterInFlight = false,
            saveRequestId = 0,
            lastReason = nil,
            lastRequestedAt = 0,
            lastConfirmedAt = 0,
        }

    return self.SaveRequests[player]
end

function DataService:_startAutoSaveLoop()
    if self.AutoSaveLoopRunning then
        return
    end

    self.AutoSaveLoopRunning = true

    task.spawn(function()
        while self.AutoSaveLoopRunning do
            task.wait(PERIODIC_SAVE_SECONDS)

            for player, profile in pairs(self.Profiles) do
                if profile and profile:IsActive() then
                    self:RequestSave(player, "periodic_autosave", {
                        debounceSeconds = 0,
                    })
                end
            end
        end
    end)
end

function DataService:RequestSave(player, reason, options)
    options = options or {}

    local profile = self.Profiles[player]
    if not profile or not profile:IsActive() then
        return false
    end

    local saveState = self:_getSaveState(player)
    saveState.dirty = true
    saveState.lastReason = reason or "unspecified"
    saveState.lastRequestedAt = tick()

    local debounceSeconds = options.debounceSeconds
    if debounceSeconds == nil then
        debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS
    end

    if options.critical == true then
        debounceSeconds = math.min(debounceSeconds, CRITICAL_SAVE_DEBOUNCE_SECONDS)
    end

    if debounceSeconds <= 0 then
        self:_saveProfileNow(player, saveState.lastReason)
        return true
    end

    if saveState.scheduled then
        return true
    end

    saveState.scheduled = true

    task.delay(debounceSeconds, function()
        local currentState = self.SaveRequests[player]
        if not currentState then
            return
        end

        currentState.scheduled = false

        if currentState.dirty then
            self:_saveProfileNow(player, currentState.lastReason or "debounced_save")
        end
    end)

    return true
end

function DataService:_saveProfileNow(player, reason)
    local profile = self.Profiles[player]
    if not profile or not profile:IsActive() then
        return false
    end

    local saveState = self:_getSaveState(player)
    if saveState.inFlight then
        saveState.pendingAfterInFlight = true
        saveState.lastReason = reason or saveState.lastReason
        return true
    end

    local dataStoreState = ProfileStore.DataStoreState or "Unknown"
    if dataStoreState ~= "Access" and not self.PersistenceWarningsIssued[player] then
        self.PersistenceWarningsIssued[player] = true
        self._logger:Warn(
            "Profile save requested while persistence is unavailable; this save cannot survive a Studio restart",
            {
                context = "DataService",
                player = player.Name,
                reason = reason,
                dataStoreState = dataStoreState,
            }
        )
    end

    saveState.inFlight = true
    saveState.pendingAfterInFlight = false
    saveState.saveRequestId += 1

    local requestId = saveState.saveRequestId
    local connected = true
    local afterSaveConnection

    afterSaveConnection = profile.OnAfterSave:Connect(function()
        if not connected then
            return
        end

        connected = false
        afterSaveConnection:Disconnect()

        saveState.inFlight = false
        saveState.dirty = false
        saveState.lastConfirmedAt = tick()

        self._logger:Debug("Profile save confirmed", {
            context = "DataService",
            player = player.Name,
            reason = reason,
            dataStoreState = dataStoreState,
        })

        if
            saveState.pendingAfterInFlight
            and self.Profiles[player] == profile
            and profile:IsActive()
        then
            saveState.pendingAfterInFlight = false
            self:_saveProfileNow(player, saveState.lastReason or "pending_save")
        end
    end)

    self._logger:Debug("Profile save requested", {
        context = "DataService",
        player = player.Name,
        reason = reason,
        dataStoreState = dataStoreState,
    })

    local saveCallSuccess, saveCallError = pcall(function()
        profile:Save()
    end)

    if not saveCallSuccess then
        connected = false
        afterSaveConnection:Disconnect()
        saveState.inFlight = false

        self._logger:Error("Profile save request failed to start", {
            context = "DataService",
            player = player.Name,
            reason = reason,
            error = tostring(saveCallError),
        })

        return false
    end

    task.delay(SAVE_CONFIRM_TIMEOUT_SECONDS, function()
        local currentState = self.SaveRequests[player]
        if
            currentState ~= saveState
            or currentState.saveRequestId ~= requestId
            or not connected
        then
            return
        end

        connected = false
        afterSaveConnection:Disconnect()
        saveState.inFlight = false

        self._logger:Warn("Profile save did not confirm before timeout", {
            context = "DataService",
            player = player.Name,
            reason = reason,
            waitedSeconds = SAVE_CONFIRM_TIMEOUT_SECONDS,
            dataStoreState = dataStoreState,
        })

        if
            saveState.pendingAfterInFlight
            and self.Profiles[player] == profile
            and profile:IsActive()
        then
            saveState.pendingAfterInFlight = false
            self:_saveProfileNow(player, saveState.lastReason or "pending_save_after_timeout")
        end
    end)

    return true
end

function DataService:LoadProfile(player)
    if self.LoadPromises[player] then
        return self.LoadPromises[player]
    end

    self._logger:Info("Loading profile", { player = player.Name, userId = player.UserId })

    local promise = task.spawn(function()
        local profile = self.ProfileStore:StartSessionAsync("Player_" .. player.UserId, {
            Cancel = function()
                return player.Parent == nil -- Cancel if player left
            end,
        })

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
            -- Expose ALL currencies from configuration/profile dynamically
            for currencyId, amount in pairs(data.Currencies or {}) do
                local attrName = currencyId:gsub("^%l", string.upper)
                player:SetAttribute(attrName, amount or 0)
            end

            -- Attach attribute change listeners for ALL currencies dynamically
            self.CurrencySignalConnections[player] = self.CurrencySignalConnections[player] or {}
            for currencyId, _ in pairs(data.Currencies or {}) do
                local attrName = currencyId:gsub("^%l", string.upper)
                -- Avoid duplicate connections
                if not self.CurrencySignalConnections[player][attrName] then
                    local conn = player:GetAttributeChangedSignal(attrName):Connect(function()
                        local newValue = player:GetAttribute(attrName)
                        local serverValue = self:GetCurrency(player, currencyId)
                        -- Only log when mismatched (external change)
                        if newValue ~= serverValue then
                            self._logger:Warn("🪙 CURRENCY ATTRIBUTE CHANGED EXTERNALLY", {
                                player = player.Name,
                                currency = currencyId,
                                attributeValue = newValue,
                                profileValue = serverValue,
                            })
                        end
                    end)
                    self.CurrencySignalConnections[player][attrName] = conn
                end
            end

            -- (Coins/Gems specific handlers removed; replaced by dynamic currency loop above)

            -- INVENTORY TRACE: Log the inventory structure that was loaded/created
            local inventoryInfo = {}
            for bucketName, bucket in pairs(data.Inventory or {}) do
                -- SAFETY CHECK: Handle both old format (numbers) and new format (bucket objects)
                if type(bucket) == "table" and bucket.total_slots then
                    -- New bucket format
                    inventoryInfo[bucketName] = {
                        total_slots = bucket.total_slots,
                        used_slots = bucket.used_slots,
                        item_count = 0,
                        format = "new_bucket",
                    }
                    if bucket.items then
                        for _ in pairs(bucket.items) do
                            inventoryInfo[bucketName].item_count = inventoryInfo[bucketName].item_count
                                + 1
                        end
                    end
                else
                    -- Old format (direct item counts) - preserve but mark for migration
                    inventoryInfo[bucketName] = {
                        total_slots = "unknown",
                        used_slots = "unknown",
                        item_count = type(bucket) == "number" and bucket or 0,
                        format = "legacy_count",
                        legacy_value = bucket,
                    }

                    self._logger:Warn("🚨 INVENTORY LEGACY FORMAT DETECTED", {
                        player = player.Name,
                        bucketName = bucketName,
                        legacyValue = bucket,
                        needsMigration = true,
                    })
                end
            end

            local equippedInfo = {}
            for category, slots in pairs(data.Equipped or {}) do
                equippedInfo[category] = {}
                for slotName, itemUid in pairs(slots) do
                    equippedInfo[category][slotName] = itemUid and "occupied" or "empty"
                end
            end

            self._logger:Info("Profile loaded successfully", {
                player = player.Name,
                level = data.Stats.Level,
                coins = data.Currencies.coins,
                sessionCount = data.Analytics.SessionCount,
                inventoryStructure = inventoryInfo,
                equippedStructure = equippedInfo,
            })

            self._logger:Info("📦 INVENTORY TRACE - Profile inventory structure loaded", {
                player = player.Name,
                inventoryBuckets = inventoryInfo,
                equippedCategories = equippedInfo,
                hasInventoryData = data.Inventory ~= nil,
                hasEquippedData = data.Equipped ~= nil,
            })

            -- COIN TRACING: Log what was loaded from ProfileStore
            self._logger:Info("🪙 LOADED FROM PROFILESTORE", {
                player = player.Name,
                coins = data.Currencies.coins,
                gems = data.Currencies.gems,
                session = data.Analytics.SessionCount,
            })

            -- Trigger profile loaded event
            self._logger:Debug("About to call _onProfileLoaded", { player = player.Name })
            self:_onProfileLoaded(player, profile)
            self._logger:Debug("_onProfileLoaded completed", { player = player.Name })
        else
            -- Profile failed to load
            self._logger:Error("Failed to load profile", {
                player = player.Name,
                userId = player.UserId,
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
        local data = profile.Data
        local sessionDuration = tick() - self.SessionStartTime
        data.Analytics.LastSessionDuration = sessionDuration
        data.Analytics.TotalPlayTime = data.Analytics.TotalPlayTime + sessionDuration

        -- COIN TRACING: Log what we're about to save
        self._logger:Info("🪙 SAVING TO PROFILESTORE", {
            player = player.Name,
            coins = data.Currencies.coins,
            gems = data.Currencies.gems,
            crystals = data.Currencies.crystals,
            session = data.Analytics.SessionCount,
            inventoryCounts = countInventoryItems(data.Inventory),
        })

        local saveCompleted = false
        local afterSaveConnection = profile.OnAfterSave:Connect(function()
            saveCompleted = true
        end)

        -- End the session (this triggers the save)
        profile:EndSession()

        local state = ProfileStore.DataStoreState or "Unknown"
        if state == "Access" then
            local waited = 0
            while not saveCompleted and waited < 10 do
                task.wait(0.1)
                waited += 0.1
            end

            if not saveCompleted then
                self._logger:Warn("Profile save did not confirm before timeout", {
                    context = "DataService",
                    player = player.Name,
                    waitedSeconds = waited,
                })
            end
        else
            self._logger:Warn(
                "Profile released while persistence is unavailable; data will not survive Studio restart",
                {
                    context = "DataService",
                    player = player.Name,
                    dataStoreState = state,
                }
            )
        end

        afterSaveConnection:Disconnect()

        self._logger:Info("🪙 COIN TRACE - Profile save triggered via EndSession", {
            player = player.Name,
            sessionDuration = sessionDuration,
            finalCoinsValue = data.Currencies.coins,
            finalCrystalsValue = data.Currencies.crystals,
        })
    else
        self._logger:Warn("🪙 COIN TRACE - No profile found for player during release", {
            player = player.Name,
        })
    end

    -- Cleanup
    self.Profiles[player] = nil
    self.LoadPromises[player] = nil
    self.SaveRequests[player] = nil
    self.PersistenceWarningsIssued[player] = nil
    if self.CurrencySignalConnections[player] then
        for _, conn in pairs(self.CurrencySignalConnections[player]) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        self.CurrencySignalConnections[player] = nil
    end
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
    if not data then
        return 0
    end

    return data.Currencies[currencyType] or 0
end

function DataService:SetCurrency(player, currencyType, amount, source)
    local currencyIcon = currencyType == "coins" and "🪙"
        or (currencyType == "gems" and "💎" or "💰")
    self._logger:Info(currencyIcon .. " CURRENCY TRACE - SetCurrency called", {
        player = player.Name,
        currencyType = currencyType,
        requestedAmount = amount,
    })

    local data = self:GetData(player)
    if not data then
        self._logger:Error(
            currencyIcon .. " CURRENCY TRACE - SetCurrency FAILED - no profile data found"
        )
        return false
    end

    -- Log current state before change
    local oldAmount = data.Currencies[currencyType] or 0
    self._logger:Info(currencyIcon .. " CURRENCY TRACE - Current state before change", {
        player = player.Name,
        currency = currencyType,
        currentProfileValue = oldAmount,
        currentAttributeValue = player:GetAttribute(currencyType:gsub("^%l", string.upper)),
        requestedNewValue = amount,
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
                maxAmount = currencyConfig.maxAmount,
            })
        end
    end

    amount = math.max(0, amount) -- No negative currencies

    -- Make the changes
    data.Currencies[currencyType] = amount
    self:_recordCurrencyLedger(data, currencyType, amount - oldAmount, source or "set_currency")

    -- Update player attribute
    local attributeName = currencyType:gsub("^%l", string.upper)
    player:SetAttribute(attributeName, amount)

    self._logger:Info(
        currencyIcon .. " CURRENCY TRACE - Currency updated in profile and attribute",
        {
            player = player.Name,
            currency = currencyType,
            oldAmount = oldAmount,
            newAmount = amount,
            attributeName = attributeName,
            profileValue = data.Currencies[currencyType],
            attributeValue = player:GetAttribute(attributeName),
            profileMatches = (data.Currencies[currencyType] == amount),
            attributeMatches = (player:GetAttribute(attributeName) == amount),
        }
    )

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
        allMatch = (verifyAmount == amount and verifyAttribute == amount),
    })

    self:RequestSave(player, "currency_" .. tostring(currencyType), {
        debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
    })

    return true
end

function DataService:AddCurrency(player, currencyType, amount, source)
    local currentAmount = self:GetCurrency(player, currencyType)
    return self:SetCurrency(player, currencyType, currentAmount + amount, source or "currency_add")
end

function DataService:RemoveCurrency(player, currencyType, amount, source)
    self._logger:Debug(
        "DataService:RemoveCurrency called",
        { player = player.Name, currencyType = currencyType, amount = amount }
    )

    local currentAmount = self:GetCurrency(player, currencyType)
    self._logger:Debug(
        "DataService:RemoveCurrency got current amount",
        { currentAmount = currentAmount }
    )

    local result =
        self:SetCurrency(player, currencyType, currentAmount - amount, source or "currency_remove")
    self._logger:Debug("DataService:RemoveCurrency SetCurrency result", { result = result })

    return result
end

function DataService:_recordCurrencyLedger(data, currencyType, delta, source)
    if delta == 0 then
        return
    end

    data.Ledger = data.Ledger or {}
    data.Ledger.CurrencySources = data.Ledger.CurrencySources or {}
    data.Ledger.CurrencySinks = data.Ledger.CurrencySinks or {}

    local bucket = delta > 0 and data.Ledger.CurrencySources or data.Ledger.CurrencySinks
    local sourceKey = tostring(source or "unknown")
    bucket[sourceKey] = bucket[sourceKey] or {}
    bucket[sourceKey][currencyType] = (bucket[sourceKey][currencyType] or 0) + math.abs(delta)
end

function DataService:GetCurrencyLedger(player)
    local data = self:GetData(player)
    if not data then
        return {
            CurrencySources = {},
            CurrencySinks = {},
        }
    end

    data.Ledger = data.Ledger or {
        CurrencySources = {},
        CurrencySinks = {},
    }

    return data.Ledger
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
    if not data then
        return false
    end

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
            newTotal = newCount,
        })

        self:RequestSave(player, "legacy_inventory_add_" .. tostring(itemId), {
            debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
        })

        return true
    else
        -- Non-stackable items
        if currentCount == 0 then
            data.Inventory[itemId] = 1
            self:RequestSave(player, "legacy_inventory_add_" .. tostring(itemId), {
                debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
            })
            return true
        else
            return false -- Already have non-stackable item
        end
    end
end

function DataService:RemoveFromInventory(player, itemId, quantity)
    local data = self:GetData(player)
    if not data then
        return false
    end

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
            remaining = newCount,
        })

        self:RequestSave(player, "legacy_inventory_remove_" .. tostring(itemId), {
            debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
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
    if not data then
        return false
    end

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
        newValue = value,
    })

    self:RequestSave(player, "stat_" .. tostring(statName), {
        debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
    })

    return true
end

function DataService:AddToStat(player, statName, amount)
    local currentValue = self:GetStat(player, statName) or 0
    return self:SetStat(player, statName, currentValue + amount)
end

function DataService:GetCounter(player, counterId)
    local data = self:GetData(player)
    if not data or not data.Stats or not data.Stats.Counters then
        return 0
    end

    return data.Stats.Counters[counterId] or 0
end

function DataService:SetCounter(player, counterId, value)
    local data = self:GetData(player)
    if not data then
        return false
    end

    data.Stats = data.Stats or {}
    data.Stats.Counters = data.Stats.Counters or {}
    data.Stats.Counters[counterId] = value

    self:RequestSave(player, "counter_" .. tostring(counterId), {
        debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
    })

    return true
end

function DataService:AddToCounter(player, counterId, amount)
    return self:SetCounter(player, counterId, self:GetCounter(player, counterId) + amount)
end

-- Configuration-driven data migration
function DataService:MigrateProfile(profile)
    local data = profile.Data
    local migrationCount = 0

    migrationCount = migrationCount + self:_migrateSchemaVersion(data)

    -- 1. Migrate currencies from configuration
    migrationCount = migrationCount + self:_migrateCurrencies(data)

    -- 2. Migrate monetization-related sections
    migrationCount = migrationCount + self:_migrateMonetizationSections(data)

    -- 3. Migrate core data structure
    migrationCount = migrationCount + self:_migrateCoreData(data)
    migrationCount = migrationCount + self:_backfillStatCounters(data)
    migrationCount = migrationCount + self:_migrateUpgrades(data)
    migrationCount = migrationCount + self:_migrateLedger(data)
    migrationCount = migrationCount + self:_migratePhase3Collections(data)
    migrationCount = migrationCount + self:_migrateAutoSystemSettings(data)

    -- 4. Migrate inventory system safely (preserve all data)
    migrationCount = migrationCount + self:_migrateInventoryBuckets(data)

    -- 5. SAFE Reconcile - only adds missing fields, never removes
    profile:Reconcile()

    if migrationCount > 0 then
        self._logger:Info("Profile migration completed", {
            player = "Unknown", -- Called before player context
            migrationsApplied = migrationCount,
            schemaVersion = data.SchemaVersion,
        })
    end
end

function DataService:_migrateSchemaVersion(data)
    local migrations = 0
    local version = tonumber(data.SchemaVersion) or 0

    while version < CURRENT_SCHEMA_VERSION do
        local migration = SchemaMigrations[version]
        if not migration then
            error("Missing profile schema migration from version " .. tostring(version))
        end

        migrations = migrations + (migration(self, data) or 0)
        version = tonumber(data.SchemaVersion) or (version + 1)
    end

    if data.SchemaVersion ~= CURRENT_SCHEMA_VERSION then
        data.SchemaVersion = CURRENT_SCHEMA_VERSION
        migrations += 1
    end

    return migrations
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
        -- IMPORTANT: do NOT reset currencies to defaults. Only add missing keys.
        -- Older debug code that overwrote player balances has been removed to prevent data loss.
        if not data._migrations then
            data._migrations = {}
        end
        data._migrations.fixIncorrectCurrencies = true

        -- Add any new currencies from config (never remove existing ones)
        for _, currency in ipairs(currenciesConfig) do
            if not data.Currencies[currency.id] then
                data.Currencies[currency.id] = currency.defaultAmount or 0
                self._logger:Debug("Added new currency from config", {
                    currency = currency.id,
                    defaultAmount = currency.defaultAmount or 0,
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
        "Titles",
    }

    for _, section in ipairs(monetizationSections) do
        if not data[section] then
            if section == "PremiumStatus" then
                data[section] = {
                    isPremium = false,
                    premiumSince = 0,
                }
            else
                data[section] = {}
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
        "Inventory",
        "Upgrades",
        "PetIndex",
        "Achievements",
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

function DataService:_migrateUpgrades(data)
    local migrations = 0

    if not data.Upgrades then
        data.Upgrades = {}
        migrations += 1
    end

    local upgradesConfig
    local success = pcall(function()
        upgradesConfig = self._configLoader:LoadConfig("upgrades")
    end)

    if not success or not upgradesConfig or type(upgradesConfig.upgrades) ~= "table" then
        return migrations
    end

    for upgradeId in pairs(upgradesConfig.upgrades) do
        if data.Upgrades[upgradeId] == nil then
            data.Upgrades[upgradeId] = 0
            migrations += 1
        end
    end

    return migrations
end

function DataService:_backfillStatCounters(data)
    data.Stats = data.Stats or {}
    data.Stats.Counters = data.Stats.Counters or {}

    local statsConfig
    local success = pcall(function()
        statsConfig = self._configLoader:LoadConfig("stats")
    end)

    if not success or not statsConfig or type(statsConfig.counters) ~= "table" then
        return 0
    end

    local migrations = 0
    for counterId, counterConfig in pairs(statsConfig.counters) do
        if data.Stats.Counters[counterId] == nil then
            data.Stats.Counters[counterId] = counterConfig.default or 0
            migrations += 1
        end
    end

    return migrations
end

function DataService:_migrateLedger(data)
    local migrations = 0

    if not data.Ledger then
        data.Ledger = {}
        migrations += 1
    end

    if not data.Ledger.CurrencySources then
        data.Ledger.CurrencySources = {}
        migrations += 1
    end

    if not data.Ledger.CurrencySinks then
        data.Ledger.CurrencySinks = {}
        migrations += 1
    end

    return migrations
end

function DataService:_migratePhase3Collections(data)
    local migrations = 0

    if not data.PetIndex then
        data.PetIndex = {}
        migrations += 1
    end
    if not data.PetIndex.Discovered then
        data.PetIndex.Discovered = {}
        migrations += 1
    end
    if not data.PetIndex.Milestones then
        data.PetIndex.Milestones = {}
        migrations += 1
    end

    if not data.Achievements then
        data.Achievements = {}
        migrations += 1
    end
    if not data.Achievements.Completed then
        data.Achievements.Completed = {}
        migrations += 1
    end

    return migrations
end

function DataService:_migrateAutoSystemSettings(data)
    local migrations = 0

    data.Settings = data.Settings or {}
    if not data.Settings.AutoSystems then
        data.Settings.AutoSystems = {}
        migrations += 1
    end

    local autoConfig
    local success = pcall(function()
        autoConfig = self._configLoader:LoadConfig("auto_systems")
    end)
    autoConfig = success and autoConfig or {}

    local targetConfig = autoConfig.auto_target or {}
    local deleteConfig = autoConfig.auto_delete or {}
    local eggConfig
    local eggSuccess = pcall(function()
        eggConfig = self._configLoader:LoadConfig("egg_system")
    end)
    eggConfig = eggSuccess and eggConfig or {}
    local hatchingConfig = eggConfig.hatching or {}
    local panelConfig = eggConfig.ui and eggConfig.ui.hatch_panel or {}
    local defaultHatchCount = tonumber(panelConfig.default_selected_count)
        or tonumber(hatchingConfig.default_requested_count)
        or 1
    local maxHatchCount = math.max(1, math.floor(tonumber(hatchingConfig.max_count) or 99))

    local autoSystems = data.Settings.AutoSystems
    if type(autoSystems.auto_target) ~= "table" then
        autoSystems.auto_target = {}
        migrations += 1
    end
    if autoSystems.auto_target.enabled == nil then
        autoSystems.auto_target.enabled = targetConfig.default_enabled == true
        migrations += 1
    end
    if type(autoSystems.auto_target.mode) ~= "string" then
        autoSystems.auto_target.mode = targetConfig.default_mode or "nearest"
        migrations += 1
    end
    if type(autoSystems.auto_target.selected_currency) ~= "string" then
        autoSystems.auto_target.selected_currency = targetConfig.default_selected_currency
            or "crystals"
        migrations += 1
    end

    if type(autoSystems.auto_delete) ~= "table" then
        autoSystems.auto_delete = {}
        migrations += 1
    end
    if autoSystems.auto_delete.enabled == nil then
        autoSystems.auto_delete.enabled = deleteConfig.default_enabled == true
        migrations += 1
    end
    if type(autoSystems.auto_delete.rarities) ~= "table" then
        autoSystems.auto_delete.rarities = {}
        migrations += 1
    end
    if type(autoSystems.auto_delete.pet_types) ~= "table" then
        autoSystems.auto_delete.pet_types = {}
        migrations += 1
    end
    if type(autoSystems.auto_delete.variants) ~= "table" then
        autoSystems.auto_delete.variants = {}
        migrations += 1
    end

    if type(autoSystems.hatch) ~= "table" then
        autoSystems.hatch = {}
        migrations += 1
    end
    local selectedCount =
        math.floor(tonumber(autoSystems.hatch.selected_count) or defaultHatchCount)
    selectedCount = math.clamp(selectedCount, 1, maxHatchCount)
    if autoSystems.hatch.selected_count ~= selectedCount then
        autoSystems.hatch.selected_count = selectedCount
        migrations += 1
    end
    if type(autoSystems.hatch.modes) ~= "table" then
        autoSystems.hatch.modes = {}
        migrations += 1
    end
    for key, cfg in pairs(panelConfig.modes or {}) do
        local optionName = type(cfg) == "table" and tostring(cfg.option or key) or ""
        if optionName ~= "" and autoSystems.hatch.modes[optionName] == nil then
            autoSystems.hatch.modes[optionName] = false
            migrations += 1
        elseif optionName ~= "" and type(autoSystems.hatch.modes[optionName]) ~= "boolean" then
            autoSystems.hatch.modes[optionName] = autoSystems.hatch.modes[optionName] == true
            migrations += 1
        end
    end

    return migrations
end

function DataService:_migrateInventoryBuckets(data)
    local migrations = 0

    -- 🛡️ CRITICAL SAFETY PRINCIPLE: NEVER delete inventory buckets, only migrate/preserve
    self._logger:Info("🛡️ INVENTORY MIGRATION - Starting safe inventory bucket migration")

    -- Ensure core inventory structure exists
    if not data.Inventory then
        data.Inventory = {}
        migrations = migrations + 1
        self._logger:Info("📦 INVENTORY MIGRATION - Created Inventory section")
    end

    if not data.Equipped then
        data.Equipped = {}
        migrations = migrations + 1
        self._logger:Info("⚔️ INVENTORY MIGRATION - Created Equipped section")
    end

    -- Load current inventory configuration
    local inventoryConfig = nil
    local configSuccess, configResult = pcall(function()
        return self._configLoader:LoadConfig("inventory")
    end)

    if not configSuccess then
        self._logger:Warn(
            "🛡️ INVENTORY MIGRATION - Could not load config, preserving existing structure",
            {
                error = configResult,
            }
        )
        return migrations
    end

    inventoryConfig = configResult

    -- 🛡️ SAFETY RULE 1: Preserve ALL existing buckets regardless of current config
    for existingBucketName, existingBucket in pairs(data.Inventory) do
        if type(existingBucket) == "number" then
            -- LEGACY FORMAT: Convert old item count to new bucket format
            self._logger:Info("📦 INVENTORY MIGRATION - Converting legacy bucket", {
                bucketName = existingBucketName,
                oldFormat = "item_count",
                oldValue = existingBucket,
            })

            data.Inventory[existingBucketName] = {
                items = {},
                total_slots = 50, -- Default slot count for migrated buckets
                used_slots = 0,
                _migrated_from_legacy = true,
                _legacy_item_count = existingBucket, -- Preserve original data for reference
            }
            migrations = migrations + 1
        elseif type(existingBucket) == "table" then
            -- MODERN FORMAT: Ensure all required fields exist
            if not existingBucket.items then
                existingBucket.items = {}
                migrations = migrations + 1
            end
            if not existingBucket.total_slots then
                existingBucket.total_slots = 50 -- Default
                migrations = migrations + 1
            end
            if existingBucket.used_slots == nil then
                existingBucket.used_slots = 0
                migrations = migrations + 1
            end

            self._logger:Debug("📦 INVENTORY MIGRATION - Preserved modern bucket", {
                bucketName = existingBucketName,
                totalSlots = existingBucket.total_slots,
                usedSlots = existingBucket.used_slots,
            })
        end
    end

    -- 🛡️ SAFETY RULE 2: Add new buckets from config (but never remove existing ones)
    if inventoryConfig and inventoryConfig.enabled_buckets then
        for bucketName, enabled in pairs(inventoryConfig.enabled_buckets) do
            if enabled and inventoryConfig.buckets[bucketName] then
                local bucketConfig = inventoryConfig.buckets[bucketName]

                if not data.Inventory[bucketName] then
                    -- NEW BUCKET: Create from config
                    data.Inventory[bucketName] = {
                        items = {},
                        total_slots = bucketConfig.base_limit,
                        used_slots = 0,
                    }
                    migrations = migrations + 1

                    self._logger:Info("📦 INVENTORY MIGRATION - Added new bucket from config", {
                        bucketName = bucketName,
                        totalSlots = bucketConfig.base_limit,
                    })
                else
                    -- EXISTING BUCKET: Optionally update slot limits (but preserve data)
                    local existingBucket = data.Inventory[bucketName]
                    if type(existingBucket) == "table" and existingBucket.total_slots then
                        -- Only increase slot limits, never decrease (prevent data loss)
                        if bucketConfig.base_limit > existingBucket.total_slots then
                            existingBucket.total_slots = bucketConfig.base_limit
                            migrations = migrations + 1

                            self._logger:Info(
                                "📦 INVENTORY MIGRATION - Increased bucket slot limit",
                                {
                                    bucketName = bucketName,
                                    oldLimit = existingBucket.total_slots,
                                    newLimit = bucketConfig.base_limit,
                                }
                            )
                        end
                    end
                end
            end
        end

        -- Log any orphaned buckets (exist in profile but not in config)
        for existingBucketName in pairs(data.Inventory) do
            if not inventoryConfig.enabled_buckets[existingBucketName] then
                self._logger:Warn("⚠️ ORPHANED BUCKET DETECTED", {
                    bucketName = existingBucketName,
                    message = "Bucket exists in profile but not enabled in current config",
                    action = "PRESERVED (never deleted for safety)",
                    recommendation = "Consider re-enabling in config or create explicit deletion process",
                })
            end
        end
    end

    -- Migrate equipped slots safely
    if inventoryConfig and inventoryConfig.equipped then
        for equipCategory, equipConfig in pairs(inventoryConfig.equipped) do
            if not data.Equipped[equipCategory] then
                data.Equipped[equipCategory] = {}

                if type(equipConfig.slots) == "number" then
                    for i = 1, equipConfig.slots do
                        data.Equipped[equipCategory]["slot_" .. i] = nil
                    end
                elseif type(equipConfig.slots) == "table" then
                    for slotName, slotCount in pairs(equipConfig.slots) do
                        if slotCount == 1 then
                            data.Equipped[equipCategory][slotName] = nil
                        else
                            for i = 1, slotCount do
                                data.Equipped[equipCategory][slotName .. "_" .. i] = nil
                            end
                        end
                    end
                end

                migrations = migrations + 1
                self._logger:Info("⚔️ INVENTORY MIGRATION - Added equipped category", {
                    equipCategory = equipCategory,
                })
            end
        end
    end

    if migrations > 0 then
        self._logger:Info("🛡️ INVENTORY MIGRATION - Safe migration completed", {
            migrationsApplied = migrations,
            preservedBuckets = true,
            dataLossRisk = false,
        })
    end

    return migrations
end

-- Event handlers
function DataService:_onProfileLoaded(player, profile)
    self._logger:Debug("_onProfileLoaded called", { player = player.Name })

    -- Initialize player in game world
    local gameConfig = self._configLoader:LoadConfig("game")
    self._logger:Debug("Game config loaded in _onProfileLoaded", { gameConfig = gameConfig })

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
            sessionCount = data.Analytics.SessionCount,
        })

        -- The currency defaults are already set from ProfileTemplate during profile creation
        -- We don't need to override them here, just log what they started with
        self._logger:Info("New player starting currencies", {
            player = player.Name,
            startingCoins = data.Currencies.coins,
            startingGems = data.Currencies.gems,
            startingCrystals = data.Currencies.crystals,
        })
    else
        self._logger:Debug("Returning player - preserving existing currency values", {
            player = player.Name,
            sessionCount = data.Analytics.SessionCount,
            currentCoins = data.Currencies.coins,
            currentGems = data.Currencies.gems,
            currentCrystals = data.Currencies.crystals,
        })
    end

    -- Load persistent effects if PlayerEffectsService is available
    if self._playerEffectsService then
        self._logger:Info("Loading player effects from DataService", { player = player.Name })
        self._playerEffectsService:LoadPlayerEffects(player)
    else
        self._logger:Warn("PlayerEffectsService not available for loading effects", {
            player = player.Name,
            hasPlayerEffectsService = self._playerEffectsService ~= nil,
        })
    end

    self._logger:Debug("_onProfileLoaded finished", { player = player.Name })
end

-- Utility functions
function DataService:SaveAllProfiles()
    local playersToRelease = {}

    for player in pairs(self.Profiles) do
        table.insert(playersToRelease, player)
    end

    for _, player in ipairs(playersToRelease) do
        self._logger:Debug("Force releasing profile for shutdown", { player = player.Name })
        self:ReleaseProfile(player)
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
    if not data then
        return false
    end

    if not data.Multipliers then
        data.Multipliers = {}
    end

    data.Multipliers[statName] = multiplier
    self._logger:Debug("Set multiplier", {
        player = player.Name,
        stat = statName,
        multiplier = multiplier,
    })
    self:RequestSave(player, "multiplier_" .. tostring(statName), {
        debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
    })
    return true
end

function DataService:GetMultiplier(player, statName)
    local data = self:GetData(player)
    if not data or not data.Multipliers then
        return 1.0 -- Default multiplier
    end
    return data.Multipliers[statName] or 1.0
end

function DataService:SetFeature(player, featureName, enabled)
    local data = self:GetData(player)
    if not data then
        return false
    end

    if not data.Features then
        data.Features = {}
    end

    data.Features[featureName] = enabled
    self._logger:Debug("Set feature", {
        player = player.Name,
        feature = featureName,
        enabled = enabled,
    })
    self:RequestSave(player, "feature_" .. tostring(featureName), {
        debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
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
    if not data then
        return false
    end

    if not data.Perks then
        data.Perks = {}
    end

    data.Perks[perkName] = value
    self._logger:Debug("Set perk", {
        player = player.Name,
        perk = perkName,
        value = value,
    })
    self:RequestSave(player, "perk_" .. tostring(perkName), {
        debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
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
    if not data then
        return false
    end

    data.OwnedPasses = passes or {}
    self._logger:Debug("Set owned passes", {
        player = player.Name,
        passCount = #data.OwnedPasses,
    })
    self:RequestSave(player, "owned_passes", {
        critical = true,
    })
    return true
end

function DataService:GetOwnedPasses(player)
    local data = self:GetData(player)
    if not data then
        return {}
    end
    return data.OwnedPasses or {}
end

function DataService:RecordPurchase(player, purchaseData)
    local data = self:GetData(player)
    if not data then
        return false
    end

    if not data.PurchaseHistory then
        data.PurchaseHistory = {}
    end

    table.insert(data.PurchaseHistory, purchaseData)
    self._logger:Info("Purchase recorded", {
        player = player.Name,
        purchaseType = purchaseData.type,
        purchaseId = purchaseData.id,
    })
    self:RequestSave(player, "purchase_" .. tostring(purchaseData.id), {
        critical = true,
    })
    return true
end

function DataService:GetPurchaseHistory(player)
    local data = self:GetData(player)
    if not data then
        return {}
    end
    return data.PurchaseHistory or {}
end

function DataService:HasMadeAnyPurchase(player)
    local history = self:GetPurchaseHistory(player)
    return #history > 0
end

function DataService:SetPremiumStatus(player, isPremium)
    local data = self:GetData(player)
    if not data then
        return false
    end

    if not data.PremiumStatus then
        data.PremiumStatus = {
            isPremium = false,
            premiumSince = 0,
        }
    end

    local wasntPremium = not data.PremiumStatus.isPremium
    data.PremiumStatus.isPremium = isPremium

    if isPremium and wasntPremium then
        data.PremiumStatus.premiumSince = os.time()
    end

    self._logger:Debug("Set premium status", {
        player = player.Name,
        isPremium = isPremium,
    })
    self:RequestSave(player, "premium_status", {
        critical = true,
    })
    return true
end

function DataService:GetPremiumStatus(player)
    local data = self:GetData(player)
    if not data or not data.PremiumStatus then
        return { isPremium = false, premiumSince = 0 }
    end
    return data.PremiumStatus
end

function DataService:GrantTitle(player, title)
    local data = self:GetData(player)
    if not data then
        return false
    end

    if not data.Titles then
        data.Titles = {}
    end

    if not table.find(data.Titles, title) then
        table.insert(data.Titles, title)
        self._logger:Info("Title granted", {
            player = player.Name,
            title = title,
        })
        self:RequestSave(player, "title_" .. tostring(title), {
            debounceSeconds = DEFAULT_SAVE_DEBOUNCE_SECONDS,
        })
    end
    return true
end

-- Graceful shutdown
game:BindToClose(function()
    if DataService._logger then
        DataService._logger:Info("Shutting down DataService...")
    end

    if DataService.Profiles then
        DataService:SaveAllProfiles()
    else
        task.wait(2)
    end
end)

return DataService
