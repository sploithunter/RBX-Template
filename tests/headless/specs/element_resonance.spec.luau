--[[
    Feature 6: Element resonance matrix — [unit] scenarios.
    Run: mise run test-headless
]]

local ElementResonance = loadModule("src/Shared/Game/ElementResonance.lua")
local elementsConfig = loadModule("configs/elements.lua")

return function()
    describe("ElementResonance.multiplier", function()
        local function m(element, realm)
            return ElementResonance.multiplier(element, realm, elementsConfig)
        end

        it("light: home (heaven) 1.2, opposing (hell) 1.5, neutral 1.0", function()
            expect(m("light", "heaven")).to.equal(1.2)
            expect(m("light", "hell")).to.equal(1.5)
            expect(m("light", "neutral")).to.equal(1.0)
        end)

        it("shadow mirrors light: opposing (heaven) 1.5, home (hell) 1.2, neutral 1.0", function()
            expect(m("shadow", "heaven")).to.equal(1.5)
            expect(m("shadow", "hell")).to.equal(1.2)
            expect(m("shadow", "neutral")).to.equal(1.0)
        end)

        it("chaotic is flat 1.3 across realms", function()
            expect(m("chaotic", "heaven")).to.equal(1.3)
            expect(m("chaotic", "hell")).to.equal(1.3)
            expect(m("chaotic", "neutral")).to.equal(1.3)
        end)

        it("neutral is flat 1.0 across realms", function()
            expect(m("neutral", "heaven")).to.equal(1.0)
            expect(m("neutral", "hell")).to.equal(1.0)
            expect(m("neutral", "neutral")).to.equal(1.0)
        end)

        it("unknown element or realm defaults to 1.0", function()
            expect(m("sparkly", "heaven")).to.equal(1.0)
            expect(m("light", "void")).to.equal(1.0)
        end)
    end)
end
