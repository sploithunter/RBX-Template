--[[
    InventoryPanel - Professional Pet Simulator Style Inventory
    
    Features:
    - Grid layout with item cards
    - Search functionality
    - Category filtering
    - Professional visual design with gradients and shadows
    - Hover effects and animations
    - Item rarity indicators
    - Responsive design
    
    Usage:
    local InventoryPanel = require(script.InventoryPanel)
    local inventory = InventoryPanel.new()
    MenuManager:RegisterPanel("Inventory", inventory)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Get shared modules
local Locations = require(ReplicatedStorage.Shared.Locations)

-- Load Logger with wrapper
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

-- Load UI config
local uiConfig
local configSuccess, configResult = pcall(function()
    return Locations.getConfig("ui")
end)

if configSuccess and configResult then
    uiConfig = configResult
else
    -- Enhanced fallback config
    uiConfig = {
        active_theme = "dark",
        themes = {
            dark = {
                primary = { 
                    background = Color3.fromRGB(25, 25, 30), 
                    surface = Color3.fromRGB(35, 35, 45),
                    accent = Color3.fromRGB(52, 152, 219)
                },
                text = { 
                    primary = Color3.fromRGB(255, 255, 255),
                    secondary = Color3.fromRGB(200, 200, 210)
                }
            }
        },
        helpers = {
            get_theme = function(config) return config.themes.dark end
        }
    }
end

local InventoryPanel = {}
InventoryPanel.__index = InventoryPanel

function InventoryPanel.new()
    local self = setmetatable({}, InventoryPanel)
    
    self.logger = LoggerWrapper.new("InventoryPanel")
    
    -- Panel state
    self.isVisible = false
    self.frame = nil
    self.searchBox = nil
    self.itemsGrid = nil
    self.itemFrames = {}
    self.selectedCategory = "All"
    self.searchTerm = ""
    
    -- Sample inventory data (replace with real data)
    self.inventoryData = self:_generateSampleData()
    
    return self
end

function InventoryPanel:Show(parent)
    if self.isVisible then return end
    
    self:_createUI(parent)
    self:_updateItemsDisplay()
    
    self.isVisible = true
    self.logger:info("Professional inventory panel shown")
end

function InventoryPanel:Hide()
    if not self.isVisible then return end
    
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    
    self.itemFrames = {}
    self.isVisible = false
    self.logger:info("Inventory panel hidden")
end

function InventoryPanel:_createUI(parent)
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Main panel frame
    self.frame = Instance.new("Frame")
    self.frame.Name = "InventoryPanel"
    self.frame.Size = UDim2.new(0.8, 0, 0.85, 0)
    self.frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    self.frame.AnchorPoint = Vector2.new(0.5, 0.5)
    self.frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    self.frame.BorderSizePixel = 0
    self.frame.ZIndex = 100
    self.frame.Parent = parent
    
    -- Rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 20)
    corner.Parent = self.frame
    
    -- Border glow
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(52, 152, 219)
    stroke.Thickness = 3
    stroke.Transparency = 0.3
    stroke.Parent = self.frame
    
    -- Background gradient
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 25))
    }
    gradient.Rotation = 45
    gradient.Parent = self.frame
    
    -- Header section
    self:_createHeader()
    
    -- Category tabs
    self:_createCategoryTabs()
    
    -- Search section
    self:_createSearchSection()
    
    -- Items grid
    self:_createItemsGrid()
    
    -- Add entrance animation
    self:_animateEntrance()
end

function InventoryPanel:_createHeader()
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Header background
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 70)
    header.Position = UDim2.new(0, 0, 0, 0)
    header.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
    header.BorderSizePixel = 0
    header.ZIndex = 101
    header.Parent = self.frame
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 20)
    headerCorner.Parent = header
    
    -- Header gradient
    local headerGradient = Instance.new("UIGradient")
    headerGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(52, 152, 219)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(41, 128, 185))
    }
    headerGradient.Rotation = 90
    headerGradient.Parent = header
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -120, 1, 0)
    title.Position = UDim2.new(0, 20, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🎒 Inventory"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 102
    title.Parent = header
    
    -- Team indicator
    local teamInfo = Instance.new("TextLabel")
    teamInfo.Name = "TeamInfo"
    teamInfo.Size = UDim2.new(0, 200, 0, 25)
    teamInfo.Position = UDim2.new(1, -220, 0, 10)
    teamInfo.BackgroundTransparency = 1
    teamInfo.Text = "🐾 Your Team: 99/99"
    teamInfo.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamInfo.TextScaled = true
    teamInfo.Font = Enum.Font.Gotham
    teamInfo.TextXAlignment = Enum.TextXAlignment.Right
    teamInfo.ZIndex = 102
    teamInfo.Parent = header
    
    -- Close button
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 50, 0, 50)
    closeButton.Position = UDim2.new(1, -60, 0, 10)
    closeButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
    closeButton.BorderSizePixel = 0
    closeButton.Text = "✕"
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextScaled = true
    closeButton.Font = Enum.Font.GothamBold
    closeButton.ZIndex = 102
    closeButton.Parent = header
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 25)
    closeCorner.Parent = closeButton
    
    -- Close button effects
    self:_addButtonHoverEffect(closeButton, Color3.fromRGB(231, 76, 60))
    
    closeButton.Activated:Connect(function()
        self:Hide()
    end)
