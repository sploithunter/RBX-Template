--[[
    AdminPanel - Administrative Tools and Test Interface
    
    Features:
    - Economy testing tools (buy items, adjust currencies)
    - Effects testing (start/stop effects, global effects)
    - Rate limiting tests
    - Debug utilities
    - System monitoring
    - Player data manipulation
    
    Usage:
    local AdminPanel = require(script.AdminPanel)
    local admin = AdminPanel.new()
    MenuManager:RegisterPanel("Admin", admin)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Get shared modules
local Locations = require(ReplicatedStorage.Shared.Locations)
local NetworkConfig = require(Locations.NetworkConfig)

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

local AdminPanel = {}
AdminPanel.__index = AdminPanel

-- Test categories and their actions
local TEST_CATEGORIES = {
    economy = {
        title = "💰 Economy Testing",
        tests = {
            {name = "Buy Test Item (50 coins)", action = "buy_test_item"},
            {name = "Buy Health Potion (25 coins)", action = "buy_health_potion"},
            {name = "Buy Wooden Sword (100 coins)", action = "buy_wooden_sword"},
            {name = "Buy Iron Sword (500 coins)", action = "buy_iron_sword"},
            {name = "Buy Basic Pickaxe (200 coins)", action = "buy_basic_pickaxe"},
            {name = "Buy Premium XP Boost (10 gems)", action = "buy_premium_xp_boost"},
            {name = "Buy Diamond Sword (25 gems)", action = "buy_diamond_sword"},
            {name = "Buy ⚡ Speed Potion (5 gems)", action = "buy_speed_potion"},
            {name = "Buy 📜 Trader Scroll (150 coins)", action = "buy_trader_scroll"},
        }
    },
    effects = {
        title = "⚡ Effects Testing",
        tests = {
            {name = "Test Effect Stacking", action = "test_effect_stacking"},
            {name = "Start XP Weekend (+8h)", action = "start_xp_weekend"},
            {name = "Start Speed Hour (1h)", action = "start_speed_hour"},
        }
    },
    system = {
        title = "🔧 System Testing",
        tests = {
            {name = "Test Rate Limiting", action = "test_rate_limiting"},
            {name = "Debug: Print Current Data", action = "debug_print_data"},
            {name = "Performance Test", action = "performance_test"},
            {name = "Network Bridge Test", action = "network_test"},
        }
    },
    currency = {
        title = "💎 Currency Management",
        tests = {
            {name = "Add 1000 Coins", action = "add_coins_1000"},
            {name = "Add 100 Gems", action = "add_gems_100"},
            {name = "Add 50 Crystals", action = "add_crystals_50"},
            {name = "Reset All Currencies", action = "reset_currencies"},
        }
    }
}

function AdminPanel.new()
    local self = setmetatable({}, AdminPanel)
    
    self.logger = LoggerWrapper.new("AdminPanel")
    self.templateManager = TemplateManager.new()
    
    -- Panel state
    self.isVisible = false
    self.frame = nil
    
    -- Network bridges
    self.economyBridge = nil
    self.effectsBridge = nil
    
    self:_initializeNetworking()
    
    return self
end

function AdminPanel:Show(parent)
    if self.isVisible then return end
    
    self:_createUI(parent)
    
    self.isVisible = true
    self.logger:info("Admin panel shown")
end

function AdminPanel:Hide()
    if not self.isVisible then return end
    
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    
    self.isVisible = false
    self.logger:info("Admin panel hidden")
end

function AdminPanel:_createUI(parent)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Create main panel using template
    self.frame = self.templateManager:CreatePanel("panel_scroll", {
        size = UDim2.new(0.8, 0, 0.9, 0),
        position = UDim2.new(0.5, 0, 0.5, 0),
        anchor_point = Vector2.new(0.5, 0.5),
        parent = parent
    })
    
    if not self.frame then
        -- Fallback frame creation
        self.frame = Instance.new("Frame")
        self.frame.Size = UDim2.new(0.8, 0, 0.9, 0)
        self.frame.Position = UDim2.new(0.5, 0, 0.5, 0)
        self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
        self.frame.BackgroundColor3 = theme.primary.surface
        self.frame.BorderSizePixel = 0
        self.frame.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 16)
        corner.Parent = self.frame
    end
    
    self.frame.Name = "AdminPanel"
    
    -- Warning header
    local warningLabel = Instance.new("TextLabel")
    warningLabel.Name = "Warning"
    warningLabel.Size = UDim2.new(1, 0, 0, 30)
    warningLabel.Position = UDim2.new(0, 0, 0, 0)
    warningLabel.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    warningLabel.BorderSizePixel = 0
    warningLabel.Text = "⚠️ ADMIN TOOLS - USE WITH CAUTION ⚠️"
    warningLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    warningLabel.TextSize = 16
    warningLabel.Font = Enum.Font.GothamBold
    warningLabel.TextXAlignment = Enum.TextXAlignment.Center
    warningLabel.Parent = self.frame
    
    local warningCorner = Instance.new("UICorner")
    warningCorner.CornerRadius = UDim.new(0, 8)
    warningCorner.Parent = warningLabel
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 40)
    titleLabel.Position = UDim2.new(0, 0, 0, 35)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "🛠️ Admin Control Panel"
    titleLabel.TextColor3 = theme.text.primary
    titleLabel.TextSize = 24
    titleLabel.Font = uiConfig.fonts and uiConfig.fonts.primary or Enum.Font.Gotham
    titleLabel.TextXAlignment = Enum.TextXAlignment.Center
    titleLabel.Parent = self.frame
    
    -- Close button
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 40, 0, 40)
    closeButton.Position = UDim2.new(1, -50, 0, 35)
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
    
    -- Scroll frame for test categories
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "AdminScroll"
    scrollFrame.Size = UDim2.new(1, -20, 1, -90)
    scrollFrame.Position = UDim2.new(0, 10, 0, 80)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 8
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = self.frame
    
    -- Layout for test categories
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
    
    -- Create test category sections
    self:_createTestCategories()
