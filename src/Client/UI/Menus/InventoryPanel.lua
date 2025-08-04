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
    
    -- Load inventory configuration
    local ConfigLoader = require(ReplicatedStorage.Shared.ConfigLoader)
    local success, result = pcall(function()
        return ConfigLoader:LoadConfig("inventory")
    end)
    
    if success then
        self.inventoryConfig = result
        self.logger:info("📁 INVENTORY CONFIG LOADED", {
            hasDisplayCategories = self.inventoryConfig.display_categories ~= nil,
            categoryCount = self.inventoryConfig.display_categories and #self.inventoryConfig.display_categories or 0,
            hasCategorySettings = self.inventoryConfig.category_settings ~= nil
        })
    else
        self.logger:error("❌ FAILED TO LOAD INVENTORY CONFIG", {error = result})
        self.inventoryConfig = nil
    end
    
    -- Load context menu configuration
    local contextSuccess, contextResult = pcall(function()
        return ConfigLoader:LoadConfig("context_menus")
    end)
    
    if contextSuccess then
        self.contextMenuConfig = contextResult
        self.logger:info("🖱️ CONTEXT MENU CONFIG LOADED", {
            hasItemTypes = self.contextMenuConfig.item_types ~= nil,
            itemTypeCount = self.contextMenuConfig.item_types and #self.contextMenuConfig.item_types or 0
        })
    else
        self.logger:error("❌ FAILED TO LOAD CONTEXT MENU CONFIG", {error = contextResult})
        self.contextMenuConfig = nil
    end
    
    -- Panel state
    self.isVisible = false
    self.frame = nil
    self.searchBox = nil
    self.itemsGrid = nil
    self.itemFrames = {}
    self.selectedCategory = "All"
    self.searchTerm = ""
    
    -- Initialize with empty data - will be populated from real inventory
    self.inventoryData = {}
    
    -- Get reference to player for inventory access
    self.player = Players.LocalPlayer
    
    -- Initialize networking  
    self.signals = nil
    self:_initializeNetworking()
    
    return self
end

function InventoryPanel:Show(parent)
    if self.isVisible then return end
    
    self:_createUI(parent)
    self:_loadRealInventoryData() -- Load real data first
    self:_refreshCategoryTabs() -- Update category tabs with real counts
    self:_setupEquippedFolderListeners() -- Listen for equipped changes
    self:_updateItemsDisplay()
    self:SetupRealTimeUpdates() -- Listen for inventory changes
    
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
    
    -- Get categories from configuration
    local categories = self:_getConfiguredCategories()
    
    for i, category in ipairs(categories) do
        self:_createCategoryTab(category, categoryContainer, i)
    end
end

