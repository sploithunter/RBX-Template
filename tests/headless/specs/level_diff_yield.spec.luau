--[[
    LevelDiffYield — diminishing XP vs out-leveled targets + the neutral payout seam.
    Jason: "nobody should be able to put on an auto clicker... and wake up 10-20
    levels ahead"; "three levels below you... almost not worth it"; coins stay
    full ("it allows for more hatching").
    Run: mise run test-headless
]]

local LevelDiffYield = loadModule("src/Shared/Game/LevelDiffYield.lua")
local leveling = loadModule("configs/leveling.lua")

local xpCfg = leveling.xp_level_scale
local payCfg = leveling.payout_level_scale

local function near(value, target)
    return math.abs(value - target) < 1e-9
end

return function()
    describe("LevelDiffYield.xp (diminishing returns, shipped numbers)", function()
        it("at-level and above pay full XP (no punch-up bonus)", function()
            expect(LevelDiffYield.xp(10, 10, xpCfg)).to.equal(1)
            expect(LevelDiffYield.xp(10, 12, xpCfg)).to.equal(1)
        end)

        it("decays 30% per level below", function()
            expect(near(LevelDiffYield.xp(10, 9, xpCfg), 0.7)).to.equal(true)
            expect(near(LevelDiffYield.xp(10, 8, xpCfg), 0.4)).to.equal(true)
        end)

        it("-3 levels hits the 10% floor (Jason: 'almost not worth it')", function()
            expect(near(LevelDiffYield.xp(10, 7, xpCfg), 0.1)).to.equal(true)
            -- and it never goes below the floor, however out-leveled
            expect(LevelDiffYield.xp(50, 1, xpCfg)).to.equal(0.1)
        end)

        it("missing config means no gate (x1)", function()
            expect(LevelDiffYield.xp(50, 1, nil)).to.equal(1)
        end)
    end)

    describe("LevelDiffYield.payout (neutral seam)", function()
        it("is exactly x1 at any level difference with shipped config", function()
            expect(LevelDiffYield.payout(10, 1, payCfg)).to.equal(1)
            expect(LevelDiffYield.payout(10, 10, payCfg)).to.equal(1)
            expect(LevelDiffYield.payout(1, 12, payCfg)).to.equal(1)
        end)

        it("the lever works when tuned (clamped linear)", function()
            local tuned = { per_level = 0.05, min = 0.5, max = 1.5 }
            expect(LevelDiffYield.payout(10, 8, tuned)).to.equal(0.9) -- 2 below: -10%
            expect(LevelDiffYield.payout(10, 30, tuned)).to.equal(1.5) -- clamped high
            expect(LevelDiffYield.payout(30, 1, tuned)).to.equal(0.5) -- clamped low
        end)
    end)
end
