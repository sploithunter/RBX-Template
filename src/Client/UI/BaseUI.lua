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
    
    -- Create all UI using the pane-based system
    self:_createTopBar()
    self:_createAllPanes()  -- Create all panes from configuration

    -- Create overlays and singleton elements if configured
    self:_createOverlays()
    self:_createSingletons()
    
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
        if paneConfig.enabled == false then
            self.logger:debug("Skipping disabled pane:", paneName)
        else
            local paneStartTime = tick()
            self:_createPane(paneName, paneConfig)
            local paneEndTime = tick()
            
            paneCount = paneCount + 1
            self.logger:debug("Created pane '" .. paneName .. "' in " .. string.format("%.2f", (paneEndTime - paneStartTime) * 1000) .. "ms")
        end
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
    
    if not config.size or type(config.size) ~= "table" then
        self.logger:error("Invalid size configuration for pane '" .. tostring(paneName) .. "'")
        return
    end

    -- Build UDim2 size using provided scale and/or pixel offsets (no viewport conversion)
    local sizeConfig = config.size
    local sizeScaleX = tonumber(sizeConfig.scaleX or 0)
    local sizeScaleY = tonumber(sizeConfig.scaleY or 0)
    local sizeOffsetX = tonumber(sizeConfig.pxX or sizeConfig.width or 0)
    local sizeOffsetY = tonumber(sizeConfig.pxY or sizeConfig.height or 0)
    
    -- Create pane container with semantic positioning
    local success, paneContainer = pcall(function()
        local container = Instance.new("Frame")
        container.Name = paneName
        container.Size = UDim2.new(sizeScaleX, sizeOffsetX, sizeScaleY, sizeOffsetY)
        return container
    end)
    
    if not success then
        self.logger:error("Failed to create pane container for '" .. tostring(paneName) .. "': " .. tostring(paneContainer))
        return
    end
    
    -- Apply positioning: either absolute scale-based or semantic
    if config.position_scale then
        local ps = config.position_scale
        local scaleX = tonumber(ps.x or 0)
        local scaleY = tonumber(ps.y or 0)
        local pixelX = (config.offset and tonumber(config.offset.x)) or 0
        local pixelY = (config.offset and tonumber(config.offset.y)) or 0
        -- optional additive scale offset
        local addScaleX = (config.offset_scale and tonumber(config.offset_scale.x)) or 0
        local addScaleY = (config.offset_scale and tonumber(config.offset_scale.y)) or 0
        paneContainer.Position = UDim2.new(scaleX + addScaleX, pixelX, scaleY + addScaleY, pixelY)
        -- Default to top-left anchor for raw scale positions (matches MCP defaults)
        paneContainer.AnchorPoint = Vector2.new(0, 0)
        if config.anchor_point then
            paneContainer.AnchorPoint = Vector2.new(config.anchor_point.x or 0, config.anchor_point.y or 0)
        elseif config.anchor then
            -- support semantic anchors like "top-left", "top-center", "center", etc.
            local anchorMap = {
                ["top-left"] = Vector2.new(0, 0),
                ["top-center"] = Vector2.new(0.5, 0),
                ["top-right"] = Vector2.new(1, 0),
                ["center-left"] = Vector2.new(0, 0.5),
                ["center"] = Vector2.new(0.5, 0.5),
                ["center-right"] = Vector2.new(1, 0.5),
                ["bottom-left"] = Vector2.new(0, 1),
                ["bottom-center"] = Vector2.new(0.5, 1),
                ["bottom-right"] = Vector2.new(1, 1)
            }
            local a = anchorMap[string.lower(config.anchor)]
            if a then paneContainer.AnchorPoint = a end
        end
    else
        local positionInfo = self:_getSemanticPosition(config.position, nil, config.offset)
        paneContainer.Position = positionInfo.position
        paneContainer.AnchorPoint = positionInfo.anchorPoint
    end
    
    paneContainer.ZIndex = 12
    paneContainer.Parent = self.mainFrame
    
    -- Optional aspect ratio constraint
    if config.aspect and tonumber(config.aspect.ratio) then
        local arc = Instance.new("UIAspectRatioConstraint")
        arc.AspectRatio = tonumber(config.aspect.ratio)
        if type(config.aspect.dominant_axis) == "string" then
            local axisLower = string.lower(config.aspect.dominant_axis)
            if axisLower == "width" then
                arc.DominantAxis = Enum.DominantAxis.Width
            elseif axisLower == "height" then
                arc.DominantAxis = Enum.DominantAxis.Height
            else
                arc.DominantAxis = Enum.DominantAxis.Width
            end
        end
        arc.Parent = paneContainer
    end

    -- Create background if enabled OR if debug backgrounds are on
    if (config.background and config.background.enabled) or (self.uiConfig.debug.show_backgrounds) then
        local bgConfig = config.background
        
        -- If debug backgrounds are enabled but no background config exists, create debug background
        if self.uiConfig.debug.show_backgrounds and (not bgConfig or not bgConfig.enabled) then
            -- Generate a unique color per pane for easy identification
            local debugColor = self:_getDebugColor(paneName)
            bgConfig = {
                enabled = true,
                color = debugColor,
                transparency = 0.75,
                corner_radius = 8,
                border = { enabled = true, color = Color3.fromRGB(0,0,0), thickness = 1, transparency = 0.1 }
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

-- Deterministic debug color per pane name for visualization
function BaseUI:_getDebugColor(name)
    local hash = 0
    for i = 1, #tostring(name) do
        hash = (hash * 31 + string.byte(name, i)) % 9973
    end
    -- Map hash to a color palette (pastel-like)
    local r = ((hash % 5) * 40 + 80) % 256
    local g = (((math.floor(hash / 5)) % 5) * 40 + 80) % 256
    local b = (((math.floor(hash / 25)) % 5) * 40 + 80) % 256
    return Color3.fromRGB(r, g, b)
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
        
        -- If no explicit cell_size provided and paneConfig.contents define scale-based sizes,
        -- compute pixel cell size from container.AbsoluteSize and the first content's size
        if (not finalLayoutConfig.cell_size) and paneConfig and paneConfig.contents and paneConfig.contents[1] then
            local first = paneConfig.contents[1]
            local sz = first.config and first.config.size
            if sz and (sz.scaleX or sz.scaleY) then
                local abs = container.AbsoluteSize
                local cw = math.max(1, math.floor(abs.X * (tonumber(sz.scaleX or 0))))
                local ch = math.max(1, math.floor(abs.Y * (tonumber(sz.scaleY or 0))))
                finalLayoutConfig = finalLayoutConfig or {}
                -- Respect rows when provided to ensure even vertical spacing
                if finalLayoutConfig.rows and finalLayoutConfig.rows > 0 then
                    local spacing = finalLayoutConfig.spacing or 0
                    ch = math.floor((abs.Y - ((finalLayoutConfig.rows - 1) * spacing)) / finalLayoutConfig.rows)
                end
                finalLayoutConfig.cell_size = { width = cw, height = ch }
                -- default spacing if none provided
                if not finalLayoutConfig.spacing then finalLayoutConfig.spacing = 0 end
            end
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
            -- Support manual position within custom layout using relative scales
            if layoutConfig.type == "custom" and contentConfig.config and contentConfig.config.position_scale then
                local ps = contentConfig.config.position_scale
                local px = (contentConfig.config.offset and contentConfig.config.offset.x) or 0
                local py = (contentConfig.config.offset and contentConfig.config.offset.y) or 0
                element.Position = UDim2.new(ps.x or 0, px, ps.y or 0, py)
                -- Keep anchor centered by default for buttons
                element.AnchorPoint = Vector2.new(0.5, 0.5)
            end
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
        
    elseif elementType == "template" then
        return self:_createTemplateElement(config, parent)
        
    elseif elementType == "image" then
        return self:_createImageElement(config, parent)
        
    elseif elementType == "label" then
        return self:_createLabelElement(config, parent)
        
    elseif elementType == "row" then
        return self:_createRowContainer(config, parent)
        
    else
        self.logger:warn("Unknown pane element type:", elementType)
        return nil
    end
end

-- Create overlays defined in config.overlays as absolute panes above content
function BaseUI:_createOverlays()
    local overlays = self.uiConfig.overlays
    if not overlays then return end
    for name, overlayConfig in pairs(overlays) do
        local overlayFrame = Instance.new("Frame")
        overlayFrame.Name = name
        overlayFrame.BackgroundTransparency = 1
        overlayFrame.ZIndex = self.uiConfig.z_index.modal
        overlayFrame.Visible = false -- start hidden to avoid blocking view while mapping panes
        overlayFrame.Parent = self.mainFrame

        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local width = overlayConfig.size and overlayConfig.size.scaleX and math.floor(viewport.X * overlayConfig.size.scaleX) or (overlayConfig.size and overlayConfig.size.pxX) or viewport.X
        local height = overlayConfig.size and overlayConfig.size.scaleY and math.floor(viewport.Y * overlayConfig.size.scaleY) or (overlayConfig.size and overlayConfig.size.pxY) or viewport.Y
        overlayFrame.Size = UDim2.new(0, width, 0, height)

        local pos = self:_getSemanticPosition(overlayConfig.position or "center", nil, nil)
        overlayFrame.Position = pos.position
        overlayFrame.AnchorPoint = pos.anchorPoint

        if overlayConfig.background and overlayConfig.background.enabled then
            overlayFrame.BackgroundTransparency = overlayConfig.background.transparency or 0
            overlayFrame.BackgroundColor3 = overlayConfig.background.color or Color3.new(0,0,0)
        end

        local layoutContainer = self:_createPaneLayout(overlayFrame, overlayConfig.layout or {type = "single",}, name, overlayConfig)
        self:_createPaneContents(layoutContainer, overlayConfig.contents or {}, overlayConfig.layout or {type = "single"})
    end
end

-- Create singleton elements like images/icons
function BaseUI:_createSingletons()
    local singletons = self.uiConfig.singletons
    if not singletons then return end
    for name, conf in pairs(singletons) do
        local container = Instance.new("Frame")
        container.Name = name
        container.BackgroundTransparency = 1
        container.ZIndex = self.uiConfig.z_index.content
        container.Parent = self.mainFrame

        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local width = conf.size and (conf.size.pxX or (conf.size.width)) or 64
        local height = conf.size and (conf.size.pxY or (conf.size.height)) or 64
        container.Size = UDim2.new(0, width, 0, height)

        local pos = self:_getSemanticPosition(conf.position or "top-right", nil, conf.offset)
        container.Position = pos.position
        container.AnchorPoint = pos.anchorPoint

        local layoutContainer = self:_createPaneLayout(container, conf.layout or {type = "single"}, name, conf)
        self:_createPaneContents(layoutContainer, conf.contents or {}, conf.layout or {type = "single"})
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
    
    -- Icon (supports both emoji and Roblox asset IDs) with configurable sizing/position
    local icon
    local iconValue = config.icon or ""
    local iconConfig = config.icon_config or {}
    local iconSizePx = iconConfig.size or {width = 22, height = 22}
    local iconPositionKind = iconConfig.position or "left" -- left | left_outside | center | right | right_outside
    local iconOffset = iconConfig.offset or {x = 8, y = 0}
    local tintWithColor = (iconConfig.tint_with_color ~= false)
    
    -- Check if icon is a Roblox asset ID (number or rbxassetid format)
    local assetId = nil
    if string.match(iconValue, "^rbxassetid://(%d+)$") then
        assetId = iconValue
    elseif string.match(iconValue, "^%d+$") then
        assetId = "rbxassetid://" .. iconValue
    end
    
    -- Helper to compute absolute position from kind
    local function computeIconPosition()
        if iconPositionKind == "center" then
            return UDim2.new(0.5, iconOffset.x, 0.5, iconOffset.y), Vector2.new(0.5, 0.5)
        end
        if iconPositionKind == "right" then
            return UDim2.new(1, - (iconOffset.x + math.floor(iconSizePx.width/2) + 6), 0.5, iconOffset.y), Vector2.new(0.5, 0.5)
        end
        if iconPositionKind == "right_outside" then
            return UDim2.new(1, iconOffset.x, 0.5, iconOffset.y), Vector2.new(0, 0.5)
        end
        if iconPositionKind == "left_outside" then
            return UDim2.new(0, iconOffset.x, 0.5, iconOffset.y), Vector2.new(0, 0.5)
        end
        -- default: left
        return UDim2.new(0, iconOffset.x + 8, 0.5, iconOffset.y), Vector2.new(0, 0.5)
    end

    if assetId then
        -- Use ImageLabel for Roblox assets with error handling
        local success, result = pcall(function()
            icon = Instance.new("ImageLabel")
            icon.Name = "Icon"
            icon.Size = UDim2.new(0, iconSizePx.width, 0, iconSizePx.height)
            local pos, anchor = computeIconPosition()
            icon.Position = pos
            icon.AnchorPoint = anchor
            icon.BackgroundTransparency = 1
            icon.Image = assetId
            if tintWithColor then
                icon.ImageColor3 = config.color  -- Optional tint
            end
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
            icon.Size = UDim2.new(0, iconSizePx.width, 0, iconSizePx.height)
            local pos, anchor = computeIconPosition()
            icon.Position = pos
            icon.AnchorPoint = anchor
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
        icon.Size = UDim2.new(0, iconSizePx.width, 0, iconSizePx.height)
        local pos, anchor = computeIconPosition()
        icon.Position = pos
        icon.AnchorPoint = anchor
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
    -- Compute left padding based on icon width (ensure minimum padding)
    local leftPadding = math.max(35, (iconSizePx.width + 13))
    if iconPositionKind == "left_outside" then
        leftPadding = 35 -- Icon sits outside; keep standard padding
    end
    amount.Size = UDim2.new(1, -leftPadding, 1, 0)
    amount.Position = UDim2.new(0, leftPadding, 0, 0)
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
    -- Merge the main button config with global defaults
    local mergedConfig = self:_mergeButtonWithDefaults(config)
    -- Use the merged config for the main button properties, but keep the original for sub-components
    config = mergedConfig or config
    
    -- noisy UI prints removed
    
    -- Determine button type: ImageButton vs TextButton
    local button
    local processedBackgroundImage = self:_processAssetId(config.background_image)
    local hasBackgroundImage = processedBackgroundImage ~= nil
    

    
    if hasBackgroundImage then
        -- PROFESSIONAL MODE: ImageButton with custom background

        button = Instance.new("ImageButton")
        button.Name = config.name .. "Button"
        button.Image = processedBackgroundImage
        button.ScaleType = Enum.ScaleType.Stretch
        button.ImageColor3 = Color3.fromRGB(255, 255, 255)
        button.BackgroundTransparency = 1 -- Let the image handle the background
        button.BorderSizePixel = 0
    else
        -- FALLBACK MODE: TextButton with programmatic styling  
        -- noisy UI prints removed
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
    -- Size: respect config.size when provided; otherwise fill container
    do
        local s = config.size
        if s then
            local sx = tonumber(s.scaleX or 0)
            local sy = tonumber(s.scaleY or 0)
            local px = tonumber(s.pxX or s.width or 0)
            local py = tonumber(s.pxY or s.height or 0)
            button.Size = UDim2.new(sx, px, sy, py)
        else
            -- default: fill
            button.Size = UDim2.new(1, 0, 1, 0)
        end
    end
    button.LayoutOrder = layoutOrder
    button.ZIndex = 13
    button.Parent = parent

    -- Optional per-button aspect ratio constraint
    if config.aspect and tonumber(config.aspect.ratio) then
        local arc = Instance.new("UIAspectRatioConstraint")
        arc.AspectRatio = tonumber(config.aspect.ratio)
        if type(config.aspect.dominant_axis) == "string" then
            local axisLower = string.lower(config.aspect.dominant_axis)
            if axisLower == "width" then
                arc.DominantAxis = Enum.DominantAxis.Width
            elseif axisLower == "height" then
                arc.DominantAxis = Enum.DominantAxis.Height
            else
                arc.DominantAxis = Enum.DominantAxis.Width
            end
        end
        arc.Parent = button
    end
    
    -- LAYER 1: FRAME (optional inner frame for styling consistency with imported UI)
    local rootButton = button
    local contentParent = rootButton
    local innerFrame
    if config.inner_frame ~= false then
        innerFrame = Instance.new("Frame")
        innerFrame.Name = "Inner"
        innerFrame.Size = UDim2.new(1, 0, 1, 0)
        innerFrame.BackgroundTransparency = 1
        innerFrame.Parent = rootButton
        contentParent = innerFrame -- attach sub-layers to inner frame
    end

    -- LAYER 2: ICON (Center of button)
    local icon = self:_createButtonIcon(config, contentParent)
    
    -- LAYER 3: NOTIFICATION BADGE (Top-right corner or configured position)
    local notification = self:_createButtonNotification(config, contentParent)
    
    -- LAYER 4: TEXT LABEL
    local label = self:_createButtonLabel(config, contentParent)
    -- (Stroke and size constraint are handled inside _createButtonLabel via text_config)
    
    -- Interactive effects
    if rootButton and rootButton:IsA("GuiButton") then
        rootButton.Activated:Connect(function()
            self:_onMenuButtonClicked(config.name)
            self:_animateButtonPress(rootButton)
        end)
    end
    
    -- Hover effects (different for image vs text buttons)
    if hasBackgroundImage then
        self:_addImageButtonHoverEffect(rootButton)
    else
        self:_addButtonHoverEffect(rootButton, config.color)
    end
    
    -- Store reference
    self.menuButtons[config.name] = rootButton

    -- AutoTarget visual indicator (server-driven via BoolValues on Player)
    if config.name == "AutoLow" or config.name == "AutoHigh" then
        -- Small state bar at top of button: orange = off, green = on
        local stateBar = Instance.new("Frame")
        stateBar.Name = "StateBar"
        stateBar.Size = UDim2.new(0.6, 0, 0, 8)
        stateBar.Position = UDim2.new(0.5, 0, 0, 6)
        stateBar.AnchorPoint = Vector2.new(0.5, 0)
        stateBar.BackgroundColor3 = Color3.fromRGB(255, 165, 0) -- off (orange)
        stateBar.BorderSizePixel = 0
        stateBar.ZIndex = rootButton.ZIndex + 1
        stateBar.Parent = contentParent

        local stateCorner = Instance.new("UICorner")
        stateCorner.CornerRadius = UDim.new(0, 4)
        stateCorner.Parent = stateBar

        local function setOn(on)
            stateBar.BackgroundColor3 = on and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 165, 0)
        end

        local function bindToPlayerFlag(flagName)
            local player = Players.LocalPlayer
            local function attach(valueObj)
                if not valueObj then return end
                setOn(valueObj.Value)
                valueObj:GetPropertyChangedSignal("Value"):Connect(function()
                    setOn(valueObj.Value)
                end)
            end
            local existing = player:FindFirstChild(flagName)
            if existing then
                attach(existing)
            else
                player.ChildAdded:Connect(function(child)
                    if child.Name == flagName then
                        attach(child)
                    end
                end)
            end
        end

        if config.name == "AutoLow" then
            bindToPlayerFlag("FreeTarget")
        else
            bindToPlayerFlag("PaidTarget")
        end
    end
    
    -- noisy UI prints removed
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
        -- noisy UI prints removed
        iconConfig = {
            size = {scale_x = 0.4, scale_y = 0.4},
            position = {scale_x = 0.5, scale_y = 0.5},
            offset = {x = 0, y = 0}
        }
    end
    
    local iconSize = iconConfig.size
    local iconPosition = iconConfig.position  
    local iconOffset = iconConfig.offset
    local iconAnchor = Vector2.new(0.5, 0.5)

    -- Semantic icon positioning kinds (mirrors text label kinds)
    do
        local kind = iconConfig.position_kind
        if kind == "left_center_edge" then
            iconPosition = {scale_x = 0, scale_y = 0.5}
        elseif kind == "right_center_edge" then
            iconPosition = {scale_x = 1.0, scale_y = 0.5}
        elseif kind == "top_center_edge" then
            iconPosition = {scale_x = 0.5, scale_y = 0}
        elseif kind == "bottom_center_edge" then
            iconPosition = {scale_x = 0.5, scale_y = 1.0}
        end
    end
    

    
    if assetId then

        -- Use ImageLabel for Roblox assets with error handling
        local success, result = pcall(function()
            icon = Instance.new("ImageLabel")
            icon.Name = "Icon"
            icon.Size = UDim2.new(iconSize.scale_x, 0, iconSize.scale_y, 0)  -- Relative sizing
            icon.Position = UDim2.new(iconPosition.scale_x, iconOffset.x, iconPosition.scale_y, iconOffset.y)  -- Relative + offset
            icon.AnchorPoint = iconAnchor
            icon.BackgroundTransparency = 1
            icon.Image = assetId
            icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
            icon.ScaleType = Enum.ScaleType.Fit
            return icon
        end)
        
        if not success then
            print("   ❌ Icon asset failed, using emoji fallback")
            icon = self:_createEmojiIcon(config, parent, iconSize, iconPosition, iconOffset, iconAnchor)
        end
    else

        icon = self:_createEmojiIcon(config, parent, iconSize, iconPosition, iconOffset, iconAnchor)
    end
    
    if icon then
        icon.ZIndex = 15
        icon.Parent = parent
    end
    
    return icon
end

-- Create emoji icon fallback with configurable sizing/positioning
function BaseUI:_createEmojiIcon(config, parent, iconSize, iconPosition, iconOffset, iconAnchor)
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
    icon.AnchorPoint = iconAnchor or Vector2.new(0.5, 0.5)
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
    
    
    
    -- Notification badge background (match MCP naming)
    local notification = Instance.new("Frame")
    notification.Name = "Noti"
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

    -- Maintain aspect ratio like MCP (UIAspectRatioConstraint)
    local arc = Instance.new("UIAspectRatioConstraint")
    arc.AspectRatio = tonumber(notifConfig.aspect_ratio or 1.6)
    arc.DominantAxis = Enum.DominantAxis.Width
    arc.Parent = notification
    
    -- Rounded corners for notification
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0) -- Perfect circle
    corner.Parent = notification
    
    -- Notification text (match MCP naming "Txt")
    local text = Instance.new("TextLabel")
    text.Name = "Txt"
    text.Size = UDim2.new(1, 0, 1, 0)
    text.Position = UDim2.new(0, 0, 0, 0)
    text.BackgroundTransparency = 1
    text.Text = tostring(notifConfig.text or "!")
    text.TextColor3 = notifConfig.text_color or Color3.fromRGB(255, 255, 255)
    text.TextScaled = true
    text.Font = Enum.Font.GothamBold
    text.ZIndex = 17
    text.Parent = notification
    
    -- Text stroke + size constraint like MCP
    local tStroke = Instance.new("UIStroke")
    tStroke.Color = (notifConfig.text_stroke_color or Color3.fromRGB(0,0,0))
    tStroke.Thickness = tonumber(notifConfig.text_stroke_thickness or 2)
    tStroke.Transparency = tonumber(notifConfig.text_stroke_transparency or 0.2)
    tStroke.Parent = text

    local tsc = Instance.new("UITextSizeConstraint")
    tsc.MaxTextSize = tonumber(notifConfig.text_max_size or 18)
    tsc.Parent = text
    
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
    
    -- Semantic label positioning kinds (e.g., "bottom_center_edge")
    do
        local kind = textConfig.position_kind
        if kind == "bottom_center_edge" then
            -- MCP-style: wraps at bottom with stroke, centered
            textConfig.anchor_point = {x = 0.5, y = 0.5}
            textConfig.position_scale = {x = 0.5, y = 0.925}
            textConfig.height_scale = textConfig.height_scale or 0.258
            textConfig.position_offset = {x = 0, y = 0}
        elseif kind == "right_center" then
            -- Right-justified midline (edge align, optional side margin via position_offset)
            textConfig.anchor_point = {x = 1.0, y = 0.5}
            textConfig.position_scale = {x = 1.0, y = 0.5}
            textConfig.height_scale = textConfig.height_scale or 0.34
            local sideMargin = (textConfig.position and tonumber(textConfig.position.side_margin)) or 0
            textConfig.position_offset = {x = -sideMargin, y = 0}
        elseif kind == "manual" then
            -- Respect provided anchor/scale/offset verbatim
            textConfig.anchor_point = textConfig.anchor_point or {x = 0.5, y = 0.5}
            textConfig.position_scale = textConfig.position_scale or {x = 0.5, y = 0.5}
            textConfig.position_offset = textConfig.position_offset or {x = 0, y = 0}
            textConfig.height_scale = textConfig.height_scale or 0.34
        end
    end

    local font = textConfig.font
    local textSize = textConfig.size
    local textColor = textConfig.color
    local useTextScaled = textConfig.text_scaled
    local textPosition = textConfig.position
    

    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    -- Prefer MCP-style scale-driven sizing/positioning when provided
    if textConfig.height_scale then
        label.Size = UDim2.new(1, 0, tonumber(textConfig.height_scale), 0)
    else
        label.Size = UDim2.new(1, 0, 0, textSize.height)
    end
    if textConfig.position_scale then
        local px = (textConfig.position_offset and tonumber(textConfig.position_offset.x)) or 0
        local py = (textConfig.position_offset and tonumber(textConfig.position_offset.y)) or 0
        label.Position = UDim2.new(textConfig.position_scale.x, px, textConfig.position_scale.y, py)
    else
        label.Position = UDim2.new(0.5, 0, 1, -textPosition.bottom_offset)
    end
    label.AnchorPoint = Vector2.new(textConfig.anchor_point and textConfig.anchor_point.x or 0.5, textConfig.anchor_point and textConfig.anchor_point.y or 0.5)
    label.BackgroundTransparency = 1
    label.Text = config.text or config.name
    label.TextColor3 = textColor  -- Configurable color
    label.TextScaled = useTextScaled  -- Configurable scaling
    label.Font = font  -- Configurable font
    if textConfig.position_kind == "right_center" then
        label.TextXAlignment = Enum.TextXAlignment.Right
    else
        label.TextXAlignment = Enum.TextXAlignment.Center  -- Center text horizontally within full-width label
    end
    label.ZIndex = 15
    
    -- If TextScaled is disabled, set a specific text size
    if not useTextScaled then
        label.TextSize = textConfig.text_size or 14  -- Default 14pt when not scaled
    end
    
    label.Parent = parent
    
    -- Label stroke: use MCP stroke when provided, else use shadow config
    do
        local strokeColor = textConfig.stroke_color or textConfig.shadow and textConfig.shadow.color
        local strokeThickness = tonumber(textConfig.stroke_thickness or (textConfig.shadow and textConfig.shadow.thickness)) or 3
        local strokeTransparency = tonumber(textConfig.stroke_transparency or (textConfig.shadow and textConfig.shadow.transparency)) or 0
        local lineJoin = textConfig.stroke_line_join or "Miter"
        if strokeColor then
            local stroke = Instance.new("UIStroke")
            stroke.Color = strokeColor
            stroke.Thickness = strokeThickness
            stroke.Transparency = strokeTransparency
            if typeof(lineJoin) == "EnumItem" then
                stroke.LineJoinMode = lineJoin
            else
                stroke.LineJoinMode = Enum.LineJoinMode.Miter
            end
            stroke.Parent = label
        end
    end
    
    -- Text size constraint
    if not label:FindFirstChildOfClass("UITextSizeConstraint") then
        local tsc = Instance.new("UITextSizeConstraint")
        tsc.MaxTextSize = tonumber(textConfig.max_text_size or 48)
        tsc.Parent = label
    end
    
    return label
