--[[
    GlobalEffectsGUI - Monitors Workspace/GlobalEffects folder structure
    
    Simple, reliable architecture:
    - No network calls - uses native Changed events
    - Automatically updates when global effects change
    - Configuration-driven display using effect values
    - Shows effects that affect all players
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local GlobalEffectsGUI = {}

-- GUI elements
local screenGui = nil
local mainFrame = nil
local titleLabel = nil
local effectsFrame = nil
local noEffectsLabel = nil

-- Track active effect labels
local activeEffectLabels = {}

function GlobalEffectsGUI:Init()
    self:CreateGUI()
    self:MonitorGlobalEffects()
    print("🌟 Global Effects GUI loaded!")
end

function GlobalEffectsGUI:CreateGUI()
    -- Create ScreenGui
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "GlobalEffectsGUI"
    screenGui.Parent = player.PlayerGui
    
    -- Main container frame
    mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 320, 0, 200)
    mainFrame.Position = UDim2.new(1, -330, 0, 150) -- Top right area
    mainFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    -- Add rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame
    
    -- Add border
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(0.3, 0.6, 1.0)
    stroke.Thickness = 2
    stroke.Parent = mainFrame
    
    -- Title label
    titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(1, 0, 0, 35)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "🌟 Global Effects"
    titleLabel.TextColor3 = Color3.new(1, 1, 1)
    titleLabel.TextScaled = true
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Parent = mainFrame
    
    -- Effects container
    effectsFrame = Instance.new("ScrollingFrame")
    effectsFrame.Name = "EffectsFrame"
    effectsFrame.Size = UDim2.new(1, -10, 1, -45)
    effectsFrame.Position = UDim2.new(0, 5, 0, 40)
    effectsFrame.BackgroundTransparency = 1
    effectsFrame.BorderSizePixel = 0
    effectsFrame.ScrollBarThickness = 6
    effectsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    effectsFrame.Parent = mainFrame
    
    -- Layout for effects
    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 5)
    listLayout.Parent = effectsFrame
    
    -- Adjust canvas size when content changes
    listLayout.Changed:Connect(function(property)
        if property == "AbsoluteContentSize" then
            effectsFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
        end
    end)
    
    -- No effects placeholder
    noEffectsLabel = Instance.new("TextLabel")
    noEffectsLabel.Name = "NoEffectsLabel"
    noEffectsLabel.Size = UDim2.new(1, 0, 1, 0)
    noEffectsLabel.Position = UDim2.new(0, 0, 0, 0)
    noEffectsLabel.BackgroundTransparency = 1
    noEffectsLabel.Text = "No global effects active"
    noEffectsLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    noEffectsLabel.TextScaled = true
    noEffectsLabel.Font = Enum.Font.Gotham
    noEffectsLabel.Visible = true
    noEffectsLabel.Parent = effectsFrame
end

function GlobalEffectsGUI:MonitorGlobalEffects()
    -- Wait for GlobalEffects folder to exist
    local function waitForGlobalEffects()
        local globalEffects = Workspace:FindFirstChild("GlobalEffects")
        if globalEffects then
            return globalEffects
        end
        
        -- Wait for it to be created
        local connection
        connection = Workspace.ChildAdded:Connect(function(child)
            if child.Name == "GlobalEffects" then
                connection:Disconnect()
            end
        end)
        
        return Workspace:WaitForChild("GlobalEffects", 30) -- 30 second timeout
    end
    
    local globalEffects = waitForGlobalEffects()
    if not globalEffects then
        print("❌ GlobalEffects folder not found after 30 seconds")
        return
    end
    
    print("📁 Monitoring GlobalEffects folder")
    
    -- Monitor existing effects
    for _, effectFolder in ipairs(globalEffects:GetChildren()) do
        if effectFolder:IsA("Folder") then
            self:AddEffectDisplay(effectFolder)
        end
    end
    
    -- Monitor new effects being added
    globalEffects.ChildAdded:Connect(function(child)
        if child:IsA("Folder") then
            print("➕ Global effect added:", child.Name)
            self:AddEffectDisplay(child)
        end
    end)
    
    -- Monitor effects being removed
    globalEffects.ChildRemoved:Connect(function(child)
        if child:IsA("Folder") then
            print("➖ Global effect removed:", child.Name)
            self:RemoveEffectDisplay(child.Name)
        end
    end)
    
    -- Update visibility
    self:UpdateVisibility()
end

