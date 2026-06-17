--[[
    PetTargeting — damage/power targeting scope resolution (badge ring + future fan-out SSOT).
    Run: mise run test-headless
]]

local PetTargeting = loadModule("src/Shared/Game/PetTargeting.lua")

local ROLES = {
    roles = {
        ranged = { targeting = "single" },
        tank = { targeting = "single" },
        artillery = { targeting = "targeted_aoe" }, -- hypothetical AoE damage role
    },
    aura_targeting_by_kind = {
        empower = "single",
        hold = "single",
        offense = "aura",
        yield = "aura",
    },
}

return function()
    describe("PetTargeting.attackScope (damage targeting -> role badge ring)", function()
        it("uses the role default", function()
            expect(PetTargeting.attackScope(nil, "ranged", ROLES)).to.equal("single")
            expect(PetTargeting.attackScope(nil, "artillery", ROLES)).to.equal("targeted_aoe")
        end)

        it("per-pet explicit override wins over the role default", function()
            expect(PetTargeting.attackScope("aura", "ranged", ROLES)).to.equal("aura")
        end)

        it("falls back to single for unknown role / missing config", function()
            expect(PetTargeting.attackScope(nil, "mystery", ROLES)).to.equal("single")
            expect(PetTargeting.attackScope(nil, "ranged", nil)).to.equal("single")
        end)
    end)

    describe("PetTargeting.auraScope (power targeting -> ability badge ring)", function()
        it("uses the kind default map", function()
            expect(PetTargeting.auraScope({ kind = "empower" }, ROLES)).to.equal("single")
            expect(PetTargeting.auraScope({ kind = "offense" }, ROLES)).to.equal("aura")
        end)

        it("an aura's own targeting overrides the kind default", function()
            expect(PetTargeting.auraScope({ kind = "offense", targeting = "single" }, ROLES)).to.equal(
                "single"
            )
        end)

        it("falls back to single for unknown kind / non-table", function()
            expect(PetTargeting.auraScope({ kind = "mystery" }, ROLES)).to.equal("single")
            expect(PetTargeting.auraScope(nil, ROLES)).to.equal("single")
        end)
    end)
end
