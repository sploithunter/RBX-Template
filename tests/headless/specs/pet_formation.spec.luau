--[[
    Issue #4: service-owned pet-follow positioning — [unit] scenarios.
    Run: mise run test-headless
]]

local PetFormation = loadModule("src/Shared/Game/PetFormation.lua")
local config = loadModule("configs/pet_follow.lua")

local formation = config.formation

-- player at origin facing +z; right is +x; so "behind" (-look) is -z.
local frame = {
    position = { x = 0, y = 0, z = 0 },
    look = { x = 0, y = 0, z = 1 },
    right = { x = 1, y = 0, z = 0 },
}

return function()
    describe("PetFormation.slotOffset (rows)", function()
        it("places a lone pet centered, one follow_distance behind", function()
            local off = PetFormation.slotOffset(1, 1, formation)
            expect(off.x).to.equal(0)
            expect(off.y).to.equal(formation.height)
            expect(off.back).to.equal(formation.follow_distance)
        end)

        it("centers a full first row symmetrically", function()
            -- 3 per row, col_spacing 4 -> x = -4, 0, +4
            expect(PetFormation.slotOffset(1, 3, formation).x).to.equal(-formation.col_spacing)
            expect(PetFormation.slotOffset(2, 3, formation).x).to.equal(0)
            expect(PetFormation.slotOffset(3, 3, formation).x).to.equal(formation.col_spacing)
        end)

        it("all first-row pets share the same follow distance", function()
            expect(PetFormation.slotOffset(1, 3, formation).back).to.equal(
                formation.follow_distance
            )
            expect(PetFormation.slotOffset(3, 3, formation).back).to.equal(
                formation.follow_distance
            )
        end)

        it("wraps to a second row once per_row is exceeded", function()
            -- pet 4 of 4 -> row 1, alone -> centered, one row_spacing further back
            local off = PetFormation.slotOffset(4, 4, formation)
            expect(off.x).to.equal(0)
            expect(off.back).to.equal(formation.follow_distance + formation.row_spacing)
        end)
    end)

    describe("PetFormation.targetPosition", function()
        it("maps the local offset into world space (origin, facing +z)", function()
            -- pet 1 of 1: x 0, back follow_distance -> world (0, height, -follow_distance)
            local pos = PetFormation.targetPosition(frame, 1, 1, formation)
            expect(pos.x).to.equal(0)
            expect(pos.y).to.equal(formation.height)
            expect(pos.z).to.equal(-formation.follow_distance)
        end)

        it("lateral offset follows the right vector", function()
            -- pet 1 of 3 sits to the player's left (x = -col_spacing)
            local pos = PetFormation.targetPosition(frame, 1, 3, formation)
            expect(pos.x).to.equal(-formation.col_spacing)
            expect(pos.z).to.equal(-formation.follow_distance)
        end)
    end)

    describe("PetFormation.slotOffset (circle)", function()
        local circle = table.clone(formation)
        circle.mode = "circle"

        it("places a lone pet centered behind at follow_distance + radius", function()
            local off = PetFormation.slotOffset(1, 1, circle)
            expect(off.x).to.equal(0)
            expect(off.back).to.near(circle.follow_distance + circle.radius, 1e-6)
        end)

        it("is laterally symmetric across the arc", function()
            -- first and last pet mirror each other on x
            local first = PetFormation.slotOffset(1, 5, circle)
            local last = PetFormation.slotOffset(5, 5, circle)
            expect(first.x).to.near(-last.x, 1e-6)
        end)
    end)

    describe("PetFormation.floatOffset", function()
        it("is zero at phase 0 and within amplitude", function()
            expect(PetFormation.floatOffset(0, config.float)).to.near(0, 1e-6)
            -- quarter period -> peak amplitude
            expect(PetFormation.floatOffset(config.float.period / 4, config.float)).to.near(
                config.float.amplitude,
                1e-6
            )
        end)
    end)

    describe("PetFormation.attackOffset", function()
        local attack = {
            style = "orbit",
            ring_radius = 6,
            ring_height = 3,
            orbit_speed = 2,
            lunge_distance = 3,
            lunge_speed = 5,
        }

        local function mag2(o)
            return math.sqrt(o.x * o.x + o.z * o.z)
        end

        it("spreads pets evenly on the ring (no two share a point)", function()
            local a = PetFormation.attackOffset(1, 4, 0, attack)
            local b = PetFormation.attackOffset(2, 4, 0, attack)
            expect(mag2(a)).to.near(attack.ring_radius, 1e-6)
            expect(mag2(b)).to.near(attack.ring_radius, 1e-6)
            expect((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 > 0.01).to.equal(true)
        end)

        it("sits at the ring height", function()
            expect(PetFormation.attackOffset(1, 3, 0, attack).y).to.equal(attack.ring_height)
        end)

        it("orbit rotates the wheel over time", function()
            local t0 = PetFormation.attackOffset(1, 4, 0, attack)
            local t1 = PetFormation.attackOffset(1, 4, 1, attack)
            expect((t0.x - t1.x) ^ 2 + (t0.z - t1.z) ^ 2 > 0.01).to.equal(true)
        end)

        it("static_ring holds position (no rotation)", function()
            local s = { style = "static_ring", ring_radius = 6, ring_height = 3 }
            local a = PetFormation.attackOffset(1, 4, 0, s)
            local b = PetFormation.attackOffset(1, 4, 5, s)
            expect(a.x).to.near(b.x, 1e-6)
            expect(a.z).to.near(b.z, 1e-6)
        end)

        it("lunge keeps the radius within [ring - lunge, ring]", function()
            local l = {
                style = "lunge",
                ring_radius = 6,
                ring_height = 3,
                lunge_distance = 3,
                lunge_speed = 5,
            }
            for step = 0, 10 do
                local r = mag2(PetFormation.attackOffset(1, 3, step * 0.2, l))
                local within = r <= l.ring_radius + 1e-6
                    and r >= l.ring_radius - l.lunge_distance - 1e-6
                expect(within).to.equal(true)
            end
        end)
    end)

    describe("PetFormation.resolve (size-aware)", function()
        local fm = {
            mode = "conga",
            follow_distance = 6,
            height = 2,
            size = { gap = 1 },
            risers = { per_row = 3, row_gap = 2, col_spacing = 3 },
            arc = { radius = 10, arc_step_degrees = 20, spread_factor = 0, depth_factor = 0 },
        }

        local function pets(...)
            local t = {}
            for i, f in ipairs({ ... }) do
                t[i] = { footprint = f, id = "p" .. i }
            end
            return t
        end

        it("sorts smallest -> front regardless of input order", function()
            local r = PetFormation.resolve(pets(7, 2, 5), fm)
            expect(r[1].pet.footprint).to.equal(2)
            expect(r[2].pet.footprint).to.equal(5)
            expect(r[3].pet.footprint).to.equal(7)
            expect(r[1].offset.back < r[3].offset.back).to.equal(true)
        end)

        describe("conga", function()
            it("is single file with size-scaled accumulating gaps", function()
                -- footprints sorted {2,2,4}: back = 7, 10, 14; x all 0
                local r = PetFormation.resolve(pets(2, 4, 2), fm)
                expect(r[1].offset.x).to.equal(0)
                expect(r[1].offset.back).to.near(7)
                expect(r[2].offset.back).to.near(10)
                expect(r[3].offset.back).to.near(14)
            end)

            it("a huge neighbour widens the gap (size-aware spacing)", function()
                local small = PetFormation.resolve(pets(2, 2), fm)
                local huge = PetFormation.resolve(pets(2, 8), fm)
                local gapSmall = small[2].offset.back - small[1].offset.back
                local gapHuge = huge[2].offset.back - huge[1].offset.back
                expect(gapHuge > gapSmall).to.equal(true)
            end)
        end)

        describe("risers", function()
            local rs = table.clone(fm)
            rs.mode = "risers"
            it("anchors the largest in the back row, behind the front row", function()
                -- 3 small front row + 1 huge -> huge alone in the back row, further back
                local r = PetFormation.resolve(pets(1, 1, 1, 9), rs)
                expect(r[4].pet.footprint).to.equal(9)
                expect(r[4].offset.back > r[1].offset.back).to.equal(true)
            end)
        end)

        describe("arc", function()
            local ac = table.clone(fm)
            ac.mode = "arc"
            it("is concave: centre closest, ends curl back, huge at the ends", function()
                local r = PetFormation.resolve(pets(1, 2, 3, 4, 5), ac)
                expect(r[1].offset.back < r[2].offset.back).to.equal(true)
                expect(r[2].offset.back < r[4].offset.back).to.equal(true)
                expect(r[5].pet.footprint).to.equal(5)
                local maxBack = 0
                for _, e in ipairs(r) do
                    maxBack = math.max(maxBack, e.offset.back)
                end
                expect(r[5].offset.back).to.near(maxBack)
            end)

            it("is laterally symmetric about the centre (odd count)", function()
                local r = PetFormation.resolve(pets(1, 1, 1, 1, 1), ac)
                expect(r[2].offset.x).to.near(-r[3].offset.x)
            end)

            it("stays symmetric for an even count (straddles the centre, no centre pet)", function()
                -- 4 equal pets -> slots ±0.5, ±1.5: laterals cancel and none sit at x=0
                local r = PetFormation.resolve(pets(1, 1, 1, 1), ac)
                local sum, anyCentre = 0, false
                for _, e in ipairs(r) do
                    sum = sum + e.offset.x
                    if math.abs(e.offset.x) < 1e-6 then
                        anyCentre = true
                    end
                end
                expect(sum).to.near(0)
                expect(anyCentre).to.equal(false)
            end)
        end)
    end)

    describe("PetFormation.moveSpeedMultiplier", function()
        it("defaults nil player/pet to 1 (returns base)", function()
            expect(PetFormation.moveSpeedMultiplier(nil, nil, { base = 1 })).to.near(1)
            expect(PetFormation.moveSpeedMultiplier(nil, nil, { base = 2, max = 5 })).to.near(2)
        end)

        it("multiplies base * player * pet", function()
            expect(PetFormation.moveSpeedMultiplier(2, 1.5, { base = 1, max = 10 })).to.near(3)
        end)

        it("clamps to [min, max]", function()
            expect(PetFormation.moveSpeedMultiplier(0.01, 1, { base = 1, min = 0.25, max = 4 })).to.near(
                0.25
            )
            expect(PetFormation.moveSpeedMultiplier(100, 1, { base = 1, min = 0.25, max = 4 })).to.near(
                4
            )
        end)
    end)

    describe("PetFormation.shouldSnap", function()
        it("snaps past the threshold, lerps within it", function()
            expect(PetFormation.shouldSnap(100, 60)).to.equal(true)
            expect(PetFormation.shouldSnap(20, 60)).to.equal(false)
            expect(PetFormation.shouldSnap(60, 60)).to.equal(false)
        end)

        it("never snaps without a threshold", function()
            expect(PetFormation.shouldSnap(1e9, nil)).to.equal(false)
        end)
    end)
end
