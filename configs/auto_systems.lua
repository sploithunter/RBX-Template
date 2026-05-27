-- Phase 5 auto-system configuration.
-- Player profiles store choices; this file is the source of truth for valid
-- target modes, default settings, and which hatch filters designers allow.

return {
    version = "1.0.0",
    enabled = true,

    auto_target = {
        enabled = true,
        default_enabled = false,
        default_mode = "nearest",
        default_selected_currency = "crystals",
        current_world_only = true,
        request_interval_seconds = 0.3,
        modes = {
            nearest = {
                display_name = "Nearest",
                sort = "distance_asc",
            },
            highest_value = {
                display_name = "Highest Value",
                sort = "value_desc",
            },
            weakest = {
                display_name = "Weakest",
                sort = "hp_asc",
            },
            strongest = {
                display_name = "Strongest",
                sort = "hp_desc",
            },
            selected_currency = {
                display_name = "Selected Currency",
                sort = "value_desc",
                requires_currency = true,
            },
        },
        compatibility_toggles = {
            free_mode = "weakest",
            paid_mode = "highest_value",
        },
    },

    auto_delete = {
        enabled = true,
        default_enabled = false,
        allow_rarity_filters = true,
        allow_pet_type_filters = true,
        allow_variant_filters = true,
        protect_unique = true,
        protected_rarities = {
            secret = true,
            exclusive = true,
            huge = true,
        },
        defaults = {
            rarities = {},
            pet_types = {},
            variants = {},
        },
    },
}
