-- Test GUI for Economy System
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Get NetworkConfig (wait for it to be loaded)
local NetworkConfig = require(ReplicatedStorage.Shared.Utils.NetworkConfig)

-- Wait for NetworkConfig to initialize, then get the Economy bridge
local economyBridge
task.wait(1) -- Give NetworkConfig time to initialize
economyBridge = NetworkConfig:GetBridge("Economy")

if not economyBridge then
    warn("Economy bridge not found! Check network.lua configuration")
    return
end

-- Create test GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EconomyTestGUI"
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 350, 0, 700)
frame.Position = UDim2.new(0, 10, 0, 10)
frame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
frame.BorderSizePixel = 0
frame.Parent = screenGui

-- Add corner radius
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "Economy System Test"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = frame

-- Currency display
local currencyLabel = Instance.new("TextLabel")
currencyLabel.Size = UDim2.new(0.9, 0, 0, 25)
currencyLabel.Position = UDim2.new(0.05, 0, 0, 35)
currencyLabel.BackgroundTransparency = 1
currencyLabel.Text = "Coins: Loading... | Gems: Loading..."
currencyLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
currencyLabel.TextScaled = true
currencyLabel.Font = Enum.Font.Gotham
currencyLabel.Parent = frame

-- Scrolling frame for shop items
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(0.9, 0, 0, 400)
scrollFrame.Position = UDim2.new(0.05, 0, 0, 70)
scrollFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 6
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = frame

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 4)
scrollCorner.Parent = scrollFrame

-- Layout for shop items
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

-- Shop items data
local shopItems = {
    -- Basic items
    {id = "test_item", name = "Test Item", price = 50, currency = "coins"},
    {id = "health_potion", name = "Health Potion", price = 25, currency = "coins"},
    {id = "wooden_sword", name = "Wooden Sword", price = 100, currency = "coins"},
    {id = "iron_sword", name = "Iron Sword", price = 500, currency = "coins"},
    {id = "basic_pickaxe", name = "Basic Pickaxe", price = 200, currency = "coins"},
    
    -- Premium items
    {id = "premium_boost", name = "Premium XP Boost", price = 10, currency = "gems"},
    {id = "diamond_sword", name = "Diamond Sword", price = 25, currency = "gems"},
    
    -- Rate limiting effect items ⚡
    {id = "speed_potion", name = "⚡ Speed Potion", price = 5, currency = "gems"},
    {id = "trader_scroll", name = "📜 Trader Scroll", price = 150, currency = "coins"},
    {id = "vip_pass", name = "💎 VIP Pass", price = 100, currency = "gems"},
    
    -- Testing utilities 🧪
    {id = "alamantic_aluminum", name = "🧪 Alamantic Aluminum", price = 1, currency = "coins"}
}

-- Function to create purchase button
local function createPurchaseButton(item, index)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -10, 0, 40)
    button.BackgroundColor3 = Color3.fromRGB(0, 120, 180)
    button.Text = string.format("Buy %s (%d %s)", item.name, item.price, item.currency)
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.Gotham
    button.TextScaled = true
    button.LayoutOrder = index
    button.Parent = scrollFrame
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 4)
    buttonCorner.Parent = button
    
    button.Activated:Connect(function()
        print(string.format("🛒 Purchasing %s for %d %s...", item.name, item.price, item.currency))
        print("📊 Current coins before purchase:", player:GetAttribute("Coins") or "unknown")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = item.id,
            cost = item.price,
            currency = item.currency
        })
    end)
    
    return button
end

-- Create purchase buttons for each item
for i, item in ipairs(shopItems) do
    createPurchaseButton(item, i)
end

-- Update canvas size based on content
local function updateCanvasSize()
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
updateCanvasSize()

-- Control buttons section
    local controlsFrame = Instance.new("Frame")
    controlsFrame.Size = UDim2.new(0.9, 0, 0, 155)
    controlsFrame.Position = UDim2.new(0.05, 0, 0, 480)
controlsFrame.BackgroundTransparency = 1
controlsFrame.Parent = frame

local controlsLayout = Instance.new("UIListLayout")
controlsLayout.Padding = UDim.new(0, 3)
controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
controlsLayout.Parent = controlsFrame

