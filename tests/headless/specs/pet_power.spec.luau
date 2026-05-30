--[[
    PetPower — single source of truth for configured base power (huge-aware).
    Run: mise run test-headless
]]

local PetPower = loadModule("src/Shared/Game/PetPower.lua")

-- mimic configs/pets.lua getPet() output
local bearBasic = { power = 10, huge_base_power = 100 }
local bearGolden = { power = 15, huge_base_power = 100 }
local doggy = { power = 12 } -- no huge_base_power configured

local prog = { enabled = true, power_scaling = { percent_per_level = 0.1, max_bonus_percent = 5 } }

return function()
    describe("PetPower.configuredBasePower", function()
        it("uses variant power for a normal pet", function()
            expect(PetPower.configuredBasePower(bearBasic, false)).to.equal(10)
            expect(PetPower.configuredBasePower(bearGolden, false)).to.equal(15)
        end)

        it("uses huge_base_power for a huge pet", function()
            expect(PetPower.configuredBasePower(bearBasic, true)).to.equal(100)
            expect(PetPower.configuredBasePower(bearGolden, true)).to.equal(100)
        end)

        it("falls back to variant power if huge_base_power is unset", function()
            expect(PetPower.configuredBasePower(doggy, true)).to.equal(12)
        end)

        it("is safe with nil config", function()
            expect(PetPower.configuredBasePower(nil, true)).to.equal(1)
        end)
    end)

    describe("PetPower.withLevel", function()
        it("is the base at level 1", function()
            expect(PetPower.withLevel(100, 1, prog)).to.equal(100)
        end)

        it("applies the per-level bonus (10% per level)", function()
            -- level 3 -> +20% -> 120
            expect(PetPower.withLevel(100, 3, prog)).to.equal(120)
        end)

        it("returns the base unchanged with no progression config", function()
            expect(PetPower.withLevel(100, 9, nil)).to.equal(100)
        end)
    end)

    describe("PetPower.basePowerForLevel", function()
        it("composes huge base + level (huge bear lvl 3 -> 120)", function()
            expect(PetPower.basePowerForLevel(bearBasic, true, 3, prog)).to.equal(120)
        end)

        it("normal bear lvl 1 -> 10", function()
            expect(PetPower.basePowerForLevel(bearBasic, false, 1, prog)).to.equal(10)
        end)
    end)
end