function InventoryPanel:_refreshCategoryTabs()
    -- Find the category container and update the counts
    local categoryContainer = self.frame:FindFirstChild("CategoryContainer")
    if not categoryContainer then return end
    
    -- Get configured categories with updated counts
    local categories = self:_getConfiguredCategories()
    
    -- Update each category tab's count display
    for _, category in ipairs(categories) do
        local tab = categoryContainer:FindFirstChild(category.name .. "Tab")
        if tab then
            local content = tab:FindFirstChild("Frame") -- Content frame name might be different
            if not content then
                -- Try to find by class
                for _, child in pairs(tab:GetChildren()) do
                    if child:IsA("Frame") and child.BackgroundTransparency == 1 then
                        content = child
                        break
                    end
                end
            end
            
            if content then
                -- Find the count label (it's positioned at Y=20)
                for _, child in pairs(content:GetChildren()) do
                    if child:IsA("TextLabel") and child.Position.Y.Offset == 20 then
                        child.Text = category.count .. " items"
                        break
                    end
                end
            end
        end
    end
    
    self.logger:info("🔄 CONFIGURED CATEGORY TABS REFRESHED", {
        categoriesUpdated = #categories
    })
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

-- 🔧 CONFIGURATION-DRIVEN CATEGORIES
function InventoryPanel:_getConfiguredCategories()
    local categories = {}
    
    if not self.inventoryConfig or not self.inventoryConfig.display_categories then
        self.logger:warn("No inventory config found, using fallback categories")
        return self:_getFallbackCategories()
    end
    
    -- Get category counts by folder mapping
    local folderCounts = self:_calculateFolderCounts()
    
    -- Process each configured category
    for _, categoryConfig in ipairs(self.inventoryConfig.display_categories) do
        local totalCount = 0
        
        -- Sum counts for all folders in this category
        for _, folderName in ipairs(categoryConfig.folders) do
            totalCount = totalCount + (folderCounts[folderName] or 0)
        end
        
        -- Check if category should be visible
        local shouldShow = categoryConfig.always_visible or totalCount > 0
        local hideEmptyCategories = self.inventoryConfig.category_settings and 
                                   self.inventoryConfig.category_settings.hide_empty_categories
        if not hideEmptyCategories then
            shouldShow = true -- Show all categories if hiding is disabled
        end
        
        -- TEMPORARY: Force show all categories for debugging
        shouldShow = true
        
        self.logger:info("🔍 CATEGORY VISIBILITY", {
            categoryName = categoryConfig.name,
            totalCount = totalCount,
            always_visible = categoryConfig.always_visible,
            shouldShow = shouldShow,
            folders = categoryConfig.folders
        })
        
        if shouldShow then
            local categoryData = {
                name = categoryConfig.name,
                icon = categoryConfig.icon,
                description = categoryConfig.description,
                folders = categoryConfig.folders,
                count = totalCount,
                order = categoryConfig.display_order
            }
            
            table.insert(categories, categoryData)
        end
    end
    
    -- Sort by display_order
    table.sort(categories, function(a, b)
        return a.order < b.order
    end)
    
    -- Create category summary for logging
    local categorySummary = {}
    for _, cat in ipairs(categories) do
        table.insert(categorySummary, cat.name .. " (" .. cat.count .. " items)")
    end
    
    self.logger:info("📁 CONFIGURED CATEGORIES", {
        count = #categories,
        categoryNames = categorySummary,
        fullCategories = categories
    })
    
    return categories
end

function InventoryPanel:_getFallbackCategories()
    -- Fallback categories if config fails to load
    local categoryCounts = self:_calculateCategoryCounts()
    return {
        { name = "All", icon = "📦", count = categoryCounts.total, folders = {"pets", "consumables", "tools", "eggs"} },
        { name = "Pets", icon = "🐾", count = categoryCounts.pets, folders = {"pets"} },
        { name = "Items", icon = "⚡", count = categoryCounts.items, folders = {"consumables"} },
        { name = "Eggs", icon = "🥚", count = categoryCounts.eggs, folders = {"eggs"} },
        { name = "Tools", icon = "🔧", count = categoryCounts.tools, folders = {"tools"} }
    }
end

function InventoryPanel:_calculateFolderCounts()
    local folderCounts = {}
    
    -- Count items by their folder origin
    for _, item in ipairs(self.inventoryData) do
        local folderName = item.folder_source or "unknown"
        folderCounts[folderName] = (folderCounts[folderName] or 0) + 1
    end
    
    self.logger:info("📊 FOLDER COUNTS DEBUG", folderCounts)
    
    return folderCounts
end

-- 📊 CATEGORY COUNTING (Legacy - now used for fallback)
function InventoryPanel:_calculateCategoryCounts()
    local counts = {
        total = 0,
        pets = 0,
        items = 0,      -- Consumables/potions
        eggs = 0,
        tools = 0
    }
    
    -- Count from real inventory data
    for _, item in ipairs(self.inventoryData) do
        counts.total = counts.total + 1
        
        -- Categorize based on item category
        if item.category == "Pets" then
            counts.pets = counts.pets + 1
        elseif item.category == "Items" or item.category == "Consumables" then
            counts.items = counts.items + 1
        elseif item.category == "Eggs" then
            counts.eggs = counts.eggs + 1
        elseif item.category == "Tools" then
            counts.tools = counts.tools + 1
        end
    end
    
    self.logger:info("📊 CATEGORY COUNTS", {
        total = counts.total,
        pets = counts.pets,
        items = counts.items,
        eggs = counts.eggs,
        tools = counts.tools
    })
    
    return counts
end

-- 🔄 REAL DATA LOADING
function InventoryPanel:_loadRealInventoryData()
    self.inventoryData = {}
    
    -- Try to find inventory folder in player
    local inventoryFolder = self.player:FindFirstChild("Inventory")
    if not inventoryFolder then
        self.logger:warn("No inventory folder found for player")
        -- Fallback to sample data for testing
        self.inventoryData = self:_generateSampleData()
        return
    end
    
    local inventoryChildren = {}
    for _, child in pairs(inventoryFolder:GetChildren()) do
        table.insert(inventoryChildren, child.Name)
    end
    
    self.logger:info("🔍 INVENTORY DEBUG - Found inventory folder", {
        children = inventoryChildren
    })
    
    -- Load pets from pets folder
    local petsFolder = inventoryFolder:FindFirstChild("pets")
    if petsFolder then
        local petsChildren = {}
        for _, child in pairs(petsFolder:GetChildren()) do
            table.insert(petsChildren, child.Name)
        end
        
        self.logger:info("🐾 PETS DEBUG - Found pets folder", {
            childCount = #petsFolder:GetChildren(),
            children = petsChildren
        })
        
        self:_loadPetsFromFolder(petsFolder)
    else
        self.logger:warn("🚫 PETS DEBUG - No pets folder found")
    end
    
    -- Load consumables from consumables folder
    local consumablesFolder = inventoryFolder:FindFirstChild("consumables")
    if consumablesFolder then
        self:_loadConsumablesFromFolder(consumablesFolder)
    else
        self.logger:info("📦 CONSUMABLES DEBUG - No consumables folder found")
    end
    
    -- Load tools from tools folder  
    local toolsFolder = inventoryFolder:FindFirstChild("tools")
    if toolsFolder then
        self:_loadToolsFromFolder(toolsFolder)
    else
        self.logger:info("🔧 TOOLS DEBUG - No tools folder found")
    end
    
    -- Load eggs from eggs folder
    local eggsFolder = inventoryFolder:FindFirstChild("eggs")
    if eggsFolder then
        self:_loadEggsFromFolder(eggsFolder)
    else
        self.logger:info("🥚 EGGS DEBUG - No eggs folder found")
    end
    
    self.logger:info("✅ INVENTORY DEBUG - Loaded real inventory data", {
        totalItems = #self.inventoryData,
        hasInventoryFolder = inventoryFolder ~= nil,
        hasPetsFolder = petsFolder ~= nil,
        sampleItems = self.inventoryData[1] and {
            name = self.inventoryData[1].name,
            folder_source = self.inventoryData[1].folder_source,
            category = self.inventoryData[1].category
        } or "no items"
    })
end

function InventoryPanel:_loadPetsFromFolder(petsFolder)
    -- Get rarity colors for display
    local rarityColors = {
        basic = Color3.fromRGB(150, 150, 150),    -- Gray
        golden = Color3.fromRGB(255, 215, 0),     -- Gold  
        rainbow = Color3.fromRGB(255, 0, 255)     -- Magenta
    }
    
    -- Get pet emoji mapping
    local petIcons = {
        bear = "🐻",
        bunny = "🐰", 
        doggy = "🐶",
        kitty = "🐱",
        dragon = "🐉"
    }
    
    -- Iterate through all pet folders
    for _, petFolder in pairs(petsFolder:GetChildren()) do
        if petFolder:IsA("Folder") and petFolder.Name ~= "Info" then
            -- Extract pet data from folder structure
            local petData = self:_extractPetDataFromFolder(petFolder)
            if petData then
                -- Convert to inventory display format
                local displayData = {
                    id = petFolder.Name,                           -- UID
                    name = petData.id:gsub("^%l", string.upper),   -- Capitalize pet name
                    icon = petIcons[petData.id] or "🐾",          -- Emoji fallback
                    rarity = petData.variant:gsub("^%l", string.upper), -- Capitalize variant
                    color = rarityColors[petData.variant] or rarityColors.basic,
                    category = "Pets",
                    count = 1, -- Pets don't stack
                    power = petData.stats and petData.stats.power or 100,
                    level = petData.level or 1,
                    uid = petFolder.Name, -- Store UID for future operations
                    folder_source = "pets", -- Track which folder this came from
                    
                    -- 3D Model data for viewport display
                    petType = petData.id,                          -- Pet type for model loading
                    variant = petData.variant,                     -- Variant for model loading
                    use3DModel = true                              -- Flag to use 3D model instead of emoji
                }
                
                table.insert(self.inventoryData, displayData)
                self.logger:info("🐾 LOADED PET", {
                    name = displayData.name,
                    folder_source = displayData.folder_source,
                    category = displayData.category,
                    petType = displayData.petType
                })
            end
        end
    end
end

function InventoryPanel:_loadConsumablesFromFolder(consumablesFolder)
    -- Map item IDs to appropriate icons
    local itemIcons = {
        health_potion = "❤️",
        speed_potion = "⚡",
        trader_scroll = "📜",
        premium_boost = "💎",
        test_item = "🧪"
    }
    
    -- Iterate through all consumable items
    for _, itemFolder in pairs(consumablesFolder:GetChildren()) do
        if itemFolder:IsA("Folder") and itemFolder.Name ~= "Info" then
            local itemData = self:_extractConsumableDataFromFolder(itemFolder)
            if itemData then
                local displayData = {
                    id = itemFolder.Name,
                    name = itemData.id:gsub("_", " "):gsub("^%l", string.upper),
                    icon = itemIcons[itemData.id] or "🧪", -- Item-specific icon or fallback
                    rarity = "Common",
                    color = Color3.fromRGB(150, 150, 150),
                    category = "Items",
                    count = itemData.quantity or 1,
                    uid = itemFolder.Name,
                    folder_source = "consumables" -- Track which folder this came from
                }
                table.insert(self.inventoryData, displayData)
                self.logger:info("🧪 LOADED CONSUMABLE", {
                    name = displayData.name,
                    folder_source = displayData.folder_source,
                    category = displayData.category,
                    count = displayData.count
                })
            end
        end
    end
end

function InventoryPanel:_loadToolsFromFolder(toolsFolder)
    -- Map tool IDs to appropriate icons
    local toolIcons = {
        basic_pickaxe = "⛏️",
        iron_pickaxe = "⛏️",
        diamond_pickaxe = "💎",
        wooden_sword = "🗡️",
        iron_sword = "⚔️",
        diamond_sword = "💎",
        crystal_staff = "🔮"
    }
    
    -- Iterate through all tool items
    for _, itemFolder in pairs(toolsFolder:GetChildren()) do
        if itemFolder:IsA("Folder") and itemFolder.Name ~= "Info" then
            local itemData = self:_extractToolDataFromFolder(itemFolder)
            if itemData then
                local displayData = {
                    id = itemFolder.Name,
                    name = itemData.id:gsub("_", " "):gsub("^%l", string.upper),
                    icon = toolIcons[itemData.id] or "🔧", -- Tool-specific icon or fallback
                    rarity = "Common",
                    color = Color3.fromRGB(150, 150, 150),
                    category = "Tools",
                    count = 1,
                    uid = itemFolder.Name,
                    folder_source = "tools" -- Track which folder this came from
                }
                table.insert(self.inventoryData, displayData)
            end
        end
    end
end

function InventoryPanel:_loadEggsFromFolder(eggsFolder)
    -- Iterate through all egg items
    for _, itemFolder in pairs(eggsFolder:GetChildren()) do
        if itemFolder:IsA("Folder") and itemFolder.Name ~= "Info" then
            local itemData = self:_extractEggDataFromFolder(itemFolder)
            if itemData then
                local displayData = {
                    id = itemFolder.Name,
                    name = itemData.id:gsub("_", " "):gsub("^%l", string.upper),
                    icon = "🥚",
                    rarity = "Common",
                    color = Color3.fromRGB(150, 150, 150),
                    category = "Eggs",
                    count = itemData.quantity or 1,
                    uid = itemFolder.Name,
                    folder_source = "eggs" -- Track which folder this came from
                }
                table.insert(self.inventoryData, displayData)
            end
        end
    end
end

function InventoryPanel:_extractConsumableDataFromFolder(itemFolder)
    local itemData = {}
    
    local itemId = itemFolder:FindFirstChild("ItemId")
    local quantity = itemFolder:FindFirstChild("Quantity")
    
    if not itemId then
        return nil
    end
    
    itemData.id = itemId.Value
    itemData.quantity = quantity and quantity.Value or 1
    
    return itemData
end

function InventoryPanel:_extractToolDataFromFolder(itemFolder)
    local itemData = {}
    
    local itemId = itemFolder:FindFirstChild("ItemId")
    if not itemId then
        return nil
    end
    
    itemData.id = itemId.Value
    
    return itemData
end

function InventoryPanel:_extractEggDataFromFolder(itemFolder)
    local itemData = {}
    
    local itemId = itemFolder:FindFirstChild("ItemId")
    local quantity = itemFolder:FindFirstChild("Quantity")
    
    if not itemId then
        return nil
    end
    
    itemData.id = itemId.Value
    itemData.quantity = quantity and quantity.Value or 1
    
    return itemData
end

-- 🎮 3D PET ICON CREATION
function InventoryPanel:_create3DPetIcon(parent, item)
    self.logger:info("🎮 CREATING VIEWPORT", {itemId = item.id, petType = item.petType, variant = item.variant})
    
    -- Create ViewportFrame for 3D model
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "PetViewport"
    viewport.Size = UDim2.new(1, 0, 1, 0)  -- Fill the iconBG
    viewport.Position = UDim2.new(0, 0, 0, 0)
    viewport.BackgroundTransparency = 1
    viewport.ZIndex = 104
    viewport.Parent = parent
    
    self.logger:info("📹 VIEWPORT CREATED", {itemId = item.id})
    
    -- Create camera
    local camera = Instance.new("Camera")
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    
    self.logger:info("📷 CAMERA CREATED", {itemId = item.id})
    
    -- Load the 3D model
    self:_load3DPetModel(viewport, camera, item)
    
    return viewport
end

function InventoryPanel:_createEmojiFallback(viewport, item)
    -- Create emoji icon as fallback when 3D model fails
    local fallbackIcon = Instance.new("TextLabel")
    fallbackIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
    fallbackIcon.Position = UDim2.new(0.1, 0, 0.1, 0)
    fallbackIcon.BackgroundTransparency = 1
    fallbackIcon.Text = item.icon
    fallbackIcon.TextScaled = true
    fallbackIcon.Font = Enum.Font.GothamBold
    fallbackIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
    fallbackIcon.ZIndex = 105
    fallbackIcon.Parent = viewport
end

function InventoryPanel:_load3DPetModel(viewport, camera, item)
    local InsertService = game:GetService("InsertService")
    local Locations = require(game:GetService("ReplicatedStorage").Shared.Locations)
    local petConfig = Locations.getConfig("pets")
    
    task.spawn(function()
        local success, result = pcall(function()
            -- Get pet data from config
            local petData = petConfig.getPet(item.petType, item.variant)
            if not petData or not petData.asset_id then
                self.logger:warn("No pet data or asset ID found", {
                    petType = item.petType,
                    variant = item.variant
                })
                return
            end
            
            -- Try to load from ReplicatedStorage.Assets first (like egg system)
            local modelClone = nil
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
            
            if assetsFolder then
                local modelsFolder = assetsFolder:FindFirstChild("Models")
                if modelsFolder then
                    local petsFolder = modelsFolder:FindFirstChild("Pets")
                    if petsFolder then
                        local petTypeFolder = petsFolder:FindFirstChild(item.petType)
                        if petTypeFolder then
                            local petModel = petTypeFolder:FindFirstChild(item.variant)
                            if petModel then
                                modelClone = petModel:Clone()
                                self.logger:debug("Loaded pet model from ReplicatedStorage.Assets", {
                                    petType = item.petType,
                                    variant = item.variant,
                                    path = petModel:GetFullName()
                                })
                            end
                        end
                    end
                end
            end
            
            -- Fallback to InsertService loading
            if not modelClone then
                local assetId = petData.asset_id
                if assetId and assetId ~= "rbxassetid://0" then
                    local assetNumber = tonumber(assetId:match("%d+"))
                    if assetNumber then
                        local asset = InsertService:LoadAsset(assetNumber)
                        modelClone = asset:FindFirstChildOfClass("Model")
                        if modelClone then
                            modelClone = modelClone:Clone()
                            self.logger:debug("Loaded pet model from InsertService", {
                                assetId = assetId,
                                petType = item.petType,
                                variant = item.variant
                            })
                        end
                        asset:Destroy()
                    end
                end
            end
            
            if not modelClone then
                self.logger:warn("Failed to load pet model, creating emoji fallback", {
                    petType = item.petType,
                    variant = item.variant,
                    assetId = petData.asset_id
                })
                
                -- Create emoji fallback in the viewport
                self:_createEmojiFallback(viewport, item)
                return
            end
            
            -- Position model in viewport
            local modelCFrame = CFrame.new(0, 0, 0)
            if modelClone.PrimaryPart then
                modelClone:SetPrimaryPartCFrame(modelCFrame)
            else
                modelClone:MoveTo(modelCFrame.Position)
            end
            
            modelClone.Parent = viewport
            
            -- Calculate camera position
            local modelSize = modelClone:GetExtentsSize()
            local zoomMultiplier = petData.viewport_zoom or 1.5
            local baseDistance = math.max(modelSize.X, modelSize.Y, modelSize.Z) * 1.2  -- Slightly closer for inventory
            local distance = baseDistance / zoomMultiplier
            
            -- Safety clamp
            if distance < 1 then distance = 1 end
            
            local modelPosition = modelClone:GetBoundingBox().Position
            
            -- Set up rotating camera (like egg system)
            local cameraAngle = 0
            local rotationSpeed = 2 -- degrees per frame
            local connection
            
            connection = game:GetService("RunService").Heartbeat:Connect(function()
                if viewport.Parent and modelClone.Parent then
                    -- Rotate camera around the model
                    camera.CFrame = CFrame.Angles(0, math.rad(cameraAngle), 0) * CFrame.new(modelPosition + Vector3.new(0, 0, distance), modelPosition)
                    cameraAngle = cameraAngle + rotationSpeed
                    if cameraAngle >= 360 then
                        cameraAngle = 0
                    end
                else
                    -- Clean up if viewport or model is destroyed
                    connection:Disconnect()
                end
            end)
            
            self.logger:info("3D pet model loaded in inventory", {
                petType = item.petType,
                variant = item.variant,
                modelSize = modelSize,
                distance = distance
            })
            
        end)
        
        if not success then
            self.logger:warn("Failed to load 3D pet model, creating emoji fallback", {
                error = result,
                petType = item.petType,
                variant = item.variant
            })
            
            -- Create emoji fallback on error
            self:_createEmojiFallback(viewport, item)
        end
    end)
end

function InventoryPanel:_extractPetDataFromFolder(petFolder)
    local petData = {}
    
    -- Required fields (match what InventoryService actually creates)
    local itemId = petFolder:FindFirstChild("ItemId")  -- Changed from "PetType"
    local variant = petFolder:FindFirstChild("variant")  -- Changed from "Variant" (case)
    
    if not itemId or not variant then
        self.logger:warn("Invalid pet folder structure", {
            folderName = petFolder.Name,
            hasItemId = itemId ~= nil,
            hasVariant = variant ~= nil,
            children = {}
        })
        
        -- Debug: List all children to see what's actually there
        local actualChildren = {}
        for _, child in pairs(petFolder:GetChildren()) do
            table.insert(actualChildren, child.Name .. " (" .. child.ClassName .. ")")
        end
        
        self.logger:warn("🔍 PET FOLDER DEBUG - Available children", {
            folderName = petFolder.Name,
            children = actualChildren
        })
        
        return nil
    end
    
    petData.id = itemId.Value
    petData.variant = variant.Value
    
    -- Optional fields
    local level = petFolder:FindFirstChild("level")  -- Changed case
    if level then petData.level = level.Value end
    
    -- Stats are in a folder structure
    local statsFolder = petFolder:FindFirstChild("stats")
    if statsFolder and statsFolder:IsA("Folder") then
        petData.stats = {}
        
        local power = statsFolder:FindFirstChild("power")
        if power then petData.stats.power = power.Value end
        
        local health = statsFolder:FindFirstChild("health")
        if health then petData.stats.health = health.Value end
        
        local speed = statsFolder:FindFirstChild("speed")
        if speed then petData.stats.speed = speed.Value end
    else
        -- Fallback: try direct children (in case structure is different)
        local power = petFolder:FindFirstChild("power")
        local health = petFolder:FindFirstChild("health") 
        local speed = petFolder:FindFirstChild("speed")
        
        if power or health or speed then
            petData.stats = {
                power = power and power.Value or 100,
                health = health and health.Value or 100,
                speed = speed and speed.Value or 1.0
            }
        end
    end
    
    local nickname = petFolder:FindFirstChild("nickname")  -- Changed case
    if nickname then petData.nickname = nickname.Value end
    
    return petData
end

function InventoryPanel:_updateItemsDisplay()
    -- Cleanup old right-click connections to prevent memory leaks
    if self._rightClickConnections then
        for itemId, connection in pairs(self._rightClickConnections) do
            if connection then
                connection:Disconnect()
            end
        end
        self._rightClickConnections = {}
    end
    
    -- Clear existing items
    for _, frame in pairs(self.itemFrames) do
        frame:Destroy()
    end
    self.itemFrames = {}
    
    -- Get current category folders for filtering
    local categoryFolders = self:_getCategoryFolders(self.selectedCategory)
    
    -- Filter items
    local filteredItems = {}
    for _, item in ipairs(self.inventoryData) do
        local matchesCategory = self:_itemMatchesCategory(item, self.selectedCategory, categoryFolders)
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

function InventoryPanel:_getCategoryFolders(categoryName)
    -- Get folders that belong to the selected category
    if not self.inventoryConfig or not self.inventoryConfig.display_categories then
        -- Fallback mapping for legacy categories
        local fallbackMapping = {
            All = {"pets", "consumables", "tools", "eggs", "resources"},
            Pets = {"pets"},
            Items = {"consumables"},
            Eggs = {"eggs"},
            Tools = {"tools"},
            Resources = {"resources"}
        }
        return fallbackMapping[categoryName] or {}
    end
    
    -- Find the category in configuration
    for _, categoryConfig in ipairs(self.inventoryConfig.display_categories) do
        if categoryConfig.name == categoryName then
            return categoryConfig.folders
        end
    end
    
    return {}
end

function InventoryPanel:_itemMatchesCategory(item, categoryName, categoryFolders)
    -- "All" category shows everything
    if categoryName == "All" then
        return true
    end
    
    -- Check if item's folder source is in the category's folder list
    if item.folder_source then
        for _, folderName in ipairs(categoryFolders) do
            if item.folder_source == folderName then
                self.logger:debug("✅ FILTER MATCH", {
                    item = item.name,
                    category = categoryName,
                    folder_source = item.folder_source,
                    matched_folder = folderName
                })
                return true
            end
        end
        self.logger:debug("❌ FILTER NO MATCH", {
            item = item.name,
            category = categoryName,
            folder_source = item.folder_source,
            available_folders = categoryFolders
        })
        return false -- Don't fall back to legacy if folder_source exists
    end
    
    -- Fallback: check legacy category field (only if no folder_source)
    local legacyMatch = item.category == categoryName
    self.logger:debug("🔄 FILTER LEGACY", {
        item = item.name,
        category = categoryName,
        item_category = item.category,
        matched = legacyMatch
    })
    return legacyMatch
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
    
    -- Item icon (3D model or emoji fallback)
    self.logger:info("🎨 CREATING ICON", {
        itemId = item.id,
        use3DModel = item.use3DModel,
        petType = item.petType,
        variant = item.variant,
        icon = item.icon
    })
    
    if item.use3DModel then
        -- Create 3D ViewportFrame
        self.logger:info("🎮 CREATING 3D MODEL", {itemId = item.id, petType = item.petType})
        local viewport = self:_create3DPetIcon(iconBG, item)
    else
        -- Use emoji fallback
        self.logger:info("🎭 USING EMOJI FALLBACK", {itemId = item.id, icon = item.icon})
        local icon = Instance.new("TextLabel")
        icon.Size = UDim2.new(0, 40, 0, 40)
        icon.Position = UDim2.new(0.5, -20, 0.5, -20)
        icon.BackgroundTransparency = 1
        icon.Text = item.icon
        icon.TextScaled = true
        icon.Font = Enum.Font.GothamBold
        icon.ZIndex = 104
        icon.Parent = iconBG
    end
    
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
    
    -- Power/stats or quantity display
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -10, 0, 15)
    infoLabel.Position = UDim2.new(0, 5, 1, -20)
    infoLabel.BackgroundTransparency = 1
    
    -- Display different info based on item type
    if item.power then
        -- Pets and tools show power
        infoLabel.Text = "⚡ " .. tostring(item.power)
    elseif item.count and item.count > 1 then
        -- Consumables show quantity
        infoLabel.Text = "×" .. tostring(item.count)
    else
        -- Default for single items
        infoLabel.Text = "×1"
    end
    
    infoLabel.TextColor3 = item.color
    infoLabel.TextScaled = true
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.ZIndex = 103
    infoLabel.Parent = itemFrame
    
    -- Add interaction system (includes hover effects)
    print("🔧 ABOUT TO ADD INTERACTIONS FOR:", item.id, item.name)
    self.logger:info("🔧 ABOUT TO ADD INTERACTIONS", {itemId = item.id, itemName = item.name})
    self:_addItemInteractions(itemFrame, item)
    print("✅ INTERACTIONS ADDED FOR:", item.id)
    self.logger:info("✅ INTERACTIONS ADDED", {itemId = item.id})
    
    -- Apply equipped styling if item is equipped
    local isEquipped = self:_isItemEquipped(item)
    self:_applyEquippedStyling(itemFrame, isEquipped, item.color)
    
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