end

function AdminPanel:_createTestCategories()
    local layoutOrder = 1
    
    for categoryKey, categoryData in pairs(TEST_CATEGORIES) do
        self:_createCategorySection(categoryData.title, categoryData.tests, layoutOrder)
        layoutOrder = layoutOrder + 1
    end
end

function AdminPanel:_createCategorySection(title, tests, layoutOrder)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Category header
    local header = Instance.new("Frame")
    header.Name = title .. "Header"
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = theme.primary.accent or Color3.fromRGB(0, 120, 180)
    header.BorderSizePixel = 0
    header.LayoutOrder = layoutOrder
    header.Parent = self.scrollFrame
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 8)
    headerCorner.Parent = header
    
    local headerLabel = Instance.new("TextLabel")
    headerLabel.Size = UDim2.new(1, -20, 1, 0)
    headerLabel.Position = UDim2.new(0, 10, 0, 0)
    headerLabel.BackgroundTransparency = 1
    headerLabel.Text = title
    headerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    headerLabel.TextSize = 16
    headerLabel.Font = Enum.Font.GothamBold
    headerLabel.TextXAlignment = Enum.TextXAlignment.Left
    headerLabel.Parent = header
    
    -- Tests container
    local testsContainer = Instance.new("Frame")
    testsContainer.Name = title .. "Tests"
    testsContainer.Size = UDim2.new(1, 0, 0, #tests * 45 + 10)
    testsContainer.BackgroundColor3 = theme.primary.card or Color3.fromRGB(50, 50, 55)
    testsContainer.BorderSizePixel = 0
    testsContainer.LayoutOrder = layoutOrder + 0.5
    testsContainer.Parent = self.scrollFrame
    
    local testsCorner = Instance.new("UICorner")
    testsCorner.CornerRadius = UDim.new(0, 8)
    testsCorner.Parent = testsContainer
    
    local testsLayout = Instance.new("UIListLayout")
    testsLayout.FillDirection = Enum.FillDirection.Vertical
    testsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    testsLayout.Padding = UDim.new(0, 5)
    testsLayout.Parent = testsContainer
    
    local testsPadding = Instance.new("UIPadding")
    testsPadding.PaddingTop = UDim.new(0, 10)
    testsPadding.PaddingBottom = UDim.new(0, 5)
    testsPadding.PaddingLeft = UDim.new(0, 10)
    testsPadding.PaddingRight = UDim.new(0, 10)
    testsPadding.Parent = testsContainer
    
    -- Create test buttons
    for i, test in ipairs(tests) do
        self:_createTestButton(test.name, test.action, i, testsContainer)
    end
end

function AdminPanel:_createTestButton(testName, action, layoutOrder, parent)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    local button = Instance.new("TextButton")
    button.Name = action .. "Button"
    button.Size = UDim2.new(1, 0, 0, 35)
    button.BackgroundColor3 = theme.button and theme.button.primary or Color3.fromRGB(0, 120, 180)
    button.BorderSizePixel = 0
    button.Text = testName
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 13
    button.Font = Enum.Font.Gotham
    button.LayoutOrder = layoutOrder
    button.Parent = parent
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 6)
    buttonCorner.Parent = button
    
    -- Hover effects
    button.MouseEnter:Connect(function()
        local tween = TweenService:Create(
            button,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad),
            {BackgroundColor3 = Color3.fromRGB(0, 140, 200)}
        )
        tween:Play()
    end)
    
    button.MouseLeave:Connect(function()
        local tween = TweenService:Create(
            button,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad),
            {BackgroundColor3 = theme.button and theme.button.primary or Color3.fromRGB(0, 120, 180)}
        )
        tween:Play()
    end)
    
    button.Activated:Connect(function()
        self:_executeTestAction(action, testName)
    end)
