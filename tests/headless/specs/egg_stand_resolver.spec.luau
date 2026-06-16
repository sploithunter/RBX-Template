--[[
    EggStandResolver — [unit] realm + stand-name -> egg id, from the realm_area_eggs matrix.
    Run: mise run test-headless
]]

local EggStandResolver = loadModule("src/Shared/Game/EggStandResolver.lua")
local petsConfig = loadModule("configs/pets.lua")

local MATRIX = petsConfig.realm_area_eggs

return function()
    describe("EggStandResolver.eggFor (matrix lookup)", function()
        it("migrates the Basic stands by name substring (base realm)", function()
            expect(EggStandResolver.eggFor("base", "BasicIce", MATRIX)).to.equal("ice_egg")
            expect(EggStandResolver.eggFor("base", "BasicSand", MATRIX)).to.equal("sand_egg")
            expect(EggStandResolver.eggFor("base", "BasicEmber", MATRIX)).to.equal("ember_egg")
            expect(EggStandResolver.eggFor("base", "BasicEarth", MATRIX)).to.equal("earth_egg")
        end)

        it("resolves a Heaven lava-area stand to the solar egg", function()
            expect(EggStandResolver.eggFor("heaven", "Lava", MATRIX)).to.equal("solar_egg")
            expect(EggStandResolver.eggFor("heaven", "HeavenLavaStand", MATRIX)).to.equal(
                "solar_egg"
            )
        end)

        -- Regression: the REAL authored stand names in the live map. Heaven uses egg-themed names
        -- (Aurora/Bloom/Guilded/Solar); Home/Hell use area names (BasicEmber/Ice/Sand/Earth). The
        -- "ember" key must beat the accidental "ice" inside "bas-ICE-mber" (3 chars) so a Fire stand
        -- never resolves to the ice egg.
        it("resolves the authored Heaven egg-themed stand names", function()
            expect(EggStandResolver.eggFor("heaven", "Aurora", MATRIX)).to.equal("aurora_egg")
            expect(EggStandResolver.eggFor("heaven", "Bloom", MATRIX)).to.equal("bloom_egg")
            expect(EggStandResolver.eggFor("heaven", "Guilded", MATRIX)).to.equal("gilded_egg")
            expect(EggStandResolver.eggFor("heaven", "Solar", MATRIX)).to.equal("solar_egg")
        end)

        it(
            "resolves Hell BasicEmber to the fire egg, not the ice egg (ember beats stray 'ice')",
            function()
                expect(EggStandResolver.eggFor("hell", "BasicEmber", MATRIX)).to.equal(
                    "infernal_egg"
                )
                expect(EggStandResolver.eggFor("hell", "BasicIce", MATRIX)).to.equal(
                    "black_ice_egg"
                )
                expect(EggStandResolver.eggFor("hell", "BasicSand", MATRIX)).to.equal("ash_egg")
                expect(EggStandResolver.eggFor("hell", "BasicEarth", MATRIX)).to.equal("blight_egg")
            end
        )

        it("is case-insensitive and returns the matched area", function()
            local egg, area = EggStandResolver.eggFor("base", "myICEpedestal", MATRIX)
            expect(egg).to.equal("ice_egg")
            expect(area).to.equal("ice")
        end)

        it("returns nil for an unknown realm, unknown area, or a name matching nothing", function()
            expect(EggStandResolver.eggFor("limbo", "Lava", MATRIX)).never.to.be.ok() -- no such realm
            expect(EggStandResolver.eggFor("base", "Lava", MATRIX)).never.to.be.ok() -- lava is heaven/hell-only
            expect(EggStandResolver.eggFor("base", "Pedestal", MATRIX)).never.to.be.ok()
        end)

        it("guards bad input", function()
            expect(EggStandResolver.eggFor(nil, "BasicIce", MATRIX)).never.to.be.ok()
            expect(EggStandResolver.eggFor("base", nil, MATRIX)).never.to.be.ok()
            expect(EggStandResolver.eggFor("base", "BasicIce", nil)).never.to.be.ok()
        end)
    end)
end
