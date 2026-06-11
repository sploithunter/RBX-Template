--[[
    Hatch luck progression curve (configs/pets.lua simulateHatch).
    Pins the diminishing-doubling curve (Jason: no hard caps, "get a good curve") —
    level and pets-hatched each add `per_doubling` per doubling past `first_bonus_at`,
    so neither term runs away (the old linear 0.01/hatch hit +5 at 500 eggs alone).
    Run: mise run test-headless
]]

local pets = loadModule("configs/pets.lua")

-- simulateHatch rolls randomly but returns the DETERMINISTIC luckMultiplier it used.
local function luckFor(playerData)
    local result = pets.simulateHatch("earth_egg", playerData)
    assert(result, "simulateHatch returned nil")
    return result.luckMultiplier
end

local function near(value, target, tolerance)
    return math.abs(value - target) <= (tolerance or 0.01)
end

return function()
    describe("hatch luck progression curve", function()
        it("fresh player is ~1x", function()
            expect(near(luckFor({ level = 0, petsHatched = 0 }), 1.0)).to.equal(true)
        end)

        it("early game roughly matches the old linear feel", function()
            -- L10/H100: old linear gave 3.0; curve lands close (~2.87)
            expect(near(luckFor({ level = 10, petsHatched = 100 }), 2.87, 0.05)).to.equal(true)
        end)

        it("endgame no longer runs to the cap", function()
            -- L50/H500: old linear gave 11 (pinned to the 10x egg cap); curve ~4.61
            expect(near(luckFor({ level = 50, petsHatched = 500 }), 4.61, 0.05)).to.equal(true)
        end)

        it("10k eggs is a slow crawl, not a runaway", function()
            -- old linear: 101x. Curve: ~6.1x — each DOUBLING of hatches adds a fixed bonus.
            local l = luckFor({ level = 50, petsHatched = 10000 })
            expect(l > 5.8 and l < 6.4).to.equal(true)
        end)

        it("buff fractions still add on top (additive luckBoost)", function()
            local base = luckFor({ level = 10, petsHatched = 100 })
            local buffed = luckFor({ level = 10, petsHatched = 100, luckBoost = 1.5 })
            expect(near(buffed - base, 1.5)).to.equal(true)
        end)
    end)
end
