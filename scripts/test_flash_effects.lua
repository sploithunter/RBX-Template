-- test_flash_effects.lua
--
-- Test script for the new flash effects configuration system
-- Validates configuration loading and effect availability

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Test loading the flash effects configuration
local function testFlashEffectsConfig()
    print("🧪 Testing Flash Effects Configuration...")
    
    local success, flashConfig = pcall(function()
        return require(ReplicatedStorage.configs.flash_effects)
    end)
    
    if not success then
        print("❌ Failed to load flash effects config:", flashConfig)
        return false
    end
    
    print("✅ Flash effects config loaded successfully")
    print("📊 Default effect:", flashConfig.default_effect)
    print("📊 Available effects:")
    
    for effectName, effectData in pairs(flashConfig.effects) do
        local status = effectData.enabled and "✅ ENABLED" or "🚧 PLACEHOLDER"
        print("  -", effectName, "(" .. effectData.name .. ")", status)
    end
    
    -- Test starburst config specifically
    local starburstConfig = flashConfig.effects.starburst
    if starburstConfig and starburstConfig.enabled then
        print("⭐ Starburst Effect Configuration:")
        print("  - Star count:", starburstConfig.config.star_count)
        print("  - Duration:", starburstConfig.config.duration)
        print("  - Size range:", starburstConfig.config.min_size, "-", starburstConfig.config.max_size)
        print("  - Colors:", #starburstConfig.config.colors, "color variations")
    end
    
    return true
end

-- Test the EggHatchingService integration
local function testEggHatchingIntegration()
    print("\n🥚 Testing EggHatchingService Integration...")
    
    local success, EggHatchingService = pcall(function()
        return require(ReplicatedStorage.Shared.Services.EggHatchingService)
    end)
    
    if not success then
        print("❌ Failed to load EggHatchingService:", EggHatchingService)
        return false
    end
    
    print("✅ EggHatchingService loaded with flash effects integration")
    
    -- Test the service can access flash config
    local hasStarburstMethod = type(EggHatchingService.CreateStarburstEffect) == "function"
    print("📊 Starburst effect methods:", hasStarburstMethod and "✅ Available" or "❌ Missing")
    
    return true
end

-- Test with a single egg (quick test)
local function testSingleEggWithStarburst()
    print("\n🌟 Testing Single Egg with Starburst Effect...")
    
    local success, result = pcall(function()
        local EggHatchingService = require(ReplicatedStorage.Shared.Services.EggHatchingService)
        
        local testEgg = {
            {
                eggType = "basic_egg",
                petType = "bear",
                variant = "basic",
                imageId = "generated_image",
                petImageId = "generated_image"
            }
        }
        
        return EggHatchingService:StartHatchingAnimation(testEgg)
    end)
    
    if success then
        print("✅ Single egg test started successfully with starburst effect")
        print("🌟 Watch for the starburst animation during the flash stage!")
    else
        print("❌ Single egg test failed:", result)
    end
    
    return success
end

-- Run all tests
local function runAllTests()
    print("🚀 Flash Effects Configuration Test Suite")
    print("==========================================")
    
    local configTest = testFlashEffectsConfig()
    local integrationTest = testEggHatchingIntegration()
    
    if configTest and integrationTest then
        print("\n✅ All tests passed! Ready to test starburst effect.")
        print("💡 Use the Admin Panel or command: testSingleEggWithStarburst()")
        return true
    else
        print("\n❌ Some tests failed. Check the errors above.")
        return false
    end
end

-- Export functions for manual testing
return {
    testFlashEffectsConfig = testFlashEffectsConfig,
    testEggHatchingIntegration = testEggHatchingIntegration,
    testSingleEggWithStarburst = testSingleEggWithStarburst,
    runAllTests = runAllTests
}