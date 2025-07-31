-- cleanup_orphaned_buckets.lua
-- DANGEROUS: This script deletes orphaned inventory buckets
-- Use with EXTREME caution - data cannot be recovered once deleted
-- Only run in Studio with full backup

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Import necessary services
local Locations = require(ReplicatedStorage.Shared.Locations)
local DataService = require(Locations.Services.DataService)
local ConfigLoader = require(Locations.Services.ConfigLoader)

print("🚨 ORPHANED BUCKET CLEANUP TOOL")
print("================================")
print("⚠️  WARNING: This permanently deletes inventory data!")
print("⚠️  Only run in Studio with backup!")
print("⚠️  Check logs carefully before confirming!")

-- Configuration
local DRY_RUN = true  -- Set to false to actually delete
local TARGET_PLAYER_NAME = "coloradoplays"  -- Change this to target player

-- Find target player
local targetPlayer = nil
for _, player in pairs(Players:GetPlayers()) do
    if player.Name == TARGET_PLAYER_NAME then
        targetPlayer = player
        break
    end
end

if not targetPlayer then
    error("❌ Player '" .. TARGET_PLAYER_NAME .. "' not found!")
end

-- Load current inventory config
local inventoryConfig = ConfigLoader:LoadConfig("inventory")
if not inventoryConfig then
    error("❌ Could not load inventory configuration!")
end

-- Get player profile
if not DataService:IsDataLoaded(targetPlayer) then
    error("❌ Player data not loaded!")
end

local profile = DataService:GetProfile(targetPlayer)
if not profile or not profile.Data then
    error("❌ Could not access player profile!")
end

local inventoryData = profile.Data.Inventory
if not inventoryData then
    print("ℹ️  No inventory data found")
    return
end

print("\n📋 INVENTORY ANALYSIS")
print("====================")

-- Identify orphaned buckets
local orphanedBuckets = {}
local validBuckets = {}

for bucketName, bucketData in pairs(inventoryData) do
    local isEnabled = inventoryConfig.enabled_buckets and inventoryConfig.enabled_buckets[bucketName]
    
    if isEnabled then
        table.insert(validBuckets, bucketName)
        print("✅ VALID BUCKET: " .. bucketName)
    else
        table.insert(orphanedBuckets, bucketName)
        print("❌ ORPHANED BUCKET: " .. bucketName .. " (items: " .. (#bucketData.items or "unknown") .. ")")
        
        -- Show items in orphaned bucket
        if bucketData.items then
            for i, item in pairs(bucketData.items) do
                print("   📦 Item " .. i .. ": " .. (item.id or "unknown"))
            end
        end
    end
end

print("\n📊 SUMMARY")
print("==========")
print("✅ Valid buckets: " .. #validBuckets)
print("❌ Orphaned buckets: " .. #orphanedBuckets)

if #orphanedBuckets == 0 then
    print("🎉 No orphaned buckets found!")
    return
end

print("\n🚨 ORPHANED BUCKETS TO DELETE:")
for _, bucketName in ipairs(orphanedBuckets) do
    print("   - " .. bucketName)
end

if DRY_RUN then
    print("\n🛡️  DRY RUN MODE - No changes made")
    print("📝 To actually delete these buckets:")
    print("   1. Set DRY_RUN = false")
    print("   2. Make sure you have a backup")
    print("   3. Run the script again")
    return
end

-- ACTUAL DELETION (only if DRY_RUN = false)
print("\n💥 STARTING DELETION...")
print("⚠️  This action cannot be undone!")

wait(3)  -- Give time to cancel

for _, bucketName in ipairs(orphanedBuckets) do
    print("🗑️  Deleting bucket: " .. bucketName)
    inventoryData[bucketName] = nil
end

print("✅ Deletion complete!")
print("🔄 Saving profile...")

-- The profile will auto-save, but we can force it
pcall(function()
    profile:Save()
end)

print("💾 Profile saved!")
print("🎉 Cleanup complete - restart server to see changes")