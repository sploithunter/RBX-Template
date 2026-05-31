--[[
    Phase 11: PetInventoryView — the pure single-source-of-truth projection module.
    Every projection (folders, equipped mirror, client cards, counts) derives from
    `items` (uid-keyed records) via this module, so they can never drift.
    Run: mise run test-headless
]]

local View = loadModule("src/Shared/Inventory/PetInventoryView.lua")

local CONFIG = { stack_key_fields = { "id", "variant" }, count_stacks_as_single = true }

-- Helper: build an items map keyed by uid.
local function items(list)
    local m = {}
    for _, rec in ipairs(list) do
        m[rec.uid] = rec
    end
    return m
end

return function()
    describe("PetInventoryView.stackKey", function()
        it("joins the configured fields", function()
            expect(View.stackKey({ id = "bear", variant = "golden" }, CONFIG)).to.equal(
                "bear:golden"
            )
        end)
    end)

    describe("PetInventoryView.normalize", function()
        it("copies the key into uid, strips quantity/_kind, coerces equipped_slot", function()
            local m = {
                u1 = {
                    id = "bear",
                    variant = "basic",
                    quantity = 5,
                    _kind = "stack",
                    equipped_slot = "2",
                },
            }
            View.normalize(m)
            expect(m.u1.uid).to.equal("u1")
            expect(m.u1.quantity).to.equal(nil)
            expect(m.u1._kind).to.equal(nil)
            expect(m.u1.equipped_slot).to.equal(2)
        end)
        it("drops zero / empty equipped_slot to nil", function()
            local m = {
                a = { id = "x", variant = "basic", equipped_slot = 0 },
                b = { id = "y", variant = "basic", equipped_slot = "" },
            }
            View.normalize(m)
            expect(m.a.equipped_slot).to.equal(nil)
            expect(m.b.equipped_slot).to.equal(nil)
        end)
        it("is idempotent (double-run is a no-op)", function()
            local m = { u1 = { id = "bear", variant = "basic", quantity = 3 } }
            View.normalize(m)
            View.normalize(m)
            expect(m.u1.uid).to.equal("u1")
            expect(m.u1.quantity).to.equal(nil)
        end)
    end)

    describe("PetInventoryView.groups", function()
        it("groups N instances of the same id:variant into one group with total=N", function()
            local m = items({
                { uid = "a", id = "bear", variant = "golden", obtained_at = 1 },
                { uid = "b", id = "bear", variant = "golden", obtained_at = 2 },
                { uid = "c", id = "bear", variant = "golden", obtained_at = 3 },
            })
            local g = View.groups(m, CONFIG)
            expect(#g).to.equal(1)
            expect(g[1].key).to.equal("bear:golden")
            expect(g[1].total).to.equal(3)
            expect(#g[1].uids).to.equal(3)
        end)
        it("counts equipped and unequipped identically in total; tracks equippedCount", function()
            local m = items({
                { uid = "a", id = "bear", variant = "golden", obtained_at = 1, equipped_slot = 1 },
                { uid = "b", id = "bear", variant = "golden", obtained_at = 2 },
            })
            local g = View.groups(m, CONFIG)
            expect(g[1].total).to.equal(2) -- equipped pet still counts toward ownership
            expect(g[1].equippedCount).to.equal(1)
        end)
        it("orders deterministically by obtained_at then uid", function()
            local m = items({
                { uid = "z", id = "bear", variant = "basic", obtained_at = 5 },
                { uid = "a", id = "wolf", variant = "basic", obtained_at = 2 },
            })
            local g = View.groups(m, CONFIG)
            expect(g[1].key).to.equal("wolf:basic") -- obtained_at 2 sorts first
            expect(g[2].key).to.equal("bear:basic")
        end)
    end)

    describe("PetInventoryView.equippedSlots", function()
        it("maps slot -> uid for in-range slots", function()
            local m = items({
                { uid = "a", id = "bear", variant = "basic", obtained_at = 1, equipped_slot = 1 },
                { uid = "b", id = "wolf", variant = "basic", obtained_at = 2, equipped_slot = 3 },
                { uid = "c", id = "cat", variant = "basic", obtained_at = 3 },
            })
            local slots = View.equippedSlots(m, 6)
            expect(slots[1]).to.equal("a")
            expect(slots[3]).to.equal("b")
            expect(slots[2]).to.equal(nil)
        end)
        it("on a slot collision the comparator-smaller record wins; loser is a conflict", function()
            local m = items({
                { uid = "a", id = "bear", variant = "basic", obtained_at = 1, equipped_slot = 1 },
                { uid = "b", id = "wolf", variant = "basic", obtained_at = 2, equipped_slot = 1 },
            })
            local slots, conflicts = View.equippedSlots(m, 6)
            expect(slots[1]).to.equal("a") -- smaller obtained_at wins
            expect(#conflicts).to.equal(1)
            expect(conflicts[1]).to.equal("b")
        end)
        it("ignores slots beyond maxSlots (caller clears them)", function()
            local m = items({
                { uid = "a", id = "bear", variant = "basic", obtained_at = 1, equipped_slot = 9 },
            })
            local slots = View.equippedSlots(m, 6)
            expect(slots[9]).to.equal(nil)
        end)
    end)

    describe("PetInventoryView.usedSlots / categoryCounts", function()
        local m = items({
            { uid = "a", id = "bear", variant = "golden", obtained_at = 1 },
            { uid = "b", id = "bear", variant = "golden", obtained_at = 2 },
            { uid = "c", id = "wolf", variant = "basic", obtained_at = 3 },
        })
        it("usedSlots counts display groups when count_stacks_as_single", function()
            expect(View.usedSlots(m, CONFIG)).to.equal(2) -- bear:golden + wolf:basic
        end)
        it("usedSlots counts instances when count_stacks_as_single = false", function()
            expect(
                View.usedSlots(
                    m,
                    { stack_key_fields = { "id", "variant" }, count_stacks_as_single = false }
                )
            ).to.equal(3)
        end)
        it("categoryCounts reports display groups and total instances", function()
            local c = View.categoryCounts(m, CONFIG)
            expect(c.display).to.equal(2)
            expect(c.total).to.equal(3)
        end)
    end)

    describe("PetInventoryView capability gating", function()
        local capability = { specialRarities = { huge = true, secret = true } }
        it("a huge pet is levelable/enchantable", function()
            expect(View.isLevelable({ id = "bear", variant = "basic", huge = true }, capability)).to.equal(
                true
            )
        end)
        it("a special rarity is levelable", function()
            expect(
                View.isLevelable(
                    { id = "bear", variant = "basic", rarity_id = "secret" },
                    capability
                )
            ).to.equal(true)
        end)
        it("a plain common is NOT levelable", function()
            expect(
                View.isLevelable(
                    { id = "bear", variant = "basic", rarity_id = "common" },
                    capability
                )
            ).to.equal(false)
        end)
        it("allowAll opens it up", function()
            expect(View.isEnchantable({ id = "bear", variant = "basic" }, { allowAll = true })).to.equal(
                true
            )
        end)
    end)
end