-- 🔄 REAL-TIME INVENTORY UPDATES
function InventoryPanel:RefreshFromRealData()
    if self.isVisible then
        self:_loadRealInventoryData()
        self:_refreshCategoryTabs() -- Update category counts too
        self:_updateItemsDisplay()
        self.logger:info("Inventory refreshed from real data")
    end
end

-- 🖱️ ITEM INTERACTION SYSTEM
function InventoryPanel:_addItemInteractions(itemFrame, item)
    print("🖱️ INSIDE _addItemInteractions FOR:", item.id, "hasSignals:", self.signals ~= nil)
    self.logger:info("🔧 ADDING INTERACTIONS", {
        itemId = item.id,
        itemName = item.name,
        hasSignals = self.signals ~= nil
    })
    
    -- Left-click: Primary action (consume/equip)
    local leftClickDetection = Instance.new("TextButton")
    leftClickDetection.Size = UDim2.new(1, 0, 1, 0)
    leftClickDetection.BackgroundTransparency = 1
    leftClickDetection.Text = ""
    leftClickDetection.ZIndex = 105
    leftClickDetection.Parent = itemFrame
    
    leftClickDetection.Activated:Connect(function()
        print("🖱️ LEFT CLICK DETECTED ON:", item.id)
        self.logger:info("🖱️ LEFT CLICK DETECTED", {itemId = item.id})
        self:_handlePrimaryAction(item)
    end)
    
    -- Right-click: Context menu (using UserInputService with frame detection)
    local isMouseOverFrame = false
    
    -- Global right-click detection (but only act if over this frame)
    local userInputService = game:GetService("UserInputService")
    local rightClickConnection = userInputService.InputBegan:Connect(function(input, gameProcessed)
        print("🔍 RIGHT CLICK INPUT:", input.UserInputType, "gameProcessed:", gameProcessed, "isMouseOver:", isMouseOverFrame, "for item:", item.id)
        
        -- For right-clicks, we ignore gameProcessed because we want to handle custom context menus
        -- For left-clicks, we still respect gameProcessed to avoid conflicts with normal UI
        if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
            return -- Only handle right-clicks in this listener
        end
        
        print("✅ RIGHT CLICK INPUT DETECTED")
        if isMouseOverFrame then
            print("🖱️ RIGHT CLICK DETECTED ON:", item.id)
            local mouse = Players.LocalPlayer:GetMouse()
            self.logger:info("🖱️ RIGHT CLICK ON ITEM", {itemId = item.id, x = mouse.X, y = mouse.Y})
            self:_showAdvancedContextMenu(item, mouse.X, mouse.Y)
        else
            print("❌ RIGHT CLICK NOT OVER THIS FRAME:", item.id)
        end
    end)
    
    -- Store connection for cleanup (prevent memory leaks)
    if not self._rightClickConnections then
        self._rightClickConnections = {}
    end
    self._rightClickConnections[item.id] = rightClickConnection
    
    print("🔧 RIGHT CLICK CONNECTION CREATED FOR:", item.id)
    
    -- CONSOLIDATED: Enhanced hover effects for visual feedback
    local originalSize = itemFrame.Size
    local stroke = itemFrame:FindFirstChild("UIStroke")
    print("🎨 SETTING UP HOVER FOR:", item.id, "hasStroke:", stroke ~= nil)
    
    -- UPDATED MouseEnter to include BOTH tracking AND hover effects
    itemFrame.MouseEnter:Connect(function()
        isMouseOverFrame = true
        print("🖱️ MOUSE ENTERED FRAME:", item.id)
        
        -- Background color change
        local bgTween = TweenService:Create(itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {BackgroundColor3 = Color3.fromRGB(55, 55, 65)}
        )
        bgTween:Play()
        
        -- Size increase
        local sizeTween = TweenService:Create(itemFrame, 
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset + 5, originalSize.Y.Scale, originalSize.Y.Offset + 5)}
        )
        sizeTween:Play()
        
        -- Stroke enhancement
        if stroke then
            local strokeTween = TweenService:Create(stroke,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                {Transparency = 0, Thickness = 3}
            )
            strokeTween:Play()
        end
    end)
    
    -- UPDATED MouseLeave to include BOTH tracking AND hover effects
    itemFrame.MouseLeave:Connect(function()
        isMouseOverFrame = false
        print("🖱️ MOUSE LEFT FRAME:", item.id)
        
        -- Background color reset
        local bgTween = TweenService:Create(itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {BackgroundColor3 = Color3.fromRGB(45, 45, 55)}
        )
        bgTween:Play()
        
        -- Size reset
        local sizeTween = TweenService:Create(itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {Size = originalSize}
        )
        sizeTween:Play()
        
        -- Stroke reset
        if stroke then
            local strokeTween = TweenService:Create(stroke,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                {Transparency = 0.3, Thickness = 2}
            )
            strokeTween:Play()
        end
    end)