end

function InventoryPanel:_createCategoryTabs()
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Category container
    local categoryContainer = Instance.new("Frame")
    categoryContainer.Name = "CategoryContainer"
    categoryContainer.Size = UDim2.new(1, -40, 0, 50)
    categoryContainer.Position = UDim2.new(0, 20, 0, 80)
    categoryContainer.BackgroundTransparency = 1
    categoryContainer.ZIndex = 101
    categoryContainer.Parent = self.frame
    
    -- Layout
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 10)
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = categoryContainer
    
    -- Category tabs
    local categories = {
        { name = "All", icon = "📦", count = #self.inventoryData },
        { name = "Pets", icon = "🐾", count = 45 },
        { name = "Items", icon = "⚡", count = 23 },
        { name = "Eggs", icon = "🥚", count = 12 },
        { name = "Tools", icon = "🔧", count = 8 }
    }
    
    for i, category in ipairs(categories) do
        self:_createCategoryTab(category, categoryContainer, i)
    end
end

function InventoryPanel:_createCategoryTab(category, parent, layoutOrder)
    local isSelected = (category.name == self.selectedCategory)
    
    -- Tab button
    local tab = Instance.new("TextButton")
    tab.Name = category.name .. "Tab"
    tab.Size = UDim2.new(0, 120, 1, 0)
    tab.BackgroundColor3 = isSelected and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(40, 40, 50)
    tab.BorderSizePixel = 0
    tab.Text = ""
    tab.LayoutOrder = layoutOrder
    tab.ZIndex = 102
    tab.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = tab
    
    -- Tab content
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -10, 1, -10)
    content.Position = UDim2.new(0, 5, 0, 5)
    content.BackgroundTransparency = 1
    content.ZIndex = 103
    content.Parent = tab
    
    -- Icon
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 20, 0, 20)
    icon.Position = UDim2.new(0, 0, 0, 2)
    icon.BackgroundTransparency = 1
    icon.Text = category.icon
    icon.TextScaled = true
    icon.Font = Enum.Font.GothamBold
    icon.ZIndex = 104
    icon.Parent = content
    
    -- Name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -25, 0, 18)
    nameLabel.Position = UDim2.new(0, 25, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = category.name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.ZIndex = 104
    nameLabel.Parent = content
    
    -- Count
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(1, -25, 0, 15)
    countLabel.Position = UDim2.new(0, 25, 0, 20)
    countLabel.BackgroundTransparency = 1
    countLabel.Text = category.count .. " items"
    countLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    countLabel.TextScaled = true
    countLabel.Font = Enum.Font.Gotham
    countLabel.TextXAlignment = Enum.TextXAlignment.Left
    countLabel.ZIndex = 104
    countLabel.Parent = content
    
    -- Click handling
    tab.Activated:Connect(function()
        self:_selectCategory(category.name)
    end)
    
    if not isSelected then
        self:_addButtonHoverEffect(tab, Color3.fromRGB(40, 40, 50))
    end
end

function InventoryPanel:_createSearchSection()
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Search container
    local searchContainer = Instance.new("Frame")
    searchContainer.Name = "SearchContainer"
    searchContainer.Size = UDim2.new(1, -40, 0, 50)
    searchContainer.Position = UDim2.new(0, 20, 0, 140)
    searchContainer.BackgroundTransparency = 1
    searchContainer.ZIndex = 101
    searchContainer.Parent = self.frame
    
    -- Search box background
    local searchBG = Instance.new("Frame")
    searchBG.Size = UDim2.new(0, 300, 1, -10)
    searchBG.Position = UDim2.new(0, 0, 0, 5)
    searchBG.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    searchBG.BorderSizePixel = 0
    searchBG.ZIndex = 102
    searchBG.Parent = searchContainer
    
    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 10)
    searchCorner.Parent = searchBG
    
    -- Search icon
    local searchIcon = Instance.new("TextLabel")
    searchIcon.Size = UDim2.new(0, 30, 0, 30)
    searchIcon.Position = UDim2.new(0, 10, 0.5, -15)
    searchIcon.BackgroundTransparency = 1
    searchIcon.Text = "🔍"
    searchIcon.TextScaled = true
    searchIcon.Font = Enum.Font.GothamBold
    searchIcon.ZIndex = 104
    searchIcon.Parent = searchBG
    
    -- Search text box
    self.searchBox = Instance.new("TextBox")
    self.searchBox.Name = "SearchBox"
    self.searchBox.Size = UDim2.new(1, -50, 1, -10)
    self.searchBox.Position = UDim2.new(0, 45, 0, 5)
    self.searchBox.BackgroundTransparency = 1
    self.searchBox.Text = ""
    self.searchBox.PlaceholderText = "Search items..."
    self.searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    self.searchBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
    self.searchBox.TextScaled = true
    self.searchBox.Font = Enum.Font.Gotham
    self.searchBox.TextXAlignment = Enum.TextXAlignment.Left
    self.searchBox.ClearTextOnFocus = false
    self.searchBox.ZIndex = 103
    self.searchBox.Parent = searchBG
    
    -- Search functionality
    self.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        self.searchTerm = self.searchBox.Text:lower()
        self:_updateItemsDisplay()
    end)
