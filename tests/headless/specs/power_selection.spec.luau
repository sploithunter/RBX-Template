--[[
    Feature 14: Power Selection at Level-Up — [unit] scenarios.
    Run: mise run test-headless
]]

local PowerSelection = loadModule("src/Shared/Game/PowerSelection.lua")
local powersConfig = loadModule("configs/powers.lua")
local archetypes = loadModule("configs/archetypes.lua")
local ArchetypeLogic = loadModule("src/Shared/Game/ArchetypeLogic.lua")

-- Cadence-agnostic: index off the live selection_levels array so this survives re-tuning.
local levels = powersConfig.selection_levels
local L1, L2, L3 = levels[1], levels[2], levels[3]
local geoPowers = ArchetypeLogic.availablePowers("geomancer", archetypes)

return function()
    describe("PowerSelection.pendingSelections", function()
        it("is 0 below the first selection level", function()
            expect(PowerSelection.pendingSelections(L1 - 1, 0, levels)).to.equal(0)
        end)

        it("is 1 on reaching the first selection level with none selected", function()
            expect(PowerSelection.pendingSelections(L1, 0, levels)).to.equal(1)
        end)

        it(
            "grants at most one per selection level (first level, 1 selected -> 0 pending)",
            function()
                expect(PowerSelection.pendingSelections(L1, 1, levels)).to.equal(0)
            end
        )

        it("accumulates unspent selections across levels (3rd level, 1 selected -> 2)", function()
            -- the first 3 selection levels reached = 3; minus 1 selected = 2 pending
            expect(PowerSelection.pendingSelections(L3, 1, levels)).to.equal(2)
        end)
    end)

    describe("PowerSelection.canSelect", function()
        it("allows a valid in-pool selection when one is pending", function()
            local r = PowerSelection.canSelect("stone_skin", geoPowers, {}, L1, levels)
            expect(r.ok).to.equal(true)
        end)

        it("rejects a power from another archetype", function()
            local r = PowerSelection.canSelect("frost_bind", geoPowers, {}, L1, levels)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("not_in_archetype_pool")
        end)

        it("rejects a duplicate selection", function()
            -- at the 2nd level with 1 already selected, a pick is pending but the dupe check fires
            local r =
                PowerSelection.canSelect("stone_skin", geoPowers, { "stone_skin" }, L2, levels)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("already_selected")
        end)

        it("rejects when no selection is pending (below the first selection level)", function()
            local r = PowerSelection.canSelect("stone_skin", geoPowers, {}, L1 - 1, levels)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("no_pending_selection")
        end)

        it(
            "rejects a second pick at the same level (1 already selected at the first level)",
            function()
                local r =
                    PowerSelection.canSelect("bulwark", geoPowers, { "stone_skin" }, L1, levels)
                expect(r.ok).to.equal(false)
                expect(r.reason).to.equal("no_pending_selection")
            end
        )
    end)
end
