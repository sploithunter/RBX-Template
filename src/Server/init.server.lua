--[[
    Server Bootstrap - Initializes the server-side game systems
    
    This file:
    1. Sets up the module loader with dependencies
    2. Loads all services in the correct order
    3. Initializes Matter ECS world and systems
    4. Starts the game loop based on configuration
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- Wait for packages to be available
local Packages = ReplicatedStorage:WaitForChild("Packages", 10)
if not Packages then
    error("Packages not found - make sure 'wally install' has been run")
end

-- Core dependencies  
local Locations = require(ReplicatedStorage.Shared.Locations)
local Matter = Locations.getLibrary("Matter") -- Matter ECS framework (manual due to Wally/Rojo sync issues)
local Reflex = Locations.getPackage("Reflex") -- Redux-like state management (via Wally) 
local ModuleLoader = require(Locations.SharedUtils.ModuleLoader)

-- Console noise reduction: defer logging until Logger is initialized

-- Create module loader
local loader = ModuleLoader.new()

-- Register core utilities (loaded first)
loader:RegisterModule("Logger", ReplicatedStorage.Shared.Utils.Logger)
loader:RegisterModule("ConfigLoader", ReplicatedStorage.Shared.ConfigLoader, {"Logger"})
loader:RegisterModule("ServerClockService", ServerScriptService.Server.Services.ServerClockService, {"Logger"})
-- NetworkConfig removed - using Signals instead

-- Register server services
loader:RegisterModule("DataService", ServerScriptService.Server.Services.DataService, {"Logger", "ConfigLoader"})
loader:RegisterModule("AdminService", ServerScriptService.Server.Services.AdminService, {"Logger", "ConfigLoader"})
loader:RegisterModule("RateLimitService", ServerScriptService.Server.Services.RateLimitService, {"Logger", "ConfigLoader", "DataService", "ServerClockService"})
loader:RegisterModule("AssetPreloadService", ServerScriptService.Server.Services.AssetPreloadService, {"Logger", "ConfigLoader"})
loader:RegisterModule("BreakableSpawner", ServerScriptService.Server.Services.BreakableSpawner, {"Logger", "ConfigLoader"})
loader:RegisterModule("BreakableService", ServerScriptService.Server.Services.BreakableService, {"Logger", "ConfigLoader"})
loader:RegisterModule("PlayerEffectsService", ServerScriptService.Server.Services.PlayerEffectsService, {"Logger", "ConfigLoader", "DataService", "ServerClockService"})
loader:RegisterModule("GlobalEffectsService", ServerScriptService.Server.Services.GlobalEffectsService, {"Logger", "ConfigLoader", "DataService", "ServerClockService"})
loader:RegisterModule("ProductIdMapper", ReplicatedStorage.Shared.Utils.ProductIdMapper, {"Logger", "ConfigLoader"})
loader:RegisterModule("EconomyService", ServerScriptService.Server.Services.EconomyService, {"Logger", "DataService", "ConfigLoader", "PlayerEffectsService", "GlobalEffectsService", "AdminService", "InventoryService"})
loader:RegisterModule("MonetizationService", ServerScriptService.Server.Services.MonetizationService, {"Logger", "DataService", "EconomyService", "ProductIdMapper", "PlayerEffectsService"})
loader:RegisterModule("InventoryService", ServerScriptService.Server.Services.InventoryService, {"Logger", "DataService", "ConfigLoader"})
loader:RegisterModule("SettingsService", ServerScriptService.Server.Services.SettingsService, {"Logger", "DataService", "ConfigLoader"})
loader:RegisterModule("DiagnosticsService", ServerScriptService.Server.Services.DiagnosticsService, {"Logger", "InventoryService", "EconomyService", "RateLimitService", "DataService"})

-- Register lazy services (loaded when needed)
-- loader:RegisterLazyModule("TradeService", ServerScriptService.Server.Services.TradeService, {"EconomyService", "DataService", "NetworkBridge"}) -- TODO: Create TradeService
-- loader:RegisterLazyModule("CombatService", ServerScriptService.Server.Services.CombatService, {"DataService", "NetworkBridge", "ConfigLoader"}) -- TODO: Create CombatService
-- loader:RegisterLazyModule("MatchmakingService", ServerScriptService.Server.Services.MatchmakingService, {"DataService", "NetworkBridge"}) -- TODO: Create MatchmakingService

-- Load all modules with error handling
-- Loading will be reported via Logger after initialization
local loadSuccess, loadOrderOrError = pcall(function()
    return loader:LoadAll()
end)

if not loadSuccess then
    error("CRITICAL STARTUP FAILURE: Module loading failed - " .. tostring(loadOrderOrError))
end

local loadOrder = loadOrderOrError

-- Start services that need to be started
-- Service startup logs will be handled via Logger
local AssetPreloadService = loader:Get("AssetPreloadService")
if AssetPreloadService then
    -- noisy confirmation removed
else
    -- noisy warning removed (Logger will report if issues occur)
end

-- Validate critical modules loaded
local requiredModules = {"Logger", "ConfigLoader", "ServerClockService", "DataService", "PlayerEffectsService", "GlobalEffectsService", "EconomyService", "ProductIdMapper", "MonetizationService", "InventoryService", "SettingsService", "DiagnosticsService"}
for _, moduleName in ipairs(requiredModules) do
    local module = loader:Get(moduleName)
    if not module then
        error("CRITICAL: Required module failed to load: " .. moduleName)
    end
end

-- Validation complete

-- Get loaded modules for easy access
local Logger = loader:Get("Logger")
local ConfigLoader = loader:Get("ConfigLoader")
-- NetworkConfig removed - using Signals instead
local DataService = loader:Get("DataService")
local PlayerEffectsService = loader:Get("PlayerEffectsService")
local MonetizationService = loader:Get("MonetizationService")

-- Set up cross-references to avoid circular dependencies
DataService:SetPlayerEffectsService(PlayerEffectsService)

-- Legacy network handler connection removed - using Signals directly


-- Load game configuration
local gameConfig = ConfigLoader:LoadConfig("game")
Logger:Info("Game configuration loaded", {
    gameMode = gameConfig.GameMode,
    maxPlayers = gameConfig.MaxPlayers,
    enableTrading = gameConfig.EnableTrading,
    enablePvP = gameConfig.EnablePvP
})

-- Validate monetization setup
local monetizationStatus = ConfigLoader:GetMonetizationStatus()
Logger:Info("Monetization status", monetizationStatus)

if #monetizationStatus.validation.errors > 0 then
    Logger:Error("MONETIZATION SETUP ERRORS:", {errors = monetizationStatus.validation.errors})
    error("Fix monetization configuration errors before starting")
end

if #monetizationStatus.validation.warnings > 0 then
    Logger:Warn("MONETIZATION SETUP WARNINGS:", {warnings = monetizationStatus.validation.warnings})
end

if monetizationStatus.validation.hasPlaceholders then
    Logger:Warn("⚠️  MONETIZATION: Replace placeholder IDs with actual Roblox product/pass IDs from Creator Dashboard")
end

-- Initialize Matter ECS World
local world = Matter.World.new()
local loop = Matter.Loop.new(world)

Logger:Info("Matter ECS world created")

-- TODO: Register Matter systems based on game mode
-- This would load different systems for FPS vs Simulator vs Tower Defense
local systems = {}

-- Add core systems that work for all game modes
-- systems.MovementSystem = require(ServerScriptService.Server.Systems.MovementSystem)
-- systems.PhysicsSystem = require(ServerScriptService.Server.Systems.PhysicsSystem)

-- Add game-mode specific systems
if gameConfig.GameMode == "Simulator" then
    Logger:Info("Loading Simulator systems")
    -- systems.CollectionSystem = require(...)
    -- systems.PetSystem = require(...)
elseif gameConfig.GameMode == "FPS" then
    Logger:Info("Loading FPS systems")
    -- systems.WeaponSystem = require(...)
    -- systems.DamageSystem = require(...)
elseif gameConfig.GameMode == "TowerDefense" then
    Logger:Info("Loading Tower Defense systems")
    -- systems.WaveSystem = require(...)
    -- systems.TowerSystem = require(...)
end

-- Start Matter loop with systems
local systemsList = {}
for name, system in pairs(systems) do
    table.insert(systemsList, system)
    Logger:Debug("Registered system", {system = name})
end

-- Start the ECS loop (temporarily disabled for debugging)
-- loop:begin({
--     default = systemsList,
--     -- Add Matter debugger in Studio (disabled due to dependency issues)
--     -- debugger = game:GetService("RunService"):IsStudio() and Matter.Debugger.new() or nil
-- })

Logger:Info("Matter ECS loop started", {systemCount = #systemsList})

-- Initialize EggSpawner system
task.spawn(function()
    -- Small delay to ensure all dependencies are ready
    task.wait(1)
    
    Logger:Info("Starting EggSpawner initialization...")
    
    local success, eggSpawnerOrError = pcall(function()
        local Locations = require(ReplicatedStorage.Shared.Locations)
        return require(ReplicatedStorage.Shared.Services.EggSpawner)
    end)
    
    if success then
        Logger:Info("EggSpawner service loaded successfully")
        local EggSpawner = eggSpawnerOrError
        local initSuccess, initError = pcall(function()
            EggSpawner:Initialize()
        end)
        
        if initSuccess then
            Logger:Info("EggSpawner initialized successfully")
        else
            Logger:Error("Failed to initialize EggSpawner", {error = tostring(initError)})
        end
    else
        Logger:Error("Failed to load EggSpawner service", {error = tostring(eggSpawnerOrError)})
    end
end)

-- UserDisplayPreferences is now handled by SettingsService via ModuleLoader

-- Initialize EggService (following working game pattern)
task.spawn(function()
    task.wait(0.1) -- Small delay after UserDisplayPreferences
    
    Logger:Info("Starting EggService initialization...")
    
    local success, eggServiceOrError = pcall(function()
        local Locations = require(ReplicatedStorage.Shared.Locations)
        return require(script.Services.EggService)
    end)
    
    if success then
        Logger:Info("EggService loaded successfully")
        local EggService = eggServiceOrError
        local initSuccess, initError = pcall(function()
            EggService:Initialize(loader) -- Pass loader so EggService can access other services
        end)
        
        if initSuccess then
            Logger:Info("EggService initialized successfully")
        else
            Logger:Error("Failed to initialize EggService", {error = tostring(initError)})
        end
    else
        Logger:Error("Failed to load EggService", {error = tostring(eggServiceOrError)})
    end
end)

-- Player management
Players.PlayerAdded:Connect(function(player)
    Logger:Info("Player joined", {
        player = player.Name,
        userId = player.UserId,
        accountAge = player.AccountAge
    })
    
    -- Player will be handled by DataService automatically
    -- DataService:LoadProfile(player) is called automatically
end)

Players.PlayerRemoving:Connect(function(player)
    Logger:Info("Player leaving", {
        player = player.Name,
        userId = player.UserId
    })
    
    -- Cleanup handled by DataService automatically
end)

-- Set up global error handling (ScriptContext deprecated, using LogService instead)
local LogService = game:GetService("LogService")
LogService.MessageOut:Connect(function(message, messageType)
    if messageType == Enum.MessageType.MessageError then
        -- Filter out Studio plugin errors (not our template's responsibility)
        if not string.find(message, "plugin") and not string.find(message, "Plugin") then
            Logger:Error("Server script error", {
                message = message,
                messageType = messageType.Name
            })
        end
    end
end)

-- Performance monitoring (configurable)
task.spawn(function()
    local loggingConfig = nil
    -- Safely attempt to load logging config from ReplicatedStorage.Configs.logging
    local ok, result = pcall(function()
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local Configs = ReplicatedStorage:WaitForChild("Configs", 5)
        if Configs and Configs:FindFirstChild("logging") then
            return require(Configs.logging)
        end
        return nil
    end)
    if ok then loggingConfig = result end

    local perfCfg = (loggingConfig and loggingConfig.performance_monitor and loggingConfig.performance_monitor.server) or {
        enabled = true,
        interval_seconds = 30,
        target_frame_time_seconds = 1/60,
        warn_frame_time_seconds = 1/30,
        error_frame_time_seconds = 0.0667,
    }

    if not perfCfg.enabled then
        return
    end

    while true do
        task.wait(perfCfg.interval_seconds or 30)

        local heartbeatTime = game:GetService("RunService").Heartbeat:Wait()
        local stats = {
            playerCount = #Players:GetPlayers(),
            memoryUsage = game:GetService("Stats"):GetTotalMemoryUsageMb(),
            heartbeatTime = heartbeatTime,
        }

        Logger:Debug("Server performance", stats)

        local target = perfCfg.target_frame_time_seconds or (1/60)
        local warnAt = perfCfg.warn_frame_time_seconds or (1/30)
        local errorAt = perfCfg.error_frame_time_seconds or 0.0667

        if heartbeatTime > errorAt then
            Logger:Error("Server performance severely degraded", {
                frameTime = heartbeatTime,
                targetFrameTime = target,
                threshold = errorAt
            })
        elseif heartbeatTime > warnAt then
            Logger:Warn("Server performance degraded", {
                frameTime = heartbeatTime,
                targetFrameTime = target,
                threshold = warnAt
            })
        end
    end
end)

-- Graceful shutdown handling
game:BindToClose(function()
    Logger:Info("Server shutting down...")
    
    -- Give services time to clean up
    task.wait(1)
    
    -- Stop Matter loop
    loop:stop()
    
    Logger:Info("Server shutdown complete")
end)

Logger:Info("🎮 Game Template Server started successfully!", {
    gameMode = gameConfig.GameMode,
    maxPlayers = gameConfig.MaxPlayers,
    systemCount = #systemsList
}) 