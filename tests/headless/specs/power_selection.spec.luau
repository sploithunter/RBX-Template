--[[
    Feature 14: Power Selection at Level-Up — [unit] scenarios.
    Run: mise run test-headless
]]

local PowerSelection = loadModule("src/Shared/Game/PowerSelection.lua")
local powersConfig = loadModule("configs/powers.lua")
local archetypes = loadModule("configs/archetypes.lua")
local ArchetypeLogic = loadModule("src/Shared/Game/ArchetypeLogic.lua")

local levels = powersConfig.selection_levels -- {5,9,13,17,21,25}
local geoPowers = ArchetypeLogic.availablePowers("geomancer", archetypes)

return function()
    describe("PowerSelection.pendingSelections", function()
        it("is 0 below the first selection level", function()
            expect(PowerSelection.pendingSelections(levels[1] - 1, 0, levels)).to.equal(0)
        end)

        it("is 1 on reaching level 5 with none selected", function()
            expect(PowerSelection.pendingSelections(5, 0, levels)).to.equal(1)
        end)

        it("grants at most one per selection level (level 5, 1 selected -> 0 pending)", function()
            expect(PowerSelection.pendingSelections(5, 1, levels)).to.equal(0)
        end)

        it("accumulates unspent selections across levels (level 13, 1 selected -> 2)", function()
            -- levels 5,9,13 reached = 3; minus 1 selected = 2 pending
            expect(PowerSelection.pendingSelections(13, 1, levels)).to.equal(2)
        end)
    end)

    describe("PowerSelection.canSelect", function()
        it("allows a valid in-pool selection when one is pending", function()
            local r = PowerSelection.canSelect("stone_skin", geoPowers, {}, 5, levels)
            expect(r.ok).to.equal(true)
        end)

        it("rejects a power from another archetype", function()
            local r = PowerSelection.canSelect("frost_bind", geoPowers, {}, 5, levels)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("not_in_archetype_pool")
        end)

        it("rejects a duplicate selection", function()
            local r = PowerSelection.canSelect("stone_skin", geoPowers, { "stone_skin" }, 9, levels)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("already_selected")
        end)

        it("rejects when no selection is pending (below the first selection level)", function()
            local r = PowerSelection.canSelect("stone_skin", geoPowers, {}, levels[1] - 1, levels)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("no_pending_selection")
        end)

        it("rejects a second pick at the same level (1 already selected at level 5)", function()
            local r = PowerSelection.canSelect("bulwark", geoPowers, { "stone_skin" }, 5, levels)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("no_pending_selection")
        end)
    end)
end
