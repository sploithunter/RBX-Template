--[[
    SupportAura.forPet / isBuffer — [unit] per-zone buffer aura lookup.
    Run: mise run test-headless
]]

local SupportAura = loadModule("src/Shared/Game/SupportAura.lua")

local ROLES = {
    by_type = { bunny = "support", penguin = "support", doggy = "melee" },
    support_auras = {
        bunny = { kind = "heal", interval = 1.5, fraction = 0.3 },
        penguin = { kind = "defense", interval = 2.0, amount = 80, duration = 3 },
        emberimp = { kind = "offense", interval = 2.0, mult = 1.25, duration = 3 },
        meerkat = { kind = "yield", interval = 2.0, mult = 1.25, duration = 3 },
    },
}

return function()
    describe("SupportAura.forPet", function()
        it("returns the themed aura for each zone's buffer", function()
            expect(SupportAura.forPet("bunny", ROLES).kind).to.equal("heal")
            expect(SupportAura.forPet("penguin", ROLES).kind).to.equal("defense")
            expect(SupportAura.forPet("emberimp", ROLES).kind).to.equal("offense")
            expect(SupportAura.forPet("meerkat", ROLES).kind).to.equal("yield")
        end)

        it("carries the tuning knobs through", function()
            local d = SupportAura.forPet("penguin", ROLES)
            expect(d.amount).to.equal(80)
            expect(d.duration).to.equal(3)
        end)

        it("returns nil for a non-buffer pet", function()
            expect(SupportAura.forPet("doggy", ROLES)).to.equal(nil)
        end)

        it("defaults safely on missing/garbage input", function()
            expect(SupportAura.forPet("bunny", nil)).to.equal(nil)
            expect(SupportAura.forPet(nil, ROLES)).to.equal(nil)
            expect(SupportAura.forPet("bunny", {})).to.equal(nil)
        end)
    end)

    describe("SupportAura.isBuffer", function()
        it("is true only for pets with an aura", function()
            expect(SupportAura.isBuffer("bunny", ROLES)).to.equal(true)
            expect(SupportAura.isBuffer("meerkat", ROLES)).to.equal(true)
            expect(SupportAura.isBuffer("doggy", ROLES)).to.equal(false)
        end)
    end)

    -- The ONE implementation of the rage rules — EnemyService (live stamp) and
    -- BattleSim (simulated swings) both route through these.
    describe("SupportAura rage rules", function()
        local RAGE = { kind = "rage", enrage_below = 0.5, mult = 1.5 }

        it("gates on the enrage threshold (at-or-below rages)", function()
            expect(SupportAura.isEnraged(RAGE, 0.51)).to.equal(false)
            expect(SupportAura.isEnraged(RAGE, 0.5)).to.equal(true)
            expect(SupportAura.isEnraged(RAGE, 0)).to.equal(true)
        end)

        it("is never enraged for non-rage auras or garbage", function()
            expect(SupportAura.isEnraged({ kind = "offense" }, 0)).to.equal(false)
            expect(SupportAura.isEnraged(nil, 0)).to.equal(false)
        end)

        it("scales the fraction (not the multiplier) by variant", function()
            expect(SupportAura.rageMultiplier(RAGE, 0.4, 1)).to.equal(1.5) -- basic +50%
            expect(SupportAura.rageMultiplier(RAGE, 0.4, 1.5)).to.equal(1.75) -- rainbow +75%
            expect(SupportAura.rageMultiplier(RAGE, 0.6, 1)).to.equal(nil) -- calm
        end)

        it("sums rage fractions additively across an aura list", function()
            local auras = { RAGE, { kind = "offense", mult = 1.2 }, RAGE }
            expect(SupportAura.rageFraction(auras, 0.3, 1)).to.equal(1.0) -- 0.5 + 0.5
            expect(SupportAura.rageFraction(auras, 0.9, 1)).to.equal(0) -- calm
            expect(SupportAura.rageFraction(nil, 0.3, 1)).to.equal(0)
        end)

        it("defaults enrage_below to 0.5 and clamps it to [0, 1]", function()
            expect(SupportAura.isEnraged({ kind = "rage" }, 0.5)).to.equal(true)
            expect(SupportAura.isEnraged({ kind = "rage", enrage_below = 7 }, 1)).to.equal(true)
        end)
    end)
end
