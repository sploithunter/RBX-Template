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

    -- Pet attack pacing (fire-rate <-> damage tradeoff). Applied to every pet swing in
    -- PetFollowService:_mine: the per-pet attack interval is multiplied by interval_mult
    -- (>1 = slower swings) and per-swing damage by damage_mult (>1 = harder hits). Setting
    -- BOTH to the same value keeps DPS constant while changing the feel — e.g. { 2, 2 } =
    -- half as many hits, each twice as big (net-same DPS, punchier + more readable). 1 = no-op.
    -- Lets us "slow down how fast things shoot" without changing balance; tune freely.
    pet_attack_pacing = {
        interval_mult = 1.0,
        damage_mult = 1.0,
    },

    -- Defensive stat (armor curve). Damage is reduced by armor/(armor+k): a pet's
    -- Defense attribute mitigates enemy hits, an enemy's Armor mitigates pet damage.
    -- At armor == k the hit is halved; diminishing returns, never full immunity.
    -- Tune k to set how much a point of armor is worth.
    armor_curve_k = 100,

    -- DEV CANDLES (BuffStatsHud ⏱ rows): standard SAME-LEVEL matchups for the battle-
    -- clock pacing readout (Jason: "battles are way too fast... over before you realize
    -- they've started"; then "a Lieutenant, a boss, three minions and maybe a team").
    -- One row per matchup; each pack entry references a real enemies.lua def so every
    -- candle tracks enemy rebalances automatically. Add/remove matchups freely — the
    -- panel builds a row per entry (this list IS how you manage "it's getting a lot").
    -- Packs are simulated under focus fire: incoming damage DECAYS as targets die.
    dev_candle = {
        matchups = {
            { label = "Lieut.", pack = { { enemy = "ember_brute", count = 1 } } },
            { label = "Boss", pack = { { enemy = "dire_bear", count = 1 } } },
            { label = "3 Minions", pack = { { enemy = "lava_imp", count = 3 } } },
            {
                label = "Warband",
                pack = {
                    { enemy = "ember_brute", count = 1 },
                    { enemy = "lava_imp", count = 3 },
                },
            },
        },
    },

    -- Defensive inverse mining (Feature 10 slice 1b). An enemy "mines" the
    -- endurance of the pets attacking it; pets attack back when an enemy is in
    -- range (combat outranks auto-mine so pets don't scatter to crystals).
    engagement = {
        aggro_range = 45, -- enemy engages a player's squad within this (studs)
        -- Which in-range enemy each pet attacks when there's no player assist target. Per-pet
        -- override via the pet's TargetPriority attribute (src/Shared/Game/TargetPriority.lua);
        -- this is the squad default. Modes: aggro (most angry at the pet, else closest) /
        -- closest / furthest / strongest / weakest / team_threat.
        target_priority = { default = "aggro" },
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
        -- they have been out of combat for regen.delay_seconds.
        -- NATURAL regen is deliberately SLOW (a trickle) so heal powers / support pets / potions are
        -- the FAST way back — that's what makes them worth slotting. Tune the trickle here.
        full_defeat_heal_seconds = 25,
        regen = {
            partial_per_second = 1.5, -- a slow trickle (~1/sec) — heals/support/potions are the FAST way back
            delay_seconds = 5, -- the "must disengage" window before the trickle even starts
        },
        -- ENEMY regen (Jason: "enemies and pets are essentially supposed to be the exact
        -- same mechanic") — same shape as the pet trickle above, at A THIRD of the pet
        -- rate (1.5 / 3 = 0.5 HP/sec; the anchor is the CURRENT pet rate — if the pet
        -- trickle gets retuned, revisit this). Disengage from a half-dead enemy and it
        -- slowly knits back together, so you can't whittle one down across visits for free.
        enemy_regen = {
            partial_per_second = 0.5,
            delay_seconds = 5,
        },
        -- Instant effects (heals etc.) have no duration to show, so we flash a blinking
        -- badge on the pet's squad card for this long + pop a world puff — a visible
        -- "tell" of what just happened. Server stamps `HealFxUntil = os.time()+this`.
        instant_fx_seconds = 3,
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
        -- Hit / crit rolls (src/Shared/Game/CombatRoll). Every attack and taunt rolls to
        -- land and to crit; a miss does nothing, a crit multiplies the effect by crit_mult.
        --   pet_attack  — a pet's damage to an enemy
        --   enemy_attack — an enemy's bite on a pet
        --   taunt       — a tank's implicit-taunt pulse (miss = the taunt fizzles this
        --                 pulse; crit = a stronger grab, lead × crit_mult)
        rolls = {
            pet_attack = { hit_chance = 0.92, crit_chance = 0.15, crit_mult = 2.0 },
            enemy_attack = { hit_chance = 0.85, crit_chance = 0.1, crit_mult = 1.8 },
            taunt = { hit_chance = 0.9, crit_chance = 0.2, crit_mult = 1.5 },
        },
    },

    -- Level-diff TO-HIT curve (src/Shared/Game/Accuracy). hit_chance = clamp(base_to_hit +
    -- per_level_step*(attackerEffectiveLevel - defenderLevel), floor, cap). The defender's
    -- published Level already bakes in its rank_offset (boss reads +2), so a boss is naturally
    -- harder to land on — no separate rank term needed. MINING is exempt (crystals can't dodge):
    -- mining_hit_chance applies to breakables with no EnemyId. This replaces the old flat
    -- engagement.rolls.pet_attack.hit_chance for the HIT decision; CombatRoll still owns crit.
    accuracy = {
        base_to_hit = 0.92, -- even-level to-hit (8% miss baseline)
        per_level_step = 0.04, -- to-hit lost per level the target is above you (gained if below)
        floor = 0.05,
        cap = 0.95,
        mining_hit_chance = 1.0, -- crystals never miss (fixes the old 8% mining whiff)
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
