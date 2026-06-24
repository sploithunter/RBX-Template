--[[
    EnhancementPricing — store buy/sell math (band selection + price formula + buyback floor).
    Run: mise run test-headless
]]

local EnhancementPricing = loadModule("src/Shared/Game/EnhancementPricing.lua")

local CFG = {
    level_step = 5,
    min_level = 5,
    max_level = 50,
    buy = { base = 20, per_level = 10, grade_mult = { natural = 1.0 } },
    sell = { fraction = 0.30 },
}

return function()
    describe("EnhancementPricing.bandFor (slottable multiple-of-5 band)", function()
        it("rounds to the nearest multiple of the step", function()
            expect(EnhancementPricing.bandFor(17, CFG)).to.equal(15) -- L17 sees L15
            expect(EnhancementPricing.bandFor(18, CFG)).to.equal(20) -- L18 sees L20
            expect(EnhancementPricing.bandFor(16, CFG)).to.equal(15)
            expect(EnhancementPricing.bandFor(22, CFG)).to.equal(20)
            expect(EnhancementPricing.bandFor(23, CFG)).to.equal(25)
        end)

        it("exact multiples map to themselves", function()
            expect(EnhancementPricing.bandFor(15, CFG)).to.equal(15)
            expect(EnhancementPricing.bandFor(20, CFG)).to.equal(20)
            expect(EnhancementPricing.bandFor(50, CFG)).to.equal(50)
        end)

        it("the shown band is always within the ±2 slot window", function()
            for lvl = 1, 60 do
                local band = EnhancementPricing.bandFor(lvl, CFG)
                local clamped = math.max(5, math.min(50, lvl))
                -- inside the clamp range, band is within 2 of the level
                if lvl >= 5 and lvl <= 50 then
                    expect(math.abs(band - lvl) <= 2).to.equal(true)
                end
                expect(clamped).to.be.ok()
            end
        end)

        it("clamps to [min_level, max_level]", function()
            expect(EnhancementPricing.bandFor(1, CFG)).to.equal(5) -- floor at min
            expect(EnhancementPricing.bandFor(2, CFG)).to.equal(5)
            expect(EnhancementPricing.bandFor(55, CFG)).to.equal(50) -- cap at max
            expect(EnhancementPricing.bandFor(999, CFG)).to.equal(50)
        end)
    end)

    describe("EnhancementPricing.buyPrice (base + per_level * level)", function()
        it("scales with the band level", function()
            expect(EnhancementPricing.buyPrice("natural", 5, CFG)).to.equal(70)
            expect(EnhancementPricing.buyPrice("natural", 10, CFG)).to.equal(120)
            expect(EnhancementPricing.buyPrice("natural", 15, CFG)).to.equal(170)
            expect(EnhancementPricing.buyPrice("natural", 20, CFG)).to.equal(220)
        end)

        it("applies the grade multiplier (room for single/dual later)", function()
            local cfg = {
                buy = { base = 20, per_level = 10, grade_mult = { natural = 1.0, single = 2.0 } },
            }
            expect(EnhancementPricing.buyPrice("natural", 10, cfg)).to.equal(120)
            expect(EnhancementPricing.buyPrice("single", 10, cfg)).to.equal(240)
        end)

        it("defaults grade multiplier to 1 for unknown grades", function()
            expect(EnhancementPricing.buyPrice("mystery", 10, CFG)).to.equal(120)
        end)

        it("is defensive against missing config", function()
            expect(EnhancementPricing.buyPrice("natural", 10, nil)).to.equal(0)
        end)
    end)

    describe("EnhancementPricing.sellPrice (junk-sink buyback)", function()
        it("is a floored fraction of the buy price", function()
            expect(EnhancementPricing.sellPrice("natural", 10, CFG)).to.equal(36) -- floor(120*0.3)
            expect(EnhancementPricing.sellPrice("natural", 5, CFG)).to.equal(21) -- floor(70*0.3)
        end)

        it("never pays more than buy (no arbitrage — fraction clamped to [0,1])", function()
            local cfg = { buy = { base = 100, per_level = 0 }, sell = { fraction = 1.5 } }
            expect(EnhancementPricing.sellPrice("natural", 10, cfg)).to.equal(100) -- clamped to 1.0
        end)

        it("is zero with no sell config", function()
            local cfg = { buy = { base = 100, per_level = 0 } }
            expect(EnhancementPricing.sellPrice("natural", 10, cfg)).to.equal(0)
        end)
    end)
end