end

-- Merge button configuration with global defaults (for main button properties)
function BaseUI:_mergeButtonWithDefaults(buttonConfig)
    -- Load UI configuration
    local ConfigLoader = require(game.ReplicatedStorage.Shared.ConfigLoader)
    local uiConfig = ConfigLoader:LoadConfig("ui")
    
    -- Get global menu_button defaults
    local defaults = uiConfig.defaults and uiConfig.defaults.menu_button or {}
    
    -- Create a merged config that preserves specific button properties
    -- but adds missing properties from defaults
    local merged = self:_deepCopy(buttonConfig)
    
    -- Only add default properties that are missing in the specific config
    if not merged.color and defaults.color then
        merged.color = defaults.color
    end
    if not merged.background_image and defaults.background_image then
        merged.background_image = defaults.background_image
    end
    
    return merged
end

-- Merge specific configuration with global defaults
function BaseUI:_mergeWithDefaults(specificConfig, elementType, configType)
    -- Load UI configuration
    local ConfigLoader = require(game.ReplicatedStorage.Shared.ConfigLoader)
    local uiConfig = ConfigLoader:LoadConfig("ui")
    

    
    -- Get global defaults
    local defaults = uiConfig.defaults and uiConfig.defaults[elementType] and uiConfig.defaults[elementType][configType] or {}
    

    
    -- If no specific config provided, return deep copy of defaults
    if not specificConfig then
        local result = self:_deepCopy(defaults)

        return result
    end
    
    -- Merge specific config with defaults (specific overrides defaults)
    local result = self:_deepMerge(defaults, specificConfig)
    -- noisy UI prints removed
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

