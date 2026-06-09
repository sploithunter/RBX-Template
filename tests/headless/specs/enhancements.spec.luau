--[[
    Enhancements (pure core) — [unit] grades, usability, compatibility, aggregation.
    Run: mise run test-headless
]]

local Enhancements = loadModule("src/Shared/Game/Enhancements.lua")
local PowerStats = loadModule("src/Shared/Game/PowerStats.lua")
local cfg = loadModule("configs/enhancements.lua")
local powersCfg = loadModule("configs/powers.lua")

local PYRO_DMG = { type = "damage", origins = { "pyromancer" } }
local GEO_CRYO_RCH = { type = "recharge", origins = { "geomancer", "cryomancer" } }

return function()
    describe("Enhancement records (grades + validity)", function()
        it("classifies single vs dual", function()
            expect(Enhancements.isSingle(PYRO_DMG)).to.equal(true)
            expect(Enhancements.isDual(PYRO_DMG)).to.equal(false)
            expect(Enhancements.isDual(GEO_CRYO_RCH)).to.equal(true)
        end)

        it("rejects malformed records", function()
            expect(Enhancements.isValid(cfg, { type = "damage", origins = {} })).to.equal(false)
            expect(Enhancements.isValid(cfg, { type = "nope", origins = { "pyromancer" } })).to.equal(
                false
            )
            expect(
                Enhancements.isValid(
                    cfg,
                    { type = "damage", origins = { "pyromancer", "pyromancer" } }
                )
            ).to.equal(false)
            expect(Enhancements.isValid(cfg, { type = "damage", origins = { "not_an_origin" } })).to.equal(
                false
            )
        end)

        it("single-origin is worth MORE than dual-origin (Jason's rule)", function()
            local single = Enhancements.value(cfg, PYRO_DMG)
            local dual = Enhancements.value(cfg, GEO_CRYO_RCH)
            expect(single > dual).to.equal(true)
            expect(single).to.equal(cfg.values.single)
            expect(dual).to.equal(cfg.values.dual)
        end)
    end)

    describe("Usability (player origin must be among the enhancement's origins)", function()
        it("single: only the matching origin", function()
            expect(Enhancements.usableBy(PYRO_DMG, "pyromancer")).to.equal(true)
            expect(Enhancements.usableBy(PYRO_DMG, "cryomancer")).to.equal(false)
        end)

        it("dual: either of its two origins", function()
            expect(Enhancements.usableBy(GEO_CRYO_RCH, "geomancer")).to.equal(true)
            expect(Enhancements.usableBy(GEO_CRYO_RCH, "cryomancer")).to.equal(true)
            expect(Enhancements.usableBy(GEO_CRYO_RCH, "sandwalker")).to.equal(false)
        end)
    end)

    describe("Type-vs-power compatibility", function()
        local kinds = powersCfg.effect_kinds

        it("healing fits a heal power, not a shield power", function()
            -- restoring_sands = heal family; dune_shield = absorb family (live config)
            local heal = powersCfg.powers.restoring_sands
            local shield = powersCfg.powers.dune_shield
            expect((Enhancements.compatibleWith(cfg, "healing", heal, kinds))).to.equal(true)
            local ok, reason = Enhancements.compatibleWith(cfg, "healing", shield, kinds)
            expect(ok).to.equal(false)
            expect(reason).to.equal("wrong_family")
        end)

        it("range is BLOCKED on single-target powers (melee rule)", function()
            local singleTarget = powersCfg.powers.dune_shield -- target = single_pet
            local ok, reason = Enhancements.compatibleWith(cfg, "range", singleTarget, kinds)
            expect(ok).to.equal(false)
            expect(reason).to.equal("not_aoe")
        end)

        it("recharge fits anything (families = *)", function()
            expect(
                (Enhancements.compatibleWith(cfg, "recharge", powersCfg.powers.dune_shield, kinds))
            ).to.equal(true)
            expect(
                (
                    Enhancements.compatibleWith(
                        cfg,
                        "recharge",
                        powersCfg.powers.restoring_sands,
                        kinds
                    )
                )
            ).to.equal(true)
        end)
    end)

    describe("Aggregation (per-axis additive)", function()
        it("sums same-axis values and skips empty/inherent slots", function()
            local slots = {
                { inherent = true },
                { enh = PYRO_DMG },
                {},
                { enh = { type = "damage", origins = { "geomancer", "pyromancer" } } },
                { enh = GEO_CRYO_RCH },
            }
            local axes = Enhancements.aggregate(cfg, slots)
            -- damage: single (0.33) + dual (0.20) = 0.53; recharge: dual (0.20)
            expect(math.abs(axes.damage - (cfg.values.single + cfg.values.dual)) < 1e-9).to.equal(
                true
            )
            expect(math.abs(axes.recharge - cfg.values.dual) < 1e-9).to.equal(true)
        end)

        it("returns empty for no slots", function()
            expect(next(Enhancements.aggregate(cfg, {}))).to.equal(nil)
        end)
    end)

    describe("Display + badge", function()
        it("names singles and duals", function()
            expect(Enhancements.displayName(cfg, PYRO_DMG)).to.equal("Pyro Damage")
            expect(Enhancements.displayName(cfg, GEO_CRYO_RCH)).to.equal("Geo/Cryo Recharge")
        end)

        it("badge: single = same color group, dual = mixed", function()
            local s = Enhancements.badgeSpec(cfg, PYRO_DMG)
            expect(s.discOrigin).to.equal("pyromancer")
            expect(s.ringOrigin).to.equal("pyromancer")
            expect(s.single).to.equal(true)
            local d = Enhancements.badgeSpec(cfg, GEO_CRYO_RCH)
            expect(d.discOrigin).to.equal("geomancer")
            expect(d.ringOrigin).to.equal("cryomancer")
            expect(d.single).to.equal(false)
        end)
    end)

    describe("Effects at cast (PowerStats ctx.enhancements)", function()
        it("damage multiplies, recharge divides; unboosted axes untouched", function()
            local power = { rechargeBase = 300, damageBase = 100, durationBase = 60 }
            local eff = PowerStats.resolveEffective(power, {
                enhancements = { damage = 0.33, recharge = 0.33 },
            })
            expect(math.abs(eff.damage - 133) < 1e-9).to.equal(true)
            expect(math.abs(eff.recharge - 300 / 1.33) < 1e-6).to.equal(true)
            expect(eff.duration).to.equal(60) -- no duration enhancement slotted
        end)

        it("two singles on one axis stack additively (x1.66)", function()
            local eff = PowerStats.resolveEffective(
                { damageBase = 100 },
                { enhancements = { damage = 0.66 } }
            )
            expect(math.abs(eff.damage - 166) < 1e-9).to.equal(true)
        end)

        it("accuracy boost applies but stays clamped to 1", function()
            local eff = PowerStats.resolveEffective(
                { accuracyBase = 0.9 },
                { enhancements = { accuracy = 0.33 } }
            )
            expect(eff.accuracy).to.equal(1) -- 0.9 * 1.33 clamped
            local eff2 = PowerStats.resolveEffective(
                { accuracyBase = 0.6 },
                { enhancements = { accuracy = 0.33 } }
            )
            expect(math.abs(eff2.accuracy - 0.6 * 1.33) < 1e-9).to.equal(true)
        end)
    end)

    describe("Config integrity", function()
        it("every type's symbol + axis are present and axis is a PowerStats axis", function()
            local axes = {
                damage = true,
                accuracy = true,
                recharge = true,
                duration = true,
                radius = true,
                magnitude = true,
                heal = true,
                shield = true,
            }
            for name, def in pairs(cfg.types) do
                expect(type(def.symbol)).to.equal("string")
                if not axes[def.axis] then
                    error(("type '%s' has unknown axis '%s'"):format(name, tostring(def.axis)))
                end
            end
        end)
    end)
end
