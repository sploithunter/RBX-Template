-- Egg System Configuration
-- Centralized settings for egg interaction, UI, and performance

return {
    version = "1.0.0",

    -- === PROXIMITY & INTERACTION SETTINGS ===
    proximity = {
        max_distance = 18, -- Maximum distance to show egg UI and allow interaction (studs)
        interaction_key = Enum.KeyCode.E, -- Key for egg interaction
        hatch_max_key = Enum.KeyCode.R,
        auto_hatch_key = Enum.KeyCode.T,
    },

    -- === PERFORMANCE SETTINGS ===
    performance = {
        update_interval = 0.1, -- How often to check for nearby eggs (seconds) - 10fps
        server_update_threshold = 30, -- Frames before calling setLastEgg on server
        ui_position_update_rate = 0.05, -- How often to update UI position for smooth movement
    },

    -- === COOLDOWN SETTINGS ===
    cooldowns = {
        purchase_cooldown = 3, -- Seconds between egg purchases per player
        ui_error_display_time = 3, -- How long error messages stay on screen
        success_notification_time = 5, -- How long success notifications stay on screen
    },

    -- Server-authoritative hatch transaction settings. The client may request any
    -- count up to max_count, but the server resolves the actual count from
    -- entitlements, currency, storage, and this config.
    hatching = {
        max_count = 99,
        default_requested_count = 1,
        allow_partial = true,
        transaction_lock_seconds = 0.35,
        failed_request_lock_seconds = 0.2,
        auto_loop_delay = 3,
        default_max_entitled_count = 99,
        compat_purchase_types = {
            Single = 1,
            Triple = 3,
            Auto = 99,
            Max = 99,
        },
        animation = {
            max_visible_eggs = 99,
            use_authored_egg_visual = true,
            authored_visual_scale = 1.25,
        },
        shop_stubs = {
            max_hatch_count = {
                enabled = true,
                default_value = 99,
                source = "config",
            },
            auto_hatch = {
                enabled = true,
                owned_by_default = true,
                source = "stub",
            },
            fast_hatch = {
                enabled = true,
                owned_by_default = false,
                source = "stub",
            },
            skip_hatch = {
                enabled = true,
                owned_by_default = false,
                source = "stub",
            },
            golden_mode = {
                enabled = true,
                owned_by_default = false,
                cost_multiplier = 20,
                source = "stub",
            },
            luck_bonus = {
                enabled = true,
                default_multiplier = 0,
                source = "stub",
            },
            secret_luck_bonus = {
                enabled = true,
                default_multiplier = 0,
                source = "stub",
            },
        },
    },

    -- === UI CONFIGURATION ===
    ui = {
        -- Egg Preview UI Dimensions
        preview_size = {
            width = 200,
            height = 120, -- Increased height for three-line layout (name, price, prompt)
        },

        hatch_panel = {
            enabled = true,
            width = 500,
            height = 176,
            settings_height = 252,
            bottom_offset = 126,
            count_step = 1,
            count_large_step = 10,
            default_selected_count = 1,
            status_display_time = 3,
            buttons = {
                hatch = "Hatch",
                max = "Max",
                auto = "Auto",
                settings = "Filters",
            },
            auto_delete = {
                rarity_filters = {
                    "common",
                    "uncommon",
                    "rare",
                    "epic",
                },
                pet_type_filters = {
                    "bear",
                    "doggy",
                    "bunny",
                    "colorado",
                },
                variant_filters = {
                    "basic",
                    "golden",
                    "rainbow",
                },
            },
            modes = {
                golden = {
                    label = "Golden",
                    option = "goldenMode",
                },
                fast = {
                    label = "Fast",
                    option = "fastHatch",
                },
                skip = {
                    label = "Skip",
                    option = "skipHatch",
                },
                silent = {
                    label = "Silent",
                    option = "silentHatch",
                },
            },
        },

        -- Pet Preview UI Dimensions
        pet_preview_size = {
            width = 600,
            height = 100,
        },

        -- UI Positioning (offset from egg world position)
        position_offset = {
            x = -100, -- Pixels left of egg center
            y = -50, -- Pixels above egg center
        },

        -- Pet Preview Positioning (offset from egg world position)
        pet_preview_offset = {
            x = -300, -- Pixels left of egg center (centers 600px wide panel)
            y = -250, -- Pixels above egg (enough space to clear egg interaction UI)
        },

        -- Colors and Styling
        colors = {
            background = Color3.fromRGB(255, 255, 255), -- White background for pet preview frame
            border = Color3.fromRGB(0, 0, 0), -- Black border for contrast
            text_primary = Color3.fromRGB(0, 0, 0), -- Black primary text
            text_secondary = Color3.fromRGB(100, 100, 100), -- Dark gray secondary text
            success_bg = Color3.fromRGB(34, 139, 34),
            error_bg = Color3.fromRGB(220, 53, 69),

            -- Pet preview colors
            pet_preview_bg = Color3.fromRGB(255, 255, 255), -- White background (same as main background)
            pet_preview_border = Color3.fromRGB(0, 100, 200), -- Blue border
            very_rare_text = Color3.fromRGB(150, 0, 0), -- Dark red for very low chances

            -- Pet container colors (individual pet frames)
            pet_container_bg = "rarity", -- "rarity" = use rarity color, or set Color3 for uniform
            pet_container_transparency = 0.7, -- Slightly more opaque for better visibility
            pet_container_border = Color3.fromRGB(200, 200, 200), -- Light gray border

            -- Pet icon/viewport colors
            pet_icon_bg = Color3.fromRGB(240, 240, 240), -- Light gray viewport background
            pet_icon_transparency = 0.2, -- Semi-transparent to show slight background
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
            pet_chance = Enum.Font.Bangers,

            -- Pet container fonts (for individual pet displays)
            pet_icon_fallback = Enum.Font.GothamBold, -- Font for emoji fallback icons (currently used)
            pet_name_secondary = Enum.Font.Gotham, -- Alternative pet name font (available for future use)
            pet_stats = Enum.Font.RobotoMono, -- For detailed pet stats (available for future use)
            rarity_label = Enum.Font.GothamBold, -- For rarity indicators (available for future use)

            -- Available font options (you can swap any of the above to these):
            -- Standard fonts that work reliably:
            -- Enum.Font.Gotham                         - Clean, readable (being replaced by Montserrat)
            -- Enum.Font.GothamBold                     - Bold version of Gotham
            -- Enum.Font.GothamBlack                    - Extra bold Gotham
            -- Enum.Font.Montserrat                     - Replacement for Gotham
            -- Enum.Font.MontserratBold                 - Bold Montserrat
            -- Enum.Font.Arimo                          - Replacement for Arial
            -- Enum.Font.ArimoBold                      - Bold Arimo
            -- Enum.Font.SourceSans                     - Clean, readable
            -- Enum.Font.SourceSansBold                 - Bold Source Sans
            -- Enum.Font.RobotoMono                     - Monospace alternative
            -- Enum.Font.SpecialElite                   - Typewriter style
            -- Enum.Font.Creepster                      - Horror/spooky theme
            -- Enum.Font.Bangers                        - Comic book style
            -- Enum.Font.Kalam                          - Handwritten style
            -- Enum.Font.PatrickHand                    - Casual handwritten
            --
            -- Note: Builder fonts may require special installation or may not be
            -- available by default. Use the fonts listed above for guaranteed compatibility.
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
        enabled = true, -- Whether to show pet preview when approaching eggs
        show_title = false, -- Whether to show title (saves space when false)
        title_text = "Pet Chances", -- Text to display in title (configurable)
        height_above_egg = 7, -- Default studs above egg to position billboard
        billboard_size = { 10, 2.5 }, -- BillboardGui size in studs [width, height]

        -- Per-egg height adjustments (optional - overrides default height_above_egg)
        -- Useful for eggs of different sizes that need custom spacing
        egg_height_overrides = {
            -- ["basic_egg"] = 2.5,          -- Basic egg uses 2.5 studs instead of default 7
            -- ["rare_egg"] = 8,             -- Rare egg uses 8 studs (taller egg needs more space)
            -- ["legendary_egg"] = 10,       -- Legendary egg uses 10 studs (very tall egg)
        },

        min_chance_to_show = 0.0001, -- Minimum chance (0.01%) to show pet, lower shows as "??"
        max_pets_to_display = 6, -- Maximum number of pets to show in preview (fits horizontal layout)
        grid_columns = 5, -- Number of columns in pet grid (horizontal row)
        pet_icon_size = 60, -- Size of each pet icon in pixels
        pet_spacing = 15, -- Horizontal spacing between pets in pixels
        smart_percentage_formatting = true, -- Use intelligent digit formatting (25%, 1%, 0.01%)
        fallback_precision = 2, -- Fallback decimal places if smart formatting disabled

        -- Display settings
        show_variant_names = true, -- Show "Golden Bear" vs just "Bear"
        group_by_rarity = true, -- Group pets by rarity in display
        sort_by_chance = true, -- Sort pets by chance (highest first)

        -- Per-egg display overrides (optional - overrides global settings)
        egg_display_overrides = {
            -- Per-egg customization examples:
            -- ["basic_egg"] = {
            --     show_variant_names = false,        -- Hide pet names for this egg
            --     pet_container_transparency = 1.0,  -- Make containers fully transparent
            --     pet_container_bg = Color3.fromRGB(50, 50, 50),  -- Custom bg color (overrides rarity)
            -- },
            -- ["golden_egg"] = {
            --     pet_container_bg = Color3.fromRGB(255, 215, 0),  -- Golden background for golden egg
            --     pet_container_transparency = 0.3,                -- More opaque for premium egg
            --     min_chance_to_show = 0.00001,                   -- Show even rarer pets (0.001%)
            -- },
            -- ["legendary_egg"] = {
            --     min_chance_to_show = 0.000001,                  -- Ultra rare threshold (0.0001%)
            -- },
        },

        -- Asset loading
        load_pet_icons = true, -- Whether to load actual pet model icons (3D models)
        fallback_to_emoji = true, -- Use emoji if asset loading fails
        icon_cache_time = 300, -- Time to cache loaded icons (seconds)

        -- 3D Model display options
        enable_model_spinning = true, -- Whether 3D models should rotate/spin
        model_rotation_speed = 1, -- Rotation speed (degrees per frame)
        static_camera_angle = 45, -- Camera angle if spinning disabled (degrees)
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
        log_proximity_changes = true, -- Log when entering/leaving egg range
        log_server_calls = true, -- Log setLastEgg server calls
        log_ui_updates = false, -- Log UI position updates (performance impact)
        log_distance_checks = false, -- Log distance calculations (very verbose)
    },

    -- === SPAWNING SETTINGS ===
    spawning = {
        spawn_point_name = "EggSpawnPoint", -- Name of parts to look for as spawn points
        search_workspace = true, -- Whether to search entire workspace for spawn points
        auto_spawn_on_startup = true, -- Whether to spawn eggs automatically on server start
        respawn_delay = 0, -- Delay before respawning egg after purchase (0 = immediate)
    },

    -- === VALIDATION SETTINGS ===
    validation = {
        -- Server-side validation strictness
        enforce_distance_check = true, -- Always validate distance on server
        enforce_currency_check = true, -- Always validate currency on server
        enforce_cooldown_check = true, -- Always validate cooldowns on server

        -- Client-side pre-validation
        client_distance_precheck = true, -- Check distance on client before server call
        client_currency_preview = true, -- Show currency requirements in UI
    },
}