-- ========== IMAGE-BASED PANEL SYSTEM ==========

-- Create professional image-based panel with configurable components
function BaseUI:CreateImagePanel(panelName, config, parent)
    -- noisy UI prints removed
    
    -- Merge configuration with global defaults
    local panelConfig = self:_mergeWithDefaults(config, "panel", "background")
    local headerConfig = self:_mergeWithDefaults(config and config.header, "panel", "header")
    local contentConfig = self:_mergeWithDefaults(config and config.content, "panel", "content")
    
    -- Get specific panel configuration if available
    local ConfigLoader = require(game.ReplicatedStorage.Shared.ConfigLoader)
    local uiConfig = ConfigLoader:LoadConfig("ui")
    local specificConfig = uiConfig.panel_configs and uiConfig.panel_configs[panelName] or {}
    
    -- noisy UI prints removed
    
    -- Create main panel container
    local panel = self:_createPanelBackground(panelConfig, specificConfig.background, parent)
    
    -- Create header if configured
    local header = nil
    if headerConfig or (specificConfig and specificConfig.header) then
        header = self:_createPanelHeader(panel, headerConfig, specificConfig.header)
    end
    
    -- Create content area
    local content = self:_createPanelContent(panel, contentConfig, specificConfig.content, header)
    
    -- noisy UI prints removed
    
    return {
        panel = panel,
        header = header,
        content = content,
        config = specificConfig
    }
