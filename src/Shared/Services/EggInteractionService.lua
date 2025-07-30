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
local petConfig = require(ReplicatedStorage.Configs.pets)

-- Local player reference
local player = Players.LocalPlayer

-- Current target service reference
local currentTargetService = nil

-- Logger setup using singleton pattern
local Logger
local loggerSuccess, loggerResult = pcall(function()
    return require(ReplicatedStorage.Shared.Utils.Logger)
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
        print("❌ CurrentTargetService not available")
        return
    end
    
    local currentTarget = currentTargetService:GetCurrentTarget()
    if currentTarget == "None" or not currentTarget then
        print("No egg currently targeted")
        return
    end
    
    print("E key pressed - attempting to purchase:", currentTarget)
    self:HandleEggPurchase(currentTarget)
end

-- === EGG PURCHASE HANDLING ===

function EggInteractionService:HandleEggPurchase(eggType)
    print("Requesting egg purchase:", eggType)
    
    -- Validate egg type
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        print("❌ Invalid egg type:", eggType)
        self:ShowErrorMessage("Invalid egg type")
        return
    end
    
    -- Client-side distance check (like working game)
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        print("❌ No character or root part")
        self:ShowErrorMessage("Character not ready")
        return
    end
    
    -- Find egg in workspace
    local eggInWorkspace = self:FindEggByType(eggType)
    if not eggInWorkspace then
        print("❌ Egg not found in workspace")
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
        print("❌ No anchor found on egg")
        self:ShowErrorMessage("Egg configuration error")
        return
    end
    
    local distance = (player.Character.HumanoidRootPart.Position - anchor.Position).Magnitude
    if distance > 10 then
        print("❌ Too far from egg:", distance)
        self:ShowErrorMessage("You must be closer to the egg")
        return
    end
    
    print("✅ Distance check passed:", distance)
    
    -- Call server using RemoteFunction (like working game)
    local eggRemote = ReplicatedStorage:FindFirstChild("EggOpened")
    if not eggRemote then
        print("❌ EggOpened RemoteFunction not found")
        self:ShowErrorMessage("Server not ready, please restart game")
        return
    end
    
    local success, result, message = pcall(function()
        return eggRemote:InvokeServer(eggType, "Single")
    end)
    
    if success then
        print("Server call successful - Result:", result, "Message:", message)
        if type(result) == "table" and result.success then
            print("✅ Purchase successful!")
            self:ShowHatchingResults(result)
        elseif result == "Error" then
            print("❌ Purchase failed:", message or "Unknown error")
            self:ShowErrorMessage(message or "Purchase failed")
        elseif type(result) == "table" and result.Pet then
            -- Handle successful result without explicit success flag
            print("✅ Purchase successful (legacy format)!")
            self:ShowHatchingResults(result)
        else
            print("❌ Unexpected result format:", type(result), result)
            self:ShowErrorMessage("Unexpected server response")
        end
    else
        print("❌ Server call failed:", result)
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
    
    -- Auto-remove after 3 seconds
    task.spawn(function()
        task.wait(3)
        errorGui:Destroy()
    end)
end

function EggInteractionService:ShowHatchingResults(result)
    print("🎉 You hatched a", result.Type, result.Pet, "with", result.Power, "power!")
    
    -- Create simple success notification
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
    
    -- Auto-remove after 5 seconds
    task.spawn(function()
        task.wait(5)
        successGui:Destroy()
    end)
end

-- === INITIALIZATION ===

function EggInteractionService:Initialize()
    print("EggInteractionService: Initializing with CurrentTarget system...")
    
    -- Get reference to CurrentTargetService
    local success, currentTargetServiceOrError = pcall(function()
        return require(ReplicatedStorage.Shared.Services.EggCurrentTargetService)
    end)
    
    if success then
        currentTargetService = currentTargetServiceOrError
        print("EggInteractionService: Got CurrentTargetService reference")
    else
        Logger:Error("Failed to get CurrentTargetService", {error = tostring(currentTargetServiceOrError)})
        return
    end
    
    -- Set up E key listening (only when not typing)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == Enum.KeyCode.E then
                if UserInputService:GetFocusedTextBox() == nil then
                    self:OnEKeyPressed()
                end
            end
        end
    end)
    
    print("EggInteractionService: Initialized with E key listening")
end

return EggInteractionService