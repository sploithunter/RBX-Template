--[[
    XpReward.fromValue — [unit] activity XP from a reward magnitude.
    Run: mise run test-headless
]]

local XpReward = loadModule("src/Shared/Game/XpReward.lua")

return function()
    describe("XpReward.fromValue", function()
        it("scales XP by per_value (floored)", function()
            expect(XpReward.fromValue(100, { per_value = 0.5, min = 1 })).to.equal(50)
            expect(XpReward.fromValue(7, { per_value = 0.5, min = 1 })).to.equal(3) -- floor(3.5)
        end)

        it("applies the floor (min) for small positive values", function()
            -- value 1 * 0.5 = 0.5 -> floor 0 -> min 1
            expect(XpReward.fromValue(1, { per_value = 0.5, min = 1 })).to.equal(1)
        end)

        it("grants nothing for zero/negative value (no min freebie)", function()
            expect(XpReward.fromValue(0, { per_value = 0.5, min = 1 })).to.equal(0)
            expect(XpReward.fromValue(-5, { per_value = 0.5, min = 1 })).to.equal(0)
        end)

        it("defaults safely with missing config", function()
            expect(XpReward.fromValue(100, {})).to.equal(0) -- per_value defaults 0
            expect(XpReward.fromValue(100, nil)).to.equal(0)
        end)
    end)
end