end

function InventoryPanel:_createItemsGrid()
    local theme = uiConfig.helpers.get_theme(uiConfig)
    
    -- Items scroll frame
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ItemsScroll"
    scrollFrame.Size = UDim2.new(1, -40, 1, -210)
    scrollFrame.Position = UDim2.new(0, 20, 0, 200)
    scrollFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 8
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(52, 152, 219)
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.ZIndex = 101
    scrollFrame.Parent = self.frame
    
    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 15)
    scrollCorner.Parent = scrollFrame
    
    -- Grid layout
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, 110, 0, 110)
    gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = scrollFrame
    
    -- Padding
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 15)
    padding.PaddingBottom = UDim.new(0, 15)
    padding.PaddingLeft = UDim.new(0, 15)
    padding.PaddingRight = UDim.new(0, 15)
    padding.Parent = scrollFrame
    
    -- Update canvas size when layout changes
    gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, gridLayout.AbsoluteContentSize.Y + 30)
    end)
    
    self.itemsGrid = scrollFrame
end

function InventoryPanel:_generateSampleData()
    local rarityColors = {
        Common = Color3.fromRGB(150, 150, 150),
        Uncommon = Color3.fromRGB(30, 255, 0),
        Rare = Color3.fromRGB(0, 112, 255),
        Epic = Color3.fromRGB(163, 53, 238),
        Legendary = Color3.fromRGB(255, 128, 0),
        Mythical = Color3.fromRGB(255, 0, 0)
    }
    
    local items = {}
    local petIcons = {"🐶", "🐱", "🐼", "🦊", "🐯", "🐸", "🐷", "🐨", "🐵", "🦁"}
    local rarities = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical"}
    
    -- Generate random pets
    for i = 1, 60 do
        local rarity = rarities[math.random(1, #rarities)]
        table.insert(items, {
            id = "pet_" .. i,
            name = "Pet " .. i,
            icon = petIcons[math.random(1, #petIcons)],
            rarity = rarity,
            color = rarityColors[rarity],
            category = "Pets",
            count = 1,
            power = math.random(100, 999)
        })
    end
    
    return items
end

function InventoryPanel:_updateItemsDisplay()
    -- Clear existing items
    for _, frame in pairs(self.itemFrames) do
        frame:Destroy()
    end
    self.itemFrames = {}
    
    -- Filter items
    local filteredItems = {}
    for _, item in ipairs(self.inventoryData) do
        local matchesCategory = (self.selectedCategory == "All" or item.category == self.selectedCategory)
        local matchesSearch = (self.searchTerm == "" or item.name:lower():find(self.searchTerm, 1, true))
        
        if matchesCategory and matchesSearch then
            table.insert(filteredItems, item)
        end
    end
    
    -- Create item frames
    for i, item in ipairs(filteredItems) do
        self:_createItemFrame(item, i)
    end
end

function InventoryPanel:_createItemFrame(item, layoutOrder)
    -- Item frame
    local itemFrame = Instance.new("Frame")
    itemFrame.Name = item.id
    itemFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    itemFrame.BorderSizePixel = 0
    itemFrame.LayoutOrder = layoutOrder
    itemFrame.ZIndex = 102
    itemFrame.Parent = self.itemsGrid
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = itemFrame
    
    -- Rarity border
    local stroke = Instance.new("UIStroke")
    stroke.Color = item.color
    stroke.Thickness = 2
    stroke.Transparency = 0.3
    stroke.Parent = itemFrame
    
    -- Background gradient
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 55, 65)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 45, 55))
    }
    gradient.Rotation = 45
    gradient.Parent = itemFrame
    
    -- Item icon background
    local iconBG = Instance.new("Frame")
    iconBG.Size = UDim2.new(0, 60, 0, 60)
    iconBG.Position = UDim2.new(0.5, -30, 0, 10)
    iconBG.BackgroundColor3 = item.color
    iconBG.BackgroundTransparency = 0.8
    iconBG.BorderSizePixel = 0
    iconBG.ZIndex = 103
    iconBG.Parent = itemFrame
    
    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(0, 30)
    iconCorner.Parent = iconBG
    
    -- Item icon
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 40, 0, 40)
    icon.Position = UDim2.new(0.5, -20, 0.5, -20)
    icon.BackgroundTransparency = 1
    icon.Text = item.icon
    icon.TextScaled = true
    icon.Font = Enum.Font.GothamBold
    icon.ZIndex = 104
    icon.Parent = iconBG
    
    -- Item name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -10, 0, 20)
    nameLabel.Position = UDim2.new(0, 5, 0, 75)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = item.name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.ZIndex = 103
    nameLabel.Parent = itemFrame
    
    -- Power/stats
    local powerLabel = Instance.new("TextLabel")
    powerLabel.Size = UDim2.new(1, -10, 0, 15)
    powerLabel.Position = UDim2.new(0, 5, 1, -20)
    powerLabel.BackgroundTransparency = 1
    powerLabel.Text = "⚡ " .. item.power
    powerLabel.TextColor3 = item.color
    powerLabel.TextScaled = true
    powerLabel.Font = Enum.Font.Gotham
    powerLabel.ZIndex = 103
    powerLabel.Parent = itemFrame
    
    -- Hover effects
    self:_addItemHoverEffect(itemFrame)
    
    -- Store reference
    table.insert(self.itemFrames, itemFrame)
