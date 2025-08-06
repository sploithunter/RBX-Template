--[[
    BaseUI - Always visible game UI layer (Professional Pet Simulator Style)
    
    Version: 2.0 - Enhanced Asset Support & Performance
    
    Features:
    - Pane-based configuration system with semantic positioning
    - Universal icon support (emoji + Roblox asset IDs with automatic fallback)
    - ImageButton architecture for optimal performance
    - Floating currency cards with smart number formatting (K/M/B/T/Qa)
    - Professional menu button styling with hover effects
    - Quest/objectives tracking system with combined layouts
    - Rewards button and notifications
    - Responsive scaling for all screen sizes
    - Configuration-as-code architecture with comprehensive documentation
    - Professional visual design with gradients, shadows, borders
    - Real-time currency animations and visual feedback
    - Robust error handling and logging
    
    Architecture:
    - Uses pane-based layout system defined in configs/ui.lua
    - Automatic UI element factories with type detection
    - Semantic positioning system (top-left, center, bottom-right, etc.)
    - Layout types: list, grid, single, custom
    - Background styling and theming support
    
    Usage:
    local BaseUI = require(script.BaseUI)
    local baseUI = BaseUI.new()
    baseUI:Show()
    
    Configuration:
    Edit configs/ui.lua to modify layout, positions, icons, and styling
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

-- Get shared modules
local Locations = require(ReplicatedStorage.Shared.Locations)

-- Load Logger with fallback
local Logger
local loggerSuccess, loggerResult = pcall(function()
    return require(Locations.Logger)
end)

-- Create logger wrapper to provide instance-like behavior
local LoggerWrapper = {}
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

-- Load TemplateManager with fallback
local TemplateManager
local templateSuccess, templateResult = pcall(function()
    return require(Locations.TemplateManager)
end)

if templateSuccess and templateResult then
    TemplateManager = templateResult
else
    -- Enhanced fallback TemplateManager
    TemplateManager = {
        new = function() 
            return {
                CreatePanel = function() return nil end,
                CreateFromTemplate = function() return nil end,
                CreateCurrencyDisplay = function() return nil end,
                CreateMenuButton = function() return nil end
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
    warn("[BaseUI] Failed to load UI config, using enhanced fallback")
    -- Enhanced fallback config with professional styling
    uiConfig = {
        active_theme = "dark",
        themes = {
            dark = {
                primary = { 
                    background = Color3.fromRGB(25, 25, 30), 
                    surface = Color3.fromRGB(35, 35, 45),
                    accent = Color3.fromRGB(0, 150, 255),
                    success = Color3.fromRGB(46, 204, 113),
                    warning = Color3.fromRGB(255, 206, 84),
                    error = Color3.fromRGB(231, 76, 60)
                },
                text = { 
                    primary = Color3.fromRGB(255, 255, 255),
                    secondary = Color3.fromRGB(200, 200, 210),
                    muted = Color3.fromRGB(150, 150, 160)
                },
                button = { 
                    primary = Color3.fromRGB(0, 150, 255),
                    secondary = Color3.fromRGB(60, 60, 80),
                    success = Color3.fromRGB(46, 204, 113),
                    danger = Color3.fromRGB(231, 76, 60)
                }
            }
        },
        spacing = { xs = 4, sm = 8, md = 16, lg = 24, xl = 32 },
        fonts = { primary = Enum.Font.GothamBold, secondary = Enum.Font.Gotham },
        z_index = { content = 10, modal = 100, tooltip = 200 },
        animations = {
            duration = { fast = 0.15, normal = 0.25, slow = 0.4 },
            easing = { ease_out = Enum.EasingStyle.Quad }
        },
        -- Pane-based layout configuration (fallback)
        panes = {
            -- Individual Floating Currency Cards (like reference game)
            coins_pane = {
                position = "center-left",
                offset = {x = 15, y = -40},
                size = {width = 120, height = 35},
                background = {
                    enabled = true,
                    color = Color3.fromRGB(0, 0, 0),
                    transparency = 0.15,
                    corner_radius = 18,
                    border = {enabled = true, color = Color3.fromRGB(255, 215, 0), thickness = 2, transparency = 0.3}
                },
                layout = {type = "single"},
                contents = {{type = "currency_display", config = {currency = "coins", icon = "💰", color = Color3.fromRGB(255, 215, 0)}}}
            },
            gems_pane = {
                position = "center-left",
                offset = {x = 15, y = 0},
                size = {width = 120, height = 35},
                background = {
                    enabled = true,
                    color = Color3.fromRGB(0, 0, 0),
                    transparency = 0.15,
                    corner_radius = 18,
                    border = {enabled = true, color = Color3.fromRGB(138, 43, 226), thickness = 2, transparency = 0.3}
                },
                layout = {type = "single"},
                contents = {{type = "currency_display", config = {currency = "gems", icon = "💎", color = Color3.fromRGB(138, 43, 226)}}}
            },
            crystals_pane = {
                position = "center-left",
                offset = {x = 15, y = 40},
                size = {width = 120, height = 35},
                background = {
                    enabled = true,
                    color = Color3.fromRGB(0, 0, 0),
                    transparency = 0.15,
                    corner_radius = 18,
                    border = {enabled = true, color = Color3.fromRGB(0, 255, 255), thickness = 2, transparency = 0.3}
                },
                layout = {type = "single"},
                contents = {{type = "currency_display", config = {currency = "crystals", icon = "🔮", color = Color3.fromRGB(0, 255, 255)}}}
            },
            player_info_pane = {
                position = "top-center",
                offset = {x = 0, y = 35},
                size = {width = 400, height = 160},  -- Increased height for both elements
                background = {
                    enabled = true,
                    color = Color3.fromRGB(0, 0, 0),
                    transparency = 0.3,
                    corner_radius = 12,
                    border = {enabled = true, color = Color3.fromRGB(255, 255, 255), thickness = 1, transparency = 0.7}
                },
                layout = {type = "custom"},
                contents = {
                    {type = "player_info", config = {}},
                    {type = "quest_tracker", config = {}}
                }
            },
            menu_buttons_pane = {
                position = "bottom-left",
                offset = {x = 0, y = -20},
                size = {width = 320, height = 160},
                background = {
                    enabled = true,
                    color = Color3.fromRGB(0, 0, 0),
                    transparency = 0.4,
                    corner_radius = 15,
                    border = {enabled = true, color = Color3.fromRGB(52, 152, 219), thickness = 2, transparency = 0.5}
                },
                layout = {type = "grid", columns = 4, rows = 2, cell_size = {width = 75, height = 75}, spacing = 5, padding = {top = 5, bottom = 5, left = 5, right = 5}},
                contents = {
                    {type = "menu_button", config = {name = "Shop", icon = "🛒", text = "Shop", color = Color3.fromRGB(46, 204, 113)}},
                    {type = "menu_button", config = {name = "Inventory", icon = "🎒", text = "Items", color = Color3.fromRGB(52, 152, 219)}},
                    {type = "menu_button", config = {name = "Effects", icon = "⚡", text = "Effects", color = Color3.fromRGB(155, 89, 182)}},
                    {type = "menu_button", config = {name = "Settings", icon = "⚙️", text = "Settings", color = Color3.fromRGB(149, 165, 166)}},
                    {type = "menu_button", config = {name = "Admin", icon = "👑", text = "Admin", color = Color3.fromRGB(231, 76, 60), admin_only = true}}
                }
            },
            pets_button_pane = {
                position = "bottom-center",
                offset = {x = 0, y = -70},  -- Adjusted for better spacing
                size = {width = 120, height = 60},  -- Slightly larger for better proportions
                background = {enabled = false},
                layout = {type = "single"},
                contents = {{type = "pets_button", config = {icon = "🐾", text = "Pets", color = Color3.fromRGB(52, 152, 219)}}}
            },
            rewards_button_pane = {
                position = "bottom-right",
                offset = {x = 0, y = -20},
                size = {width = 120, height = 60},
                background = {enabled = false},
                layout = {type = "single"},
                contents = {{type = "rewards_button", config = {icon = "🎁", text = "Rewards", color = Color3.fromRGB(255, 215, 0), badge_count = 3}}}
            }
        },
        debug = {
            show_bounds = false,
            show_anchor_points = false,
            show_backgrounds = false,
            position_validation = false
        },
        helpers = {
            get_theme = function(config) return config.themes.dark end,
            get_scale_factor = function() return 1.0 end,
            calculate_auto_grid = function(config, width, height, buttonCount, padding)
                -- Simple fallback auto-grid calculation
                return {
                    columns = 4,
                    rows = 2,
                    cell_size = {width = 65, height = 65},
                    spacing = 3,
                    padding = padding or {top = 5, bottom = 5, left = 5, right = 5},
                    info = {
                        button_count = buttonCount,
                        available_size = {width = width, height = height},
                        calculated_button_size = {width = 65, height = 65}
                    }
                }
            end
        }
    }
end

local BaseUI = {}
BaseUI.__index = BaseUI

function BaseUI.new()
    local self = setmetatable({}, BaseUI)
    
    self.logger = LoggerWrapper.new("BaseUI")
    self.templateManager = TemplateManager.new()
    
    -- Store UI configuration in instance
    self.uiConfig = uiConfig
    
    -- UI state
    self.isVisible = false
    self.playerData = {
        currencies = {}, -- Will be populated from player attributes
        level = 15,
        xp = 750,
        maxXp = 1000
    }
    
    -- Quest/objectives data
    self.questData = {
        currentQuest = "Collect 50 Rainbow Blocks",
        progress = 32,
        maxProgress = 50,
        reward = "500 Coins + Rare Pet"
    }
    
    -- UI elements
    self.screenGui = nil
    self.mainFrame = nil
    self.currencyDisplays = {}
    self.menuButtons = {}
    self.animations = {}
    
    -- Menu manager reference
    self.menuManager = nil

    -- Store reference to player for attribute access
    self.player = Players.LocalPlayer
    
    return self
end

function BaseUI:Show()
    if self.isVisible then
        self.logger:warn("BaseUI already visible")
        return
    end
    
    self:_createUI()
    self:_setupNetworking()
    self:_setupResponsiveScaling()
    self:_setupCurrencyUpdates()
    self:_startAnimations()
    
    self.isVisible = true
    self.logger:info("Professional BaseUI shown")
end

function BaseUI:Hide()
    if not self.isVisible then return end
    
    -- Stop animations
    for _, tween in pairs(self.animations) do
        if tween then tween:Cancel() end
    end
    
    if self.screenGui then
        self.screenGui:Destroy()
        self.screenGui = nil
    end
    
    self.isVisible = false
    self.logger:info("BaseUI hidden")
end

function BaseUI:SetMenuManager(menuManager)
    self.menuManager = menuManager
end

-- Create the professional main UI structure
function BaseUI:_createUI()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Create ScreenGui with proper ordering
    self.screenGui = Instance.new("ScreenGui")
    self.screenGui.Name = "ProfessionalBaseUI"
    self.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    self.screenGui.IgnoreGuiInset = true
    self.screenGui.Parent = playerGui
    
    -- Create main container (full screen, transparent)
    self.mainFrame = Instance.new("Frame")
    self.mainFrame.Name = "MainContainer"
    self.mainFrame.Size = UDim2.new(1, 0, 1, 0)
    self.mainFrame.Position = UDim2.new(0, 0, 0, 0)
    self.mainFrame.BackgroundTransparency = 1
    self.mainFrame.ZIndex = self.uiConfig.z_index.content
    self.mainFrame.Parent = self.screenGui
    
    -- Create all UI using the new pane-based system
    self:_createTopBar()
    self:_createAllPanes()  -- Create all panes from configuration
    
    self.logger:info("Professional UI structure created with pane-based architecture")
end

-- Semantic positioning system for configuration-as-code layouts (with caching)
function BaseUI:_getSemanticPosition(alignment, size, offset)
    -- Validate inputs
    if type(alignment) ~= "string" then
        self.logger:error("Invalid alignment type: expected string, got " .. type(alignment))
        alignment = "center"
    end
    
    offset = offset or {x = 0, y = 0}
    
    -- Ensure offset has valid values
    if type(offset) ~= "table" then
        offset = {x = 0, y = 0}
    end
    offset.x = tonumber(offset.x) or 0
    offset.y = tonumber(offset.y) or 0
    
    -- Create cache key for this position calculation
    local cacheKey = alignment .. "_" .. offset.x .. "_" .. offset.y
    
    -- Return cached position if available
    if self.positionCache and self.positionCache[cacheKey] then
        return self.positionCache[cacheKey]
    end
    
    -- Initialize cache if needed
    if not self.positionCache then
        self.positionCache = {}
    end
    
    local positions = {
        -- Top alignments
        ["top-left"] = {
            position = UDim2.new(0, 15 + offset.x, 0, 15 + offset.y),
            anchorPoint = Vector2.new(0, 0)
        },
        ["top-center"] = {
            position = UDim2.new(0.5, offset.x, 0, 15 + offset.y),
            anchorPoint = Vector2.new(0.5, 0)
        },
        ["top-right"] = {
            position = UDim2.new(1, -15 + offset.x, 0, 15 + offset.y),
            anchorPoint = Vector2.new(1, 0)
        },
        
        -- Center alignments
        ["center-left"] = {
            position = UDim2.new(0, 15 + offset.x, 0.5, offset.y),
            anchorPoint = Vector2.new(0, 0.5)
        },
        ["center"] = {
            position = UDim2.new(0.5, offset.x, 0.5, offset.y),
            anchorPoint = Vector2.new(0.5, 0.5)
        },
        ["center-right"] = {
            position = UDim2.new(1, -15 + offset.x, 0.5, offset.y),
            anchorPoint = Vector2.new(1, 0.5)
        },
        
        -- Bottom alignments
        ["bottom-left"] = {
            position = UDim2.new(0, 15 + offset.x, 1, -15 + offset.y),
            anchorPoint = Vector2.new(0, 1)
        },
        ["bottom-center"] = {
            position = UDim2.new(0.5, offset.x, 1, -15 + offset.y),
            anchorPoint = Vector2.new(0.5, 1)
        },
        ["bottom-right"] = {
            position = UDim2.new(1, -15 + offset.x, 1, -15 + offset.y),
            anchorPoint = Vector2.new(1, 1)
        }
    }
    
    local result = positions[alignment] or positions["center"]
    
    -- Cache the result for future use
    self.positionCache[cacheKey] = result
    
    return result
end

-- Get semantic grid fill settings based on position
function BaseUI:_getSemanticGridFill(position)
    -- Define fill behavior based on semantic position for optimal aesthetics
    local fillConfigs = {
        -- TOP POSITIONS - Fill from top down
        ["top-left"] = {
            fillDirection = Enum.FillDirection.Horizontal,
            horizontalAlignment = Enum.HorizontalAlignment.Left,
            verticalAlignment = Enum.VerticalAlignment.Top,
            startCorner = Enum.StartCorner.TopLeft
        },
        ["top-center"] = {
            fillDirection = Enum.FillDirection.Horizontal,
            horizontalAlignment = Enum.HorizontalAlignment.Center,
            verticalAlignment = Enum.VerticalAlignment.Top,
            startCorner = Enum.StartCorner.TopLeft
        },
        ["top-right"] = {
            fillDirection = Enum.FillDirection.Horizontal,
            horizontalAlignment = Enum.HorizontalAlignment.Right,
            verticalAlignment = Enum.VerticalAlignment.Top,
            startCorner = Enum.StartCorner.TopRight
        },
        
        -- CENTER POSITIONS - Fill from center outward
        ["center-left"] = {
            fillDirection = Enum.FillDirection.Vertical,
            horizontalAlignment = Enum.HorizontalAlignment.Left,
            verticalAlignment = Enum.VerticalAlignment.Center,
            startCorner = Enum.StartCorner.TopLeft
        },
        ["center"] = {
            fillDirection = Enum.FillDirection.Horizontal,
            horizontalAlignment = Enum.HorizontalAlignment.Center,
            verticalAlignment = Enum.VerticalAlignment.Center,
            startCorner = Enum.StartCorner.TopLeft
        },
        ["center-right"] = {
            fillDirection = Enum.FillDirection.Vertical,
            horizontalAlignment = Enum.HorizontalAlignment.Right,
            verticalAlignment = Enum.VerticalAlignment.Center,
            startCorner = Enum.StartCorner.TopRight
        },
        
        -- BOTTOM POSITIONS - Fill from bottom up
        ["bottom-left"] = {
            fillDirection = Enum.FillDirection.Horizontal,
            horizontalAlignment = Enum.HorizontalAlignment.Left,
            verticalAlignment = Enum.VerticalAlignment.Bottom,
            startCorner = Enum.StartCorner.BottomLeft
        },
        ["bottom-center"] = {
            fillDirection = Enum.FillDirection.Horizontal,
            horizontalAlignment = Enum.HorizontalAlignment.Center,
            verticalAlignment = Enum.VerticalAlignment.Bottom,
            startCorner = Enum.StartCorner.BottomLeft
        },
        ["bottom-right"] = {
            fillDirection = Enum.FillDirection.Horizontal,
            horizontalAlignment = Enum.HorizontalAlignment.Right,
            verticalAlignment = Enum.VerticalAlignment.Bottom,
            startCorner = Enum.StartCorner.BottomRight
        }
    }
    
    -- Return the appropriate config or default to top-left behavior
    return fillConfigs[position] or fillConfigs["top-left"]
end

-- === PANE-BASED UI SYSTEM ===
--[[
    CONFIGURATION-AS-CODE PANE ARCHITECTURE
    
    This system organizes UI elements into configurable "panes" (containers) that can be positioned
    semantically and contain multiple UI elements with various layout types.
    
    KEY CONCEPTS:
    - Panes: Containers that hold related UI elements (like "cards" in web development)
    - Semantic Positioning: Position panes using logical names like "top-left", "center", etc.
    - Layout Types: Each pane can use different layouts (list, grid, single, custom)
    - Element Factories: Type-based element creation (currency_display, menu_button, etc.)
    
    PERFORMANCE OPTIMIZATIONS:
    - Cached semantic position calculations
    - Cached theme lookups
    - Performance logging with millisecond timing
    - Robust error handling with graceful fallbacks
    
    CONFIGURATION STRUCTURE:
    panes = {
        pane_name = {
            position = "top-left" | "center" | "bottom-right" | etc.,
            offset = {x = 0, y = 0},
            size = {width = 200, height = 100},
            background = {enabled = true, color = Color3, transparency = 0.3, ...},
            layout = {type = "list"|"grid"|"single"|"custom", ...},
            contents = {{type = "element_type", config = {...}}, ...}
        }
    }
    
    ADDING NEW ELEMENTS:
    1. Add element type to _createPaneElement factory method
    2. Create corresponding _create[ElementType]Element method
    3. Update configuration with new element type and config structure
--]]

-- Create all panes from configuration
function BaseUI:_createAllPanes()
    if not self.uiConfig.panes then
        self.logger:warn("No panes configuration found, using fallback")
        return
    end
    
    if type(self.uiConfig.panes) ~= "table" then
        self.logger:error("Invalid panes configuration - expected table, got " .. type(self.uiConfig.panes))
        return
    end
    
    local startTime = tick()
    local paneCount = 0
    
    -- Create each configured pane
    for paneName, paneConfig in pairs(self.uiConfig.panes) do
        local paneStartTime = tick()
        self:_createPane(paneName, paneConfig)
        local paneEndTime = tick()
        
        paneCount = paneCount + 1
        self.logger:debug("Created pane '" .. paneName .. "' in " .. string.format("%.2f", (paneEndTime - paneStartTime) * 1000) .. "ms")
    end
    
    local totalTime = tick() - startTime
    self.logger:info("Created " .. paneCount .. " panes in " .. string.format("%.2f", totalTime * 1000) .. "ms")
end

-- Create individual pane (container) with its contents
function BaseUI:_createPane(paneName, config)
    -- Validate pane configuration
    if not config or type(config) ~= "table" then
        self.logger:error("Invalid pane config for '" .. tostring(paneName) .. "'")
        return
    end
    
    if not config.size or type(config.size) ~= "table" or not config.size.width or not config.size.height then
        self.logger:error("Invalid size configuration for pane '" .. tostring(paneName) .. "'")
        return
    end
    
    -- Create pane container with semantic positioning
    local success, paneContainer = pcall(function()
        local container = Instance.new("Frame")
        container.Name = paneName
        container.Size = UDim2.new(0, config.size.width, 0, config.size.height)
        return container
    end)
    
    if not success then
        self.logger:error("Failed to create pane container for '" .. tostring(paneName) .. "': " .. tostring(paneContainer))
        return
    end
    
    -- Apply semantic positioning
    local positionInfo = self:_getSemanticPosition(config.position, nil, config.offset)
    paneContainer.Position = positionInfo.position
    paneContainer.AnchorPoint = positionInfo.anchorPoint
    
    paneContainer.ZIndex = 12
    paneContainer.Parent = self.mainFrame
    
    -- Create background if enabled OR if debug backgrounds are on
    if (config.background and config.background.enabled) or (self.uiConfig.debug.show_backgrounds) then
        local bgConfig = config.background
        
        -- If debug backgrounds are enabled but no background config exists, create debug background
        if self.uiConfig.debug.show_backgrounds and (not bgConfig or not bgConfig.enabled) then
            bgConfig = {
                enabled = true,
                color = Color3.fromRGB(50, 50, 50),
                transparency = 0.8,
                corner_radius = 8
            }
        end
        
        self:_createPaneBackground(paneContainer, bgConfig)
    else
        paneContainer.BackgroundTransparency = 1
    end
    
    -- Create layout container
    local layoutContainer = self:_createPaneLayout(paneContainer, config.layout, paneName, config)
    
    -- Create contents
    self:_createPaneContents(layoutContainer, config.contents, config.layout)
    
    -- Debug visualization (if enabled)
    if self.uiConfig.debug.show_bounds then
        self:_addDebugBounds(paneContainer, paneName)
    end
    
    if self.uiConfig.debug.show_anchor_points then
        self:_addDebugAnchorPoint(paneContainer, positionInfo.anchorPoint, paneName)
    end
    
    if self.uiConfig.debug.position_validation then
        self:_validatePanePosition(paneContainer, config, paneName)
    end
    
    self.logger:debug("Created pane:", paneName)
end

-- Create pane background styling
function BaseUI:_createPaneBackground(container, bgConfig)
    container.BackgroundColor3 = bgConfig.color
    container.BackgroundTransparency = bgConfig.transparency or 0
    container.BorderSizePixel = 0
    
    -- Rounded corners
    if bgConfig.corner_radius then
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, bgConfig.corner_radius)
        corner.Parent = container
    end
    
    -- Border/stroke
    if bgConfig.border and bgConfig.border.enabled then
        local stroke = Instance.new("UIStroke")
        stroke.Color = bgConfig.border.color
        stroke.Thickness = bgConfig.border.thickness or 1
        stroke.Transparency = bgConfig.border.transparency or 0
        stroke.Parent = container
    end
end

-- Create layout container based on layout type
function BaseUI:_createPaneLayout(container, layoutConfig, paneName, paneConfig)
    local layoutContainer = container
    
    if layoutConfig.type == "list" then
        -- List layout
        local layout = Instance.new("UIListLayout")
        layout.FillDirection = layoutConfig.direction == "horizontal" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, layoutConfig.spacing or 4)
        
        if layoutConfig.direction == "vertical" then
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        else
            layout.VerticalAlignment = Enum.VerticalAlignment.Center
        end
        
        layout.Parent = layoutContainer
        
    elseif layoutConfig.type == "grid" then
        -- Grid layout with auto-sizing support
        local finalLayoutConfig = layoutConfig
        
        -- Check if we need auto-sizing (when auto_size is enabled)
        if layoutConfig.auto_size then
            local containerSize = container.Size
            local containerWidth = containerSize.X.Offset
            local containerHeight = containerSize.Y.Offset
            local buttonCount = layoutConfig.button_count or 7 -- Default or calculate from contents
            
            local autoGrid = self.uiConfig.helpers.calculate_auto_grid(
                self.uiConfig, 
                containerWidth, 
                containerHeight, 
                buttonCount, 
                layoutConfig.padding
            )
            
            -- Log the auto-sizing calculation for debugging
            self.logger:info("Auto-grid calculated:", autoGrid.info)
            
            -- Update layout config with calculated values
            finalLayoutConfig = {
                type = "grid",
                columns = autoGrid.columns,
                rows = autoGrid.rows,
                cell_size = autoGrid.cell_size,
                spacing = autoGrid.spacing,
                padding = autoGrid.padding,
                auto_size = true -- Keep the flag
            }
        end
        
        local gridLayout = Instance.new("UIGridLayout")
        gridLayout.CellSize = UDim2.new(0, finalLayoutConfig.cell_size.width, 0, finalLayoutConfig.cell_size.height)
        gridLayout.CellPadding = UDim2.new(0, finalLayoutConfig.spacing or 5, 0, finalLayoutConfig.spacing or 5)
        gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
        
        -- Apply contextual grid filling based on semantic position
        local semanticFill = self:_getSemanticGridFill(paneConfig.position)
        gridLayout.FillDirection = semanticFill.fillDirection
        gridLayout.HorizontalAlignment = semanticFill.horizontalAlignment
        gridLayout.VerticalAlignment = semanticFill.verticalAlignment
        gridLayout.StartCorner = semanticFill.startCorner
        
        gridLayout.Parent = layoutContainer
        
    elseif layoutConfig.type == "single" then
        -- Single element (no special layout)
        -- Element will fill the container
        
    elseif layoutConfig.type == "custom" then
        -- Custom layout (handled by specific content creators)
        
    end
    
    -- Add padding if specified
    if layoutConfig.padding then
        local padding = Instance.new("UIPadding")
        padding.PaddingTop = UDim.new(0, layoutConfig.padding.top or 0)
        padding.PaddingBottom = UDim.new(0, layoutConfig.padding.bottom or 0)
        padding.PaddingLeft = UDim.new(0, layoutConfig.padding.left or 0)
        padding.PaddingRight = UDim.new(0, layoutConfig.padding.right or 0)
        padding.Parent = layoutContainer
    end
    
    return layoutContainer
end

-- Create contents within a pane
function BaseUI:_createPaneContents(container, contents, layoutConfig)
    for i, contentConfig in ipairs(contents) do
        local element = self:_createPaneElement(contentConfig, container, i, layoutConfig)
        if element then
            element.LayoutOrder = i
        end
    end
end

-- Factory for creating different types of pane elements
function BaseUI:_createPaneElement(contentConfig, parent, layoutOrder, layoutConfig)
    local elementType = contentConfig.type
    local config = contentConfig.config
    
    if elementType == "currency_display" then
        return self:_createCurrencyElement(config, parent, layoutOrder)
        
    elseif elementType == "menu_button" then
        self.logger:info("🔧 BaseUI: Creating menu button", {
            buttonName = config.name,
            hasAdminOnly = config.admin_only or false
        })
        -- Check admin-only restriction
        if config.admin_only then
            -- Use centralized admin checking (single source of truth)
            local Locations = require(ReplicatedStorage.Shared.Locations)
            local AdminChecker = require(Locations.SharedUtils.AdminChecker)
            local isAdmin = AdminChecker.IsCurrentPlayerAdmin()
            self.logger:info("🔍 BaseUI: Admin check for menu button", {
                buttonName = config.name,
                isAdmin = isAdmin,
                userId = Players.LocalPlayer.UserId
            })
            if not isAdmin then
                self.logger:info("🚫 BaseUI: Skipping admin button - user not authorized", {
                    buttonName = config.name
                })
                return nil  -- Skip admin button for non-admin users
            end
        end
        return self:_createMenuButtonElement(config, parent, layoutOrder)
        
    elseif elementType == "player_info" then
        return self:_createPlayerInfoElement(config, parent)
        
    elseif elementType == "quest_tracker" then
        return self:_createQuestTrackerElement(config, parent)
        
    elseif elementType == "pets_button" then
        return self:_createPetsButtonElement(config, parent)
        
    elseif elementType == "rewards_button" then
        return self:_createRewardsButtonElement(config, parent)
        
    else
        self.logger:warn("Unknown pane element type:", elementType)
        return nil
    end
end

-- === PANE ELEMENT FACTORIES ===
-- Create currency display element for panes (optimized for floating cards)
function BaseUI:_createCurrencyElement(config, parent, layoutOrder)
    local theme = self:_getCachedTheme()
    
    -- Currency frame (fills entire pane for floating card look)
    local frame = Instance.new("Frame")
    frame.Name = config.currency .. "Frame"
    frame.Size = UDim2.new(1, 0, 1, 0)  -- Fill entire pane
    frame.Position = UDim2.new(0, 0, 0, 0)
    frame.BackgroundTransparency = 1  -- Pane provides background
    frame.BorderSizePixel = 0
    frame.LayoutOrder = layoutOrder
    frame.Parent = parent
    
    -- Icon (supports both emoji and Roblox asset IDs)
    local icon
    local iconValue = config.icon or ""
    
    -- Check if icon is a Roblox asset ID (number or rbxassetid format)
    local assetId = nil
    if string.match(iconValue, "^rbxassetid://(%d+)$") then
        assetId = iconValue
    elseif string.match(iconValue, "^%d+$") then
        assetId = "rbxassetid://" .. iconValue
    end
    
    if assetId then
        -- Use ImageLabel for Roblox assets with error handling
        local success, result = pcall(function()
            icon = Instance.new("ImageLabel")
            icon.Name = "Icon"
            icon.Size = UDim2.new(0, 22, 0, 22)
            icon.Position = UDim2.new(0, 8, 0.5, -11)
            icon.BackgroundTransparency = 1
            icon.Image = assetId
            icon.ImageColor3 = config.color  -- Tint the asset
            icon.ScaleType = Enum.ScaleType.Fit
            icon.Parent = frame
            return icon
        end)
        
        if not success then
            self.logger:warn("Failed to create ImageLabel for currency asset '" .. tostring(assetId) .. "': " .. tostring(result))
            self.logger:warn("Falling back to emoji icon for currency: " .. tostring(config.currency))
            -- Fallback to emoji based on currency type
            local fallbackEmoji = config.currency == "coins" and "💰" or 
                                config.currency == "gems" and "💎" or 
                                config.currency == "crystals" and "🔮" or "💰"
            icon = Instance.new("TextLabel")
            icon.Name = "Icon"
            icon.Size = UDim2.new(0, 22, 0, 22)
            icon.Position = UDim2.new(0, 8, 0.5, -11)
            icon.BackgroundTransparency = 1
            icon.Text = fallbackEmoji
            icon.TextColor3 = config.color
            icon.TextScaled = true
            icon.Font = Enum.Font.GothamBold
            icon.Parent = frame
        end
    else
        -- Use TextLabel for emoji
        icon = Instance.new("TextLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.new(0, 22, 0, 22)
        icon.Position = UDim2.new(0, 8, 0.5, -11)
        icon.BackgroundTransparency = 1
        icon.Text = iconValue
        icon.TextColor3 = config.color
        icon.TextScaled = true
        icon.Font = Enum.Font.GothamBold
        icon.Parent = frame
    end
    
    -- Amount label (optimized for floating card)
    local amount = Instance.new("TextLabel")
    amount.Name = "Amount"
    amount.Size = UDim2.new(1, -35, 1, 0)  -- Fill remaining space
    amount.Position = UDim2.new(0, 35, 0, 0)
    amount.BackgroundTransparency = 1
    local realAmount = self.player:GetAttribute(config.currency:gsub("^%l", string.upper)) or 0
    amount.Text = self:_formatNumber(realAmount)
    amount.TextColor3 = Color3.fromRGB(255, 255, 255)  -- Clean white text
    amount.TextScaled = true
    amount.Font = Enum.Font.GothamBold
    amount.TextXAlignment = Enum.TextXAlignment.Center  -- Center align for cards
    amount.Parent = frame
    
    -- Add subtle drop shadow effect for depth
    local shadow = Instance.new("TextLabel")
    shadow.Name = "Shadow"
    shadow.Size = amount.Size
    shadow.Position = UDim2.new(amount.Position.X.Scale, amount.Position.X.Offset + 1, amount.Position.Y.Scale, amount.Position.Y.Offset + 1)
    shadow.BackgroundTransparency = 1
    shadow.Text = amount.Text
    shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
    shadow.TextTransparency = 0.5
    shadow.TextScaled = true
    shadow.Font = Enum.Font.GothamBold
    shadow.TextXAlignment = Enum.TextXAlignment.Center
    shadow.ZIndex = amount.ZIndex - 1
    shadow.Parent = frame
    
    -- Store reference for updates (include shadow for animations)
    self.currencyDisplays[config.currency] = {
        frame = frame,
        amount = amount,
        shadow = shadow,
        icon = icon
    }
    
    -- Add subtle floating card hover effect
    self:_addHoverEffect(frame)
    
    return frame
end

-- Create professional image-based menu button element with layered components
function BaseUI:_createMenuButtonElement(config, parent, layoutOrder)
    print("🎨 Creating professional button for:", config.name)
    print("   📄 Background image:", config.background_image or "None (using fallback)")
    print("   🔔 Notification enabled:", config.notification and config.notification.enabled or false)
    
    -- Determine button type: ImageButton vs TextButton
    local button
    local processedBackgroundImage = self:_processAssetId(config.background_image)
    local hasBackgroundImage = processedBackgroundImage ~= nil
    
    print("   🔍 Debug asset processing:")
    print("     Raw value:", config.background_image, "Type:", type(config.background_image))
    print("     Processed:", processedBackgroundImage)
    print("     HasBackgroundImage:", hasBackgroundImage)
    
    if hasBackgroundImage then
        -- PROFESSIONAL MODE: ImageButton with custom background
        print("   ✨ Using ImageButton mode (professional)")
        button = Instance.new("ImageButton")
        button.Name = config.name .. "Button"
        button.Image = processedBackgroundImage
        button.ScaleType = Enum.ScaleType.Stretch
        button.ImageColor3 = Color3.fromRGB(255, 255, 255)
        button.BackgroundTransparency = 1 -- Let the image handle the background
        button.BorderSizePixel = 0
    else
        -- FALLBACK MODE: TextButton with programmatic styling  
        print("   🔄 Using TextButton mode (fallback)")
        button = Instance.new("TextButton")
        button.Name = config.name .. "Button" 
        button.BackgroundColor3 = config.color
        button.BorderSizePixel = 0
        
        -- Rounded corners for fallback mode
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 15)
        corner.Parent = button
        
        -- Gradient effect for fallback mode
        local gradient = Instance.new("UIGradient")
        gradient.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, config.color)
        }
        gradient.Rotation = 45
        gradient.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(1, 0)
        }
        gradient.Parent = button
        
        -- Border glow for fallback mode
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255, 255, 255)
        stroke.Thickness = 2
        stroke.Transparency = 0.8
        stroke.Parent = button
    end
    
    -- Common button properties
    if not hasBackgroundImage then
        -- Only TextButton has Text property
        button.Text = ""
    end
    button.LayoutOrder = layoutOrder
    button.ZIndex = 13
    button.Parent = parent
    
    -- LAYER 1: ICON (Center of button)
    local icon = self:_createButtonIcon(config, button)
    
    -- LAYER 2: NOTIFICATION BADGE (Top-right corner or configured position)
    local notification = self:_createButtonNotification(config, button)
    
    -- LAYER 3: TEXT LABEL (Bottom of button)
    local label = self:_createButtonLabel(config, button)
    
    -- Interactive effects
    button.Activated:Connect(function()
        self:_onMenuButtonClicked(config.name)
        self:_animateButtonPress(button)
    end)
    
    -- Hover effects (different for image vs text buttons)
    if hasBackgroundImage then
        self:_addImageButtonHoverEffect(button)
    else
        self:_addButtonHoverEffect(button, config.color)
    end
    
    -- Store reference
    self.menuButtons[config.name] = button
    
    print("   ✅ Professional button created successfully")
    return button
