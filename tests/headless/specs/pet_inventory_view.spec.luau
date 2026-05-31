--[[
    Phase 11: PetInventoryView — the pure SSOT projection module (hybrid storage):
      - COMMON STACK entry: { id, variant, quantity, equipped_slots = {n…} }  (key = id:variant)
      - SPECIAL entry:      { uid, id, variant, equipped_slot = nil|n, … }     (key = uid)
    quantity = total owned (never decremented on equip); equipping just adds a slot.
    Run: mise run test-headless
]]

local View = loadModule("src/Shared/Inventory/PetInventoryView.lua")

local CONFIG = { stack_key_fields = { "id", "variant" }, count_stacks_as_single = true }
local CAP = { specialRarities = { huge = true, secret = true } }

local function map(t)
    return t
end

return function()
    describe("PetInventoryView.isStackEntry", function()
        it("true for an entry with numeric quantity, false for a uid record", function()
            expect(View.isStackEntry({ id = "bear", variant = "basic", quantity = 5 })).to.equal(
                true
            )
            expect(View.isStackEntry({ uid = "x", id = "bear", equipped_slot = 1 })).to.equal(false)
        end)
    end)

    describe("PetInventoryView.stackKey", function()
        it("joins the configured fields for a common", function()
            expect(View.stackKey({ id = "bear", variant = "golden" }, CONFIG)).to.equal(
                "bear:golden"
            )
        end)
        it("keys a special uniquely by uid when capability is given", function()
            expect(
                View.stackKey(
                    { uid = "u9", id = "bear", variant = "basic", huge = true },
                    CONFIG,
                    CAP
                )
            ).to.equal("uid:u9")
        end)
    end)

    describe("PetInventoryView.normalize", function()
        it(
            "common stack: coerces quantity + equipped_slots, strips uid/_kind/equipped_slot",
            function()
                local m = map({
                    ["bear:basic"] = {
                        id = "bear",
                        variant = "basic",
                        quantity = 3,
                        equipped_slots = { 3, 3, 1, 0, "x" },
                        uid = "bogus",
                        _kind = "stack",
                        equipped_slot = 2,
                    },
                })
                View.normalize(m)
                local e = m["bear:basic"]
                expect(e.quantity).to.equal(3)
                expect(e.uid).to.equal(nil)
                expect(e._kind).to.equal(nil)
                expect(e.equipped_slot).to.equal(nil)
                expect(#e.equipped_slots).to.equal(2) -- {1,3} (deduped, sorted, ≤quantity)
                expect(e.equipped_slots[1]).to.equal(1)
                expect(e.equipped_slots[2]).to.equal(3)
            end
        )
        it("clamps equipped_slots count to quantity", function()
            local m = map({
                ["c:basic"] = {
                    id = "c",
                    variant = "basic",
                    quantity = 1,
                    equipped_slots = { 1, 2, 3 },
                },
            })
            View.normalize(m)
            expect(#m["c:basic"].equipped_slots).to.equal(1)
        end)
        it(
            "special: uid=key, coerces equipped_slot, strips quantity/equipped_slots/_kind",
            function()
                local m = map({
                    u1 = {
                        id = "bear",
                        variant = "basic",
                        huge = true,
                        equipped_slot = "2",
                        quantity = 1,
                        _kind = "special",
                    },
                })
                View.normalize(m)
                expect(m.u1.uid).to.equal("u1")
                expect(m.u1.equipped_slot).to.equal(2)
                expect(m.u1.quantity).to.equal(nil)
                expect(m.u1._kind).to.equal(nil)
            end
        )
        it("is idempotent", function()
            local m = map({
                ["bear:basic"] = {
                    id = "bear",
                    variant = "basic",
                    quantity = 4,
                    equipped_slots = { 2 },
                },
            })
            View.normalize(m)
            View.normalize(m)
            expect(m["bear:basic"].quantity).to.equal(4)
            expect(#m["bear:basic"].equipped_slots).to.equal(1)
        end)
    end)

    describe("PetInventoryView.groups", function()
        it("a common stack is one group with total=quantity", function()
            local m = map({
                ["bear:golden"] = { id = "bear", variant = "golden", quantity = 3, obtained_at = 1 },
            })
            local g = View.groups(m, CONFIG, CAP)
            expect(#g).to.equal(1)
            expect(g[1].key).to.equal("bear:golden")
            expect(g[1].total).to.equal(3)
            expect(g[1].isSpecial).to.equal(false)
        end)
        it("tracks equipped/unequipped from equipped_slots", function()
            local m = map({
                ["bunny:basic"] = {
                    id = "bunny",
                    variant = "basic",
                    quantity = 3,
                    equipped_slots = { 4 },
                    obtained_at = 1,
                },
            })
            local g = View.groups(m, CONFIG, CAP)
            expect(g[1].total).to.equal(3)
            expect(g[1].equippedCount).to.equal(1)
            expect(g[1].unequippedCount).to.equal(2)
        end)
        it("huge specials never merge into the common stack of the same id:variant", function()
            local m = map({
                ["bear:basic"] = { id = "bear", variant = "basic", quantity = 80, obtained_at = 5 },
                h1 = { uid = "h1", id = "bear", variant = "basic", huge = true, obtained_at = 1000 },
                h2 = { uid = "h2", id = "bear", variant = "basic", huge = true, obtained_at = 1001 },
            })
            local g = View.groups(m, CONFIG, CAP)
            expect(#g).to.equal(3) -- 1 common bear:basic + 2 singleton huge
            local common
            for _, grp in ipairs(g) do
                if grp.key == "bear:basic" then
                    common = grp
                end
            end
            expect(common.total).to.equal(80)
            expect(common.isSpecial).to.equal(false)
        end)
        it("equipped special counts toward its singleton group", function()
            local m = map({
                h1 = {
                    uid = "h1",
                    id = "bear",
                    variant = "basic",
                    huge = true,
                    equipped_slot = 1,
                    obtained_at = 1,
                },
            })
            local g = View.groups(m, CONFIG, CAP)
            expect(g[1].total).to.equal(1)
            expect(g[1].equippedCount).to.equal(1)
            expect(g[1].uids[1]).to.equal("h1")
        end)
    end)

    describe("PetInventoryView.equippedSlots", function()
        it("maps stack slots and special slots into one slot map", function()
            local m = map({
                ["bear:basic"] = {
                    id = "bear",
                    variant = "basic",
                    quantity = 4,
                    equipped_slots = { 1, 3 },
                    obtained_at = 1,
                },
                h1 = {
                    uid = "h1",
                    id = "bear",
                    variant = "basic",
                    huge = true,
                    equipped_slot = 2,
                    obtained_at = 2,
                },
            })
            local slots = View.equippedSlots(m, 6)
            expect(slots[1].kind).to.equal("stack")
            expect(slots[1].key).to.equal("bear:basic")
            expect(slots[2].kind).to.equal("special")
            expect(slots[2].uid).to.equal("h1")
            expect(slots[3].kind).to.equal("stack")
            expect(slots[4]).to.equal(nil)
        end)
        it("resolves a slot collision: comparator-smaller wins, loser is a conflict", function()
            local m = map({
                ["bear:basic"] = {
                    id = "bear",
                    variant = "basic",
                    quantity = 1,
                    equipped_slots = { 1 },
                    obtained_at = 1,
                },
                h1 = {
                    uid = "h1",
                    id = "wolf",
                    variant = "basic",
                    huge = true,
                    equipped_slot = 1,
                    obtained_at = 2,
                },
            })
            local slots, conflicts = View.equippedSlots(m, 6)
            expect(slots[1].kind).to.equal("stack") -- obtained_at 1 wins
            expect(#conflicts).to.equal(1)
            expect(conflicts[1].uid).to.equal("h1")
        end)
        it("ignores slots beyond maxSlots", function()
            local m = map({
                ["bear:basic"] = {
                    id = "bear",
                    variant = "basic",
                    quantity = 1,
                    equipped_slots = { 9 },
                },
            })
            expect(View.equippedSlots(m, 6)[9]).to.equal(nil)
        end)
    end)

    describe("PetInventoryView.usedSlots / categoryCounts", function()
        local m = map({
            ["bear:basic"] = { id = "bear", variant = "basic", quantity = 80, obtained_at = 5 },
            ["bunny:basic"] = {
                id = "bunny",
                variant = "basic",
                quantity = 29,
                equipped_slots = { 4 },
                obtained_at = 1,
            },
            h1 = { uid = "h1", id = "bear", variant = "basic", huge = true, obtained_at = 1000 },
        })
        it("usedSlots = #stack kinds + #specials (count_stacks_as_single)", function()
            expect(View.usedSlots(m, CONFIG, CAP)).to.equal(3) -- bear:basic + bunny:basic + h1
        end)
        it("usedSlots expands quantity when count_stacks_as_single = false", function()
            expect(
                View.usedSlots(
                    m,
                    { stack_key_fields = { "id", "variant" }, count_stacks_as_single = false },
                    CAP
                )
            ).to.equal(110) -- 80 + 29 + 1
        end)
        it("categoryCounts: display groups vs total instances", function()
            local c = View.categoryCounts(m, CONFIG, CAP)
            expect(c.display).to.equal(3)
            expect(c.total).to.equal(110)
        end)
    end)

    describe("PetInventoryView capability gating", function()
        it("huge / special-rarity pets are levelable+enchantable; plain commons are not", function()
            expect(View.isLevelable({ id = "bear", variant = "basic", huge = true }, CAP)).to.equal(
                true
            )
            expect(
                View.isEnchantable({ id = "bear", variant = "basic", rarity_id = "secret" }, CAP)
            ).to.equal(true)
            expect(View.isLevelable({ id = "bear", variant = "basic", rarity_id = "common" }, CAP)).to.equal(
                false
            )
            expect(View.isEnchantable({ id = "bear", variant = "basic" }, { allowAll = true })).to.equal(
                true
            )
        end)
    end)
end
