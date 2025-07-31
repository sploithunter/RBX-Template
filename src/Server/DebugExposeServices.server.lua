-- Debug Service Exposer - Temporary script to expose services to _G for console testing

local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("🔍 DEBUG: Waiting for server initialization to complete...")

-- Wait for the server's "✅ All required modules validated" message
-- This indicates the ModuleLoader and all services are ready
spawn(function()
    wait(10) -- Wait longer for server to fully initialize
    
    local attempts = 0
    local maxAttempts = 10
    
    while attempts < maxAttempts do
        attempts = attempts + 1
        print("🔍 DEBUG: Attempt", attempts, "to expose services...")
        
        local success, result = pcall(function()
            local Locations = require(ReplicatedStorage.Shared.Locations)
            local ModuleLoader = require(Locations.Libraries.ModuleLoader)
            
            -- Try to get services
            local EconomyService = ModuleLoader:Get("EconomyService")
            local InventoryService = ModuleLoader:Get("InventoryService") 
            local DataService = ModuleLoader:Get("DataService")
            
            if EconomyService and InventoryService and DataService then
                -- Expose services to _G
                _G.DEBUG_EconomyService = EconomyService
                _G.DEBUG_InventoryService = InventoryService
                _G.DEBUG_DataService = DataService
                
                print("✅ DEBUG: Services exposed to _G")
                print("  EconomyService:", _G.DEBUG_EconomyService and "✅" or "❌")
                print("  InventoryService:", _G.DEBUG_InventoryService and "✅" or "❌")
                print("  DataService:", _G.DEBUG_DataService and "✅" or "❌")
                
                return true
            else
                error("Services not ready yet")
            end
        end)
        
        if success then
            print("🎉 DEBUG: Successfully exposed services to _G!")
            break
        else
            print("⏳ DEBUG: Services not ready yet, waiting... (" .. result .. ")")
            wait(2)
        end
    end
    
    if attempts >= maxAttempts then
        print("❌ DEBUG: Failed to expose services after", maxAttempts, "attempts")
    end
end)