-- Comprehensive Test Button
local comprehensiveTestButton = Instance.new("TextButton")
comprehensiveTestButton.Size = UDim2.new(1, 0, 0, 30)
comprehensiveTestButton.BackgroundColor3 = Color3.fromRGB(34, 139, 34)
comprehensiveTestButton.Text = "🚀 RUN COMPREHENSIVE TEST"
comprehensiveTestButton.TextColor3 = Color3.fromRGB(255, 255, 255)
comprehensiveTestButton.Font = Enum.Font.GothamBold
comprehensiveTestButton.TextScaled = true
comprehensiveTestButton.LayoutOrder = 0
comprehensiveTestButton.Parent = controlsFrame

local comprehensiveCorner = Instance.new("UICorner")
comprehensiveCorner.CornerRadius = UDim.new(0, 4)
comprehensiveCorner.Parent = comprehensiveTestButton

comprehensiveTestButton.Activated:Connect(function()
    print("🚀 ===== COMPREHENSIVE ECONOMY TEST STARTING =====")
    
    -- Test sequence with delays to see each step
    local function runTestSequence()
        -- Step 1: Get initial state
        print("📊 Step 1: Getting initial state...")
        economyBridge:Fire("server", "GetPlayerDebugInfo", {})
        task.wait(1)
        
        -- Step 2: Purchase with coins
        print("💰 Step 2: Purchasing test_item with coins...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "test_item",
            cost = 50,
            currency = "coins"
        })
        task.wait(1)
        
        -- Step 3: Purchase with gems
        print("💎 Step 3: Purchasing premium_boost with gems...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "premium_boost",
            cost = 10,
            currency = "gems"
        })
        task.wait(1)
        
        -- Step 4: Sell an item
        print("💸 Step 4: Selling test_item...")
        economyBridge:Fire("server", "SellItem", {
            itemId = "test_item",
            quantity = 1
        })
        task.wait(1)
        
        -- Step 5: Try purchasing with insufficient funds
        print("❌ Step 5: Testing insufficient funds (diamond_sword = 25 gems)...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "diamond_sword",
            cost = 25,
            currency = "gems"
        })
        task.wait(1)
        
        -- Step 5.5: Try purchasing with insufficient level (crystal_staff requires level 10)
        print("❌ Step 5.5: Testing insufficient level (crystal_staff requires level 10, player is level 1)...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "crystal_staff",
            cost = 5,
            currency = "crystals"
        })
        task.wait(1)
        
        -- Step 6: Get final state and summary
        print("📊 Step 6: Getting final state...")
        economyBridge:Fire("server", "GetPlayerDebugInfo", {})
        task.wait(1)
        
        -- Step 7: Test level requirement bypass (temporarily increase level)
        print("🔧 Step 7: Testing level requirement system...")
        print("   - Setting player level to 10 to test crystal_staff purchase...")
        -- Note: This would require a test-only level adjustment function
        
        print("🏁 ===== COMPREHENSIVE TEST COMPLETED =====")
        print("✅ Check the logs above to verify all systems worked correctly!")
        print("📋 EXPECTED RESULTS:")
        print("   ✅ Steps 1-4: All purchases and sells should succeed")
        print("   ❌ Step 5: diamond_sword should fail (insufficient gems)")
        print("   ❌ Step 5.5: crystal_staff should fail (insufficient level)")
    end
    
    task.spawn(runTestSequence)
end)

-- Get Shop Items Button
local shopButton = Instance.new("TextButton")
shopButton.Size = UDim2.new(1, 0, 0, 25)
shopButton.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
shopButton.Text = "Refresh Shop Items"
shopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
shopButton.Font = Enum.Font.Gotham
shopButton.TextScaled = true
shopButton.LayoutOrder = 1
shopButton.Parent = controlsFrame

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 4)
shopCorner.Parent = shopButton

shopButton.Activated:Connect(function()
    print("🏪 Requesting shop items...")
    economyBridge:Fire("server", "GetShopItems", {})
end)

-- Sell Test Item Button
local sellButton = Instance.new("TextButton")
sellButton.Size = UDim2.new(1, 0, 0, 25)
sellButton.BackgroundColor3 = Color3.fromRGB(200, 100, 0)
sellButton.Text = "Sell Test Item"
sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)
sellButton.Font = Enum.Font.Gotham
sellButton.TextScaled = true
sellButton.LayoutOrder = 2
sellButton.Parent = controlsFrame

