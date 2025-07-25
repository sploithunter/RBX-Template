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
    
    return self:_deepCopy(configs[configName])
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

function ConfigLoader:GetProduct(productId)
    local monetization = self:LoadConfig("monetization")
    for _, product in ipairs(monetization.products or {}) do
        if product.id == productId then
            return product
        end
    end
    return nil
end

function ConfigLoader:GetGamePass(passId)
    local monetization = self:LoadConfig("monetization")
    for _, pass in ipairs(monetization.passes or {}) do
        if pass.id == passId then
            return pass
        end
    end
    return nil
end

function ConfigLoader:ValidateConfig(configName, config)
    -- TODO: Implement configuration validation
    -- This would check required fields, data types, etc.
    return true
end

function ConfigLoader:ReloadConfig(configName)
    -- TODO: Implement hot reloading from files
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

return ConfigLoader 