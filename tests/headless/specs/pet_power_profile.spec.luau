--[[
    PetPower.resolveProfile — [unit] mining/combat power split + contextual multipliers.
    Run: mise run test-headless
]]

local PetPower = loadModule("src/Shared/Game/PetPower.lua")

return function()
    describe("PetPower.resolveProfile intrinsic split", function()
        it("with all multipliers 1, mining = combat = base", function()
            local r = PetPower.resolveProfile({ base = 10 })
            expect(r.miningBase).to.equal(10)
            expect(r.combatBase).to.equal(10)
            expect(r.miningEffective).to.equal(10)
            expect(r.combatEffective).to.equal(10)
        end)

        it("matches the live bear/bunny numbers (tank 0.6 / support 0.35, grass 1.0)", function()
            -- bear: power 10, tank mining_mult 0.6 -> 6
            local bear = PetPower.resolveProfile({ base = 10, miningMult = 0.6, elementMult = 1.0 })
            expect(bear.miningBase).to.equal(6)
            -- bunny: power 8, support mining_mult 0.35 -> 2.8
            local bunny =
                PetPower.resolveProfile({ base = 8, miningMult = 0.35, elementMult = 1.0 })
            expect(bunny.miningBase).to.near(2.8, 1e-9)
        end)

        it("mining and combat diverge when their aptitudes differ (the trade driver)", function()
            local r = PetPower.resolveProfile({ base = 10, miningMult = 1.5, combatMult = 0.4 })
            expect(r.miningBase).to.equal(15) -- a 'miner'
            expect(r.combatBase).to.equal(4) -- weak in a fight
        end)

        it("element + variant scale BOTH numbers (intrinsic, shared)", function()
            -- lava attack_mult 1.15, golden variant 1.5
            local r = PetPower.resolveProfile({
                base = 10,
                elementMult = 1.15,
                variantMult = 1.5,
                miningMult = 1.0,
                combatMult = 1.0,
            })
            expect(r.miningBase).to.near(17.25, 1e-9) -- 10 * 1.15 * 1.5
            expect(r.combatBase).to.near(17.25, 1e-9)
        end)

        it("base_scale is a global lever on everything", function()
            local r = PetPower.resolveProfile({ base = 10, baseScale = 2, miningMult = 0.6 })
            expect(r.miningBase).to.equal(12) -- 10 * 2 * 0.6
        end)
    end)

    describe("PetPower.resolveProfile contextual multipliers", function()
        it("multiplies all context values into effective, leaving base untouched", function()
            local r = PetPower.resolveProfile({
                base = 10,
                miningMult = 0.6,
                context = { level = 1.5, boost = 2.0 },
            })
            expect(r.miningBase).to.equal(6) -- intrinsic unchanged (the card number)
            expect(r.contextMult).to.equal(3) -- 1.5 * 2.0
            expect(r.miningEffective).to.equal(18) -- 6 * 3 (live)
        end)

        it("empty/absent context leaves effective == base", function()
            local r = PetPower.resolveProfile({ base = 10, miningMult = 0.6, context = {} })
            expect(r.contextMult).to.equal(1)
            expect(r.miningEffective).to.equal(r.miningBase)
        end)

        it("a future multiplier is just another context key (framework check)", function()
            local r = PetPower.resolveProfile({
                base = 10,
                context = { level = 2, boost = 1, gamepass = 1.25, some_future_thing = 1.1 },
            })
            expect(r.contextMult).to.near(2.75, 1e-9) -- 2 * 1 * 1.25 * 1.1
        end)
    end)

    describe("PetPower.roundForDisplay", function()
        it("rounds, floors, ceils per mode", function()
            expect(PetPower.roundForDisplay(2.8, "round")).to.equal(3)
            expect(PetPower.roundForDisplay(2.8, "floor")).to.equal(2)
            expect(PetPower.roundForDisplay(2.1, "ceil")).to.equal(3)
        end)
    end)
end