local sellCorner = Instance.new("UICorner")
sellCorner.CornerRadius = UDim.new(0, 4)
sellCorner.Parent = sellButton

sellButton.Activated:Connect(function()
    print("💰 Testing item sell...")
    print("📊 Current coins before sell:", player:GetAttribute("Coins") or "unknown")
    economyBridge:Fire("server", "SellItem", {
        itemId = "test_item",
        quantity = 1
    })
end)

-- Debug button
local debugButton = Instance.new("TextButton")
debugButton.Size = UDim2.new(1, 0, 0, 15)
debugButton.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
debugButton.Text = "Debug: Print Current Data"
debugButton.TextColor3 = Color3.fromRGB(255, 255, 255)
debugButton.TextScaled = true
debugButton.Font = Enum.Font.Gotham
debugButton.LayoutOrder = 3
debugButton.Parent = controlsFrame

local debugCorner = Instance.new("UICorner")
debugCorner.CornerRadius = UDim.new(0, 4)
debugCorner.Parent = debugButton

debugButton.Activated:Connect(function()
    print("🔍 DEBUG INFO:")
    print("   Coins:", player:GetAttribute("Coins") or "not set")
    print("   Gems:", player:GetAttribute("Gems") or "not set")
    print("   Level:", player:GetAttribute("Level") or "not set")
    print("   Data Loaded:", player:GetAttribute("DataLoaded") or "not set")
    print("   Bridge Available:", economyBridge ~= nil)
    
    -- Request inventory info from server
    economyBridge:Fire("server", "GetPlayerDebugInfo", {})
end)

-- Rate Limiting Test Button
local rateLimitButton = Instance.new("TextButton")
rateLimitButton.Size = UDim2.new(1, 0, 0, 25)
rateLimitButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
rateLimitButton.Text = "Test Rate Limiting"
rateLimitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
rateLimitButton.TextScaled = true
rateLimitButton.Font = Enum.Font.Gotham
rateLimitButton.LayoutOrder = 4
rateLimitButton.Parent = controlsFrame

local rateLimitCorner = Instance.new("UICorner")
rateLimitCorner.CornerRadius = UDim.new(0, 4)
rateLimitCorner.Parent = rateLimitButton

rateLimitButton.Activated:Connect(function()
    task.spawn(function()
        print("🚨 ===== RATE LIMITING TEST START =====")
        
        -- Test 1: Rapid fire purchases (should trigger rate limiting)
        print("⚡ Test 1: Rapid fire purchases (should hit rate limits)...")
        for i = 1, 10 do
            print(string.format("  🔥 Rapid purchase #%d", i))
            economyBridge:Fire("server", "PurchaseItem", {
                itemId = "test_item",
                cost = 50,
                currency = "coins"
            })
            task.wait(0.05) -- Very fast - 20 requests per second
        end
        task.wait(2)
        
        -- Test 2: Purchase and use a speed potion
        print("🧪 Test 2: Buying and using speed potion...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "speed_potion",
            cost = 5,
            currency = "gems"
        })
        task.wait(1)
        
        print("  💊 Using speed potion (should apply rate boost)...")
        economyBridge:Fire("server", "UseItem", {itemId = "speed_potion"})
        task.wait(2)
        
        -- Test 3: Rapid purchases WITH speed boost active
        print("⚡ Test 3: Rapid purchases WITH speed boost...")
        for i = 1, 10 do
            print(string.format("  ⚡ Boosted purchase #%d", i))
            economyBridge:Fire("server", "PurchaseItem", {
                itemId = "test_item",
                cost = 50,
                currency = "coins"
            })
            task.wait(0.05)
        end
        task.wait(2)
        
        -- Test 4: Check final state
        print("📊 Test 4: Getting final state...")
        economyBridge:Fire("server", "GetPlayerDebugInfo", {})
        
        print("🏁 ===== RATE LIMITING TEST COMPLETE =====")
        print("📋 EXPECTED RESULTS:")
        print("   ❌ Test 1: Some purchases should be blocked (rate limited)")
        print("   ✅ Test 2: Speed potion should be purchased and used")
        print("   ✅ Test 3: More purchases should succeed (rate boost active)")
    end)
end)

