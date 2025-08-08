--[[
    EggInteractionService - Simplified to work with CurrentTarget system
    
    Now only handles E key presses and egg purchasing.
    All proximity detection and UI positioning is handled by EggCurrentTargetService.
    Follows the working game's pattern exactly.
--]]

local EggInteractionService = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Dependencies
local Locations = require(ReplicatedStorage.Shared.Locations)
local petConfig = Locations.getConfig("pets")
local eggSystemConfig = Locations.getConfig("egg_system")

-- Local player reference
local player = Players.LocalPlayer

-- Current target service reference
local currentTargetService = nil

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

-- === E KEY INTERACTION ===

function EggInteractionService:OnEKeyPressed()
    -- Get current target from the targeting service
    if not currentTargetService then
        Logger:Warn("CurrentTargetService not available", {context = "EggInteractionService"})
        return
    end
    
    local currentTarget = currentTargetService:GetCurrentTarget()
    if currentTarget == "None" or not currentTarget then
        Logger:Debug("No egg currently targeted", {context = "EggInteractionService"})
        return
    end
    
    Logger:Info("E pressed - attempting purchase", {context = "EggInteractionService", eggType = currentTarget})
    self:HandleEggPurchase(currentTarget)
end

-- === EGG PURCHASE HANDLING ===

function EggInteractionService:HandleEggPurchase(eggType)
    Logger:Info("Requesting egg purchase", {context = "EggInteractionService", eggType = eggType})
    
    -- Validate egg type
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        Logger:Warn("Invalid egg type", {context = "EggInteractionService", eggType = eggType})
        self:ShowErrorMessage("Invalid egg type")
        return
    end
    
    -- Client-side distance check (like working game)
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        Logger:Warn("No character or root part", {context = "EggInteractionService"})
        self:ShowErrorMessage("Character not ready")
        return
    end
    
    -- Find egg in workspace
    local eggInWorkspace = self:FindEggByType(eggType)
    if not eggInWorkspace then
        Logger:Warn("Egg not found in workspace", {context = "EggInteractionService"})
        self:ShowErrorMessage("Egg not found")
        return
    end
    
    -- Check distance using EggSpawnPoint as anchor
    local spawnPointRef = eggInWorkspace:FindFirstChild("SpawnPoint")
    local anchor = spawnPointRef and spawnPointRef.Value
    
    -- Fallback to PrimaryPart or any Part if no SpawnPoint reference
    if not anchor then
        anchor = eggInWorkspace.PrimaryPart or eggInWorkspace:FindFirstChildOfClass("Part")
    end
    
    if not anchor then
        Logger:Warn("No anchor found on egg", {context = "EggInteractionService"})
        self:ShowErrorMessage("Egg configuration error")
        return
    end
    
    local distance = (player.Character.HumanoidRootPart.Position - anchor.Position).Magnitude
    if distance > eggSystemConfig.proximity.max_distance then
        Logger:Info("Too far from egg", {context = "EggInteractionService", distance = distance})
        self:ShowErrorMessage(eggSystemConfig.messages.too_far_away)
        return
    end
    
    Logger:Debug("Distance check passed", {context = "EggInteractionService", distance = distance})
    
    -- Call server using RemoteFunction (like working game)
    local eggRemote = ReplicatedStorage:FindFirstChild("EggOpened")
    if not eggRemote then
        Logger:Error("EggOpened RemoteFunction not found", {context = "EggInteractionService"})
        self:ShowErrorMessage("Server not ready, please restart game")
        return
    end
    
    local success, result, message = pcall(function()
        return eggRemote:InvokeServer(eggType, "Single")
    end)
    
    if success then
        Logger:Info("Server call successful", {context = "EggInteractionService", resultType = typeof(result)})
        if type(result) == "table" and result.success then
            Logger:Info("Purchase successful", {context = "EggInteractionService"})
            self:ShowHatchingResults(result)
        elseif result == "Error" then
            Logger:Warn("Purchase failed", {context = "EggInteractionService", message = message or "Unknown error"})
            self:ShowErrorMessage(message or "Purchase failed")
        elseif type(result) == "table" and result.Pet then
            -- Handle successful result without explicit success flag
            Logger:Info("Purchase successful (legacy format)", {context = "EggInteractionService"})
            self:ShowHatchingResults(result)
        else
            Logger:Warn("Unexpected result format", {context = "EggInteractionService", resultType = typeof(result)})
            self:ShowErrorMessage("Unexpected server response")
        end
    else
        Logger:Error("Server call failed", {context = "EggInteractionService", error = tostring(result)})
        self:ShowErrorMessage("Connection error")
    end
end

function EggInteractionService:FindEggByType(eggType)
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") then
            local objEggType = obj:GetAttribute("EggType")
            local eggInfo = obj:FindFirstChild("EggType")
            if eggInfo then objEggType = eggInfo.Value end
            
            if objEggType == eggType then
                return obj
            end
        end
    end
    return nil
end

-- === UI FEEDBACK ===

function EggInteractionService:ShowErrorMessage(errorMessage)
    -- Create simple error notification
    local errorGui = Instance.new("ScreenGui")
    errorGui.Name = "EggError"
    errorGui.ResetOnSpawn = false
    errorGui.Parent = player.PlayerGui
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 80)
    frame.Position = UDim2.new(0.5, -150, 0.8, -40)
    frame.BackgroundColor3 = Color3.fromRGB(220, 53, 69)
    frame.BorderSizePixel = 0
    frame.Parent = errorGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 1, -10)
    label.Position = UDim2.new(0, 10, 0, 5)
    label.BackgroundTransparency = 1
    label.Text = "❌ " .. errorMessage
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.Parent = frame
    
    -- Slide in animation
    frame.Position = UDim2.new(0.5, -150, 1, 0)
    local tween = TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -150, 0.8, -40)
    })
    tween:Play()
    
    -- Auto-remove after configured time
    task.spawn(function()
        task.wait(eggSystemConfig.cooldowns.ui_error_display_time)
        errorGui:Destroy()
    end)
