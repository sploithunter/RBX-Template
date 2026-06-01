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
        -- When chasing, the enemy presses this many studs INSIDE attack_range instead of
        -- parking on its edge — otherwise it stalls just out of bite range of a kiting
        -- target (float boundary) and never lands a hit. Keep < attack_range.
        attack_press = 3,
        -- Client render smoothing: the server moves enemies in ~update_interval steps;
        -- EnemyMotion (client) interpolates the visible model toward each step at this
        -- exponential rate (higher = snappier, lower = floatier). Server stays the
        -- authority for position; this only smooths what the player sees.
        render_lerp_rate = 12,
        -- Procedural walk gait (client, EnemyMotion): rig-less mesh enemies get a
        -- waddle while moving — a vertical bob plus a bank/wiggle about the facing axis.
        -- Driven by distance travelled, so it scales with speed and stops when the enemy
        -- is still. This is the DEFAULT; each enemy in configs/enemies.lua can override
        -- any field via its own `gait = {...}` (merged over this), so different pets move
        -- differently. `style` selects the motion shape (EnemyMotion STYLES):
        --   waddle  — bob 2x/stride + left/right bank 1x (the classic down->L->up->down->R->up)
        --   march   — stiff bob, no tilt
        --   hop     — one big bounce per stride, no tilt
        --   slither — no bob, heading wiggles left/right (snake-like)
        gait = {
            enabled = true,
            style = "waddle",
            bob_height = 0.6, -- studs of vertical bob at full amplitude
            tilt_degrees = 12, -- max bank / wiggle (degrees) at full amplitude
            stride_length = 5, -- studs travelled per full cycle (2 bobs / 1 tilt L+R)
            ref_speed = 8, -- speed (studs/s) at which the gait reaches full amplitude
            ease_rate = 8, -- how fast the gait fades in/out as it starts/stops
        },
        -- A downed pet (taken all the way down) is out for this long, then fully
        -- heals — the "fully defeated takes X to heal" consequence. Partially
        -- damaged pets bleed their damage back at regen.partial_per_second once
        -- they have been out of combat for regen.delay_seconds (the faster heal).
        full_defeat_heal_seconds = 25,
        regen = {
            partial_per_second = 12,
            delay_seconds = 3,
        },
        -- Aggro / threat table (src/Shared/Game/AggroTable). The enemy chases + bites the
        -- highest-aggro attacker. Aggro builds from DAMAGE dealt to the enemy
        -- (damage_factor per point) plus PASSIVE threat each second (× the attacker's
        -- Threat stat, so a tank holds aggro). It DECAYS at decay_per_second, so once
        -- nothing keeps hitting the enemy the top entry bleeds away; when the top drops
        -- to/below disengage_threshold the enemy gives up and idles. taunt_amount is the
        -- chunk a taunt/provoke power adds (player or tank drawing aggro; wired later).
        aggro = {
            passive_per_second = 1.5,
            damage_factor = 1.0,
            decay_per_second = 4,
            disengage_threshold = 0.5,
            taunt_amount = 250,
            -- Proximity aggro: any attacker within proximity_range of the enemy keeps a
            -- baseline aggro of proximity_floor (> disengage_threshold), so decay can't
            -- make the enemy "forget" a pet right next to it — get close enough and it
            -- engages. Only once everything leaves range does aggro bleed to zero and the
            -- enemy disengages. (A future stealth flag exempts a target from this floor.)
            proximity_range = 30,
            proximity_floor = 6,
            -- Implicit taunt: roles flagged `implicit_taunt` (tanks) automatically grab
            -- the enemy's attention. Every `interval` seconds a taunting pet's aggro is
            -- bumped to `lead` × the highest OTHER attacker — so it leads the pack and
            -- holds the enemy. It is NOT absolute: between pulses a pet doing a huge burst
            -- of damage out-aggros and rips the enemy off the tank until the next pulse.
            -- Tune interval/lead to balance how sticky tanks are.
            taunt = {
                interval = 3,
                lead = 1.3,
            },
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
