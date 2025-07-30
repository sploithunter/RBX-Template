--[[
    SettingsPanel - Game Settings and Configuration
    
    Features:
    - Audio settings (master volume, effects, music)
    - Graphics settings (quality, performance mode)
    - UI settings (scale, theme preference)
    - Admin panel access (for authorized users)
    - Player preferences and accessibility options
    
    Usage:
    local SettingsPanel = require(script.SettingsPanel)
    local settings = SettingsPanel.new()
    MenuManager:RegisterPanel("Settings", settings)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

-- Get shared modules
local Locations = require(ReplicatedStorage.Shared.Locations)

-- Load Logger with wrapper (following the established pattern)
local LoggerWrapper
local loggerSuccess, loggerResult = pcall(function()
    return require(ReplicatedStorage.Shared.Utils.Logger)
end)

if loggerSuccess and loggerResult then
    LoggerWrapper = {
        new = function(name)
            return {
                info = function(self, ...) loggerResult:Info("[" .. name .. "] " .. tostring((...)), {context = name}) end,
                warn = function(self, ...) loggerResult:Warn("[" .. name .. "] " .. tostring((...)), {context = name}) end,
                error = function(self, ...) loggerResult:Error("[" .. name .. "] " .. tostring((...)), {context = name}) end,
                debug = function(self, ...) loggerResult:Debug("[" .. name .. "] " .. tostring((...)), {context = name}) end,
            }
        end
    }
else
    LoggerWrapper = {
        new = function(name)
            return {
                info = function(self, ...) print("[" .. name .. "] INFO:", ...) end,
                warn = function(self, ...) warn("[" .. name .. "] WARN:", ...) end,
                error = function(self, ...) warn("[" .. name .. "] ERROR:", ...) end,
                debug = function(self, ...) print("[" .. name .. "] DEBUG:", ...) end,
            }
        end
    }
end

-- Load TemplateManager
local TemplateManager
local templateSuccess, templateResult = pcall(function()
    return require(Locations.TemplateManager)
end)
if templateSuccess and templateResult then
    TemplateManager = templateResult
else
    TemplateManager = {
        new = function() 
            return {
                CreatePanel = function() return nil end,
                CreateFromTemplate = function() return nil end
            } 
        end 
    }
end

-- Load UI config
local uiConfig
local configSuccess, configResult = pcall(function()
    return Locations.getConfig("ui")
end)
if configSuccess and configResult then
    uiConfig = configResult
else
    uiConfig = {
        themes = { dark = { primary = { surface = Color3.fromRGB(40, 40, 45) }, text = { primary = Color3.fromRGB(255, 255, 255) } } },
        active_theme = "dark",
        helpers = { get_theme = function(config) return config.themes.dark end }
    }
end

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel

-- Admin user list (in a real game, this would come from a secure server)
local ADMIN_USERS = {
    ["coloradoplays"] = true,
    -- Add more admin usernames here
}

function SettingsPanel.new()
    local self = setmetatable({}, SettingsPanel)
    
    self.logger = LoggerWrapper.new("SettingsPanel")
    self.templateManager = TemplateManager.new()
    
    -- Panel state
    self.isVisible = false
    self.frame = nil
    
    -- Settings state
    self.settings = {
        audio = {
            masterVolume = 0.8,
            effectsVolume = 0.7,
            musicVolume = 0.6,
            uiSoundsEnabled = true
        },
        graphics = {
            quality = "medium", -- low, medium, high
            performanceMode = false,
            reducedMotion = false
        },
        ui = {
            scale = 1.0,
            theme = "dark", -- dark, light
            showTooltips = true,
            compactMode = false
        },
        accessibility = {
            highContrast = false,
            largeText = false,
            keyboardNavigation = true
        }
    }
    
    -- Check if user is admin
    self.isAdmin = ADMIN_USERS[Players.LocalPlayer.Name] == true
    
    return self
end

function SettingsPanel:Show(parent)
    if self.isVisible then return end
    
    self:_createUI(parent)
    self:_loadSettings()
    
    self.isVisible = true
    self.logger:info("Settings panel shown")
end

function SettingsPanel:Hide()
    if not self.isVisible then return end
    
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    
    self.isVisible = false
    self.logger:info("Settings panel hidden")
end

function SettingsPanel:_createUI(parent)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Create main panel using template
    self.frame = self.templateManager:CreatePanel("panel_scroll", {
        size = UDim2.new(0.7, 0, 0.85, 0),
        position = UDim2.new(0.5, 0, 0.5, 0),
        anchor_point = Vector2.new(0.5, 0.5),
        parent = parent
    })
    
    if not self.frame then
        -- Fallback frame creation
        self.frame = Instance.new("Frame")
        self.frame.Size = UDim2.new(0.7, 0, 0.85, 0)
        self.frame.Position = UDim2.new(0.5, 0, 0.5, 0)
        self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
        self.frame.BackgroundColor3 = theme.primary.surface
        self.frame.BorderSizePixel = 0
        self.frame.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 16)
        corner.Parent = self.frame
    end
    
    self.frame.Name = "SettingsPanel"
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 50)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "⚙️ Settings" .. (self.isAdmin and " (Admin)" or "")
    titleLabel.TextColor3 = theme.text.primary
    titleLabel.TextSize = 24
    titleLabel.Font = uiConfig.fonts and uiConfig.fonts.primary or Enum.Font.Gotham
    titleLabel.TextXAlignment = Enum.TextXAlignment.Center
    titleLabel.Parent = self.frame
    
    -- Close button
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 40, 0, 40)
    closeButton.Position = UDim2.new(1, -50, 0, 10)
    closeButton.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    closeButton.BorderSizePixel = 0
    closeButton.Text = "✕"
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextSize = 20
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Parent = self.frame
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 8)
    closeCorner.Parent = closeButton
    
    closeButton.Activated:Connect(function()
        self:Hide()
    end)
    
    -- Scroll frame for settings
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "SettingsScroll"
    scrollFrame.Size = UDim2.new(1, -20, 1, -70)
    scrollFrame.Position = UDim2.new(0, 10, 0, 60)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 8
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = self.frame
    
    -- Layout for settings
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 15)
    layout.Parent = scrollFrame
    
    -- Update canvas size when layout changes
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
    end)
    
    self.scrollFrame = scrollFrame
    
    -- Create settings sections
    self:_createAudioSettings()
    self:_createGraphicsSettings()
    self:_createUISettings()
    
    -- Admin section (only for admin users)
    if self.isAdmin then
        self:_createAdminSettings()
    end
