--[[
    Client Bootstrap - Initializes the client-side game systems
    
    This file:
    1. Sets up the module loader for client modules
    2. Initializes Matter ECS client world
    3. Sets up UI systems and controllers
    4. Handles networking with server
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

-- Wait for packages and shared modules
local Packages = ReplicatedStorage:WaitForChild("Packages", 10)
if not Packages then
    error("Packages not found - make sure 'wally install' has been run")
end

local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
if not Shared then
    error("Shared modules not found")
end

-- Core dependencies
local Matter = require(ReplicatedStorage.Shared.Libraries.Matter) -- Matter ECS framework
local Reflex = require(ReplicatedStorage.Shared.Libraries.Reflex) -- Redux-like state management
local ModuleLoader = require(Shared.Utils.ModuleLoader)

local localPlayer = Players.LocalPlayer

print("🎮 Starting Game Template Client...")

-- Create module loader for client
local loader = ModuleLoader.new()

-- Register shared utilities
loader:RegisterModule("Logger", Shared.Utils.Logger)
loader:RegisterModule("ConfigLoader", Shared.ConfigLoader, {"Logger"})
loader:RegisterModule("NetworkConfig", Shared.Utils.NetworkConfig, {"Logger", "ConfigLoader"})
loader:RegisterModule("NetworkBridge", Shared.Network.NetworkBridge, {"Logger", "NetworkConfig"})

-- Register client controllers
-- loader:RegisterModule("InputController", StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController, {"Logger"})
-- loader:RegisterModule("CameraController", StarterPlayer.StarterPlayerScripts.Client.Controllers.CameraController, {"Logger", "InputController"})
-- loader:RegisterModule("UIController", StarterPlayer.StarterPlayerScripts.Client.Controllers.UIController, {"Logger", "NetworkBridge"})

-- Register client systems (lazy loaded)
-- loader:RegisterLazyModule("RenderSystem", StarterPlayer.StarterPlayerScripts.Client.Systems.RenderSystem, {"Logger"})
-- loader:RegisterLazyModule("AnimationSystem", StarterPlayer.StarterPlayerScripts.Client.Systems.AnimationSystem, {"Logger"})
-- loader:RegisterLazyModule("ParticleSystem", StarterPlayer.StarterPlayerScripts.Client.Systems.ParticleSystem, {"Logger"})

-- Load all modules
print("📦 Loading client modules...")
local loadOrder = loader:LoadAll()
print("✅ Client modules loaded:", table.concat(loadOrder, ", "))

-- Get loaded modules for easy access
local Logger = loader:Get("Logger")
local ConfigLoader = loader:Get("ConfigLoader")
local NetworkConfig = loader:Get("NetworkConfig")
local NetworkBridge = loader:Get("NetworkBridge")

-- Load client configuration
local gameConfig = ConfigLoader:LoadConfig("game")
Logger:Info("Client initialized", {
    gameMode = gameConfig.GameMode,
    player = localPlayer.Name,
    userId = localPlayer.UserId
})

-- Initialize Matter ECS World for client
local world = Matter.World.new()
local loop = Matter.Loop.new(world)

Logger:Info("Client Matter ECS world created")

-- TODO: Register client-side Matter systems
local systems = {}

-- Add game-mode specific client systems
if gameConfig.GameMode == "Simulator" then
    Logger:Info("Loading Simulator client systems")
    -- systems.PetFollowSystem = require(...)
    -- systems.CollectionEffectsSystem = require(...)
elseif gameConfig.GameMode == "FPS" then
    Logger:Info("Loading FPS client systems")
    -- systems.WeaponRenderSystem = require(...)
    -- systems.CrosshairSystem = require(...)
elseif gameConfig.GameMode == "TowerDefense" then
    Logger:Info("Loading Tower Defense client systems")
    -- systems.TowerPreviewSystem = require(...)
    -- systems.PathVisualizationSystem = require(...)
end

-- Start Matter loop with client systems
local systemsList = {}
for name, system in pairs(systems) do
    table.insert(systemsList, system)
    Logger:Debug("Registered client system", {system = name})
end

-- Start the client ECS loop (temporarily disabled for debugging)
-- loop:begin({
--     default = systemsList,
--     -- Add Matter debugger in Studio (disabled due to dependency issues)
--     -- debugger = game:GetService("RunService"):IsStudio() and Matter.Debugger.new() or nil
-- })

Logger:Info("Client Matter ECS loop started", {systemCount = #systemsList})

-- Set up economy networking
local economyBridge = NetworkBridge:CreateBridge("Economy")

-- Define client-side packet handlers
economyBridge:Connect(function(packetType, data)
    Logger:Debug("Client received packet", {packetType = packetType, data = data})
    
    if packetType == "CurrencyUpdate" then
        Logger:Debug("Currency updated", data)
        -- Update UI currency display
        -- UIController:UpdateCurrency(data.currency, data.amount)
    elseif packetType == "ShopItems" then
        Logger:Debug("Shop items received", {itemCount = #data.items})
        print("🏪 SHOP ITEMS:")
        for i, item in ipairs(data.items) do
            print(string.format("   %d. %s - %d %s (Can afford: %s)", 
                i, item.name, item.price.amount, item.price.currency, tostring(item.canAfford)))
        end
    elseif packetType == "PurchaseSuccess" then
        Logger:Info("Purchase successful", data)
        print("✅ PURCHASE SUCCESS:", data.itemId)
        -- Show purchase success UI
        -- UIController:ShowPurchaseSuccess(data.itemId)
    elseif packetType == "SellSuccess" then
        Logger:Info("Sell successful", data)
        print("✅ SELL SUCCESS:", data.itemId, "for", data.totalPrice, "currency")
    elseif packetType == "EconomyError" then
        Logger:Warn("Economy error", data)
        print("❌ ECONOMY ERROR:", data.message)
        -- Show error message to player
        -- UIController:ShowError(data.message)
    elseif packetType == "PlayerDebugInfo" then
        print("🔍 SERVER DEBUG INFO:")
        print("   Server Inventory:", data.inventory)
        print("   Server Currencies:", data.currencies)
    elseif packetType == "ActiveEffects" then
        -- Update the effects status GUI (pass full data, not just data.effects)
        if _G.EffectsStatusGUI then
            _G.EffectsStatusGUI:UpdateFromServer(data)
        end
        print("⚡ ACTIVE EFFECTS UPDATED:", data.effects)
    elseif packetType == "GiveItemSuccess" then
        print("🎁 ITEM GIVEN:", data.message)
    end
end)

-- Set up input handling
local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end
    
    -- Example input handling
    if input.KeyCode == Enum.KeyCode.Tab then
        -- Toggle inventory
        Logger:Debug("Inventory toggle requested")
    elseif input.KeyCode == Enum.KeyCode.M then
        -- Toggle main menu
        Logger:Debug("Main menu toggle requested")
    elseif input.KeyCode == Enum.KeyCode.B then
        -- Open shop
        economyBridge:Fire("GetShopItems", {})
        Logger:Debug("Shop requested")
    end
end

UserInputService.InputBegan:Connect(onInputBegan)

-- Wait for character spawn
local function onCharacterAdded(character)
    Logger:Info("Character spawned", {
        character = character.Name,
        spawnTime = tick()
    })
    
    -- Wait for character to fully load
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    -- Apply game configuration to character
    humanoid.WalkSpeed = gameConfig.WorldSettings.WalkSpeed
    humanoid.JumpPower = gameConfig.WorldSettings.JumpPower
    
    -- Set up character-specific systems
    -- This is where you'd initialize things like:
    -- - First person camera for FPS
    -- - Pet following for simulators
    -- - Tool selection for tower defense
end

-- Connect character events
if localPlayer.Character then
    onCharacterAdded(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

-- Wait for data to load
local function waitForDataLoaded()
    local dataLoaded = localPlayer:GetAttribute("DataLoaded")
    if dataLoaded then
        Logger:Info("Player data loaded")
        
        -- Get initial currency values
        local coins = localPlayer:GetAttribute("Coins") or 0
        local gems = localPlayer:GetAttribute("Gems") or 0
        local level = localPlayer:GetAttribute("Level") or 1
        
        Logger:Info("Initial player state", {
            coins = coins,
            gems = gems,
            level = level
        })
        
        -- Initialize UI with player data
        -- UIController:InitializeWithPlayerData({
        --     coins = coins,
        --     gems = gems,
        --     level = level
        -- })
        
        return true
    end
    
    return false
end

-- Check if data is already loaded, or wait for it
if not waitForDataLoaded() then
    Logger:Info("Waiting for player data to load...")
    
    local connection
    connection = localPlayer:GetAttributeChangedSignal("DataLoaded"):Connect(function()
        if waitForDataLoaded() then
            connection:Disconnect()
        end
    end)
    
    -- Timeout after 30 seconds
    task.delay(30, function()
        if connection and connection.Connected then
            connection:Disconnect()
            Logger:Error("Timeout waiting for player data")
        end
    end)
end

-- Performance monitoring (client-side)
task.spawn(function()
    while true do
        task.wait(60) -- Log performance every minute
        
        local stats = {
            fps = 1 / game:GetService("RunService").Heartbeat:Wait(),
            ping = localPlayer:GetNetworkPing() * 1000, -- Convert to ms
            memoryUsage = game:GetService("Stats"):GetTotalMemoryUsageMb()
        }
        
        Logger:Debug("Client performance", stats)
        
        -- Warn if performance is poor
        if stats.fps < 30 then
            Logger:Warn("Low FPS detected", {fps = stats.fps})
        end
        
        if stats.ping > 200 then
            Logger:Warn("High ping detected", {ping = stats.ping})
        end
    end
end)

-- Handle game shutdown (only available on server)
-- Note: BindToClose only works on server, clients handle disconnection differently
if game:GetService("RunService"):IsServer() then
    game:BindToClose(function()
        Logger:Info("Client shutting down...")
        
        -- Stop Matter loop
        loop:stop()
        
        Logger:Info("Client shutdown complete")
    end)
end

-- Set up error handling (ScriptContext deprecated, using LogService instead)
local LogService = game:GetService("LogService")
LogService.MessageOut:Connect(function(message, messageType)
    if messageType == Enum.MessageType.MessageError then
        -- Filter out Studio plugin errors (not our template's responsibility)
        if not string.find(message, "plugin") and not string.find(message, "Plugin") then
            Logger:Error("Client script error", {
                message = message,
                messageType = messageType.Name
            })
        end
    end
end)

Logger:Info("🎯 Game Template Client started successfully!", {
    gameMode = gameConfig.GameMode,
    systemCount = #systemsList,
    player = localPlayer.Name
})

-- Load test GUI for economy testing (remove in production)
if game:GetService("RunService"):IsStudio() then
    task.spawn(function()
        require(script.UI.TestEconomyGUI)
        require(script.UI.SimpleEffectsGUI)
        require(script.UI.GlobalEffectsGUI)
    end)
end 