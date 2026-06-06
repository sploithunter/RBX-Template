--[[
    Powers — Halo & Horns [PROTOTYPE] (Feature 14: Power Selection at Level-Up).

    Player-cast support powers, gated by archetype (configs/archetypes.lua power_pool
    references these ids). At each selection level the player picks ONE power from
    their archetype's pool; selections accumulate and persist (profile.Powers).
    Focus cost (Feature 12) + base cooldown live here; augmentation slots (Feature 15)
    modify the effective cooldown. Pure rules: `src/Shared/Game/PowerSelection.lua`.
]]

return {
    -- 10 power picks across 1->50 (target: 10 powers out of a larger pool). Pools
    -- (archetypes.lua power_pool) are smaller than 10 today, so late picks gracefully show
    -- "no powers available" until the pools are authored out. Keep in sync with
    -- level_track.lua power_levels.
    selection_levels = { 3, 7, 11, 15, 19, 24, 29, 34, 40, 46 },

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
        -- shields = ABSORPTION pools (soak `magnitude` damage before endurance), not heals.
        -- duration > 0 = the shield also EXPIRES after that many seconds even if not fully soaked
        -- (no permanent player power); whichever comes first — depleted or timed out — drops it.
        shield = { family = "absorb", magnitude = 40, duration = 12 },
        -- Armor / hardening = a temp +Defense % reducer on the armor curve (NOT an absorb pool):
        -- the pet's own material HARDENS (Stone Skin, Ice Armor). Sustained mitigation vs. shield's
        -- burst soak. Applies to the squad and expires after `duration`s (no permanent armor).
        armor = { family = "defense_buff", magnitude = 80, duration = 12 },
        -- Bulwark = squad DAMAGE REDUCTION for `duration`s (temp +Defense armor), per design
        team_shield = { family = "defense_buff", magnitude = 120, duration = 15 },
        dodge = { family = "absorb", magnitude = 30, duration = 8 },
        damage_buff = { family = "buff", magnitude = 1.5, duration = 8 },
        root = { family = "root", magnitude = 0, duration = 5 },
        aoe_slow = { family = "root", magnitude = 0, duration = 5 },
        blizzard = { family = "root", magnitude = 0, duration = 6 },
        aoe_blind = { family = "vulnerable", magnitude = 1.5, duration = 6 },
        damage_over_time = { family = "vulnerable", magnitude = 1.5, duration = 6 },
        aoe_damage = { family = "vulnerable", magnitude = 2.0, duration = 5 },
        mark_of_flame = { family = "vulnerable", magnitude = 1.5, duration = 8 },
        eruption = { family = "vulnerable", magnitude = 2.0, duration = 5 },

        -- ===== GENERIC pool (farming / luck / utility) — magnitude = FRACTION (+0.5 = +50%),
        -- summed per axis via BuffStack (docs Part E). White disc (no element origin). =====
        coin_yield = { family = "coin_yield", magnitude = 0.5, duration = 30 }, -- Prospector
        windfall = { family = "coin_yield", magnitude = 2.0, duration = 10 }, -- Windfall (big burst)
        mining_boost = { family = "mining", magnitude = 0.5, duration = 30 }, -- Mother Lode
        luck = { family = "luck", magnitude = 0.5, duration = 60 }, -- Fortune
        luck_huge = { family = "luck", magnitude = 2.0, duration = 30 }, -- Huge Fortune (marquee)
        move_speed = { family = "move_speed", magnitude = 0.4, duration = 20 }, -- Swift
        recharge = { family = "recharge", magnitude = 0.5, duration = 20 }, -- Hasten
        xp_boost = { family = "xp", magnitude = 0.5, duration = 30 }, -- XP Surge
        revive = { family = "revive", magnitude = 0, duration = 0 }, -- instant re-summon (mechanic)
        recall = { family = "recall", magnitude = 0, duration = 0 }, -- teleport to saved spot
        world_travel = { family = "world_travel", magnitude = 0, duration = 0 }, -- teleport to a hub

        -- ===== Attack-fill (origin-coloured) — reuse the enemy-debuff families (firewall-safe:
        -- player powers don't deal direct damage; they make pets hit harder / lock enemies). =====
        sunder = { family = "vulnerable", magnitude = 1.6, duration = 6 }, -- armor break (AoE)
        expose = { family = "vulnerable", magnitude = 1.4, duration = 8 }, -- expose one target
        disarm = { family = "vulnerable", magnitude = 1.3, duration = 6 }, -- weaken one target
        focus_fire = { family = "vulnerable", magnitude = 1.5, duration = 6 }, -- designate + soften
        cripple = { family = "root", magnitude = 0, duration = 4 }, -- slow/lock one target
        strike = { family = "vulnerable", magnitude = 1.5, duration = 4 }, -- basic single hit

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
        -- GENERIC powers (generic = true): any archetype can pick them; white disc (no element).
        -- Farming + luck + utility — see configs/archetypes.lua generic_pool.
        prospector = {
            generic = true,
            focus_cost = 20,
            cooldown_seconds = 40,
            effect = "coin_yield",
        },
        windfall = { generic = true, focus_cost = 30, cooldown_seconds = 60, effect = "windfall" },
        mother_lode = {
            generic = true,
            focus_cost = 25,
            cooldown_seconds = 45,
            effect = "mining_boost",
        },
        fortune = { generic = true, focus_cost = 20, cooldown_seconds = 45, effect = "luck" },
        huge_fortune = {
            generic = true,
            focus_cost = 50,
            cooldown_seconds = 120,
            effect = "luck_huge",
        },
        swift = { generic = true, focus_cost = 15, cooldown_seconds = 25, effect = "move_speed" },
        hasten = { generic = true, focus_cost = 20, cooldown_seconds = 60, effect = "recharge" },
        xp_surge = { generic = true, focus_cost = 25, cooldown_seconds = 60, effect = "xp_boost" },
        revive = { generic = true, focus_cost = 25, cooldown_seconds = 30, effect = "revive" },
        recall = { generic = true, focus_cost = 10, cooldown_seconds = 30, effect = "recall" },
        world_travel = {
            generic = true,
            focus_cost = 10,
            cooldown_seconds = 30,
            effect = "world_travel",
        },

        -- Attack-fill (origin-coloured, per archetype). Element from the archetype theme.
        sunder = {
            archetype = "geomancer",
            focus_cost = 18,
            cooldown_seconds = 25,
            effect = "sunder",
        },
        expose = {
            archetype = "sandwalker",
            focus_cost = 15,
            cooldown_seconds = 20,
            effect = "expose",
        },
        cripple = {
            archetype = "sandwalker",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "cripple",
        },
        disarm = {
            archetype = "cryomancer",
            focus_cost = 18,
            cooldown_seconds = 25,
            effect = "disarm",
        },
        focus_fire = {
            archetype = "cryomancer",
            focus_cost = 12,
            cooldown_seconds = 15,
            effect = "focus_fire",
        },
        strike = {
            archetype = "pyromancer",
            focus_cost = 10,
            cooldown_seconds = 12,
            effect = "strike",
        },

        -- Single-target defensive powers: target = "single_pet" lands on the SELECTED squad pet
        -- only (CombatBuffTarget), not the whole squad. aegis = a focused shield (bubble); ironclad
        -- = a focused armor (reskin). Falls back to the first pet when nothing is selected.
        aegis = {
            archetype = "geomancer",
            focus_cost = 12,
            cooldown_seconds = 18,
            effect = "shield", -- absorb pool -> bubble on the one selected pet
            target = "single_pet",
        },
        ironclad = {
            archetype = "geomancer",
            focus_cost = 12,
            cooldown_seconds = 18,
            effect = "armor", -- +Defense % -> reskin on the one selected pet
            target = "single_pet",
        },
        -- Geomancer
        stone_skin = {
            archetype = "geomancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "armor", -- hardened stone skin = +Defense %, not an absorb pool
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
            effect = "armor", -- ice plating = +Defense %, not an absorb pool
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