function GlobalEffectsGUI:AddEffectDisplay(effectFolder)
    local effectId = effectFolder.Name
    
    -- Don't add duplicates
    if activeEffectLabels[effectId] then
        return
    end
    
    -- Create effect display frame
    local effectFrame = Instance.new("Frame")
    effectFrame.Name = effectId .. "Frame"
    effectFrame.Size = UDim2.new(1, 0, 0, 50)
    effectFrame.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    effectFrame.BackgroundTransparency = 0.2
    effectFrame.BorderSizePixel = 0
    effectFrame.Parent = effectsFrame
    
    -- Rounded corners for effect frame
    local effectCorner = Instance.new("UICorner")
    effectCorner.CornerRadius = UDim.new(0, 8)
    effectCorner.Parent = effectFrame
    
    -- Effect border
    local effectStroke = Instance.new("UIStroke")
    effectStroke.Color = Color3.new(0.4, 0.8, 0.4)
    effectStroke.Thickness = 1
    effectStroke.Parent = effectFrame
    
    -- Effect text label
    local effectLabel = Instance.new("TextLabel")
    effectLabel.Name = "EffectLabel"
    effectLabel.Size = UDim2.new(1, -10, 1, 0)
    effectLabel.Position = UDim2.new(0, 5, 0, 0)
    effectLabel.BackgroundTransparency = 1
    effectLabel.TextColor3 = Color3.new(1, 1, 1)
    effectLabel.TextScaled = true
    effectLabel.Font = Enum.Font.Gotham
    effectLabel.TextXAlignment = Enum.TextXAlignment.Left
    effectLabel.Parent = effectFrame
    
    -- Store reference
    activeEffectLabels[effectId] = {
        frame = effectFrame,
        label = effectLabel,
        folder = effectFolder
    }
    
    -- Monitor value changes in this effect
    self:MonitorEffectValues(effectFolder, effectLabel)
    
    -- Initial update
    self:UpdateEffectDisplay(effectFolder, effectLabel)
    
    -- Update visibility
    self:UpdateVisibility()
end

function GlobalEffectsGUI:RemoveEffectDisplay(effectId)
    local effectData = activeEffectLabels[effectId]
    if effectData then
        effectData.frame:Destroy()
        activeEffectLabels[effectId] = nil
        
        -- Update visibility
        self:UpdateVisibility()
    end
end

function GlobalEffectsGUI:MonitorEffectValues(effectFolder, effectLabel)
    -- Monitor all value changes in the effect folder
    local function onValueChanged()
        self:UpdateEffectDisplay(effectFolder, effectLabel)
    end
    
    -- Connect to existing values
    for _, child in ipairs(effectFolder:GetChildren()) do
        if child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue") then
            child.Changed:Connect(onValueChanged)
        end
    end
    
    -- Connect to new values being added
    effectFolder.ChildAdded:Connect(function(child)
        if child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue") then
            child.Changed:Connect(onValueChanged)
            onValueChanged() -- Update immediately
        end
    end)
end

function GlobalEffectsGUI:UpdateEffectDisplay(effectFolder, effectLabel)
    -- Get effect values
    local displayName = effectFolder:FindFirstChild("displayName")
    local icon = effectFolder:FindFirstChild("icon")
    local description = effectFolder:FindFirstChild("description")
    local timeRemaining = effectFolder:FindFirstChild("timeRemaining")
    local reason = effectFolder:FindFirstChild("reason")
    
    -- Format display text
    local nameText = (displayName and displayName.Value) or effectFolder.Name
    local iconText = (icon and icon.Value) or "🌟"
    local descText = (description and description.Value) or "Global effect active"
    local reasonText = (reason and reason.Value) or "Server event"
    
    local timeText = ""
    if timeRemaining then
        if timeRemaining.Value == -1 then
            timeText = "Permanent"
        else
            local minutes = math.floor(timeRemaining.Value / 60)
            local seconds = timeRemaining.Value % 60
            if minutes > 0 then
                timeText = string.format("%dm %ds", minutes, seconds)
            else
                timeText = string.format("%ds", seconds)
            end
        end
    end
    
    -- Update label
    local displayText = string.format("%s %s\n%s • %s", iconText, nameText, timeText, reasonText)
    effectLabel.Text = displayText
end

function GlobalEffectsGUI:UpdateVisibility()
    local hasEffects = next(activeEffectLabels) ~= nil
    noEffectsLabel.Visible = not hasEffects
    
    -- Adjust main frame size based on content
    local contentHeight = 45 -- Title height
    if hasEffects then
        local layout = effectsFrame:FindFirstChild("UIListLayout")
        if layout then
            contentHeight = contentHeight + math.min(layout.AbsoluteContentSize.Y + 10, 300) -- Max height 300
        end
    else
        contentHeight = contentHeight + 60 -- Space for "no effects" message
    end
    
    -- Tween to new size
    local targetSize = UDim2.new(0, 320, 0, contentHeight)
    local tween = TweenService:Create(mainFrame, TweenInfo.new(0.3), {Size = targetSize})
    tween:Play()
end

-- Initialize the GUI
GlobalEffectsGUI:Init()

return GlobalEffectsGUI 