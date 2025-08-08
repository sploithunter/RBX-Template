-- Universal Inventory System Configuration
-- This file defines inventory buckets, schemas, and settings for the game

return {
    -- Version for migration support
    version = "1.0.0",
    
    -- Which inventory buckets this game uses
    enabled_buckets = {
        pets = true,
        weapons = false,      -- Disabled for pet simulator
        tools = true,         -- Enabled for pickaxes and mining tools
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
        },
        
        tools = {
            display_name = "Tools",
            icon = "🔧",
            base_limit = 25,            -- 25 different tools
            stack_size = 1,             -- Tools don't stack (each has durability)
            allow_duplicates = true,    -- Can have multiple of same tool type
            storage_type = "unique",    -- Each tool instance has unique properties
            
            item_schema = {
                required = {
                    "id",               -- Tool type (pickaxe, sword, etc.)
                    "obtained_at"       -- When first obtained
                },
                optional = {
                    "durability",       -- Current durability
                    "max_durability",   -- Maximum durability
                    "level",            -- Tool level/tier
                    "enchantments",     -- Tool enchantments/modifiers
                    "nickname"          -- Custom name
                }
            },
            
            validation = {
                min_durability = 0,
                max_level = 100
            }
        }
    },
    
    -- Equipped configuration
    equipped = {
        pets = {
            -- Temporary: large default while aggregate-based limit is wired up
            -- Final design: this numeric default is a floor; runtime aggregate may raise/lower
            slots = 99,                 -- Number of equipped slots (stub; see InventoryService _getMaxEquippedSlots)
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
        },
        
        tools = {
            slots = 1,                  -- Number of equipped tool slots (active pickaxe)
            display_name = "Active Tool",
            icon = "🔧",
            
            -- Slot extensions via gamepasses (optional for premium players)
            slot_extensions = {
                {
                    gamepass_id = 987654321,  -- TODO: Replace with actual gamepass ID
                    additional_slots = 1,
                    name = "2nd Tool Slot"
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
    },
    
    -- UI Display Categories Configuration
    -- These define what tabs appear in the inventory UI and what folders they show
    display_categories = {
        {
            name = "All",
            icon = "📦",
            description = "All items across all categories",
            folders = {"pets", "consumables", "tools", "eggs", "resources"}, -- All enabled buckets
            display_order = 1,
            always_visible = true  -- Show even if no items
        },
        {
            name = "Pets",
            icon = "🐾", 
            description = "Your collected pets and companions",
            folders = {"pets"},
            display_order = 2,
            always_visible = true
        },
        {
            name = "Items",
            icon = "⚡",
            description = "Consumable items and potions",
            folders = {"consumables"},  -- Could be ["consumables", "potions"] if you had separate folders
            display_order = 3,
            always_visible = false  -- Hide if no items
        },
        {
            name = "Eggs",
            icon = "🥚",
            description = "Eggs ready to hatch",
            folders = {"eggs"},
            display_order = 4,
            always_visible = false
        },
        {
            name = "Tools",
            icon = "🔧",
            description = "Tools and equipment",
            folders = {"tools", "weapons"},  -- Group tools and weapons together
            display_order = 5,
            always_visible = false
        },
        {
            name = "Resources",
            icon = "🪨",
            description = "Collected materials and resources",
            folders = {"resources"},
            display_order = 6,
            always_visible = false
        }
    },
    
    -- Category display settings
    category_settings = {
        max_visible_categories = 8,     -- Don't overwhelm the UI
        hide_empty_categories = true,   -- Hide categories with 0 items (unless always_visible)
        show_item_counts = true,        -- Show "X items" next to category names
        compact_mode = false,           -- Use smaller category tabs
        
        -- Category icons can fallback to bucket icons if not specified
        use_bucket_icons_fallback = true,
        
        -- Custom category colors (optional)
        category_colors = {
            All = Color3.fromRGB(100, 100, 100),     -- Gray
            Pets = Color3.fromRGB(255, 182, 193),    -- Pink
            Items = Color3.fromRGB(135, 206, 250),   -- Light Blue
            Eggs = Color3.fromRGB(255, 255, 224),    -- Light Yellow
            Tools = Color3.fromRGB(210, 180, 140),   -- Tan
            Resources = Color3.fromRGB(160, 82, 45)  -- Brown
        }
    }
}