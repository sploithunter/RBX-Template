--[[
    InventoryService - Universal Inventory Management System
    
    Features:
    - Unique ID generation for items
    - Bucket-based storage (stackable vs unique items)
    - Folder-based replication to client
    - Type-safe operations with comprehensive validation
    - Real-time client updates via Value objects
    
    Usage:
    local uid = InventoryService:AddItem(player, "pets", petData)
    local success = InventoryService:EquipItem(player, "pets", uid, "slot_1")
    local inventory = InventoryService:GetInventory(player, "pets")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Locations = require(ReplicatedStorage.Shared.Locations)

local InventoryService = {}
InventoryService.__index = InventoryService

function InventoryService:Init()
    print("🚀 InventoryService:Init() called")
    
    -- Get injected dependencies
    self._logger = self._modules.Logger
    self._dataService = self._modules.DataService
    self._configLoader = self._modules.ConfigLoader
    
    print("📦 InventoryService dependencies injected")
    
    -- Load inventory configuration
    self._inventoryConfig = self._configLoader:LoadConfig("inventory")
    
    print("📋 InventoryService config loaded")
    
    -- Track player inventory folders for replication
    self._playerInventoryFolders = {}
    self._playerEquippedFolders = {}
    
    self._logger:Info("📦 InventoryService initializing", {
        enabledBuckets = self._inventoryConfig.enabled_buckets,
        settingsDebug = self._inventoryConfig.settings.debug_logging
    })
    
    -- Connect to player events for folder management
    Players.PlayerAdded:Connect(function(player)
        self:_onPlayerAdded(player)
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        self:_onPlayerRemoving(player)
    end)
    
    -- Setup Network Signals for inventory operations
    self:_setupNetworkSignals()
    
    self._logger:Info("✅ InventoryService initialized successfully")
end

function InventoryService:Start()
    print("🚀 InventoryService:Start() called")
    
    -- Create folders for any players already in game
    for _, player in pairs(Players:GetPlayers()) do
        if self._dataService:IsDataLoaded(player) then
            print("📂 Creating folders for existing player:", player.Name)
            self:_createInventoryFolders(player)
        end
    end
    
    self._logger:Info("🚀 InventoryService started")
    print("✅ InventoryService fully started and ready")
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- 🆔 UID GENERATION SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryService:GenerateUID(itemType)
    local timestamp = math.floor(tick())
    local randomSuffix = HttpService:GenerateGUID(false):sub(1, self._inventoryConfig.settings.uid_prefix_length)
    
    local uid = string.format("%s_%d_%s", itemType or "item", timestamp, randomSuffix)
    
    if self._inventoryConfig.settings.trace_operations then
        self._logger:Debug("🆔 UID GENERATED", {
            uid = uid,
            itemType = itemType,
            timestamp = timestamp,
            randomSuffix = randomSuffix
        })
    end
    
    return uid
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- 📦 CORE INVENTORY OPERATIONS
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryService:AddItem(player, bucketName, itemData)
    if self._inventoryConfig.settings.trace_operations then
        self._logger:Info("📦 ADD ITEM - Starting", {
            player = player.Name,
            bucket = bucketName,
            itemId = itemData.id,
            itemType = type(itemData)
        })
    end
    
    -- Validate inputs
    local isValid, errorMsg = self:_validateAddItem(player, bucketName, itemData)
    if not isValid then
        self._logger:Error("❌ ADD ITEM FAILED - Validation error", {
            player = player.Name,
            bucket = bucketName,
            error = errorMsg
        })
        return nil, errorMsg
    end
    
    -- Get player data
    local data = self._dataService:GetData(player)
    if not data or not data.Inventory or not data.Inventory[bucketName] then
        self._logger:Error("❌ ADD ITEM FAILED - Bucket not found", {
            player = player.Name,
            bucket = bucketName
        })
        return nil, "Bucket not found: " .. bucketName
    end
    
    local bucket = data.Inventory[bucketName]
    local bucketConfig = self._inventoryConfig.buckets[bucketName]
    
    -- Check if bucket has space
    if not self:HasSpace(player, bucketName, 1) then
        self._logger:Warn("⚠️ ADD ITEM FAILED - No space", {
            player = player.Name,
            bucket = bucketName,
            usedSlots = bucket.used_slots,
            totalSlots = bucket.total_slots
        })
        return nil, "No space in " .. bucketConfig.display_name
    end
    
    local uid = nil
    local success = false
    
    if bucketConfig.storage_type == "stackable" then
        uid, success = self:_addStackableItem(player, bucketName, itemData, bucket, bucketConfig)
    else
        uid, success = self:_addUniqueItem(player, bucketName, itemData, bucket, bucketConfig)
    end
    
    if success then
        -- Update folder replication
        self:_updateBucketFolders(player, bucketName)
        
        self._logger:Info("✅ ADD ITEM SUCCESS", {
            player = player.Name,
            bucket = bucketName,
            uid = uid,
            itemId = itemData.id,
            storageType = bucketConfig.storage_type
        })
        
        return uid
    else
        self._logger:Error("❌ ADD ITEM FAILED - Storage error", {
            player = player.Name,
            bucket = bucketName,
            itemId = itemData.id
        })
        return nil, "Failed to add item"
    end
end

function InventoryService:_addStackableItem(player, bucketName, itemData, bucket, bucketConfig)
    local itemId = itemData.id
    
    -- Check if item already exists in bucket
    if bucket.items[itemId] then
        -- Stack with existing item
        local existingItem = bucket.items[itemId]
        local newQuantity = existingItem.quantity + (itemData.quantity or 1)
        
        -- Check stack limit
        if newQuantity > bucketConfig.stack_size then
            self._logger:Warn("⚠️ STACKABLE ADD - Stack limit exceeded", {
                player = player.Name,
                itemId = itemId,
                currentQuantity = existingItem.quantity,
                addingQuantity = itemData.quantity or 1,
                stackLimit = bucketConfig.stack_size
            })
            return nil, false
        end
        
        existingItem.quantity = newQuantity
        
        self._logger:Debug("📦 STACKABLE ADD - Stacked with existing", {
            player = player.Name,
            itemId = itemId,
            newQuantity = newQuantity
        })
        
        return itemId, true
    else
        -- Create new stack
        bucket.items[itemId] = {
            id = itemId,
            quantity = itemData.quantity or 1,
            obtained_at = os.time()
        }
        
        -- Copy any optional properties
        for _, optionalField in ipairs(bucketConfig.item_schema.optional or {}) do
            if itemData[optionalField] then
                bucket.items[itemId][optionalField] = itemData[optionalField]
            end
        end
        
        bucket.used_slots = bucket.used_slots + 1
        
        self._logger:Debug("📦 STACKABLE ADD - Created new stack", {
            player = player.Name,
            itemId = itemId,
            quantity = itemData.quantity or 1,
            newUsedSlots = bucket.used_slots
        })
        
        return itemId, true
    end
end

function InventoryService:_addUniqueItem(player, bucketName, itemData, bucket, bucketConfig)
    local uid = self:GenerateUID(itemData.id or "item")
    
    -- Create unique item entry
    bucket.items[uid] = {
        id = itemData.id,
        obtained_at = os.time()
    }
    
    -- Copy all provided data
    for key, value in pairs(itemData) do
        if key ~= "id" then  -- id already set
            bucket.items[uid][key] = value
        end
    end
    
    -- Apply defaults for missing optional fields
    local defaults = self._inventoryConfig.defaults[bucketName] or {}
    for _, optionalField in ipairs(bucketConfig.item_schema.optional or {}) do
        if bucket.items[uid][optionalField] == nil and defaults[optionalField] ~= nil then
            bucket.items[uid][optionalField] = defaults[optionalField]
        end
    end
    
    bucket.used_slots = bucket.used_slots + 1
    
    self._logger:Debug("📦 UNIQUE ADD - Created unique item", {
        player = player.Name,
        uid = uid,
        itemId = itemData.id,
        newUsedSlots = bucket.used_slots
    })
    
    return uid, true
end

function InventoryService:RemoveItem(player, bucketName, uid, quantity)
    if self._inventoryConfig.settings.trace_operations then
        self._logger:Info("📦 REMOVE ITEM - Starting", {
            player = player.Name,
            bucket = bucketName,
            uid = uid,
            quantity = quantity
        })
    end
    
    -- Get player data and bucket
    local data = self._dataService:GetData(player)
    if not data or not data.Inventory or not data.Inventory[bucketName] then
        return false, "Bucket not found"
    end
    
    local bucket = data.Inventory[bucketName]
    local bucketConfig = self._inventoryConfig.buckets[bucketName]
    
    if not bucket.items[uid] then
        self._logger:Warn("⚠️ REMOVE ITEM - Item not found", {
            player = player.Name,
            bucket = bucketName,
            uid = uid
        })
        return false, "Item not found"
    end
    
    local item = bucket.items[uid]
    local success = false
    
    if bucketConfig.storage_type == "stackable" then
        success = self:_removeStackableItem(player, bucketName, uid, quantity or 1, bucket, item)
    else
        success = self:_removeUniqueItem(player, bucketName, uid, bucket)
    end
    
    if success then
        -- Update folder replication
        self:_updateBucketFolders(player, bucketName)
        
        self._logger:Info("✅ REMOVE ITEM SUCCESS", {
            player = player.Name,
            bucket = bucketName,
            uid = uid,
            storageType = bucketConfig.storage_type
        })
    end
    
    return success
end

function InventoryService:_removeStackableItem(player, bucketName, uid, quantity, bucket, item)
    if item.quantity <= quantity then
        -- Remove entire stack
        bucket.items[uid] = nil
        bucket.used_slots = bucket.used_slots - 1
        
        self._logger:Debug("📦 STACKABLE REMOVE - Removed entire stack", {
            player = player.Name,
            uid = uid,
            removedQuantity = item.quantity,
            newUsedSlots = bucket.used_slots
        })
    else
        -- Reduce stack
        item.quantity = item.quantity - quantity
        
        self._logger:Debug("📦 STACKABLE REMOVE - Reduced stack", {
            player = player.Name,
            uid = uid,
            removedQuantity = quantity,
            remainingQuantity = item.quantity
        })
    end
    
    return true
end

function InventoryService:_removeUniqueItem(player, bucketName, uid, bucket)
    bucket.items[uid] = nil
    bucket.used_slots = bucket.used_slots - 1
    
    self._logger:Debug("📦 UNIQUE REMOVE - Removed unique item", {
        player = player.Name,
        uid = uid,
        newUsedSlots = bucket.used_slots
    })
    
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- 📂 FOLDER-BASED REPLICATION SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryService:_onPlayerAdded(player)
    -- Wait for DataService to load player profile
    task.spawn(function()
        local maxWait = 10  -- seconds
        local waited = 0
        
        while not self._dataService:IsDataLoaded(player) and waited < maxWait do
            task.wait(0.1)
            waited = waited + 0.1
        end
        
        if self._dataService:IsDataLoaded(player) then
            self:_createInventoryFolders(player)
        else
            self._logger:Warn("⚠️ REPLICATION - Player data not loaded in time", {
                player = player.Name,
                waitedSeconds = waited
            })
        end
    end)
end

function InventoryService:_onPlayerRemoving(player)
    -- Cleanup folder references
    self._playerInventoryFolders[player] = nil
    self._playerEquippedFolders[player] = nil
    
    self._logger:Debug("🧹 REPLICATION - Cleaned up folder references", {
        player = player.Name
    })
end

function InventoryService:_createInventoryFolders(player)
    self._logger:Info("📂 REPLICATION - Creating inventory folders", {
        player = player.Name
    })
    
    local data = self._dataService:GetData(player)
    if not data or not data.Inventory then
        self._logger:Error("❌ REPLICATION - No inventory data found", {
            player = player.Name
        })
        return
    end
    
    -- Create main Inventory folder
    local inventoryFolder = Instance.new("Folder")
    inventoryFolder.Name = "Inventory"
    inventoryFolder.Parent = player
    
    -- Create main Equipped folder  
    local equippedFolder = Instance.new("Folder")
    equippedFolder.Name = "Equipped"
    equippedFolder.Parent = player
    
    -- Store references
    self._playerInventoryFolders[player] = inventoryFolder
    self._playerEquippedFolders[player] = equippedFolder
    
    -- Create bucket folders
    for bucketName, bucket in pairs(data.Inventory) do
        if type(bucket) == "table" and bucket.total_slots then
            self:_createBucketFolder(player, bucketName, inventoryFolder)
        end
    end
    
    -- Create equipped folders
    for category, slots in pairs(data.Equipped or {}) do
        self:_createEquippedFolder(player, category, equippedFolder)
    end
    
    self._logger:Info("✅ REPLICATION - Inventory folders created successfully", {
        player = player.Name,
        inventoryBuckets = self:_getBucketNames(data.Inventory),
        equippedCategories = self:_getBucketNames(data.Equipped or {})
    })
end

function InventoryService:_createBucketFolder(player, bucketName, parentFolder)
    local data = self._dataService:GetData(player)
    local bucket = data.Inventory[bucketName]
    local bucketConfig = self._inventoryConfig.buckets[bucketName]
    
    -- Create bucket folder
    local bucketFolder = Instance.new("Folder")
    bucketFolder.Name = bucketName
    bucketFolder.Parent = parentFolder
    
    -- Create info subfolder with slot information
    local infoFolder = Instance.new("Folder")
    infoFolder.Name = "Info"
    infoFolder.Parent = bucketFolder
    
    local slotsUsed = Instance.new("IntValue")
    slotsUsed.Name = "SlotsUsed"
    slotsUsed.Value = bucket.used_slots or 0
    slotsUsed.Parent = infoFolder
    
    local slotsTotal = Instance.new("IntValue")
    slotsTotal.Name = "SlotsTotal"
    slotsTotal.Value = bucket.total_slots or 0
    slotsTotal.Parent = infoFolder
    
    local storageType = Instance.new("StringValue")
    storageType.Name = "StorageType"
    storageType.Value = bucketConfig and bucketConfig.storage_type or "unique"
    storageType.Parent = infoFolder
    
    -- Create item folders
    for uid, itemData in pairs(bucket.items or {}) do
        self:_createItemFolder(bucketFolder, uid, itemData, bucketConfig)
    end
    
    self._logger:Debug("📂 REPLICATION - Created bucket folder", {
        player = player.Name,
        bucket = bucketName,
        usedSlots = bucket.used_slots,
        totalSlots = bucket.total_slots,
        itemCount = self:_countItems(bucket.items or {})
    })
end

function InventoryService:_createItemFolder(parentFolder, uid, itemData, bucketConfig)
    local itemFolder = Instance.new("Folder")
    itemFolder.Name = uid
    itemFolder.Parent = parentFolder
    
    -- Add basic item information
    local itemId = Instance.new("StringValue")
    itemId.Name = "ItemId"
    itemId.Value = itemData.id or "unknown"
    itemId.Parent = itemFolder
    
    local obtainedAt = Instance.new("NumberValue")
    obtainedAt.Name = "ObtainedAt"
    obtainedAt.Value = itemData.obtained_at or 0
    obtainedAt.Parent = itemFolder
    
    -- Add storage-type specific data
    if bucketConfig and bucketConfig.storage_type == "stackable" then
        local quantity = Instance.new("IntValue")
        quantity.Name = "Quantity"
        quantity.Value = itemData.quantity or 1
        quantity.Parent = itemFolder
    else
        -- Unique item properties
        for key, value in pairs(itemData) do
            if key ~= "id" and key ~= "obtained_at" then
                local valueObj = self:_createValueObject(key, value)
                if valueObj then
                    valueObj.Parent = itemFolder
                end
            end
        end
    end
end

function InventoryService:_createEquippedFolder(player, category, parentFolder)
    local data = self._dataService:GetData(player)
    local slots = data.Equipped[category]
    local configured = self._inventoryConfig.equipped[category]
    local configuredSlots = (configured and type(configured.slots) == "number") and configured.slots or nil
    
    local categoryFolder = Instance.new("Folder")
    categoryFolder.Name = category
    categoryFolder.Parent = parentFolder
    
    local createdCount = 0
    if configuredSlots then
        local maxSlots = self:_getMaxEquippedSlots(player, category, configuredSlots)
        for i = 1, maxSlots do
            local slotName = "slot_" .. i
            local itemUid = slots and slots[slotName] or nil
            local slotValue = Instance.new("StringValue")
            slotValue.Name = slotName
            slotValue.Value = itemUid or ""
            slotValue.Parent = categoryFolder
            createdCount = createdCount + 1
        end
    else
        -- Fallback: create only declared keys
        for slotName, itemUid in pairs(slots or {}) do
            local slotValue = Instance.new("StringValue")
            slotValue.Name = slotName
            slotValue.Value = itemUid or ""
            slotValue.Parent = categoryFolder
            createdCount = createdCount + 1
        end
    end
    
    self._logger:Debug("⚔️ REPLICATION - Created equipped folder", {
        player = player.Name,
        category = category,
        slots = createdCount
    })
end

function InventoryService:_updateBucketFolders(player, bucketName)
    local inventoryFolder = self._playerInventoryFolders[player]
    if not inventoryFolder then
        self._logger:Warn("⚠️ REPLICATION - No inventory folder found for update", {
            player = player.Name,
            bucket = bucketName
        })
        return
    end
    
    local bucketFolder = inventoryFolder:FindFirstChild(bucketName)
    if not bucketFolder then
        self._logger:Warn("⚠️ REPLICATION - No bucket folder found for update", {
            player = player.Name,
            bucket = bucketName
        })
        return
    end
    
    -- Update slot counts
    local data = self._dataService:GetData(player)
    local bucket = data.Inventory[bucketName]
    
    local infoFolder = bucketFolder:FindFirstChild("Info")
    if infoFolder then
        local slotsUsed = infoFolder:FindFirstChild("SlotsUsed")
        if slotsUsed then
            slotsUsed.Value = bucket.used_slots or 0
        end
    end
    
    -- Remove old item folders
    for _, child in pairs(bucketFolder:GetChildren()) do
        if child.Name ~= "Info" then
            child:Destroy()
        end
    end
    
    -- Recreate item folders
    local bucketConfig = self._inventoryConfig.buckets[bucketName]
    for uid, itemData in pairs(bucket.items or {}) do
        self:_createItemFolder(bucketFolder, uid, itemData, bucketConfig)
    end
    
    if self._inventoryConfig.settings.trace_operations then
        self._logger:Debug("🔄 REPLICATION - Updated bucket folder", {
            player = player.Name,
            bucket = bucketName,
            usedSlots = bucket.used_slots,
            itemCount = self:_countItems(bucket.items or {})
        })
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- 🔍 QUERY OPERATIONS
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryService:GetInventory(player, bucketName)
    local data = self._dataService:GetData(player)
    if not data or not data.Inventory then
        return nil
    end
    
    if bucketName then
        return data.Inventory[bucketName]
    else
        return data.Inventory
    end
end

function InventoryService:GetItem(player, bucketName, uid)
    local bucket = self:GetInventory(player, bucketName)
    if not bucket or not bucket.items then
        return nil
    end
    
    return bucket.items[uid]
end

function InventoryService:HasSpace(player, bucketName, amount)
    amount = amount or 1
    
    local bucket = self:GetInventory(player, bucketName)
    if not bucket then
        return false
    end
    
    local availableSlots = bucket.total_slots - bucket.used_slots
    return availableSlots >= amount
end

function InventoryService:GetUsedSlots(player, bucketName)
    local bucket = self:GetInventory(player, bucketName)
    return bucket and bucket.used_slots or 0
end

function InventoryService:GetTotalSlots(player, bucketName)
    local bucket = self:GetInventory(player, bucketName)
    return bucket and bucket.total_slots or 0
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- 🛡️ VALIDATION HELPERS
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryService:_validateAddItem(player, bucketName, itemData)
    if not player or not player.Parent then
        return false, "Invalid player"
    end
    
    if not bucketName or type(bucketName) ~= "string" then
        return false, "Invalid bucket name"
    end
    
    if not self._inventoryConfig.enabled_buckets[bucketName] then
        return false, "Bucket not enabled: " .. bucketName
    end
    
    if not itemData or type(itemData) ~= "table" then
        return false, "Invalid item data"
    end
    
    if not itemData.id or type(itemData.id) ~= "string" then
        return false, "Item missing required 'id' field"
    end
    
    local bucketConfig = self._inventoryConfig.buckets[bucketName]
    if not bucketConfig then
        return false, "Bucket configuration not found: " .. bucketName
    end
    
    -- Validate required fields
    for _, requiredField in ipairs(bucketConfig.item_schema.required or {}) do
        if requiredField ~= "obtained_at" and not itemData[requiredField] then
            return false, "Item missing required field: " .. requiredField
        end
    end
    
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- 🔧 UTILITY HELPERS
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryService:_createValueObject(name, value)
    local valueType = type(value)
    local valueObj = nil
    
    if valueType == "string" then
        valueObj = Instance.new("StringValue")
        valueObj.Value = value
    elseif valueType == "number" then
        if math.floor(value) == value then
            valueObj = Instance.new("IntValue")
        else
            valueObj = Instance.new("NumberValue")
        end
        valueObj.Value = value
    elseif valueType == "boolean" then
        valueObj = Instance.new("BoolValue")
        valueObj.Value = value
    elseif valueType == "table" then
        -- For complex data like stats or enchantments, create a folder
        valueObj = Instance.new("Folder")
        for key, subValue in pairs(value) do
            local subObj = self:_createValueObject(key, subValue)
            if subObj then
                subObj.Parent = valueObj
            end
        end
    end
    
    if valueObj then
        valueObj.Name = name
    end
    
    return valueObj
end

function InventoryService:_getBucketNames(buckets)
    local names = {}
    for name in pairs(buckets) do
        table.insert(names, name)
    end
    return names
end

function InventoryService:_countItems(items)
    local count = 0
    for _ in pairs(items) do
        count = count + 1
    end
    return count
end

-- Determine maximum equipped slots for a category.
-- Stub: returns 99 for pets; defaults to configured count for others.
function InventoryService:_getMaxEquippedSlots(player, category, configuredSlots)
    if category == "pets" then
        -- Future: compute from Player/Aggregates (e.g., base + gamepasses + effects)
        return 99
    end
    return configuredSlots or 1
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- 🌐 NETWORK SIGNAL HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryService:_setupNetworkSignals()
    local Signals = require(ReplicatedStorage.Shared.Network.Signals)
    
    -- Player deletes item from their inventory
    Signals.DeleteInventoryItem.OnServerEvent:Connect(function(player, data)
        self:_handleDeleteInventoryItem(player, data)
    end)
    
    -- Admin cleanup commands
    Signals.CleanupInventory.OnServerEvent:Connect(function(player, data)
        print("🛠️ SERVER RECEIVED: CleanupInventory from", player.Name)
        print("🔍 CLEANUP DATA:", data)
        self._logger:Warn("🚨 ADMIN CLEANUP TRIGGERED", {
            admin = player.Name,
            data = data,
            stackTrace = debug.traceback("Admin cleanup call stack:")
        })
        self:_handleCleanupInventory(player, data)
    end)
    
    Signals.FixItemCategories.OnServerEvent:Connect(function(player, data)
        print("🛠️ SERVER RECEIVED: FixItemCategories from", player.Name)
        self:_handleFixItemCategories(player, data)
    end)
    
    Signals.CleanOrphanedBuckets.OnServerEvent:Connect(function(player, data)
        print("🛠️ SERVER RECEIVED: CleanOrphanedBuckets from", player.Name)
        self:_handleCleanOrphanedBuckets(player, data)
    end)
    
    -- Pet equipping
    Signals.TogglePetEquipped.OnServerEvent:Connect(function(player, data)
        self:_handleTogglePetEquipped(player, data)
    end)
    
    -- Tool equipping
    Signals.ToggleToolEquipped.OnServerEvent:Connect(function(player, data)
        self:_handleToggleToolEquipped(player, data)
    end)
    
    self._logger:Info("📡 Inventory Network Signals connected")
end

function InventoryService:_handleDeleteInventoryItem(player, data)
    self._logger:Info("🗑️ DELETE ITEM REQUEST", {
        player = player.Name,
        bucket = data.bucket,
        itemUid = data.itemUid,
        itemId = data.itemId,
        quantity = data.quantity or 1,
        reason = data.reason
    })
    
    -- Validate player is deleting their own item (security check)
    if not player or not data.bucket or not data.itemUid then
        self._logger:Warn("❌ Invalid delete request", {
            player = player and player.Name or "nil",
            data = data
        })
        return
    end
    
    -- Get player's profile
    local profile = self._dataService:GetProfile(player)
    if not profile then
        self._logger:Warn("❌ No profile found for player", {player = player.Name})
        return
    end
    
    -- Check if item exists in the specified bucket
    local inventoryData = profile.Data.Inventory or {}
    local bucketData = inventoryData[data.bucket]
    if not bucketData or not bucketData.items then
        self._logger:Warn("❌ Bucket not found", {bucket = data.bucket})
        return
    end
    
    local item = bucketData.items[data.itemUid]
    if not item then
        self._logger:Warn("❌ Item not found", {itemUid = data.itemUid, bucket = data.bucket})
        return
    end
    
    local deleteQuantity = data.quantity or 1
    local currentQuantity = item.quantity or 1
    
    if deleteQuantity >= currentQuantity then
        -- Delete entire item
        bucketData.items[data.itemUid] = nil
        bucketData.used_slots = math.max(0, (bucketData.used_slots or 0) - 1)
        
        self._logger:Info("✅ Item completely deleted", {
            player = player.Name,
            itemId = data.itemId,
            itemUid = data.itemUid,
            bucket = data.bucket,
            deletedQuantity = currentQuantity,
            newUsedSlots = bucketData.used_slots
        })
    else
        -- Reduce quantity
        item.quantity = currentQuantity - deleteQuantity
        
        self._logger:Info("✅ Item quantity reduced", {
            player = player.Name,
            itemId = data.itemId,
            itemUid = data.itemUid,
            bucket = data.bucket,
            deletedQuantity = deleteQuantity,
            remainingQuantity = item.quantity
        })
    end
    
    -- Update replication folders immediately
    self:_updateBucketFolders(player, data.bucket)
end

function InventoryService:_handleCleanupInventory(player, data)
    self._logger:Info("🧹 ADMIN CLEANUP REQUEST", {
        admin = player.Name,
        targetPlayerId = data.targetPlayerId,
        action = data.action
    })
    
    -- Validate admin permissions (you may want to add AdminService check here)
    local targetPlayer = Players:GetPlayerByUserId(data.targetPlayerId)
    if not targetPlayer then
        self._logger:Warn("❌ Target player not found", {targetPlayerId = data.targetPlayerId})
        return
    end
    
    -- Get target player's profile
    local profile = self._dataService:GetProfile(targetPlayer)
    if not profile then
        self._logger:Warn("❌ No profile found for target player", {player = targetPlayer.Name})
        return
    end
    
    -- Use the unified orphaned bucket removal logic
    self:_removeOrphanedBuckets(player, data)
end

-- Helper function to count items in a table
function InventoryService:_countTableItems(items)
    local count = 0
    for _ in pairs(items or {}) do
        count = count + 1
    end
    return count
end

function InventoryService:_handleFixItemCategories(player, data)
    self._logger:Info("🔧 ADMIN FIX CATEGORIES REQUEST", {
        admin = player.Name,
        targetPlayerId = data.targetPlayerId,
        action = data.action
    })
    
    -- Validate admin permissions
    local targetPlayer = Players:GetPlayerByUserId(data.targetPlayerId)
    if not targetPlayer then
        self._logger:Warn("❌ Target player not found", {targetPlayerId = data.targetPlayerId})
        return
    end
    
    -- Get target player's profile  
    local profile = self._dataService:GetProfile(targetPlayer)
    if not profile then
        self._logger:Warn("❌ No profile found for target player", {player = targetPlayer.Name})
        return
    end
    
    -- This would implement item migration logic
    -- For now, just log that it was called
    self._logger:Info("✅ Category fix completed", {
        admin = player.Name,
        targetPlayer = targetPlayer.Name,
        note = "Migration logic would go here"
    })
end

function InventoryService:_handleCleanOrphanedBuckets(player, data)
    self._logger:Info("🗑️ ADMIN CLEAN ORPHANED BUCKETS REQUEST", {
        admin = player.Name,
        targetPlayerId = data.targetPlayerId,
        action = data.action
    })
    
    -- Use the same logic as the safe cleanup - remove buckets not in config
    self:_removeOrphanedBuckets(player, data)
end

-- Unified orphaned bucket removal logic
function InventoryService:_removeOrphanedBuckets(player, data)
    -- Validate admin permissions
    local targetPlayer = Players:GetPlayerByUserId(data.targetPlayerId)
    if not targetPlayer then
        self._logger:Warn("❌ Target player not found", {targetPlayerId = data.targetPlayerId})
        return
    end
    
    -- Get target player's profile  
    local profile = self._dataService:GetProfile(targetPlayer)
    if not profile then
        self._logger:Warn("❌ No profile found for target player", {player = targetPlayer.Name})
        return
    end
    
    if not profile.Data or not profile.Data.Inventory then
        self._logger:Info("✅ No inventory data to clean", {player = targetPlayer.Name})
        return
    end
    
    -- Get list of buckets that SHOULD exist (from configuration)
    local validBuckets = {}
    for _, bucketConfig in ipairs(self._inventoryConfig.enabled_buckets or {}) do
        validBuckets[bucketConfig.name] = true
    end
    
    self._logger:Info("📋 VALID BUCKETS FROM CONFIG", {
        validBuckets = validBuckets,
        configuredCount = #(self._inventoryConfig.enabled_buckets or {})
    })
    
    local cleaned = {}
    local bucketsCleaned = 0
    local itemsCleaned = 0
    
    -- Remove everything that is NOT supposed to be there
    for bucketName, bucketData in pairs(profile.Data.Inventory) do
        if not validBuckets[bucketName] then
            -- This bucket shouldn't exist - remove it
            local itemCount = 0
            if type(bucketData) == "table" and bucketData.items then
                itemCount = self:_countTableItems(bucketData.items)
            end
            
            self._logger:Info("🗑️ REMOVING INVALID BUCKET", {
                bucketName = bucketName,
                itemCount = itemCount,
                targetPlayer = targetPlayer.Name,
                reason = "Not in enabled_buckets configuration"
            })
            
            profile.Data.Inventory[bucketName] = nil
            table.insert(cleaned, bucketName .. " (" .. itemCount .. " items)")
            bucketsCleaned = bucketsCleaned + 1
            itemsCleaned = itemsCleaned + itemCount
        end
    end
    
    if bucketsCleaned > 0 then
        -- Recreate all inventory folders to reflect the cleanup
        -- First, destroy existing folders
        if self._playerInventoryFolders[targetPlayer] then
            self._playerInventoryFolders[targetPlayer]:Destroy()
        end
        if self._playerEquippedFolders[targetPlayer] then
            self._playerEquippedFolders[targetPlayer]:Destroy()
        end
        
        -- Clear references and recreate
        self._playerInventoryFolders[targetPlayer] = nil
        self._playerEquippedFolders[targetPlayer] = nil
        self:_createInventoryFolders(targetPlayer)
        
        self._logger:Info("✅ Orphaned buckets cleaned", {
            admin = player.Name,
            targetPlayer = targetPlayer.Name,
            bucketsRemoved = bucketsCleaned,
            itemsRemoved = itemsCleaned,
            cleanedBuckets = cleaned
        })
    else
        self._logger:Info("✅ No orphaned buckets found to clean", {
            admin = player.Name,
            targetPlayer = targetPlayer.Name
        })
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- 🎽 EQUIPMENT HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryService:_handleTogglePetEquipped(player, data)
    self._logger:Info("🐾 PET EQUIP REQUEST", {
        player = player.Name,
        bucket = data.bucket,
        itemUid = data.itemUid,
        itemId = data.itemId,
        action = data.action or "toggle"
    })
    
    -- Validate request
    if not data.bucket or not data.itemUid or data.bucket ~= "pets" then
        self._logger:Warn("❌ Invalid pet equip request", {
            player = player.Name,
            bucket = data.bucket,
            itemUid = data.itemUid
        })
        return
    end
    
    -- Get player data
    local playerData = self._dataService:GetData(player)
    if not playerData or not playerData.Inventory or not playerData.Inventory.pets then
        self._logger:Warn("❌ No pet inventory found", {player = player.Name})
        return
    end
    
    -- Verify pet exists in inventory
    local pet = playerData.Inventory.pets.items[data.itemUid]
    if not pet then
        self._logger:Warn("❌ Pet not found in inventory", {
            player = player.Name,
            itemUid = data.itemUid
        })
        return
    end
    
    -- Initialize equipped pets if needed
    if not playerData.Equipped then
        playerData.Equipped = {}
    end
    if not playerData.Equipped.pets then
        playerData.Equipped.pets = {}
    end
    
    local success, result = self:_togglePetEquipment(player, data.itemUid, pet, playerData)
    
    if success then
        -- Update equipped folder replication
        self:_updateEquippedFolders(player, "pets")
        
        self._logger:Info("✅ Pet equipped successfully", {
            player = player.Name,
            petId = pet.id,
            petUid = data.itemUid,
            slot = result.slot,
            action = result.action
        })
    end
end

function InventoryService:_handleToggleToolEquipped(player, data)
    self._logger:Info("🔧 TOOL EQUIP REQUEST", {
        player = player.Name,
        bucket = data.bucket,
        itemUid = data.itemUid,
        itemId = data.itemId,
        action = data.action or "toggle"
    })
    
    -- Validate request
    if not data.bucket or not data.itemUid or data.bucket ~= "tools" then
        self._logger:Warn("❌ Invalid tool equip request", {
            player = player.Name,
            bucket = data.bucket,
            itemUid = data.itemUid
        })
        return
    end
    
    -- Get player data
    local playerData = self._dataService:GetData(player)
    if not playerData or not playerData.Inventory or not playerData.Inventory.tools then
        self._logger:Warn("❌ No tool inventory found", {player = player.Name})
        return
    end
    
    -- Verify tool exists in inventory
    local tool = playerData.Inventory.tools.items[data.itemUid]
    if not tool then
        self._logger:Warn("❌ Tool not found in inventory", {
            player = player.Name,
            itemUid = data.itemUid
        })
        return
    end
    
    -- Initialize equipped tools if needed
    if not playerData.Equipped then
        playerData.Equipped = {}
    end
    if not playerData.Equipped.tools then
        playerData.Equipped.tools = {}
    end
    
    local success, result = self:_toggleToolEquipment(player, data.itemUid, tool, playerData)
    
    if success then
        -- Update equipped folder replication
        self:_updateEquippedFolders(player, "tools")
        
        self._logger:Info("✅ Tool equipped successfully", {
            player = player.Name,
            toolId = tool.id,
            toolUid = data.itemUid,
            slot = result.slot,
            action = result.action
        })
    end
end

function InventoryService:_togglePetEquipment(player, petUid, pet, playerData)
    local equippedPets = playerData.Equipped.pets
    local petSlots = self._inventoryConfig.equipped.pets

    -- Compute max slots via aggregate stub (returns 99 for now)
    local maxSlots = self:_getMaxEquippedSlots(player, "pets", petSlots.slots)
    
    -- Check if pet is already equipped
    local currentSlot = nil
    for slotName, equippedUid in pairs(equippedPets) do
        if equippedUid == petUid then
            currentSlot = slotName
            break
        end
    end
    
    if currentSlot then
        -- Unequip the pet
        equippedPets[currentSlot] = nil
        return true, {action = "unequipped", slot = currentSlot}
    else
        -- Find an empty slot to equip the pet (respect runtime maxSlots)
        for i = 1, maxSlots do
            local slotName = "slot_" .. i
            if not equippedPets[slotName] then
                equippedPets[slotName] = petUid
                return true, {action = "equipped", slot = slotName}
            end
        end
        
        -- No empty slots - replace the first slot
        equippedPets["slot_1"] = petUid
        return true, {action = "equipped", slot = "slot_1", replaced = true}
    end
end

function InventoryService:_toggleToolEquipment(player, toolUid, tool, playerData)
    local equippedTools = playerData.Equipped.tools
    local toolSlots = self._inventoryConfig.equipped.tools
    
    -- Check if tool is already equipped
    local currentSlot = nil
    for slotName, equippedUid in pairs(equippedTools) do
        if equippedUid == toolUid then
            currentSlot = slotName
            break
        end
    end
    
    if currentSlot then
        -- Unequip the tool
        equippedTools[currentSlot] = nil
        return true, {action = "unequipped", slot = currentSlot}
    else
        -- Find an empty slot to equip the tool
        for i = 1, toolSlots.slots do
            local slotName = "slot_" .. i
            if not equippedTools[slotName] then
                equippedTools[slotName] = toolUid
                return true, {action = "equipped", slot = slotName}
            end
        end
        
        -- No empty slots - replace the first slot
        equippedTools["slot_1"] = toolUid
        return true, {action = "equipped", slot = "slot_1", replaced = true}
    end
end

function InventoryService:_updateEquippedFolders(player, category)
    local equippedFolder = self._playerEquippedFolders[player]
    if not equippedFolder then
        self._logger:Warn("⚠️ No equipped folder found for update", {
            player = player.Name,
            category = category
        })
        return
    end
    
    local categoryFolder = equippedFolder:FindFirstChild(category)
    if not categoryFolder then
        -- Create category folder if it doesn't exist
        categoryFolder = Instance.new("Folder")
        categoryFolder.Name = category
        categoryFolder.Parent = equippedFolder
    end
    
    -- Incrementally update slot values up to runtime max slots
    local playerData = self._dataService:GetData(player)
    local slots = playerData.Equipped[category] or {}
    local configured = self._inventoryConfig.equipped[category]
    local configuredSlots = (configured and type(configured.slots) == "number") and configured.slots or 0
    local maxSlots = self:_getMaxEquippedSlots(player, category, configuredSlots)

    local createdCount = 0
    local updatedCount = 0
    for i = 1, maxSlots do
        local slotName = "slot_" .. i
        local desiredValue = slots[slotName] or ""
        local slotValue = categoryFolder:FindFirstChild(slotName)
        if not slotValue then
            slotValue = Instance.new("StringValue")
            slotValue.Name = slotName
            slotValue.Value = desiredValue
            slotValue.Parent = categoryFolder
            createdCount = createdCount + 1
        else
            if slotValue.Value ~= desiredValue then
                slotValue.Value = desiredValue
                updatedCount = updatedCount + 1
            end
        end
    end
    
    self._logger:Debug("⚔️ Updated equipped folder", {
        player = player.Name,
        category = category,
        createdSlots = createdCount,
        updatedSlots = updatedCount,
        maxSlots = maxSlots
    })
end

return InventoryService