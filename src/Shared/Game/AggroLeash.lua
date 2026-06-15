--[[
    AggroLeash — pure persistence math for enemy aggro (Halo & Horns combat).

    The threat table (src/Shared/Game/AggroTable) decides WHO an enemy is angry at. This module
    decides HOW LONG it stays angry as that target moves away — replacing the old tangle of four
    overlapping gates (perception_range / proximity / aggro_range "draft" 45 / leash_range 90, two
    of them wrongly keyed to the PLAYER) with one distance-banded model keyed to the actual combat
    target (the nearest live pet):

      dist <= engage_radius            LOCKED  — never disengages; chases its target around its turf.
                                                 Threat decays at the base rate.
      engage_radius < dist <= give_up  CHASING — threat decays chase_decay_mult× faster (and
                                                 leave_area_decay_mult× if the target has left the
                                                 enemy's home area), so it pursues a fleeing target a
                                                 little past the border, then loses interest.
      dist > give_up_range             DROP    — give up immediately (teleported / crossed the map /
                                                 went to another world). Pets follow the player, so a
                                                 player leaving takes the squad out of range = drop.

    Why nearest-PET distance, not the player: combat is fought against pets, and pets follow the
    player. Keying to the pet makes "I teleported away" fall out for free (the squad goes with you)
    and removes the player-vs-pet reference-frame bug that made enemies quit ~45 studs out.

    CC effects (taunt / fear / daze) layer ON TOP of this, they don't change the leash math:
      * taunt — force the enemy's target to a chosen pet for a duration (overrides table top).
      * fear  — the enemy flees the source for a duration (target preserved, movement inverted).
      * daze / stun — action-lock (can't move or attack) while the threat table is preserved.
    The table + leash own "who / how long"; CC owns "what it does right now."

    Pure + Roblox-free: dist is a number; cfg is the engagement.aggro config table.
]]

local AggroLeash = {}

local DEFAULTS = {
    engage_radius = 160, -- locked-on radius (never disengages within this)
    give_up_range = 400, -- hard cutoff (teleport / far side of map / new world)
    chase_decay_mult = 3, -- threat bleeds this much faster while chasing beyond engage_radius
    leave_area_decay_mult = 6, -- ...and this much faster if the target left the enemy's home area
}

local function num(cfg, key)
    local v = cfg and cfg[key]
    return (type(v) == "number") and v or DEFAULTS[key]
end

-- Threat-decay multiplier for the current target distance. 1× while locked on (within
-- engage_radius); chase_decay_mult× while chasing beyond it; leave_area_decay_mult× (the larger
-- of the two) once the target's player has left the enemy's home area, so a fleeing-into-the-next-
-- biome target is forgotten quickly.
function AggroLeash.decayMult(dist, inTerritory, cfg)
    local mult = 1
    if dist > num(cfg, "engage_radius") then
        mult = num(cfg, "chase_decay_mult")
    end
    if not inTerritory then
        mult = math.max(mult, num(cfg, "leave_area_decay_mult"))
    end
    return mult
end

-- Persistence verdict given the nearest-pet distance and whether a valid threat target still
-- exists above the disengage threshold:
--   "drop"   — let go of aggro entirely (idle / loiter).
--   "engage" — has a real threat target; fight normally.
--   "lock"   — no threat target left, BUT still within engage_radius -> keep pursuing the nearest
--              pet (it may be retreating, e.g. a Rally) rather than quitting.
function AggroLeash.verdict(dist, hasThreatTarget, cfg)
    if dist > num(cfg, "give_up_range") then
        return "drop"
    end
    if hasThreatTarget then
        return "engage"
    end
    if dist <= num(cfg, "engage_radius") then
        return "lock"
    end
    return "drop"
end

return AggroLeash