end

-- Create panel background (ImageLabel or Frame)
function BaseUI:_createPanelBackground(defaultConfig, specificConfig, parent)
    local config = specificConfig or defaultConfig
    local backgroundImage = config and config.image
    local panel
    
    if backgroundImage then
        -- noisy UI prints removed
        panel = Instance.new("ImageLabel")
        panel.Image = self:_processAssetId(backgroundImage)
        panel.ScaleType = Enum.ScaleType.Stretch
        panel.ImageColor3 = Color3.fromRGB(255, 255, 255)
        panel.BackgroundTransparency = 1
    else
        -- noisy UI prints removed
        panel = Instance.new("Frame")
        panel.BackgroundColor3 = config and config.color or defaultConfig.color
        panel.BackgroundTransparency = 0
    end
    
    -- Common properties
    panel.Name = "ImagePanel"
    panel.BorderSizePixel = 0
    panel.Parent = parent
    
    -- Add corner radius if not using image
    if not backgroundImage and config and config.corner_radius then
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, config.corner_radius)
        corner.Parent = panel
    end
    
    return panel
end

-- Create panel header with icon and title
function BaseUI:_createPanelHeader(panel, defaultConfig, specificConfig)
    local config = specificConfig or defaultConfig
    if not config then return nil end
    
    -- noisy UI prints removed
    
    local header
    local headerImage = config.background_image
    
    if headerImage then
        header = Instance.new("ImageLabel")
        header.Image = self:_processAssetId(headerImage)
        header.ScaleType = Enum.ScaleType.Stretch
        header.BackgroundTransparency = 1
    else
        header = Instance.new("Frame")
        header.BackgroundColor3 = config.background_color or defaultConfig.background_color
        header.BackgroundTransparency = 0
        
        -- Add corner radius for frame headers
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 12)
        corner.Parent = header
    end
    
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, config.height or defaultConfig.height)
    header.Position = UDim2.new(0, 0, 0, 0)
    header.BorderSizePixel = 0
    header.ZIndex = 15
    header.Parent = panel
    
    -- Add header icon if configured
    if config.icon then
        self:_createHeaderIcon(header, config)
    end
    
    -- Add header title if configured
    if config.title_text then
        self:_createHeaderTitle(header, config)
    end
    
    return header
