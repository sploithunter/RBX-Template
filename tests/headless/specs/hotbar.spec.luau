--[[
    Feature 16: Hotbar / Command Bar — [unit] scenarios.
    Run: mise run test-headless
]]

local HotbarLogic = loadModule("src/Shared/Game/HotbarLogic.lua")
local config = loadModule("configs/hotbar.lua")
local archetypes = loadModule("configs/archetypes.lua")
local ArchetypeLogic = loadModule("src/Shared/Game/ArchetypeLogic.lua")

local geoPowers = ArchetypeLogic.availablePowers("geomancer", archetypes)

return function()
    describe("HotbarLogic.defaultBindings (archetype fill)", function()
        -- without the prototype override, the bar fills from the archetype pool
        local noOverride = table.clone(config)
        noOverride.default_binds = nil
        local b = HotbarLogic.defaultBindings(geoPowers, noOverride)

        it("binds the leading power slots to the archetype's powers", function()
            expect(b[1].type).to.equal("power")
            expect(b[1].target).to.equal(geoPowers[1])
            expect(b[3].target).to.equal(geoPowers[3])
        end)

        it("binds roster + tactical slots from config", function()
            expect(b[noOverride.defaults.roster_slots[1]].type).to.equal("roster")
            local tSlot = noOverride.defaults.tactical_slots[1]
            expect(b[tSlot].type).to.equal("tactical")
            expect(b[tSlot].target).to.equal(config.tactical_commands[1])
        end)
    end)

    describe("HotbarLogic.defaultBindings (default_binds override)", function()
        -- when default_binds is set, it wins regardless of archetype (config-agnostic: use a local
        -- override so this survives the live config nulling default_binds for the level-up flow)
        local override = table.clone(config)
        override.default_binds = {
            { slot = 1, type = "power", target = "cataclysm" },
            { slot = 8, type = "tactical", target = "scatter" },
        }
        local b = HotbarLogic.defaultBindings(geoPowers, override)

        it("uses the explicit layout, ignoring the archetype pool", function()
            expect(b[1].type).to.equal("power")
            expect(b[1].target).to.equal("cataclysm")
            expect(b[8].type).to.equal("tactical")
            expect(b[8].target).to.equal("scatter")
        end)
    end)

    describe("HotbarLogic.canRebind", function()
        it("allows rebinding to a valid power/roster bind", function()
            expect(HotbarLogic.canRebind(1, { type = "roster", target = "Healer Team" }, config).ok).to.equal(
                true
            )
        end)

        it("rejects an out-of-range slot (21)", function()
            expect(HotbarLogic.canRebind(21, { type = "power", target = "x" }, config).reason).to.equal(
                "invalid_slot"
            )
        end)

        it("rejects an invalid bind type", function()
            expect(HotbarLogic.canRebind(1, { type = "spell", target = "x" }, config).reason).to.equal(
                "invalid_bind_type"
            )
        end)

        it("allows clearing a slot (nil bind)", function()
            expect(HotbarLogic.canRebind(1, nil, config).ok).to.equal(true)
        end)
    end)

    describe("HotbarLogic.bindAt", function()
        it("returns nil for an empty slot (press does nothing)", function()
            expect(HotbarLogic.bindAt({}, 15)).to.equal(nil)
        end)

        it("returns the bind at a filled slot", function()
            local hotbar = { [1] = { type = "power", target = "stone_skin" } }
            expect(HotbarLogic.bindAt(hotbar, 1).target).to.equal("stone_skin")
        end)
    end)
end
