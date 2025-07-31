-- Egg System Configuration
-- Centralized settings for egg interaction, UI, and performance

return {
    version = "1.0.0",
    
    -- === PROXIMITY & INTERACTION SETTINGS ===
    proximity = {
        max_distance = 10,              -- Maximum distance to show egg UI and allow interaction (studs)
        interaction_key = Enum.KeyCode.E, -- Key for egg interaction
    },
    
    -- === PERFORMANCE SETTINGS ===
    performance = {
        update_interval = 0.1,          -- How often to check for nearby eggs (seconds) - 10fps
        server_update_threshold = 30,   -- Frames before calling setLastEgg on server  
        ui_position_update_rate = 0.05, -- How often to update UI position for smooth movement
    },
    
    -- === COOLDOWN SETTINGS ===
    cooldowns = {
        purchase_cooldown = 3,          -- Seconds between egg purchases per player
        ui_error_display_time = 3,      -- How long error messages stay on screen
        success_notification_time = 5,  -- How long success notifications stay on screen
    },
    
    -- === UI CONFIGURATION ===
    ui = {
        -- Egg Preview UI Dimensions
        preview_size = {
            width = 200,
            height = 100,
        },
        
        -- Pet Preview UI Dimensions  
        pet_preview_size = {
            width = 400,
            height = 300,
        },
        
        -- UI Positioning (offset from egg world position)
        position_offset = {
            x = -100,  -- Pixels left of egg center
            y = -50,   -- Pixels above egg center
        },
        
        -- Pet Preview Positioning (offset from egg world position)
        pet_preview_offset = {
            x = -200,  -- Pixels left of egg center
            y = -350,  -- Pixels above egg center (higher than basic preview)
        },
        
        -- Colors and Styling
        colors = {
            background = Color3.fromRGB(30, 30, 30),
            border = Color3.fromRGB(255, 255, 255),
            text_primary = Color3.fromRGB(255, 255, 255),
            text_secondary = Color3.fromRGB(200, 200, 200),
            success_bg = Color3.fromRGB(34, 139, 34),
            error_bg = Color3.fromRGB(220, 53, 69),
            
            -- Pet preview colors
            pet_preview_bg = Color3.fromRGB(20, 20, 20),
            pet_preview_border = Color3.fromRGB(100, 100, 255),
            very_rare_text = Color3.fromRGB(255, 100, 100), -- For very low chances (<0.1%)
        },
        
        -- Corner Radius
        corner_radius = 12,
        border_thickness = 2,
        
        -- Fonts
        fonts = {
            title = Enum.Font.GothamBold,
            prompt = Enum.Font.Gotham,
            notification = Enum.Font.Gotham,
            pet_name = Enum.Font.GothamBold,
            pet_chance = Enum.Font.Gotham,
        },
        
        -- Animation Settings
        animations = {
            slide_in_time = 0.3,
            slide_in_style = Enum.EasingStyle.Back,
            slide_in_direction = Enum.EasingDirection.Out,
        },
    },
    
    -- === PET PREVIEW SETTINGS ===
    pet_preview = {
        enabled = true,                     -- Whether to show pet preview when approaching eggs
        min_chance_to_show = 0.001,        -- Minimum chance (0.1%) to show pet, lower shows as "??"
        max_pets_to_display = 8,           -- Maximum number of pets to show in preview
        grid_columns = 4,                  -- Number of columns in pet grid
        pet_icon_size = 60,                -- Size of each pet icon in pixels
        chance_precision = 2,              -- Decimal places for percentage display (e.g., 2 = "5.25%")
        
        -- Display settings
        show_variant_names = true,         -- Show "Golden Bear" vs just "Bear"
        group_by_rarity = true,            -- Group pets by rarity in display
        sort_by_chance = true,             -- Sort pets by chance (highest first)
        
        -- Asset loading
        load_pet_icons = true,             -- Whether to load actual pet model icons (3D models)
        fallback_to_emoji = true,          -- Use emoji if asset loading fails
        icon_cache_time = 300,             -- Time to cache loaded icons (seconds)
        
        -- 3D Model display options
        enable_model_spinning = true,      -- Whether 3D models should rotate/spin
        model_rotation_speed = 1,          -- Rotation speed (degrees per frame)
        static_camera_angle = 45,          -- Camera angle if spinning disabled (degrees)
    },
    
    -- === ERROR MESSAGES ===
    messages = {
        character_not_ready = "Character not ready",
        egg_not_found = "Egg not found",
        too_far_away = "You must be closer to the egg",
        egg_config_error = "Egg configuration error", 
        server_not_ready = "Server not ready, please restart game",
        connection_error = "Connection error",
        purchase_failed = "Purchase failed",
        insufficient_currency = "Insufficient funds",
        transaction_failed = "Transaction failed",
        hatching_failed = "Hatching failed",
        cooldown_active = "Please wait before purchasing again",
    },
    
    -- === DEBUG SETTINGS ===
    debug = {
        log_proximity_changes = true,   -- Log when entering/leaving egg range
        log_server_calls = true,        -- Log setLastEgg server calls
        log_ui_updates = false,         -- Log UI position updates (performance impact)
        log_distance_checks = false,    -- Log distance calculations (very verbose)
    },
    
    -- === SPAWNING SETTINGS ===
    spawning = {
        spawn_point_name = "EggSpawnPoint", -- Name of parts to look for as spawn points
        search_workspace = true,            -- Whether to search entire workspace for spawn points
        auto_spawn_on_startup = true,       -- Whether to spawn eggs automatically on server start
        respawn_delay = 0,                  -- Delay before respawning egg after purchase (0 = immediate)
    },
    
    -- === VALIDATION SETTINGS ===
    validation = {
        -- Server-side validation strictness
        enforce_distance_check = true,      -- Always validate distance on server
        enforce_currency_check = true,      -- Always validate currency on server
        enforce_cooldown_check = true,      -- Always validate cooldowns on server
        
        -- Client-side pre-validation
        client_distance_precheck = true,    -- Check distance on client before server call
        client_currency_preview = true,     -- Show currency requirements in UI
    },
}