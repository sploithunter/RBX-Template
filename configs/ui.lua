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

local uiConfig = {
    version = "2.0.0", -- Updated for template system
    
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
        
        -- Default template configurations
        defaults = {
            currency_display = {
                size = UDim2.new(0, 120, 0, 40),
                position = UDim2.new(0, 0, 0, 0),
                anchor_point = Vector2.new(0, 0),
                currency_type = "coins", -- Maps to assets.currency_icons
            },
            
            menu_button = {
                size = UDim2.new(0, 80, 0, 80),
                corner_radius = 12,
                icon_size = UDim2.new(0, 40, 0, 40),
                text_size = 14,
            },
            
            generic_item = {
                size = UDim2.new(0, 100, 0, 100),
                corner_radius = 8,
                stroke_thickness = 2,
                gradient_enabled = true,
            },
            
            large_panel = {
                size = UDim2.new(0.8, 0, 0.8, 0),
                position = UDim2.new(0.5, 0, 0.5, 0),
                anchor_point = Vector2.new(0.5, 0.5),
                corner_radius = 16,
            }
        }
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
    
    -- Responsive scaling factors
    scale_factors = {
        mobile = 0.6,
        tablet = 0.7,
        desktop = 0.8,
        wide = 0.9,
    },
    
    -- === COMPONENT DEFAULTS ===
    defaults = {
        button = {
            size = UDim2.new(0, 100, 0, 32),
            corner_radius = "md",
            font = "primary",
            font_size = "sm",
            padding = "md",
            sound_enabled = true,
            hover_scale = 1.05,
            press_scale = 0.95,
        },
        
        panel = {
            background_transparency = 0,
            border_size = 0,
            corner_radius = "md",
            shadow_enabled = true,
            shadow_size = 4,
            shadow_transparency = 0.3,
        },
        
        text_input = {
            size = UDim2.new(0, 180, 0, 30),
            corner_radius = "sm",
            font = "primary",
            font_size = "sm",
            padding = "sm",
            placeholder_transparency = 0.5,
        },
        
        modal = {
            backdrop_transparency = 0.3,
            animation_duration = 0.25,
            corner_radius = "lg",
            shadow_enabled = true,
        },
        
        toast = {
            duration = 3, -- seconds
            corner_radius = "md",
            shadow_enabled = true,
            animation_duration = 0.3,
        },
    },
    
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
        show_backgrounds = false,  -- Force show pane backgrounds for debugging
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
                -- Supports both emoji and asset IDs: icon = "💰" or icon = "7733686592"
                {type = "currency_display", config = {currency = "coins", icon = "💰", color = Color3.fromRGB(255, 215, 0)}}
            }
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
                border = {
                    enabled = true,
                    color = Color3.fromRGB(138, 43, 226),
                    thickness = 2,
                    transparency = 0.3
                }
            },
            layout = {type = "single"},
            contents = {
                -- Supports both emoji and asset IDs: icon = "💎" or icon = "7733686592" 
                {type = "currency_display", config = {currency = "gems", icon = "💎", color = Color3.fromRGB(138, 43, 226)}}
            }
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
                border = {
                    enabled = true,
                    color = Color3.fromRGB(0, 255, 255),
                    thickness = 2,
                    transparency = 0.3
                }
            },
            layout = {type = "single"},
            contents = {
                -- Supports both emoji and asset IDs: icon = "🔮" or icon = "7733686592"
                {type = "currency_display", config = {currency = "crystals", icon = "🔮", color = Color3.fromRGB(0, 255, 255)}}
            }
        },
        
        -- Player Info Pane (top-center - Colorado Plays, Level, XP)
        player_info_pane = {
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
            layout = {
                type = "single"
            },
            contents = {
                {type = "player_info", config = {}}
            }
        },

        -- Quest Tracker Pane (center-right with completely clear background)
        quest_tracker_pane = {
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
            position = "bottom-left", 
            offset = {x = 10, y = -10}, -- Safe padding from edges
            size = {width = 280, height = 140}, -- Container size - buttons will auto-fit
            background = {enabled = false}, -- Debug backgrounds will handle visualization
            layout = {
                type = "grid",
                auto_size = true, -- Enable automatic sizing based on content
                button_count = 7, -- Exact number of buttons for calculation
                padding = {top = 5, bottom = 5, left = 5, right = 5} -- Padding for calculations
            },
            contents = {
                -- Now using configuration-driven actions! Mix and match emoji and asset IDs:
                {type = "menu_button", config = {name = "Shop", icon = "rbxassetid://7733920644", text = "Shop", color = Color3.fromRGB(46, 204, 113), action = "shop_action"}},
                {type = "menu_button", config = {name = "Inventory", icon = "🎒", text = "Items", color = Color3.fromRGB(52, 152, 219), action = "inventory_action"}},
                {type = "menu_button", config = {name = "Effects", icon = "⚡", text = "Effects", color = Color3.fromRGB(155, 89, 182), action = "effects_action"}},
                {type = "menu_button", config = {name = "Settings", icon = "⚙️", text = "Settings", color = Color3.fromRGB(149, 165, 166), action = "settings_action"}},
                {type = "menu_button", config = {name = "Admin", icon = "👑", text = "Admin", color = Color3.fromRGB(231, 76, 60), action = "admin_action", admin_only = true}},
                -- Add more buttons with custom actions - automatically arranged in 4x2 grid
                {type = "menu_button", config = {name = "Daily", icon = "📅", text = "Daily", color = Color3.fromRGB(255, 165, 0), action = "daily_login_action"}},
                {type = "menu_button", config = {name = "Quest", icon = "🎯", text = "Quest", color = Color3.fromRGB(34, 139, 34), action = "quest_claim_action"}}
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
        
        rewards_button_pane = {
            position = "bottom-right", 
            offset = {x = -10, y = -10},  -- Standardized bottom alignment + small right padding
            size = {width = 120, height = 60},
            background = {enabled = false},
            layout = {type = "single"},
            contents = {
                {type = "rewards_button", config = {icon = "🎁", text = "Rewards", color = Color3.fromRGB(255, 215, 0), badge_count = 3, action = "rewards_action"}}
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
            return config.templates.defaults[template_type] or {}
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
    }
}

return uiConfig 