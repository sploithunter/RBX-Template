-- Flash Effects Configuration
-- Configuration-driven flash effects for egg hatching animations
-- Following the "Configuration as Code" principle from COMPREHENSIVE_ARCHITECTURE.md

return {
    version = "1.0.0",
    
    -- Default flash effect to use
    default_effect = "starburst",
    
    -- Effect definitions
    effects = {
        -- ⭐ Star Burst Effect (IMPLEMENTED)
        starburst = {
            name = "Star Burst",
            description = "Multiple expanding stars radiating from center",
            type = "starburst",
            enabled = true,
            
            -- Visual configuration
            config = {
                star_count = 8,                    -- Number of stars
                min_size = 20,                     -- Minimum star size
                max_size = 80,                     -- Maximum star size
                expansion_distance = 400,           -- How far stars travel
                duration = 0.8,                    -- Total animation duration
                
                -- Colors (gradient from center to edge)
                colors = {
                    Color3.fromRGB(255, 255, 255), -- White center
                    Color3.fromRGB(255, 255, 150), -- Light yellow
                    Color3.fromRGB(255, 200, 100), -- Golden
                    Color3.fromRGB(255, 150, 50),  -- Orange edge
                },
                
                -- Animation properties
                rotation_speed = 360,              -- Degrees per second
                fade_in_time = 0.1,               -- Time to fade in
                fade_out_time = 0.3,              -- Time to fade out
                scale_overshoot = 1.2,            -- Scale overshoot factor
            }
        },
        
        -- 💥 Explosion Effect (PLACEHOLDER)
        explosion = {
            name = "Explosion",
            description = "Particle explosion with debris flying outward",
            type = "explosion",
            enabled = false, -- Not implemented yet
            
            config = {
                particle_count = 50,
                explosion_radius = 150,
                debris_types = {"spark", "smoke", "fire"},
                gravity_effect = true,
                duration = 1.2,
                
                colors = {
                    Color3.fromRGB(255, 100, 0),   -- Orange fire
                    Color3.fromRGB(255, 200, 0),   -- Yellow flame
                    Color3.fromRGB(255, 255, 255), -- White hot
                },
                
                shockwave_enabled = true,
                shockwave_size = 300,
                screen_shake = {
                    enabled = true,
                    intensity = 5,
                    duration = 0.3
                }
            }
        },
        
        -- ✨ Magic Sparkle Burst (PLACEHOLDER)
        sparkle_burst = {
            name = "Magic Sparkle Burst",
            description = "Hundreds of small sparkles exploding outward",
            type = "sparkle_burst",
            enabled = false, -- Not implemented yet
            
            config = {
                sparkle_count = 200,
                sparkle_size = {min = 3, max = 12},
                burst_radius = 180,
                twinkle_frequency = 8, -- Sparkles per second
                duration = 1.5,
                
                colors = {
                    Color3.fromRGB(255, 255, 255), -- White
                    Color3.fromRGB(255, 200, 255), -- Pink
                    Color3.fromRGB(200, 255, 255), -- Cyan
                    Color3.fromRGB(255, 255, 200), -- Yellow
                    Color3.fromRGB(200, 255, 200), -- Green
                },
                
                gravity_enabled = false,
                fade_pattern = "twinkle", -- "linear", "twinkle", "pulse"
                trail_enabled = true,
                trail_length = 10
            }
        },
        
        -- 🌊 Energy Wave (PLACEHOLDER)
        energy_wave = {
            name = "Energy Wave",
            description = "Concentric circles expanding from center",
            type = "energy_wave",
            enabled = false, -- Not implemented yet
            
            config = {
                wave_count = 3,
                wave_spacing = 0.2, -- Time between waves
                max_radius = 250,
                wave_thickness = 8,
                duration = 1.0,
                
                colors = {
                    Color3.fromRGB(100, 200, 255), -- Blue energy
                    Color3.fromRGB(200, 255, 255), -- Cyan
                    Color3.fromRGB(255, 255, 255), -- White
                },
                
                distortion_enabled = true,
                particle_trail = true,
                pulse_frequency = 4, -- Pulses per second
                transparency_gradient = true
            }
        },
        
        -- 🔥 Fire Burst (PLACEHOLDER)
        fire_burst = {
            name = "Fire Burst",
            description = "Flame particles shooting upward with smoke trails",
            type = "fire_burst",
            enabled = false, -- Not implemented yet
            
            config = {
                flame_count = 30,
                flame_height = {min = 50, max = 150},
                spread_angle = 60, -- Degrees
                duration = 1.8,
                
                colors = {
                    Color3.fromRGB(255, 50, 0),    -- Red fire
                    Color3.fromRGB(255, 150, 0),   -- Orange
                    Color3.fromRGB(255, 255, 0),   -- Yellow
                    Color3.fromRGB(100, 100, 100), -- Smoke
                },
                
                smoke_enabled = true,
                smoke_rise_speed = 50,
                heat_distortion = true,
                ember_particles = true,
                wind_effect = {
                    enabled = true,
                    direction = Vector3.new(1, 0, 0),
                    strength = 0.3
                }
            }
        },
        
        -- 🎆 Rainbow Burst (PLACEHOLDER)
        rainbow_burst = {
            name = "Rainbow Burst",
            description = "Colorful rainbow explosion with prismatic effects",
            type = "rainbow_burst",
            enabled = false, -- Not implemented yet
            
            config = {
                ray_count = 12,
                ray_length = 200,
                color_cycle_speed = 2, -- Cycles per second
                duration = 1.2,
                
                colors = {
                    Color3.fromRGB(255, 0, 0),     -- Red
                    Color3.fromRGB(255, 127, 0),   -- Orange
                    Color3.fromRGB(255, 255, 0),   -- Yellow
                    Color3.fromRGB(0, 255, 0),     -- Green
                    Color3.fromRGB(0, 0, 255),     -- Blue
                    Color3.fromRGB(75, 0, 130),    -- Indigo
                    Color3.fromRGB(148, 0, 211),   -- Violet
                },
                
                prism_effect = true,
                sparkle_overlay = true,
                color_blend_mode = "additive",
                rotation_enabled = true,
                rotation_speed = 180 -- Degrees per second
            }
        }
    },
    
    -- Effect categories for UI organization
    categories = {
        magical = {"starburst", "sparkle_burst", "rainbow_burst"},
        realistic = {"explosion", "fire_burst"},
        energy = {"energy_wave"},
    },
    
    -- Performance settings
    performance = {
        max_particles_per_effect = 500,
        reduce_effects_on_mobile = true,
        fps_threshold_for_reduction = 30,
        
        -- Quality levels
        quality_levels = {
            low = {
                particle_multiplier = 0.5,
                duration_multiplier = 0.8,
                color_complexity = "simple"
            },
            medium = {
                particle_multiplier = 0.8,
                duration_multiplier = 0.9,
                color_complexity = "medium"
            },
            high = {
                particle_multiplier = 1.0,
                duration_multiplier = 1.0,
                color_complexity = "full"
            }
        }
    }
}