end

function InventoryPanel:_showDeleteConfirmation(item)
    self.logger:info("🗑️ ITEM DELETE REQUESTED", {itemId = item.id, itemName = item.name})
    
    -- Create confirmation dialog
    local confirmFrame = Instance.new("Frame")
    confirmFrame.Name = "DeleteConfirmation"
    confirmFrame.Size = UDim2.new(0, 300, 0, 150)
    confirmFrame.Position = UDim2.new(0.5, -150, 0.5, -75)
    confirmFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    confirmFrame.BorderSizePixel = 0
    confirmFrame.ZIndex = 200
    confirmFrame.Parent = self.frame
    
    local confirmCorner = Instance.new("UICorner")
    confirmCorner.CornerRadius = UDim.new(0, 12)
    confirmCorner.Parent = confirmFrame
    
    local confirmStroke = Instance.new("UIStroke")
    confirmStroke.Color = Color3.fromRGB(231, 76, 60)
    confirmStroke.Thickness = 2
    confirmStroke.Parent = confirmFrame
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 30)
    titleLabel.Position = UDim2.new(0, 10, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Delete Item?"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 18
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.ZIndex = 201
    titleLabel.Parent = confirmFrame
    
    -- Message
    local messageLabel = Instance.new("TextLabel")
    messageLabel.Size = UDim2.new(1, -20, 0, 40)
    messageLabel.Position = UDim2.new(0, 10, 0, 45)
    messageLabel.BackgroundTransparency = 1
    messageLabel.Text = "Are you sure you want to delete:\n" .. item.name .. "?"
    messageLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    messageLabel.TextSize = 14
    messageLabel.Font = Enum.Font.Gotham
    messageLabel.ZIndex = 201
    messageLabel.TextWrapped = true
    messageLabel.Parent = confirmFrame
    
    -- Warning for valuable items
    if item.power and item.power > 10 then
        local warningLabel = Instance.new("TextLabel")
        warningLabel.Size = UDim2.new(1, -20, 0, 20)
        warningLabel.Position = UDim2.new(0, 10, 0, 85)
        warningLabel.BackgroundTransparency = 1
        warningLabel.Text = "⚠️ This item cannot be recovered!"
        warningLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
        warningLabel.TextSize = 12
        warningLabel.Font = Enum.Font.GothamBold
        warningLabel.ZIndex = 201
        warningLabel.Parent = confirmFrame
    end
    
    -- Buttons
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Size = UDim2.new(1, -20, 0, 35)
    buttonContainer.Position = UDim2.new(0, 10, 1, -45)
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.ZIndex = 201
    buttonContainer.Parent = confirmFrame
    
    local buttonLayout = Instance.new("UIListLayout")
    buttonLayout.FillDirection = Enum.FillDirection.Horizontal
    buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
    buttonLayout.Padding = UDim.new(0, 10)
    buttonLayout.Parent = buttonContainer
    
    -- Cancel button
    local cancelButton = Instance.new("TextButton")
    cancelButton.Size = UDim2.new(0, 80, 1, 0)
    cancelButton.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
    cancelButton.BorderSizePixel = 0
    cancelButton.Text = "Cancel"
    cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    cancelButton.TextSize = 14
    cancelButton.Font = Enum.Font.Gotham
    cancelButton.LayoutOrder = 1
    cancelButton.ZIndex = 202
    cancelButton.Parent = buttonContainer
    
    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0, 6)
    cancelCorner.Parent = cancelButton
    
    -- Delete button
    local deleteButton = Instance.new("TextButton")
    deleteButton.Size = UDim2.new(0, 80, 1, 0)
    deleteButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
    deleteButton.BorderSizePixel = 0
    deleteButton.Text = "Delete"
    deleteButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    deleteButton.TextSize = 14
    deleteButton.Font = Enum.Font.GothamBold
    deleteButton.LayoutOrder = 2
    deleteButton.ZIndex = 202
    deleteButton.Parent = buttonContainer
    
    local deleteCorner = Instance.new("UICorner")
    deleteCorner.CornerRadius = UDim.new(0, 6)
    deleteCorner.Parent = deleteButton
    
    -- Button actions
    cancelButton.Activated:Connect(function()
        confirmFrame:Destroy()
    end)
    
    deleteButton.Activated:Connect(function()
        confirmFrame:Destroy()
        self:_deleteItem(item)
    end)
    
    -- Entrance animation
    confirmFrame.BackgroundTransparency = 1
    confirmFrame.Size = UDim2.new(0, 0, 0, 0)
    confirmFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    
    local tween = TweenService:Create(confirmFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            BackgroundTransparency = 0,
            Size = UDim2.new(0, 300, 0, 150),
            Position = UDim2.new(0.5, -150, 0.5, -75)
        }
    )
    tween:Play()
