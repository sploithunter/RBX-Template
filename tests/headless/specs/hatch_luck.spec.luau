--[[
    Hatch luck progression (configs/pets.lua simulateHatch).
    Two terms, neither can run away (Jason: no hard caps, no volume farming):
      - LEVEL: diminishing-doubling curve (+per_doubling per doubling past
        first_bonus_at; log2, bounded by the level cap anyway).
      - COLLECTION: index completion fraction (0..1, from PetIndexService) x
        index_luck.max_bonus — a natural cap at 100% collection. Replaced the
        raw pets-hatched count, which a parked 24/7 auto-hatcher farmed for free.
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
    describe("hatch luck progression", function()
        it("fresh player is ~1x", function()
            expect(near(luckFor({ level = 0, indexCompletion = 0 }), 1.0)).to.equal(true)
        end)

        it("level follows the doubling curve", function()
            -- level 10: 1 + 0.5*log2(1 + 10/3) = ~2.06
            expect(near(luckFor({ level = 10, indexCompletion = 0 }), 2.06, 0.02)).to.equal(true)
            -- level 50: 1 + 0.5*log2(1 + 50/3) = ~3.07
            expect(near(luckFor({ level = 50, indexCompletion = 0 }), 3.07, 0.02)).to.equal(true)
        end)

        it("collection completion scales the index bonus linearly to its natural cap", function()
            local base = luckFor({ level = 0, indexCompletion = 0 })
            -- 50% collection (Jason's hypothetical: 160 of 330 entries) = half the weight
            expect(near(luckFor({ level = 0, indexCompletion = 0.5 }) - base, 1.0)).to.equal(true)
            -- full collection = the full configured max_bonus (2.0)
            expect(near(luckFor({ level = 0, indexCompletion = 1 }) - base, 2.0)).to.equal(true)
        end)

        it("completion is clamped — nothing past 100%", function()
            expect(
                near(
                    luckFor({ level = 0, indexCompletion = 5 }),
                    luckFor({ level = 0, indexCompletion = 1 })
                )
            ).to.equal(true)
        end)

        it("raw hatch volume earns NOTHING (the old runaway term is gone)", function()
            local a = luckFor({ level = 10, indexCompletion = 0.25 })
            local b = luckFor({ level = 10, indexCompletion = 0.25, petsHatched = 1000000 })
            expect(near(a, b)).to.equal(true)
        end)

        it("buff fractions still add on top (additive luckBoost)", function()
            local base = luckFor({ level = 10, indexCompletion = 0.5 })
            local buffed = luckFor({ level = 10, indexCompletion = 0.5, luckBoost = 1.5 })
            expect(near(buffed - base, 1.5)).to.equal(true)
        end)
    end)
end