end

-- Create header icon
function BaseUI:_createHeaderIcon(header, config)
    local iconValue = config.icon
    local fallbackValue = config.icon_fallback
    local assetId = self:_processAssetId(iconValue)
    local icon
    
    if assetId then
        -- Try to create ImageLabel with primary icon
        icon = Instance.new("ImageLabel")
        icon.Image = assetId
        icon.ScaleType = Enum.ScaleType.Fit
        icon.BackgroundTransparency = 1
    else
        -- Fallback to text/emoji if no valid asset ID
        local displayText = iconValue
        if not displayText and fallbackValue then
            displayText = fallbackValue
        end
        
        icon = Instance.new("TextLabel")
        icon.Text = displayText or "?"
        icon.TextScaled = true
        icon.Font = Enum.Font.GothamBold
        icon.BackgroundTransparency = 1
        icon.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
    
    icon.Name = "HeaderIcon"
    
    -- Size based on header scale - both width and height use the same scale
    local iconSize = config.icon_size or {scale = 0.8}  -- Default 80% of header height
    local scale = iconSize.scale or 0.8
    icon.Size = UDim2.new(scale, 0, scale, 0)  -- Both width and height use the scale (e.g., 1.15 for 115%)
    
    -- Add aspect ratio constraint to make it square
    local aspectRatio = Instance.new("UIAspectRatioConstraint")
    aspectRatio.AspectRatio = 1  -- Square (1:1 ratio)
    aspectRatio.AspectType = Enum.AspectType.FitWithinMaxSize
    aspectRatio.Parent = icon
    
    -- Position based on icon_position
    local position = config.icon_position or "left"
    if position == "top-left-corner" then
        icon.Position = UDim2.new(0, -10, 0, -10)  -- Extends outside bounds
        icon.AnchorPoint = Vector2.new(0, 0)
    elseif position == "top-left" then
        icon.Position = UDim2.new(0, 0, 0, 0)  -- Exactly at corner
        icon.AnchorPoint = Vector2.new(0, 0)
    elseif position == "left" then
        icon.Position = UDim2.new(0.02, 0, 0.5, 0)  -- 2% from left edge, vertically centered
        icon.AnchorPoint = Vector2.new(0, 0.5)
    elseif position == "center" then
        icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
    end
    
    icon.ZIndex = 16
    icon.Parent = header
    return icon
