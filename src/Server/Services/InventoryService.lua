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
    
    local categoryFolder = Instance.new("Folder")
    categoryFolder.Name = category
    categoryFolder.Parent = parentFolder
    
    for slotName, itemUid in pairs(slots or {}) do
        local slotValue = Instance.new("StringValue")
        slotValue.Name = slotName
        slotValue.Value = itemUid or ""
        slotValue.Parent = categoryFolder
    end
    
    self._logger:Debug("⚔️ REPLICATION - Created equipped folder", {
        player = player.Name,
        category = category,
        slots = self:_countItems(slots or {})
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

return InventoryService