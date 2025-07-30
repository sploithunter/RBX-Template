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
        
        -- UI Positioning (offset from egg world position)
        position_offset = {
            x = -100,  -- Pixels left of egg center
            y = -50,   -- Pixels above egg center
        },
        
        -- Colors and Styling
        colors = {
            background = Color3.fromRGB(30, 30, 30),
            border = Color3.fromRGB(255, 255, 255),
            text_primary = Color3.fromRGB(255, 255, 255),
            text_secondary = Color3.fromRGB(200, 200, 200),
            success_bg = Color3.fromRGB(34, 139, 34),
            error_bg = Color3.fromRGB(220, 53, 69),
        },
        
        -- Corner Radius
        corner_radius = 12,
        border_thickness = 2,
        
        -- Fonts
        fonts = {
            title = Enum.Font.GothamBold,
            prompt = Enum.Font.Gotham,
            notification = Enum.Font.Gotham,
        },
        
        -- Animation Settings
        animations = {
            slide_in_time = 0.3,
            slide_in_style = Enum.EasingStyle.Back,
            slide_in_direction = Enum.EasingDirection.Out,
        },
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