end

-- Create header title
function BaseUI:_createHeaderTitle(header, config)
    local title = Instance.new("TextLabel")
    title.Name = "HeaderTitle"
    title.Size = UDim2.new(0.75, 0, 1, 0)
    title.Position = UDim2.new(0.15, 0, 0, 0)  -- 15% from left, allowing space for scalable icon
    title.BackgroundTransparency = 1
    title.Text = config.title_text
    title.TextColor3 = config.title_color or Color3.fromRGB(255, 255, 255)
    title.TextSize = config.title_size or 32  -- Increased from 24 to 32 for better visibility
    title.Font = config.title_font or Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Center
    title.ZIndex = 16
    title.Parent = header
    
    return title
end

-- Create panel content area
function BaseUI:_createPanelContent(panel, defaultConfig, specificConfig, header)
    local config = specificConfig or defaultConfig
    local content
    
    if config and config.background_image then
        content = Instance.new("ImageLabel")
        content.Image = self:_processAssetId(config.background_image)
        content.ScaleType = Enum.ScaleType.Stretch
        content.BackgroundTransparency = 1
    else
        content = Instance.new("Frame")
        content.BackgroundColor3 = config and config.background_color or defaultConfig.background_color
        content.BackgroundTransparency = 0.1  -- Slight transparency for layering
        
        -- Add corner radius
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, config and config.corner_radius or defaultConfig.corner_radius)
        corner.Parent = content
    end
    
    content.Name = "Content"
    content.BorderSizePixel = 0
    content.ZIndex = 14
    
    -- Position based on whether header exists
    local headerHeight = header and (header.Size.Y.Offset + 10) or 0
    content.Size = UDim2.new(1, -20, 1, -(headerHeight + 20))
    content.Position = UDim2.new(0, 10, 0, headerHeight + 10)
    content.Parent = panel
    
    return content
