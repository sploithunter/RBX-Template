--[[
    Feature 6: Element resonance matrix — [unit] scenarios.
    Run: mise run test-headless
]]

local ElementResonance = loadModule("src/Shared/Game/ElementResonance.lua")
local elementsConfig = loadModule("configs/elements.lua")

local biomeCfg = loadModule("configs/elements.lua")

return function()
    describe("ElementResonance.biomeMultiplier (zone RPS)", function()
        it("advantage in the zone your element beats", function()
            expect(ElementResonance.biomeMultiplier("lava", "grass", biomeCfg)).to.equal(1.25)
            expect(ElementResonance.biomeMultiplier("grass", "desert", biomeCfg)).to.equal(1.25)
            expect(ElementResonance.biomeMultiplier("desert", "ice", biomeCfg)).to.equal(1.25)
            expect(ElementResonance.biomeMultiplier("ice", "lava", biomeCfg)).to.equal(1.25)
        end)

        it("disadvantage in the zone that beats you", function()
            expect(ElementResonance.biomeMultiplier("grass", "lava", biomeCfg)).to.equal(0.8)
            expect(ElementResonance.biomeMultiplier("lava", "ice", biomeCfg)).to.equal(0.8)
        end)

        it("home and opposite are neutral", function()
            expect(ElementResonance.biomeMultiplier("grass", "grass", biomeCfg)).to.equal(1)
            expect(ElementResonance.biomeMultiplier("grass", "ice", biomeCfg)).to.equal(1)
            expect(ElementResonance.biomeMultiplier("lava", "desert", biomeCfg)).to.equal(1)
        end)

        it("special/unknown zones are neutral by construction", function()
            expect(ElementResonance.biomeMultiplier("lava", "heaven_3", biomeCfg)).to.equal(1)
            expect(ElementResonance.biomeMultiplier(nil, "grass", biomeCfg)).to.equal(1)
            expect(ElementResonance.biomeMultiplier("lava", "grass", nil)).to.equal(1)
        end)
    end)

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
