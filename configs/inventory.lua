-- Universal Inventory System Configuration
-- This file defines inventory buckets, schemas, and settings for the game

return {
    -- Version for migration support
    version = "1.0.0",
    
    -- Which inventory buckets this game uses
    enabled_buckets = {
        pets = true,
        weapons = false,      -- Disabled for pet simulator
        tools = false,        -- Disabled for pet simulator
        consumables = true,
        resources = true,     -- NEW: For stackable resources like wood, ore, etc.
        cosmetics = false,
        mounts = false
    },
    
    -- Bucket definitions
    buckets = {
        pets = {
            display_name = "Pets",
            icon = "🐾",
            base_limit = 50,
            stack_size = 1,              -- Pets don't stack
            allow_duplicates = true,     -- Can have multiple of same pet type
            storage_type = "unique",     -- NEW: Each pet has unique properties
            
            -- Limit extensions via gamepasses
            limit_extensions = {
                { 
                    gamepass_id = 123456789,  -- TODO: Replace with actual gamepass ID
                    additional_slots = 50,
                    name = "Extra Pet Storage"
                },
                { 
                    gamepass_id = 987654321,  -- TODO: Replace with actual gamepass ID
                    additional_slots = 100,
                    name = "Ultimate Pet Storage"
                }
            },
            
            -- Schema for pet instances
            item_schema = {
                required = {
                    "id",               -- Pet type from pet config
                    "variant",          -- basic/golden/rainbow
                    "obtained_at"       -- Timestamp
                },
                optional = {
                    "level",            -- Default: 1
                    "exp",              -- Default: 0
                    "nickname",         -- Default: ""
                    "stats",            -- Default: base stats from pet config
                    "enchantments",     -- Default: {}
                    "locked"            -- Default: false (for trade protection)
                }
            },
            
            -- Validation rules
            validation = {
                max_nickname_length = 20,
                allowed_characters = "^[%w%s]+$",  -- Alphanumeric + spaces
                max_level = 100,
                max_enchantments = 5
            }
        },
        
        consumables = {
            display_name = "Consumables",
            icon = "🧪",
            base_limit = 100,
            stack_size = 99,            -- Items can stack
            allow_duplicates = false,   -- Same items merge into stacks
            storage_type = "stackable", -- NEW: Indicates items are identical/countable
            
            -- Limit extensions via gamepasses
            limit_extensions = {
                {
                    gamepass_id = 555666777,  -- TODO: Replace with actual gamepass ID
                    additional_slots = 50,
                    name = "Extra Storage"
                }
            },
            
            item_schema = {
                required = {
                    "id",
                    "quantity",
                    "obtained_at"
                },
                optional = {
                    "expires_at"        -- For time-limited items
                }
            },
            
            validation = {
                max_quantity_per_stack = 99,
                min_quantity = 1
            }
        },
        
        resources = {
            display_name = "Resources",
            icon = "🪨",
            base_limit = 50,            -- 50 different resource types
            stack_size = 10000,         -- Each resource can stack to 10k
            allow_duplicates = false,   -- Same resources merge into stacks
            storage_type = "stackable", -- Identical items, store as counts
            
            item_schema = {
                required = {
                    "id",               -- Resource type (wood, stone, iron, etc.)
                    "quantity",         -- How many of this resource
                    "obtained_at"       -- When first obtained
                },
                optional = {
                    "quality",          -- Resource quality/grade
                    "source"            -- Where it was obtained
                }
            },
            
            validation = {
                max_quantity_per_stack = 10000,
                min_quantity = 1
            }
        }
    },
    
    -- Equipped configuration
    equipped = {
        pets = {
            slots = 3,                  -- Number of equipped slots
            display_name = "Active Pets",
            icon = "🐾",
            
            -- Slot extensions via gamepasses
            slot_extensions = {
                {
                    gamepass_id = 456789123,  -- TODO: Replace with actual gamepass ID
                    additional_slots = 1,
                    name = "4th Pet Slot"
                },
                {
                    gamepass_id = 789123456,  -- TODO: Replace with actual gamepass ID
                    additional_slots = 2,
                    name = "5th & 6th Pet Slots"
                }
            }
        }
    },
    
    -- General settings
    settings = {
        enable_trading = true,
        enable_item_locking = true,     -- Prevent accidental deletion/trading
        enable_bulk_actions = true,     -- Mass delete/organize
        auto_sort_enabled = true,
        default_sort_order = "rarity",  -- rarity/level/newest/oldest
        
        -- UID generation settings
        uid_prefix_length = 8,          -- Length of random suffix
        uid_include_timestamp = true,
        
        -- Debug settings
        debug_logging = true,           -- Enable detailed logging for development
        trace_operations = true,        -- Trace all inventory operations
        validate_on_load = true         -- Validate inventory structure on player join
    },
    
    -- Default values for new items
    defaults = {
        pets = {
            level = 1,
            exp = 0,
            nickname = "",
            stats = {},  -- Will be filled from pet config
            enchantments = {},
            locked = false
        },
        consumables = {
            quantity = 1
        }
    }
}