end

-- 🎮 PRIMARY ACTIONS (Left-click)
function InventoryPanel:_handlePrimaryAction(item)
    print("🎮 HANDLING PRIMARY ACTION FOR:", item.id, "folder_source:", item.folder_source)
    self.logger:info("🖱️ PRIMARY ACTION", {
        itemId = item.id,
        itemName = item.name,
        folder_source = item.folder_source,
        count = item.count
    })
    
    if item.folder_source == "consumables" then
        -- Consume the item
        self:_consumeItem(item)
    elseif item.folder_source == "pets" then
        -- Equip/unequip pet
        self:_togglePetEquipped(item)
    elseif item.folder_source == "tools" then
        -- Equip/unequip tool
        self:_toggleToolEquipped(item)
    else
        -- Default: Show info
        self:_showItemInfo(item)
    end
end

function InventoryPanel:_consumeItem(item)
    self.logger:info("🍎 CONSUMING ITEM", {itemId = item.id, itemName = item.name})
    
    if self.signals then
        self.signals.ConsumeItem:FireServer({
            bucket = item.folder_source,
            itemUid = item.uid,
            itemId = item.id,
            quantity = 1
        })
        self.logger:info("✅ Consume request sent to server")
    else
        self.logger:warn("❌ Signals not available for consumption")
    end
end

function InventoryPanel:_togglePetEquipped(item)
    self.logger:info("🐾 TOGGLING PET EQUIPPED", {itemId = item.id, itemName = item.name})
    
    if self.signals then
        self.signals.TogglePetEquipped:FireServer({
            bucket = item.folder_source,
            itemUid = item.uid,
            itemId = item.id
        })
        self.logger:info("✅ Toggle pet request sent to server")
    else
        self.logger:warn("❌ Signals not available for pet equipping")
    end
end

function InventoryPanel:_toggleToolEquipped(item)
    self.logger:info("🔧 TOGGLING TOOL EQUIPPED", {itemId = item.id, itemName = item.name})
    
    if self.signals then
        self.signals.ToggleToolEquipped:FireServer({
            bucket = item.folder_source,
            itemUid = item.uid,
            itemId = item.id
        })
        self.logger:info("✅ Toggle tool request sent to server")
    else
        self.logger:warn("❌ Signals not available for tool equipping")
    end
end

