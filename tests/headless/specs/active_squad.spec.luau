--[[
    Feature 9: Active squad hierarchy — [unit] scenarios.
    Run: mise run test-headless
]]

local ActiveSquad = loadModule("src/Shared/Game/ActiveSquad.lua")
local squadConfig = loadModule("configs/squad.lua")

return function()
    describe("ActiveSquad.canDeploy", function()
        local max = squadConfig.limits.active_squad

        it("allows deploy when below max", function()
            expect(ActiveSquad.canDeploy(2, max).ok).to.equal(true)
        end)

        it("rejects deploy when at max (active_squad_full)", function()
            local r = ActiveSquad.canDeploy(max, max)
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("active_squad_full")
        end)

        it("a stacked pet occupies one slot (size counts entries, not pet counts)", function()
            -- 4 entries (one of them a 30-pet stack) -> a 5th still fits
            expect(ActiveSquad.canDeploy(4, max).ok).to.equal(true)
        end)
    end)

    describe("ActiveSquad.canSwap", function()
        local cooldown = squadConfig.swap_cooldown_seconds

        it("is instant out of combat", function()
            expect(ActiveSquad.canSwap(false, 10000, 10001, cooldown).ok).to.equal(true)
        end)

        it("is allowed in combat when no prior swap", function()
            expect(ActiveSquad.canSwap(true, nil, 10000, cooldown).ok).to.equal(true)
        end)

        it("is blocked in combat within the cooldown window", function()
            local r = ActiveSquad.canSwap(true, 10000 - 2, 10000, cooldown) -- 2s ago, 5s cd
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("swap_cooldown_active")
            expect(r.remaining).to.equal(3)
        end)

        it("is allowed in combat after the cooldown elapses", function()
            expect(ActiveSquad.canSwap(true, 10000 - 6, 10000, cooldown).ok).to.equal(true) -- 6s ago
        end)
    end)
end