end

function SettingsPanel:_createSectionHeader(title, layoutOrder)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    local header = Instance.new("Frame")
    header.Name = title .. "Header"
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = theme.primary.accent or Color3.fromRGB(0, 120, 180)
    header.BorderSizePixel = 0
    header.LayoutOrder = layoutOrder
    header.Parent = self.scrollFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = header
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 16
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = header
end

function SettingsPanel:_createSliderSetting(name, currentValue, minValue, maxValue, layoutOrder, callback)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    local settingFrame = Instance.new("Frame")
    settingFrame.Name = name .. "Setting"
    settingFrame.Size = UDim2.new(1, 0, 0, 50)
    settingFrame.BackgroundColor3 = theme.primary.card or Color3.fromRGB(50, 50, 55)
    settingFrame.BorderSizePixel = 0
    settingFrame.LayoutOrder = layoutOrder
    settingFrame.Parent = self.scrollFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = settingFrame
    
    -- Label
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.4, 0, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = theme.text.primary
    label.TextSize = 14
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = settingFrame
    
    -- Slider background
    local sliderBG = Instance.new("Frame")
    sliderBG.Size = UDim2.new(0.35, 0, 0, 8)
    sliderBG.Position = UDim2.new(0.45, 0, 0.5, -4)
    sliderBG.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    sliderBG.BorderSizePixel = 0
    sliderBG.Parent = settingFrame
    
    local sliderCorner = Instance.new("UICorner")
    sliderCorner.CornerRadius = UDim.new(0, 4)
    sliderCorner.Parent = sliderBG
    
    -- Slider fill
    local sliderFill = Instance.new("Frame")
    local fillPercent = (currentValue - minValue) / (maxValue - minValue)
    sliderFill.Size = UDim2.new(fillPercent, 0, 1, 0)
    sliderFill.Position = UDim2.new(0, 0, 0, 0)
    sliderFill.BackgroundColor3 = theme.primary.accent or Color3.fromRGB(0, 120, 180)
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderBG
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = sliderFill
    
    -- Value label
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0.15, 0, 1, 0)
    valueLabel.Position = UDim2.new(0.85, 0, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = tostring(math.floor(currentValue * 100)) .. "%"
    valueLabel.TextColor3 = theme.text.secondary or Color3.fromRGB(200, 200, 200)
    valueLabel.TextSize = 12
    valueLabel.Font = Enum.Font.Gotham
    valueLabel.TextXAlignment = Enum.TextXAlignment.Center
    valueLabel.Parent = settingFrame
    
    -- Click handling for slider
    local function updateSlider(input)
        local percent = math.clamp((input.Position.X - sliderBG.AbsolutePosition.X) / sliderBG.AbsoluteSize.X, 0, 1)
        local newValue = minValue + (maxValue - minValue) * percent
        
        sliderFill.Size = UDim2.new(percent, 0, 1, 0)
        valueLabel.Text = tostring(math.floor(newValue * 100)) .. "%"
        
        if callback then
            callback(newValue)
        end
    end
    
    sliderBG.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            updateSlider(input)
        end
    end)
