--[[
    Aggro/threat table: accumulate, clamp, decay-to-zero, top-with-filter, pacify.
    Run: mise run test-headless
]]

local AggroTable = loadModule("src/Shared/Game/AggroTable.lua")

return function()
    describe("AggroTable.add / get", function()
        it("accumulates aggro per attacker", function()
            local t = AggroTable.new()
            AggroTable.add(t, "petA", 10)
            AggroTable.add(t, "petA", 5)
            AggroTable.add(t, "petB", 3)
            expect(AggroTable.get(t, "petA")).to.equal(15)
            expect(AggroTable.get(t, "petB")).to.equal(3)
            expect(AggroTable.get(t, "nobody")).to.equal(0)
        end)

        it("clamps at zero and drops the entry (never negative)", function()
            local t = AggroTable.new()
            AggroTable.add(t, "petA", 4)
            AggroTable.add(t, "petA", -10)
            expect(AggroTable.get(t, "petA")).to.equal(0)
            expect(AggroTable.size(t)).to.equal(0)
        end)

        it("ignores nil keys and zero amounts", function()
            local t = AggroTable.new()
            AggroTable.add(t, nil, 5)
            AggroTable.add(t, "petA", 0)
            expect(AggroTable.size(t)).to.equal(0)
        end)
    end)

    describe("AggroTable.top", function()
        it("returns the highest-aggro key above the floor", function()
            local t = AggroTable.new()
            AggroTable.add(t, "tank", 40)
            AggroTable.add(t, "dps", 25)
            local key, val = AggroTable.top(t, 0)
            expect(key).to.equal("tank")
            expect(val).to.equal(40)
        end)

        it("returns nil when nothing exceeds the floor (disengage)", function()
            local t = AggroTable.new()
            AggroTable.add(t, "petA", 0.3)
            expect(AggroTable.top(t, 0.5)).to.equal(nil)
        end)

        it("skips entries filtered out by isValid (e.g. downed pets)", function()
            local t = AggroTable.new()
            AggroTable.add(t, "downed", 100)
            AggroTable.add(t, "alive", 10)
            local key = AggroTable.top(t, 0, function(k)
                return k ~= "downed"
            end)
            expect(key).to.equal("alive")
        end)
    end)

    describe("AggroTable.decay", function()
        it("bleeds every entry by rate*dt and removes those that hit zero", function()
            local t = AggroTable.new()
            AggroTable.add(t, "petA", 10)
            AggroTable.add(t, "petB", 2)
            AggroTable.decay(t, 1, 3) -- drop 3 each
            expect(AggroTable.get(t, "petA")).to.equal(7)
            expect(AggroTable.get(t, "petB")).to.equal(0) -- 2-3 -> removed
            expect(AggroTable.size(t)).to.equal(1)
        end)

        it("a non-refreshed top entry eventually decays below the disengage floor", function()
            local t = AggroTable.new()
            AggroTable.add(t, "petA", 5)
            for _ = 1, 20 do
                AggroTable.decay(t, 0.1, 3) -- 0.3/tick * 20 = 6 > 5
            end
            expect(AggroTable.top(t, 0.5)).to.equal(nil)
        end)
    end)

    describe("AggroTable.clear (pacify)", function()
        it("removes an attacker entirely", function()
            local t = AggroTable.new()
            AggroTable.add(t, "petA", 50)
            AggroTable.clear(t, "petA")
            expect(AggroTable.get(t, "petA")).to.equal(0)
            expect(AggroTable.top(t, 0)).to.equal(nil)
        end)
    end)
end
