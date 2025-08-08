--[[
    ConfigLoader - Loads and manages game configuration from Lua files
    
    Features:
    - Lua configuration loading
    - Configuration caching and hot reloading
    - Environment-specific configs (Dev/Prod)
    - Configuration validation
    - Default fallbacks
    
    Usage:
    local ConfigLoader = require(ReplicatedStorage.Shared.ConfigLoader)
    local gameConfig = ConfigLoader:LoadConfig("game")
    local items = ConfigLoader:LoadConfig("items")
]]

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local ConfigLoader = {}
ConfigLoader.__index = ConfigLoader

-- Configuration storage
local configs = {}
local configsLoaded = false

-- Simple config parser for our Lua config files  
local function parseConfig(content)
    local result = {}
    local currentSection = result
    local stack = {}
    
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub("^%s*", ""):gsub("%s*$", "") -- trim
        
        if line:sub(1, 1) == "#" or line == "" then
            -- Skip comments and empty lines
        elseif line:match(":$") then
            -- Section header (e.g., "bridges:")
            local key = line:sub(1, -2)
            currentSection[key] = {}
            table.insert(stack, currentSection)
            currentSection = currentSection[key]
        elseif line:match("^%s*%w+:%s*") then
            -- Key-value pair (e.g., "rateLimit: 30")
            local key, value = line:match("^%s*(%w+):%s*(.*)$")
            if value == "true" then value = true
            elseif value == "false" then value = false
            elseif tonumber(value) then value = tonumber(value)
            elseif value:match('^".*"$') then value = value:sub(2, -2) -- remove quotes
            end
            currentSection[key] = value
        end
    end
    
    return result
end