-- 🖱️ ADVANCED CONTEXT MENU (Right-click)
function InventoryPanel:_showAdvancedContextMenu(item, x, y)
    print("🖱️ SHOWING CONTEXT MENU FOR:", item.id, "at", x, y)
    self.logger:info("🖱️ ADVANCED CONTEXT MENU", {itemId = item.id, x = x, y = y})
    
    -- Calculate menu size based on available options
    local menuOptions = self:_getContextMenuOptions(item)
    local menuHeight = #menuOptions * 35 + 10
    
    -- Clamp menu position to screen bounds
    local screenSize = workspace.CurrentCamera.ViewportSize
    local clampedX = math.min(x, screenSize.X - 160) -- Leave 10px margin
    local clampedY = math.min(y, screenSize.Y - menuHeight - 10)
    clampedX = math.max(clampedX, 10) -- Minimum 10px from left edge
    clampedY = math.max(clampedY, 10) -- Minimum 10px from top edge
    
    print("📍 CLAMPED POSITION: x=" .. clampedX .. " y=" .. clampedY .. " (screen: " .. screenSize.X .. "x" .. screenSize.Y .. ")")
    
    -- Create ScreenGui container (required for visibility)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ContextMenuGui"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = Players.LocalPlayer.PlayerGui
    
    -- Create context menu
    local contextMenu = Instance.new("Frame")
    contextMenu.Name = "AdvancedContextMenu"
    contextMenu.Size = UDim2.new(0, 150, 0, menuHeight)
    contextMenu.Position = UDim2.new(0, clampedX, 0, clampedY)
    contextMenu.BackgroundColor3 = Color3.fromRGB(255, 100, 100) -- BRIGHT RED for testing
    contextMenu.BackgroundTransparency = 0 -- Make it fully opaque
    contextMenu.BorderSizePixel = 2 -- Add visible border
    contextMenu.BorderColor3 = Color3.fromRGB(255, 255, 0) -- YELLOW border
    contextMenu.ZIndex = 1000 -- Much higher ZIndex
    -- Parent to ScreenGui (this makes it visible!)
    contextMenu.Parent = screenGui
    
    -- Debug: Print the exact path
    local fullPath = contextMenu:GetFullName()
    print("🔍 CONTEXT MENU FULL PATH:", fullPath)
    print("🔍 PLAYER GUI CHILDREN COUNT:", #Players.LocalPlayer.PlayerGui:GetChildren())
    
    local menuCorner = Instance.new("UICorner")
    menuCorner.CornerRadius = UDim.new(0, 8)
    menuCorner.Parent = contextMenu
    
    local menuStroke = Instance.new("UIStroke")
    menuStroke.Color = Color3.fromRGB(100, 100, 110)
    menuStroke.Thickness = 1
    menuStroke.Parent = contextMenu
    
    local menuLayout = Instance.new("UIListLayout")
    menuLayout.FillDirection = Enum.FillDirection.Vertical
    menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
    menuLayout.Padding = UDim.new(0, 2)
    menuLayout.Parent = contextMenu
    
    local menuPadding = Instance.new("UIPadding")
    menuPadding.PaddingTop = UDim.new(0, 5)
    menuPadding.PaddingBottom = UDim.new(0, 5)
    menuPadding.PaddingLeft = UDim.new(0, 5)
    menuPadding.PaddingRight = UDim.new(0, 5)
    menuPadding.Parent = contextMenu
    
    -- Create menu options
    print("📋 CREATING", #menuOptions, "MENU OPTIONS")
    for i, option in ipairs(menuOptions) do
        print("🔧 CREATING OPTION:", option.text, "action:", option.action)
        self:_createContextMenuOption(contextMenu, option, i, item)
    end
    
    local parentName = contextMenu.Parent and contextMenu.Parent.Name or "nil"
    print("✅ CONTEXT MENU CREATED - Parent:", parentName, "Position:", contextMenu.Position, "Size:", contextMenu.Size)
    
    -- Auto-close functionality (pass ScreenGui to destroy the whole thing)
    self:_setupContextMenuAutoClose(screenGui)
end

function InventoryPanel:_getContextMenuOptions(item)
    local options = {}
    
    -- Get configuration for this item type
    local itemType = item.folder_source or "unknown"
    local config = self.contextMenuConfig
    
    if not config then
        -- Fallback if no config loaded
        return self:_getFallbackContextMenuOptions(item)
    end
    
    -- Get item type configuration
    local typeConfig = config.item_types[itemType] or config.fallback
    if not typeConfig or not typeConfig.actions then
        return self:_getFallbackContextMenuOptions(item)
    end
    
    print("🎯 USING CONFIG FOR ITEM TYPE:", itemType, "actions:", #typeConfig.actions)
    
    -- Process base actions for this item type
    for _, actionConfig in ipairs(typeConfig.actions) do
        self:_addConfiguredAction(options, actionConfig, item)
    end
    
    -- Add item-specific overrides if they exist
    if typeConfig.item_overrides and typeConfig.item_overrides[item.id] then
        local overrides = typeConfig.item_overrides[item.id]
        if overrides.additional_actions then
            print("🔧 ADDING ITEM-SPECIFIC ACTIONS FOR:", item.id)
            for _, actionConfig in ipairs(overrides.additional_actions) do
                self:_addConfiguredAction(options, actionConfig, item)
            end
        end
    end
    
    -- Sort by order
    table.sort(options, function(a, b) 
        return (a.order or 999) < (b.order or 999) 
    end)
    
    print("📋 FINAL OPTIONS COUNT:", #options)
    
    return options
end

function InventoryPanel:_addConfiguredAction(options, actionConfig, item)
    local itemCount = item.count or 1
    
    -- Check if action should be enabled
    if actionConfig.min_count and itemCount < actionConfig.min_count then
        print("❌ SKIPPING ACTION:", actionConfig.action, "- not enough items (need", actionConfig.min_count, "have", itemCount, ")")
        return -- Skip if not enough items
    end
    
    -- Handle quantity-based actions (delete, consume, etc.)
    if actionConfig.quantities then
        print("🔢 PROCESSING QUANTITY ACTION:", actionConfig.action, "with quantities:", table.concat(actionConfig.quantities, ", "))
        for _, quantity in ipairs(actionConfig.quantities) do
            local actualQuantity = quantity
            if quantity == "all" then
                actualQuantity = itemCount
            elseif type(quantity) == "number" and quantity > itemCount then
                print("⏭️ SKIPPING QUANTITY:", quantity, "- not enough items")
                -- Skip if we don't have enough items
            else
                -- Get color for this quantity
                local color = actionConfig.color
                if actionConfig.quantity_colors and actionConfig.quantity_colors[quantity] then
                    color = actionConfig.quantity_colors[quantity]
                end
                
                -- Format text with quantity
                local text = actionConfig.text
                if quantity == "all" then
                    text = string.format(text:gsub("%%d", "All (%d)"), itemCount)
                else
                    text = string.format(text, quantity)
                end
                
                table.insert(options, {
                    text = text,
                    action = actionConfig.action,
                    quantity = actualQuantity,
                    color = Color3.fromRGB(color[1], color[2], color[3]),
                    order = actionConfig.order,
                    confirmation = actionConfig.confirmation
                })
            end
        end
    else
        -- Single action (info, equip, etc.)
        print("➡️ ADDING SINGLE ACTION:", actionConfig.action, actionConfig.text)
        table.insert(options, {
            text = actionConfig.text,
            action = actionConfig.action,
            color = Color3.fromRGB(actionConfig.color[1], actionConfig.color[2], actionConfig.color[3]),
            order = actionConfig.order,
            confirmation = actionConfig.confirmation
        })
    end
end

function InventoryPanel:_getFallbackContextMenuOptions(item)
    -- Basic fallback when config fails to load
    print("🔄 USING FALLBACK OPTIONS FOR:", item.id)
    local options = {}
    local itemCount = item.count or 1
    
    table.insert(options, {
        text = "ℹ️ Info",
        action = "info",
        color = Color3.fromRGB(100, 150, 255),
        order = 1
    })
    
    if itemCount > 1 then
        table.insert(options, {
            text = "🗑️ Delete 1",
            action = "delete",
            quantity = 1,
            color = Color3.fromRGB(255, 200, 100),
            order = 2
        })
        table.insert(options, {
            text = "🗑️ Delete All (" .. itemCount .. ")",
            action = "delete",
            quantity = itemCount,
            color = Color3.fromRGB(230, 76, 60),
            order = 3
        })
    else
        table.insert(options, {
            text = "🗑️ Delete",
            action = "delete",
            quantity = 1,
            color = Color3.fromRGB(230, 76, 60),
            order = 2
        })
    end
    
    return options
end

function InventoryPanel:_createContextMenuOption(parent, option, layoutOrder, item)
    print("🔧 CREATING BUTTON:", option.text, "color:", option.color)
    local optionButton = Instance.new("TextButton")
    optionButton.Size = UDim2.new(1, 0, 0, 30)
    optionButton.BackgroundColor3 = option.color or Color3.fromRGB(60, 60, 70) -- Fallback color
    optionButton.BackgroundTransparency = 0.8
    optionButton.BorderSizePixel = 0
    optionButton.Text = option.text
    optionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    optionButton.TextSize = 12
    optionButton.Font = Enum.Font.Gotham
    optionButton.LayoutOrder = layoutOrder
    optionButton.ZIndex = 1001 -- Higher than context menu
    optionButton.Parent = parent
    
    local optionCorner = Instance.new("UICorner")
    optionCorner.CornerRadius = UDim.new(0, 4)
    optionCorner.Parent = optionButton
    
    -- Hover effect
    optionButton.MouseEnter:Connect(function()
        local tween = TweenService:Create(optionButton,
            TweenInfo.new(0.1, Enum.EasingStyle.Quad),
            {BackgroundTransparency = 0.3}
        )
        tween:Play()
    end)
    
    optionButton.MouseLeave:Connect(function()
        local tween = TweenService:Create(optionButton,
            TweenInfo.new(0.1, Enum.EasingStyle.Quad),
            {BackgroundTransparency = 0.8}
        )
        tween:Play()
    end)
    
    -- Action
    optionButton.Activated:Connect(function()
        print("🖱️ CONTEXT MENU OPTION CLICKED:", option.text)
        self.logger:info("🖱️ CONTEXT MENU ACTION", {action = option.action, text = option.text, quantity = option.quantity})
        
        -- Find and destroy the ScreenGui (parent of parent)
        local screenGui = parent.Parent
        if screenGui and screenGui:IsA("ScreenGui") then
            screenGui:Destroy()
        else
            parent:Destroy() -- Fallback
        end
        self:_executeContextMenuAction(option, item)
    end)
    
    -- Also add debug for mouse events on the button
    optionButton.MouseButton1Click:Connect(function()
        print("🔘 BUTTON MouseButton1Click DETECTED:", option.text)
    end)
    
    optionButton.MouseButton1Down:Connect(function()
        print("🔽 BUTTON MouseButton1Down DETECTED:", option.text)
    end)
    
    print("✅ BUTTON CREATED AND ADDED TO PARENT:", optionButton.Text, "Parent:", parent.Name)
end

function InventoryPanel:_executeContextMenuAction(option, item)
    print("🎬 EXECUTING ACTION:", option.action, "quantity:", option.quantity, "for item:", item.id)
    
    if option.action == "info" then
        self:_showItemInfo(item)
    elseif option.action == "delete" then
        self:_deleteItemQuantity(item, option.quantity)
    elseif option.action == "consume" then
        self:_consumeItemQuantity(item, option.quantity)
    elseif option.action == "equip" then
        self:_toggleItemEquipped(item)
    elseif option.action == "rename" then
        self:_renameItem(item)
    elseif option.action == "sell" then
        self:_sellItem(item)
    elseif option.action == "upgrade" then
        self:_upgradeItem(item)
    elseif option.action == "hatch" then
        self:_hatchEgg(item, option.quantity or 1)
    elseif option.action == "hatch_multiple" then
        self:_hatchEgg(item, option.quantity)
    else
        self.logger:warn("❓ UNKNOWN ACTION", {action = option.action, itemId = item.id})
        print("❓ UNKNOWN ACTION:", option.action)
    end
end

-- 🍎 CONSUME ACTIONS
function InventoryPanel:_consumeItemQuantity(item, quantity)
    print("🍎 CONSUMING ITEM:", item.id, "quantity:", quantity)
    self.logger:info("🍎 CONSUME ITEM", {
        itemId = item.id,
        itemName = item.name,
        quantity = quantity,
        folder_source = item.folder_source
    })
    
    if self.signals and self.signals.ConsumeItem then
        self.signals.ConsumeItem:FireServer({
            bucket = item.folder_source,
            itemUid = item.uid,
            itemId = item.id,
            quantity = quantity
        })
        self.logger:info("✅ Consume request sent to server")
    else
        self.logger:warn("❌ Signals not available for consuming")
    end
end

-- 🐾 EQUIP ACTIONS
function InventoryPanel:_toggleItemEquipped(item)
    print("🐾 TOGGLING EQUIPPED:", item.id)
    if item.folder_source == "pets" then
        self:_togglePetEquipped(item)
    elseif item.folder_source == "tools" then
        self:_toggleToolEquipped(item)
    else
        self.logger:warn("❓ Cannot equip item type", {folder_source = item.folder_source})
    end
end

-- ✏️ RENAME ACTIONS
function InventoryPanel:_renameItem(item)
    print("✏️ RENAME ITEM:", item.id)
    -- TODO: Show text input dialog for renaming
    self.logger:info("✏️ RENAME REQUESTED", {itemId = item.id})
    print("🚧 RENAME NOT IMPLEMENTED YET")
end

-- 💰 SELL ACTIONS  
function InventoryPanel:_sellItem(item)
    print("💰 SELL ITEM:", item.id)
    -- TODO: Implement selling to shop
    self.logger:info("💰 SELL REQUESTED", {itemId = item.id})
    print("🚧 SELL NOT IMPLEMENTED YET")
end

-- ⬆️ UPGRADE ACTIONS
function InventoryPanel:_upgradeItem(item)
    print("⬆️ UPGRADE ITEM:", item.id)
    -- TODO: Implement item upgrading
    self.logger:info("⬆️ UPGRADE REQUESTED", {itemId = item.id})
    print("🚧 UPGRADE NOT IMPLEMENTED YET")
end

-- 🥚 HATCH ACTIONS
function InventoryPanel:_hatchEgg(item, quantity)
    print("🥚 HATCH EGG:", item.id, "quantity:", quantity)
    -- TODO: Implement egg hatching from inventory
    self.logger:info("🥚 HATCH REQUESTED", {itemId = item.id, quantity = quantity})
    print("🚧 HATCH NOT IMPLEMENTED YET - Use egg interaction in world")
end

function InventoryPanel:_deleteItemQuantity(item, quantity)
    self.logger:info("🗑️ DELETING ITEM QUANTITY", {
        itemId = item.id,
        itemName = item.name,
        quantity = quantity,
        totalCount = item.count
    })
    
    local itemUid = item.uid or item.uniqueId
    if item.folder_source and itemUid then
        if self.signals then
            self.signals.DeleteInventoryItem:FireServer({
                bucket = item.folder_source,
                itemUid = itemUid,
                itemId = item.id,
                quantity = quantity,
                reason = "player_deleted"
            })
            self.logger:info("✅ Delete quantity request sent to server")
        else
            self.logger:warn("❌ Signals not available for deletion")
        end
    else
        self.logger:warn("❌ Cannot delete item - missing source or UID")
    end
    
    -- Immediate UI feedback
    task.wait(0.1)
    self:RefreshFromRealData()
end

function InventoryPanel:_setupContextMenuAutoClose(contextMenu)
    -- SIMPLE SOLUTION: Just auto-close after 5 seconds, no click detection
    -- Let the button events handle themselves without interference
    task.spawn(function()
        task.wait(5)
        if contextMenu.Parent then
            print("🕒 AUTO-CLOSING CONTEXT MENU AFTER 5 SECONDS")
            contextMenu:Destroy()
        end
    end)
end

function InventoryPanel:_showItemContextMenu(item, x, y)
    self.logger:info("🖱️ ITEM CONTEXT MENU", {itemId = item.id, x = x, y = y})
    
    -- Create context menu
    local contextMenu = Instance.new("Frame")
    contextMenu.Name = "ItemContextMenu"
    contextMenu.Size = UDim2.new(0, 120, 0, 80)
    contextMenu.Position = UDim2.new(0, x, 0, y)
    contextMenu.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    contextMenu.BorderSizePixel = 0
    contextMenu.ZIndex = 150
    contextMenu.Parent = Players.LocalPlayer.PlayerGui
    
    local menuCorner = Instance.new("UICorner")
    menuCorner.CornerRadius = UDim.new(0, 6)
    menuCorner.Parent = contextMenu
    
    local menuStroke = Instance.new("UIStroke")
    menuStroke.Color = Color3.fromRGB(100, 100, 110)
    menuStroke.Thickness = 1
    menuStroke.Parent = contextMenu
    
    local menuLayout = Instance.new("UIListLayout")
    menuLayout.FillDirection = Enum.FillDirection.Vertical
    menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
    menuLayout.Parent = contextMenu
    
    -- Delete option
    local deleteOption = Instance.new("TextButton")
    deleteOption.Size = UDim2.new(1, 0, 0, 40)
    deleteOption.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
    deleteOption.BackgroundTransparency = 0.2
    deleteOption.BorderSizePixel = 0
    deleteOption.Text = "🗑️ Delete"
    deleteOption.TextColor3 = Color3.fromRGB(255, 255, 255)
    deleteOption.TextSize = 12
    deleteOption.Font = Enum.Font.Gotham
    deleteOption.LayoutOrder = 1
    deleteOption.ZIndex = 151
    deleteOption.Parent = contextMenu
    
    -- Info option
    local infoOption = Instance.new("TextButton")
    infoOption.Size = UDim2.new(1, 0, 0, 40)
    infoOption.BackgroundTransparency = 1
    infoOption.BorderSizePixel = 0
    infoOption.Text = "ℹ️ Info"
    infoOption.TextColor3 = Color3.fromRGB(255, 255, 255)
    infoOption.TextSize = 12
    infoOption.Font = Enum.Font.Gotham
    infoOption.LayoutOrder = 2
    infoOption.ZIndex = 151
    infoOption.Parent = contextMenu
    
    -- Actions
    deleteOption.Activated:Connect(function()
        contextMenu:Destroy()
        self:_showDeleteConfirmation(item)
    end)
    
    infoOption.Activated:Connect(function()
        contextMenu:Destroy()
        self:_showItemInfo(item)
    end)
    
    -- Auto-close after 3 seconds or on click outside
    local closeConnection
    local closeTimer = task.wait(3)
    
    closeConnection = game:GetService("UserInputService").InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            contextMenu:Destroy()
            closeConnection:Disconnect()
        end
    end)
    
    task.spawn(function()
        task.wait(3)
        if contextMenu.Parent then
            contextMenu:Destroy()
        end
        if closeConnection then
            closeConnection:Disconnect()
        end
    end)
end

function InventoryPanel:_deleteItem(item)
    self.logger:info("🗑️ DELETING ITEM", {
        itemId = item.id, 
        itemName = item.name,
        folder_source = item.folder_source,
        uniqueId = item.uniqueId,
        uid = item.uid,
        hasSignals = self.signals ~= nil,
        signalsType = typeof(self.signals)
    })
    
    -- Debug: Check if DeleteInventoryItem signal exists
    if self.signals then
        self.logger:info("🔍 SIGNALS DEBUG", {
            hasDeleteSignal = self.signals.DeleteInventoryItem ~= nil,
            deleteSignalType = typeof(self.signals.DeleteInventoryItem),
            hasFireServerMethod = self.signals.DeleteInventoryItem and typeof(self.signals.DeleteInventoryItem.FireServer) == "function"
        })
    end
    
    -- Determine which network call to make based on source
    local itemUid = item.uid or item.uniqueId  -- Check both field names
    if item.folder_source and itemUid then
        -- Real inventory item - call server to delete from ProfileStore
        if self.signals then
            self.signals.DeleteInventoryItem:FireServer({
                bucket = item.folder_source,
                itemUid = itemUid,
                itemId = item.id,
                reason = "player_deleted"
            })
            self.logger:info("✅ Delete request sent to server via Signals")
        else
            self.logger:warn("❌ Signals not available for deletion")
        end
    else
        self.logger:warn("❌ Cannot delete item - missing source or UID", {
            hasSource = item.folder_source ~= nil,
            hasUid = itemUid ~= nil,
            itemUid = itemUid,
            hasOldUid = item.uniqueId ~= nil,
            hasNewUid = item.uid ~= nil
        })
    end
    
    -- Immediate UI feedback - remove from display
    task.wait(0.1)
    self:RefreshFromRealData()
end

function InventoryPanel:_showItemInfo(item)
    self.logger:info("ℹ️ SHOWING ITEM INFO", {itemId = item.id})
    -- This would show detailed item information
    -- For now, just log the item data
    print("=== ITEM INFO ===")
    for key, value in pairs(item) do
        print(key .. ":", value)
    end
    print("================")
end

-- 🌐 NETWORK INITIALIZATION
function InventoryPanel:_initializeNetworking()
    local success, signals = pcall(function()
        return require(ReplicatedStorage.Shared.Network.Signals)
    end)
    
    if success and signals then
        self.signals = signals
        self.logger:info("✅ Signals initialized for inventory")
    else
        self.logger:warn("❌ Failed to get Signals module:", signals)
    end
end

function InventoryPanel:SetupRealTimeUpdates()
    -- Watch for changes to the inventory folder
    local inventoryFolder = self.player:FindFirstChild("Inventory")
    if inventoryFolder then
        local petsFolder = inventoryFolder:FindFirstChild("pets")
        if petsFolder then
            -- Listen for new pets being added
            petsFolder.ChildAdded:Connect(function(child)
                if child:IsA("Folder") and child.Name ~= "Info" then
                    self.logger:info("New pet detected in inventory", {petFolder = child.Name})
                    task.wait(0.1) -- Small delay to ensure folder is fully created
                    self:RefreshFromRealData()
                end
            end)
            
            -- Listen for pets being removed
            petsFolder.ChildRemoved:Connect(function(child)
                if child:IsA("Folder") and child.Name ~= "Info" then
                    self.logger:info("Pet removed from inventory", {petFolder = child.Name})
                    self:RefreshFromRealData()
                end
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- ⚔️ EQUIPPED ITEM TRACKING
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryPanel:_setupEquippedFolderListeners()
    local player = Players.LocalPlayer
    
    self.logger:info("⚔️ Setting up equipped folder listeners...")
    
    -- Use task.spawn to avoid blocking
    task.spawn(function()
        -- Wait for equipped folder to be created
        local equippedFolder = player:WaitForChild("Equipped", 10)
        if not equippedFolder then
            self.logger:warn("❌ No equipped folder found after 10 seconds")
            return
        end
        
        self.logger:info("✅ Found equipped folder")
        
        -- Track equipped items for quick lookup
        self.equippedItems = {
            pets = {},
            tools = {}
        }
        
        -- Set up pets folder listener
        task.spawn(function()
            local petsFolder = equippedFolder:FindFirstChild("pets")
            if not petsFolder then
                self.logger:info("⚔️ Waiting for pets folder to be created...")
                petsFolder = equippedFolder.ChildAdded:Wait()
                while petsFolder.Name ~= "pets" do
                    petsFolder = equippedFolder.ChildAdded:Wait()
                end
            end
            
            self.logger:info("✅ Found pets folder, setting up listener")
            self:_setupCategoryEquippedListener(petsFolder, "pets")
        end)
        
        -- Set up tools folder listener
        task.spawn(function()
            local toolsFolder = equippedFolder:FindFirstChild("tools")
            if toolsFolder then
                self.logger:info("✅ Found existing tools folder, setting up listener")
                self:_setupCategoryEquippedListener(toolsFolder, "tools")
            else
                self.logger:info("⚔️ Waiting for tools folder to be created...")
                -- Listen for tools folder to be created
                equippedFolder.ChildAdded:Connect(function(child)
                    if child.Name == "tools" then
                        self.logger:info("✅ Tools folder created, setting up listener")
                        self:_setupCategoryEquippedListener(child, "tools")
                    end
                end)
            end
        end)
        
        self.logger:info("⚔️ Equipped folder listeners setup complete")
    end)
end

function InventoryPanel:_setupCategoryEquippedListener(categoryFolder, categoryName)
    self.logger:info("⚔️ Setting up listener for category: " .. categoryName)
    
    -- Load initial equipped items
    local initialCount = 0
    for _, slotValue in pairs(categoryFolder:GetChildren()) do
        if slotValue:IsA("StringValue") and slotValue.Value ~= "" then
            self.equippedItems[categoryName][slotValue.Value] = slotValue.Name
            initialCount = initialCount + 1
            self.logger:info("📍 Initial equipped item found", {
                category = categoryName,
                slot = slotValue.Name,
                itemUid = slotValue.Value
            })
        end
    end
    
    -- Listen for equipped changes
    categoryFolder.ChildAdded:Connect(function(slotValue)
        if slotValue:IsA("StringValue") then
            self.logger:info("📍 ChildAdded in " .. categoryName, {
                slotName = slotValue.Name,
                slotValue = slotValue.Value
            })
            self:_onEquippedChanged(categoryName, slotValue.Value, slotValue.Name, "equipped")
        end
    end)
    
    categoryFolder.ChildRemoved:Connect(function(slotValue)
        if slotValue:IsA("StringValue") then
            self.logger:info("📍 ChildRemoved in " .. categoryName, {
                slotName = slotValue.Name,
                slotValue = slotValue.Value
            })
            self:_onEquippedChanged(categoryName, slotValue.Value, slotValue.Name, "unequipped")
        end
    end)
    
    -- Listen for value changes within slots
    for _, slotValue in pairs(categoryFolder:GetChildren()) do
        if slotValue:IsA("StringValue") then
            slotValue.Changed:Connect(function(newValue)
                local oldValue = slotValue.Value
                self.logger:info("📍 Value changed in " .. categoryName, {
                    slotName = slotValue.Name,
                    oldValue = oldValue,
                    newValue = newValue
                })
                self:_onEquippedChanged(categoryName, newValue, slotValue.Name, newValue ~= "" and "equipped" or "unequipped")
            end)
        end
    end
    
    self.logger:info("⚔️ Set up equipped listener complete", {
        category = categoryName,
        initialEquipped = initialCount,
        totalSlots = #categoryFolder:GetChildren()
    })
end

function InventoryPanel:_onEquippedChanged(categoryName, itemUid, slotName, action)
    self.logger:info("⚔️ EQUIPPED CHANGED", {
        category = categoryName,
        itemUid = itemUid,
        slot = slotName,
        action = action
    })
    
    if action == "equipped" and itemUid ~= "" then
        self.equippedItems[categoryName][itemUid] = slotName
        self.logger:info("✅ Added to equipped items", {itemUid = itemUid, slot = slotName})
    elseif action == "unequipped" then
        self.equippedItems[categoryName][itemUid] = nil
        self.logger:info("❌ Removed from equipped items", {itemUid = itemUid})
    end
    
    -- Refresh the UI to update equipped styling
    self.logger:info("🔄 Refreshing UI for equipped change")
    self:_updateItemsDisplay()
end

-- Debug function to manually check equipped items
function InventoryPanel:DebugEquippedItems()
    print("=== EQUIPPED ITEMS DEBUG ===")
    if self.equippedItems then
        for category, items in pairs(self.equippedItems) do
            print(category .. ":")
            for itemUid, slot in pairs(items) do
                print("  " .. itemUid .. " -> " .. slot)
            end
        end
    else
        print("equippedItems not initialized")
    end
    
    -- Also check the actual folders
    local player = Players.LocalPlayer
    local equippedFolder = player:FindFirstChild("Equipped")
    if equippedFolder then
        print("=== ACTUAL FOLDERS ===")
        for _, categoryFolder in pairs(equippedFolder:GetChildren()) do
            if categoryFolder:IsA("Folder") then
                print(categoryFolder.Name .. ":")
                for _, slotValue in pairs(categoryFolder:GetChildren()) do
                    if slotValue:IsA("StringValue") then
                        print("  " .. slotValue.Name .. " = " .. slotValue.Value)
                    end
                end
            end
        end
    else
        print("No equipped folder found")
    end
    print("===========================")
end

function InventoryPanel:_isItemEquipped(item)
    if not self.equippedItems then return false end
    
    if item.folder_source == "pets" then
        return self.equippedItems.pets[item.uid] ~= nil
    elseif item.folder_source == "tools" then
        return self.equippedItems.tools[item.uid] ~= nil
    end
    
    return false
end

function InventoryPanel:_applyEquippedStyling(itemFrame, isEquipped, originalColor)
    if not itemFrame then return end
    
    local stroke = itemFrame:FindFirstChild("UIStroke")
    local gradient = itemFrame:FindFirstChild("UIGradient")
    
    if isEquipped then
        -- Equipped styling: Golden border and brighter background
        if stroke then
            stroke.Color = Color3.fromRGB(255, 215, 0) -- Gold
            stroke.Thickness = 3
            stroke.Transparency = 0
        end
        
        if gradient then
            gradient.Color = ColorSequence.new{
                ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 75, 45)), -- Golden tint
                ColorSequenceKeypoint.new(1, Color3.fromRGB(65, 60, 35))
            }
        end
        
        -- Add equipped icon
        local equippedIcon = itemFrame:FindFirstChild("EquippedIcon")
        if not equippedIcon then
            equippedIcon = Instance.new("TextLabel")
            equippedIcon.Name = "EquippedIcon"
            equippedIcon.Size = UDim2.new(0, 24, 0, 24)
            equippedIcon.Position = UDim2.new(1, -30, 0, 6)
            equippedIcon.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
            equippedIcon.BackgroundTransparency = 0.2
            equippedIcon.BorderSizePixel = 0
            equippedIcon.Text = "⚔️"
            equippedIcon.TextSize = 14
            equippedIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
            equippedIcon.ZIndex = 110
            equippedIcon.Parent = itemFrame
            
            local iconCorner = Instance.new("UICorner")
            iconCorner.CornerRadius = UDim.new(0, 12)
            iconCorner.Parent = equippedIcon
        end
    else
        -- Unequipped styling: Restore original colors
        if stroke then
            stroke.Color = originalColor or Color3.fromRGB(100, 100, 100) -- Use original rarity color
            stroke.Thickness = 2
            stroke.Transparency = 0.3
        end
        
        if gradient then
            gradient.Color = ColorSequence.new{
                ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 55, 65)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 45, 55))
            }
        end
        
        -- Remove equipped icon
        local equippedIcon = itemFrame:FindFirstChild("EquippedIcon")
        if equippedIcon then
            equippedIcon:Destroy()
        end
    end
end

function InventoryPanel:Destroy()
    self:Hide()
    self.logger:info("Professional inventory panel destroyed")
end

return InventoryPanel 