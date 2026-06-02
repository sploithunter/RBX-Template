--[[
    CombatOrigin: canonical-element resolution — pet origin by default, player archetype when
    unified, archetype->element mapping (earth=grass), valid-element + fallback handling.
    Run: mise run test-headless
]]

local CombatOrigin = loadModule("src/Shared/Game/CombatOrigin.lua")

local CFG = {
    unify_to_player = false,
    default_element = "grass",
    archetype_element = {
        geomancer = "grass",
        pyromancer = "lava",
        cryomancer = "ice",
        sandwalker = "desert",
    },
}

local function withUnify(on)
    local c = table.clone(CFG)
    c.unify_to_player = on
    return c
end

return function()
    describe("CombatOrigin.archetypeElement", function()
        it("maps archetypes to canonical elements (earth -> grass)", function()
            expect(CombatOrigin.archetypeElement("geomancer", CFG)).to.equal("grass")
            expect(CombatOrigin.archetypeElement("pyromancer", CFG)).to.equal("lava")
            expect(CombatOrigin.archetypeElement("cryomancer", CFG)).to.equal("ice")
            expect(CombatOrigin.archetypeElement("sandwalker", CFG)).to.equal("desert")
        end)

        it("returns nil for an unknown archetype", function()
            expect(CombatOrigin.archetypeElement("wizard", CFG)).to.equal(nil)
        end)
    end)

    describe("CombatOrigin.resolve (hybrid, not unified)", function()
        it("uses the pet's own biome element", function()
            expect(CombatOrigin.resolve("lava", "cryomancer", withUnify(false))).to.equal("lava")
            expect(CombatOrigin.resolve("ice", "pyromancer", withUnify(false))).to.equal("ice")
        end)

        it("falls back to default for an invalid/missing pet element", function()
            expect(CombatOrigin.resolve(nil, "pyromancer", withUnify(false))).to.equal("grass")
            expect(CombatOrigin.resolve("plasma", nil, withUnify(false))).to.equal("grass")
        end)
    end)

    describe("CombatOrigin.resolve (unify to player)", function()
        it("uses the player's archetype element regardless of the pet", function()
            expect(CombatOrigin.resolve("ice", "pyromancer", withUnify(true))).to.equal("lava")
            expect(CombatOrigin.resolve("lava", "cryomancer", withUnify(true))).to.equal("ice")
            expect(CombatOrigin.resolve("desert", "geomancer", withUnify(true))).to.equal("grass")
        end)

        it("falls back to the pet element when the player has no/unknown archetype", function()
            expect(CombatOrigin.resolve("desert", nil, withUnify(true))).to.equal("desert")
            expect(CombatOrigin.resolve("lava", "wizard", withUnify(true))).to.equal("lava")
        end)
    end)
end
