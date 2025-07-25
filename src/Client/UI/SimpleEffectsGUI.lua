--[[
    SimpleEffectsGUI - Monitors Player/TimedBoosts folder structure
    
    Simple, reliable architecture:
    - No network calls - uses native Changed events
    - Automatically updates when folder values change
    - Configuration-driven display using effect values
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SimpleEffectsGUI = {}

-- GUI elements
local gui = nil
local mainFrame = nil
local effectsFrame = nil
local noEffectsLabel = nil

-- Connection cleanup
local connections = {}

function SimpleEffectsGUI:Init()
    self:CreateGUI()
    self:SetupPlayerMonitoring()
    
    print("⚡ Simple Effects GUI loaded!")
end

function SimpleEffectsGUI:CreateGUI()
    -- Main ScreenGui
    gui = Instance.new("ScreenGui")
    gui.Name = "SimpleEffectsGUI"
    gui.Parent = playerGui
    
    -- Main frame (top-right corner)
    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 300, 0, 200)
    mainFrame.Position = UDim2.new(1, -320, 0, 20)
    mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    mainFrame.BackgroundTransparency = 0.3
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = gui
    
    -- Corner rounding
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = mainFrame
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "⚡ Active Effects"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame
    
    -- Effects container
    effectsFrame = Instance.new("ScrollingFrame")
    effectsFrame.Size = UDim2.new(1, -10, 1, -40)
    effectsFrame.Position = UDim2.new(0, 5, 0, 35)
    effectsFrame.BackgroundTransparency = 1
    effectsFrame.BorderSizePixel = 0
    effectsFrame.ScrollBarThickness = 4
    effectsFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
    effectsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    effectsFrame.Parent = mainFrame
    
    -- List layout
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 5)
    layout.Parent = effectsFrame
    
    -- No effects label
    noEffectsLabel = Instance.new("TextLabel")
    noEffectsLabel.Size = UDim2.new(1, 0, 1, 0)
    noEffectsLabel.BackgroundTransparency = 1
    noEffectsLabel.Text = "No active effects"
    noEffectsLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    noEffectsLabel.TextScaled = true
    noEffectsLabel.Font = Enum.Font.Gotham
    noEffectsLabel.Parent = effectsFrame
end

function SimpleEffectsGUI:SetupPlayerMonitoring()
    -- Wait for player to be fully loaded
    if player.Character then
        self:MonitorTimedBoosts()
    end
    
    player.CharacterAdded:Connect(function()
        wait(1) -- Wait for server to set up folders
        self:MonitorTimedBoosts()
    end)
end

function SimpleEffectsGUI:MonitorTimedBoosts()
    -- Clean up existing connections
    for _, connection in pairs(connections) do
        connection:Disconnect()
    end
    connections = {}
    
    -- Monitor TimedBoosts folder
    local function setupTimedBoostsMonitoring()
        local timedBoosts = player:FindFirstChild("TimedBoosts")
        if timedBoosts then
            -- Monitor when effects are added/removed
            table.insert(connections, timedBoosts.ChildAdded:Connect(function(child)
                if child:IsA("Folder") then
                    self:OnEffectAdded(child)
                end
            end))
            
            table.insert(connections, timedBoosts.ChildRemoved:Connect(function(child)
                if child:IsA("Folder") then
                    self:OnEffectRemoved(child)
                end
            end))
            
            -- Monitor existing effects
            for _, effectFolder in ipairs(timedBoosts:GetChildren()) do
                if effectFolder:IsA("Folder") then
                    self:OnEffectAdded(effectFolder)
                end
            end
            
            print("📁 Monitoring TimedBoosts folder")
        else
            -- Wait for TimedBoosts folder to be created
            table.insert(connections, player.ChildAdded:Connect(function(child)
                if child.Name == "TimedBoosts" then
                    wait(0.1) -- Small delay for folder to populate
                    setupTimedBoostsMonitoring()
                end
            end))
        end
    end
    
    setupTimedBoostsMonitoring()
    self:UpdateEffectsDisplay()
end

function SimpleEffectsGUI:OnEffectAdded(effectFolder)
    print("➕ Effect added:", effectFolder.Name)
    
    -- Monitor timeRemaining changes for real-time countdown
    local timeRemaining = effectFolder:FindFirstChild("timeRemaining")
    if timeRemaining then
        table.insert(connections, timeRemaining.Changed:Connect(function()
            self:UpdateEffectDisplay(effectFolder)
        end))
    end
    
    self:UpdateEffectsDisplay()
end

