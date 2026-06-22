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
    -- Power picks (CoH-paced): dense even levels early, widening to ~every-4 in the 30s. 12 picks,
    -- last at L38 so any power can still earn its 6 enhancement slots before the L50 cap. Fewer picks
    -- than slots exist for (48 slots vs 72 to 6-slot all 12) ⇒ you CHOOSE which powers to god-tier →
    -- build diversity. MUST mirror level_track.lua power_levels.
    -- Levels where the player actually GETS to pick a power. The menu shows each power at the
    -- first selection level >= its unlock_level (the level you can truly choose it), so it never
    -- advertises a level you can't pick at. Reaches 44 so the L44 capstones are choosable; the
    -- L40/L46 picks (15 total) keep the tail meaningful AND leave slots intentionally scarce
    -- (15 powers x 6 = 90 capacity vs ~68 slots ever granted) so every slot is a real build choice.
    selection_levels = { 2, 4, 6, 8, 10, 12, 15, 18, 22, 26, 30, 36, 40, 44, 46 },

    -- Families whose effect reaches an ENEMY through the pets (offensive / control / debuff /
    -- pet-amplified damage). These can't be cast unless the squad is actually engaged with an
    -- enemy (no firing a meteor into empty space). Friendly families (heal/buff/absorb/
    -- defense_buff) target your own pets and are always castable. `engage_radius` = how close an
    -- alive enemy must be to the squad to count as engaged.
    enemy_targeted_families = {
        vulnerable = true,
        root = true,
        root_guard = true, -- Seismic Hold (roots enemies + hardens the squad)
        amplified_burst = true,
        burn_spread = true,
        team_cleave = true,
    },
    -- #174: families whose target-STRENGTH debuff also applies to FARMING (crystals), not just
    -- enemies. Vulnerability speeds mining the same way it speeds combat, so a pet mining a node
    -- counts as "engaged" for these. Control/CC families (root/disarm) are meaningless on a static
    -- crystal, so they stay enemy-only (absent here).
    farm_targeted_families = {
        vulnerable = true,
    },
    engage_radius = 60,

    -- Per-axis level scaling for PowerStats.resolveEffective (docs/PET_REALM_POWER_DATA_MODEL.md P3).
    --   effective = base × clamp(1 + per_level × (casterLevel − base_level), min, max)
    -- CONSERVATIVE starting point — only DAMAGE scales (so DoT ticks grow gently with the caster's
    -- level); recharge / duration / radius / magnitude stay FLAT (no entry ⇒ identity ×1) until a
    -- dedicated balance pass tunes them. Tune freely; an absent axis means "don't scale it".
    scaling = {
        damage = { per_level = 0.03, base_level = 1, min = 1, max = 2.5 }, -- +3%/level, up to ×2.5
    },

    -- Real-cast FX per effect FAMILY → configs/power_fx.lua primitive ids (PowerService:Cast resolves
    -- these; the client renders them via PowerFXRender, element from the power's origin). `source`
    -- plays on the caster, `target` on each engaged enemy (hostile families only). A nil/"tbd" → a
    -- floating "(effect TBD)" placeholder. Generic/white powers (no archetype element) resolve "tbd"
    -- for now — they have no element-themed visual yet. Tune freely; this is what stops every power
    -- of an origin from looking identical (a shield reads as a shield, a buff as a buff, …).
    --   bespoke families fired inside _applyEffect (NOT here): amplified_burst, team_cleave.
    family_fx = {
        -- friendly / self
        heal = { source = "heal_nova" },
        buff = { source = "aura" },
        damage_buff = { source = "aura" },
        armor = { source = "aura" },
        fortify = { source = "aura" },
        defense_buff = { source = "aura" },
        absorb = { source = "shield_bubble" },
        team_shield = { source = "shield_bubble" },
        shield = { source = "shield_bubble" },
        move_speed = { source = "aura" },
        recharge = { source = "aura" },
        xp_boost = { source = "aura" },
        luck = { source = "aura" },
        luck_huge = { source = "aura" },
        -- hostile (source on caster + target on each enemy). `source` is intentionally OMITTED: the
        -- caster tell is chosen by AoE-ness in PowerService:Cast — AoE powers (target=targeted_aoe/
        -- team_aoe) get the `cast_burst` ring (reads as AoE), single-target ones get the small
        -- `cast_emit` body emission. A per-power `fx.source` still overrides. `target` = the enemy hit.
        vulnerable = { target = "eruption" },
        burn_spread = { target = "eruption" },
        root = { target = "eruption" },
        root_guard = { target = "eruption" },
        -- no clean visual yet ⇒ floating "(effect TBD)"
        summon = { source = "tbd" },
        revive = { source = "tbd" },
        recall = { source = "tbd" },
        world_travel = { source = "tbd" },
        magnet = { source = "tbd" },
        coin_yield = { source = "tbd" },
        windfall = { source = "tbd" },
    },

    -- How each `effect` keyword resolves to a concrete SUPPORT action when cast
    -- (§16.5 firewall: player powers never deal direct damage — "damage" effects
    -- become enemy VULNERABILITY so pets hit harder). Families the services apply:
    --   heal      — refill `magnitude` endurance on the player's living pets
    --   buff      — x`magnitude` pet damage for `duration`s (player PetDamageBuff)
    --   root      — engaged enemies can't chase for `duration`s
    --   vulnerable— engaged enemies take x`magnitude` pet damage for `duration`s
    --
    -- COMBAT VFX (how a power READS on the pet) is config, not code. A power may declare:
    --   combat_vfx = { look = "bubble"|"dodge"|"reskin"|"aura"|"none", badge = true|false, on_hit = "dodge_pop" }
    -- If omitted, CombatAuraController defaults the look by effect family (absorb -> bubble, but an
    -- absorb effect_kind with evade=true -> dodge; defense_buff -> reskin; heal -> aura). So a NEW
    -- power just declares its family (or an explicit combat_vfx.look) and the renderer obeys — no
    -- per-power branches in the controller.
    -- Default to-hit base per effect FAMILY (a power's own `accuracy_base` overrides). Debuff/control
    -- powers land below 100% so they CAN miss (and so an `accuracy` enhancement has room to help —
    -- a base of 1 clamps the boost away). Families with NO entry auto-land at 1.0 (buffs/heals/etc.).
    -- Only families whose powers actually roll to-hit (`_accuracyHit`: vulnerable marks, root holds)
    -- belong here. Tune freely.
    accuracy_family_base = {
        vulnerable = 0.9, -- marks/debuffs: ~10% base miss before the level curve
        root = 0.9, -- holds/slows
    },

    effect_kinds = {
        -- shields = ABSORPTION pools (soak `magnitude` damage before endurance), not heals.
        -- duration > 0 = the shield also EXPIRES after that many seconds even if not fully soaked
        -- (no permanent player power); whichever comes first — depleted or timed out — drops it.
        shield = { family = "absorb", magnitude = 400, duration = 12 },
        -- Armor / hardening = a temp +Defense % reducer on the armor curve (NOT an absorb pool):
        -- the pet's own material HARDENS (Stone Skin, Ice Armor). Sustained mitigation vs. shield's
        -- burst soak. Applies to the squad and expires after `duration`s (no permanent armor).
        armor = { family = "defense_buff", magnitude = 80, duration = 12 },
        -- Bulwark = squad DAMAGE REDUCTION for `duration`s (temp +Defense armor), per design
        team_shield = { family = "defense_buff", magnitude = 120, duration = 15 },
        -- `evade=true`: an absorb pool that reads as DODGE (no shield bubble; pops "Dodge!" per hit
        -- it turns aside) rather than a shield. See PowerService EvasionUntil + CombatAuraController.
        dodge = { family = "absorb", magnitude = 300, duration = 8, evade = true },
        damage_buff = { family = "buff", magnitude = 1.5, duration = 8 },
        -- Critical Strike (Pyromancer): +crit CHANCE (fraction, additive) on the squad's hits for a
        -- duration — boosts crit on both combat AND mining. Crit damage stays at the roll's crit_mult.
        crit_up = { family = "crit", magnitude = 0.25, duration = 12 },
        root = { family = "root", magnitude = 0, duration = 5 },
        aoe_slow = { family = "root", magnitude = 0, duration = 5 },
        blizzard = { family = "root", magnitude = 0, duration = 6 },
        aoe_blind = { family = "vulnerable", magnitude = 1.5, duration = 6 },
        -- Targeted DoT: Mark of Flame (the only power using this key) burns its single target
        -- ~20 HP/sec (10x world) on top of the +50% damage debuff for 6s.
        damage_over_time = {
            family = "vulnerable",
            magnitude = 1.5,
            duration = 6,
            dot = { per_tick = 20, interval = 1, aoe = false },
        },
        aoe_damage = { family = "vulnerable", magnitude = 2.0, duration = 5 },
        eruption = { family = "vulnerable", magnitude = 2.0, duration = 5 },

        -- ===== GENERIC pool (farming / luck / utility) — magnitude = FRACTION (+0.5 = +50%),
        -- summed per axis via BuffStack (docs Part E). White disc (no element origin). =====
        coin_yield = { family = "coin_yield", magnitude = 0.5, duration = 30 }, -- Prospector
        -- Windfall (Jason): +200% DROP-TABLE chance (loot — enhancement cogs + premium
        -- gems), NOT coins. drop_rate axis, consumed by DropService + BreakableSpawner.
        windfall = { family = "drop_rate", magnitude = 2.0, duration = 10 },
        luck = { family = "luck", magnitude = 0.5, duration = 60 }, -- Fortune
        luck_huge = { family = "luck", magnitude = 2.0, duration = 30 }, -- Huge Fortune (marquee)
        -- PASSIVE (always-on by ownership): owning the power applies the buff permanently — no cast,
        -- no timer. Re-applied on pick + spawn/join (PowerService:_applyOwnedPassives). Only families
        -- with a SOLE-OCCUPANT axis are passive today; coin_yield (Prospector) + luck (Fortune) share
        -- their axis with Windfall / Huge Fortune bursts and need additive BuffStack (#169) first.
        move_speed = { family = "move_speed", magnitude = 0.4, passive = true }, -- Swift: always-on speed
        recharge = { family = "recharge", magnitude = 0.5, passive = true }, -- Hasten: always-on recharge
        xp_boost = { family = "xp", magnitude = 0.5, passive = true }, -- XP Surge: always-on XP
        revive = { family = "revive", magnitude = 0, duration = 0 }, -- instant re-summon (mechanic)
        recall = { family = "recall", magnitude = 0, duration = 0 }, -- teleport to saved spot
        world_travel = { family = "world_travel", magnitude = 0, duration = 0 }, -- teleport to a hub
        magnet = { family = "magnet", magnitude = 30, passive = true }, -- always-on +30 studs collect radius (#167)

        -- ===== Attack-fill (origin-coloured) — reuse the enemy-debuff families (firewall-safe:
        -- player powers don't deal direct damage; they make pets hit harder / lock enemies). =====
        sunder = { family = "vulnerable", magnitude = 1.6, duration = 6 }, -- armor break (AoE)
        expose = { family = "vulnerable", magnitude = 1.4, duration = 8 }, -- expose one target
        disarm = { family = "vulnerable", magnitude = 1.3, duration = 6 }, -- weaken one target
        focus_fire = { family = "vulnerable", magnitude = 1.5, duration = 6 }, -- designate + soften
        cripple = { family = "root", magnitude = 0, duration = 4 }, -- slow/lock one target
        strike = { family = "vulnerable", magnitude = 1.5, duration = 4 }, -- basic single hit

        -- ===== NEW origin-core effects — placeholder families so the powers resolve + show in menus;
        -- the real mechanics (Rage HP-curve, Fear flee, true Disarm/Hold, heals, player_field) are
        -- separate build slices. Firewall-safe. See docs/PET_REALM_ORIGIN_POWERSETS.md. =====
        taunt = { family = "taunt", magnitude = 0, duration = 8 }, -- TBD: aggro pull (threat)
        rage = { family = "rage", magnitude = 0.5, toggle = true }, -- TBD: lower HP -> higher damage
        armor_field = { family = "armor", magnitude = 0.25, duration = 12 }, -- player_field team armor
        -- 10x-world heal values (were 3 / 1.5 placeholder stubs — negligible vs ~hundreds-deep
        -- pools). restoring_sands = a strong FOCUSED single-pet mend (target=single_pet -> the
        -- selected squad card); healing_field = a self-AoE that hits the squad with a smaller
        -- upfront + a sustaining tail. Tuning starting points — adjust freely.
        restoring_sands = { family = "heal", magnitude = 600, duration = 0 }, -- single-pet instant heal
        healing_field = {
            family = "heal",
            magnitude = 200,
            duration = 8,
            hot = 120,
            hot_tick = 2,
            hot_seconds = 8,
        }, -- player_field heal + tail
        fear = { family = "fear", magnitude = 0, duration = 5 }, -- TBD: flee (AI state)
        ice_shard = { family = "vulnerable", magnitude = 1.4, duration = 4 }, -- targeted damage (via pets)
        deep_freeze = { family = "root", magnitude = 0, duration = 4 }, -- TBD: full hold (Capacitor)
        frost_field = { family = "root", magnitude = 0, duration = 6 }, -- player_field slow/freeze
        scorch = { family = "vulnerable", magnitude = 1.3, duration = 8 }, -- -def debuff
        fire_nova = { family = "vulnerable", magnitude = 1.8, duration = 4 }, -- player_field burn AoE

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
            -- the fire actually burns as it spreads: AoE DoT, 1 HP/sec across every enemy
            dot = { per_tick = 10, interval = 1, aoe = true },
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

        -- ===== Origin signatures (4 per origin; docs/PET_REALM_SIGNATURE_POWERS.md). Each tracks its
        -- origin's identity: earth=SHIELD/tank, ice=CONTROL, desert=HEAL, fire=DAMAGE. Capstones vary
        -- by identity — earth=summon guardian, fire=damage meteor, ice=field hold, desert=summon+revive.
        -- Most reuse existing families (firewall-safe + badge-ready); a few combos add small branches. =====
        -- Earth / Geomancer (shield/tank)
        bastion = { family = "absorb", magnitude = 900, duration = 14 }, -- anchor: huge squad shield
        seismic_hold = { family = "root_guard", magnitude = 120, duration = 6 }, -- root enemies + squad +Def
        living_mountain = {
            family = "fortify",
            magnitude = 150,
            duration = 10,
            heal = 300,
            hot_tick = 2,
        }, -- +Def + heal-over-time (30/2s)
        gaia_colossus = { family = "summon", guardian = "colossus", magnitude = 0, duration = 20 }, -- summon tank
        -- Fire / Pyromancer (damage) — Wildfire/Firestorm/Cataclysm above; this is the 4th
        -- mark that bites harder as it burns (1.9->2.6 vuln) + a targeted DoT (2.5 HP/sec on its mark,
        -- a touch hotter than the basic Mark of Flame's 2)
        inferno_brand = {
            family = "vulnerable",
            magnitude = 1.9,
            duration = 8,
            ramp_to = 2.6,
            dot = { per_tick = 25, interval = 1, aoe = false },
        },
        -- Ice / Cryomancer (control)
        -- anchor: strong AoE lockdown + light frostbite (3 HP/sec AoE (10x world); lowest of the cryomancer line)
        permafrost = {
            family = "root",
            magnitude = 0,
            duration = 8,
            dot = { per_tick = 3, interval = 1, aoe = true },
        },
        shatter = { family = "vulnerable", magnitude = 2.2, duration = 5, frozen_bonus = 1.4 }, -- big vuln, x1.4 again on FROZEN targets (2.2->3.08)
        -- mass hard freeze + deeper frostbite (4 HP/sec AoE (10x world); between Permafrost and Eternal Winter)
        absolute_zero = {
            family = "root",
            magnitude = 0,
            duration = 7,
            dot = { per_tick = 4, interval = 1, aoe = true },
        },
        -- Capstone: field-wide hold + a MINOR AoE DoT — 5 HP/sec (10x world; deliberately small so the
        -- frostbite chips slowly rather than bursting). Holds every enemy and grinds them down.
        eternal_winter = {
            family = "root",
            magnitude = 0,
            duration = 12,
            dot = { per_tick = 5, interval = 1, aoe = true },
        },
        -- Desert / Sandwalker (heal/sustain)
        oasis = {
            family = "heal",
            magnitude = 700,
            duration = 0,
            hot = 200,
            hot_tick = 2,
            hot_seconds = 8,
        }, -- big heal + 200/2s tail for 8s (10x world)
        mirage_veil = { family = "absorb", magnitude = 450, duration = 10, evade_heal = 120 }, -- evasion/absorb + heal-on-evade
        simoom = { family = "heal_blind", magnitude = 550, duration = 6, vuln = 1.5 }, -- heal squad + blind
        genie_dunes = {
            family = "summon",
            guardian = "djinn",
            magnitude = 70,
            duration = 20,
            revive = true,
        }, -- summon + revive + heal
    },

    powers = {
        -- GENERIC powers (generic = true): any archetype can pick them; white disc (no element).
        -- Farming + luck + utility — see configs/archetypes.lua generic_pool.
        -- `unlock_level` = the level at which a generic power becomes SELECTABLE in the neutral pool
        -- (the Power Choice menu shows earlier-unlock powers as pickable, later ones as locked with a
        --  "Lvl N" tag). Origins lock until L5, so neutrals carry the early game: tiered 2/4/6/8/10.
        prospector = {
            generic = true,
            display_name = "Prospector",
            focus_cost = 20,
            cooldown_seconds = 40,
            effect = "coin_yield",
            unlock_level = 2,
            subtitle = "Always-On",
        },
        windfall = {
            generic = true,
            display_name = "Windfall",
            focus_cost = 30,
            cooldown_seconds = 60,
            effect = "windfall",
            unlock_level = 6,
            subtitle = "Always-On",
        },
        -- (Mother Lode cut: "+mining damage" was redundant — damage buffs/debuffs already speed up
        --  crystal mining, and support pets cover yield. No distinct mechanic, so no power.)
        fortune = {
            generic = true,
            display_name = "Luck",
            focus_cost = 20,
            cooldown_seconds = 300, -- balance: 5 min recharge for a 1 min luck window
            effect = "luck",
            unlock_level = 8,
            subtitle = "Player-Targeted Special",
        },
        huge_fortune = {
            generic = true,
            display_name = "Huge Fortune",
            focus_cost = 50,
            cooldown_seconds = 120,
            effect = "luck_huge",
            unlock_level = 30,
            subtitle = "Player-Targeted Special",
        },
        swift = {
            generic = true,
            display_name = "Swift",
            focus_cost = 15,
            cooldown_seconds = 25,
            effect = "move_speed",
            unlock_level = 2,
            subtitle = "Always-On",
        },
        hasten = {
            generic = true,
            display_name = "Hasten",
            focus_cost = 20,
            cooldown_seconds = 60,
            effect = "recharge",
            unlock_level = 14,
            subtitle = "Always-On",
        },
        xp_surge = {
            generic = true,
            display_name = "XP Surge",
            focus_cost = 25,
            cooldown_seconds = 60,
            effect = "xp_boost",
            unlock_level = 4,
            subtitle = "Always-On",
        },
        revive = {
            generic = true,
            display_name = "Revive",
            focus_cost = 25,
            cooldown_seconds = 30,
            effect = "revive",
            unlock_level = 10,
            subtitle = "Single-Target Health",
        },
        recall = {
            generic = true,
            display_name = "Recall",
            focus_cost = 10,
            cooldown_seconds = 30,
            effect = "recall",
            unlock_level = 20,
            subtitle = "Player-Targeted Travel",
        },
        magnet = {
            generic = true,
            display_name = "Magnet",
            focus_cost = 15,
            cooldown_seconds = 30,
            effect = "magnet",
            unlock_level = 2,
            subtitle = "Always-On",
        },
        world_travel = {
            generic = true,
            display_name = "World Travel",
            focus_cost = 10,
            cooldown_seconds = 30,
            effect = "world_travel",
            unlock_level = 4,
            subtitle = "Player-Targeted Special",
        },

        -- ===== ORIGIN CORES — 7 per origin (full schema: display_name/role/element/target/glyph/
        -- unlock_level). See docs/PET_REALM_ORIGIN_POWERSETS.md. Signatures follow below.
        -- NOTE: new effects (taunt/rage/armor_field/restoring_sands/healing_field/fear/ice_shard/
        -- deep_freeze/frost_field/scorch/fire_nova) + target "player_field" have placeholder
        -- effect_kinds; their mechanics are separate build slices. =====

        -- Geomancer (earth · tank): targeted+team armor, buff, debuff, Taunt, Rage, Armor Field
        stone_skin = {
            archetype = "geomancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "armor",
            display_name = "Stone Skin",
            subtitle = "Single-Pet Armor",
            role = "armor",
            element = "earth",
            target = "single_pet",
            glyph = "shield",
            unlock_level = 6,
        },
        ironclad = {
            archetype = "geomancer",
            focus_cost = 16,
            cooldown_seconds = 24,
            effect = "armor",
            display_name = "Ironclad",
            subtitle = "Team Armor",
            role = "armor",
            element = "earth",
            target = "team_aoe",
            glyph = "shield",
            unlock_level = 9,
        },
        mountains_strength = {
            archetype = "geomancer",
            focus_cost = 25,
            cooldown_seconds = 40,
            effect = "damage_buff",
            display_name = "Mountain's Strength",
            subtitle = "Team Damage Buff",
            role = "buff",
            element = "earth",
            target = "team_aoe",
            glyph = "buff",
            unlock_level = 9,
        },
        sunder = {
            archetype = "geomancer",
            focus_cost = 18,
            cooldown_seconds = 25,
            effect = "sunder",
            display_name = "Sunder",
            subtitle = "Single-Target Debuff",
            role = "debuff",
            element = "earth",
            target = "single",
            glyph = "debuff",
            unlock_level = 6,
        },
        taunt = {
            archetype = "geomancer",
            focus_cost = 12,
            cooldown_seconds = 16,
            effect = "taunt",
            display_name = "Taunt",
            subtitle = "AoE Aggro+",
            role = "control",
            element = "earth",
            target = "targeted_aoe",
            glyph = "control",
            unlock_level = 6,
        },
        rage = {
            archetype = "geomancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "rage",
            display_name = "Rage",
            subtitle = "Self Low-HP Damage",
            role = "buff",
            element = "earth",
            target = "single_pet",
            glyph = "buff",
            unlock_level = 12,
        },
        armor_field = {
            archetype = "geomancer",
            focus_cost = 35,
            cooldown_seconds = 45,
            effect = "armor_field",
            display_name = "Armor Field",
            subtitle = "Self-AoE Armor",
            role = "armor",
            element = "earth",
            target = "player_field",
            glyph = "shield",
            unlock_level = 12,
        },

        -- Sandwalker (desert · buffer/heal/illusion): heal, shield, dodge, debuffs, Fear, Healing Field
        mirage_step = {
            archetype = "sandwalker",
            focus_cost = 15,
            cooldown_seconds = 20,
            effect = "dodge",
            display_name = "Mirage Step",
            subtitle = "Single-Ally Evasion",
            role = "buff",
            element = "desert",
            target = "single_pet",
            glyph = "buff",
            combat_vfx = { look = "dodge", on_hit = "dodge_pop" }, -- dodge, NOT a shield bubble
            unlock_level = 6,
        },
        dune_shield = {
            archetype = "sandwalker",
            focus_cost = 18,
            cooldown_seconds = 30,
            effect = "shield",
            display_name = "Dune Shield",
            subtitle = "Single-Pet Shield",
            role = "shield",
            element = "desert",
            target = "single_pet",
            glyph = "shield",
            combat_vfx = { look = "bubble" }, -- real absorb shield -> element force-field bubble
            unlock_level = 6,
        },
        restoring_sands = {
            archetype = "sandwalker",
            focus_cost = 20,
            cooldown_seconds = 25,
            effect = "restoring_sands",
            display_name = "Restoring Sands",
            subtitle = "Single-Pet Heal",
            role = "heal",
            element = "desert",
            target = "single_pet",
            glyph = "heal",
            unlock_level = 6,
        },
        expose = {
            archetype = "sandwalker",
            focus_cost = 15,
            cooldown_seconds = 20,
            effect = "expose",
            display_name = "Expose",
            subtitle = "Single-Target Debuff",
            role = "debuff",
            element = "desert",
            target = "single",
            glyph = "debuff",
            unlock_level = 9,
        },
        sandstorm = {
            archetype = "sandwalker",
            focus_cost = 35,
            cooldown_seconds = 50,
            effect = "aoe_blind",
            display_name = "Sandstorm",
            subtitle = "AoE Blind Debuff",
            role = "debuff",
            element = "desert",
            target = "targeted_aoe",
            glyph = "debuff",
            unlock_level = 9,
        },
        fear = {
            archetype = "sandwalker",
            focus_cost = 25,
            cooldown_seconds = 35,
            effect = "fear",
            display_name = "Fear",
            subtitle = "Single-Target Fear",
            role = "control",
            element = "desert",
            target = "single",
            glyph = "control",
            unlock_level = 12,
        },
        healing_field = {
            archetype = "sandwalker",
            focus_cost = 35,
            cooldown_seconds = 45,
            effect = "healing_field",
            display_name = "Healing Field",
            subtitle = "Self-AoE Heal",
            role = "heal",
            element = "desert",
            target = "player_field",
            glyph = "heal",
            unlock_level = 12,
        },

        -- Cryomancer (ice · controller): control trio (root/disarm/hold), armor, vuln, damage, field
        frost_bind = {
            archetype = "cryomancer",
            focus_cost = 25,
            cooldown_seconds = 35,
            effect = "root",
            display_name = "Frost Bind",
            subtitle = "Single-Target Root",
            role = "control",
            element = "ice",
            target = "single",
            glyph = "control",
            unlock_level = 6,
        },
        ice_armor = {
            archetype = "cryomancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "armor",
            display_name = "Ice Armor",
            subtitle = "Single-Pet Armor",
            role = "armor",
            element = "ice",
            target = "single_pet",
            glyph = "shield",
            unlock_level = 6,
        },
        disarm = {
            archetype = "cryomancer",
            focus_cost = 18,
            cooldown_seconds = 25,
            effect = "disarm",
            display_name = "Disarm",
            subtitle = "Single-Target Disarm",
            role = "control",
            element = "ice",
            target = "single",
            glyph = "control",
            unlock_level = 6,
        },
        focus_fire = {
            archetype = "cryomancer",
            focus_cost = 12,
            cooldown_seconds = 15,
            effect = "focus_fire",
            display_name = "Focus Fire",
            subtitle = "Single-Target Debuff",
            role = "debuff",
            element = "ice",
            target = "single",
            glyph = "debuff",
            unlock_level = 9,
        },
        ice_shard = {
            archetype = "cryomancer",
            focus_cost = 14,
            cooldown_seconds = 12,
            effect = "ice_shard",
            display_name = "Ice Shard",
            subtitle = "Single-Target Damage",
            role = "damage",
            element = "ice",
            target = "single",
            glyph = "burst",
            unlock_level = 9,
        },
        deep_freeze = {
            archetype = "cryomancer",
            focus_cost = 28,
            cooldown_seconds = 40,
            effect = "deep_freeze",
            display_name = "Deep Freeze",
            subtitle = "Single-Target Hold",
            role = "control",
            element = "ice",
            target = "single",
            glyph = "control",
            unlock_level = 12,
        },
        frost_field = {
            archetype = "cryomancer",
            focus_cost = 35,
            cooldown_seconds = 45,
            effect = "frost_field",
            display_name = "Frost Field",
            subtitle = "Self-AoE Freeze",
            role = "control",
            element = "ice",
            target = "player_field",
            glyph = "control",
            unlock_level = 12,
        },

        -- Pyromancer (lava · damage): strike, DoT, shield, AoE, crit buff, Scorch, Fire Nova
        strike = {
            archetype = "pyromancer",
            focus_cost = 10,
            cooldown_seconds = 12,
            effect = "strike",
            display_name = "Strike",
            subtitle = "Single-Target Damage",
            role = "damage",
            element = "lava",
            target = "single",
            glyph = "burst",
            unlock_level = 6,
        },
        mark_of_flame = {
            archetype = "pyromancer",
            focus_cost = 20,
            cooldown_seconds = 25,
            effect = "damage_over_time",
            display_name = "Mark of Flame",
            subtitle = "Single-Target DoT",
            role = "damage",
            element = "lava",
            target = "single",
            glyph = "debuff",
            unlock_level = 6,
        },
        ember_ward = {
            archetype = "pyromancer",
            focus_cost = 20,
            cooldown_seconds = 30,
            effect = "shield",
            display_name = "Ember Ward",
            subtitle = "Single-Pet Shield",
            role = "shield",
            element = "lava",
            target = "single_pet",
            glyph = "shield",
            unlock_level = 6,
        },
        eruption = {
            archetype = "pyromancer",
            focus_cost = 45,
            cooldown_seconds = 60,
            effect = "aoe_damage",
            display_name = "Eruption",
            subtitle = "AoE Damage",
            role = "damage",
            element = "lava",
            target = "targeted_aoe",
            glyph = "burst",
            unlock_level = 9,
        },
        critical_strike = {
            archetype = "pyromancer",
            focus_cost = 30,
            cooldown_seconds = 40,
            effect = "crit_up",
            display_name = "Critical Strike",
            subtitle = "Team Crit Buff",
            role = "buff",
            element = "lava",
            target = "team_aoe",
            glyph = "buff",
            unlock_level = 9,
        },
        scorch = {
            archetype = "pyromancer",
            focus_cost = 16,
            cooldown_seconds = 18,
            effect = "scorch",
            display_name = "Scorch",
            subtitle = "Single-Target Debuff",
            role = "debuff",
            element = "lava",
            target = "single",
            glyph = "debuff",
            unlock_level = 12,
        },
        fire_nova = {
            archetype = "pyromancer",
            focus_cost = 40,
            cooldown_seconds = 50,
            effect = "fire_nova",
            display_name = "Fire Nova",
            subtitle = "Self-AoE Burn",
            role = "damage",
            element = "lava",
            target = "player_field",
            glyph = "burst",
            unlock_level = 12,
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
            subtitle = "AoE DoT (spreads)",
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
            subtitle = "AoE Cleave",
            signature = true,
            role = "damage",
            element = "lava",
            target = "team_aoe",
            glyph = "burst",
            unlock_level = 22,
        },
        cataclysm = {
            archetype = "pyromancer",
            focus_cost = 60,
            cooldown_seconds = 90,
            effect = "cataclysm",
            display_name = "Cataclysm",
            subtitle = "AoE Nuke",
            signature = true,
            capstone = true,
            role = "damage",
            element = "lava",
            target = "targeted_aoe",
            glyph = "burst",
            unlock_level = 44,
        },

        -- ===== Origin signatures (docs/PET_REALM_SIGNATURE_POWERS.md) — 4 per origin, each in its
        -- identity. element drives the badge disc colour; glyph drives the symbol; target the ring. =====
        -- Earth / Geomancer — SHIELD/tank
        bastion = {
            archetype = "geomancer",
            focus_cost = 30,
            cooldown_seconds = 35,
            effect = "bastion",
            display_name = "Bastion",
            subtitle = "Team Shield",
            signature = true,
            role = "shield",
            element = "earth",
            target = "team_aoe",
            glyph = "shield",
            unlock_level = 15,
        },
        seismic_hold = {
            archetype = "geomancer",
            focus_cost = 30,
            cooldown_seconds = 40,
            effect = "seismic_hold",
            display_name = "Seismic Event",
            subtitle = "AoE Knockback + DoT",
            signature = true,
            role = "control",
            element = "earth",
            target = "targeted_aoe",
            glyph = "hold",
            unlock_level = 22,
        },
        living_mountain = {
            archetype = "geomancer",
            focus_cost = 40,
            cooldown_seconds = 55,
            effect = "living_mountain",
            display_name = "Living Mountain",
            subtitle = "Team Defense + Heal",
            signature = true,
            role = "shield",
            element = "earth",
            target = "team_aoe",
            glyph = "shield",
            unlock_level = 30,
        },
        gaia_colossus = {
            archetype = "geomancer",
            focus_cost = 70,
            cooldown_seconds = 120,
            effect = "gaia_colossus",
            display_name = "Gaia's Colossus",
            subtitle = "Summon Guardian",
            signature = true,
            capstone = true,
            role = "summon",
            element = "earth",
            target = "friendly",
            glyph = "summon",
            unlock_level = 44,
        },
        -- Fire / Pyromancer — DAMAGE (4th)
        inferno_brand = {
            archetype = "pyromancer",
            focus_cost = 20,
            cooldown_seconds = 22,
            effect = "inferno_brand",
            display_name = "Inferno Brand",
            subtitle = "Single-Target DoT",
            signature = true,
            role = "damage",
            element = "lava",
            target = "single",
            glyph = "brand",
            unlock_level = 30,
        },
        -- Ice / Cryomancer — CONTROL
        permafrost = {
            archetype = "cryomancer",
            focus_cost = 25,
            cooldown_seconds = 30,
            effect = "permafrost",
            display_name = "Permafrost",
            subtitle = "AoE Root + DoT",
            signature = true,
            role = "control",
            element = "ice",
            target = "targeted_aoe",
            glyph = "hold",
            unlock_level = 15,
        },
        shatter = {
            archetype = "cryomancer",
            focus_cost = 25,
            cooldown_seconds = 28,
            effect = "shatter",
            display_name = "Shatter",
            subtitle = "AoE Damage",
            signature = true,
            role = "damage",
            element = "ice",
            target = "targeted_aoe",
            glyph = "burst",
            unlock_level = 22,
        },
        absolute_zero = {
            archetype = "cryomancer",
            focus_cost = 45,
            cooldown_seconds = 60,
            effect = "absolute_zero",
            display_name = "Absolute Zero",
            subtitle = "AoE Hard Freeze",
            signature = true,
            role = "control",
            element = "ice",
            target = "targeted_aoe",
            glyph = "hold",
            unlock_level = 30,
        },
        eternal_winter = {
            archetype = "cryomancer",
            focus_cost = 70,
            cooldown_seconds = 120,
            effect = "eternal_winter",
            display_name = "Eternal Winter",
            subtitle = "AoE Hold + DoT",
            signature = true,
            capstone = true,
            role = "control",
            element = "ice",
            target = "targeted_aoe",
            glyph = "hold",
            unlock_level = 44,
        },
        -- Desert / Sandwalker — HEAL/sustain
        oasis = {
            archetype = "sandwalker",
            focus_cost = 25,
            cooldown_seconds = 30,
            effect = "oasis",
            display_name = "Oasis",
            subtitle = "Team Heal",
            signature = true,
            role = "heal",
            element = "desert",
            target = "team_aoe",
            glyph = "heal",
            unlock_level = 15,
        },
        mirage_veil = {
            archetype = "sandwalker",
            focus_cost = 20,
            cooldown_seconds = 25,
            effect = "mirage_veil",
            display_name = "Mirage Veil",
            subtitle = "Team Shield",
            signature = true,
            role = "shield",
            element = "desert",
            target = "team_aoe",
            glyph = "shield",
            unlock_level = 22,
        },
        simoom = {
            archetype = "sandwalker",
            focus_cost = 35,
            cooldown_seconds = 45,
            effect = "simoom",
            display_name = "Simoom",
            subtitle = "AoE Heal",
            signature = true,
            role = "heal",
            element = "desert",
            target = "team_aoe",
            glyph = "heal",
            unlock_level = 30,
        },
        genie_dunes = {
            archetype = "sandwalker",
            focus_cost = 70,
            cooldown_seconds = 120,
            effect = "genie_dunes",
            display_name = "Genie of the Dunes",
            subtitle = "Summon + Revive",
            signature = true,
            capstone = true,
            role = "summon",
            element = "desert",
            target = "friendly",
            glyph = "summon",
            unlock_level = 44,
        },
    },
}
