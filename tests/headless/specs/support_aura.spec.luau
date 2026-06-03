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
end
