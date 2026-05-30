--[[
    Feature 3: Layer access & portals — [unit] scenarios.
    Run: mise run test-headless
]]

local LayerAccess = loadModule("src/Shared/Game/LayerAccess.lua")
local layersConfig = loadModule("configs/layers.lua")

return function()
    describe("LayerAccess.canAccess", function()
        local function access(soul, balance, layer, opts)
            return LayerAccess.canAccess(soul, balance, layer, layersConfig, opts)
        end

        it("a new player (soul 0) can access base", function()
            expect(access(0, 0, "base").ok).to.equal(true)
        end)

        it("rejects Heaven 1 when Soul is too low (no deduction)", function()
            local r = access(10, 1000, "heaven_1")
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("soul_too_low")
        end)

        it("rejects Heaven 1 when tokens are insufficient", function()
            local r = access(50, 50, "heaven_1")
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("insufficient_tokens")
            expect(r.cost).to.equal(100)
            expect(r.currency).to.equal("light_tokens")
        end)

        it("allows Heaven 1 with enough Soul and tokens", function()
            local r = access(25, 150, "heaven_1")
            expect(r.ok).to.equal(true)
            expect(r.cost).to.equal(100)
            expect(r.currency).to.equal("light_tokens")
        end)

        it("rejects Hell 1 with positive Soul (wrong direction)", function()
            local r = access(30, 1000, "hell_1")
            expect(r.ok).to.equal(false)
            expect(r.reason).to.equal("soul_wrong_direction")
        end)

        it("allows Hell 1 with sufficiently negative Soul + tokens", function()
            expect(access(-25, 150, "hell_1").ok).to.equal(true)
        end)

        it("cross-path visit portal ignores Soul (token cost still applies)", function()
            -- Heaven-aligned player visiting Hell 1 via a visit portal
            expect(access(50, 100, "hell_1", { crossPathVisit = true }).ok).to.equal(true)
            -- but still needs the tokens
            expect(access(50, 50, "hell_1", { crossPathVisit = true }).reason).to.equal(
                "insufficient_tokens"
            )
        end)

        it("unknown layer is rejected", function()
            expect(access(0, 0, "valhalla").reason).to.equal("unknown_layer")
        end)
    end)

    describe("LayerAccess.accessibleLayers", function()
        it("a fresh player can only access base", function()
            local layers = LayerAccess.accessibleLayers(0, {}, layersConfig)
            expect(#layers).to.equal(1)
            expect(layers[1]).to.equal("base")
        end)

        it("a Heaven-aligned, token-rich player can access base + Heaven 1", function()
            local layers = LayerAccess.accessibleLayers(25, { light_tokens = 150 }, layersConfig)
            -- base + heaven_1 (soul 25 >= 20, tokens 150 >= 100); heaven_2 needs soul 40
            local set = {}
            for _, l in ipairs(layers) do
                set[l] = true
            end
            expect(set.base).to.equal(true)
            expect(set.heaven_1).to.equal(true)
            expect(set.heaven_2).to.equal(nil)
        end)
    end)
end
