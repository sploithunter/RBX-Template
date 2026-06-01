--[[
    Feature 10 slice 1b: PetEndurance — defensive inverse-mining arithmetic.
    Run: mise run test-headless
]]

local PetEndurance = loadModule("src/Shared/Game/PetEndurance.lua")

return function()
    describe("PetEndurance.maxEndurance", function()
        it("is power times the down-threshold factor", function()
            expect(PetEndurance.maxEndurance(100, 1.0)).to.equal(100)
            expect(PetEndurance.maxEndurance(100, 1.5)).to.equal(150)
        end)

        it("floors at 1 so a 0-power pet still takes a hit to down", function()
            expect(PetEndurance.maxEndurance(0, 1.0)).to.equal(1)
            expect(PetEndurance.maxEndurance(nil, nil)).to.equal(1)
        end)
    end)

    describe("PetEndurance.applyHit", function()
        it("accumulates damage", function()
            expect(PetEndurance.applyHit(0, 10)).to.equal(10)
            expect(PetEndurance.applyHit(10, 25)).to.equal(35)
        end)

        it("treats nil as zero and never goes negative", function()
            expect(PetEndurance.applyHit(nil, 5)).to.equal(5)
            expect(PetEndurance.applyHit(3, -10)).to.equal(0)
        end)
    end)

    describe("PetEndurance.isDowned", function()
        it("is false below the ceiling and true at/above it", function()
            -- power 100, factor 1.0 -> ceiling 100
            expect(PetEndurance.isDowned(99, 100, 1.0)).to.equal(false)
            expect(PetEndurance.isDowned(100, 100, 1.0)).to.equal(true)
            expect(PetEndurance.isDowned(140, 100, 1.0)).to.equal(true)
        end)
    end)

    describe("PetEndurance.regen (partial-damage heal)", function()
        it("bleeds accumulated damage back toward zero at perSecond", function()
            -- 50 taken, 8/s for 2s -> 34
            expect(PetEndurance.regen(50, 2, 8)).to.equal(34)
        end)

        it("clamps at zero (cannot overheal)", function()
            expect(PetEndurance.regen(10, 5, 8)).to.equal(0)
        end)

        it("is a no-op at zero rate", function()
            expect(PetEndurance.regen(50, 2, 0)).to.equal(50)
        end)
    end)

    describe("PetEndurance.canRegen (out-of-combat gate)", function()
        it("waits the delay after the last hit before regenerating", function()
            -- last hit at t=10, delay 3s
            expect(PetEndurance.canRegen(12, 10, 3)).to.equal(false)
            expect(PetEndurance.canRegen(13, 10, 3)).to.equal(true)
            expect(PetEndurance.canRegen(20, 10, 3)).to.equal(true)
        end)
    end)

    describe("PetEndurance.healthFraction", function()
        it("is 1 at full health and 0 when downed", function()
            expect(PetEndurance.healthFraction(0, 100, 1.0)).to.equal(1)
            expect(PetEndurance.healthFraction(100, 100, 1.0)).to.equal(0)
        end)

        it("is the linear remaining fraction in between", function()
            expect(PetEndurance.healthFraction(25, 100, 1.0)).to.equal(0.75)
        end)

        it("never reports negative even past the ceiling", function()
            expect(PetEndurance.healthFraction(140, 100, 1.0)).to.equal(0)
        end)
    end)
end