end

function AdminPanel:_executeTestAction(action, testName)
    self.logger:info("Executing test action:", action)
    
    -- Economy actions
    if action:find("buy_") then
        self:_executePurchaseAction(action)
    elseif action:find("add_") then
        self:_executeCurrencyAction(action)
    elseif action == "reset_currencies" then
        self:_resetCurrencies()
    
    -- Effects actions
    elseif action:find("effect") or action:find("start_") then
        self:_executeEffectAction(action)
    
    -- System actions
    elseif action == "test_rate_limiting" then
        self:_testRateLimit()
    elseif action == "debug_print_data" then
        self:_debugPrintData()
    elseif action == "performance_test" then
        self:_performanceTest()
    elseif action == "network_test" then
        self:_networkTest()
    
    else
        self.logger:warn("Unknown action:", action)
    end
end

function AdminPanel:_executePurchaseAction(action)
    if not self.economyBridge then
        self.logger:warn("Economy bridge not available")
        return
    end
    
    -- Map actions to purchase data
    local purchases = {
        buy_test_item = {itemId = "test_item", cost = 50, currency = "coins"},
        buy_health_potion = {itemId = "health_potion", cost = 25, currency = "coins"},
        buy_wooden_sword = {itemId = "wooden_sword", cost = 100, currency = "coins"},
        buy_iron_sword = {itemId = "iron_sword", cost = 500, currency = "coins"},
        buy_basic_pickaxe = {itemId = "basic_pickaxe", cost = 200, currency = "coins"},
        buy_premium_xp_boost = {itemId = "premium_xp_boost", cost = 10, currency = "gems"},
        buy_diamond_sword = {itemId = "diamond_sword", cost = 25, currency = "gems"},
        buy_speed_potion = {itemId = "speed_potion", cost = 5, currency = "gems"},
        buy_trader_scroll = {itemId = "trader_scroll", cost = 150, currency = "coins"},
    }
    
    local purchaseData = purchases[action]
    if purchaseData then
        self.economyBridge:Fire("purchase_item", purchaseData)
        self.logger:info("Purchase request sent:", purchaseData.itemId)
    end
