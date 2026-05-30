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
end