end

-- Create image-based toggle setting
function BaseUI:CreateImageToggle(name, currentValue, config, parent, callback)
    -- noisy UI prints removed
    
    -- Merge with defaults
    local toggleConfig = self:_mergeWithDefaults(config, "setting_item", "toggle")
    local backgroundConfig = self:_mergeWithDefaults(config, "setting_item", "background")
    local labelConfig = self:_mergeWithDefaults(config, "setting_item", "label")
    
    -- Safety checks
    if not toggleConfig or not toggleConfig.on_image then
        -- noisy UI prints removed
        toggleConfig = {
            on_image = "5533192672",
            off_image = "5533209494", 
            size = {width = 60, height = 30},
            position = "right"
        }
    end
    
    -- Create setting container
    local container = Instance.new("Frame")
    container.Name = name .. "Toggle"
    container.Size = UDim2.new(1, 0, 0, backgroundConfig.height or 50)
    container.BackgroundColor3 = backgroundConfig.color or Color3.fromRGB(50, 52, 58)
    container.BorderSizePixel = 0
    container.Parent = parent
    
    -- Add corner radius
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, backgroundConfig.corner_radius or 8)
    corner.Parent = container
    
    -- Create label
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = labelConfig.color or Color3.fromRGB(255, 255, 255)
    label.TextSize = labelConfig.size or 14
    label.Font = labelConfig.font or Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ZIndex = 15
    label.Parent = container
    
    -- Create toggle button (ImageButton)
    local toggleButton = Instance.new("ImageButton")
    toggleButton.Name = "ToggleButton"
    toggleButton.Size = UDim2.new(0, toggleConfig.size.width, 0, toggleConfig.size.height)
    toggleButton.Position = UDim2.new(1, -toggleConfig.size.width - 15, 0.5, 0)
    toggleButton.AnchorPoint = Vector2.new(0, 0.5)
    toggleButton.BackgroundTransparency = 1
    toggleButton.BorderSizePixel = 0
    toggleButton.ScaleType = Enum.ScaleType.Fit
    toggleButton.ZIndex = 15
    toggleButton.Parent = container
    
    -- Set initial state
    local function updateToggleState()
        local imageId = currentValue and toggleConfig.on_image or toggleConfig.off_image
        toggleButton.Image = self:_processAssetId(imageId)
    end
    
    updateToggleState()
    
    -- Handle toggle interaction
    toggleButton.Activated:Connect(function()
        currentValue = not currentValue
        updateToggleState()
        
        if callback then
            callback(currentValue)
        end
    end)
    
    return {
        container = container,
        label = label,
        toggle = toggleButton,
        getValue = function() return currentValue end,
        setValue = function(value) 
            currentValue = value
            updateToggleState()
        end
    }
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
        petsButton.Size = UDim2.new(1, 0, 1, 0)
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