end

-- Create button icon layer (supports emoji and asset IDs with configurable sizing/positioning)
function BaseUI:_createButtonIcon(config, parent)
    local iconValue = config.icon or ""
    local assetId = self:_processAssetId(iconValue)
    local icon
    
    -- Get icon configuration with global defaults
    local iconConfig = self:_mergeWithDefaults(config.icon_config, "menu_button", "icon_config")
    
    -- Safety check and fallback to hardcoded defaults if merging failed
    if not iconConfig or not iconConfig.size then
        print("   ⚠️ WARNING: Defaults merging failed, using hardcoded fallbacks")
        iconConfig = {
            size = {scale_x = 0.4, scale_y = 0.4},
            position = {scale_x = 0.5, scale_y = 0.5},
            offset = {x = 0, y = 0}
        }
    end
    
    local iconSize = iconConfig.size
    local iconPosition = iconConfig.position  
    local iconOffset = iconConfig.offset
    
    print("   🎯 Icon configuration:")
    print("     Size: " .. (iconSize and iconSize.scale_x or "nil") .. "x" .. (iconSize and iconSize.scale_y or "nil") .. " (relative to button)")
    print("     Position: " .. (iconPosition and iconPosition.scale_x or "nil") .. "," .. (iconPosition and iconPosition.scale_y or "nil") .. " (relative)")
    print("     Offset: " .. (iconOffset and iconOffset.x or "nil") .. "," .. (iconOffset and iconOffset.y or "nil") .. " (pixels)")
    
    if assetId then
        print("   🖼️ Creating ImageLabel icon:", assetId)
        -- Use ImageLabel for Roblox assets with error handling
        local success, result = pcall(function()
            icon = Instance.new("ImageLabel")
            icon.Name = "Icon"
            icon.Size = UDim2.new(iconSize.scale_x, 0, iconSize.scale_y, 0)  -- Relative sizing
            icon.Position = UDim2.new(iconPosition.scale_x, iconOffset.x, iconPosition.scale_y, iconOffset.y)  -- Relative + offset
            icon.AnchorPoint = Vector2.new(0.5, 0.5)  -- Always center anchor as requested
            icon.BackgroundTransparency = 1
            icon.Image = assetId
            icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
            icon.ScaleType = Enum.ScaleType.Fit
            return icon
        end)
        
        if not success then
            print("   ❌ Icon asset failed, using emoji fallback")
            icon = self:_createEmojiIcon(config, parent, iconSize, iconPosition, iconOffset)
        end
    else
        print("   😀 Creating emoji icon:", iconValue)
        icon = self:_createEmojiIcon(config, parent, iconSize, iconPosition, iconOffset)
    end
    
    if icon then
        icon.ZIndex = 15
        icon.Parent = parent
    end
    
    return icon
