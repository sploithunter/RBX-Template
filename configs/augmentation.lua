--[[
    Augmentation slots — Halo & Horns [PROTOTYPE] (Feature 15).

    Players earn unallocated slots at slot-grant levels and place them on UNLOCKED
    (selected) powers (Feature 14). Each slot has a type; matching types on the same
    power trigger escalating set bonuses. Slots persist (profile.Slots) and are
    returned to unallocated on respec. Pure rules: `src/Shared/Game/Augmentation.lua`.
]]

return {
    -- Keep in sync with level_track.lua slot_levels (the level-up grants the slots here).
    -- Every ODD level 3–49 = 24 grants × 2 = 48 enhancement slots (CoH-paced; scarce vs the 72 it
    -- would take to 6-slot all 12 powers → you choose which powers to god-tier).
    slot_grant_levels = { 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35, 37, 39, 41, 43, 45, 47, 49 },
    max_slots_per_power = 6,
    slot_types = { "recharge", "strength", "range", "duration", "efficiency", "reliability" },

    -- Per-slot effect magnitude by type (e.g. each recharge slot = -5% cooldown).
    per_slot = {
        recharge = 0.05,
        strength = 0.05,
        range = 0.05,
        duration = 0.05,
        efficiency = 0.05,
        reliability = 0.05,
    },

    -- Set bonuses by number of MATCHING-type slots on one power. Higher tiers are
    -- stronger and stack with lower tiers (4 matching => 3-tier AND 4-tier apply).
    set_bonuses = {
        [3] = 0.10,
        [4] = 0.20,
        [5] = 0.30,
        [6] = 0.45,
    },
}
