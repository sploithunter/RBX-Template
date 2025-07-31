-- Direct Server Access Debug Script
-- Run this in the server console to test EconomyService directly

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get the ModuleLoader
local Locations = require(ReplicatedStorage.Shared.Locations)
local ModuleLoader = require(Locations.Libraries.ModuleLoader)

-- Get services
local EconomyService = ModuleLoader:Get("EconomyService")
local InventoryService = ModuleLoader:Get("InventoryService")
local DataService = ModuleLoader:Get("DataService")

-- Test player (replace with actual player name)
local testPlayerName = "coloradoplays"  -- Change this to your username
local testPlayer = Players:FindFirstChild(testPlayerName)

if not testPlayer then
    print("❌ Player not found:", testPlayerName)
    print("Available players:", table.concat(Players:GetChildren(), ", "))
    return
end

print("🧪 DIRECT SERVER TEST - Starting")
print("📋 Testing player:", testPlayer.Name)

-- Test 1: Check if services exist
print("\n🔍 SERVICE AVAILABILITY:")
print("  EconomyService:", EconomyService and "✅ FOUND" or "❌ MISSING")
print("  InventoryService:", InventoryService and "✅ FOUND" or "❌ MISSING")
print("  DataService:", DataService and "✅ FOUND" or "❌ MISSING")

if not (EconomyService and InventoryService and DataService) then
    print("❌ Missing required services!")
    return
end

-- Test 2: Check player profile
print("\n🔍 PLAYER PROFILE:")
local profile = DataService:GetProfile(testPlayer)
if profile then
    print("  Profile found: ✅")
    print("  Coins:", profile.Data.Currencies and profile.Data.Currencies.coins or "NOT SET")
    
    -- Show inventory structure
    if profile.Data.Inventory then
        print("  Inventory buckets:")
        for bucketName, bucket in pairs(profile.Data.Inventory) do
            if type(bucket) == "table" and bucket.items then
                print("    " .. bucketName .. ": " .. #bucket.items .. " items")
            else
                print("    " .. bucketName .. ": " .. tostring(bucket) .. " (legacy format)")
            end
        end
    else
        print("  No inventory data")
    end
else
    print("  Profile: ❌ NOT FOUND")
    return
end

-- Test 3: Direct purchase test
print("\n🧪 DIRECT PURCHASE TEST:")
print("  Attempting to purchase health_potion...")

local purchaseData = {
    itemId = "health_potion"
}

print("  Purchase data:", game:GetService("HttpService"):JSONEncode(purchaseData))

-- Call EconomyService directly
local success, result = pcall(function()
    return EconomyService:PurchaseItem(testPlayer, purchaseData)
end)

print("  Purchase result:")
print("    Success:", success)
print("    Result:", result)

-- Test 4: Check inventory after purchase
print("\n🔍 INVENTORY AFTER PURCHASE:")
local newProfile = DataService:GetProfile(testPlayer)
if newProfile and newProfile.Data.Inventory then
    for bucketName, bucket in pairs(newProfile.Data.Inventory) do
        if type(bucket) == "table" and bucket.items then
            print("  " .. bucketName .. ": " .. #bucket.items .. " items")
            if #bucket.items > 0 then
                for i, item in ipairs(bucket.items) do
                    print("    [" .. i .. "]", game:GetService("HttpService"):JSONEncode(item))
                end
            end
        end
    end
end

-- Test 5: Check client-side replication
print("\n🔍 CLIENT REPLICATION CHECK:")
local inventoryFolder = testPlayer:FindFirstChild("Inventory")
if inventoryFolder then
    print("  Inventory folder: ✅ FOUND")
    for _, child in pairs(inventoryFolder:GetChildren()) do
        print("    " .. child.Name .. ":", child.ClassName)
        if child:IsA("Folder") then
            print("      Items:", #child:GetChildren())
        end
    end
else
    print("  Inventory folder: ❌ NOT FOUND")
end

print("\n🧪 DIRECT SERVER TEST - Complete")