end

-- Create emoji icon fallback with configurable sizing/positioning
function BaseUI:_createEmojiIcon(config, parent, iconSize, iconPosition, iconOffset)
    local iconValue = config.icon or ""
    local fallbackIcon = config.name == "Shop" and "🛒" or 
                        config.name == "Inventory" and "🎒" or 
                        config.name == "Effects" and "⚡" or 
                        config.name == "Settings" and "⚙️" or 
                        config.name == "Admin" and "👑" or 
                        iconValue ~= "" and iconValue or "📋"
    
    -- Use provided size/position or fallback to defaults
    iconSize = iconSize or {scale_x = 0.4, scale_y = 0.4}
    iconPosition = iconPosition or {scale_x = 0.5, scale_y = 0.5}
    iconOffset = iconOffset or {x = 0, y = 0}
                        
    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(iconSize.scale_x, 0, iconSize.scale_y, 0)  -- Relative sizing
    icon.Position = UDim2.new(iconPosition.scale_x, iconOffset.x, iconPosition.scale_y, iconOffset.y)  -- Relative + offset
    icon.AnchorPoint = Vector2.new(0.5, 0.5)  -- Always center anchor as requested
    icon.BackgroundTransparency = 1
    icon.Text = fallbackIcon
    icon.TextColor3 = Color3.fromRGB(255, 255, 255)
    icon.TextScaled = true
    icon.Font = Enum.Font.GothamBold
    
    return icon
