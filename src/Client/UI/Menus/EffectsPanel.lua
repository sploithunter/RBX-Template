--[[
    EffectsPanel - Player and Global Effects Management
    
    Features:
    - Display active player effects with timers
    - Show global effects affecting all players
    - Effect activation/deactivation controls
    - Visual effect indicators and progress bars
    - Integration with PlayerEffectsService
    
    Usage:
    local EffectsPanel = require(script.EffectsPanel)
    local effects = EffectsPanel.new()
    MenuManager:RegisterPanel("Effects", effects)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Get shared modules
local Locations = require(ReplicatedStorage.Shared.Locations)

-- Load Logger with wrapper (following the established pattern)
local LoggerWrapper
local loggerSuccess, loggerResult = pcall(function()
    return require(Locations.Logger)
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
    -- Fallback TemplateManager
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

local EffectsPanel = {}
EffectsPanel.__index = EffectsPanel

function EffectsPanel.new()
    local self = setmetatable({}, EffectsPanel)
    
    self.logger = LoggerWrapper.new("EffectsPanel")
    self.templateManager = TemplateManager.new()
    
    -- Panel state
    self.isVisible = false
    self.frame = nil
    self.effectsData = {
        playerEffects = {},
        globalEffects = {}
    }
    
    self.effectDisplays = {}
    
    return self
end

function EffectsPanel:Show(parent)
    if self.isVisible then return end
    
    self:_createUI(parent)
    self:_loadEffectsData()
    
    self.isVisible = true
    self.logger:info("Effects panel shown")
end

function EffectsPanel:Hide()
    if not self.isVisible then return end
    
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    
    self.isVisible = false
    self.logger:info("Effects panel hidden")
end

function EffectsPanel:_createUI(parent)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Create main panel using template
    self.frame = self.templateManager:CreatePanel("panel_scroll", {
        size = UDim2.new(0.6, 0, 0.8, 0),
        position = UDim2.new(0.5, 0, 0.5, 0),
        anchor_point = Vector2.new(0.5, 0.5),
        parent = parent
    })
    
    if not self.frame then
        -- Fallback frame creation
        self.frame = Instance.new("Frame")
        self.frame.Size = UDim2.new(0.6, 0, 0.8, 0)
        self.frame.Position = UDim2.new(0.5, 0, 0.5, 0)
        self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
        self.frame.BackgroundColor3 = theme.primary.surface
        self.frame.BorderSizePixel = 0
        self.frame.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 16)
        corner.Parent = self.frame
    end
    
    self.frame.Name = "EffectsPanel"
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 50)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "⚡ Effects Manager"
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
    
    -- Scroll frame for effects
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "EffectsScroll"
    scrollFrame.Size = UDim2.new(1, -20, 1, -70)
    scrollFrame.Position = UDim2.new(0, 10, 0, 60)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 8
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = self.frame
    
    -- Layout for effects
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 10)
    layout.Parent = scrollFrame
    
    -- Update canvas size when layout changes
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
    end)
    
    self.scrollFrame = scrollFrame
end

function EffectsPanel:_loadEffectsData()
    -- Try to get real effects data from services
    local player = Players.LocalPlayer
    
    -- Mock data for now (replace with real service calls)
    self.effectsData = {
        playerEffects = {
            {id = "speed_boost", name = "Speed Boost", duration = 300, remaining = 45, icon = "🏃", active = true},
            {id = "double_coins", name = "Double Coins", duration = 600, remaining = 120, icon = "💰", active = true},
            {id = "vip_status", name = "VIP Status", duration = -1, remaining = -1, icon = "⭐", active = true}, -- Permanent
        },
        globalEffects = {
            {id = "global_xp", name = "2x XP Weekend", duration = 7200, remaining = 3600, icon = "📈", active = true},
            {id = "premium_benefits", name = "Premium Benefits", duration = -1, remaining = -1, icon = "💎", active = true},
        }
    }
    
    self:_updateEffectsDisplay()
end

