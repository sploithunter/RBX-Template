--[[
    Aggro model — one symmetric "aggro game" for pets AND enemies (docs/AGGRO_MODEL.md).

    Every combat unit keeps a decaying threat table toward the other side; focus-fire, taunt, fear,
    rage and farm-vs-fight all fall out of how threat is added and bled. This config holds the knobs.

    SHAPE: a symmetric `base` block (read by BOTH sides) × per-side `pet` / `enemy` MULTIPLIERS.
    Start fully symmetric (every mult = 1.0). `enemy.threat_mult` (etc.) is the artificial difficulty
    dial — crank enemy aggro up or down WITHOUT touching the pet side. Effective = base[x] * side.<x>_mult.

    Phase 1 wires base + side mults (symmetric core). taunt/fear/rage knobs are staged here now but
    only consumed in Phase 2.
]]

return {
    -- The v2 threat-table model is ON permanently (Jason: "I like the current aggro model... turned on
    -- permanently"). The flag is kept as an ESCAPE HATCH, not an A/B default: set false here, or
    -- `_G.AggroV2 = false` in the server command bar, to fall back to the legacy aggroPlayerName path.
    enabled = true,

    -- SYMMETRIC defaults, read by both sides.
    base = {
        threat_per_damage = 1.0, -- threat added to the struck unit's table per point of damage taken
        splash_frac = 0.25, -- a hit unit's TEAMMATES gain this fraction of the direct credit...
        splash_radius = 40, -- ...if within this many studs (used for the PET squad splash)
        -- ENEMY band wake: attacking one enemy only rouses its OWN patrol band (never a second
        -- group), and only the members that can NOTICE the attack — within notice_radius AND with a
        -- clear line of sight to the victim (notice_los). A band-mate around a corner / over a hill /
        -- too far stays asleep, so you can pick off isolated enemies (CoH-style sneak attack / pull).
        notice_radius = 50,
        notice_los = true, -- raycast victim→ally; world geometry between them blocks the wake
        seed_rate = 2, -- per-second threat trickle from an APPROACHING hostile (starts a fight...
        seed_radius = 60, -- ...before first contact; a parked, non-damaging foe only ever gets this
        -- and decays off → farming resumes). The farm-lock fix.
        engage_floor = 5, -- top threat must reach this to ENTER combat...
        exit_floor = 1, -- ...and drop below this to LEAVE (engage > exit = hysteresis, no flapping)
        decay = {
            per_second = 4, -- base bleed; reuses the AggroLeash distance curve below
            start_range = 90, -- beyond this the bleed speeds up (you're fleeing)
            chase_mult = 3, -- ×faster past start_range
            leave_area_mult = 6, -- ×faster once the target has left the unit's home area
        },
        proximity = {
            floor = 6, -- a hostile within range keeps at least this much threat (won't forget what's...
            range = 30, -- ...right next to it) — must sit above exit_floor
        },
    },

    -- PER-SIDE multipliers over `base`. 1.0 = symmetric. Bump enemy.* to make foes stickier/meaner.
    pet = { threat_mult = 1.0, decay_mult = 1.0, splash_mult = 1.0, seed_mult = 1.0 },
    enemy = { threat_mult = 1.0, decay_mult = 1.0, splash_mult = 1.0, seed_mult = 1.0 },

    -- POWERS as aggro (Phase 2 consumers; knobs staged here).
    taunt = { lead = 3, interval = 3 }, -- pin the taunter to the top of the target's table
    fear = { duration = 3, magnitude = -50 }, -- entry toward the source goes negative → flee, then recover
    rage = { tip = 200, calm = 80, amp = 1.5 }, -- tipping point on aggro HEAT (threat directed AT the unit)
}