end

-- Create notification badge layer
function BaseUI:_createButtonNotification(config, parent)
    local notifConfig = config.notification
    if not notifConfig or not notifConfig.enabled then
        return nil
    end
    
    print("   🔔 Creating notification badge:", notifConfig.text)
    
    -- Notification badge background
    local notification = Instance.new("Frame")
    notification.Name = "Notification"
    notification.BackgroundColor3 = notifConfig.background_color or Color3.fromRGB(255, 0, 0)
    notification.BorderSizePixel = 0
    notification.ZIndex = 16
    
    -- Position based on config (default: top-right)
    local position = notifConfig.position or "top-right"
    
    -- INSIDE POSITIONS (traditional, within button boundaries)
    if position == "top-right" then
        notification.Size = UDim2.new(0, 25, 0, 25)
        notification.Position = UDim2.new(1, -5, 0, 5)
        notification.AnchorPoint = Vector2.new(1, 0)
    elseif position == "top-left" then
        notification.Size = UDim2.new(0, 25, 0, 25)
        notification.Position = UDim2.new(0, 5, 0, 5)
        notification.AnchorPoint = Vector2.new(0, 0)
    elseif position == "bottom-right" then
        notification.Size = UDim2.new(0, 25, 0, 25)
        notification.Position = UDim2.new(1, -5, 1, -5)
        notification.AnchorPoint = Vector2.new(1, 1)
    elseif position == "bottom-left" then
        notification.Size = UDim2.new(0, 25, 0, 25)
        notification.Position = UDim2.new(0, 5, 1, -5)
        notification.AnchorPoint = Vector2.new(0, 1)
        
    -- CORNER POSITIONS (extended outside button boundaries for prominence)
    elseif position == "top-right-corner" then
        notification.Size = UDim2.new(0, 25, 0, 25)
        notification.Position = UDim2.new(1, 5, 0, -5)  -- Extends outside
        notification.AnchorPoint = Vector2.new(1, 0)  -- Fixed: Right edge, top edge
    elseif position == "top-left-corner" then
        notification.Size = UDim2.new(0, 25, 0, 25)
        notification.Position = UDim2.new(0, -5, 0, -5)  -- Extends outside
        notification.AnchorPoint = Vector2.new(0, 0)  -- Fixed: Left edge, top edge
    elseif position == "bottom-right-corner" then
        notification.Size = UDim2.new(0, 25, 0, 25)
        notification.Position = UDim2.new(1, 5, 1, 5)  -- Extends outside
        notification.AnchorPoint = Vector2.new(1, 1)  -- Fixed: Right edge, bottom edge
    elseif position == "bottom-left-corner" then
        notification.Size = UDim2.new(0, 25, 0, 25)
        notification.Position = UDim2.new(0, -5, 1, 5)  -- Extends outside
        notification.AnchorPoint = Vector2.new(0, 1)  -- Fixed: Left edge, bottom edge
    end
    
    notification.Parent = parent
    
    -- Rounded corners for notification
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0) -- Perfect circle
    corner.Parent = notification
    
    -- Notification text
    local text = Instance.new("TextLabel")
    text.Name = "NotificationText"
    text.Size = UDim2.new(1, 0, 1, 0)
    text.Position = UDim2.new(0, 0, 0, 0)
    text.BackgroundTransparency = 1
    text.Text = tostring(notifConfig.text or "!")
    text.TextColor3 = notifConfig.text_color or Color3.fromRGB(255, 255, 255)
    text.TextScaled = true
    text.Font = Enum.Font.GothamBold
    text.ZIndex = 17
    text.Parent = notification
    
    -- Add subtle glow effect
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = notification
    
    return notification