-- Load configs from ReplicatedStorage
local function loadConfigsFromStorage()
    if configsLoaded then return end
    
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local configsFolder = ReplicatedStorage:FindFirstChild("Configs")
    
    if not configsFolder then
        warn("Configs folder not found in ReplicatedStorage - using hardcoded defaults")
        -- Hardcoded fallback configurations
        configs = {
    game = {
        GameMode = "Simulator", -- Options: Simulator, FPS, TowerDefense, Custom
        MaxPlayers = 20,
        EnableTrading = true,
        EnablePvP = false,
        RespawnTime = 5,
        StartingCurrency = {
            coins = 100,
            gems = 0
        },
        WorldSettings = {
            Gravity = 196.2,
            WalkSpeed = 16,
            JumpPower = 50
        }
    },
    
    currencies = {
        {
            id = "coins",
            name = "Coins",
            icon = "💰",
            maxAmount = 1000000000,
            defaultAmount = 100,
            canPurchase = false
        },
        {
            id = "gems",
            name = "Gems", 
            icon = "💎",
            maxAmount = 100000,
            defaultAmount = 0,
            canPurchase = true,
            premium = true
        }
    },
    
    items = {
        {
            id = "test_item",
            name = "Test Item",
            type = "consumable",
            rarity = "common",
            description = "A simple test item for debugging purchases",
            price = {
                currency = "coins",
                amount = 50
            },
            level_requirement = 1,
            stackable = true,
            max_stack = 99
        },
        {
            id = "wooden_sword",
            name = "Wooden Sword",
            type = "weapon",
            rarity = "common",
            stats = {
                damage = 10,
                speed = 1.5,
                range = 5
            },
            price = {
                currency = "coins",
                amount = 100
            },
            level_requirement = 1
        },
        {
            id = "iron_sword",
            name = "Iron Sword", 
            type = "weapon",
            rarity = "uncommon",
            stats = {
                damage = 20,
                speed = 1.3,
                range = 5
            },
            price = {
                currency = "coins",
                amount = 500
            },
            level_requirement = 5
        },
        {
            id = "health_potion",
            name = "Health Potion",
            type = "consumable",
            rarity = "common",
            effects = {
                health_restore = 50
            },
            price = {
                currency = "coins",
                amount = 25
            },
            stackable = true,
            max_stack = 10
        }
    },
    
    enemies = {
        {
            id = "goblin",
            name = "Goblin",
            type = "melee",
            level = 1,
            stats = {
                health = 50,
                damage = 8,
                speed = 12,
                detection_range = 20,
                attack_range = 3
            },
            rewards = {
                experience = 10,
                currency = {
                    coins = {min = 5, max = 15}
                }
            },
            spawn_weight = 10
        },
        {
            id = "orc",
            name = "Orc Warrior",
            type = "melee", 
            level = 5,
            stats = {
                health = 150,
                damage = 25,
                speed = 10,
                detection_range = 25,
                attack_range = 4
            },
            rewards = {
                experience = 50,
                currency = {
                    coins = {min = 20, max = 40}
                }
            },
            spawn_weight = 5
        }
    },
    
    ui = {
        -- Fallback UI configuration
        version = "1.0.0",
        active_theme = "dark",
        themes = {
            dark = {
                primary = {
                    background = Color3.fromRGB(30, 30, 35),
                    surface = Color3.fromRGB(40, 40, 45),
                    accent = Color3.fromRGB(0, 120, 180),
                },
                text = {
                    primary = Color3.fromRGB(255, 255, 255),
                    secondary = Color3.fromRGB(200, 200, 200),
                },
                button = {
                    primary = Color3.fromRGB(0, 120, 180),
                }
            }
        },
        fonts = {
            primary = Enum.Font.Gotham,
            sizes = { md = 14 }
        },
        spacing = { md = 16 },
        radius = { md = 8 },
        animations = {
            duration = { fast = 0.15 }
        },
        helpers = {
            get_theme = function(config)
                return config.themes[config.active_theme] or config.themes.dark
            end,
            get_spacing = function(config, key)
                local value = config.spacing[key] or config.spacing.md
                return UDim.new(0, value)
            end,
            get_radius = function(config, key)
                local value = config.radius[key] or config.radius.md
                return UDim.new(0, value)
            end,
        }
    },
    
    monetization = {
        products = {
            {
                id = "gems_100",
                name = "100 Gems",
                price_robux = 100,
                rewards = {
                    gems = 100
                }
            },
            {
                id = "gems_500", 
                name = "500 Gems",
                price_robux = 400,
                rewards = {
                    gems = 500,
                    bonus_coins = 1000
                }
            },
            {
                id = "starter_pack",
                name = "Starter Pack",
                price_robux = 200,
                rewards = {
                    gems = 150,
                    coins = 2000,
                    items = {"iron_sword", "health_potion"}
                }
            }
        },
        
        passes = {
            {
                id = "vip",
                name = "VIP Pass",
                price_robux = 500,
                benefits = {
                    daily_gems = 10,
                    experience_multiplier = 2,
                    exclusive_items = true
                }
            }
        }
    },
    
    analytics = {
        events = {
            "player_joined",
            "player_left", 
            "level_up",
            "item_purchased",
            "currency_earned",
            "enemy_defeated",
            "quest_completed"
        },
        
        retention_milestones = {
            tutorial_completed = 1,
            first_purchase = 7,
            level_10_reached = 3,
            friend_invited = 14
        }
    }
        }
        configsLoaded = true
        return
    end
    
    -- Load configs from files
    for _, child in ipairs(configsFolder:GetChildren()) do
        if child:IsA("ModuleScript") then
            local configName = child.Name
            local success, result = pcall(function()
                return require(child)
            end)
            
            if success then
                configs[configName] = result
            else
                warn("Failed to load config:", configName, result)
            end
        end
    end
    
    configsLoaded = true
end

function ConfigLoader:Init()
    -- Initialize caches
    self._monetizationCache = nil
    self._configCaches = {}
    
    if self._modules and self._modules.Logger then
        self._modules.Logger:Info("ConfigLoader initialized", {
            configCount = self:_getConfigCount()
        })
    end
end