end

function EggInteractionService:ShowHatchingResults(result)
    -- Reduce console noise: keep egg-related logs through Logger only
    local Logger = self._modules and self._modules.Logger
    if Logger and Logger.Info then
        Logger:Info("Hatched pet", {pet = result.Pet, variant = result.Type, power = result.Power})
    end
    
    -- Use the full egg hatching animation system instead of simple notification
    local success, hatchingService = pcall(function()
        return require(ReplicatedStorage.Shared.Services.EggHatchingService)
    end)
    
    if success and hatchingService then
        -- Prepare egg data for animation
        local eggData = {
            petType = result.Pet,
            variant = result.Type,
            power = result.Power,
            eggType = result.EggType or "basic_egg", -- Add egg type for proper image lookup
            imageId = self:GetEggImageId(result.EggType or "basic_egg"),
            petImageId = self:GetPetImageId(result.Pet, result.Type)
        }
        
        -- Start the hatching animation (uses persistent reusable GUI)
        if Logger and Logger.Info then
            Logger:Info("Starting egg hatching animation", {pet = result.Pet, variant = result.Type})
        end
        local animationResult = hatchingService:StartHatchingAnimation({eggData})
        if Logger and Logger.Info then
            Logger:Info("Hatching animation started (persistent GUI)")
        end
    else
        -- Fallback to simple notification if animation service fails
        warn("Failed to load EggHatchingService, falling back to simple notification")
        self:ShowSimpleHatchingNotification(result)
    end
end

-- Fallback simple notification (moved from original function)
function EggInteractionService:ShowSimpleHatchingNotification(result)
    local successGui = Instance.new("ScreenGui")
    successGui.Name = "HatchingSuccess"
    successGui.ResetOnSpawn = false
    successGui.Parent = player.PlayerGui
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 120)
    frame.Position = UDim2.new(0.5, -200, 0.5, -60)
    frame.BackgroundColor3 = Color3.fromRGB(34, 139, 34)
    frame.BorderSizePixel = 0
    frame.Parent = successGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0.5, 0)
    title.Position = UDim2.new(0, 10, 0, 5)
    title.BackgroundTransparency = 1
    title.Text = "🎉 EGG HATCHED!"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = frame
    
    local details = Instance.new("TextLabel")
    details.Size = UDim2.new(1, -20, 0.5, 0)
    details.Position = UDim2.new(0, 10, 0.5, 0)
    details.BackgroundTransparency = 1
    details.Text = result.Type .. " " .. result.Pet .. " (Power: " .. result.Power .. ")"
    details.TextColor3 = Color3.fromRGB(255, 255, 255)
    details.TextScaled = true
    details.Font = Enum.Font.Gotham
    details.Parent = frame
    
    -- Auto-remove after configured time
    task.spawn(function()
        task.wait(eggSystemConfig.cooldowns.success_notification_time)
        successGui:Destroy()
    end)
end

-- Helper functions to get image IDs for animations
function EggInteractionService:GetEggImageId(eggType)
    -- Try to get egg image from generated assets
    local success, imageId = pcall(function()
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        if assetsFolder then
            local imagesFolder = assetsFolder:FindFirstChild("Images")
            if imagesFolder then
                local eggsFolder = imagesFolder:FindFirstChild("Eggs")
                if eggsFolder then
                    local eggImage = eggsFolder:FindFirstChild(eggType)
                    if eggImage then
                        return "generated_image" -- Special flag for cloned ViewportFrame
                    end
                end
            end
        end
        return "rbxasset://textures/face.png" -- Fallback
    end)
    
    return success and imageId or "rbxasset://textures/face.png"
end

function EggInteractionService:GetPetImageId(petType, variant)
    -- Try to get pet image from generated assets
    local success, imageId = pcall(function()
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        if assetsFolder then
            local imagesFolder = assetsFolder:FindFirstChild("Images")
            if imagesFolder then
                local petsFolder = imagesFolder:FindFirstChild("Pets")
                if petsFolder then
                    local petTypeFolder = petsFolder:FindFirstChild(petType)
                    if petTypeFolder then
                        local petImage = petTypeFolder:FindFirstChild(variant)
                        if petImage then
                            return "generated_image" -- Special flag for cloned ViewportFrame
                        end
                    end
                end
            end
        end
        return "rbxasset://textures/face.png" -- Fallback
    end)
    
    return success and imageId or "rbxasset://textures/face.png"
end

-- === INITIALIZATION ===

function EggInteractionService:Initialize()
    Logger:Info("Initializing with CurrentTarget system", {context = "EggInteractionService"})
    
    -- Get reference to CurrentTargetService
    local success, currentTargetServiceOrError = pcall(function()
        return require(ReplicatedStorage.Shared.Services.EggCurrentTargetService)
    end)
    
    if success then
        currentTargetService = currentTargetServiceOrError
        Logger:Info("Got CurrentTargetService reference", {context = "EggInteractionService"})
    else
        Logger:Error("Failed to get CurrentTargetService", {error = tostring(currentTargetServiceOrError)})
        return
    end
    
    -- Set up E key listening (only when not typing)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == eggSystemConfig.proximity.interaction_key then
                if UserInputService:GetFocusedTextBox() == nil then
                    self:OnEKeyPressed()
                end
            end
        end
    end)
    
    Logger:Info("Initialized with E key listening", {context = "EggInteractionService"})
end

return EggInteractionService