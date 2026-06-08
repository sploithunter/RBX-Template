--[[
    Feature 15: Augmentation Slots — [unit] scenarios.
    Run: mise run test-headless
]]

local Augmentation = loadModule("src/Shared/Game/Augmentation.lua")
local config = loadModule("configs/augmentation.lua")

local grants = config.slot_grant_levels -- {8,12,18,25,35,45}

local function countActive(active, slotType, tier)
    for _, b in ipairs(active) do
        if b.type == slotType and b.tier == tier then
            return b.amount
        end
    end
    return nil
end

return function()
    describe("Augmentation slot grants", function()
        it("grants no slots below the first grant level", function()
            expect(Augmentation.slotsGranted(grants[1] - 1, grants)).to.equal(0)
            expect(Augmentation.unallocatedSlots(grants[1] - 1, 0, grants)).to.equal(0)
        end)

        it("grants 1 slot on reaching the first grant level", function()
            expect(Augmentation.slotsGranted(grants[1], grants)).to.equal(1)
            expect(Augmentation.unallocatedSlots(grants[1], 0, grants)).to.equal(1)
        end)

        it("unallocated = granted minus allocated", function()
            -- at the 3rd grant level -> 3 granted; 2 allocated -> 1 free
            expect(Augmentation.unallocatedSlots(grants[3], 2, grants)).to.equal(1)
        end)
    end)

    describe("Augmentation.canPlace", function()
        it("allows placing on an unlocked power with a free slot", function()
            expect(Augmentation.canPlace("recharge", true, {}, 1, config).ok).to.equal(true)
        end)

        it("rejects placing on a locked (unselected) power", function()
            local r = Augmentation.canPlace("recharge", false, {}, 1, config)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("power_locked")
        end)

        it("rejects an unknown slot type", function()
            expect(Augmentation.canPlace("haste", true, {}, 1, config).reason).to.equal(
                "invalid_slot_type"
            )
        end)

        it("rejects when no unallocated slots remain", function()
            expect(Augmentation.canPlace("recharge", true, {}, 0, config).reason).to.equal(
                "no_unallocated_slots"
            )
        end)

        it("rejects exceeding the per-power max (6)", function()
            local full = { "recharge", "recharge", "recharge", "strength", "range", "duration" }
            expect(Augmentation.canPlace("recharge", true, full, 1, config).reason).to.equal(
                "max_slots_reached"
            )
        end)
    end)

    describe("Augmentation.activeSetBonuses", function()
        it("3 matching slots trigger the 3-tier set bonus", function()
            local active =
                Augmentation.activeSetBonuses({ "recharge", "recharge", "recharge" }, config)
            expect(countActive(active, "recharge", 3)).to.equal(config.set_bonuses[3])
            expect(countActive(active, "recharge", 4)).to.equal(nil)
        end)

        it("4 matching slots apply BOTH the 3- and 4-tier bonuses, 4 stronger", function()
            local active = Augmentation.activeSetBonuses(
                { "recharge", "recharge", "recharge", "recharge" },
                config
            )
            local t3 = countActive(active, "recharge", 3)
            local t4 = countActive(active, "recharge", 4)
            expect(t3).to.equal(config.set_bonuses[3])
            expect(t4).to.equal(config.set_bonuses[4])
            expect(t4 > t3).to.equal(true)
        end)

        it("2 matching slots trigger no set bonus", function()
            expect(#Augmentation.activeSetBonuses({ "recharge", "recharge" }, config)).to.equal(0)
        end)
    end)
end
