--[[
    EconomyService - Handles all economy-related operations
    
    Features:
    - Secure currency transactions
    - Item purchasing with validation
    - Transaction history and logging
    - Economy balancing and analytics
    - Gift/reward systems
    
    Usage:
    EconomyService:PurchaseItem(player, "wooden_sword")
    EconomyService:GiftCurrency(player, "coins", 100, "daily_reward")
    EconomyService:CanAffordItem(player, "iron_sword")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Libraries = ReplicatedStorage.Shared.Libraries
local Signal = require(Libraries.Signal)

local EconomyService = {}
EconomyService.__index = EconomyService

function EconomyService:Init()
    -- Get dependencies with validation
    self._logger = self._modules.Logger
    self._dataService = self._modules.DataService
    self._networkConfig = self._modules.NetworkConfig
    self._configLoader = self._modules.ConfigLoader
    self._playerEffectsService = self._modules.PlayerEffectsService
    self._globalEffectsService = self._modules.GlobalEffectsService
    self._adminService = self._modules.AdminService
    self._inventoryService = self._modules.InventoryService
    -- Backward-compatibility alias so existing effect code can reuse old variable names
    self._rateLimitService = self._playerEffectsService
    
    -- Validate critical dependencies
    if not self._logger then
        error("EconomyService: Logger dependency missing - check ModuleLoader configuration")
    end
    
    if not self._dataService then
        self._logger:Error("CRITICAL: DataService dependency missing")
        error("EconomyService: DataService dependency missing - check ModuleLoader configuration")
    end
    
    if not self._networkConfig then
        self._logger:Error("CRITICAL: NetworkConfig dependency missing")
        error("EconomyService: NetworkConfig dependency missing - check ModuleLoader configuration")
    end
    
    if not self._configLoader then
        self._logger:Error("CRITICAL: ConfigLoader dependency missing")
        error("EconomyService: ConfigLoader dependency missing - check ModuleLoader configuration")
    end
    
    -- RateLimitService is optional for backward compatibility, but warn if missing
    if not self._rateLimitService then
        self._logger:Error("CRITICAL: RateLimitService dependency missing - rate limiting features disabled", {
            suggestion = "Check ModuleLoader configuration and RateLimitService loading"
        })
        -- Don't error, but make it very visible that this is wrong
    else
        self._logger:Info("EconomyService: RateLimitService dependency loaded successfully")
    end
    
    -- Validate InventoryService dependency
    if not self._inventoryService then
        self._logger:Error("CRITICAL: InventoryService dependency missing")
        error("EconomyService: InventoryService dependency missing - check ModuleLoader configuration")
    else
        self._logger:Info("EconomyService: InventoryService dependency loaded successfully")
    end
    
    -- Create signals for economy events
    self.CurrencyChanged = Signal.new()
    self.ItemPurchased = Signal.new()
    self.TransactionCompleted = Signal.new()
    
    -- Transaction history
    self.TransactionHistory = {}
    
    -- Set up networking
    self:_setupNetworking()
    -- Set up Net signals
    self:_setupNetSignals()
    
    -- Set up monetization
    self:_setupMonetization()
    
    self._logger:Info("EconomyService initialized")
end

function EconomyService:_setupNetworking()
    -- legacy bridge setup kept for backwards compatibility
    self._signals = require(game:GetService("ReplicatedStorage").Shared.Network.Signals)
    self._economyBridge = {Fire = function() end}
end

-- New Net signal setup using sleitnick/Net
function EconomyService:_setupNetSignals()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Signals = require(ReplicatedStorage.Shared.Network.Signals)
    self._signals = Signals

    -- Purchase item from client
    Signals.PurchaseItem.OnServerEvent:Connect(function(player, data)
        local ok, msg = self:PurchaseItem(player, data)
        -- return result to client
        Signals.PurchaseResult:FireClient(player, {success = ok, message = msg})
    end)

    -- Adjust currency (+/-)
    Signals.AdjustCurrency.OnServerEvent:Connect(function(player, data)
        if type(data) ~= "table" then return end
        if data.reset then
            -- Reset all currencies for player
            local currencies = self._dataService:GetCurrencies(player)
            for curr, value in pairs(currencies) do
                if value > 0 then
                    self:RemoveCurrency(player, curr, value, "admin_reset")
                end
            end
            return
        end
        local currency = data.currency
        local amount = data.amount
        if not currency or not amount then return end
        if amount >= 0 then
            self:AddCurrency(player, currency, amount, "admin_adjust")
        else
            self:RemoveCurrency(player, currency, -amount, "admin_adjust")
        end
    end)
end

-- legacy networking code moved to _setupLegacyBridge
--[[ LEGACY ECONOMY BRIDGE kept for backward compatibility
    -- Get the auto-configured Economy bridge from NetworkConfig
    self._economyBridge = self._networkConfig:GetBridge("Economy")
    
    if not self._economyBridge then
        self._logger:Error("Economy bridge not found - check network.lua configuration")
        return
    end
    
    self._logger:Debug("Economy networking ready", {bridge = "Economy"})
--]]
-- End of DebugExpose legacy block

function EconomyService:_setupMonetization()
    -- Handle developer product purchases
    MarketplaceService.ProcessReceipt = function(receiptInfo)
        return self:ProcessDeveloperProductPurchase(receiptInfo)
    end
    
    -- Handle game pass purchases
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
        if wasPurchased then
            self:ProcessGamePassPurchase(player, gamePassId)
        end
    end)
end

-- Currency Management
function EconomyService:GetCurrency(player, currencyType)
    return self._dataService:GetCurrency(player, currencyType)
end

function EconomyService:AddCurrency(player, currencyType, amount, reason)
    if not self._dataService:IsDataLoaded(player) then
        return false
    end
    
    local oldAmount = self:GetCurrency(player, currencyType)
    local success = self._dataService:AddCurrency(player, currencyType, amount)
    
    if success then
        local newAmount = self:GetCurrency(player, currencyType)
        
        -- Log transaction
        self:_logTransaction(player, {
            type = "currency_add",
            currency = currencyType,
            amount = amount,
            reason = reason or "unknown",
            timestamp = os.time()
        })
        
        -- Fire events
        self.CurrencyChanged:Fire(player, currencyType, newAmount, oldAmount)
        
        -- Sync to client
        require(game:GetService("ReplicatedStorage").Shared.Network.Signals).CurrencyUpdate:FireClient(player, {
            currency = currencyType,
            amount = newAmount,
            change = amount
        })
        
        self._logger:Debug("Currency added", {
            player = player.Name,
            currency = currencyType,
            amount = amount,
            newTotal = newAmount,
            reason = reason
        })
        
        return true
    end
    
    return false
end

function EconomyService:RemoveCurrency(player, currencyType, amount, reason)
    self._logger:Debug("RemoveCurrency called", {player = player.Name, currencyType = currencyType, amount = amount, reason = reason})
    
    if not self._dataService:CanAfford(player, currencyType, amount) then
        self._logger:Debug("CanAfford check failed", {currencyType = currencyType, amount = amount})
        return false
    end
    
    self._logger:Debug("CanAfford check passed, getting old amount")
    local oldAmount = self:GetCurrency(player, currencyType)
    self._logger:Debug("Old amount retrieved", {oldAmount = oldAmount})
    
    self._logger:Debug("Calling DataService:RemoveCurrency")
    local success = self._dataService:RemoveCurrency(player, currencyType, amount)
    self._logger:Debug("DataService:RemoveCurrency returned", {success = success})
    
    if success then
        local newAmount = self:GetCurrency(player, currencyType)
        
        -- Log transaction
        self:_logTransaction(player, {
            type = "currency_remove",
            currency = currencyType,
            amount = amount,
            reason = reason or "unknown",
            timestamp = os.time()
        })
        
        -- Fire events (with error handling)
        local signalSuccess, signalError = pcall(function()
            self.CurrencyChanged:Fire(player, currencyType, newAmount, oldAmount)
        end)
        
        if not signalSuccess then
            self._logger:Error("Error firing CurrencyChanged signal", {error = signalError})
        end
        
        -- Sync to client (with error handling)
        local bridgeSuccess, bridgeError = pcall(function()
            require(game:GetService("ReplicatedStorage").Shared.Network.Signals).CurrencyUpdate:FireClient(player, {
                currency = currencyType,
                amount = newAmount,
                change = -amount
            })
        end)
        
        if not bridgeSuccess then
            self._logger:Error("Error firing CurrencyUpdate", {error = bridgeError})
        end
        
        return true
    end
    
    return false
end

function EconomyService:CanAfford(player, currencyType, amount)
    return self._dataService:CanAfford(player, currencyType, amount)
end

-- Use an item from inventory (for consumables with effects)
function EconomyService:UseItem(player, data)
    local itemId = data.itemId
    if not itemId then
        self:_sendError(player, "No item specified")
        return false
    end
    
    if not self._dataService:IsDataLoaded(player) then
        self:_sendError(player, "Data not loaded")
        return false
    end
    
    -- Check if player has the item
    if not self._dataService:HasItem(player, itemId, 1) then
        self:_sendError(player, "Item not found in inventory")
        return false
    end
    
    -- Get item configuration
    local itemConfig = self._configLoader:GetItem(itemId)
    if not itemConfig then
        self:_sendError(player, "Item configuration not found")
        return false
    end
    
    -- Check if item is consumable
    if not itemConfig.consumable then
        self:_sendError(player, "Item is not consumable")
        return false
    end
    
    -- Remove item from inventory
    if not self._dataService:RemoveFromInventory(player, itemId, 1) then
        self:_sendError(player, "Failed to consume item")
        return false
    end
    
    -- Apply item effects
    if itemConfig.effects then
        if itemConfig.effects.rate_effect then
            self:_applyItemEffect(player, itemConfig)
        elseif itemConfig.effects.global_effect then
            self:_applyGlobalEffect(player, itemConfig)
        elseif itemConfig.effects.special_effect then
            self:_applySpecialEffect(player, itemConfig)
        end
    end
    
    self._logger:Info("Item used", {
        player = player.Name,
        itemId = itemId,
        effects = itemConfig.effects
    })
    
    return true
end

-- Item Management
function EconomyService:PurchaseItem(player, data)
    -- Extract itemId from data
    local itemId = data.itemId
    if not itemId then
        self:_sendError(player, "No item specified")
        return false
    end
    
    if not self._dataService:IsDataLoaded(player) then
        self:_sendError(player, "Data not loaded")
        return false
    end
    
    -- Get item configuration
    local itemConfig = self._configLoader:GetItem(itemId)
    if not itemConfig then
        self:_sendError(player, "Item not found")
        return false
    end
    
    -- Check if player can afford it
    local price = itemConfig.price
    
    if not self:CanAfford(player, price.currency, price.amount) then
        self:_sendError(player, "Insufficient funds")
        return false
    end
    
    -- Check level requirement
    if itemConfig.level_requirement then
        local playerLevel = self._dataService:GetStat(player, "Level") or 1
        if playerLevel < itemConfig.level_requirement then
            self:_sendError(player, "Level requirement not met")
            return false
        end
    end
    
    -- Remove currency
    local currencySuccess = self:RemoveCurrency(player, price.currency, price.amount, "item_purchase")
    
    if not currencySuccess then
        self:_sendError(player, "Purchase failed")
        return false
    end
    
    -- Add item to inventory using new InventoryService
    self._logger:Info("💰 PURCHASE - Adding item to new inventory system", {
        player = player.Name,
        itemId = itemId,
        itemConfig = itemConfig
    })
    
    -- Determine which bucket this item belongs to based on configuration
    local bucketName = self:_determineItemBucket(itemConfig)
    if not bucketName then
        self._logger:Error("💰 PURCHASE - Could not determine bucket for item", {
            itemId = itemId,
            itemConfig = itemConfig
        })
        -- Refund 
        self:AddCurrency(player, price.currency, price.amount, "purchase_refund_no_bucket")
        self:_sendError(player, "Item configuration error")
        return false
    end
    
    -- Create item data for inventory
    local itemData = {
        id = itemId,
        obtained_at = os.time()
    }
    
    -- Add quantity for stackable items
    if itemConfig.stackable then
        itemData.quantity = 1
    end
    
    -- Add any additional properties from the item config
    if itemConfig.level then
        itemData.level = itemConfig.level
    end
    if itemConfig.rarity then
        itemData.rarity = itemConfig.rarity
    end
    
    local inventoryCallSuccess, inventoryResult = pcall(function()
        return self._inventoryService:AddItem(player, bucketName, itemData)
    end)
    
    if not inventoryCallSuccess then
        self._logger:Error("💰 PURCHASE - Error during inventory addition", {
            error = inventoryResult, 
            itemId = itemId,
            bucketName = bucketName,
            player = player.Name
        })
        -- Refund if inventory add failed due to error
        self:AddCurrency(player, price.currency, price.amount, "purchase_refund_error")
        self:_sendError(player, "Inventory error")
        return false
    end
    
    if not inventoryResult then
        self._logger:Warn("💰 PURCHASE - Inventory addition failed (no space)", {
            itemId = itemId,
            bucketName = bucketName,
            player = player.Name
        })
        -- Refund if inventory add failed
        self:AddCurrency(player, price.currency, price.amount, "purchase_refund")
        self:_sendError(player, "Inventory full")
        return false
    end
    
    self._logger:Info("💰 PURCHASE - Item successfully added to inventory", {
        player = player.Name,
        itemId = itemId,
        uid = inventoryResult,
        bucketName = bucketName
    })
    
    -- Log transaction
    self:_logTransaction(player, {
        type = "item_purchase",
        itemId = itemId,
        price = price,
        timestamp = os.time()
    })
    
    -- Fire events (with error handling)
    local itemPurchasedResult, itemPurchasedError = pcall(function()
        self.ItemPurchased:Fire(player, itemId, price)
    end)
    
    if not itemPurchasedResult then
        self._logger:Error("Error firing ItemPurchased signal", {error = itemPurchasedError, itemId = itemId})
    end
    
    -- Send success to client (with error handling)
    local purchaseSuccessResult, purchaseSuccessError = pcall(function()
        self._economyBridge:Fire(player, "PurchaseSuccess", {
            itemId = itemId,
            price = price
        })
    end)
    
    if not purchaseSuccessResult then
        self._logger:Error("Error sending PurchaseSuccess", {error = purchaseSuccessError, itemId = itemId})
    end
    
    -- Check if item has rate limit effects and apply them
    if itemConfig.effects and itemConfig.effects.rate_effect and itemConfig.consumable then
        self:_applyItemEffect(player, itemConfig)
    end
    
    self._logger:Info("Item purchased", {
        player = player.Name,
        itemId = itemId,
        price = price
    })
    
    return true
end

function EconomyService:SellItem(player, data)
    self._logger:Debug("SellItem called", {player = player.Name, data = data})
    
    -- Wrap in pcall to catch any errors
    local success, result = pcall(function()
        self._logger:Debug("SellItem - checking data loaded")
        local dataLoaded = self._dataService:IsDataLoaded(player)
        self._logger:Debug("SellItem - data loaded result", {dataLoaded = dataLoaded})
        
        if not dataLoaded then
            self._logger:Debug("SellItem failed - data not loaded")
            self:_sendError(player, "Data not loaded")
            return false
        end
        
        self._logger:Debug("SellItem - data check passed")
        return true
    end)
    
    if not success then
        self._logger:Error("SellItem error in data check", {error = result, player = player.Name})
        self:_sendError(player, "Internal error during data check")
        return false
    end
    
    if not result then
        return false
    end
    
    local itemId = data.itemId
    local quantity = data.quantity or 1
    
    self._logger:Debug("SellItem processing", {itemId = itemId, quantity = quantity})
    
    -- Check current inventory first
    local inventory = self._dataService:GetInventory(player)
    self._logger:Debug("SellItem current inventory", {inventory = inventory})
    
    -- Check if player has the item
    local itemCount = self._dataService:GetItemCount(player, itemId)
    self._logger:Debug("SellItem item count check", {itemId = itemId, itemCount = itemCount, needed = quantity})
    
    local hasItem = self._dataService:HasItem(player, itemId, quantity)
    self._logger:Debug("SellItem HasItem result", {hasItem = hasItem, itemId = itemId, quantity = quantity})
    
    if not hasItem then
        self._logger:Debug("SellItem failed - item not found in inventory")
        self:_sendError(player, "Item not found in inventory")
        return false
    end
    
    -- Get item configuration
    local itemConfig = self._configLoader:GetItem(itemId)
    self._logger:Debug("SellItem item config", {itemConfig = itemConfig})
    
    if not itemConfig or not itemConfig.price then
        self._logger:Debug("SellItem failed - item cannot be sold", {itemConfig = itemConfig})
        self:_sendError(player, "Item cannot be sold")
        return false
    end
    
    -- Calculate sell price (typically 50% of buy price)
    local sellPrice = math.floor(itemConfig.price.amount * 0.5)
    local totalSellPrice = sellPrice * quantity
    
    self._logger:Debug("SellItem price calculation", {sellPrice = sellPrice, totalSellPrice = totalSellPrice})
    
    -- Remove items from inventory
    local success = self._dataService:RemoveFromInventory(player, itemId, quantity)
    self._logger:Debug("SellItem inventory removal", {success = success})
    
    if not success then
        self._logger:Debug("SellItem failed - could not remove from inventory")
        self:_sendError(player, "Failed to remove item")
        return false
    end
    
    -- Add currency
    self._logger:Debug("SellItem adding currency", {currency = itemConfig.price.currency, amount = totalSellPrice})
    self:AddCurrency(player, itemConfig.price.currency, totalSellPrice, "item_sale")
    
    -- Send success to client (with error handling)
    local sellSuccessResult, sellSuccessError = pcall(function()
        self._economyBridge:Fire(player, "SellSuccess", {
            itemId = itemId,
            quantity = quantity,
            totalPrice = totalSellPrice
        })
    end)
    
    if not sellSuccessResult then
        self._logger:Error("Error sending SellSuccess", {error = sellSuccessError, itemId = itemId})
    end
    
    self._logger:Info("Item sold", {
        player = player.Name,
        itemId = itemId,
        quantity = quantity,
        totalPrice = totalSellPrice
    })
    
    return true
end

function EconomyService:CanAffordItem(player, itemId)
    local itemConfig = self._configLoader:GetItem(itemId)
    if not itemConfig or not itemConfig.price then
        return false
    end
    
    return self:CanAfford(player, itemConfig.price.currency, itemConfig.price.amount)
end

-- Shop Management
function EconomyService:GetShopItems(player, data)
    self._logger:Debug("GetShopItems called", {player = player.Name})
    self:SendShopItems(player)
end

function EconomyService:SendShopItems(player)
    self._logger:Debug("SendShopItems called", {player = player.Name})
    
    local items = self._configLoader:LoadConfig("items")
    self._logger:Debug("SendShopItems loaded items", {itemCount = #items, items = items})
    
    local shopItems = {}
    
    for _, item in ipairs(items) do
        self._logger:Debug("SendShopItems processing item", {item = item})
        if item.price then -- Only include purchasable items
            local canAfford = self:CanAffordItem(player, item.id)
            local shopItem = {
                id = item.id,
                name = item.name,
                type = item.type,
                rarity = item.rarity,
                price = item.price,
                level_requirement = item.level_requirement,
                canAfford = canAfford
            }
            table.insert(shopItems, shopItem)
            self._logger:Debug("SendShopItems added item to shop", {shopItem = shopItem})
        else
            self._logger:Debug("SendShopItems skipping item (no price)", {item = item})
        end
    end
    
    self._logger:Debug("SendShopItems sending items", {shopItemCount = #shopItems, shopItems = shopItems})
    
    if not self._economyBridge then
        self._logger:Error("SendShopItems: No economy bridge available")
        return
    end
    
    local success, error = pcall(function()
        self._economyBridge:Fire(player, "ShopItems", {items = shopItems})
    end)
    
    if success then
        self._logger:Debug("SendShopItems completed successfully")
    else
        self._logger:Error("SendShopItems failed", {error = error})
    end
end

function EconomyService:GetPlayerDebugInfo(player, data)
    self._logger:Debug("GetPlayerDebugInfo called", {player = player.Name})
    
    local inventory = self._dataService:GetInventory(player)
    local currencies = {
        coins = self._dataService:GetCurrency(player, "coins"),
        gems = self._dataService:GetCurrency(player, "gems")
    }
    
    self._logger:Info("🔍 PLAYER DEBUG INFO", {
        player = player.Name,
        inventory = inventory,
        currencies = currencies,
        dataLoaded = self._dataService:IsDataLoaded(player)
    })
    
    -- Send to client
    self._economyBridge:Fire(player, "PlayerDebugInfo", {
        inventory = inventory,
        currencies = currencies
    })
end

function EconomyService:GiveTestItem(player, data)
    self._logger:Debug("GiveTestItem called", {player = player.Name})
    
    if not self._dataService:IsDataLoaded(player) then
        self:_sendError(player, "Data not loaded")
        return false
    end
    
    -- Give the player a test item and some coins for testing
    local success = self._dataService:AddToInventory(player, "test_item", 1)
    if success then
        self._logger:Info("Test item given", {player = player.Name})
        
        -- Also give some coins if they have 0
        local currentCoins = self._dataService:GetCurrency(player, "coins")
        if currentCoins == 0 then
            self:AddCurrency(player, "coins", 100, "test_setup")
            self._logger:Info("Test coins given", {player = player.Name})
        end
        
        self._economyBridge:Fire(player, "GiveItemSuccess", {
            itemId = "test_item",
            message = "Test item and coins given for testing!"
        })
    else
        self:_sendError(player, "Failed to give test item")
    end
end

-- Monetization
function EconomyService:ProcessDeveloperProductPurchase(receiptInfo)
    local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if not player then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Get product configuration
    local productConfig = self._configLoader:GetProduct(tostring(receiptInfo.ProductId))
    if not productConfig then
        self._logger:Warn("Unknown product purchased", {
            productId = receiptInfo.ProductId,
            player = player.Name
        })
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Grant rewards
    local success = self:_grantProductRewards(player, productConfig)
    
    if success then
        self._logger:Info("Developer product processed", {
            player = player.Name,
            productId = receiptInfo.ProductId,
            receiptId = receiptInfo.PurchaseId
        })
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

function EconomyService:ProcessGamePassPurchase(player, gamePassId)
    local passConfig = self._configLoader:GetGamePass(tostring(gamePassId))
    if not passConfig then
        self._logger:Warn("Unknown game pass purchased", {
            gamePassId = gamePassId,
            player = player.Name
        })
        return
    end
    
    -- Mark pass as owned and grant benefits
    self:_grantGamePassBenefits(player, passConfig)
    
    self._logger:Info("Game pass processed", {
        player = player.Name,
        gamePassId = gamePassId
    })
end

function EconomyService:_grantProductRewards(player, productConfig)
    local rewards = productConfig.rewards
    
    -- Grant currencies
    for currency, amount in pairs(rewards) do
        if type(amount) == "number" then
            self:AddCurrency(player, currency, amount, "robux_purchase")
        end
    end
    
    -- Grant items
    if rewards.items then
        for _, itemId in ipairs(rewards.items) do
            self._dataService:AddToInventory(player, itemId, 1)
        end
    end
    
    return true
end

function EconomyService:_grantGamePassBenefits(player, passConfig)
    -- Game pass benefits are typically handled by other systems
    -- This just logs the purchase for now
    
    self:_logTransaction(player, {
        type = "game_pass_purchase",
        passId = passConfig.id,
        benefits = passConfig.benefits,
        timestamp = os.time()
    })
end

-- Gift System
function EconomyService:GiftCurrency(player, currencyType, amount, reason)
    return self:AddCurrency(player, currencyType, amount, reason or "gift")
end

function EconomyService:GiftItem(player, itemId, quantity, reason)
    if self._dataService:AddToInventory(player, itemId, quantity or 1) then
        self:_logTransaction(player, {
            type = "item_gift",
            itemId = itemId,
            quantity = quantity or 1,
            reason = reason or "gift",
            timestamp = os.time()
        })
        return true
    end
    return false
end

-- Utility Functions
function EconomyService:_logTransaction(player, transaction)
    if not self.TransactionHistory[player] then
        self.TransactionHistory[player] = {}
    end
    
    table.insert(self.TransactionHistory[player], transaction)
    
    -- Keep only last 100 transactions per player
    local history = self.TransactionHistory[player]
    if #history > 100 then
        table.remove(history, 1)
    end
end

function EconomyService:_sendError(player, message)
    self._logger:Info("Economy error occurred", {player = player.Name, message = message})
    
    if not self._economyBridge then
        self._logger:Error("_sendError: No economy bridge available")
        return
    end
    
    local success, error = pcall(function()
        self._economyBridge:Fire(player, "EconomyError", {
            message = message,
            timestamp = tick()
        })
    end)
    
    if not success then
        self._logger:Error("Failed to send error message", {error = error, player = player.Name, message = message})
    end
end

function EconomyService:_applyItemEffect(player, itemConfig)
    if not self._rateLimitService then
        self._logger:Error("CRITICAL: Cannot apply item effects - RateLimitService not available", {
            player = player.Name,
            item = itemConfig.id,
            effect = itemConfig.effects and itemConfig.effects.rate_effect,
            solution = "Check RateLimitService loading and dependency injection"
        })
        return false
    end
    
    local effects = itemConfig.effects
    if not effects or not effects.rate_effect then
        return false
    end
    
    local duration = effects.duration or 300 -- Default 5 minutes
    if duration == -1 then
        duration = 86400 * 365 * 10 -- 10 years for "permanent" effects
    end
    
    local success = self._playerEffectsService:ApplyEffect(player, effects.rate_effect, duration)
    
    if success then
        self._logger:Info("Player effect applied", {
            player = player.Name,
            effect = effects.rate_effect,
            duration = duration,
            item = itemConfig.id
        })
    end
    
    return success
end

function EconomyService:_applyGlobalEffect(player, itemConfig)
    if not self._globalEffectsService then
        self._logger:Error("CRITICAL: Cannot apply global effects - GlobalEffectsService not available", {
            player = player.Name,
            item = itemConfig.id,
            effect = itemConfig.effects.global_effect
        })
        return false
    end
    
    local effects = itemConfig.effects
    if not effects.global_effect then
        return false
    end
    
    local duration = effects.duration or 3600 -- Default 1 hour
    local reason = effects.reason or string.format("Triggered by %s using %s", player.Name, itemConfig.name)
    
    local success = self._globalEffectsService:ApplyGlobalEffect(effects.global_effect, duration, reason)
    
    if success then
        self._logger:Info("Global effect applied", {
            player = player.Name,
            effect = effects.global_effect,
            duration = duration,
            reason = reason,
            item = itemConfig.id
        })
    end
    
    return success
end

function EconomyService:_applySpecialEffect(player, itemConfig)
    local effects = itemConfig.effects
    
    self._logger:Info("_applySpecialEffect called", {
        player = player.Name,
        item = itemConfig.id,
        specialEffect = effects.special_effect
    })
    
    if effects.special_effect == "clear_all_effects" then
        if not self._playerEffectsService then
            self._logger:Error("CRITICAL: Cannot clear player effects - PlayerEffectsService not available", {
                player = player.Name,
                item = itemConfig.id
            })
            return false
        end
        
        self._logger:Info("Calling ClearAllEffects", {
            player = player.Name,
            item = itemConfig.id
        })
        
        local effectsCleared = self._playerEffectsService:ClearAllEffects(player)
        
        self._logger:Info("Special effect applied - player effects cleared", {
            player = player.Name,
            item = itemConfig.id,
            effectsCleared = effectsCleared
        })
        
        return true
    elseif effects.special_effect == "clear_all_global_effects" then
        if not self._globalEffectsService then
            self._logger:Error("CRITICAL: Cannot clear global effects - GlobalEffectsService not available", {
                player = player.Name,
                item = itemConfig.id
            })
            return false
        end
        
        local effectsCleared = self._globalEffectsService:ClearAllGlobalEffects()
        
        self._logger:Info("Special effect applied - global effects cleared", {
            player = player.Name,
            item = itemConfig.id,
            effectsCleared = effectsCleared
        })
        
        return true
    end
    
    return false
end

function EconomyService:GetActiveEffects(player, data)
    self._logger:Debug("GetActiveEffects called", {player = player.Name})
    
    if not self._rateLimitService then
        self._logger:Error("RateLimitService not available for GetActiveEffects")
        self:_sendError(player, "Effects service unavailable")
        return
    end
    
    local activeEffects = self._rateLimitService:GetActiveEffects(player)
    
    self._logger:Debug("Sending active effects", {
        player = player.Name,
        effectCount = next(activeEffects) and #activeEffects or 0,
        effects = activeEffects
    })
    
    -- Send to client
    if self._economyBridge then
        local success, error = pcall(function()
            self._economyBridge:Fire(player, "ActiveEffects", {effects = activeEffects})
        end)
        
        if not success then
            self._logger:Error("Failed to send active effects", {error = error, player = player.Name})
        end
    end
end

-- Admin Panel Handlers
function EconomyService:AdjustCurrency(player, data)
    -- SECURITY: Validate admin authorization (supports target players)
    if not self._adminService then
        self._logger:Error("🚨 SECURITY: AdminService not available for authorization check")
        return
    end
    
    local authorized, reason, targetPlayer = self._adminService:ValidateAdminAction(player, "adjustCurrency", data, "client")
    if not authorized then
        self._logger:Warn("🚨 UNAUTHORIZED AdjustCurrency attempt blocked", {
            admin = player.Name,
            adminId = player.UserId,
            reason = reason,
            requestedCurrency = data.currency,
            requestedAmount = data.amount,
            targetUserId = data.targetPlayerId
        })
        return
    end
    
    -- Determine target player (self if no target specified)
    local target = targetPlayer or player
    
    self._logger:Info("🔧 Admin: AdjustCurrency called", {
        admin = player.Name,
        target = target.Name,
        currency = data.currency,
        amount = data.amount,
        isMultiPlayer = targetPlayer ~= nil
    })
    
    local success = self:AddCurrency(target, data.currency, data.amount, "admin_adjustment")
    
    if success then
        self._logger:Info("🔧 Admin: Currency adjusted successfully", {
            admin = player.Name,
            target = target.Name,
            currency = data.currency,
            amount = data.amount
        })
    else
        self._logger:Error("🔧 Admin: Currency adjustment failed", {
            admin = player.Name,
            target = target.Name,
            currency = data.currency,
            amount = data.amount
        })
    end
end

function EconomyService:SetCurrency(player, data)
    -- SECURITY: Validate admin authorization (supports target players)
    if not self._adminService then
        self._logger:Error("🚨 SECURITY: AdminService not available for authorization check")
        return
    end
    
    local authorized, reason, targetPlayer = self._adminService:ValidateAdminAction(player, "setCurrency", data, "client")
    if not authorized then
        self._logger:Warn("🚨 UNAUTHORIZED SetCurrency attempt blocked", {
            admin = player.Name,
            adminId = player.UserId,
            reason = reason,
            requestedCurrency = data.currency,
            requestedAmount = data.amount,
            targetUserId = data.targetPlayerId
        })
        return
    end
    
    -- Determine target player (self if no target specified)
    local target = targetPlayer or player
    
    self._logger:Info("🧪 Admin: SetCurrency called", {
        admin = player.Name,
        target = target.Name,
        currency = data.currency,
        amount = data.amount,
        isMultiPlayer = targetPlayer ~= nil
    })
    
    -- Use DataService directly to set absolute value
    local success = self._dataService:SetCurrency(target, data.currency, data.amount)
    
    if success then
        local newAmount = self:GetCurrency(target, data.currency)
        
        -- Log transaction
        self:_logTransaction(target, {
            type = "admin_set_currency",
            currency = data.currency,
            amount = data.amount,
            reason = "admin_panel",
            adminUser = player.Name,
            timestamp = os.time()
        })
        
        -- Fire events
        self.CurrencyChanged:Fire(target, data.currency, newAmount, 0)
        
        -- Sync to client
        require(game:GetService("ReplicatedStorage").Shared.Network.Signals).CurrencyUpdate:FireClient(target, {
            currency = data.currency,
            amount = newAmount,
            change = data.amount
        })
        
        self._logger:Info("🧪 Admin: Currency set successfully", {
            admin = player.Name,
            target = target.Name,
            currency = data.currency,
            amount = data.amount,
            actualValue = newAmount
        })
    else
        self._logger:Error("🧪 Admin: Currency set failed", {
            player = player.Name,
            currency = data.currency,
            amount = data.amount
        })
    end
end

function EconomyService:AdminPurchaseItem(player, data)
    self._logger:Info("🔧 Admin: AdminPurchaseItem called", {
        player = player.Name,
        itemId = data.itemId,
        cost = data.cost,
        currency = data.currency,
        fullData = data
    })
    
    -- ❌ FIXED: PurchaseItem expects (player, data) not (player, itemId)
    -- Create the proper data structure that PurchaseItem expects
    local purchaseData = {
        itemId = data.itemId
    }
    
    self._logger:Info("🔧 Admin: Calling PurchaseItem with data", {
        player = player.Name,
        purchaseData = purchaseData
    })
    
    -- Use the regular purchase flow with correct parameters
    local success = self:PurchaseItem(player, purchaseData)
    
    if success then
        self._logger:Info("🔧 Admin: Item purchase successful", {
            player = player.Name,
            itemId = data.itemId
        })
    else
        self._logger:Error("🔧 Admin: Item purchase failed", {
            player = player.Name,
            itemId = data.itemId
        })
    end
end

function EconomyService:ResetCurrencies(player, data)
    self._logger:Info("🔧 Admin: ResetCurrencies called", {player = player.Name})
    
    -- Reset to config defaults
    local currenciesConfig = self._configLoader:LoadConfig("currencies")
    
    for _, currency in ipairs(currenciesConfig) do
        local defaultAmount = currency.defaultAmount or 0
        self._dataService:SetCurrency(player, currency.id, defaultAmount)
        
        -- Sync to client
        require(game:GetService("ReplicatedStorage").Shared.Network.Signals).CurrencyUpdate:FireClient(player, {
            currency = currency.id,
            amount = defaultAmount,
            change = 0
        })
    end
    
    self._logger:Info("🔧 Admin: All currencies reset to defaults", {player = player.Name})
end

function EconomyService:GetTransactionHistory(player)
    return self.TransactionHistory[player] or {}
end

-- Helper method to determine which inventory bucket an item belongs to
function EconomyService:_determineItemBucket(itemConfig)
    -- Get inventory configuration to know what buckets are available
    local inventoryConfig = self._configLoader:LoadConfig("inventory")
    if not inventoryConfig or not inventoryConfig.enabled_buckets then
        return nil
    end
    
    -- Determine bucket based on item properties
    -- Priority order: explicit bucket, item type, fallback logic
    
    -- 1. Check if item explicitly specifies a bucket
    if itemConfig.inventory_bucket and inventoryConfig.enabled_buckets[itemConfig.inventory_bucket] then
        return itemConfig.inventory_bucket
    end
    
    -- 2. Determine by item type/category
    if itemConfig.type then
        local typeMapping = {
            consumable = "consumables",
            potion = "consumables", 
            resource = "resources",
            material = "resources",
            pet = "pets",
            weapon = "weapons",
            tool = "tools",
            cosmetic = "cosmetics"
        }
        
        local mappedBucket = typeMapping[itemConfig.type]
        if mappedBucket and inventoryConfig.enabled_buckets[mappedBucket] then
            return mappedBucket
        end
    end
    
    -- 3. Fallback based on item ID patterns
    local itemId = itemConfig.id
    if itemId then
        if itemId:find("potion") or itemId:find("boost") or itemId:find("scroll") then
            if inventoryConfig.enabled_buckets.consumables then
                return "consumables"
            end
        elseif itemId:find("wood") or itemId:find("stone") or itemId:find("iron") or itemId:find("gold") then
            if inventoryConfig.enabled_buckets.resources then
                return "resources"
            end
        elseif itemId:find("sword") or itemId:find("pickaxe") or itemId:find("weapon") then
            if inventoryConfig.enabled_buckets.weapons then
                return "weapons"
            end
        end
    end
    
    -- 4. Final fallback - use consumables if available (most items are consumable)
    if inventoryConfig.enabled_buckets.consumables then
        return "consumables"
    end
    
    -- 5. Absolute fallback - use first available bucket
    for bucketName, enabled in pairs(inventoryConfig.enabled_buckets) do
        if enabled then
            return bucketName
        end
    end
    
    return nil
end

-- Cleanup when players leave
Players.PlayerRemoving:Connect(function(player)
    if EconomyService.TransactionHistory then
        EconomyService.TransactionHistory[player] = nil
    end
end)

return EconomyService 