-- Create a generic template-based element using TemplateManager
function BaseUI:_createTemplateElement(config, parent)
    if not self.templateManager or not config or not config.template_type then
        return nil
    end
    local instance = self.templateManager:CreateFromTemplate(config.template_type, config.props or {})
    if instance then
        instance.Parent = parent
    end
    return instance
end

-- Create a simple ImageLabel element
function BaseUI:_createImageElement(config, parent)
    local imageId = config and (config.assetId or config.image or config.id)
    if not imageId then
        return nil
    end
    local image = Instance.new("ImageLabel")
    image.Name = config.name or "Image"
    image.BackgroundTransparency = 1
    image.Image = tostring(imageId)
    if config.size then
        if config.size.width and config.size.height then
            image.Size = UDim2.new(0, config.size.width, 0, config.size.height)
        elseif config.size.pxX and config.size.pxY then
            image.Size = UDim2.new(0, config.size.pxX, 0, config.size.pxY)
        end
    end
    if config.positionUDim2 then
        image.Position = config.positionUDim2
    end
    if config.anchor_point then
        image.AnchorPoint = config.anchor_point
    end
    image.Parent = parent
    return image
end

-- Create a horizontal row container that hosts child contents and consumes vertical space evenly
function BaseUI:_createRowContainer(config, parent)
    local row = Instance.new("Frame")
    row.Name = config.name or "Row"
    local heightScale = tonumber(config.height_scale or 0.33)
    row.Size = UDim2.new(1, 0, heightScale, 0)
    row.BackgroundTransparency = 1
    row.Parent = parent
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.FillDirection = Enum.FillDirection.Horizontal
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, config.spacing or 0)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    listLayout.Parent = row
    
    if config.padding then
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, config.padding.top or 0)
        pad.PaddingBottom = UDim.new(0, config.padding.bottom or 0)
        pad.PaddingLeft = UDim.new(0, config.padding.left or 0)
        pad.PaddingRight = UDim.new(0, config.padding.right or 0)
        pad.Parent = row
    end
    
    local innerLayoutConfig = { type = "list", direction = "horizontal", spacing = config.spacing or 0 }
    if config.contents then
        self:_createPaneContents(row, config.contents, innerLayoutConfig)
    end
    
    return row
end

-- Create a simple TextLabel element for debugging/labels
function BaseUI:_createLabelElement(config, parent)
    local text = (config and config.text) or "Label"
    local label = Instance.new("TextLabel")
    label.Name = config and (config.name or "Label") or "Label"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Text = text
    label.TextScaled = true
    label.Font = (self.uiConfig and self.uiConfig.fonts and self.uiConfig.fonts.bold) or Enum.Font.GothamBold
    label.TextColor3 = (config and config.color) or Color3.fromRGB(255,255,255)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = parent
    return label
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
    -- If the menuName matches a special UI-less action, execute it instead of opening a panel
    local actionName = menuName:lower() .. "_action"
    local actionConfig = self.uiConfig.helpers.get_action_config(self.uiConfig, actionName)
    if not actionConfig then
        -- Try explicit auto-target action names
        if menuName == "AutoLow" then actionConfig = self.uiConfig.helpers.get_action_config(self.uiConfig, "auto_target_low") end
        if menuName == "AutoHigh" then actionConfig = self.uiConfig.helpers.get_action_config(self.uiConfig, "auto_target_high") end
    end
    if actionConfig and actionConfig.type == "script_execute" and actionConfig.script == "AutoTargetActions" then
        -- Dispatch to client script action handler
        local ok, handler = pcall(function()
            return require(script.Parent.Parent.Systems.AutoTarget)
        end)
        if ok and handler then
            local at = handler._singleton or handler
            if actionConfig.method == "ToggleLow" and at.ToggleFree then
                at:ToggleFree()
                return
            elseif actionConfig.method == "ToggleHigh" and at.TogglePaid then
                at:TogglePaid()
                return
            end
        end
    end
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