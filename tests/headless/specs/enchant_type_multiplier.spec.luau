--[[
    Enchant type-multiplier curve (Jason: "base * type multiplier — no shift, no cap").
    Pins the agreed Coin Finder curve so the config numbers can't silently drift.
    coin% = strength * coin_finder.amount_per_strength * type_multipliers[tier]
    Run: mise run test-headless
]]

local enchants = loadModule("configs/enchants.lua")

local function coinPct(strength, tier)
    local base = enchants.effects.coin_finder.modifier.amount_per_strength
    local mult = enchants.type_multipliers[tier]
    -- round to 4 decimals — 0.06 isn't exact in binary, so 5*0.06*1.5 lands at 0.4499999…
    return math.floor(strength * base * mult * 10000 + 0.5) / 10000
end

return function()
    describe("enchant type_multipliers (coin curve)", function()
        it("base is 6% per strength (legendary tier)", function()
            expect(enchants.effects.coin_finder.modifier.amount_per_strength).to.equal(0.06)
            expect(enchants.type_multipliers.legendary).to.equal(1.0)
        end)

        it("exclusive +5 = 60% (the anchor)", function()
            expect(coinPct(5, "exclusive")).to.equal(0.6)
            expect(coinPct(1, "exclusive")).to.equal(0.12)
        end)

        it("scales up by tier — colossal +5 = 120%", function()
            expect(coinPct(5, "legendary")).to.equal(0.30)
            expect(coinPct(5, "mythic")).to.equal(0.45)
            expect(coinPct(5, "huge")).to.equal(0.75)
            expect(coinPct(5, "titanic")).to.equal(0.90)
            expect(coinPct(5, "colossal")).to.equal(1.20)
        end)

        it("is uncapped — strength past +5 keeps climbing", function()
            expect(coinPct(7, "colossal")).to.equal(1.68) -- 7 * 0.06 * 4.0
            expect(coinPct(10, "colossal")).to.equal(2.40)
        end)

        it("every enchantable tier has a multiplier", function()
            for _, tier in ipairs({
                "legendary",
                "mythic",
                "secret",
                "exclusive",
                "huge",
                "titanic",
                "colossal",
            }) do
                expect(type(enchants.type_multipliers[tier])).to.equal("number")
            end
        end)
    end)
end
