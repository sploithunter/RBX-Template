--[[
    Powers — Halo & Horns [PROTOTYPE] (Feature 14: Power Selection at Level-Up).

    Player-cast support powers, gated by archetype (configs/archetypes.lua power_pool
    references these ids). At each selection level the player picks ONE power from
    their archetype's pool; selections accumulate and persist (profile.Powers).
    Focus cost (Feature 12) + base cooldown live here; augmentation slots (Feature 15)
    modify the effective cooldown. Pure rules: `src/Shared/Game/PowerSelection.lua`.
]]

return {
    -- Levels that grant a power selection (one per level). Tunable.
    selection_levels = { 5, 9, 13, 17, 21, 25 },

    -- Families whose effect reaches an ENEMY through the pets (offensive / control / debuff /
    -- pet-amplified damage). These can't be cast unless the squad is actually engaged with an
    -- enemy (no firing a meteor into empty space). Friendly families (heal/buff/absorb/
    -- defense_buff) target your own pets and are always castable. `engage_radius` = how close an
    -- alive enemy must be to the squad to count as engaged.
    enemy_targeted_families = {
        vulnerable = true,
        root = true,
        amplified_burst = true,
        burn_spread = true,
        team_cleave = true,
    },
    engage_radius = 60,

    -- How each `effect` keyword resolves to a concrete SUPPORT action when cast
    -- (§16.5 firewall: player powers never deal direct damage — "damage" effects
    -- become enemy VULNERABILITY so pets hit harder). Families the services apply:
    --   heal      — refill `magnitude` endurance on the player's living pets
    --   buff      — x`magnitude` pet damage for `duration`s (player PetDamageBuff)
    --   root      — engaged enemies can't chase for `duration`s
    --   vulnerable— engaged enemies take x`magnitude` pet damage for `duration`s
    effect_kinds = {
        -- shields = ABSORPTION pools (soak `magnitude` damage before endurance), not heals
        shield = { family = "absorb", magnitude = 40, duration = 0 },
        ice_armor = { family = "absorb", magnitude = 40, duration = 0 },
        dune_shield = { family = "absorb", magnitude = 40, duration = 0 },
        ember_ward = { family = "absorb", magnitude = 40, duration = 0 },
        -- Bulwark = squad DAMAGE REDUCTION for `duration`s (temp +Defense armor), per design
        team_shield = { family = "defense_buff", magnitude = 120, duration = 15 },
        dodge = { family = "absorb", magnitude = 30, duration = 0 },
        damage_buff = { family = "buff", magnitude = 1.5, duration = 8 },
        root = { family = "root", magnitude = 0, duration = 5 },
        aoe_slow = { family = "root", magnitude = 0, duration = 5 },
        blizzard = { family = "root", magnitude = 0, duration = 6 },
        aoe_blind = { family = "vulnerable", magnitude = 1.5, duration = 6 },
        damage_over_time = { family = "vulnerable", magnitude = 1.5, duration = 6 },
        aoe_damage = { family = "vulnerable", magnitude = 2.0, duration = 5 },
        mark_of_flame = { family = "vulnerable", magnitude = 1.5, duration = 8 },
        eruption = { family = "vulnerable", magnitude = 2.0, duration = 5 },

        -- ===== Pyromancer signatures (Feature: signature powers, §17.8) =====
        -- Firewall-safe (§16.5): none of these deal standalone player damage. "amplified_burst"
        -- is PET-damage amplification — its burst is scaled by the squad's attack total and
        -- credited to the pets (see AmplifiedBurst); the others are vulnerability/cleave buffs.
        --   burn_spread   — a vulnerability mark on the pet's target that SPREADS to nearby
        --                   enemies every `spread_interval`s within `spread_radius` (contagion)
        --   team_cleave   — for `duration`s every pet's attacks deal x`magnitude` splash damage
        --                   to other enemies within `cleave_radius`
        --   amplified_burst — meteor on the engagement: each enemy within `radius` takes a burst
        --                   = squad-attack-total x`magnitude` (radial falloff to `falloff` at the
        --                   edge), credited to pets, then a molten pool lingers `pit_duration`s
        --                   applying x`pit_vulnerable` vulnerability
        wildfire = {
            family = "burn_spread",
            magnitude = 1.6,
            duration = 8,
            spread_radius = 14,
            spread_interval = 1.5,
        },
        firestorm = { family = "team_cleave", magnitude = 0.5, duration = 6, cleave_radius = 8 },
        cataclysm = {
            family = "amplified_burst",
            magnitude = 3.0,
            duration = 5,
            radius = 16,
            falloff = 0.5,
            pit_vulnerable = 1.5,
            pit_duration = 4,
        },
    },

    powers = {
        -- Geomancer
        stone_skin = {
            archetype = "geomancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "shield",
        },
        bulwark = {
            archetype = "geomancer",
            focus_cost = 30,
            cooldown_seconds = 45,
            effect = "team_shield",
        },
        mountains_strength = {
            archetype = "geomancer",
            focus_cost = 25,
            cooldown_seconds = 40,
            effect = "damage_buff",
        },
        -- Sandwalker
        mirage_step = {
            archetype = "sandwalker",
            focus_cost = 15,
            cooldown_seconds = 20,
            effect = "dodge",
        },
        sandstorm = {
            archetype = "sandwalker",
            focus_cost = 35,
            cooldown_seconds = 50,
            effect = "aoe_blind",
        },
        dune_shield = {
            archetype = "sandwalker",
            focus_cost = 20,
            cooldown_seconds = 35,
            effect = "shield",
        },
        -- Cryomancer
        frost_bind = {
            archetype = "cryomancer",
            focus_cost = 25,
            cooldown_seconds = 35,
            effect = "root",
        },
        ice_armor = {
            archetype = "cryomancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "shield",
        },
        blizzard = {
            archetype = "cryomancer",
            focus_cost = 40,
            cooldown_seconds = 60,
            effect = "aoe_slow",
        },
        -- Pyromancer
        mark_of_flame = {
            archetype = "pyromancer",
            focus_cost = 20,
            cooldown_seconds = 25,
            effect = "damage_over_time",
        },
        ember_ward = {
            archetype = "pyromancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "shield",
        },
        eruption = {
            archetype = "pyromancer",
            focus_cost = 45,
            cooldown_seconds = 60,
            effect = "aoe_damage",
        },

        -- ===== Pyromancer SIGNATURES (§17.8) — exclusive, 2 mid-tier + 1 capstone =====
        -- Extended schema (display_name/signature/capstone/role/element/target/glyph/unlock_level)
        -- drives the hotbar icon (glyph + element tint + target badge) and CoH-style level gating.
        -- target: single | single_spread | targeted_aoe | team_aoe | friendly (the pet picks the
        -- actual target; the player only augments what the squad is already attacking).
        wildfire = {
            archetype = "pyromancer",
            focus_cost = 25,
            cooldown_seconds = 25,
            effect = "wildfire",
            display_name = "Wildfire",
            signature = true,
            role = "damage",
            element = "lava",
            target = "single_spread",
            glyph = "debuff",
            unlock_level = 15,
        },
        firestorm = {
            archetype = "pyromancer",
            focus_cost = 35,
            cooldown_seconds = 40,
            effect = "firestorm",
            display_name = "Firestorm",
            signature = true,
            role = "damage",
            element = "lava",
            target = "team_aoe",
            glyph = "burst",
            unlock_level = 20,
        },
        cataclysm = {
            archetype = "pyromancer",
            focus_cost = 60,
            cooldown_seconds = 90,
            effect = "cataclysm",
            display_name = "Cataclysm",
            signature = true,
            capstone = true,
            role = "damage",
            element = "lava",
            target = "targeted_aoe",
            glyph = "burst",
            unlock_level = 30,
        },
    },
}
