--[[
    UI Configuration - Pane-Based Architecture (Configuration-as-Code)
    
    Version: 2.0 - Enhanced Asset Support & Performance
    
    This file defines the complete UI layout system using a pane-based architecture.
    All UI positioning, styling, icons, and behavior can be modified here without
    touching any Lua code.
    
    Key Features:
    - Semantic positioning system (top-left, center, bottom-right, etc.)
    - Universal icon support (emoji + Roblox asset IDs)
    - Pane-based layout with configurable backgrounds and layouts
    - Floating currency cards with professional styling
    - Menu button grids with hover effects
    - Combined UI elements (player info + quest tracker)
    - Responsive design with automatic scaling
    
    Architecture:
    - panes: Define UI containers with position, size, background, layout, and contents
    - themes: Visual styling and color schemes
    - layout: Positioning and sizing rules
    - menu_views: Complex multi-view menu definitions
    
    Usage:
    Simply modify the configuration values below to reorganize the entire UI.
    No code changes required - the BaseUI system reads this configuration
    and generates the UI automatically.
--]]

-- 🐛 DEBUG: UI Config loading started
-- 🎉 UNIVERSAL CONSISTENCY SYSTEM ACTIVE!
-- One image rules all buttons: Global defaults working perfectly!

local uiConfig = {
    version = "2.0.0", -- Updated for template system
    
    -- GLOBAL DEFAULTS for all UI elements
    -- These defaults are applied to any element that doesn't override them
    defaults = {
        menu_button = {
            -- Icon defaults
            icon_config = {
                size = {scale_x = 0.894, scale_y = 0.733},  -- MCP icon sizing (relative to button)
                position = {scale_x = 0.5, scale_y = 0.5},  -- Center
                offset = {x = 0, y = 0}
            },
            
            -- Text defaults
            text_config = {
                font = Enum.Font.FredokaOne,                -- Default font for button text
                size = {height = 20, margin = 10},          -- Default text area size (ignored when height_scale set)
                color = Color3.fromRGB(255, 255, 255),      -- Default white text
                text_scaled = true,                         -- Default auto-scale text
                text_size = 14,                             -- Default font size when not scaled
                position = {bottom_offset = 25, side_margin = 5},  -- Default text position
                -- Semantic default: bottom_center_edge
                position_kind = "bottom_center_edge",
                anchor_point = {x = 0.5, y = 0.5},
                position_scale = {x = 0.5, y = 0.925},
                height_scale = 0.258,
                -- MCP stroke defaults
                stroke_color = Color3.fromRGB(0, 53, 76),
                stroke_thickness = 3,
                stroke_transparency = 0,
                stroke_line_join = Enum.LineJoinMode.Miter,
                shadow = {
                    enabled = true,                         -- Default shadow enabled
                    color = Color3.fromRGB(0, 0, 0),        -- Default black shadow
                    thickness = 2,                          -- Default shadow thickness
                    transparency = 0.5                      -- Default shadow transparency
                }
            },
            
            -- Notification defaults
            notification = {
                enabled = false,                            -- Default no notification
                text = "!",                                 -- Default notification text
                background_color = Color3.fromRGB(255, 0, 0),  -- Default red background
                text_color = Color3.fromRGB(255, 255, 255), -- Default white text
                position = "top-right"                      -- Default position
            },
            
            -- Button defaults - APPLIES TO ALL BUTTONS GLOBALLY
            color = Color3.fromRGB(100, 100, 100),          -- Default button color (fallback mode)
            background_image = "16992268172"                -- 🎨 GLOBAL: Teal panel for ALL buttons
        },
        
        -- Panel defaults (for settings panel, inventory panel, etc.)
        -- 🌟 UNIVERSAL PANEL SYSTEM - ONE IMAGE RULES ALL PANELS! 🌟
        panel = {
            -- Panel background defaults - APPLIES TO ALL PANELS GLOBALLY
            background = {
                image = "16992268172",                       -- 🎨 GLOBAL: Blue panel for ALL panels
                color = Color3.fromRGB(40, 42, 48),         -- Fallback color if image fails
                corner_radius = 16,                         -- Default corner radius
                padding = {top = 20, bottom = 20, left = 20, right = 20}  -- Default padding
            },
            
            -- Panel header defaults - APPLIES TO ALL PANEL HEADERS GLOBALLY  
            header = {
                height = 70,                                -- Default header height
                background_image = "16992268172",           -- 🎨 GLOBAL: Teal panel for ALL headers
                background_color = Color3.fromRGB(35, 37, 43),  -- Fallback color if image fails
                title_font = Enum.Font.GothamBold,          -- Default title font
                title_size = 24,                            -- Default title size
                title_color = Color3.fromRGB(255, 255, 255), -- Default title color
                icon_size = {width = 32, height = 32},      -- Default header icon size
                icon_position = "top-left-corner",          -- Default icon position
                
                -- Close button defaults - APPLIES TO ALL POPUP PANELS GLOBALLY
                -- 🎯 AUTO-APPLIED: Every panel gets this close button unless explicitly disabled
                close_button = {
                    icon = "89257673063270",                -- 🎨 GLOBAL: New X button icon for ALL panels
                    size = {width = 30, height = 30},       -- Default close button size
                    position = "top-right-corner",          -- Position in top-right corner
                    offset = {x = 10, y = -10},             -- Offset from corner (extends outside bounds)
                    background_color = Color3.fromRGB(220, 60, 60),  -- Default red background
                    hover_color = Color3.fromRGB(180, 40, 40),       -- Darker red on hover
                    corner_radius = 8                       -- Default corner radius
                }
            },
            
            -- Panel content defaults
            content = {
                background_image = nil,                     -- Keep content transparent for layering
                background_color = Color3.fromRGB(45, 47, 53),  -- Subtle content color
                corner_radius = 12,                         -- Default content corner radius
                padding = {top = 15, bottom = 15, left = 15, right = 15}  -- Default content padding
            }
        },
        
        -- Setting item defaults (for individual settings like toggles, sliders)
        setting_item = {
            -- Setting background defaults
            background = {
                image = nil,                                -- Default no setting background
                color = Color3.fromRGB(50, 52, 58),         -- Default setting color
                corner_radius = 8,                          -- Default setting corner radius
                height = 50                                 -- Default setting height
            },
            
            -- Setting label defaults
            label = {
                font = Enum.Font.Gotham,                    -- Default label font
                size = 14,                                  -- Default label size
                color = Color3.fromRGB(255, 255, 255),      -- Default label color
                position = "left"                           -- Default label position
            },
            
            -- Toggle defaults
            toggle = {
                on_image = "5533192672",                    -- Default ON toggle image
                off_image = "5533209494",                   -- Default OFF toggle image
                size = {width = 60, height = 30},           -- Default toggle size
                position = "right"                          -- Default toggle position
            }
        }
    },
    -- Template System Configuration
    templates = {
        -- Template storage path
        storage_path = "ReplicatedStorage.UI_Templates",
        
        -- Asset ID mappings (your owned assets - swappable without code changes)
        assets = {
            currency_icons = {
                coins = "rbxassetid://5088859456", -- Using your gems icon
                gems = "rbxassetid://5088859456",   -- Your gems asset
                crystals = "rbxassetid://12155643116", -- Your crystals asset
                robux = "rbxassetid://5088859456", -- Can use gems icon as fallback
                xp = "rbxassetid://5088859456", -- Can use gems icon as fallback
            },
            
            ui_icons = {
                shop = "rbxassetid://12155643116", -- Using your frame asset for now
                inventory = "rbxassetid://12155643116", 
                settings = "rbxassetid://12155643116",
                effects = "rbxassetid://12155643116",
                close = "rbxassetid://12155643116",
                menu = "rbxassetid://12155643116",
            },
            
            backgrounds = {
                panel = "rbxassetid://12155643116", -- Your frame background
                button = "rbxassetid://12155643116",
                frame = "rbxassetid://12155643116",
            }
        },
        
        -- Template type mappings
        types = {
            currency_display = "CurrencyLabel",
            menu_button = "MenuButton", 
            shop_item = "GenericEntryTemplate",
            inventory_item = "GenericEntryTemplate",
            panel_large = "LargeUIBlank",
            panel_scroll = "LargeUIScroller",
            text_display = "TextLabelStyle",
        },
        
        -- Optional per-template defaults (safe to be empty)
        defaults = {
            -- Examples (uncomment and customize as needed):
            -- menu_button = { corner_radius = 12 },
            -- panel_large = { corner_radius = 16 },
            -- panel_scroll = { corner_radius = 16 },
        },
        
        -- Template configurations moved to template_helpers section below
    },

    -- === THEMES ===
    themes = {
        dark = {
            name = "Dark Theme",
            primary = {
                background = Color3.fromRGB(30, 30, 35),
                surface = Color3.fromRGB(40, 40, 45),
                accent = Color3.fromRGB(0, 120, 180),
                success = Color3.fromRGB(34, 139, 34),
                warning = Color3.fromRGB(255, 165, 0),
                error = Color3.fromRGB(220, 53, 69),
                info = Color3.fromRGB(138, 43, 226),
            },
            text = {
                primary = Color3.fromRGB(255, 255, 255),
                secondary = Color3.fromRGB(200, 200, 200),
                muted = Color3.fromRGB(150, 150, 150),
                disabled = Color3.fromRGB(100, 100, 100),
                inverse = Color3.fromRGB(0, 0, 0),
            },
            button = {
                primary = Color3.fromRGB(0, 120, 180),
                secondary = Color3.fromRGB(100, 100, 120),
                success = Color3.fromRGB(34, 139, 34),
                danger = Color3.fromRGB(220, 53, 69),
                disabled = Color3.fromRGB(60, 60, 65),
            },
            input = {
                background = Color3.fromRGB(35, 35, 40),
                border = Color3.fromRGB(80, 80, 85),
                focus = Color3.fromRGB(0, 120, 180),
                error = Color3.fromRGB(220, 53, 69),
            },
            shadow = Color3.fromRGB(0, 0, 0),
            overlay = Color3.fromRGB(0, 0, 0),
        },
        
        light = {
            name = "Light Theme",
            primary = {
                background = Color3.fromRGB(248, 249, 250),
                surface = Color3.fromRGB(255, 255, 255),
                accent = Color3.fromRGB(0, 123, 255),
                success = Color3.fromRGB(40, 167, 69),
                warning = Color3.fromRGB(255, 193, 7),
                error = Color3.fromRGB(220, 53, 69),
                info = Color3.fromRGB(23, 162, 184),
            },
            text = {
                primary = Color3.fromRGB(33, 37, 41),
                secondary = Color3.fromRGB(108, 117, 125),
                muted = Color3.fromRGB(134, 142, 150),
                disabled = Color3.fromRGB(173, 181, 189),
                inverse = Color3.fromRGB(255, 255, 255),
            },
            button = {
                primary = Color3.fromRGB(0, 123, 255),
                secondary = Color3.fromRGB(108, 117, 125),
                success = Color3.fromRGB(40, 167, 69),
                danger = Color3.fromRGB(220, 53, 69),
                disabled = Color3.fromRGB(173, 181, 189),
            },
            input = {
                background = Color3.fromRGB(255, 255, 255),
                border = Color3.fromRGB(206, 212, 218),
                focus = Color3.fromRGB(0, 123, 255),
                error = Color3.fromRGB(220, 53, 69),
            },
            shadow = Color3.fromRGB(0, 0, 0),
            overlay = Color3.fromRGB(255, 255, 255),
        }
    },
    
    -- Current active theme
    active_theme = "dark",
    
    -- === TYPOGRAPHY ===
    fonts = {
        primary = Enum.Font.Gotham,
        secondary = Enum.Font.GothamMedium,
        bold = Enum.Font.GothamBold,
        monospace = Enum.Font.RobotoMono,
        
        -- Font sizes (scaled automatically based on screen size)
        sizes = {
            xs = 10,
            sm = 12,
            md = 14,
            lg = 16,
            xl = 18,
            xxl = 24,
            xxxl = 32,
        }
    },
    
    -- === SPACING SYSTEM ===
    spacing = {
        xs = 4,
        sm = 8,
        md = 16,
        lg = 24,
        xl = 32,
        xxl = 48,
        xxxl = 64,
    },
    
    -- === BORDER RADIUS ===
    radius = {
        none = 0,
        sm = 4,
        md = 8,
        lg = 12,
        xl = 16,
        full = 999, -- For circular elements
    },
    
    -- === ANIMATIONS ===
    animations = {
        duration = {
            fast = 0.15,
            normal = 0.25,
            slow = 0.4,
        },
        easing = {
            ease_in = Enum.EasingStyle.Quad,
            ease_out = Enum.EasingStyle.Quad,
            ease_in_out = Enum.EasingStyle.Quad,
            bounce = Enum.EasingStyle.Bounce,
            elastic = Enum.EasingStyle.Elastic,
        },
        direction = {
            in_dir = Enum.EasingDirection.In,
            out_dir = Enum.EasingDirection.Out,
            in_out_dir = Enum.EasingDirection.InOut,
        },
        
        -- Menu transition effects - Professional Animation Showcase
        menu_transitions = {
            enabled = true,
            default_effect = "slide_in_right", -- Default animation
            
            effects = {
                -- === DIRECTIONAL SLIDES ===
                slide_in_right = {
                    name = "Slide from Right",
                    duration = "normal",
                    easing = "ease_out",
                    direction = "out_dir",
                    start_position = UDim2.new(1.2, 0, 0.5, 0), -- Off-screen right
                    end_position = UDim2.new(0.5, 0, 0.5, 0),   -- Center
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_transparency = 0,
                    end_transparency = 0,
                },
                
                slide_in_left = {
                    name = "Slide from Left",
                    duration = "normal",
                    easing = "ease_out", 
                    direction = "out_dir",
                    start_position = UDim2.new(-0.2, 0, 0.5, 0), -- Off-screen left
                    end_position = UDim2.new(0.5, 0, 0.5, 0),    -- Center
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_transparency = 0,
                    end_transparency = 0,
                },
                
                slide_in_top = {
                    name = "Slide from Top",
                    duration = "normal",
                    easing = "ease_out",
                    direction = "out_dir", 
                    start_position = UDim2.new(0.5, 0, -0.2, 0), -- Off-screen top
                    end_position = UDim2.new(0.5, 0, 0.5, 0),    -- Center
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_transparency = 0,
                    end_transparency = 0,
                },
                
                slide_in_bottom = {
                    name = "Slide from Bottom",
                    duration = "normal", 
                    easing = "ease_out",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, 1.2, 0),  -- Off-screen bottom
                    end_position = UDim2.new(0.5, 0, 0.5, 0),    -- Center
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_transparency = 0,
                    end_transparency = 0,
                },
                
                -- === SCALING EFFECTS ===
                scale_in_small = {
                    name = "Scale In (Small)",
                    duration = "fast",
                    easing = "ease_out",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, 0.5, 0),
                    end_position = UDim2.new(0.5, 0, 0.5, 0),
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_scale = 0.3,
                    end_scale = 1.0,
                    start_transparency = 0.8,
                    end_transparency = 0,
                },
                
                scale_in_large = {
                    name = "Scale In (Large)",
                    duration = "normal",
                    easing = "ease_out",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, 0.5, 0),
                    end_position = UDim2.new(0.5, 0, 0.5, 0),
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_scale = 1.5,
                    end_scale = 1.0,
                    start_transparency = 0.5,
                    end_transparency = 0,
                },
                
                -- === ROTATION EFFECTS ===
                spin_in = {
                    name = "Spin In",
                    duration = "normal",
                    easing = "ease_out",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, 0.5, 0),
                    end_position = UDim2.new(0.5, 0, 0.5, 0),
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_scale = 0.1,
                    end_scale = 1.0,
                    start_rotation = 180, -- Half rotation
                    end_rotation = 0,
                    start_transparency = 0.7,
                    end_transparency = 0,
                },
                
                flip_in = {
                    name = "Flip In",
                    duration = "normal",
                    easing = "bounce",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, 0.5, 0),
                    end_position = UDim2.new(0.5, 0, 0.5, 0),
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_scale = 0.01, -- Nearly invisible
                    end_scale = 1.0,
                    start_rotation = 90, -- Quarter rotation
                    end_rotation = 0,
                    start_transparency = 0.9,
                    end_transparency = 0,
                },
                
                -- === BOUNCE & ELASTIC ===
                bounce_in = {
                    name = "Bounce In",
                    duration = "slow",
                    easing = "bounce",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, -0.3, 0), -- Off-screen top
                    end_position = UDim2.new(0.5, 0, 0.5, 0),    -- Center
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_transparency = 0,
                    end_transparency = 0,
                },
                
                elastic_in = {
                    name = "Elastic In",
                    duration = "slow",
                    easing = "elastic",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, 0.5, 0),
                    end_position = UDim2.new(0.5, 0, 0.5, 0),
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_scale = 0.2,
                    end_scale = 1.0,
                    start_transparency = 0.3,
                    end_transparency = 0,
                },
                
                -- === FADE VARIATIONS ===
                fade_in = {
                    name = "Fade In",
                    duration = "fast",
                    easing = "ease_in_out",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, 0.5, 0),
                    end_position = UDim2.new(0.5, 0, 0.5, 0),
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_transparency = 1,
                    end_transparency = 0,
                },
                
                fade_in_scale = {
                    name = "Fade + Scale",
                    duration = "normal",
                    easing = "ease_out",
                    direction = "out_dir",
                    start_position = UDim2.new(0.5, 0, 0.5, 0),
                    end_position = UDim2.new(0.5, 0, 0.5, 0),
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_scale = 0.8,
                    end_scale = 1.0,
                    start_transparency = 1,
                    end_transparency = 0,
                },
                
                -- === SPECIAL EFFECTS ===
                spiral_in = {
                    name = "Spiral In",
                    duration = "slow",
                    easing = "ease_out",
                    direction = "out_dir",
                    start_position = UDim2.new(1.5, 0, -0.5, 0), -- Off-screen top-right
                    end_position = UDim2.new(0.5, 0, 0.5, 0),    -- Center
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_scale = 0.3,
                    end_scale = 1.0,
                    start_rotation = 360, -- Full rotation
                    end_rotation = 0,
                    start_transparency = 0.8,
                    end_transparency = 0,
                },
                
                zoom_blur = {
                    name = "Zoom Blur",
                    duration = "fast",
                    easing = "ease_in",
                    direction = "in_dir",
                    start_position = UDim2.new(0.5, 0, 0.5, 0),
                    end_position = UDim2.new(0.5, 0, 0.5, 0),
                    anchor_point = Vector2.new(0.5, 0.5),
                    start_scale = 3.0, -- Very large
                    end_scale = 1.0,
                    start_transparency = 0.9,
                    end_transparency = 0,
                }
            }
        }
    },
    
    -- === RESPONSIVE DESIGN ===
    breakpoints = {
        mobile = 600,     -- Phone screens
        tablet = 900,     -- Tablet screens  
        desktop = 1200,   -- Desktop screens
        wide = 1600,      -- Wide screens
    },
    
    -- Inventory grid configuration has moved under panel_configs.inventory_panel.grid
    
    -- Responsive scaling factors
    scale_factors = {
        mobile = 0.6,
        tablet = 0.7,
        desktop = 0.8,
        wide = 0.9,
    },
    
    -- === COMPONENT DEFAULTS REMOVED ===
    -- These were unused and have been consolidated into the main defaults section above
    
    -- === SOUND EFFECTS ===
    sounds = {
        button_hover = "rbxasset://sounds/electronicpingshort.wav",
        button_click = "rbxasset://sounds/button-09.mp3", 
        error = "rbxasset://sounds/electronicpingshort.wav",
        success = "rbxasset://sounds/bell-sweet.mp3",
        notification = "rbxasset://sounds/notification.mp3",
        
        -- Sound settings
        volume = 0.5,
        enabled = true,
    },
    
    -- === Z-INDEX LAYERS ===
    z_index = {
        background = 1,
        content = 10,
        dropdown = 100,
        modal = 1000,
        toast = 2000,
        tooltip = 3000,
    },
    
    -- === ACCESSIBILITY ===
    accessibility = {
        high_contrast_mode = false,
        reduced_motion = false,
        screen_reader_support = true,
        keyboard_navigation = true,
        focus_indicators = true,
    },
    
    -- === MOBILE SPECIFIC ===
    mobile = {
        touch_target_min_size = 44, -- Minimum touch target size in pixels
        swipe_threshold = 50,
        long_press_duration = 0.5,
        haptic_feedback = true,
    },
    
    -- === DEBUG & DEVELOPMENT ===
    debug = {
        show_bounds = false,  -- Enable to visualize pane boundaries
        show_anchor_points = false,  -- Show anchor point indicators
        show_backgrounds = false,  -- Off: keep pane containers clear
        log_interactions = false,
        performance_monitoring = true,
        component_inspector = false,
        position_validation = false,  -- Validate positioning calculations
    },
    
    -- === ANIMATION TESTING SYSTEM ===
    -- Quick way to test different animations - just change the values below!
    -- This system allows developers to easily prototype different animation effects
    -- without modifying the main action configuration.
    animation_showcase = {
        enabled = true,
        
        -- Override animations for testing (set to false to use default action animations)
        -- When true: Uses test_effects below instead of action configuration
        -- When false: Uses the transition defined in each action (shop_action.transition, etc.)
        override_animations = true,  -- ENABLED to showcase animation variety
        
        -- Test animations (when override_animations = true)
        -- Each menu name (lowercase) maps to an animation effect name
        test_effects = {
            shop = "slide_in_left",      -- Try: slide_in_right, scale_in_small, spiral_in
            inventory = "flip_in",       -- Try: bounce_in, elastic_in, zoom_blur
            effects = "spin_in",         -- Try: slide_in_top, fade_in_scale, scale_in_large
            settings = "slide_in_bottom",-- Try: fade_in, elastic_in, bounce_in
            admin = "zoom_blur",         -- Try: spiral_in, spin_in, scale_in_large
        },
        
        -- Available effects for easy copy/paste:
        -- All effects are defined in animations.menu_transitions.effects below
        -- SLIDES: slide_in_right, slide_in_left, slide_in_top, slide_in_bottom
        -- SCALES: scale_in_small, scale_in_large, fade_in_scale  
        -- ROTATION: spin_in, flip_in, spiral_in
        -- BOUNCE: bounce_in, elastic_in
        -- FADE: fade_in, fade_in_scale, zoom_blur
        -- SPECIAL: spiral_in, zoom_blur
    },
    
    -- === ACTION SYSTEM (Configuration-as-Code) ===
    -- Define all button actions through configuration instead of hardcoded behavior
    actions = {
        -- Menu Panel Actions - Each with unique animation style
        shop_action = {
            type = "menu_panel",
            panel = "Shop",
            transition = "slide_in_right", -- Classic slide from right
            sound = "button_click",
            description = "Opens the shop panel with slide animation"
        },

        -- Auto-Target Actions (server-driven visual state; UI calls script actions to toggle)
        auto_target_low = {
            type = "script_execute",
            script = "AutoTargetActions",
            method = "ToggleLow"
        },
        auto_target_high = {
            type = "script_execute",
            script = "AutoTargetActions",
            method = "ToggleHigh"
        },

        -- Aliases to match BaseUI name->action convention (menuName:lower() .. "_action")
        autolow_action = {
            type = "script_execute",
            script = "AutoTargetActions",
            method = "ToggleLow"
        },
        autohigh_action = {
            type = "script_execute",
            script = "AutoTargetActions",
            method = "ToggleHigh"
        },
        
        inventory_action = {
            type = "menu_panel", 
            panel = "Inventory",
            transition = "scale_in_small", -- Compact scale in
            sound = "button_click",
            description = "Opens inventory with scale animation"
        },
        
        effects_action = {
            type = "menu_panel",
            panel = "Effects", 
            transition = "spiral_in", -- Dramatic spiral effect
            sound = "button_click",
            description = "Opens effects panel with spiral animation"
        },
        
        settings_action = {
            type = "menu_panel",
            panel = "Settings",
            transition = "fade_in_scale", -- Subtle fade + scale
            sound = "button_click",
            description = "Opens settings panel with fade animation"
        },
        
        admin_action = {
            type = "menu_panel",
            panel = "Admin",
            transition = "bounce_in", -- Authority bounce
            sound = "button_click",
            conditions = {
                admin_only = true
            },
            description = "Opens admin panel with bounce animation"
        },
        
        -- Custom Script Actions
        pets_action = {
            type = "script_execute",
            script = "PetsHandler", 
            method = "TogglePetsUI",
            parameters = {
                animation = "slide_up"
            },
            sound = "success",
            description = "Opens pets interface with custom logic"
        },
        
        rewards_action = {
            type = "script_execute", 
            script = "RewardsHandler",
            method = "ClaimAllRewards",
            parameters = {
                auto_claim = true,
                show_notification = true
            },
            sound = "success",
            description = "Claims all available rewards"
        },
        
        -- Multi-step Action Sequences
        daily_login_action = {
            type = "action_sequence",
            sequence = {
                {type = "script_execute", script = "DailyRewards", method = "CheckAvailable"},
                {type = "menu_panel", panel = "DailyRewards", transition = "elastic_in"}, -- Exciting daily reward
                {type = "script_execute", script = "Analytics", method = "LogDailyLogin"}
            },
            description = "Daily login reward flow with elastic animation"
        },
        
        -- Network/Remote Actions
        purchase_gems_action = {
            type = "network_call",
            service = "EconomyService", 
            method = "InitiatePurchase",
            parameters = {
                product_type = "gems",
                package = "starter_pack"
            },
            confirmation = {
                enabled = true,
                title = "Purchase Confirmation",
                message = "Buy starter gem pack for 99 Robux?"
            },
            description = "Initiates gem purchase flow"
        },
        
        -- Conditional Actions
        quest_claim_action = {
            type = "conditional_action",
            conditions = {
                quest_completed = true,
                not_claimed = true
            },
            success_action = {
                type = "script_execute",
                script = "QuestManager", 
                method = "ClaimReward"
            },
            failure_action = {
                type = "notification",
                message = "Quest not completed yet!",
                notification_type = "warning"
            },
            description = "Claims quest reward if eligible"
        },
        
        -- Notification Actions  
        achievement_action = {
            type = "notification",
            message = "Achievement unlocked!",
            notification_type = "success",
            duration = 3,
            sound = "achievement",
            description = "Shows achievement notification"
        },
        
        -- Debug/Development Actions
        debug_currencies_action = {
            type = "script_execute",
            script = "DebugConsole",
            method = "AddCurrencies", 
            parameters = {
                coins = 1000,
                gems = 100,
                crystals = 50
            },
            conditions = {
                debug_mode = true
            },
            description = "Adds test currencies (debug only)"
        }
    },
    
    -- === PANE-BASED LAYOUT SYSTEM (Configuration-as-Code) ===
    -- Modern component-based architecture where groups of elements live in configurable "panes"
    -- Think of these as "cards" in web development - containers that hold related UI elements
    panes = {
        -- Individual Floating Currency Cards (like reference game)
        coins_pane = {
            enabled = false,
            position = "center-left",
            offset = {x = 15, y = -40},
            size = {width = 120, height = 35},
            background = {
                enabled = true,
                color = Color3.fromRGB(0, 0, 0),
                transparency = 0.15,
                corner_radius = 18,
                border = {
                    enabled = true,
                    color = Color3.fromRGB(255, 215, 0),
                    thickness = 2,
                    transparency = 0.3
                }
            },
            layout = {type = "single"},
            contents = {
                {type = "currency_display", config = {
                    currency = "coins",
                    icon = "6995302957",
                    color = Color3.fromRGB(255, 215, 0),
                    icon_config = {
                        size = {width = 32, height = 32},
                        position = "left_outside", -- allow big icon to protrude outside
                        offset = {x = -10, y = 0},  -- negative X to push further left
                        tint_with_color = true
                    }
                }}
            }
        },
        
        gems_pane = {
            enabled = false,
            position = "center-left",
            offset = {x = 15, y = 0},
            size = {width = 120, height = 35},
            background = {
                enabled = true,
                color = Color3.fromRGB(0, 0, 0),
                transparency = 0.15,
                corner_radius = 18,
                border = {
                    enabled = true,
                    color = Color3.fromRGB(138, 43, 226),
                    thickness = 2,
                    transparency = 0.3
                }
            },
            layout = {type = "single"},
            contents = {
                {type = "currency_display", config = {
                    currency = "gems",
                    icon = "136309678310342",
                    color = Color3.fromRGB(138, 43, 226),
                    icon_config = {
                        size = {width = 32, height = 32},
                        position = "left_outside",
                        offset = {x = -10, y = 0}
                    }
                }}
            }
        },
        
        crystals_pane = {
            enabled = false,
            position = "center-left",
            offset = {x = 15, y = 40},
            size = {width = 120, height = 35},
            background = {
                enabled = true,
                color = Color3.fromRGB(0, 0, 0),
                transparency = 0.15,
                corner_radius = 18,
                border = {
                    enabled = true,
                    color = Color3.fromRGB(0, 255, 255),
                    thickness = 2,
                    transparency = 0.3
                }
            },
            layout = {type = "single"},
            contents = {
                {type = "currency_display", config = {
                    currency = "crystals",
                    icon = "138067583",
                    color = Color3.fromRGB(0, 255, 255),
                    icon_config = {
                        size = {width = 32, height = 32},
                        position = "left_outside",
                        offset = {x = -10, y = 0}
                    }
                }}
            }
        },
        
        -- Player Info Pane (hidden while building imported top bar currencies)
        player_info_pane = {
            enabled = false,
            position = "top-center",
            offset = {x = 0, y = 35},
            size = {width = 300, height = 80},
            background = {
                enabled = true,
                color = Color3.fromRGB(0, 0, 0),
                transparency = 0.3,
                corner_radius = 12,
                border = {
                    enabled = true,
                    color = Color3.fromRGB(255, 255, 255),
                    thickness = 1,
                    transparency = 0.7
                }
            },
            layout = { type = "single" },
            contents = { {type = "player_info", config = {}} }
        },

        -- Quest Tracker Pane (center-right with completely clear background)
        quest_tracker_pane = {
            enabled = false,
            position = "center-right",
            offset = {x = -15, y = 0},
            size = {width = 350, height = 120},
            background = {
                enabled = false  -- Completely disabled background for full transparency
            },
            layout = {
                type = "single"
            },
            contents = {
                {type = "quest_tracker", config = {}}
            }
        },

        
        -- Menu Buttons Pane (bottom-left) - Auto-sizing grid that adapts to content
        menu_buttons_pane = {
            enabled = false,
            position = "bottom-left", 
            offset = {x = 10, y = -10}, -- restore original placement
            size = {width = 280, height = 140}, -- Container size - buttons will auto-fit
            background = {enabled = false}, -- Debug backgrounds will handle visualization
            layout = {
                type = "grid",
                auto_size = true, -- Enable automatic sizing based on content
                button_count = 7, -- Exact number of buttons for calculation
                padding = {top = 5, bottom = 5, left = 5, right = 5} -- Padding for calculations
            },
            contents = {
                -- 🌟 UNIVERSAL CONSISTENCY SYSTEM! 🌟
                -- 🎨 ONE IMAGE RULES ALL: Every button gets teal panel background (16809347055) automatically!
                -- 📏 GLOBAL DEFAULTS: Consistent icon sizing, text styling, positioning across ALL buttons
                -- ⚡ MINIMAL CONFIG: Most buttons need only 4 lines (name, icon, text, action)!
                -- 🎯 SELECTIVE OVERRIDES: Still allows custom styling when needed (shop, admin, special buttons)
                --
                -- RESULT: 90% consistency with 10% customization effort! Perfect for importing professional GUIs.
                
                -- 🔥 SPECIAL SHOP: Override global default for unique shop styling
                {type = "menu_button", config = {
                    name = "Shop", 
                    background_image = "16992152563",      -- 🎨 OVERRIDE: Special shop background 
                    icon = "17684357501", 
                    text = "Shop", 
                    action = "shop_action",
                    notification = {
                        enabled = true,
                        text = "-25%",
                        background_color = Color3.fromRGB(255, 200, 0),
                        text_color = Color3.fromRGB(0, 0, 0),
                        position = "top-left-corner"
                    }
                    -- Everything else (icon size, text style, etc.) comes from GLOBAL defaults! 🎉
                }},
                
                -- 🟢 MINIMAL CONFIG: Uses 95% global defaults (teal background, default styling)
                {type = "menu_button", config = {
                    name = "Inventory", 
                    icon = "85179217604910",                   -- 🎨 NEW: Custom inventory bag icon
                    icon_fallback = "🎒",                      -- 🔄 FALLBACK: Backpack emoji if asset fails
                    text = "Items", 
                    action = "inventory_action"
                    -- 🎨 Automatically gets: teal background, default icon size/position, default text styling!
                }},
                
                -- 🟡 SELECTIVE OVERRIDES: Uses global teal background + custom styling
                {type = "menu_button", config = {
                    name = "Effects", 
                    icon = "⚡", 
                    icon_config = {
                        size = {scale_x = 0.6, scale_y = 0.6}   -- 🎨 OVERRIDE: Larger icon
                    },
                    text = "Effects", 
                    text_config = {
                        color = Color3.fromRGB(255, 255, 0)     -- 🎨 OVERRIDE: Yellow text
                    },
                    action = "effects_action",
                    notification = {
                        enabled = true,
                        text = "3",
                        background_color = Color3.fromRGB(255, 0, 0),
                        position = "top-right-corner"
                    }
                    -- 🎨 Still gets: global teal background, default text font/size, default icon anchor!
                }},
                
                -- 🔵 ULTRA-MINIMAL: Just icon, text, action - everything else from global defaults
                {type = "menu_button", config = {
                    name = "Settings", 
                    icon = "⚙️", 
                    text = "Settings", 
                    action = "settings_action"
                    -- 🎨 Automatically gets: teal background, default colors, default layout!
                }},
                
                -- 🟣 MINIMAL WITH OVERRIDE: Custom icon but inherits everything else
                {type = "menu_button", config = {
                    name = "Admin", 
                    icon = "6031068421", 
                    text = "Admin", 
                    action = "admin_action", 
                    admin_only = true
                    -- 🎨 Automatically gets: teal background, default text styling, default layout!
                }},
                
                -- ⭐ NOTIFICATION EXAMPLE: Simple notification that inherits default styling  
                {type = "menu_button", config = {
                    name = "Daily", 
                    icon = "📅", 
                    text = "Daily", 
                    action = "daily_login_action",
                    notification = {
                        enabled = true,
                        text = "!",
                        -- 🎨 Inherits: default red background, white text, default position
                    }
                    -- 🎨 Automatically gets: teal background, default icon/text styling!
                }},
                
                -- 🚀 ABSOLUTE MINIMAL: 4 lines = professional button!
                {type = "menu_button", config = {
                    name = "Quest", 
                    icon = "🎯", 
                    text = "Quest", 
                    action = "quest_claim_action"
                    -- 🎨 100% global defaults = instant professional styling!
                }}
            }
        },
        
        -- Single Button Panes - All aligned to same bottom edge
        pets_button_pane = {
            position = "bottom-center",
            offset = {x = 0, y = -10},  -- Standardized bottom alignment
            size = {width = 120, height = 60},
            background = {enabled = false},
            layout = {type = "single"},
            contents = {
                {type = "pets_button", config = {icon = "13262136255", text = "Pets", color = Color3.fromRGB(52, 152, 219), action = "pets_action"}}
            }
        },
        
        -- Auto-target buttons flanking the Pets button
        auto_low_button_pane = {
            position = "bottom-center",
            offset = {x = -140, y = -10},
            size = {width = 60, height = 60},
            background = {enabled = false},
            layout = {type = "single"},
            contents = {
                {type = "menu_button", config = {name = "AutoLow", icon = "70726573", text = "Low", action = "autolow_action"}}
            }
        },
        auto_high_button_pane = {
            position = "bottom-center",
            offset = {x = 140, y = -10},
            size = {width = 60, height = 60},
            background = {enabled = false},
            layout = {type = "single"},
            contents = {
                {type = "menu_button", config = {name = "AutoHigh", icon = "70726573", text = "High", action = "autohigh_action"}}
            }
        },
        
        rewards_button_pane = {
            enabled = false,
            position = "bottom-right", 
            offset = {x = -10, y = -10},  -- Standardized bottom alignment + small right padding
            size = {width = 120, height = 60},
            background = {enabled = false},
            layout = {type = "single"},
            contents = {
                {type = "rewards_button", config = {icon = "🎁", text = "Rewards", color = Color3.fromRGB(255, 215, 0), badge_count = 3, action = "rewards_action"}}
            }
        },

        -- === IMPORTED LAYOUT ANCHORS (from external game's StarterGui.Guis.Layout) ===
        imported_top_bar = {
            position_scale = {x = 0.5, y = 0.0112233441},
            size = {scaleX = 0.428944618, scaleY = 0.113355778},
            anchor = "top-center",
            background = {enabled = false},
            layout = {type = "list", direction = "horizontal", spacing = 12, horizontal_alignment = "center", vertical_alignment = "center", padding = {left = 12, right = 12}},
            contents = {
                {type = "currency_display", config = {
                    currency = "crystals",
                    background_image = "rbxassetid://17016939569",
                    icon = "rbxassetid://85121058596566",
                    icon_config = { position_kind = "left_center_edge", size = {scale_x = 0.307, scale_y = 1.107}, offset = {x = 3, y = 0} },
                    aspect = { ratio = 3.8, dominant_axis = "width" },
                    amount_config = {
                        alignment = "center",
                        color = Color3.fromRGB(255,255,255),
                        font = Enum.Font.FredokaOne,
                        stroke = { color = Color3.fromRGB(102, 56, 0), thickness = 2.5, transparency = 0 },
                        gradient = {
                            rotation = -90,
                            keypoints = {
                                { t = 0, color = { r = 255, g = 191, b = 0 } },   -- golden yellow top
                                { t = 1, color = { r = 255, g = 247, b = 0 } }    -- bright yellow bottom
                            },
                            transparency = NumberSequence.new{
                                NumberSequenceKeypoint.new(0, 0),
                                NumberSequenceKeypoint.new(1, 0)
                            }
                        },
                        left_padding_px = 60
                    },
                    plus_button = { enabled = true, icon = "rbxassetid://17016956685", size = {pxX = 22, pxY = 22}, offset = {x = -6, y = 0} }
                }},
                {type = "currency_display", config = {
                    currency = "gems",
                    background_image = "rbxassetid://17016939569",
                    icon = "rbxassetid://124465574877924",
                    icon_config = { position_kind = "left_center_edge", size = {scale_x = 0.338, scale_y = 1.219}, offset = {x = 3, y = 0} },
                    aspect = { ratio = 3.8, dominant_axis = "width" },
                    amount_config = {
                        alignment = "center",
                        color = Color3.fromRGB(255,255,255),
                        font = Enum.Font.FredokaOne,
                        stroke = { color = Color3.fromRGB(102, 56, 0), thickness = 2.5, transparency = 0 },
                        gradient = {
                            rotation = -90,
                            keypoints = {
                                { t = 0, color = { r = 255, g = 191, b = 0 } },
                                { t = 1, color = { r = 255, g = 247, b = 0 } }
                            },
                            transparency = NumberSequence.new{
                                NumberSequenceKeypoint.new(0, 0),
                                NumberSequenceKeypoint.new(1, 0)
                            }
                        },
                        left_padding_px = 60
                    },
                    plus_button = { enabled = true, icon = "rbxassetid://17016956685", size = {pxX = 22, pxY = 22}, offset = {x = -6, y = 0} }
                }},
                {type = "currency_display", config = {
                    currency = "coins",
                    background_image = "rbxassetid://17016939569",
                    icon = "rbxassetid://17016991150",
                    icon_config = { position_kind = "left_center_edge", size = {scale_x = 0.30, scale_y = 1.05}, offset = {x = 3, y = 0} },
                    aspect = { ratio = 3.8, dominant_axis = "width" },
                    amount_config = {
                        alignment = "center",
                        color = Color3.fromRGB(255,255,255),
                        font = Enum.Font.FredokaOne,
                        stroke = { color = Color3.fromRGB(102, 56, 0), thickness = 2.5, transparency = 0 },
                        gradient = {
                            rotation = -90,
                            keypoints = {
                                { t = 0, color = { r = 255, g = 191, b = 0 } },
                                { t = 1, color = { r = 255, g = 247, b = 0 } }
                            },
                            transparency = NumberSequence.new{
                                NumberSequenceKeypoint.new(0, 0),
                                NumberSequenceKeypoint.new(1, 0)
                            }
                        },
                        left_padding_px = 60
                    },
                    plus_button = { enabled = false }
                }},
            }
        },
        imported_bottom_bar = {
            position_scale = {x = 0.5, y = 0.99},
            size = {scaleX = 0.529887676, scaleY = 0.154213503},
            anchor = "bottom-center",
            background = {enabled = true, color = Color3.fromRGB(39, 174, 96), transparency = 0.5}, -- green
            layout = {type = "list", direction = "horizontal", spacing = 10},
            contents = {
                {type = "label", config = {text = "BOTTOM", color = Color3.fromRGB(255,255,255)}}
            }
        },
        imported_left_rail = {
            position_scale = {x = 0.00522466097, y = 0.5},
            size = {scaleX = 0.0966562182, scaleY = 0.44893378},
            anchor = "center-left",
            background = {enabled = false},
            -- Even spacing like InventoryPanel: 3 stacked rows, each row hosts 2 buttons centered
            layout = {type = "list", direction = "vertical", spacing = 6, padding = {top = 4, bottom = 4, left = 4, right = 4}},
            contents = {
                {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
                    {type = "menu_button", config = {name = "Store", text = "Store", background_image = "rbxassetid://16992152563", icon = "rbxassetid://17684357501", action = "shop_action", aspect = {ratio = 1.0, dominant_axis = "width"}, 
                    notification = { enabled = true, text = "-25%", position = "top-left-corner" }, 
                    icon_config = { size = {scale_x = 0.85, scale_y = 0.85}, position = {scale_x = 0.5, scale_y = 0.45}, offset = {x = 0, y = 0} }, 
                    text_config = { position = { bottom_offset = 18, side_margin = 6 }, stroke_color = Color3.fromRGB(76, 42, 1), shadow = {enabled = true, color = Color3.fromRGB(0,0,0), thickness = 2, transparency = 0.5 } } 
                }},
                    {type = "menu_button", config = {name = "Invite", text = "Invite", icon = "rbxassetid://16992260427", action = "rewards_action", aspect = {ratio = 1.0, dominant_axis = "width"}}}
                }}},
                {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
                    {type = "menu_button", config = {name = "Settings", text = "Settings", icon = "rbxassetid://17214007349", action = "settings_action", aspect = {ratio = 1.0, dominant_axis = "width"}}},
                    {type = "menu_button", config = {name = "Rebirth", text = "Rebirth", icon = "rbxassetid://16992290821", action = "quest_claim_action", aspect = {ratio = 1.0, dominant_axis = "width"}}}
                }}},
                {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
                    {type = "menu_button", config = {name = "Pet", text = "Pets", icon = "rbxassetid://16992283947", action = "pets_action", aspect = {ratio = 1.0, dominant_axis = "width"}}},
                    {type = "menu_button", config = {name = "Spins", text = "Spins", icon = "rbxassetid://16992338584", action = "daily_login_action", aspect = {ratio = 1.0, dominant_axis = "width"}}}
                }}}
            }
        },
        imported_right_cluster = {
            position_scale = {x = 0.995, y = 0.5},
            -- Match left rail size for consistent look
            size = {scaleX = 0.0966562182, scaleY = 0.44893378},
            anchor = "center-right",
            background = {enabled = false},
            layout = {type = "list", direction = "vertical", spacing = 6, padding = {top = 4, bottom = 4, left = 4, right = 4}},
            contents = {
                -- Row 1: Follow US (single)
                {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
                    {type = "menu_button", config = {name = "FollowUs", text = "Follow US", background_image = "rbxassetid://17016922306", icon = "rbxassetid://113655698755065", icon_config = { position_kind = "left_center_edge", size = {scale_x = 0.65, scale_y = 0.65}, offset = {x = 0, y = 0} }, action = "rewards_action", aspect = {ratio = 2.0, dominant_axis = "width"}, text_config = { position_kind = "manual", anchor_point = {x = 0.5, y = 0.5}, position_scale = {x = 0.5, y = 0.5}, position_offset = {x = 10, y = 0} }}}
                }}},

                -- Row 2: Free Rewards (single)
                {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
                    {type = "menu_button", config = {name = "FreeRewards", text = "Free Rewards", background_image = "rbxassetid://17016922306", icon = "rbxassetid://17016933050", icon_config = { position_kind = "left_center_edge", size = {scale_x = 0.5, scale_y = 0.5}, offset = {x = 0, y = 0} }, action = "rewards_action", aspect = {ratio = 2.0, dominant_axis = "width"}, text_config = { position_kind = "manual", anchor_point = {x = 0.5, y = 0.5}, position_scale = {x = 0.5, y = 0.5}, position_offset = {x = 10, y = 0} }}}
                }}},

                -- Row 3: Gifts + Trade
                {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
                    {type = "menu_button", config = {name = "Gifts", text = "Gifts", icon = "rbxassetid://17016894485", icon_config = { size = {scale_x = 0.9, scale_y = 0.9} }, action = "rewards_action", background_image = "rbxassetid://16992152563", aspect = {ratio = 1.0, dominant_axis = "width"}, notification = {enabled = true, text = "1", position = "top-left-corner"}}},
                    {type = "menu_button", config = {name = "Trade", text = "Trade", icon = "rbxassetid://17016842399", action = "inventory_action", aspect = {ratio = 1.0, dominant_axis = "width"}}}
                }}},

                -- Row 4: Worlds + Codes
                {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
                    {type = "menu_button", config = {name = "Worlds", text = "Worlds", icon = "rbxassetid://17016840352", action = "effects_action", aspect = {ratio = 1.0, dominant_axis = "width"}}},
                    {type = "menu_button", config = {name = "Codes", text = "Codes", icon = "rbxassetid://17017213702", action = "daily_login_action", aspect = {ratio = 1.0, dominant_axis = "width"}}}
                }}}
            }
        },
        imported_boosts_stack = {
            position_scale = {x = 0.00522465771, y = 0.740112424},
            size = {scaleX = 0.248757988, scaleY = 0.246622533},
            anchor = "top-left",
            -- Semantic position only used for grid fill and alignment (not absolute placement)
            position = "bottom-left",
            -- Keep visible while developing
            -- Keep background config for developers, but default to invisible in production
            background = { enabled = false, color = Color3.fromRGB(155, 89, 182), transparency = 0.5 },
            -- MCP uses UIGridLayout here; mirror with our grid and auto sizing
            -- For a bottom-left anchored stack we want rows to fill from bottom-left visually.
            -- Use grid and let BaseUI adjust StartCorner via semantic position.
            layout = { type = "grid", auto_size = true, button_count = 2, padding = { top = 4, bottom = 4, left = 4, right = 4 } },
            contents = {
                -- Premium boost button (lock icon + +50% label)
                {type = "menu_button", config = {
                    name = "PremiumBoost",
                    icon = "rbxassetid://18666999677", -- Lock icon from MCP
                    text = "+50%",
                    action = "rewards_action",
                    -- Square button constraint
                    aspect = { ratio = 1.0, dominant_axis = "width" },
                    icon_config = {
                        size = { scale_x = 0.69, scale_y = 0.69 },
                        position = { scale_x = 0.5, scale_y = 0.5 },
                        offset = { x = 0, y = -4 }
                    },
                    text_config = {
                        -- Dark stroke like MCP bottom text
                        stroke_color = Color3.fromRGB(25, 25, 25)
                    },
                    -- Mirror MCP inner TextLabel overlay (cyan->white gradient, blue-gray stroke)
                    overlay_label = {
                        enabled = true,
                        text = "", -- MCP glyph (PUA)
                        position_kind = "center",
                        height_scale = 1.0,
                        -- small nudge to align the glyph visually while staying relative
                        position_offset = { x = -5, y = 0 },
                        stroke = { color = Color3.fromRGB(49, 64, 88), thickness = 2, transparency = 0 },
                        gradient = {
                            rotation = -90,
                            keypoints = {
                                { t = 0.000, color = { r = 165, g = 197, b = 255 } },
                                { t = 1.000, color = { r = 255, g = 255, b = 255 } }
                            }
                        },
                        text_max_size = 36,
                        aspect_ratio = 1.0
                    }
                }},
                -- Kade button (avatar headshot in MCP; use person emoji placeholder)
                {type = "menu_button", config = {
                    name = "KadeBoost",
                    -- Use avatar headshot thumbnail directly; BaseUI now supports rbxthumb://
                    icon = "rbxthumb://type=AvatarHeadShot&id=536245038&w=420&h=420",
                    text = "Kade",
                    action = "rewards_action",
                    aspect = { ratio = 1.0, dominant_axis = "width" },
                    icon_config = {
                        size = { scale_x = 0.69, scale_y = 0.69 },
                        position = { scale_x = 0.5, scale_y = 0.5 },
                        offset = { x = 0, y = -4 }
                    },
                    text_config = {
                        stroke_color = Color3.fromRGB(25, 25, 25)
                    },
                    -- Add check-mark style text badge in top-right corner with MCP-like styling
                    notification = {
                        enabled = true,
                        text = "✓",
                        position = "top-right-corner",
                        aspect_ratio = 1.0,
                        -- Smaller square badge with rounded corners
                        size = { pxX = 18, pxY = 18 },
                        corner_radius = 4,
                        background_color = Color3.fromRGB(41, 121, 255), -- blue box
                        text_color = Color3.fromRGB(255, 255, 255), -- white check
                        text_stroke_color = Color3.fromRGB(0, 0, 0),
                        text_stroke_thickness = 1.5,
                        text_max_size = 14,
                        rotation = 15
                    }
                }}
            }
        },
        imported_notifications = {
            position_scale = {x = 0.5, y = 0.34},
            size = {scaleX = 0.600000024, scaleY = 1.0},
            anchor = "center",
            background = {enabled = true, color = Color3.fromRGB(230, 126, 34), transparency = 0.5}, -- orange
            layout = {type = "list", direction = "vertical", spacing = 8},
            contents = {
                {type = "label", config = {text = "NOTICES", color = Color3.fromRGB(255,255,255)}}
            }
        }
        
        -- Available positions: "top-left", "top-center", "top-right",
        --                     "center-left", "center", "center-right", 
        --                     "bottom-left", "bottom-center", "bottom-right"
        --
        -- Layout types: "list", "grid", "single", "custom"
        -- Background: Fully configurable colors, transparency, borders
        -- Contents: Array of UI elements with their own configurations
    },

    -- === OVERLAYS AND SINGLETON ELEMENTS (from imported GUI) ===
    overlays = {
        overlay_buying = {
            position = "center",
            size = {scaleX = 1.0, scaleY = 1.0},
            background = {enabled = true, color = Color3.fromRGB(0,0,0), transparency = 0.3},
            layout = {type = "single"},
            contents = {
                {type = "template", config = {template_type = "panel_large", props = {}}}
            }
        },
        pet_hover_tooltip = {
            position = "center",
            size = {pxX = 100, pxY = 78},
            layout = {type = "single"},
            contents = {
                {type = "template", config = {template_type = "panel_large", props = {}}}
            }
        }
    },

    singletons = {
        robux_icon = {
            position = "top-right",
            size = {pxX = 64, pxY = 64},
            layout = {type = "single"},
            contents = {
                {type = "image", config = {assetId = "rbxassetid://17120958513"}}
            }
        }
    },
    
    -- === PANEL CONFIGURATIONS (Image-based panels) ===
    -- 🎯 OVERRIDE EXAMPLES: How to customize specific panels when needed
    -- Most panels will automatically use the global defaults above ⬆️
    -- 
    -- ✨ STANDARDIZED CLOSE BUTTON SYSTEM:
    -- ALL panels automatically get the close button from global defaults unless explicitly disabled
    -- - Icon: 89257673063270 (new X button asset)
    -- - Position: top-right-corner extending outside panel bounds  
    -- - Hover effects: automatic red -> darker red transitions
    -- - No additional configuration needed per panel!
    --
    -- 🔄 ICON FALLBACK SYSTEM:
    -- Use 'icon' for asset ID and 'icon_fallback' for emoji/text backup
    -- - If asset fails to load, automatically switches to fallback
    -- - Example: icon = "12345", icon_fallback = "🎒"
    panel_configs = {
        -- 🟢 USES GLOBAL DEFAULTS: Settings panel inherits everything from defaults
        settings_panel = {
            header = {
                icon = "1003379313",                        -- Gear icon (only override needed)
                title_text = "Settings"                     -- Title text (only override needed)
                -- Everything else comes from global defaults!
            },
            settings = {
                -- Settings-specific overrides for toggles
                toggle_on = "5533192672",                   -- ON button toggle
                toggle_off = "5533209494",                  -- OFF button toggle
                setting_height = 55
            }
        },
        
        -- 🟢 USES GLOBAL DEFAULTS: Inventory panel inherits everything including close button
        inventory_panel = {
            header = {
                icon = "85179217604910",                   -- 🎨 NEW: Custom inventory bag icon
                icon_fallback = "🎒",                      -- 🔄 FALLBACK: Backpack emoji if asset fails
                icon_size = {scale = 1.0},                -- 🎨 BIGGER: 115% of header height (scales with screen)
                icon_position = "top-left-corner",         -- 🎯 POSITION: Top-left corner with anchor (0,0)
                title_text = "Inventory"                   -- Custom title
                -- Background images and close button come from global defaults!
            },
            -- Card/grid sizing controls used by InventoryPanel
            grid = {
                card_size = Vector2.new(65, 65),
                card_padding = Vector2.new(8, 8),
                -- Absolute icon size (inside each card). If omitted, icon scales with card.
                -- You can also use `icon_scale` to size the icon as a percentage of the card
                -- (takes precedence if provided here; see InventoryPanel for logic).
                -- Explicit size overrides scale if provided
                --icon_size = Vector2.new(56, 56),
                icon_scale = 0.85, -- used when icon_size is not provided

                -- NEW: Label layout controls for better separation and readability
                name_label = {
                    height_scale = 0.18,            -- portion of card height reserved for name text
                    bottom_offset_scale = 0.40,      -- distance from bottom of card
                    font = Enum.Font.GothamBold,
                    color = Color3.fromRGB(255, 255, 255)
                },
                power_label = {
                    height_scale = 0.14,
                    bottom_offset_scale = 0.14,
                    font = Enum.Font.Gotham,
                    prefix = "⚡ ",
                    color_from_rarity = true
                }
            }
        },
        
        -- 🔴 FULL OVERRIDE EXAMPLE: Admin panel completely different styling
        admin_panel = {
            background = {
                image = "16809347055",                      -- 🎨 OVERRIDE: Teal instead of blue
                corner_radius = 20                          -- 🎨 OVERRIDE: Different corner radius
            },
            header = {
                height = 80,                                -- 🎨 OVERRIDE: Taller header
                background_image = "6208057940",            -- 🎨 OVERRIDE: Blue header for contrast
                icon = "👑",                               -- 🎨 OVERRIDE: Admin crown icon
                icon_position = "center",                   -- 🎨 OVERRIDE: Centered icon
                title_text = "Admin Panel",
                title_color = Color3.fromRGB(255, 215, 0)  -- 🎨 OVERRIDE: Gold title
            }
        },
        
        -- 🟣 SPECIAL THEME EXAMPLE: Shop panel with unique styling
        shop_panel = {
            background = {
                image = "18852000893",                      -- 🎨 OVERRIDE: Special shop background
                corner_radius = 12
            },
            header = {
                background_image = "18852000893",           -- 🎨 OVERRIDE: Match background
                icon = "🛒",
                title_text = "Shop",
                title_color = Color3.fromRGB(255, 215, 0)  -- Gold text for shop
            }
        },
        
        -- 💡 HOW IT WORKS:
        -- • panels with NO CONFIG = 100% global defaults (blue panel + teal header)
        -- • panels with PARTIAL CONFIG = global defaults + your overrides
        -- • panels with FULL CONFIG = completely custom (but still inherits unspecified properties)
        --
        -- This means 90% of your panels will be visually consistent with ZERO configuration! 🎉
    },
    
    -- === COMPLEX MENU VIEWS (Multi-view Panes) ===
    -- For menus that can switch between different content views
    menu_views = {
        shop_panel = {
            default_view = "featured",
            views = {
                featured = {
                    name = "Featured",
                    icon = "⭐",
                    layout = {type = "grid", columns = 3, rows = 4},
                    contents = {
                        -- Featured items configuration
                    }
                },
                pets = {
                    name = "Pets", 
                    icon = "🐾",
                    layout = {type = "grid", columns = 4, rows = 5},
                    contents = {
                        -- Pet items configuration
                    }
                },
                boosts = {
                    name = "Boosts",
                    icon = "⚡", 
                    layout = {type = "list", direction = "vertical"},
                    contents = {
                        -- Boost items configuration
                    }
                }
            }
        }
    },
    
    -- === HELPER FUNCTIONS ===
    helpers = {
        -- Get current theme colors
        get_theme = function(config)
            return config.themes[config.active_theme] or config.themes.dark
        end,
        
        -- Get responsive scale factor
        get_scale_factor = function(config, screen_size)
            local width = screen_size and screen_size.X or 1200
            
            if width <= config.breakpoints.mobile then
                return config.scale_factors.mobile
            elseif width <= config.breakpoints.tablet then
                return config.scale_factors.tablet
            elseif width <= config.breakpoints.desktop then
                return config.scale_factors.desktop
            else
                return config.scale_factors.wide
            end
        end,
        
        -- Convert spacing key to UDim
        get_spacing = function(config, key)
            local value = config.spacing[key] or config.spacing.md
            return UDim.new(0, value)
        end,
        
        -- Convert radius key to UDim
        get_radius = function(config, key)
            local value = config.radius[key] or config.radius.md
            return UDim.new(0, value)
        end,
        
        -- NEW: Template system helpers
        get_template_path = function(config, template_name)
            return config.templates.storage_path .. "." .. template_name
        end,
        
        get_asset_id = function(config, category, key)
            local assets = config.templates.assets[category]
            return assets and assets[key] or "rbxassetid://0"
        end,
        
        get_template_config = function(config, template_type)
            local templates = config and config.templates
            local defaults = templates and templates.defaults
            if defaults and defaults[template_type] then
                return defaults[template_type]
            end
            return {}
        end,
        
        format_currency = function(config, amount)
            if amount >= 1000000 then
                return string.format("%.1fM", amount / 1000000)
            elseif amount >= 1000 then
                return string.format("%.1fK", amount / 1000)
            else
                return tostring(amount)
            end
        end,
        
        -- NEW: Pane system helpers
        get_pane_config = function(config, paneName)
            return config.panes and config.panes[paneName] or nil
        end,
        
        get_all_panes = function(config)
            return config.panes or {}
        end,
        
        get_menu_view_config = function(config, menuName, viewName)
            local menu = config.menu_views and config.menu_views[menuName]
            if menu and menu.views then
                return menu.views[viewName] or menu.views[menu.default_view]
            end
            return nil
        end,
        
        -- === ACTION SYSTEM HELPERS ===
        
        -- Get action configuration by name
        get_action_config = function(config, actionName)
            return config.actions and config.actions[actionName] or nil
        end,
        
        -- Get all available actions
        get_all_actions = function(config)
            return config.actions or {}
        end,
        
        -- Check if action conditions are met
        check_action_conditions = function(config, actionConfig, playerState)
            if not actionConfig.conditions then
                return true
            end
            
            -- Check admin_only condition
            if actionConfig.conditions.admin_only and not playerState.is_admin then
                return false
            end
            
            -- Check debug_mode condition
            if actionConfig.conditions.debug_mode and not playerState.debug_mode then
                return false
            end
            
            -- Check quest completion
            if actionConfig.conditions.quest_completed and not playerState.quest_completed then
                return false
            end
            
            -- Check if not claimed
            if actionConfig.conditions.not_claimed and playerState.already_claimed then
                return false
            end
            
            return true
        end,
        
        -- Execute action by name (helper for UI system)
        execute_action = function(config, actionName, playerState, actionHandler)
            local actionConfig = config.helpers.get_action_config(config, actionName)
            if not actionConfig then
                warn("Action not found:", actionName)
                return false
            end
            
            -- Check conditions
            if not config.helpers.check_action_conditions(config, actionConfig, playerState or {}) then
                warn("Action conditions not met:", actionName)
                return false
            end
            
            -- Execute action through handler
            if actionHandler and actionHandler.executeAction then
                return actionHandler:executeAction(actionConfig)
            end
            
            warn("No action handler provided for:", actionName)
            return false
        end,
        
        -- Get actions by type
        get_actions_by_type = function(config, actionType)
            local actions = {}
            for name, actionConfig in pairs(config.actions or {}) do
                if actionConfig.type == actionType then
                    actions[name] = actionConfig
                end
            end
            return actions
        end,
        
        -- === AUTO-SIZING GRID HELPERS ===
        
        -- Calculate optimal grid dimensions and button sizes for a given container and button count
        calculate_auto_grid = function(config, containerWidth, containerHeight, buttonCount, padding)
            padding = padding or {top = 3, bottom = 3, left = 3, right = 3}
            local spacing = 3
            
            -- Calculate available space after padding
            local availableWidth = containerWidth - padding.left - padding.right
            local availableHeight = containerHeight - padding.top - padding.bottom
            
            -- Find optimal grid dimensions
            local bestCols = 4 -- Start with 4 columns as preference
            local bestRows = math.ceil(buttonCount / bestCols)
            
            -- Try different column counts to find best fit
            for cols = 3, 5 do
                local rows = math.ceil(buttonCount / cols)
                if cols * rows >= buttonCount then
                    -- Calculate required space for this configuration
                    local reqWidth = cols * 50 + (cols - 1) * spacing -- minimum 50px buttons
                    local reqHeight = rows * 50 + (rows - 1) * spacing
                    
                    if reqWidth <= availableWidth and reqHeight <= availableHeight then
                        bestCols = cols
                        bestRows = rows
                        break
                    end
                end
            end
            
            -- Calculate optimal button size
            local buttonWidth = math.floor((availableWidth - (bestCols - 1) * spacing) / bestCols)
            local buttonHeight = math.floor((availableHeight - (bestRows - 1) * spacing) / bestRows)
            
            -- Ensure minimum button size
            buttonWidth = math.max(buttonWidth, 45)
            buttonHeight = math.max(buttonHeight, 45)
            
            return {
                columns = bestCols,
                rows = bestRows,
                cell_size = {width = buttonWidth, height = buttonHeight},
                spacing = spacing,
                padding = padding,
                info = {
                    button_count = buttonCount,
                    available_size = {width = availableWidth, height = availableHeight},
                    calculated_button_size = {width = buttonWidth, height = buttonHeight}
                }
            }
        end
    } -- Close helpers table
} -- Close the main uiConfig table


-- 🎉 UNIVERSAL CONSISTENCY SYSTEM - Successfully loaded!

return uiConfig 


--[[
MCP IMPORT SNIPPETS
Extract UIGradient ColorSequence keypoints from MCP (Studio console):

  local g = game.StarterGui.Guis.Layout.Boosts.Container.Premium.TextLabel:FindFirstChildOfClass("UIGradient")
  local out = {}
  for _, kp in ipairs(g.Color.Keypoints) do
      local c = kp.Value
      table.insert(out, string.format("{ t = %.3f, color = { r = %d, g = %d, b = %d } }",
          kp.Time, math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5)))
  end
  print("keypoints = {"..table.concat(out, ", ").."}")

Paste the printed table into an element's amount_config.gradient.keypoints, e.g.:

  amount_config = {
      gradient = {
          rotation = -90,
          keypoints = { { t = 0.000, color = { r = 255, g = 162, b = 0 } }, { t = 1.000, color = { r = 255, g = 247, b = 0 } } },
      }
  }
]]