end

function SettingsPanel:_createToggleSetting(name, currentValue, layoutOrder, callback)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    local settingFrame = Instance.new("Frame")
    settingFrame.Name = name .. "Setting"
    settingFrame.Size = UDim2.new(1, 0, 0, 40)
    settingFrame.BackgroundColor3 = theme.primary.card or Color3.fromRGB(50, 50, 55)
    settingFrame.BorderSizePixel = 0
    settingFrame.LayoutOrder = layoutOrder
    settingFrame.Parent = self.scrollFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = settingFrame
    
    -- Label
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = theme.text.primary
    label.TextSize = 14
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = settingFrame
    
    -- Toggle button
    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(0, 60, 0, 25)
    toggleButton.Position = UDim2.new(1, -75, 0.5, -12.5)
    toggleButton.BackgroundColor3 = currentValue and Color3.fromRGB(0, 180, 0) or Color3.fromRGB(120, 120, 120)
    toggleButton.BorderSizePixel = 0
    toggleButton.Text = currentValue and "ON" or "OFF"
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.TextSize = 12
    toggleButton.Font = Enum.Font.GothamBold
    toggleButton.Parent = settingFrame
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 12)
    toggleCorner.Parent = toggleButton
    
    toggleButton.Activated:Connect(function()
        currentValue = not currentValue
        toggleButton.BackgroundColor3 = currentValue and Color3.fromRGB(0, 180, 0) or Color3.fromRGB(120, 120, 120)
        toggleButton.Text = currentValue and "ON" or "OFF"
        
        if callback then
            callback(currentValue)
        end
    end)
end

function SettingsPanel:_createButtonSetting(name, buttonText, layoutOrder, callback)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    local settingFrame = Instance.new("Frame")
    settingFrame.Name = name .. "Setting"
    settingFrame.Size = UDim2.new(1, 0, 0, 40)
    settingFrame.BackgroundColor3 = theme.primary.card or Color3.fromRGB(50, 50, 55)
    settingFrame.BorderSizePixel = 0
    settingFrame.LayoutOrder = layoutOrder
    settingFrame.Parent = self.scrollFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = settingFrame
    
    -- Label
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, 0, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = theme.text.primary
    label.TextSize = 14
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = settingFrame
    
    -- Action button
    local actionButton = Instance.new("TextButton")
    actionButton.Size = UDim2.new(0, 120, 0, 25)
    actionButton.Position = UDim2.new(1, -135, 0.5, -12.5)
    actionButton.BackgroundColor3 = theme.button and theme.button.primary or Color3.fromRGB(0, 120, 180)
    actionButton.BorderSizePixel = 0
    actionButton.Text = buttonText
    actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    actionButton.TextSize = 12
    actionButton.Font = Enum.Font.Gotham
    actionButton.Parent = settingFrame
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 6)
    buttonCorner.Parent = actionButton
    
    actionButton.Activated:Connect(function()
        if callback then
            callback()
        end
    end)
