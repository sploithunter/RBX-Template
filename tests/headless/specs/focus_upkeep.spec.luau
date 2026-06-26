--[[
    FocusUpkeep — the always-on (toggle) Focus drain economy. Unit scenarios.
    Run: mise run test-headless
]]

local FocusUpkeep = loadModule("src/Shared/Game/FocusUpkeep.lua")

return function()
    describe("FocusUpkeep.effectiveRate", function()
        it("returns the base rate with no reduction", function()
            expect(FocusUpkeep.effectiveRate(2.5, 0)).to.equal(2.5)
            expect(FocusUpkeep.effectiveRate(2.5, nil)).to.equal(2.5)
        end)

        it("lowers the rate by an efficiency reduction fraction", function()
            -- 40% efficiency reduction on a 2.5/s toggle -> 1.5/s
            expect(FocusUpkeep.effectiveRate(2.5, 0.4)).to.equal(1.5)
        end)

        it("clamps reduction to [0,1] (>=1 is free, <0 is none)", function()
            expect(FocusUpkeep.effectiveRate(2.5, 1.5)).to.equal(0)
            expect(FocusUpkeep.effectiveRate(2.5, -1)).to.equal(2.5)
        end)

        it("treats a non-positive base as free", function()
            expect(FocusUpkeep.effectiveRate(0, 0.5)).to.equal(0)
        end)
    end)

    describe("FocusUpkeep.total", function()
        it("sums the active toggles' rates", function()
            expect(FocusUpkeep.total({ 2.5, 1.5, 1.0 })).to.equal(5)
        end)

        it("is zero for no active toggles", function()
            expect(FocusUpkeep.total({})).to.equal(0)
            expect(FocusUpkeep.total(nil)).to.equal(0)
        end)
    end)

    describe("FocusUpkeep.step", function()
        it("drains rate*dt when the pool covers it", function()
            -- 5/s for 0.2s = 1.0 drained; 100 -> 99
            local r = FocusUpkeep.step(100, 5, 0.2)
            expect(r.focus).to.equal(99)
            expect(r.drained).to.equal(1)
            expect(r.crashed).to.equal(false)
        end)

        it("does nothing with no active upkeep", function()
            local r = FocusUpkeep.step(50, 0, 0.2)
            expect(r.focus).to.equal(50)
            expect(r.crashed).to.equal(false)
        end)

        it("crashes when the pool cannot cover the full tick", function()
            -- need 1.0 but only 0.5 left -> drain to 0 and crash
            local r = FocusUpkeep.step(0.5, 5, 0.2)
            expect(r.focus).to.equal(0)
            expect(r.drained).to.equal(0.5)
            expect(r.crashed).to.equal(true)
        end)

        it("crashes from an empty pool with active upkeep", function()
            local r = FocusUpkeep.step(0, 5, 0.2)
            expect(r.focus).to.equal(0)
            expect(r.crashed).to.equal(true)
        end)

        it("drains exactly to zero without crashing", function()
            -- need exactly 1.0, pool exactly 1.0 -> 0, not a crash
            local r = FocusUpkeep.step(1, 5, 0.2)
            expect(r.focus).to.equal(0)
            expect(r.crashed).to.equal(false)
        end)
    end)
end
