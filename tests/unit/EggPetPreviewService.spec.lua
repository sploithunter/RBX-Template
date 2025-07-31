--[[
    Test for EggPetPreviewService
    
    Tests the pet chance calculation logic to ensure:
    - Base egg chances are calculated correctly
    - Player modifiers (luck, level, gamepass) are applied properly
    - Results are sorted and formatted correctly
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Test setup
return function()
    local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
    
    describe("EggPetPreviewService", function()
        local EggPetPreviewService
        local mockPlayer
        
        beforeEach(function()
            -- Mock player with aggregates
            mockPlayer = {
                UserId = 12345,
                Name = "TestPlayer",
                MembershipType = Enum.MembershipType.None,
                GetAttribute = function(self, key)
                    local attributes = {
                        Level = 5,
                        PetsHatched = 10
                    }
                    return attributes[key]
                end,
                FindFirstChild = function(self, name)
                    if name == "Aggregates" then
                        return {
                            FindFirstChild = function(self, statName)
                                local stats = {
                                    luckBoost = {Value = 0.5},      -- +0.5 luck from potions
                                    rareLuckBoost = {Value = 0.2},  -- +0.2 rare luck
                                    ultraLuckBoost = {Value = 0.1}  -- +0.1 ultra luck
                                }
                                return stats[statName]
                            end
                        }
                    end
                    return nil
                end
            }
            
            -- Provide mock player for server-side tests
            _G.__TEST_LOCAL_PLAYER = mockPlayer
            
            EggPetPreviewService = require(ReplicatedStorage.Shared.Services.EggPetPreviewService)
        end)
        
        describe("GetPlayerData", function()
            it("should gather player data including aggregates", function()
                local playerData = EggPetPreviewService:GetPlayerData(mockPlayer)
                
                expect(playerData.level).to.equal(5)
                expect(playerData.petsHatched).to.equal(10)
                expect(playerData.luckBoost).to.equal(0.5)
                expect(playerData.rareLuckBoost).to.equal(0.2)
                expect(playerData.ultraLuckBoost).to.equal(0.1)
                expect(playerData.isVIP).to.equal(false)
            end)
            
            it("should detect premium players", function()
                mockPlayer.MembershipType = Enum.MembershipType.Premium
                local playerData = EggPetPreviewService:GetPlayerData(mockPlayer)
                expect(playerData.isVIP).to.equal(true)
            end)
        end)
        
        describe("CalculatePetChances", function()
            it("should calculate chances for basic_egg", function()
                local chances = EggPetPreviewService:CalculatePetChances("basic_egg")
                
                expect(chances).to.be.a("table")
                expect(#chances > 0).to.equal(true)
                
                -- Should have different pet types
                local petTypes = {}
                for _, chance in ipairs(chances) do
                    petTypes[chance.petType] = true
                    expect(chance.chance > 0).to.equal(true)
                    expect(chance.petData).to.be.ok()
                end
                
                -- Should have multiple pet types from config
                expect(petTypes.bear).to.equal(true)
                expect(petTypes.bunny).to.equal(true)
            end)
            
            it("should show only basic variants for basic eggs", function()
                local chances = EggPetPreviewService:CalculatePetChances("basic_egg")
                
                -- Should only have basic variants, no golden or rainbow
                for _, chance in ipairs(chances) do
                    expect(chance.variant).to.equal("basic")
                    -- Chance should be the raw pet type weight (no rarity calculation)
                    expect(chance.chance > 0).to.equal(true)
                end
                
                -- Check specific pet type chance (bear should be 25% = 0.25)
                local bearFound = false
                for _, chance in ipairs(chances) do
                    if chance.petType == "bear" then
                        bearFound = true
                        expect(chance.chance).to.equal(0.25) -- 25% weight from config
                        break
                    end
                end
                expect(bearFound).to.equal(true)
            end)
            
            it("should show golden and rainbow variants for golden eggs", function()
                local chances = EggPetPreviewService:CalculatePetChances("golden_egg")
                
                -- Should only have golden and rainbow variants, no basic
                local hasGolden = false
                local hasRainbow = false
                
                for _, chance in ipairs(chances) do
                    expect(chance.variant == "golden" or chance.variant == "rainbow").to.equal(true)
                    if chance.variant == "golden" then hasGolden = true end
                    if chance.variant == "rainbow" then hasRainbow = true end
                end
                
                expect(hasGolden).to.equal(true)
                expect(hasRainbow).to.equal(true)
            end)
            
            it("should return empty table for invalid egg", function()
                local chances = EggPetPreviewService:CalculatePetChances("invalid_egg")
                expect(chances).to.be.a("table")
                expect(#chances).to.equal(0)
            end)
        end)
        
        describe("GetPetAssetImage", function()
            it("should return valid asset IDs", function()
                expect(EggPetPreviewService:GetPetAssetImage("rbxassetid://12345")).to.equal("rbxassetid://12345")
                expect(EggPetPreviewService:GetPetAssetImage("12345")).to.equal("rbxassetid://12345")
                expect(EggPetPreviewService:GetPetAssetImage("rbxassetid://0")).to.equal("")
                expect(EggPetPreviewService:GetPetAssetImage(nil)).to.equal("")
            end)
        end)
        
        describe("GetPetEmojiIcon", function()
            it("should return appropriate emoji fallbacks", function()
                expect(EggPetPreviewService:GetPetEmojiIcon("bear")).to.equal("🐻")
                expect(EggPetPreviewService:GetPetEmojiIcon("bunny")).to.equal("🐰")
                expect(EggPetPreviewService:GetPetEmojiIcon("unknown")).to.equal("🐾")
            end)
        end)
    end)
end