end

function SettingsPanel:_createAudioSettings()
    self:_createSectionHeader("🔊 Audio Settings", 1)
    
    self:_createSliderSetting("Master Volume", self.settings.audio.masterVolume, 0, 1, 2, function(value)
        self.settings.audio.masterVolume = value
        SoundService.MasterVolume = value
    end)
    
    self:_createSliderSetting("Effects Volume", self.settings.audio.effectsVolume, 0, 1, 3, function(value)
        self.settings.audio.effectsVolume = value
        -- Apply to effects volume group
    end)
    
    self:_createSliderSetting("Music Volume", self.settings.audio.musicVolume, 0, 1, 4, function(value)
        self.settings.audio.musicVolume = value
        -- Apply to music volume group
    end)
    
    self:_createToggleSetting("UI Sounds", self.settings.audio.uiSoundsEnabled, 5, function(value)
        self.settings.audio.uiSoundsEnabled = value
    end)
end

function SettingsPanel:_createGraphicsSettings()
    self:_createSectionHeader("🎨 Graphics Settings", 6)
    
    self:_createToggleSetting("Performance Mode", self.settings.graphics.performanceMode, 7, function(value)
        self.settings.graphics.performanceMode = value
        -- Apply performance optimizations
    end)
    
    self:_createToggleSetting("Reduced Motion", self.settings.graphics.reducedMotion, 8, function(value)
        self.settings.graphics.reducedMotion = value
        -- Disable/reduce animations
    end)
end

function SettingsPanel:_createUISettings()
    self:_createSectionHeader("📱 UI Settings", 9)
    
    self:_createSliderSetting("UI Scale", self.settings.ui.scale, 0.8, 1.2, 10, function(value)
        self.settings.ui.scale = value
        -- Apply UI scaling
    end)
    
    self:_createToggleSetting("Show Tooltips", self.settings.ui.showTooltips, 11, function(value)
        self.settings.ui.showTooltips = value
    end)
    
    self:_createToggleSetting("Compact Mode", self.settings.ui.compactMode, 12, function(value)
        self.settings.ui.compactMode = value
    end)
end

function SettingsPanel:_createAdminSettings()
    self:_createSectionHeader("🛠️ Admin Tools", 13)
    
    self:_createButtonSetting("Test Menu Access", "Open Admin Panel", 14, function()
        self:_openAdminPanel()
    end)
    
    self:_createButtonSetting("Debug Mode", "Toggle Debug UI", 15, function()
        -- Toggle debug overlays
        self.logger:info("Debug mode toggled")
    end)
    
    self:_createButtonSetting("Performance Monitor", "Show Stats", 16, function()
        -- Show performance statistics
        self.logger:info("Performance monitor toggled")
    end)
end

function SettingsPanel:_openAdminPanel()
    self.logger:info("Opening admin panel")
    
    -- Create admin panel (this would open your test menu system)
    -- For now, we'll emit an event that MenuManager can listen to
    if self.onAdminPanelRequested then
        self.onAdminPanelRequested()
    end
end

function SettingsPanel:_loadSettings()
    -- Load settings from player data or local storage
    -- For now, using defaults
    self.logger:info("Settings loaded")
end

function SettingsPanel:_saveSettings()
    -- Save settings to player data or local storage
    self.logger:info("Settings saved")
end

-- Set callback for admin panel requests
function SettingsPanel:SetAdminPanelCallback(callback)
    self.onAdminPanelRequested = callback
end

-- Public interface methods
function SettingsPanel:IsVisible()
    return self.isVisible
end

function SettingsPanel:GetFrame()
    return self.frame
end

function SettingsPanel:IsAdmin()
    return self.isAdmin
end

function SettingsPanel:Destroy()
    self:_saveSettings()
    self:Hide()
    self.logger:info("Settings panel destroyed")
end

return SettingsPanel 