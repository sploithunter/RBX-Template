--[[
    PetFormation — pure functional core for pet-follow positioning (issue #4).

    No Roblox APIs. Computes where each equipped pet should sit relative to the
    player, from a config-driven formation. The service (PetFollowService) feeds
    it the player's frame each tick and drives an AlignPosition per pet to the
    returned world position — replacing the cloned control-box chain.

    A "frame" is a plain table describing the player's root orientation:
        { position = {x,y,z}, look = {x,y,z}, right = {x,y,z} }
    (look = unit forward, right = unit right; up is assumed world +Y.)

      slotOffset(index, count, formation)            -> { x, y, back }
          local offset: x = lateral (along right), y = height (up),
          back = distance behind the player (along -look). 1-based index.
      targetPosition(frame, index, count, formation)  -> { x, y, z } world
      floatOffset(phase, floatConfig)                 -> number (vertical bob)
]]

local PetFormation = {}

local function degToRad(d)
    return d * math.pi / 180
end

-- Local offset for pet `index` of `count`, per the formation mode.
function PetFormation.slotOffset(index, count, formation)
    local i = index - 1 -- 0-based
    if formation.mode == "circle" then
        local angle
        if count <= 1 then
            angle = 0
        else
            local t = i / (count - 1) -- 0..1
            local arc = degToRad(formation.arc_degrees)
            angle = -arc / 2 + t * arc
        end
        return {
            x = formation.radius * math.sin(angle),
            y = formation.height,
            back = formation.follow_distance + formation.radius * math.cos(angle),
        }
    end

    -- default: "rows" — a centered marching grid behind the player.
    local perRow = formation.per_row
    local row = math.floor(i / perRow)
    local col = i % perRow
    local petsInRow = math.min(perRow, count - row * perRow)
    local center = (petsInRow - 1) / 2
    return {
        x = (col - center) * formation.col_spacing,
        y = formation.height,
        back = formation.follow_distance + row * formation.row_spacing,
    }
end

-- World target for pet `index`, applying the local offset to the player frame.
-- world = position + right*x + up*y + (-look)*back
function PetFormation.targetPosition(frame, index, count, formation)
    local off = PetFormation.slotOffset(index, count, formation)
    local p, look, right = frame.position, frame.look, frame.right
    return {
        x = p.x + right.x * off.x - look.x * off.back,
        y = p.y + off.y - look.y * off.back + right.y * off.x,
        z = p.z + right.z * off.x - look.z * off.back,
    }
end

-- Vertical bob from a phase (e.g. elapsed time). Deterministic; no clock here.
function PetFormation.floatOffset(phase, floatConfig)
    if not floatConfig or floatConfig.amplitude == 0 then
        return 0
    end
    return floatConfig.amplitude * math.sin((2 * math.pi / floatConfig.period) * phase)
end

return PetFormation
