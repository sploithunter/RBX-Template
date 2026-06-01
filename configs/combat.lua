--[[
    Combat tuning + spawners — Halo & Horns [PROTOTYPE] (Feature 10).

    auto_target            — default pet targeting mode ("nearest").
    group_scaling          — enemy HP scaling for multiplayer (Feature 18):
                             scaledHp = baseHp * (1 + per_extra_player * (partySize - 1)).
    pet_down_threshold_factor — a pet has no HP stat; it can absorb
                             power * this_factor accumulated enemy damage before
                             it is downed -> Spirit Form (Feature 7) -> auto-return
                             from the active squad (Feature 9).
    spawners               — zoneId -> { biome, enemies = { {id, count}, ... } }.
                             Marker placement is authored map work ([studio]).

    Read by CombatService; pure math lives in `src/Shared/Game/CombatMath.lua`.
]]

return {
    auto_target = "nearest",

    group_scaling = {
        per_extra_player = 0.5,
    },

    pet_down_threshold_factor = 1.0,

    -- Defensive stat (armor curve). Damage is reduced by armor/(armor+k): a pet's
    -- Defense attribute mitigates enemy hits, an enemy's Armor mitigates pet damage.
    -- At armor == k the hit is halved; diminishing returns, never full immunity.
    -- Tune k to set how much a point of armor is worth.
    armor_curve_k = 100,

    -- Defensive inverse mining (Feature 10 slice 1b). An enemy "mines" the
    -- endurance of the pets attacking it; pets attack back when an enemy is in
    -- range (combat outranks auto-mine so pets don't scatter to crystals).
    engagement = {
        aggro_range = 45, -- enemy engages a player's squad within this (studs)
        attack_range = 11, -- enemy damages a pet within this of itself (studs)
        -- Chase + perception (slice 2). An idle enemy NOTICES a player by distance
        -- x probability (rolled every perception_interval; certain on top, zero past
        -- perception_range). Once it has aggro it CHASES (move_speed lives per enemy
        -- in configs/enemies.lua) until within attack_range, biting the highest-THREAT
        -- pet in range — so a tank pet (high Threat attribute, else its Power) pulls
        -- aggro off squishier pets. It drops aggro if the player leaves leash_range.
        perception_range = 70,
        perception_interval = 0.75,
        leash_range = 90,
        default_move_speed = 12,
        -- A downed pet (taken all the way down) is out for this long, then fully
        -- heals — the "fully defeated takes X to heal" consequence. Partially
        -- damaged pets bleed their damage back at regen.partial_per_second once
        -- they have been out of combat for regen.delay_seconds (the faster heal).
        full_defeat_heal_seconds = 25,
        regen = {
            partial_per_second = 12,
            delay_seconds = 3,
        },
    },

    -- Staged degradation (§11.3): a pet visibly weakens before it is downed, so the
    -- player can RECALL it first (the agency that makes recall worthwhile). Keyed off
    -- the pet's health fraction (1 = full, 0 = downed): at/below strained_at -> Strained,
    -- at/below critical_at -> Critical. The *_damage_penalty fractions reduce the damage
    -- a pet DEALS in that state (0 = off for now; wired with the HUD's combat effects).
    degradation = {
        strained_at = 0.6,
        critical_at = 0.3,
        strained_damage_penalty = 0.0,
        critical_damage_penalty = 0.0,
    },

    -- Squad-HUD status badges (the buff/debuff icons on the right-side pet cards).
    -- When a timed effect is within `blink_lead_seconds` of expiring, its badge
    -- blinks so the player notices it's about to drop. `blink_period_seconds` is one
    -- full on/off cycle. Pool effects with no expiry (e.g. shield) never blink.
    status_badges = {
        blink_lead_seconds = 5,
        blink_period_seconds = 0.5,
    },

    spawners = {
        hell_1_lava = {
            biome = "lava",
            enemies = {
                { id = "lava_imp", count = 4 },
                { id = "ember_brute", count = 1 },
            },
        },
    },
}