end

-- Create button text label layer with configurable font and sizing
function BaseUI:_createButtonLabel(config, parent)
    -- Get text configuration with global defaults
    local textConfig = self:_mergeWithDefaults(config.text_config, "menu_button", "text_config")
    
    -- Safety check and fallback to hardcoded defaults if merging failed
    if not textConfig or not textConfig.font then
        print("   ⚠️ WARNING: Text defaults merging failed, using hardcoded fallbacks")
        textConfig = {
            font = Enum.Font.GothamBold,
            size = {height = 20, margin = 10},
            color = Color3.fromRGB(255, 255, 255),
            text_scaled = true,
            text_size = 14,
            position = {bottom_offset = 25, side_margin = 5},
            shadow = {
                enabled = true,
                color = Color3.fromRGB(0, 0, 0),
                thickness = 2,
                transparency = 0.5
            }
        }
    end
    
    local font = textConfig.font
    local textSize = textConfig.size
    local textColor = textConfig.color
    local useTextScaled = textConfig.text_scaled
    local textPosition = textConfig.position
    
    print("   📝 Text configuration:")
    print("     Font: " .. tostring(font))
    print("     Height: " .. textSize.height .. "px, Margin: " .. textSize.margin .. "px")
    print("     Color: " .. tostring(textColor))
    print("     Text Scaled: " .. tostring(useTextScaled))
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, -textSize.margin * 2, 0, textSize.height)  -- Configurable size
    label.Position = UDim2.new(0, textPosition.side_margin, 1, -textPosition.bottom_offset)  -- Configurable position
    label.AnchorPoint = Vector2.new(0, 0)
    label.BackgroundTransparency = 1
    label.Text = config.text or config.name
    label.TextColor3 = textColor  -- Configurable color
    label.TextScaled = useTextScaled  -- Configurable scaling
    label.Font = font  -- Configurable font
    label.ZIndex = 15
    
    -- If TextScaled is disabled, set a specific text size
    if not useTextScaled then
        label.TextSize = textConfig.text_size or 14  -- Default 14pt when not scaled
    end
    
    label.Parent = parent
    
    -- Add text shadow for better readability (configurable)
    local shadowConfig = textConfig.shadow
    if shadowConfig.enabled then
        local shadow = Instance.new("UIStroke")
        shadow.Color = shadowConfig.color
        shadow.Thickness = shadowConfig.thickness
        shadow.Transparency = shadowConfig.transparency
        shadow.Parent = label
    end
    
    return label
end

-- Merge specific configuration with global defaults
function BaseUI:_mergeWithDefaults(specificConfig, elementType, configType)
    -- Load UI configuration
    local ConfigLoader = require(game.ReplicatedStorage.Shared.ConfigLoader)
    local uiConfig = ConfigLoader:LoadConfig("ui")
    
    print("   🔍 DEBUG _mergeWithDefaults:")
    print("     elementType:", elementType, "configType:", configType)
    print("     uiConfig.defaults exists:", uiConfig.defaults ~= nil)
    
    -- Get global defaults
    local defaults = uiConfig.defaults and uiConfig.defaults[elementType] and uiConfig.defaults[elementType][configType] or {}
    
    print("     defaults found:", defaults ~= nil, "defaults empty:", next(defaults) == nil)
    print("     specificConfig provided:", specificConfig ~= nil)
    
    -- If no specific config provided, return deep copy of defaults
    if not specificConfig then
        local result = self:_deepCopy(defaults)
        print("     returning defaults copy, has size:", result.size ~= nil)
        return result
    end
    
    -- Merge specific config with defaults (specific overrides defaults)
    local result = self:_deepMerge(defaults, specificConfig)
    print("     returning merged config, has size:", result.size ~= nil)
    return result
end

-- Deep copy a table
function BaseUI:_deepCopy(original)
    if type(original) ~= 'table' then return original end
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = self:_deepCopy(value)
    end
    return copy
end

-- Deep merge two tables (second overrides first)
function BaseUI:_deepMerge(default, override)
    local result = self:_deepCopy(default)
    
    if type(override) ~= 'table' then
        return override
    end
    
    for key, value in pairs(override) do
        if type(value) == 'table' and type(result[key]) == 'table' then
            result[key] = self:_deepMerge(result[key], value)
        else
            result[key] = value
        end
    end
    
    return result
end