end

function AdminPanel:_executeCurrencyAction(action)
    if not self.economyBridge then
        self.logger:warn("Economy bridge not available")
        return
    end
    
    local currencyAdjustments = {
        add_coins_1000 = {currency = "coins", amount = 1000},
        add_gems_100 = {currency = "gems", amount = 100},
        add_crystals_50 = {currency = "crystals", amount = 50},
    }
    
    local adjustment = currencyAdjustments[action]
    if adjustment then
        self.economyBridge:Fire("adjust_currency", adjustment)
        self.logger:info("Currency adjustment sent:", adjustment)
    end
end

function AdminPanel:_resetCurrencies()
    if not self.economyBridge then
        self.logger:warn("Economy bridge not available")
        return
    end
    
    self.economyBridge:Fire("reset_currencies", {})
    self.logger:info("Currency reset requested")
end

function AdminPanel:_executeEffectAction(action)
    self.logger:info("Effect action:", action)
    -- Implement effect actions when effects system is connected
end

function AdminPanel:_testRateLimit()
    self.logger:info("Testing rate limits...")
    -- Spam requests to test rate limiting
    for i = 1, 10 do
        if self.economyBridge then
            self.economyBridge:Fire("test_request", {iteration = i})
        end
    end
end

function AdminPanel:_debugPrintData()
    local player = Players.LocalPlayer
    print("=== DEBUG: Player Data ===")
    print("Player:", player.Name)
    print("UserId:", player.UserId)
    if player:FindFirstChild("leaderstats") then
        print("Leaderstats found:")
        for _, stat in pairs(player.leaderstats:GetChildren()) do
            print("  ", stat.Name, "=", stat.Value)
        end
    else
        print("No leaderstats found")
    end
    print("=== END DEBUG ===")
end

function AdminPanel:_performanceTest()
    self.logger:info("Running performance test...")
    local startTime = tick()
    
    -- Create and destroy many UI elements
    for i = 1, 1000 do
        local testFrame = Instance.new("Frame")
        testFrame.Size = UDim2.new(0, 10, 0, 10)
        testFrame.Parent = workspace
        testFrame:Destroy()
    end
    
    local endTime = tick()
    self.logger:info("Performance test completed in", endTime - startTime, "seconds")
end

function AdminPanel:_networkTest()
    self.logger:info("Testing network connections...")
    if self.economyBridge then
        self.logger:info("Economy bridge: CONNECTED")
    else
        self.logger:warn("Economy bridge: NOT CONNECTED")
    end
    
    if self.effectsBridge then
        self.logger:info("Effects bridge: CONNECTED")
    else
        self.logger:warn("Effects bridge: NOT CONNECTED")
    end
end

function AdminPanel:_initializeNetworking()
    task.spawn(function()
        task.wait(2) -- Wait for NetworkConfig to initialize
        
        if NetworkConfig then
            self.economyBridge = NetworkConfig:GetBridge("Economy")
            self.effectsBridge = NetworkConfig:GetBridge("Effects")
            
            if self.economyBridge then
                self.logger:info("Economy bridge connected")
            end
            if self.effectsBridge then
                self.logger:info("Effects bridge connected")
            end
        else
            self.logger:warn("NetworkConfig not available")
        end
    end)
end

-- Public interface methods
function AdminPanel:IsVisible()
    return self.isVisible
end

function AdminPanel:GetFrame()
    return self.frame
end

function AdminPanel:Destroy()
    self:Hide()
    self.logger:info("Admin panel destroyed")
end

return AdminPanel 