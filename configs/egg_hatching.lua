-- Egg Hatching Animation Configuration
-- Timing and speed settings for the egg hatching animation sequence
-- Following the "Configuration as Code" principle from COMPREHENSIVE_ARCHITECTURE.md

local config = {
    version = "1.0.0",
    
    -- === SPEED PRESETS ===
    -- Pre-configured timing sets for different experiences
    speed_presets = {
        -- Normal speed - balanced and cinematic
        normal = {
            name = "Normal",
            description = "Standard cinematic timing for immersive experience",
            speed_multiplier = 1.0,
        },
        
        -- Fast speed - quicker for frequent hatching
        fast = {
            name = "Fast", 
            description = "25% faster for active gameplay",
            speed_multiplier = 0.75,
        },
        
        -- Very fast speed - for bulk hatching
        very_fast = {
            name = "Very Fast",
            description = "50% faster for bulk egg opening",
            speed_multiplier = 0.5,
        },
        
        -- Ultra fast speed - minimal timing for rapid hatching
        ultra_fast = {
            name = "Ultra Fast",
            description = "Ultra-fast for maximum efficiency",
            speed_multiplier = 0.25,
        },
        
        -- Slow speed - extended for dramatic effect
        slow = {
            name = "Slow",
            description = "25% slower for dramatic effect",
            speed_multiplier = 1.25,
        },
    },
    
    -- === DEFAULT TIMING CONFIGURATION ===
    -- Base timing values (will be multiplied by speed_multiplier)
    timing = {
        -- Shake phase
        shake_duration = 2.0,           -- How long each egg shakes
        shake_wait_duration = 2.0,      -- How long to wait for all shaking to complete
        
        -- Flash and reveal phase  
        flash_duration = 0.5,           -- Duration of flash effect
        reveal_duration = 1.0,          -- Duration of pet reveal animation
        stagger_delay = 0.2,            -- Delay between each egg in multi-egg sequences
        
        -- Completion and cleanup
        reveal_completion_wait = 1.5,   -- Wait time after all reveals complete
        result_enjoyment_time = 1.0,    -- Time to enjoy results before screen restore
        cleanup_pause_time = 1.0,       -- Pause before final cleanup
        
        -- Screen transitions
        screen_clear_duration = 0.3,    -- Time for UI elements to animate off-screen
        screen_restore_duration = 0.3,  -- Time for UI elements to animate back
    },
    
    -- === CURRENT ACTIVE PRESET ===
    -- Change this to use different speed presets
    current_preset = "normal",  -- Options: "normal", "fast", "very_fast", "ultra_fast", "slow"
    
    -- === ADVANCED SETTINGS ===
    advanced = {
        -- Performance optimizations
        skip_shake_for_large_batches = true,  -- Skip shake animation for 10+ eggs
        large_batch_threshold = 10,           -- Number of eggs to trigger performance mode
        
        -- Multi-egg behavior
        max_simultaneous_reveals = 5,        -- Maximum eggs revealing at once (performance)
        batch_reveal_mode = "staggered",      -- "staggered" or "simultaneous" 
        
        -- Debug options
        enable_timing_debug = false,         -- Show detailed timing debug in console
        show_speed_multiplier = false,       -- Display current speed in UI
    },
    
    -- === TIMING CALCULATION HELPERS ===
    -- Functions to calculate adjusted timings (used by EggHatchingService)
    helpers = {},
    
    -- === CONFIGURATION VALIDATION ===
    validation = {
        min_speed_multiplier = 0.1,   -- Minimum allowed speed (10x slower)
        max_speed_multiplier = 10.0,  -- Maximum allowed speed (10x faster)
        
        -- Required timing keys
        required_timings = {
            "shake_duration",
            "shake_wait_duration", 
            "flash_duration",
            "reveal_duration",
            "stagger_delay",
            "reveal_completion_wait",
            "result_enjoyment_time",
            "cleanup_pause_time",
        },
    },
}

-- Add helper functions that reference the main config table directly
local function get_speed_multiplier(config)
    local preset = config.speed_presets[config.current_preset]
    return preset and preset.speed_multiplier or 1.0
end

local function get_adjusted_timing(config, timing_key)
    local base_time = config.timing[timing_key] or 1.0
    local multiplier = get_speed_multiplier(config)
    return base_time * multiplier
end

local function get_adjusted_timings(config)
    local multiplier = get_speed_multiplier(config)
    local adjusted = {}
    
    for key, base_time in pairs(config.timing) do
        adjusted[key] = base_time * multiplier
    end
    
    return adjusted
end

-- Attach helper functions to the config
config.helpers = {
    get_speed_multiplier = function() return get_speed_multiplier(config) end,
    get_adjusted_timing = function(timing_key) return get_adjusted_timing(config, timing_key) end,
    get_adjusted_timings = function() return get_adjusted_timings(config) end,
}

return config