function ConfigLoader:LoadConfig(configName)
    -- Load configs from storage if not already loaded
    loadConfigsFromStorage()
    
    if not configs[configName] then
        error(string.format("Config '%s' not found", configName))
    end
    
    -- Validate config before returning
    local config = configs[configName]
    local isValid, errorMessage = self:ValidateConfig(configName, config)
    
    if not isValid then
        error(string.format("Invalid config '%s': %s", configName, errorMessage or "Unknown validation error"))
    end
    
    return self:_deepCopy(config)
end

function ConfigLoader:GetItem(itemId)
    local items = self:LoadConfig("items")
    for _, item in ipairs(items) do
        if item.id == itemId then
            return item
        end
    end
    return nil
end

function ConfigLoader:GetEnemy(enemyId)
    local enemies = self:LoadConfig("enemies")
    for _, enemy in ipairs(enemies) do
        if enemy.id == enemyId then
            return enemy
        end
    end
    return nil
end

function ConfigLoader:GetCurrency(currencyId)
    local currencies = self:LoadConfig("currencies")
    for _, currency in ipairs(currencies) do
        if currency.id == currencyId then
            return currency
        end
    end
    return nil
end

-- Monetization-specific config methods with caching
function ConfigLoader:GetProduct(productId)
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    if not monetization or not monetization.products then
        return nil
    end
    
    for _, product in ipairs(monetization.products) do
        if product.id == productId then
            return product
        end
    end
    return nil
end

function ConfigLoader:GetGamePass(passId)
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    if not monetization or not monetization.passes then
        return nil
    end
    
    for _, pass in ipairs(monetization.passes) do
        if pass.id == passId then
            return pass
        end
    end
    return nil
end

-- Get product by Roblox product ID
function ConfigLoader:GetProductByRobloxId(robloxProductId)
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    if not monetization or not monetization.product_id_mapping then
        return nil
    end
    
    -- Find config ID that maps to this Roblox ID
    local configId = nil
    for id, productId in pairs(monetization.product_id_mapping) do
        if productId == robloxProductId then
            configId = id
            break
        end
    end
    
    if configId then
        return self:GetProduct(configId)
    end
    
    return nil
end

-- Get all monetization products
function ConfigLoader:GetAllProducts()
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    return (monetization and monetization.products) or {}
end

-- Get all game passes
function ConfigLoader:GetAllGamePasses()
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    return (monetization and monetization.passes) or {}
end

-- Get product ID mapping
function ConfigLoader:GetProductIdMapping()
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    return (monetization and monetization.product_id_mapping) or {}
end

-- Get Roblox product/pass ID from config ID
function ConfigLoader:GetRobloxId(configId)
    local mapping = self:GetProductIdMapping()
    return mapping[configId]
end

-- Get premium benefits configuration
function ConfigLoader:GetPremiumBenefits()
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    return (monetization and monetization.premium_benefits) or {}
end

-- Get first purchase bonus configuration
function ConfigLoader:GetFirstPurchaseBonus()
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    return (monetization and monetization.first_purchase_bonus) or {}
end

-- Get validation rules
function ConfigLoader:GetValidationRules()
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    return (monetization and monetization.validation_rules) or {}
end

-- Get error messages
function ConfigLoader:GetErrorMessages()
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    return (monetization and monetization.error_messages) or {}
end

-- Get analytics configuration
function ConfigLoader:GetAnalyticsConfig()
    if not self._monetizationCache then
        self._monetizationCache = self:LoadConfig("monetization")
    end
    
    local monetization = self._monetizationCache
    return (monetization and monetization.analytics) or {}
end

-- Clear monetization cache (for hot reloading)
function ConfigLoader:ClearMonetizationCache()
    self._monetizationCache = nil
end

