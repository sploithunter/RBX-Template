--[[
    Debug InventoryService Loading
    
    This script checks if InventoryService is loaded and working.
    Place in ServerScriptService and run to debug.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for services
local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
local Locations = require(Shared.Locations)

print("🔍 ═══════════════════════════════════════════════════════════")
print("🔍 INVENTORY SERVICE DEBUG")
print("🔍 ═══════════════════════════════════════════════════════════")

-- Wait for services to be available
task.wait(3)

print("\n📋 Checking service availability...")

local InventoryService = Locations.getService("InventoryService")
if InventoryService then
    print("✅ InventoryService is available")
    print("  Type:", type(InventoryService))
    
    -- Check if it has expected methods
    local methods = {"AddItem", "RemoveItem", "GetInventory", "GenerateUID"}
    for _, methodName in ipairs(methods) do
        if InventoryService[methodName] then
            print(string.format("  ✅ Method %s exists", methodName))
        else
            print(string.format("  ❌ Method %s missing", methodName))
        end
    end
    
    -- Check if it has been initialized
    if InventoryService._logger then
        print("  ✅ Logger dependency injected")
    else
        print("  ❌ Logger dependency missing")
    end
    
    if InventoryService._dataService then
        print("  ✅ DataService dependency injected")
    else
        print("  ❌ DataService dependency missing")
    end
    
    if InventoryService._inventoryConfig then
        print("  ✅ Inventory config loaded")
        print("  📊 Config version:", InventoryService._inventoryConfig.version)
        print("  📊 Enabled buckets:", InventoryService._inventoryConfig.enabled_buckets)
    else
        print("  ❌ Inventory config missing")
    end
    
    -- Test UID generation
    local testUID = InventoryService:GenerateUID("test")
    if testUID then
        print("  ✅ UID generation working:", testUID)
    else
        print("  ❌ UID generation failed")
    end
    
else
    print("❌ InventoryService is NOT available")
    
    -- Check if it's in the service registry
    print("\n🔍 Checking service registry...")
    print("Available services:", Locations.Services)
    
    -- Check if the module is registered
    local DataService = Locations.getService("DataService")
    if DataService then
        print("✅ DataService is available (for comparison)")
    else
        print("❌ DataService is also not available")
    end
end

print("\n✅ DEBUG COMPLETE")

return true