function SimpleEffectsGUI:OnEffectRemoved(effectFolder)
    print("➖ Effect removed:", effectFolder.Name)
    
    -- Remove GUI element
    local effectGui = effectsFrame:FindFirstChild(effectFolder.Name)
    if effectGui then
        effectGui:Destroy()
    end
    
    self:UpdateEffectsDisplay()
end

function SimpleEffectsGUI:UpdateEffectsDisplay()
    local timedBoosts = player:FindFirstChild("TimedBoosts")
    local hasEffects = false
    
    if timedBoosts then
        -- Clear existing effect GUIs
        for _, child in ipairs(effectsFrame:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        
        -- Create GUI for each effect
        for _, effectFolder in ipairs(timedBoosts:GetChildren()) do
            if effectFolder:IsA("Folder") then
                self:CreateEffectGUI(effectFolder)
                hasEffects = true
            end
        end
    end
    
    -- Show/hide "no effects" label
    noEffectsLabel.Visible = not hasEffects
    
    -- Update canvas size
    local layout = effectsFrame:FindFirstChild("UIListLayout")
    if layout then
        effectsFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
    end
end

function SimpleEffectsGUI:CreateEffectGUI(effectFolder)
    local effectFrame = Instance.new("Frame")
    effectFrame.Name = effectFolder.Name
    effectFrame.Size = UDim2.new(1, 0, 0, 60)
    effectFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    effectFrame.BorderSizePixel = 0
    effectFrame.Parent = effectsFrame
    
    -- Corner rounding
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = effectFrame
    
    -- Get effect values
    local displayName = effectFolder:FindFirstChild("displayName")
    local description = effectFolder:FindFirstChild("description")
    local icon = effectFolder:FindFirstChild("icon")
    local timeRemaining = effectFolder:FindFirstChild("timeRemaining")
    local multiplier = effectFolder:FindFirstChild("multiplier")
    
    -- Icon
    local iconLabel = Instance.new("TextLabel")
    iconLabel.Size = UDim2.new(0, 40, 0, 40)
    iconLabel.Position = UDim2.new(0, 10, 0, 10)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Text = (icon and icon.Value) or "✨"
    iconLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    iconLabel.TextScaled = true
    iconLabel.Font = Enum.Font.Gotham
    iconLabel.Parent = effectFrame
    
    -- Name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -120, 0, 20)
    nameLabel.Position = UDim2.new(0, 55, 0, 5)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = (displayName and displayName.Value) or effectFolder.Name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Parent = effectFrame
    
    -- Description
    local descLabel = Instance.new("TextLabel")
    descLabel.Size = UDim2.new(1, -120, 0, 15)
    descLabel.Position = UDim2.new(0, 55, 0, 25)
    descLabel.BackgroundTransparency = 1
    descLabel.Text = (description and description.Value) or "Effect active"
    descLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    descLabel.TextScaled = true
    descLabel.Font = Enum.Font.Gotham
    descLabel.TextXAlignment = Enum.TextXAlignment.Left
    descLabel.Parent = effectFrame
    
    -- Timer
    local timerLabel = Instance.new("TextLabel")
    timerLabel.Size = UDim2.new(0, 60, 0, 30)
    timerLabel.Position = UDim2.new(1, -70, 0, 15)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    timerLabel.TextScaled = true
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.Parent = effectFrame
    
    -- Update timer display
    self:UpdateEffectDisplay(effectFolder)
end

function SimpleEffectsGUI:UpdateEffectDisplay(effectFolder)
    local effectFrame = effectsFrame:FindFirstChild(effectFolder.Name)
    if not effectFrame then return end
    
    local timerLabel = effectFrame:FindFirstChild("TextLabel") -- Find timer label
    if not timerLabel then return end
    
    -- Find the actual timer label (last TextLabel)
    for _, child in ipairs(effectFrame:GetChildren()) do
        if child:IsA("TextLabel") and child.Position.X.Scale > 0.8 then
            timerLabel = child
            break
        end
    end
    
    local timeRemaining = effectFolder:FindFirstChild("timeRemaining")
    if timeRemaining then
        if timeRemaining.Value == -1 then
            timerLabel.Text = "∞"
            timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
        elseif timeRemaining.Value > 0 then
            local minutes = math.floor(timeRemaining.Value / 60)
            local seconds = timeRemaining.Value % 60
            timerLabel.Text = string.format("%d:%02d", minutes, seconds)
            timerLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        else
            timerLabel.Text = "0:00"
            timerLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        end
    end
end

-- Global access
_G.SimpleEffectsGUI = SimpleEffectsGUI

-- Auto-initialize
SimpleEffectsGUI:Init()

return SimpleEffectsGUI 