function EffectsPanel:_updateEffectsDisplay()
    -- Clear existing displays
    for _, display in pairs(self.effectDisplays) do
        display:Destroy()
    end
    self.effectDisplays = {}
    
    local theme = uiConfig.helpers.get_theme(uiConfig)
    local layoutOrder = 1
    
    -- Player Effects Section
    self:_createSectionHeader("Player Effects", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    for _, effect in ipairs(self.effectsData.playerEffects) do
        self:_createEffectDisplay(effect, "player", layoutOrder)
        layoutOrder = layoutOrder + 1
    end
    
    -- Global Effects Section
    self:_createSectionHeader("Global Effects", layoutOrder)
    layoutOrder = layoutOrder + 1
    
    for _, effect in ipairs(self.effectsData.globalEffects) do
        self:_createEffectDisplay(effect, "global", layoutOrder)
        layoutOrder = layoutOrder + 1
    end
end

function EffectsPanel:_createSectionHeader(title, layoutOrder)
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

function EffectsPanel:_createEffectDisplay(effect, effectType, layoutOrder)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    local effectFrame = Instance.new("Frame")
    effectFrame.Name = effect.id .. "Display"
    effectFrame.Size = UDim2.new(1, 0, 0, 60)
    effectFrame.BackgroundColor3 = theme.primary.card or Color3.fromRGB(50, 50, 55)
    effectFrame.BorderSizePixel = 0
    effectFrame.LayoutOrder = layoutOrder
    effectFrame.Parent = self.scrollFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = effectFrame
    
    -- Icon
    local iconLabel = Instance.new("TextLabel")
    iconLabel.Size = UDim2.new(0, 40, 0, 40)
    iconLabel.Position = UDim2.new(0, 10, 0.5, -20)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Text = effect.icon
    iconLabel.TextSize = 24
    iconLabel.Parent = effectFrame
    
    -- Effect name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(0, 200, 0, 20)
    nameLabel.Position = UDim2.new(0, 60, 0, 10)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = effect.name
    nameLabel.TextColor3 = theme.text.primary
    nameLabel.TextSize = 14
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Parent = effectFrame
    
    -- Duration/Timer
    local timeLabel = Instance.new("TextLabel")
    timeLabel.Size = UDim2.new(0, 200, 0, 16)
    timeLabel.Position = UDim2.new(0, 60, 0, 32)
    timeLabel.BackgroundTransparency = 1
    timeLabel.TextColor3 = theme.text.secondary or Color3.fromRGB(200, 200, 200)
    timeLabel.TextSize = 12
    timeLabel.Font = Enum.Font.Gotham
    timeLabel.TextXAlignment = Enum.TextXAlignment.Left
    timeLabel.Parent = effectFrame
    
    if effect.remaining == -1 then
        timeLabel.Text = "Permanent"
    else
        local minutes = math.floor(effect.remaining / 60)
        local seconds = effect.remaining % 60
        timeLabel.Text = string.format("%02d:%02d remaining", minutes, seconds)
    end
    
    -- Progress bar (for timed effects)
    if effect.remaining ~= -1 then
        local progressBG = Instance.new("Frame")
        progressBG.Size = UDim2.new(0, 150, 0, 4)
        progressBG.Position = UDim2.new(1, -160, 1, -8)
        progressBG.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        progressBG.BorderSizePixel = 0
        progressBG.Parent = effectFrame
        
        local progressFill = Instance.new("Frame")
        progressFill.Size = UDim2.new(effect.remaining / effect.duration, 0, 1, 0)
        progressFill.Position = UDim2.new(0, 0, 0, 0)
        progressFill.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
        progressFill.BorderSizePixel = 0
        progressFill.Parent = progressBG
        
        local progressCorner1 = Instance.new("UICorner")
        progressCorner1.CornerRadius = UDim.new(0, 2)
        progressCorner1.Parent = progressBG
        
        local progressCorner2 = Instance.new("UICorner")
        progressCorner2.CornerRadius = UDim.new(0, 2)
        progressCorner2.Parent = progressFill
    end
    
    table.insert(self.effectDisplays, effectFrame)
end

-- Update effects data (call this periodically)
function EffectsPanel:UpdateEffects(newEffectsData)
    if newEffectsData then
        self.effectsData = newEffectsData
    end
    
    if self.isVisible then
        self:_updateEffectsDisplay()
    end
end

-- Public interface methods
function EffectsPanel:IsVisible()
    return self.isVisible
end

function EffectsPanel:GetFrame()
    return self.frame
end

function EffectsPanel:Destroy()
    self:Hide()
    self.logger:info("Effects panel destroyed")
end

return EffectsPanel 