-- Validate monetization setup and warn about placeholder IDs
function ConfigLoader:ValidateMonetizationSetup()
    local monetization = self._monetizationCache or self:LoadConfig("monetization")
    local warnings = {}
    local errors = {}
    
    -- Check for placeholder product IDs
    for configId, robloxId in pairs(monetization.product_id_mapping) do
        if robloxId == 1234567890 or robloxId == 1234567891 or robloxId == 1234567892 then
            table.insert(warnings, "Product '" .. configId .. "' still uses placeholder ID " .. robloxId)
        elseif robloxId == 123456789 or robloxId == 123456790 or robloxId == 123456791 then
            table.insert(warnings, "Game pass '" .. configId .. "' still uses placeholder ID " .. robloxId)
        end
        
        if robloxId <= 0 then
            table.insert(errors, "Invalid Roblox ID for '" .. configId .. "': " .. robloxId)
        end
    end
    
    -- Check test mode configuration
    local validation = monetization.validation_rules
    if validation and validation.test_mode and validation.test_mode.enabled then
        table.insert(warnings, "Test mode is enabled - purchases will be free in Studio")
    end
    
    return {
        isValid = #errors == 0,
        errors = errors,
        warnings = warnings,
        hasPlaceholders = #warnings > 0
    }
end

-- Get monetization setup status for debugging
function ConfigLoader:GetMonetizationStatus()
    local status = self:ValidateMonetizationSetup()
    local monetization = self._monetizationCache or self:LoadConfig("monetization")
    
    return {
        validation = status,
        productCount = #monetization.products,
        passCount = #monetization.passes,
        hasPremiumBenefits = monetization.premium_benefits.enabled,
        hasFirstPurchaseBonus = monetization.first_purchase_bonus.enabled,
        testModeEnabled = monetization.validation_rules.test_mode.enabled
    }
end

function ConfigLoader:ValidateConfig(configName, config)
    if configName == "monetization" then
        return self:_validateMonetizationConfig(config)
    elseif configName == "items" then
        return self:_validateItemsConfig(config)
    elseif configName == "currencies" then
        return self:_validateCurrenciesConfig(config)
    elseif configName == "ui" then
        return self:_validateUIConfig(config)
    elseif configName == "inventory" then
        return self:_validateInventoryConfig(config)
    elseif configName == "context_menus" then
        return self:_validateContextMenusConfig(config)
    end
    
    -- Default validation for other configs
    return true
end

function ConfigLoader:_validateMonetizationConfig(config)
    if not config then
        return false, "Monetization config is nil"
    end
    
    -- Check required sections
    local requiredSections = {"product_id_mapping", "products", "passes", "premium_benefits"}
    for _, section in ipairs(requiredSections) do
        if not config[section] then
            return false, "Missing required section: " .. section
        end
    end
    
    -- Validate products
    if type(config.products) ~= "table" then
        return false, "Products must be a table"
    end
    
    for i, product in ipairs(config.products) do
        if not product.id or type(product.id) ~= "string" then
            return false, "Product " .. i .. " missing or invalid id"
        end
        
        if not product.name or type(product.name) ~= "string" then
            return false, "Product " .. product.id .. " missing or invalid name"
        end
        
        if not product.price_robux or type(product.price_robux) ~= "number" then
            return false, "Product " .. product.id .. " missing or invalid price_robux"
        end
        
        if not product.rewards or type(product.rewards) ~= "table" then
            return false, "Product " .. product.id .. " missing or invalid rewards"
        end
        
        -- Check if product ID exists in mapping
        if not config.product_id_mapping[product.id] then
            return false, "Product " .. product.id .. " not found in product_id_mapping"
        end
    end
    
    -- Validate game passes
    if type(config.passes) ~= "table" then
        return false, "Passes must be a table"
    end
    
    for i, pass in ipairs(config.passes) do
        if not pass.id or type(pass.id) ~= "string" then
            return false, "Pass " .. i .. " missing or invalid id"
        end
        
        if not pass.name or type(pass.name) ~= "string" then
            return false, "Pass " .. pass.id .. " missing or invalid name"
        end
        
        if not pass.price_robux or type(pass.price_robux) ~= "number" then
            return false, "Pass " .. pass.id .. " missing or invalid price_robux"
        end
        
        if not pass.benefits or type(pass.benefits) ~= "table" then
            return false, "Pass " .. pass.id .. " missing or invalid benefits"
        end
        
        -- Check if pass ID exists in mapping
        if not config.product_id_mapping[pass.id] then
            return false, "Pass " .. pass.id .. " not found in product_id_mapping"
        end
    end
    
    -- Validate product ID mapping
    if type(config.product_id_mapping) ~= "table" then
        return false, "Product ID mapping must be a table"
    end
    
    for configId, robloxId in pairs(config.product_id_mapping) do
        if type(configId) ~= "string" then
            return false, "Config ID must be string: " .. tostring(configId)
        end
        
        if type(robloxId) ~= "number" then
            return false, "Roblox ID must be number for: " .. configId
        end
    end
    
    return true
