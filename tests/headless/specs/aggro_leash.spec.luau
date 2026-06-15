--[[
    AggroLeash — distance-banded aggro persistence (enemy stays angry until the squad is far).
    Run: mise run test-headless
]]

local AggroLeash = loadModule("src/Shared/Game/AggroLeash.lua")

local CFG = {
    engage_radius = 160,
    give_up_range = 400,
    chase_decay_mult = 3,
    leave_area_decay_mult = 6,
}

return function()
    describe("AggroLeash.decayMult", function()
        it("is 1x while locked on (within engage_radius), in territory", function()
            expect(AggroLeash.decayMult(0, true, CFG)).to.equal(1)
            expect(AggroLeash.decayMult(160, true, CFG)).to.equal(1)
        end)

        it("ramps to chase_decay_mult once past engage_radius", function()
            expect(AggroLeash.decayMult(161, true, CFG)).to.equal(3)
            expect(AggroLeash.decayMult(399, true, CFG)).to.equal(3)
        end)

        it("uses leave_area_decay_mult (the larger) once out of the home area", function()
            -- out of area but still close: the area penalty still applies (forgets a fleeing-into-
            -- the-next-biome target fast)
            expect(AggroLeash.decayMult(0, false, CFG)).to.equal(6)
            expect(AggroLeash.decayMult(300, false, CFG)).to.equal(6) -- max(3, 6)
        end)

        it("falls back to sane defaults when cfg is missing", function()
            expect(AggroLeash.decayMult(0, true, nil)).to.equal(1)
            expect(AggroLeash.decayMult(99999, true, nil)).to.equal(3) -- default chase_decay_mult
        end)
    end)

    describe("AggroLeash.verdict", function()
        it("engages whenever there is a live threat target in range", function()
            expect(AggroLeash.verdict(10, true, CFG)).to.equal("engage")
            expect(AggroLeash.verdict(390, true, CFG)).to.equal("engage")
        end)

        it(
            "locks on (keeps pursuing) when threat bled out but still within engage_radius",
            function()
                expect(AggroLeash.verdict(50, false, CFG)).to.equal("lock")
                expect(AggroLeash.verdict(160, false, CFG)).to.equal("lock")
            end
        )

        it("drops when threat is gone AND beyond engage_radius", function()
            expect(AggroLeash.verdict(161, false, CFG)).to.equal("drop")
        end)

        it("drops past give_up_range even with a live target (teleport / new world)", function()
            expect(AggroLeash.verdict(401, true, CFG)).to.equal("drop")
            expect(AggroLeash.verdict(9999, true, CFG)).to.equal("drop")
        end)
    end)
end