end

function InventoryPanel:_selectCategory(categoryName)
    self.selectedCategory = categoryName
    
    -- Update category tabs visual state
    local categoryContainer = self.frame:FindFirstChild("CategoryContainer")
    if categoryContainer then
        for _, tab in ipairs(categoryContainer:GetChildren()) do
            if tab:IsA("TextButton") then
                local isSelected = tab.Name:find(categoryName)
                tab.BackgroundColor3 = isSelected and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(40, 40, 50)
            end
        end
    end
    
    -- Update items display
    self:_updateItemsDisplay()
end

function InventoryPanel:_addButtonHoverEffect(button, originalColor)
    button.MouseEnter:Connect(function()
        local tween = TweenService:Create(button, 
            TweenInfo.new(0.15, Enum.EasingStyle.Quad), 
            {BackgroundColor3 = Color3.new(
                math.min(1, originalColor.R + 0.1),
                math.min(1, originalColor.G + 0.1),
                math.min(1, originalColor.B + 0.1)
            )}
        )
        tween:Play()
    end)
    
    button.MouseLeave:Connect(function()
        local tween = TweenService:Create(button, 
            TweenInfo.new(0.15, Enum.EasingStyle.Quad), 
            {BackgroundColor3 = originalColor}
        )
        tween:Play()
    end)
end

function InventoryPanel:_addItemHoverEffect(itemFrame)
    local originalSize = itemFrame.Size
    local stroke = itemFrame:FindFirstChild("UIStroke")
    
    itemFrame.MouseEnter:Connect(function()
        local sizeTween = TweenService:Create(itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset + 5, originalSize.Y.Scale, originalSize.Y.Offset + 5)}
        )
        sizeTween:Play()
        
        if stroke then
            local strokeTween = TweenService:Create(stroke,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                {Transparency = 0, Thickness = 3}
            )
            strokeTween:Play()
        end
    end)
    
    itemFrame.MouseLeave:Connect(function()
        local sizeTween = TweenService:Create(itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {Size = originalSize}
        )
        sizeTween:Play()
        
        if stroke then
            local strokeTween = TweenService:Create(stroke,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                {Transparency = 0.3, Thickness = 2}
            )
            strokeTween:Play()
        end
    end)
end

function InventoryPanel:_animateEntrance()
    -- Start slightly off-screen and transparent
    self.frame.Position = UDim2.new(0.5, 0, 0.5, 50)
    self.frame.BackgroundTransparency = 1
    
    -- Animate to final position
    local tween = TweenService:Create(self.frame,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(0.5, 0, 0.5, 0),
            BackgroundTransparency = 0
        }
    )
    tween:Play()
end

-- Public interface methods
function InventoryPanel:IsVisible()
    return self.isVisible
end

function InventoryPanel:GetFrame()
    return self.frame
end

function InventoryPanel:UpdateInventory(newData)
    if newData then
        self.inventoryData = newData
        if self.isVisible then
            self:_updateItemsDisplay()
        end
    end
end

function InventoryPanel:Destroy()
    self:Hide()
    self.logger:info("Professional inventory panel destroyed")
end

return InventoryPanel 