-- SettingsService.lua
-- 
-- Manages persistent player settings using ProfileStore as the single source of truth.
-- Creates replicated player folders that automatically sync to clients via Roblox's
-- built-in replication system. Handles user preference changes via Signals.
--
-- ARCHITECTURE:
-- 1. ProfileStore contains all settings data (single source of truth)
-- 2. Server creates Player/Settings/DisplayPreferences folders with StringValues
-- 3. Client reads directly from replicated folders (no DataService access needed)
-- 4. Client sends changes via Signals.SaveDisplayPreferences to server
-- 5. Server updates ProfileStore and replicated folders immediately
--
-- This pattern follows InventoryService's approach and leverages Roblox's automatic
-- Player folder replication to avoid complex client-server data synchronization.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Get shared modules
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local SettingsService = {}
SettingsService.__index = SettingsService

function SettingsService:Init()
    -- Console cleanup: route through Logger only
    
    -- Get injected dependencies
    self._logger = self._modules.Logger
    self._dataService = self._modules.DataService
    self._configLoader = self._modules.ConfigLoader
    
    -- Dependencies injected
    
    -- Track player settings folders for replication
    self._playerSettingsFolders = {}
    
    self._logger:Info("⚙️ SettingsService initializing")
    
    -- Connect to player events for folder management
    Players.PlayerAdded:Connect(function(player)
        self:_onPlayerAdded(player)
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        self:_onPlayerRemoving(player)
    end)
    
    -- Setup Network Signals for settings operations
    self:_setupNetworkSignals()
    
    self._logger:Info("✅ SettingsService initialized successfully")
end

function SettingsService:Start()
    -- Startup handled via Logger
    
    -- Create folders for any players already in game
    for _, player in pairs(Players:GetPlayers()) do
        if self._dataService:IsDataLoaded(player) then
            self._logger:Info("Creating settings folders for existing player", {player = player.Name})
            self:_createSettingsFolders(player)
        end
    end
    
    self._logger:Info("🚀 SettingsService started")
    -- Ready
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- PLAYER FOLDER MANAGEMENT (following InventoryService pattern exactly)
-- ═══════════════════════════════════════════════════════════════════════════════════

function SettingsService:_onPlayerAdded(player)
    -- Wait for DataService to load player profile
    task.spawn(function()
        local maxWait = 10  -- seconds
        local waited = 0
        
        while not self._dataService:IsDataLoaded(player) and waited < maxWait do
            task.wait(0.1)
            waited = waited + 0.1
        end
        
        if self._dataService:IsDataLoaded(player) then
            self:_createSettingsFolders(player)
        else
            self._logger:Warn("⚠️ SETTINGS - Player data not loaded in time", {
                player = player.Name,
                waitedSeconds = waited
            })
        end
    end)
end

function SettingsService:_onPlayerRemoving(player)
    -- Cleanup folder references
    self._playerSettingsFolders[player] = nil
    
    self._logger:Debug("🧹 SETTINGS - Cleaned up folder references", {
        player = player.Name
    })
end

function SettingsService:_createSettingsFolders(player)
    self._logger:Info("⚙️ SETTINGS - Creating settings folders", {
        player = player.Name
    })
    
    local data = self._dataService:GetData(player)
    if not data then
        self._logger:Error("❌ SETTINGS - No player data found", {
            player = player.Name
        })
        return
    end
    
    -- Ensure Settings exists in ProfileStore (single source of truth)
    if not data.Settings then
        data.Settings = {
            MusicEnabled = true,
            SFXEnabled = true,
            GraphicsQuality = "Auto",
            DisplayPreferences = {}
        }
    end
    
    -- Ensure DisplayPreferences exists
    if not data.Settings.DisplayPreferences then
        data.Settings.DisplayPreferences = {}
    end
    
    -- Create main Settings folder (will replicate to client)
    local settingsFolder = Instance.new("Folder")
    settingsFolder.Name = "Settings"
    settingsFolder.Parent = player
    
    -- Store reference
    self._playerSettingsFolders[player] = settingsFolder
    
    -- Create DisplayPreferences subfolder
    local displayPrefFolder = Instance.new("Folder")
    displayPrefFolder.Name = "DisplayPreferences"
    displayPrefFolder.Parent = settingsFolder
    
    -- Create StringValues for each display preference (from ProfileStore)
    for context, method in pairs(data.Settings.DisplayPreferences) do
        local prefValue = Instance.new("StringValue")
        prefValue.Name = context
        prefValue.Value = method
        prefValue.Parent = displayPrefFolder
    end
    
    self._logger:Info("✅ SETTINGS - Settings folders created successfully", {
        player = player.Name,
        displayPreferences = data.Settings.DisplayPreferences
    })
end

function SettingsService:_updateDisplayPreference(player, context, method)
    local data = self._dataService:GetData(player)
    if not data or not data.Settings then
        self._logger:Error("❌ No player settings data found", {
            player = player.Name,
            context = context
        })
        return false
    end
    
    -- Update ProfileStore (single source of truth)
    data.Settings.DisplayPreferences[context] = method
    
    -- Update replicated folder for immediate client access
    local settingsFolder = self._playerSettingsFolders[player]
    if settingsFolder then
        local displayPrefFolder = settingsFolder:FindFirstChild("DisplayPreferences")
        if displayPrefFolder then
            local prefValue = displayPrefFolder:FindFirstChild(context)
            if prefValue then
                prefValue.Value = method
            else
                -- Create new preference
                local newPrefValue = Instance.new("StringValue")
                newPrefValue.Name = context
                newPrefValue.Value = method
                newPrefValue.Parent = displayPrefFolder
            end
        end
    end
    
    self._logger:Info("✅ Updated display preference", {
        player = player.Name,
        context = context,
        method = method
    })
    
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- NETWORK SIGNALS (following InventoryService pattern)
-- ═══════════════════════════════════════════════════════════════════════════════════

function SettingsService:_setupNetworkSignals()
    -- Handle display preference updates from client
    Signals.SaveDisplayPreferences.OnServerEvent:Connect(function(player, preferences)
        self._logger:Info("📥 Received display preferences from client", {
            player = player.Name,
            preferences = preferences
        })
        
        if not preferences or type(preferences) ~= "table" then
            self._logger:Warn("❌ Invalid preferences data from client", {
                player = player.Name,
                preferences = preferences
            })
            return
        end
        
        -- Update each preference
        for context, method in pairs(preferences) do
            self:_updateDisplayPreference(player, context, method)
        end
    end)
    
    self._logger:Info("📡 Settings network signals configured")
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════════════

function SettingsService:GetDisplayPreference(player, context)
    local data = self._dataService:GetData(player)
    if data and data.Settings and data.Settings.DisplayPreferences then
        return data.Settings.DisplayPreferences[context]
    end
    return nil
end

return SettingsService