end

function ConfigLoader:_validateItemsConfig(config)
    if not config or type(config) ~= "table" then
        return false, "Items config must be a table"
    end
    
    for i, item in ipairs(config) do
        if not item.id or type(item.id) ~= "string" then
            return false, "Item " .. i .. " missing or invalid id"
        end
        
        if not item.name or type(item.name) ~= "string" then
            return false, "Item " .. item.id .. " missing or invalid name"
        end
    end
    
    return true
end

function ConfigLoader:_validateCurrenciesConfig(config)
    if not config or type(config) ~= "table" then
        return false, "Currencies config must be a table"
    end
    
    for i, currency in ipairs(config) do
        if not currency.id or type(currency.id) ~= "string" then
            return false, "Currency " .. i .. " missing or invalid id"
        end
        
        if not currency.name or type(currency.name) ~= "string" then
            return false, "Currency " .. currency.id .. " missing or invalid name"
        end
    end
    
    return true
end

function ConfigLoader:_validateUIConfig(config)
    if not config or type(config) ~= "table" then
        return false, "UI config must be a table"
    end
    
    -- Check required sections
    local requiredSections = {"themes", "active_theme", "fonts", "spacing", "radius", "animations", "helpers"}
    for _, section in ipairs(requiredSections) do
        if not config[section] then
            return false, "Missing required section: " .. section
        end
    end
    
    -- Validate themes
    if not config.themes or type(config.themes) ~= "table" then
        return false, "Themes must be a table"
    end
    
    if not config.themes.dark or not config.themes.light then
        return false, "Dark and light themes are required"
    end
    
    -- Validate active theme exists
    if not config.themes[config.active_theme] then
        return false, "Active theme '" .. tostring(config.active_theme) .. "' not found in themes"
    end
    
    return true
end

function ConfigLoader:_validateContextMenusConfig(config)
    if not config or type(config) ~= "table" then
        return false, "Context menus config must be a table"
    end
    
    -- Check required sections
    if not config.global then
        return false, "Missing required section: global"
    end
    
    if not config.item_types then
        return false, "Missing required section: item_types"
    end
    
    if not config.fallback then
        return false, "Missing required section: fallback"
    end
    
    -- Validate item_types structure
    if type(config.item_types) ~= "table" then
        return false, "item_types must be a table"
    end
    
    -- Check that each item type has actions
    for itemType, typeConfig in pairs(config.item_types) do
        if not typeConfig.actions or type(typeConfig.actions) ~= "table" then
            return false, "Item type '" .. itemType .. "' must have actions table"
        end
        
        -- Validate each action
        for i, action in ipairs(typeConfig.actions) do
            if not action.action or not action.text or not action.color then
                return false, "Action " .. i .. " in item type '" .. itemType .. "' missing required fields (action, text, color)"
            end
        end
    end
    
    return true
end

function ConfigLoader:ReloadConfig(configName)
    -- Clear specific config cache
    if configName == "monetization" then
        self:ClearMonetizationCache()
    end
    
    if self._configCaches then
        self._configCaches[configName] = nil
    end
    
    if self._modules and self._modules.Logger then
        self._modules.Logger:Info("Config reloaded", {config = configName})
    end
    
    return self:LoadConfig(configName)
end

function ConfigLoader:_deepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = self:_deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function ConfigLoader:_getConfigCount()
    local count = 0
    for _ in pairs(configs) do
        count = count + 1
    end
    return count
end

