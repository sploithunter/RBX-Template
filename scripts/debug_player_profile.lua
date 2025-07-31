--[[
    Debug Player Profile Script
    
    This script shows where the inventory data currently exists.
    Place this in ServerScriptService and run to see the profile structure.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for services
local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
local Locations = require(Shared.Locations)

print("🔍 ═══════════════════════════════════════════════════════════")
print("🔍 INVENTORY DATA LOCATION DEBUG")
print("🔍 ═══════════════════════════════════════════════════════════")

-- Wait for a player to be available
local function debugPlayerProfile(player)
    print(string.format("\n👤 DEBUGGING PROFILE FOR: %s", player.Name))
    
    -- Wait for DataService
    local DataService = Locations.getService("DataService")
    if not DataService then
        print("❌ DataService not available")
        return
    end
    
    -- Wait for profile to load
    task.wait(2)
    
    local profile = DataService:GetProfile(player)
    if not profile then
        print("❌ No profile found for player")
        return
    end
    
    local data = profile.Data
    
    print("\n📊 PROFILE DATA STRUCTURE:")
    print(string.format("  • Player: %s", player.Name))
    print(string.format("  • Level: %s", data.Stats and data.Stats.Level or "Unknown"))
    print(string.format("  • Coins: %s", data.Currencies and data.Currencies.coins or "Unknown"))
    
    print("\n📦 INVENTORY SECTION:")
    if data.Inventory then
        print("✅ Inventory section exists in ProfileStore")
        
        for bucketName, bucket in pairs(data.Inventory) do
            if type(bucket) == "table" and bucket.total_slots then
                -- New bucket format
                local itemCount = 0
                if bucket.items then
                    for _ in pairs(bucket.items) do
                        itemCount = itemCount + 1
                    end
                end
                
                print(string.format("  • %s: %d/%d slots, %d items", 
                    bucketName, bucket.used_slots or 0, bucket.total_slots, itemCount))
                
                -- Show actual items if any
                if bucket.items and next(bucket.items) then
                    for itemId, itemData in pairs(bucket.items) do
                        if type(itemData) == "table" then
                            print(string.format("    └─ %s: %s", itemId, itemData.id or "unknown"))
                        else
                            print(string.format("    └─ %s: %s", itemId, tostring(itemData)))
                        end
                    end
                end
            else
                -- Legacy format or simple value
                print(string.format("  • %s: %s (legacy/orphaned)", bucketName, tostring(bucket)))
            end
        end
    else
        print("❌ No Inventory section found")
    end
    
    print("\n⚔️ EQUIPPED SECTION:")
    if data.Equipped then
        print("✅ Equipped section exists in ProfileStore")
        
        for category, slots in pairs(data.Equipped) do
            print(string.format("  • %s:", category))
            if type(slots) == "table" then
                for slotName, itemUid in pairs(slots) do
                    local status = itemUid and ("equipped: " .. itemUid) or "empty"
                    print(string.format("    └─ %s: %s", slotName, status))
                end
            end
        end
    else
        print("❌ No Equipped section found")
    end
    
    print("\n📂 CLIENT-SIDE VISIBILITY:")
    print("❌ Inventory folders NOT YET CREATED")
    print("❌ Data only exists in ProfileStore (server-side)")
    print("❌ Client cannot see inventory data yet")
    
    print("\n🚀 NEXT STEPS TO MAKE DATA VISIBLE:")
    print("  1. Implement InventoryService (Phase 2)")
    print("  2. Create folder-based replication")
    print("  3. Update InventoryPanel UI to read from folders")
    print("  4. Add pet hatching integration")
    
    print(string.format("\n✅ PROFILE DEBUG COMPLETE for %s", player.Name))
end

-- Debug existing players
for _, player in pairs(Players:GetPlayers()) do
    debugPlayerProfile(player)
end

-- Debug new players
Players.PlayerAdded:Connect(debugPlayerProfile)

print("\n💡 HOW TO VERIFY:")
print("  1. This script shows ProfileStore data (server-side)")
print("  2. Check Player folders in Explorer (currently empty)")
print("  3. Inventory data exists but isn't replicated to client yet")
print("  4. Phase 2 will create the folder replication system")

return true