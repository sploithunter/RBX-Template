--[[
    Enemies — Halo & Horns [PROTOTYPE] (Feature 10: Combat).

    Enemy archetypes for Hell-focused combat. Each enemy has:
      hp         — base health (scaled by party size at spawn, see configs/combat.lua)
      tier       — Spirit Form cooldown tier applied to a pet this enemy downs
                   (maps to configs/spirit_form.lua cooldown_tiers)
      attack     — { damage, cadence, sundering }
                     damage    = damage dealt to a targeted pet per hit
                     cadence   = seconds between attacks
                     sundering = Focus drained from the player per hit (0 = none)
      drop_table — currency/token amounts awarded on defeat (numeric keys are
                   awarded deterministically; *_chance keys are random [studio]).

    Read by CombatService via ConfigLoader; pure math lives in
    `src/Shared/Game/CombatMath.lua`.
]]

return {
    -- Proximity baddie spawners (Jason): map parts named BaddieSpawner* (he placed
    -- BaddieSpawnerLava + BaddieSpawnerDesert) spawn a wave when a player comes near —
    -- "a taste of combat before they decide to go up or down the Heaven/Hell tree."
    -- No bosses here (no real models yet).
    spawners = {
        part_prefix = "BaddieSpawner",
        radius = 50, -- studs: trigger distance from the part
        -- RANDOM cooldown (Jason: "sometimes you'll get more than one") — each trigger
        -- rolls a value in [min,max]; a short roll can land a second wave while the
        -- first is still up.
        cooldown = { min = 30, max = 120 },
        -- hard cap on LIVING baddies tied to one spawner (Jason: don't bury the
        -- player, and no stockpiling a crap ton for the next guy) — at the cap the
        -- spawner stays quiet until some die.
        max_alive = 6,
        scatter = 8, -- studs: random spread around the part so the wave isn't a stack
        waves = {
            { weight = 10, units = { { enemy = "lava_imp", count = 3 } } },
            { weight = 10, units = { { enemy = "raging_bear", count = 1 } } },
            -- the rare one: the full welcoming committee
            {
                weight = 2,
                units = {
                    { enemy = "lava_imp", count = 3 },
                    { enemy = "raging_bear", count = 1 },
                },
            },
        },
    },

    enemies = {
        lava_imp = {
            hp = 120,
            display_name = "Lava Imp",
            tier = "trash_mob",
            move_speed = 15, -- studs/sec while chasing (slice 2); skittery + fast
            armor = 0, -- defensive stat: pet damage mitigated by armor/(armor+k)
            -- Real art (uploaded model). EnemyService clones+anchors+scales it; falls
            -- back to the procedural block if the asset can't load. model_scale brings
            -- the ~1.9-stud mesh up to enemy size (~7.6 tall). needs_primary_part = the
            -- model ships without a PrimaryPart, so the service assigns one (first part);
            -- omit it for models that already define their own PrimaryPart.
            model_asset = 110801864701636,
            model_scale = 4,
            needs_primary_part = true,
            -- Skittery little imp: quick, springy waddle with an exaggerated tilt.
            gait = { style = "waddle", bob_height = 0.5, tilt_degrees = 16, stride_length = 3.5 },
            attack = { damage = 10, cadence = 1.5, sundering = 0 },
            drop_table = { lava_coins = 8, shadow_tokens = 1 },
        },
        -- [TEST] A tanky, harmless training dummy for measuring damage + AoE. Enormous HP so it
        -- survives a whole test session (damage keeps logging instead of one-shotting), zero attack
        -- so it never hurts pets, stationary so an AoE cluster stays put, and zero armor so the
        -- numbers you read are the pet's/power's RAW output (raise armor to test mitigation). Spawn
        -- via the combat.spawnEnemy bus command; read damage as MaxHP-HP or the Contrib ledger.
        training_dummy = {
            hp = 100000,
            display_name = "Training Dummy",
            tier = "trash_mob",
            move_speed = 0,
            armor = 0,
            attack = { damage = 0, cadence = 999, sundering = 0 },
            gait = { style = "march", bob_height = 0, tilt_degrees = 0, stride_length = 0 },
            drop_table = {},
        },
        ember_brute = {
            hp = 400,
            display_name = "Ember Brute",
            tier = "mid_tier",
            move_speed = 10, -- heavier, slower
            armor = 80, -- tougher: ~44% pet-damage reduction at k=100
            -- Heavy bruiser: a slow, stiff march with a deep stomp and little tilt.
            gait = { style = "march", bob_height = 0.9, tilt_degrees = 4, stride_length = 7 },
            -- A Sundering attacker: drains player Focus on hit (Feature 12).
            attack = { damage = 25, cadence = 2.0, sundering = 20 },
            drop_table = { lava_coins = 30, shadow_tokens = 4, rare_drop_chance = 0.1 },
        },
        ember_acolyte = {
            hp = 200,
            display_name = "Ember Acolyte",
            tier = "trash_mob",
            move_speed = 13,
            armor = 0,
            attack = { damage = 8, cadence = 2.0, sundering = 0 },
            -- Enemy HEALER: restores HP to the most-hurt nearby enemy on a cadence (mirrors
            -- the pet support role). Kill the acolyte first to flip the fight.
            auto_heal = { interval = 2.0, amount = 120, range = 45 },
            drop_table = { lava_coins = 12, shadow_tokens = 2 },
        },
        raging_bear = {
            hp = 350,
            display_name = "Raging Bear",
            tier = "mid_tier",
            move_speed = 11, -- charges in faster than the brute
            armor = 70, -- thick hide: ~41% pet-damage reduction at k=100
            -- Real art (uploaded model: a bear MeshPart, no PrimaryPart). Native ~1.9 tall;
            -- model_scale 5 brings it to ~9.5 — bigger and meaner than the imp.
            model_asset = 99990991951749,
            model_scale = 5,
            needs_primary_part = true,
            -- Heavy aggressive lope: a big springy waddle with a pronounced shoulder roll.
            gait = { style = "waddle", bob_height = 0.8, tilt_degrees = 12, stride_length = 6 },
            attack = { damage = 22, cadence = 1.8, sundering = 0 },
            drop_table = { lava_coins = 35, shadow_tokens = 4, rare_drop_chance = 0.12 },
        },
        dire_bear = {
            hp = 6500,
            display_name = "Dire Bear",
            tier = "boss",
            move_speed = 8, -- lumbering colossus
            armor = 230, -- ~70% pet-damage reduction at k=100
            -- Same bear art, scaled WAY up for a boss: ~1.9 * 11 = ~21 studs tall.
            model_asset = 99990991951749,
            model_scale = 11,
            needs_primary_part = true,
            -- Ground-shaking march: deep slow stomp, minimal tilt (too massive to sway).
            gait = { style = "march", bob_height = 1.4, tilt_degrees = 3, stride_length = 11 },
            attack = { damage = 75, cadence = 2.6, sundering = 35 },
            drop_table = { lava_coins = 280, shadow_tokens = 32, rare_drop_chance = 0.5 },
        },
        infernal_boss = {
            hp = 5000,
            display_name = "Infernal Boss",
            tier = "boss",
            move_speed = 8, -- lumbering
            armor = 200, -- heavily armored (~67% reduction at k=100)
            -- Lumbering colossus: huge slow ground-shaking stomp, almost no tilt.
            gait = { style = "march", bob_height = 1.3, tilt_degrees = 3, stride_length = 10 },
            attack = { damage = 60, cadence = 2.5, sundering = 40 },
            drop_table = { lava_coins = 200, shadow_tokens = 25 },
        },
    },
}