-- Process asset ID (handles various formats: numbers, strings, rbxassetid://)
function BaseUI:_processAssetId(value)
    if not value or value == "" then
        return nil
    end
    
    -- Convert number to string if needed
    local valueStr = tostring(value)
    
    if string.match(valueStr, "^rbxassetid://(%d+)$") then
        return valueStr
    elseif string.match(valueStr, "^%d+$") then
        return "rbxassetid://" .. valueStr
    end
    
    return nil
end

-- Add hover effect for ImageButtons
function BaseUI:_addImageButtonHoverEffect(button)
    local tweenService = game:GetService("TweenService")
    local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    
    button.MouseEnter:Connect(function()
        local hoverTween = tweenService:Create(button, tweenInfo, {
            ImageColor3 = Color3.fromRGB(200, 200, 200),
            Size = button.Size + UDim2.new(0, 4, 0, 4)
        })
        hoverTween:Play()
    end)
    
    button.MouseLeave:Connect(function()
        local leaveTween = tweenService:Create(button, tweenInfo, {
            ImageColor3 = Color3.fromRGB(255, 255, 255),
            Size = button.Size - UDim2.new(0, 4, 0, 4)
        })
        leaveTween:Play()
    end)
end

-- Create player info element for panes
function BaseUI:_createPlayerInfoElement(config, parent)
    local theme = self:_getCachedTheme()
    
    -- Player name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "PlayerName"
    nameLabel.Size = UDim2.new(1, -20, 0, 25)
    nameLabel.Position = UDim2.new(0, 10, 0, 8)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "👤 " .. Players.LocalPlayer.Name
    nameLabel.TextColor3 = theme.text.primary
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.ZIndex = 13
    nameLabel.Parent = parent
    
    -- Level and XP
    local levelLabel = Instance.new("TextLabel")
    levelLabel.Name = "LevelInfo"
    levelLabel.Size = UDim2.new(1, -20, 0, 20)
    levelLabel.Position = UDim2.new(0, 10, 0, 35)
    levelLabel.BackgroundTransparency = 1
    levelLabel.Text = "Level " .. self.playerData.level .. " • " .. self.playerData.xp .. "/" .. self.playerData.maxXp .. " XP"
    levelLabel.TextColor3 = theme.text.secondary
    levelLabel.TextScaled = true
    levelLabel.Font = Enum.Font.Gotham
    levelLabel.TextXAlignment = Enum.TextXAlignment.Center
    levelLabel.ZIndex = 13
    levelLabel.Parent = parent
    
    return nameLabel
end

-- Create quest tracker element for panes
function BaseUI:_createQuestTrackerElement(config, parent)
    local theme = self:_getCachedTheme()
    
    -- Check if this is a combined pane (has other children) and adjust positioning
    local yOffset = 70  -- Position below player info when combined
    if #parent:GetChildren() <= 1 then
        yOffset = 8  -- Original position when standalone
    end
    
    -- Quest title
    local title = Instance.new("TextLabel")
    title.Name = "QuestTitle"
    title.Size = UDim2.new(1, -20, 0, 25)
    title.Position = UDim2.new(0, 10, 0, yOffset)
    title.BackgroundTransparency = 1
    title.Text = "🎯 Current Quest"
    title.TextColor3 = Color3.fromRGB(255, 215, 0)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Center  -- Center align for combined layout
    title.ZIndex = 13
    title.Parent = parent
    
    -- Quest description
    local description = Instance.new("TextLabel")
    description.Name = "QuestDescription"
    description.Size = UDim2.new(1, -20, 0, 35)
    description.Position = UDim2.new(0, 10, 0, yOffset + 27)
    description.BackgroundTransparency = 1
    description.Text = self.questData.currentQuest
    description.TextColor3 = theme.text.primary
    description.TextScaled = true
    description.Font = Enum.Font.Gotham
    description.TextXAlignment = Enum.TextXAlignment.Center  -- Center align for combined layout
    description.TextWrapped = true
    description.ZIndex = 13
    description.Parent = parent
    
    -- Progress bar background
    local progressBG = Instance.new("Frame")
    progressBG.Name = "ProgressBackground"
    progressBG.Size = UDim2.new(1, -20, 0, 15)
    progressBG.Position = UDim2.new(0, 10, 0, yOffset + 67)
    progressBG.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    progressBG.BorderSizePixel = 0
    progressBG.ZIndex = 13
    progressBG.Parent = parent
    
    local progressCorner = Instance.new("UICorner")
    progressCorner.CornerRadius = UDim.new(0, 8)
    progressCorner.Parent = progressBG
    
    -- Progress bar fill
    local progressFill = Instance.new("Frame")
    progressFill.Name = "ProgressFill"
    progressFill.Size = UDim2.new(self.questData.progress / self.questData.maxProgress, 0, 1, 0)
    progressFill.Position = UDim2.new(0, 0, 0, 0)
    progressFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    progressFill.BorderSizePixel = 0
    progressFill.ZIndex = 14
    progressFill.Parent = progressBG
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 8)
    fillCorner.Parent = progressFill
    
    -- Progress text
    local progressText = Instance.new("TextLabel")
    progressText.Name = "ProgressText"
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.Position = UDim2.new(0, 0, 0, 0)
    progressText.BackgroundTransparency = 1
    progressText.Text = self.questData.progress .. "/" .. self.questData.maxProgress
    progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
    progressText.TextScaled = true
    progressText.Font = Enum.Font.GothamBold
    progressText.ZIndex = 15
    progressText.Parent = progressBG
    
    return title
end

-- Create pets button element for panes
function BaseUI:_createPetsButtonElement(config, parent)
    -- Check if we're using an asset ID or emoji/text
    local iconValue = config.icon or ""
    local isAssetId = string.match(iconValue, "^%d+$") or string.match(iconValue, "^rbxassetid://(%d+)$")
    local assetId = nil
    
    if string.match(iconValue, "^rbxassetid://(%d+)$") then
        assetId = iconValue
    elseif string.match(iconValue, "^%d+$") then
        assetId = "rbxassetid://" .. iconValue
    end
    
    -- Create appropriate button type
    local petsButton
    if isAssetId then
        -- Use ImageButton for assets - cleaner and more efficient
        petsButton = Instance.new("ImageButton")
        petsButton.Name = "PetsButton"
        petsButton.Size = UDim2.new(1, 0, 1, 0)
        petsButton.BackgroundColor3 = config.color
        petsButton.BorderSizePixel = 0
        petsButton.Image = assetId
        petsButton.ImageColor3 = Color3.fromRGB(255, 255, 255)
        petsButton.ScaleType = Enum.ScaleType.Fit
        petsButton.ZIndex = 15
        petsButton.Parent = parent
    else
        -- Use TextButton for emoji/text
        petsButton = Instance.new("TextButton")
        petsButton.Name = "PetsButton"
        petsButton.Size = UDim2.new(1, 0, 1, 0)
        petsButton.BackgroundColor3 = config.color
        petsButton.BorderSizePixel = 0
        petsButton.Text = iconValue
        petsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        petsButton.TextScaled = true
        petsButton.Font = Enum.Font.GothamBold
        petsButton.ZIndex = 15
        petsButton.Parent = parent
    end
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 25)
    corner.Parent = petsButton
    
    -- Gradient effect
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, config.color)
    }
    gradient.Rotation = 45
    gradient.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0)
    }
    gradient.Parent = petsButton
    
    -- Border glow
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 2
    stroke.Transparency = 0.5
    stroke.Parent = petsButton
    
    -- Add text label for "Pets" text (positioned at bottom for both button types)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 18)
    label.Position = UDim2.new(0, 0, 1, -22)  -- Position at bottom of button
    label.BackgroundTransparency = 1
    label.Text = config.text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.ZIndex = 16
    label.Parent = petsButton
    
    -- Click handling
    petsButton.Activated:Connect(function()
        self:_onMenuButtonClicked("Inventory")
        self:_animateButtonPress(petsButton)
    end)
    
    -- Hover effects
    self:_addButtonHoverEffect(petsButton, config.color)
    
    return petsButton
end