-- Environment-specific config loading
function ConfigLoader:GetEnvironment()
    if RunService:IsStudio() then
        return "development"
    else
        return "production"
    end
end

function ConfigLoader:IsProduction()
    return self:GetEnvironment() == "production"
end

function ConfigLoader:IsDevelopment()
    return self:GetEnvironment() == "development"
end

function ConfigLoader:_validateInventoryConfig(config)
    if not config then
        return false, "Inventory config is nil"
    end
    
    -- Check required top-level fields
    local requiredFields = {"version", "enabled_buckets", "buckets", "settings"}
    for _, field in ipairs(requiredFields) do
        if not config[field] then
            return false, "Missing required field: " .. field
        end
    end
    
    -- Validate version
    if type(config.version) ~= "string" then
        return false, "Version must be a string"
    end
    
    -- Validate enabled_buckets
    if type(config.enabled_buckets) ~= "table" then
        return false, "enabled_buckets must be a table"
    end
    
    -- Validate buckets
    if type(config.buckets) ~= "table" then
        return false, "buckets must be a table"
    end
    
    -- Check that each enabled bucket has a corresponding bucket definition
    for bucketName, enabled in pairs(config.enabled_buckets) do
        if enabled and not config.buckets[bucketName] then
            return false, "Enabled bucket '" .. bucketName .. "' has no bucket definition"
        end
        
        if enabled then
            local bucket = config.buckets[bucketName]
            
            -- Validate required bucket fields
            local requiredBucketFields = {"display_name", "icon", "base_limit", "stack_size", "storage_type", "item_schema"}
            for _, field in ipairs(requiredBucketFields) do
                if not bucket[field] then
                    return false, "Bucket '" .. bucketName .. "' missing required field: " .. field
                end
            end
            
            -- Validate bucket field types
            if type(bucket.display_name) ~= "string" then
                return false, "Bucket '" .. bucketName .. "' display_name must be a string"
            end
            
            if type(bucket.base_limit) ~= "number" or bucket.base_limit <= 0 then
                return false, "Bucket '" .. bucketName .. "' base_limit must be a positive number"
            end
            
            if type(bucket.stack_size) ~= "number" or bucket.stack_size <= 0 then
                return false, "Bucket '" .. bucketName .. "' stack_size must be a positive number"
            end
            
            -- Validate storage_type
            if bucket.storage_type ~= "unique" and bucket.storage_type ~= "stackable" then
                return false, "Bucket '" .. bucketName .. "' storage_type must be 'unique' or 'stackable'"
            end
            
            -- Validate item schema
            if type(bucket.item_schema) ~= "table" then
                return false, "Bucket '" .. bucketName .. "' item_schema must be a table"
            end
            
            if not bucket.item_schema.required or type(bucket.item_schema.required) ~= "table" then
                return false, "Bucket '" .. bucketName .. "' item_schema must have 'required' array"
            end
            
            if not bucket.item_schema.optional or type(bucket.item_schema.optional) ~= "table" then
                return false, "Bucket '" .. bucketName .. "' item_schema must have 'optional' array"  
            end
        end
    end
    
    -- Validate equipped configuration
    if config.equipped then
        if type(config.equipped) ~= "table" then
            return false, "equipped must be a table"
        end
        
        for equipCategory, equipConfig in pairs(config.equipped) do
            if type(equipConfig) ~= "table" then
                return false, "Equipped category '" .. equipCategory .. "' must be a table"
            end
            
            if not equipConfig.slots then
                return false, "Equipped category '" .. equipCategory .. "' missing slots field"
            end
            
            if not equipConfig.display_name or type(equipConfig.display_name) ~= "string" then
                return false, "Equipped category '" .. equipCategory .. "' missing or invalid display_name"
            end
        end
    end
    
    -- Validate settings
    if type(config.settings) ~= "table" then
        return false, "settings must be a table"
    end
    
    if self._modules and self._modules.Logger then
        self._modules.Logger:Info("Inventory config validated", {context = "ConfigLoader"})
    end
    return true
end

return ConfigLoader 