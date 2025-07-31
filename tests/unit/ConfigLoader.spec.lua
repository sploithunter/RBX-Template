--[[
    ConfigLoader Test Suite
    
    Tests for configuration loading, validation, and monetization handling
]]

return function()
    
    local ConfigLoader = require(game.ReplicatedStorage.Shared.ConfigLoader)
    -- Save original loader for patches throughout this spec
    local originalLoadConfig = ConfigLoader.LoadConfig
    
    describe("ConfigLoader", function()
        local configLoader
        
        beforeEach(function()
            configLoader = setmetatable({}, ConfigLoader)
            configLoader:Init()
        end)
        
        describe("Monetization Config Methods", function()
            -- Mock monetization config
            local mockMonetizationConfig = {
                product_id_mapping = {
                    small_gems = 1234567890,
                    medium_gems = 1234567891,
                    starter_pack = 1234567892,
                    vip_pass = 123456789,
                    auto_collect = 123456790,
                    speed_boost = 123456791
                },
                products = {
                    {
                        id = "small_gems",
                        name = "100 Gems",
                        price_robux = 99,
                        rewards = {gems = 100}
                    },
                    {
                        id = "medium_gems",
                        name = "500 Gems",
                        price_robux = 399,
                        rewards = {gems = 550}
                    },
                    {
                        id = "starter_pack",
                        name = "Starter Pack",
                        price_robux = 199,
                        rewards = {
                            gems = 150,
                            coins = 25000,
                            items = {"wooden_sword"}
                        }
                    }
                },
                passes = {
                    {
                        id = "vip_pass",
                        name = "VIP Pass",
                        price_robux = 499,
                        benefits = {
                            multipliers = {xp = 2.0, coins = 1.5}
                        }
                    },
                    {
                        id = "auto_collect",
                        name = "Auto Collector",
                        price_robux = 299,
                        benefits = {
                            features = {auto_collect_enabled = true}
                        }
                    },
                    {
                        id = "speed_boost",
                        name = "Speed Boost",
                        price_robux = 199,
                        benefits = {
                            effects = {
                                id = "speed_pass",
                                permanent = true,
                                stats = {speedMultiplier = 0.5}
                            }
                        }
                    }
                },
                premium_benefits = {
                    enabled = true,
                    multipliers = {xp = 1.5, coins = 1.25}
                },
                first_purchase_bonus = {
                    enabled = true,
                    rewards = {gems = 100, coins = 50000}
                },
                validation_rules = {
                    test_mode = {enabled = true}
                },
                error_messages = {
                    product_not_found = "Product not found"
                },
                analytics = {
                    track_purchases = true
                }
            }
            
            -- Apply monkey-patch only once for the whole test run

            if not ConfigLoader.__TEST_PATCH_APPLIED then
                ConfigLoader.__TEST_PATCH_APPLIED = true
                -- duplicate patch block removed
                ConfigLoader.LoadConfig = function(self, configName)
                    if configName == "monetization" then
                        return mockMonetizationConfig
                    end
                    return originalLoadConfig(self, configName)
                end
            end
            
            it("should get product by ID", function()
                local product = configLoader:GetProduct("small_gems")
                
                expect(product).to.be.ok()
                expect(product.id).to.equal("small_gems")
                expect(product.name).to.equal("100 Gems")
                expect(product.price_robux).to.equal(99)
                expect(product.rewards.gems).to.equal(100)
            end)
            
            it("should get game pass by ID", function()
                local pass = configLoader:GetGamePass("vip_pass")
                
                expect(pass).to.be.ok()
                expect(pass.id).to.equal("vip_pass")
                expect(pass.name).to.equal("VIP Pass")
                expect(pass.price_robux).to.equal(499)
                expect(pass.benefits.multipliers.xp).to.equal(2.0)
            end)
            
            it("should get product by Roblox ID", function()
                local product = configLoader:GetProductByRobloxId(1234567890)
                
                expect(product).to.be.ok()
                expect(product.id).to.equal("small_gems")
                expect(product.name).to.equal("100 Gems")
            end)
            
            it("should return nil for unknown product", function()
                local product = configLoader:GetProduct("unknown_product")
                expect(product).to.equal(nil)
            end)
            
            it("should return nil for unknown game pass", function()
                local pass = configLoader:GetGamePass("unknown_pass")
                expect(pass).to.equal(nil)
            end)
            
            it("should get all products", function()
                local products = configLoader:GetAllProducts()
                
                expect(#products).to.equal(3)
                expect(products[1].id).to.equal("small_gems")
                expect(products[2].id).to.equal("medium_gems")
                expect(products[3].id).to.equal("starter_pack")
            end)
            
            it("should get all game passes", function()
                local passes = configLoader:GetAllGamePasses()
                
                expect(#passes).to.equal(3)
                expect(passes[1].id).to.equal("vip_pass")
                expect(passes[2].id).to.equal("auto_collect")
                expect(passes[3].id).to.equal("speed_boost")
            end)
            
            it("should get product ID mapping", function()
                local mapping = configLoader:GetProductIdMapping()
                
                expect(mapping).to.be.ok()
                expect(mapping.small_gems).to.equal(1234567890)
                expect(mapping.vip_pass).to.equal(123456789)
            end)
            
            it("should get Roblox ID from config ID", function()
                local robloxId = configLoader:GetRobloxId("small_gems")
                expect(robloxId).to.equal(1234567890)
                
                local passId = configLoader:GetRobloxId("vip_pass")
                expect(passId).to.equal(123456789)
            end)
            
            it("should get premium benefits", function()
                local benefits = configLoader:GetPremiumBenefits()
                
                expect(benefits).to.be.ok()
                expect(benefits.enabled).to.equal(true)
                expect(benefits.multipliers.xp).to.equal(1.5)
                expect(benefits.multipliers.coins).to.equal(1.25)
            end)
            
            it("should get first purchase bonus", function()
                local bonus = configLoader:GetFirstPurchaseBonus()
                
                expect(bonus).to.be.ok()
                expect(bonus.enabled).to.equal(true)
                expect(bonus.rewards.gems).to.equal(100)
                expect(bonus.rewards.coins).to.equal(50000)
            end)
            
            it("should get validation rules", function()
                local rules = configLoader:GetValidationRules()
                
                expect(rules).to.be.ok()
                expect(rules.test_mode.enabled).to.equal(true)
            end)
            
            it("should get error messages", function()
                local messages = configLoader:GetErrorMessages()
                
                expect(messages).to.be.ok()
                expect(messages.product_not_found).to.equal("Product not found")
            end)
            
            it("should get analytics config", function()
                local analytics = configLoader:GetAnalyticsConfig()
                
                expect(analytics).to.be.ok()
                expect(analytics.track_purchases).to.equal(true)
            end)
        end)
        
        describe("Configuration Validation", function()
            it("should validate valid monetization config", function()
                local validConfig = {
                    product_id_mapping = {test_product = 123456789},
                    products = {
                        {
                            id = "test_product",
                            name = "Test Product",
                            price_robux = 99,
                            rewards = {gems = 100}
                        }
                    },
                    passes = {},
                    premium_benefits = {enabled = true}
                }
                
                local isValid, error = configLoader:ValidateConfig("monetization", validConfig)
                expect(isValid).to.equal(true)
                expect(error).to.equal(nil)
            end)
            
            it("should reject monetization config with missing product_id_mapping", function()
                local invalidConfig = {
                    products = {},
                    passes = {},
                    premium_benefits = {}
                }
                
                local isValid, error = configLoader:ValidateConfig("monetization", invalidConfig)
                expect(isValid).to.equal(false)
                expect(string.find(error, "Missing required section: product_id_mapping", 1, true)).to.be.ok()
            end)
            
            it("should reject product with missing ID", function()
                local invalidConfig = {
                    product_id_mapping = {},
                    products = {
                        {
                            name = "Test Product",
                            price_robux = 99,
                            rewards = {}
                        }
                    },
                    passes = {},
                    premium_benefits = {}
                }
                
                local isValid, error = configLoader:ValidateConfig("monetization", invalidConfig)
                expect(isValid).to.equal(false)
                expect(string.find(error, "missing or invalid id", 1, true)).to.be.ok()
            end)
            
            it("should reject product not in ID mapping", function()
                local invalidConfig = {
                    product_id_mapping = {},
                    products = {
                        {
                            id = "test_product",
                            name = "Test Product",
                            price_robux = 99,
                            rewards = {}
                        }
                    },
                    passes = {},
                    premium_benefits = {}
                }
                
                local isValid, error = configLoader:ValidateConfig("monetization", invalidConfig)
                expect(isValid).to.equal(false)
                expect(string.find(error, "not found in product_id_mapping", 1, true)).to.be.ok()
            end)
        end)
        
        describe("Monetization Setup Validation", function()
            it("should detect placeholder IDs", function()
                -- Mock monetization config with placeholders
                configLoader._monetizationCache = {
                    product_id_mapping = {
                        small_gems = 1234567890,  -- Placeholder
                        vip_pass = 123456789     -- Placeholder
                    },
                    products = {},
                    passes = {},
                    premium_benefits = {},
                    validation_rules = {
                        test_mode = {enabled = true}
                    }
                }
                
                local status = configLoader:ValidateMonetizationSetup()
                
                expect(status.isValid).to.equal(true)
                expect(status.hasPlaceholders).to.equal(true)
                expect(#status.warnings).to.equal(3)  -- 2 placeholders + test mode
                expect(string.find(status.warnings[1], "placeholder ID", 1, true)).to.be.ok()
                expect(string.find(status.warnings[2], "placeholder ID", 1, true)).to.be.ok()
                expect(string.find(status.warnings[3], "Test mode is enabled", 1, true)).to.be.ok()
            end)
            
            it("should detect invalid Roblox IDs", function()
                configLoader._monetizationCache = {
                    product_id_mapping = {
                        invalid_product = -1  -- Invalid ID
                    },
                    products = {},
                    passes = {},
                    premium_benefits = {},
                    validation_rules = {
                        test_mode = {enabled = false}
                    }
                }
                
                local status = configLoader:ValidateMonetizationSetup()
                
                expect(status.isValid).to.equal(false)
                expect(#status.errors).to.equal(1)
                expect(string.find(status.errors[1], "Invalid Roblox ID", 1, true)).to.be.ok()
            end)
            
            it("should get monetization status", function()
                configLoader._monetizationCache = {
                    product_id_mapping = {},
                    products = {{}, {}},  -- 2 products
                    passes = {{}, {}, {}},  -- 3 passes
                    premium_benefits = {enabled = true},
                    first_purchase_bonus = {enabled = false},
                    validation_rules = {
                        test_mode = {enabled = true}
                    }
                }
                
                local status = configLoader:GetMonetizationStatus()
                
                expect(status.productCount).to.equal(2)
                expect(status.passCount).to.equal(3)
                expect(status.hasPremiumBenefits).to.equal(true)
                expect(status.hasFirstPurchaseBonus).to.equal(false)
                expect(status.testModeEnabled).to.equal(true)
            end)
        end)
        
        describe("Cache Management", function()
            it("should cache monetization config", function()
                -- Mock the LoadConfig to track calls
                local loadCalls = 0
                -- duplicate patch block removed
                ConfigLoader.LoadConfig = function(self, configName)
                    if configName == "monetization" then
                        loadCalls = loadCalls + 1
                        return {
                            product_id_mapping = {},
                            products = {},
                            passes = {},
                            premium_benefits = {}
                        }
                    end
                    return originalLoadConfig(self, configName)
                end
                
                -- First call should load
                configLoader:GetProduct("test")
                expect(loadCalls).to.equal(1)
                
                -- Second call should use cache
                configLoader:GetGamePass("test")
                expect(loadCalls).to.equal(1)
                
                -- Clear cache and try again
                configLoader:ClearMonetizationCache()
                configLoader:GetProduct("test")
                expect(loadCalls).to.equal(2)
            end)
        end)
    end)
end 