-- Create rewards button element for panes
function BaseUI:_createRewardsButtonElement(config, parent)
    -- Rewards button
    local rewardsButton = Instance.new("TextButton")
    rewardsButton.Name = "RewardsButton"
    rewardsButton.Size = UDim2.new(1, 0, 1, 0)
    rewardsButton.BackgroundColor3 = config.color
    rewardsButton.BorderSizePixel = 0
    rewardsButton.Text = ""
    rewardsButton.ZIndex = 13
    rewardsButton.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 15)
    corner.Parent = rewardsButton
    
    -- Gradient
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, config.color)
    }
    gradient.Rotation = 45
    gradient.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 0)
    }
    gradient.Parent = rewardsButton
    
    -- Border
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 2
    stroke.Transparency = 0.5
    stroke.Parent = rewardsButton
    
    -- Icon (supports both emoji and Roblox asset IDs)
    local icon
    local iconValue = config.icon or ""
    
    -- Check if icon is a Roblox asset ID (number or rbxassetid format)
    local assetId = nil
    if string.match(iconValue, "^rbxassetid://(%d+)$") then
        assetId = iconValue
    elseif string.match(iconValue, "^%d+$") then
        assetId = "rbxassetid://" .. iconValue
    end
    
    if assetId then
        -- Use ImageLabel for Roblox assets with error handling
        local success, result = pcall(function()
            icon = Instance.new("ImageLabel")
            icon.Size = UDim2.new(0, 25, 0, 25)
            icon.Position = UDim2.new(0, 10, 0.5, -12)
            icon.BackgroundTransparency = 1
            icon.Image = assetId
            icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
            icon.ScaleType = Enum.ScaleType.Fit
            icon.ZIndex = 14
            icon.Parent = rewardsButton
            return icon
        end)
        
        if not success then
            self.logger:warn("Failed to create ImageLabel for rewards button asset '" .. tostring(assetId) .. "': " .. tostring(result))
            self.logger:warn("Falling back to emoji icon for rewards button")
            -- Fallback to gift emoji
            icon = Instance.new("TextLabel")
            icon.Size = UDim2.new(0, 25, 0, 25)
            icon.Position = UDim2.new(0, 10, 0.5, -12)
            icon.BackgroundTransparency = 1
            icon.Text = "🎁"  -- Fallback gift emoji
            icon.TextScaled = true
            icon.Font = Enum.Font.GothamBold
            icon.ZIndex = 14
            icon.Parent = rewardsButton
        end
    else
        -- Use TextLabel for emoji
        icon = Instance.new("TextLabel")
        icon.Size = UDim2.new(0, 25, 0, 25)
        icon.Position = UDim2.new(0, 10, 0.5, -12)
        icon.BackgroundTransparency = 1
        icon.Text = iconValue
        icon.TextScaled = true
        icon.Font = Enum.Font.GothamBold
        icon.ZIndex = 14
        icon.Parent = rewardsButton
    end
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -45, 1, 0)
    label.Position = UDim2.new(0, 40, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = config.text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.ZIndex = 14
    label.Parent = rewardsButton
    
    -- Notification badge
    if config.badge_count and config.badge_count > 0 then
        local badge = Instance.new("Frame")
        badge.Name = "NotificationBadge"
        badge.Size = UDim2.new(0, 20, 0, 20)
        badge.Position = UDim2.new(1, -5, 0, -5)
        badge.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
        badge.BorderSizePixel = 0
        badge.ZIndex = 15
        badge.Parent = rewardsButton
        
        local badgeCorner = Instance.new("UICorner")
        badgeCorner.CornerRadius = UDim.new(0.5, 0)
        badgeCorner.Parent = badge
        
        local badgeText = Instance.new("TextLabel")
        badgeText.Size = UDim2.new(1, 0, 1, 0)
        badgeText.BackgroundTransparency = 1
        badgeText.Text = tostring(config.badge_count)
        badgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
        badgeText.TextScaled = true
        badgeText.Font = Enum.Font.GothamBold
        badgeText.ZIndex = 16
        badgeText.Parent = badge
    end
    
    -- Click handling
    rewardsButton.Activated:Connect(function()
        self:_onRewardsButtonClicked()
        self:_animateButtonPress(rewardsButton)
    end)
    
    self:_addButtonHoverEffect(rewardsButton, config.color)
    
    return rewardsButton
end

-- Performance optimization: Cache theme lookups
function BaseUI:_getCachedTheme()
    if not self.cachedTheme then
        self.cachedTheme = self.uiConfig.helpers.get_theme(self.uiConfig)
    end
    return self.cachedTheme
end

-- Add simple hover effect to frames
function BaseUI:_addHoverEffect(frame)
    local originalTransparency = frame.BackgroundTransparency
    
    frame.MouseEnter:Connect(function()
        local tween = TweenService:Create(frame, 
            TweenInfo.new(0.15, Enum.EasingStyle.Quad), 
            {BackgroundTransparency = math.max(0, originalTransparency - 0.1)}
        )
        tween:Play()
    end)
    
    frame.MouseLeave:Connect(function()
        local tween = TweenService:Create(frame, 
            TweenInfo.new(0.15, Enum.EasingStyle.Quad), 
            {BackgroundTransparency = originalTransparency}
        )
        tween:Play()
    end)
end

-- Create the top status bar
function BaseUI:_createTopBar()
    local theme = self.uiConfig.helpers.get_theme(self.uiConfig)
    
    -- Top bar background
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 8)
    topBar.Position = UDim2.new(0, 0, 0, 0)
    topBar.BackgroundColor3 = theme.primary.accent
    topBar.BorderSizePixel = 0
    topBar.ZIndex = 15
    topBar.Parent = self.mainFrame
    
    -- Add gradient effect
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 150, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 200, 150))
    }
    gradient.Parent = topBar
end

-- DEPRECATED METHODS REMOVED - Now using pane-based system
-- Currency displays are now created via _createCurrencyElement in pane factories

-- DEPRECATED METHODS REMOVED - Now using pane-based system  
-- Menu buttons are now created via _createMenuButtonElement in pane factories

-- DEPRECATED METHODS REMOVED - Now using pane-based system
-- Quest tracker is now created via _createQuestTrackerElement in pane factories

-- DEPRECATED METHODS REMOVED - Now using pane-based system
-- Rewards button is now created via _createRewardsButtonElement in pane factories

-- DEPRECATED METHODS REMOVED - Now using pane-based system
-- Player info is now created via _createPlayerInfoElement in pane factories

-- DEPRECATED METHODS REMOVED - Now using pane-based system
-- Pets button is now created via _createPetsButtonElement in pane factories

-- Helper functions for enhanced features
function BaseUI:_formatNumber(number)
    -- Handle negative numbers
    local isNegative = number < 0
    number = math.abs(number)
    
    -- Number formatting similar to Short module in working MCP example
    local suffixes = {
        {1e15, "Qa"},  -- Quadrillion
        {1e12, "T"},   -- Trillion  
        {1e9,  "B"},   -- Billion
        {1e6,  "M"},   -- Million
        {1e3,  "K"}    -- Thousand
    }
    
    for _, suffix in ipairs(suffixes) do
        if number >= suffix[1] then
            local formatted = number / suffix[1]
            -- Show decimals only if needed and meaningful
            if formatted >= 100 then
                formatted = string.format("%.0f%s", formatted, suffix[2])
            elseif formatted >= 10 then
                formatted = string.format("%.1f%s", formatted, suffix[2])
            else
                formatted = string.format("%.2f%s", formatted, suffix[2])
            end
            
            return isNegative and "-" .. formatted or formatted
        end
    end
    
    -- For numbers less than 1000, show whole number
    local result = tostring(math.floor(number))
    return isNegative and "-" .. result or result
end

function BaseUI:_addHoverEffect(element)
    local originalTransparency = element.BackgroundTransparency
    
    element.MouseEnter:Connect(function()
        local tween = TweenService:Create(element, 
            TweenInfo.new(0.2, Enum.EasingStyle.Quad), 
            {BackgroundTransparency = originalTransparency - 0.1}
        )
        tween:Play()
    end)
    
    element.MouseLeave:Connect(function()
        local tween = TweenService:Create(element, 
            TweenInfo.new(0.2, Enum.EasingStyle.Quad), 
            {BackgroundTransparency = originalTransparency}
        )
        tween:Play()
    end)
end

function BaseUI:_addButtonHoverEffect(button, originalColor)
    button.MouseEnter:Connect(function()
        local tween = TweenService:Create(button, 
            TweenInfo.new(0.15, Enum.EasingStyle.Quad), 
            {
                BackgroundColor3 = Color3.new(
                    math.min(1, originalColor.R + 0.1),
                    math.min(1, originalColor.G + 0.1),
                    math.min(1, originalColor.B + 0.1)
                )
            }
        )
        tween:Play()
    end)
    
    button.MouseLeave:Connect(function()
        local tween = TweenService:Create(button, 
            TweenInfo.new(0.15, Enum.EasingStyle.Quad), 
            {
                BackgroundColor3 = originalColor
            }
        )
        tween:Play()
    end)
end

function BaseUI:_animateButtonPress(button)
    local originalSize = button.Size
    
    local shrink = TweenService:Create(button,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad),
        {Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset - 5, originalSize.Y.Scale, originalSize.Y.Offset - 5)}
    )
    
    shrink:Play()
    shrink.Completed:Connect(function()
        local expand = TweenService:Create(button,
            TweenInfo.new(0.1, Enum.EasingStyle.Quad),
            {Size = originalSize}
        )
        expand:Play()
    end)
end

function BaseUI:_startAnimations()
    -- Breathing effect for quest tracker border
    local questTracker = self.mainFrame:FindFirstChild("QuestTracker")
    if questTracker and questTracker:FindFirstChild("UIStroke") then
        local stroke = questTracker:FindFirstChild("UIStroke")
        
        local breathe = TweenService:Create(stroke,
            TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            {Transparency = 0.7}
        )
        breathe:Play()
        table.insert(self.animations, breathe)
    end
end

-- Event handlers
function BaseUI:_onMenuButtonClicked(menuName)
    self.logger:info("Professional menu button clicked:", menuName)
    
    if not self.menuManager then
        self.logger:warn("MenuManager not set")
        return
    end
    
    -- Get transition effect from action configuration system
    -- This integrates with our configuration-as-code animation system
    local transitionEffect = self:_getTransitionForMenu(menuName)
    
    self.logger:info("Opening panel with transition:", transitionEffect)
    self.menuManager:TogglePanel(menuName, transitionEffect)
end

-- Get transition effect for a menu based on action configuration and animation showcase
-- This function implements a priority system for animation selection:
-- 1. Animation showcase overrides (for testing/development)
-- 2. Action configuration transitions (production settings)
-- 3. Default fallback animation
function BaseUI:_getTransitionForMenu(menuName)
    -- Priority 1: Check animation showcase overrides first
    -- This allows developers to easily test different animations without changing production config
    if self.uiConfig.animation_showcase and self.uiConfig.animation_showcase.enabled then
        if self.uiConfig.animation_showcase.override_animations then
            local overrideEffect = self.uiConfig.animation_showcase.test_effects[menuName:lower()]
            if overrideEffect then
                self.logger:info("Using animation showcase override for", menuName, ":", overrideEffect)
                return overrideEffect
            end
        end
    end
    
    -- Priority 2: Get transition from action configuration
    -- Each menu button can have its own unique transition defined in the action system
    local actionName = menuName:lower() .. "_action"
    local actionConfig = self.uiConfig.helpers.get_action_config(self.uiConfig, actionName)
    
    if actionConfig and actionConfig.transition then
        self.logger:info("Using action transition for", menuName, ":", actionConfig.transition)
        return actionConfig.transition
    end
    
    -- Priority 3: Fallback to default
    -- Ensures we always have a working animation even if configuration is incomplete
    local defaultEffect = "slide_in_right"
    if self.uiConfig.animations and self.uiConfig.animations.menu_transitions then
        defaultEffect = self.uiConfig.animations.menu_transitions.default_effect or defaultEffect
    end
    
    self.logger:info("Using default transition for", menuName, ":", defaultEffect)
    return defaultEffect
end

function BaseUI:_onRewardsButtonClicked()
    self.logger:info("Rewards button clicked")
    -- Handle rewards logic here
end

