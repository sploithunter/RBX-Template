-- Unit tests for ConfigLoader
return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ConfigLoader = require(ReplicatedStorage.Shared.ConfigLoader)
    
    describe("ConfigLoader", function()
        it("should load game config", function()
            local config = ConfigLoader:LoadConfig("game")
            expect(config).to.be.a("table")
            expect(config.GameMode).to.be.a("string")
            expect(config.MaxPlayers).to.be.a("number")
        end)
        
        it("should load currencies config", function()
            local currencies = ConfigLoader:LoadConfig("currencies")
            expect(currencies).to.be.a("table")
            expect(#currencies).to.be.greaterThan(0)
            
            local firstCurrency = currencies[1]
            expect(firstCurrency.id).to.be.a("string")
            expect(firstCurrency.name).to.be.a("string")
        end)
        
        it("should load items config", function()
            local items = ConfigLoader:LoadConfig("items")
            expect(items).to.be.a("table")
            expect(#items).to.be.greaterThan(0)
            
            local firstItem = items[1]
            expect(firstItem.id).to.be.a("string")
            expect(firstItem.name).to.be.a("string")
            expect(firstItem.type).to.be.a("string")
        end)
        
        it("should get specific items by ID", function()
            local sword = ConfigLoader:GetItem("wooden_sword")
            expect(sword).to.be.a("table")
            expect(sword.id).to.equal("wooden_sword")
            expect(sword.type).to.equal("weapon")
        end)
        
        it("should return nil for invalid item ID", function()
            local invalid = ConfigLoader:GetItem("invalid_item")
            expect(invalid).to.equal(nil)
        end)
        
        it("should get specific currencies by ID", function()
            local coins = ConfigLoader:GetCurrency("coins")
            expect(coins).to.be.a("table")
            expect(coins.id).to.equal("coins")
            expect(coins.name).to.equal("Coins")
        end)
        
        it("should detect development environment in Studio", function()
            local env = ConfigLoader:GetEnvironment()
            expect(env).to.equal("development")
            expect(ConfigLoader:IsDevelopment()).to.equal(true)
            expect(ConfigLoader:IsProduction()).to.equal(false)
        end)
        
        it("should throw error for invalid config", function()
            expect(function()
                ConfigLoader:LoadConfig("invalid_config")
            end).to.throw()
        end)
    end)
end 