-- Effect Stacking Test Button
local effectButton = Instance.new("TextButton")
effectButton.Size = UDim2.new(1, 0, 0, 25)
effectButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
effectButton.Text = "Test Effect Stacking"
effectButton.TextColor3 = Color3.fromRGB(255, 255, 255)
effectButton.TextScaled = true
effectButton.Font = Enum.Font.Gotham
effectButton.LayoutOrder = 5
effectButton.Parent = controlsFrame

local effectCorner = Instance.new("UICorner")
effectCorner.CornerRadius = UDim.new(0, 4)
effectCorner.Parent = effectButton

effectButton.Activated:Connect(function()
    task.spawn(function()
        print("🔗 ===== EFFECT STACKING TEST START =====")
        
        -- Test 1: Buy multiple DIFFERENT effect items
        print("🛒 Test 1: Buying different effect items...")
        
        print("  💊 Buying speed potion...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "speed_potion",
            cost = 5,
            currency = "gems"
        })
        task.wait(1)
        
        print("  📜 Buying trader scroll...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "trader_scroll",
            cost = 150,
            currency = "coins"
        })
        task.wait(1)
        
        print("  💎 Buying VIP pass...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "vip_pass",
            cost = 100,
            currency = "gems"
        })
        task.wait(1)
        
        print("  💊 Buying extra speed potion...")
        economyBridge:Fire("server", "PurchaseItem", {
            itemId = "speed_potion",
            cost = 5,
            currency = "gems"
        })
        task.wait(2)
        
        -- Test 2: Use different effects (should test stacking limits)
        print("⚡ Test 2: Using different effects (testing stacking)...")
        
        print("  🧪 Using speed potion (effect #1)...")
        economyBridge:Fire("server", "UseItem", {itemId = "speed_potion"})
        task.wait(1)
        
        print("  📜 Using trader scroll (effect #2)...")
        economyBridge:Fire("server", "UseItem", {itemId = "trader_scroll"})
        task.wait(1)
        
        print("  💎 Using VIP pass (effect #3)...")
        economyBridge:Fire("server", "UseItem", {itemId = "vip_pass"})
        task.wait(1)
        
        print("  💊 Using 4th speed potion (should be rejected - stacking limit)...")
        economyBridge:Fire("server", "UseItem", {itemId = "speed_potion"})
        task.wait(2)
        
        -- Test 3: Try to add 5th effect (should be rejected)
        print("📜 Test 3: Attempting 5th effect (should fail)...")
        print("  🧪 Trying to use another speed potion...")
        economyBridge:Fire("server", "UseItem", {itemId = "speed_potion"})
        task.wait(2)
        
        -- Test 4: Rapid purchases with mixed effects
        print("🚀 Test 4: Rapid purchases with mixed effects active...")
        for i = 1, 8 do
            print(string.format("  🎯 Multi-effect purchase #%d", i))
            economyBridge:Fire("server", "PurchaseItem", {
                itemId = "test_item",
                cost = 50,
                currency = "coins"
            })
            task.wait(0.1)
        end
        
        print("🏁 ===== EFFECT STACKING TEST COMPLETE =====")
        print("📋 EXPECTED RESULTS:")
        print("   ✅ First 3 different effects should stack (speed, trader, VIP)")
        print("   ❌ 4th effect should be rejected (stacking limit of 3)")
        print("   ❌ 5th effect should be rejected (stacking limit)")
        print("   ✅ Mixed effect purchases should succeed with boosted rates")
    end)
end)

-- Function to update currency display
local function updateCurrencyDisplay()
    local coins = player:GetAttribute("Coins") or 0
    local gems = player:GetAttribute("Gems") or 0
    local crystals = player:GetAttribute("Crystals") or 0
    currencyLabel.Text = string.format("💰 Coins: %d | 💎 Gems: %d | 🔮 Crystals: %d", coins, gems, crystals)
end

-- Update currency display when attributes change
player:GetAttributeChangedSignal("Coins"):Connect(updateCurrencyDisplay)
player:GetAttributeChangedSignal("Gems"):Connect(updateCurrencyDisplay)
player:GetAttributeChangedSignal("Crystals"):Connect(updateCurrencyDisplay)

-- Initial currency display update
task.spawn(function()
    task.wait(2) -- Wait for data to potentially load
    updateCurrencyDisplay()
end)

print("💰 Enhanced Economy Test GUI loaded!")

return {
    UpdateStatus = function(text)
        -- Could add a status label if needed
        print("Status:", text)
    end
} 