-- Update methods for real-time data (now uses player attributes automatically)
function BaseUI:UpdateCurrencies(currencies)
    -- This method is now mostly handled by _setupCurrencyUpdates()
    -- But we can still support manual updates if needed
    for currencyType, amount in pairs(currencies) do
        if self.currencyDisplays[currencyType] then
            local display = self.currencyDisplays[currencyType]
            display.amount.Text = self:_formatNumber(amount)
            
            -- Animate the update
            local tween = TweenService:Create(display.amount,
                TweenInfo.new(0.3, Enum.EasingStyle.Bounce),
                {TextColor3 = Color3.fromRGB(0, 255, 0)}
            )
            tween:Play()
            
            tween.Completed:Connect(function()
                local resetTween = TweenService:Create(display.amount,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad),
                    {TextColor3 = Color3.fromRGB(255, 255, 255)}
                )
                resetTween:Play()
            end)
        end
    end
end

function BaseUI:UpdatePlayerData(data)
    if data.level then self.playerData.level = data.level end
    if data.xp then self.playerData.xp = data.xp end
    if data.maxXp then self.playerData.maxXp = data.maxXp end
    
    -- Update UI elements if they exist
    local playerInfo = self.mainFrame:FindFirstChild("PlayerInfo")
    if playerInfo then
        local levelLabel = playerInfo:FindFirstChild("LevelInfo")
        if levelLabel then
            levelLabel.Text = "Level " .. self.playerData.level .. " • " .. self.playerData.xp .. "/" .. self.playerData.maxXp .. " XP"
        end
        
        local xpFill = playerInfo:FindFirstChild("XPBackground"):FindFirstChild("XPFill")
        if xpFill then
            local tween = TweenService:Create(xpFill,
                TweenInfo.new(0.5, Enum.EasingStyle.Quad),
                {Size = UDim2.new(self.playerData.xp / self.playerData.maxXp, 0, 1, 0)}
            )
            tween:Play()
        end
    end
end

-- Setup real-time currency updates like working MCP example
function BaseUI:_setupCurrencyUpdates()
    -- Store previous values to detect changes
    local previousValues = {}
    
    -- Update currency displays when player attributes change (like working TestEconomyGUI)
    local function updateAllCurrencies()
        for currencyType, display in pairs(self.currencyDisplays) do
            if display and display.amount then
                local attributeName = currencyType:gsub("^%l", string.upper) -- coins -> Coins
                local realAmount = self.player:GetAttribute(attributeName) or 0
                local previousAmount = previousValues[currencyType] or 0
                
                -- Update the text
                local formattedAmount = self:_formatNumber(realAmount)
                display.amount.Text = formattedAmount
                
                -- Update shadow text if it exists (for floating cards)
                if display.shadow then
                    display.shadow.Text = formattedAmount
                end
                
                -- Animate if value changed (and not initial load)
                if previousAmount > 0 and realAmount ~= previousAmount then
                    self:_animateCurrencyUpdate(display, realAmount - previousAmount)
                end
                
                -- Store current value for next comparison
                previousValues[currencyType] = realAmount
            end
        end
    end
    
    -- Connect to attribute changes for real-time updates
    self.player:GetAttributeChangedSignal("Coins"):Connect(updateAllCurrencies)
    self.player:GetAttributeChangedSignal("Gems"):Connect(updateAllCurrencies)
    self.player:GetAttributeChangedSignal("Crystals"):Connect(updateAllCurrencies)
    
    -- Initial update after a short delay
    task.spawn(function()
        task.wait(1) -- Wait for data to load
        updateAllCurrencies()
    end)
    
    self.logger:info("Currency update system initialized with animations")
end

-- Animate currency updates with visual feedback for floating cards
function BaseUI:_animateCurrencyUpdate(display, changeAmount)
    if not display or not display.amount or not display.frame then
        return
    end
    
    local isPositive = changeAmount > 0
    local color = isPositive and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 100, 100)
    local originalColor = Color3.fromRGB(255, 255, 255)
    
    -- Create floating text for change amount (outside the card)
    local changeText = Instance.new("TextLabel")
    changeText.Name = "ChangeIndicator"
    changeText.Size = UDim2.new(0, 50, 0, 20)
    changeText.Position = UDim2.new(1, 5, 0.5, -10)
    changeText.BackgroundTransparency = 1
    changeText.Text = (isPositive and "+" or "") .. self:_formatNumber(changeAmount)
    changeText.TextColor3 = color
    changeText.TextScaled = true
    changeText.Font = Enum.Font.GothamBold
    changeText.TextTransparency = 0  -- Start visible
    changeText.ZIndex = 20
    changeText.Parent = display.frame
    
    -- Add stroke for better visibility
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = changeText
    
    -- Animate the main amount text with color change
    local mainTween = TweenService:Create(display.amount,
        TweenInfo.new(0.3, Enum.EasingStyle.Bounce),
        {TextColor3 = color}
    )
    
    -- Update shadow text directly (don't tween Text property)
    if display.shadow then
        display.shadow.Text = display.amount.Text
    end
    
    -- Animate floating card effect (subtle scale)
    local cardTween = TweenService:Create(display.frame,
        TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
        {Size = UDim2.new(1.05, 0, 1.05, 0)}  -- Slight scale up
    )
    
    -- Animate the floating change text with fade and float
    local floatTween = TweenService:Create(changeText,
        TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(1, 15, -0.3, 0),
            TextTransparency = 1
        }
    )
    
    -- Animate the stroke fade separately
    local strokeTween = TweenService:Create(stroke,
        TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Transparency = 1}
    )
    
    -- Start animations
    mainTween:Play()
    cardTween:Play()
    floatTween:Play()
    strokeTween:Play()
    
    -- Reset color animation
    mainTween.Completed:Connect(function()
        local resetTween = TweenService:Create(display.amount,
            TweenInfo.new(0.8, Enum.EasingStyle.Quad),
            {TextColor3 = originalColor}
        )
        resetTween:Play()
    end)
    
    -- Reset card scale
    cardTween.Completed:Connect(function()
        local resetCardTween = TweenService:Create(display.frame,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad),
            {Size = UDim2.new(1, 0, 1, 0)}  -- Back to normal
        )
        resetCardTween:Play()
    end)
    
    -- Clean up floating text
    floatTween.Completed:Connect(function()
        changeText:Destroy()
    end)
end

-- Setup networking and responsive scaling
function BaseUI:_setupNetworking()
    self.logger:info("Professional UI networking setup")
end

function BaseUI:_setupResponsiveScaling()
    -- Handle screen size changes using Camera ViewportSize instead of GetScreenResolution
    local camera = workspace.CurrentCamera
    local function onScreenSizeChanged()
        local viewportSize = camera.ViewportSize
        local scale = math.min(viewportSize.X / 1920, viewportSize.Y / 1080) -- Base resolution scaling
        
        -- Update UI scaling here if needed
        self.logger:debug("Screen size changed, scale factor:", scale)
    end
    
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(onScreenSizeChanged)
    onScreenSizeChanged() -- Initial setup
end

-- === DEBUG VISUALIZATION METHODS ===

-- Add visual bounds to see pane boundaries
function BaseUI:_addDebugBounds(paneContainer, paneName)
    local debugFrame = Instance.new("Frame")
    debugFrame.Name = "DebugBounds_" .. paneName
    debugFrame.Size = UDim2.new(1, 0, 1, 0)
    debugFrame.Position = UDim2.new(0, 0, 0, 0)
    debugFrame.BackgroundTransparency = 0.7
    debugFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Red border
    debugFrame.BorderSizePixel = 0
    debugFrame.ZIndex = 999
    debugFrame.Parent = paneContainer
    
    -- Add border stroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 0) -- Yellow border
    stroke.Thickness = 2
    stroke.Transparency = 0
    stroke.Parent = debugFrame
    
    -- Add pane name label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0, 20)
    nameLabel.Position = UDim2.new(0, 0, 0, -25)
    nameLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.BackgroundTransparency = 0.3
    nameLabel.Text = paneName
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.ZIndex = 1000
    nameLabel.Parent = debugFrame
end

-- Add visual indicator for anchor point
function BaseUI:_addDebugAnchorPoint(paneContainer, anchorPoint, paneName)
    local anchorIndicator = Instance.new("Frame")
    anchorIndicator.Name = "DebugAnchor_" .. paneName
    anchorIndicator.Size = UDim2.new(0, 10, 0, 10)
    anchorIndicator.Position = UDim2.new(anchorPoint.X, -5, anchorPoint.Y, -5) -- Center on anchor point
    anchorIndicator.BackgroundColor3 = Color3.fromRGB(0, 255, 0) -- Green dot
    anchorIndicator.BorderSizePixel = 0
    anchorIndicator.ZIndex = 1001
    anchorIndicator.Parent = paneContainer
    
    -- Make it circular
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = anchorIndicator
    
    -- Add anchor point coordinates label
    local coordLabel = Instance.new("TextLabel")
    coordLabel.Size = UDim2.new(0, 80, 0, 15)
    coordLabel.Position = UDim2.new(0, 15, 0, -7)
    coordLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    coordLabel.BackgroundTransparency = 0.3
    coordLabel.Text = string.format("(%.1f, %.1f)", anchorPoint.X, anchorPoint.Y)
    coordLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    coordLabel.TextScaled = true
    coordLabel.Font = Enum.Font.Gotham
    coordLabel.ZIndex = 1002
    coordLabel.Parent = anchorIndicator
end

-- Validate and log position calculations
function BaseUI:_validatePanePosition(paneContainer, config, paneName)
    local actualPosition = paneContainer.Position
    local actualAnchor = paneContainer.AnchorPoint
    local actualSize = paneContainer.Size
    
    self.logger:info("Position Debug for", paneName, {
        semantic_position = config.position,
        offset = config.offset,
        calculated_position = tostring(actualPosition),
        anchor_point = string.format("(%.1f, %.1f)", actualAnchor.X, actualAnchor.Y),
        size = string.format("(%d, %d)", actualSize.X.Offset, actualSize.Y.Offset),
        context = "PositionValidation"
    })
end

return BaseUI 