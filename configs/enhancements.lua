--[[
    Enhancements — Halo & Horns (CoH-style power slotting).

    An enhancement is a record { type, origins } that fills one of a power's EMPTY slots
    (data.Slots[powerId], earned at slot levels) and boosts ONE stat axis of THAT power.

    GRADES (Jason's design):
      • SINGLE-origin — { origins = { "pyromancer" } }. Disc + ring in the SAME color group.
        Stronger (values.single), but usable only when the PLAYER's origin matches.
      • DUAL-origin   — { origins = { "pyromancer", "cryomancer" } }. Disc + ring in DIFFERENT
        color groups. Weaker (values.dual), usable by EITHER origin — twice as often useful,
        deliberately less potent.

    Type → axis → families: each type boosts one PowerStats axis and only fits powers whose
    effect FAMILY it makes sense on (families = "*" means any). `requires_aoe` additionally
    blocks the type on non-AoE powers (Range on a melee/single-target power is meaningless).

    Visuals: disc = the type's symbol in origins[1]'s color; ring = the `enhancement` ring
    (power_icons.rings.enhancement, grayscale) tinted origins[2] or origins[1]'s color.
]]

return {
    -- The four origins (archetype ids — usability checks read the player's data.Archetype).
    origins = { "geomancer", "pyromancer", "cryomancer", "sandwalker" },

    -- Short flavor prefix per origin for display names ("Pyro Damage", "Geo/Cryo Recharge").
    origin_names = {
        geomancer = "Geo",
        pyromancer = "Pyro",
        cryomancer = "Cryo",
        sandwalker = "Sand",
    },

    -- Boost fraction by grade: effective axis = base × (1 + Σ values) — recharge divides instead
    -- (base / (1 + Σ)) so a recharge enhancement SHORTENS the cooldown.
    values = {
        single = 0.33,
        dual = 0.20,
        natural = 0.15, -- origin-less generic (pre-origin players' tier; usable by all)
    },

    -- type -> { symbol (disc icon key), axis (PowerStats axis), families ("*" or set),
    --           requires_aoe? } — see header. Families list mirrors docs (Jason's table).
    types = {
        damage = {
            symbol = "fist",
            axis = "damage",
            families = {
                vulnerable = true,
                buff = true,
                rage = true,
                amplified_burst = true,
                burn_spread = true,
                team_cleave = true,
            },
        },
        accuracy = {
            symbol = "target",
            axis = "accuracy",
            -- Only families that ROLL to-hit (_accuracyHit: vulnerable marks, root holds) AND land
            -- below 1.0 (accuracy_family_base) — there a +accuracy enhancement actually improves the
            -- chance the debuff lands. Other families auto-land (no roll) → accuracy was a dead slot.
            families = {
                vulnerable = true,
                root = true,
            },
        },
        recharge = {
            symbol = "history",
            axis = "recharge",
            families = "*", -- anything WITH a cooldown benefits from shortening it
            excludes_passive = true, -- Jason: "Magnet doesn't need recharge" — always-on
            -- powers (passive/toggle kinds) have nothing to recharge
        },
        armor = {
            symbol = "armor_chest",
            axis = "magnitude",
            families = { defense_buff = true, armor = true, fortify = true },
        },
        shield = {
            symbol = "shield",
            axis = "magnitude",
            families = { absorb = true },
        },
        health = {
            -- broad survivability: boosts the magnitude of any endurance-protecting power
            symbol = "heart",
            axis = "magnitude",
            families = { heal = true, absorb = true, defense_buff = true, armor = true },
        },
        range = {
            symbol = "range",
            axis = "radius",
            -- Only families with a REAL radius the game reads: Magnet (collect reach, via the
            -- radius_families magnitude fold), Cataclysm's burst, Firestorm's cleave, Wildfire's
            -- spread. The other "AoE" debuffs hit ALL engaged enemies (no radius to widen), so range
            -- was a dead slot there — excluded. (Gives a power a `radius` to bring it back in.)
            families = {
                magnet = true,
                amplified_burst = true,
                team_cleave = true,
                burn_spread = true,
            },
            requires_aoe = true, -- still blocked on melee / single-target powers
        },
        duration = {
            symbol = "hourglass",
            axis = "duration",
            families = {
                buff = true,
                defense_buff = true,
                armor = true,
                fortify = true,
                absorb = true,
                vulnerable = true,
                root = true,
                root_guard = true,
                fear = true,
                taunt = true,
                luck = true,
                -- rage is a TOGGLE (no duration to extend) — dropped (was a no-op slot)
                drop_rate = true, -- Windfall: extend the loot-chance window (it has duration=10)
            },
        },
        -- POTENCY (Jason): +% to the power's own magnitude — the universal "makes the
        -- power more" type, and what makes always-on passives slottable (Swift runs
        -- faster, XP Surge pays more, Magnet pulls wider). Magnitude-driven families.
        potency = {
            symbol = "potency", -- Jason's batch-4 art (was chevrons_up placeholder)
            axis = "magnitude",
            families = {
                buff = true,
                coin_yield = true,
                crit = true,
                drop_rate = true, -- Windfall: boost the +drop-chance magnitude (it has magnitude=2.0)
                luck = true,
                magnet = true,
                move_speed = true,
                recharge = true, -- Hasten's recharge-BUFF magnitude
                xp = true,
                rage = true,
                vulnerable = true,
            },
        },
        -- SPARK (the FIRST proc — Jason: ship one now to prove the mechanics; rare
        -- multi-effect specialties come later and build on this shape). On a damaging
        -- power hit: `chance` to surge the hit for +`bonus` of its damage.
        spark = {
            symbol = "proc", -- Jason's batch-4 art (was capacitor placeholder)
            proc = { trigger = "hit", chance = 0.15, bonus = 1.0 },
            -- Gated to families that deal/credit REAL damage (the proc surges a hit's damage by
            -- `bonus`). Pure buffs/debuffs (vulnerable/buff/rage) have no hit to proc on, so they're
            -- excluded — spark there was a dead slot.
            families = {
                amplified_burst = true, -- Cataclysm (burst credited to pets)
                burn_spread = true, -- Wildfire (DoT)
                team_cleave = true, -- Firestorm (cleave splash)
            },
        },
        healing = {
            symbol = "plus",
            axis = "heal",
            families = { heal = true, heal_blind = true },
        },
    },

    -- Power `target` values that count as AoE for `requires_aoe` types.
    aoe_targets = {
        targeted_aoe = true,
        team_aoe = true,
        player_field = true,
        eruption = true,
        single_spread = true,
    },

    -- Effect FAMILIES whose magnitude IS a radius — `range` applies to these even
    -- without an AoE target (Jason: Magnet's only sensible enhancement is range).
    radius_families = {
        magnet = true,
    },

    -- Effect FAMILIES whose magnitude IS their "damage" — these player powers deal no direct damage
    -- (firewall): their POTENCY lives in `magnitude` (vulnerability %, pet-damage buff, burst/cleave
    -- mult). A `damage` enhancement folds into magnitude here (else it scales a 0 damageBase → "no
    -- change"). burn_spread (Wildfire) is INTENTIONALLY excluded — it has a real DoT damageBase, so
    -- its `damage` enhancement scales the burn directly.
    damage_as_magnitude_families = {
        vulnerable = true, -- Sandstorm / Mark of Flame / Sunder / … (+% enemies take)
        buff = true, -- Mountain's Strength (+% pet damage)
        rage = true, -- Rage (HP-inverse pet damage)
        amplified_burst = true, -- Cataclysm (burst = squad-attack × magnitude)
        team_cleave = true, -- Firestorm (cleave splash × magnitude)
    },

    -- Effect FAMILIES whose magnitude IS their "heal" — heal powers store the heal amount in
    -- `magnitude` (no healBase is ever set), so a `healing` enhancement folds into magnitude (else
    -- it scales a 0 healBase → "no change"). Same fold home as the damage/radius folds.
    heal_as_magnitude_families = {
        heal = true,
        heal_blind = true,
    },

    -- DROPS: rolled when a breakable/enemy dies (DropService). The MODEL is semi-generic — the
    -- identity (type/origins) is revealed at pickup via the GameEvents float.
    drops = {
        enabled = true,
        -- chance per breakable broken / enemy defeated that an enhancement drops
        -- (doubled 0.02/0.08 -> 0.04/0.16, Jason 2026-06-11: a full 1->6 leveling run
        -- yielded only two drops that fit any of his powers; roll back if it floods)
        breakable_chance = 0.04,
        enemy_chance = 0.16,
        -- of those drops, this fraction are NATURAL (origin-less junk tier) — Jason:
        -- "allow generics to drop everywhere; that makes an actual junk economy."
        -- The rest are zone-branded origin drops (~25/75 single/dual structurally).
        natural_chance = 0.5,
        -- grade split for a drop: single is the rarer, better find
        single_chance = 0.35,
        -- DROP LEVEL by area (Jason): an enhancement rolls its level from the band of the
        -- area it drops in, +/- jitter (clamped to 1). The whole home world is 1-5; future
        -- realms add their own band keyed by the player's CurrentArea attribute value.
        levels = {
            jitter = 2,
            -- DELIBERATELY ONE BAND for the whole homeworld — do NOT texture per zone
            -- (Jason): everyone starts in Grass/earth, so per-zone bands would
            -- disadvantage earth-origin players (their homeworld singles would roll
            -- low). Future realms ROTATE/SPIRAL the starting zone so every origin
            -- takes fair turns at "go back to your homeworld for the right stuff."

            -- CoH-style level scaling (Jason): an enhancement works within +/- `window`
            -- levels of the PLAYER. Above you (up to +2) = stronger; below = weaker;
            -- can't SLOT one more than `window` above you; one slotted that falls more
            -- than `window` BELOW you contributes NOTHING (stays slotted, boost dead).
            -- value multiplier = 1 + per_level * (enhLevel - playerLevel), so a single
            -- at +2 = 33% * 1.2 ~= 40%, at -2 = 33% * 0.8 ~= 26%. L50 players hunt L52s.
            scaling = { window = 2, per_level = 0.10 },
            -- FOLLOW-PLAYER (Jason, 2026-06-11: "I'm level 8 and there is no new
            -- world to get higher ones"): once the player outgrows an area's band,
            -- it slides up with them — effective band = { max(lo, player - span),
            -- max(hi, player) }, jitter on top. L8 on the 1-5 homeworld rolls 4-8
            -- (finds up to 10); L50 rolls 46-50 (hunts 52s). Below the band top
            -- nothing changes. Realm bands with high floors (e.g. {10,18}) still
            -- beat the slid homeworld band, so realm hunting stays worth it.
            follow_player = { enabled = true, span = 4 },
            bands = {
                default = { 1, 5 }, -- home world (Grass/Desert/Lava/Ice all use this today)
                -- ["SomeRealmArea"] = { 10, 18 },
            },
        },
        -- THE LAND SPEAKS (Jason): a drop's PRIMARY origin (the disc color) is always
        -- the zone's own — earth zone drops are always green. The RING (second origin)
        -- is random; when it rolls the zone's origin the drop is SINGLE-origin, so pure
        -- singles can only be found in their home world. Unmapped areas roll legacy.
        -- Keyed by the zone's BIOME/element (configs/areas.lua zones[*].element), NOT
        -- the area NAME — so EVERY grass area (Spawn, Meadow, ...) maps to geomancer,
        -- not just a literal "Grass" that no area is named (Jason: the old name-keyed
        -- table silently never matched grass, so geomancer interiors never dropped).
        -- The zone's origin is the cog INTERIOR at 100%; the RING is random. Spend
        -- time in your origin's biome to farm its interior.
        area_origins = {
            grass = "geomancer",
            lava = "pyromancer",
            ice = "cryomancer",
            desert = "sandwalker",
        },

        -- relative weight per type (uniform start; tune freely)
        type_weights = {
            spark = 0.25, -- procs are the rare tier (specialty drops later build on this)
            damage = 1,
            accuracy = 1,
            recharge = 1,
            armor = 1,
            shield = 1,
            health = 1,
            range = 1,
            duration = 1,
            healing = 1,
        },
        despawn_seconds = 45,
        -- Authored COGWHEEL drop model (Jason, 2026-06-09): ONE shared 3500-tri mesh + 6 color
        -- textures (scripts/cogwheel_model_ids.json). Color hints the ORIGIN on the ground
        -- (the TYPE stays hidden until pickup): singles use their origin's color, duals use
        -- purple (mixed), silver is the fallback/unknown.
        cog = {
            mesh = "rbxassetid://76065631196112",
            size = 1.6, -- widest-side studs (gem-drop scale)
            textures = {
                silver = "rbxassetid://70588294918015",
                green = "rbxassetid://129292347025511",
                blue = "rbxassetid://131082834586557",
                purple = "rbxassetid://97999269673992",
                red = "rbxassetid://88662935252644",
                yellow = "rbxassetid://79723645423878",
            },
            origin_colors = {
                geomancer = "green",
                pyromancer = "red",
                cryomancer = "blue",
                sandwalker = "yellow",
            },
            dual_color = "purple",
            fallback_color = "silver",
        },
        -- Optional override: a Model under ReplicatedStorage.Assets.Models takes precedence
        -- over the cog mesh when set.
        model_name = nil,
        pickup_radius = 8,
    },

    -- Max enhancements held in the inventory (oldest beyond the cap are refused, not deleted).
    inventory_cap = 60,

    -- Replacing an occupied slot DESTROYS the old enhancement (CoH-style commitment).
    replace_destroys = true,
}
