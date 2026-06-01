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
    enemies = {
        lava_imp = {
            hp = 120,
            tier = "trash_mob",
            move_speed = 15, -- studs/sec while chasing (slice 2); skittery + fast
            armor = 0, -- defensive stat: pet damage mitigated by armor/(armor+k)
            -- Real art (uploaded model). EnemyService clones+anchors+scales it; falls
            -- back to the procedural block if the asset can't load. model_scale brings
            -- the ~1.9-stud mesh up to enemy size (~7.6 tall).
            model_asset = 110801864701636,
            model_scale = 4,
            attack = { damage = 10, cadence = 1.5, sundering = 0 },
            drop_table = { lava_coins = 8, shadow_tokens = 1 },
        },
        ember_brute = {
            hp = 400,
            tier = "mid_tier",
            move_speed = 10, -- heavier, slower
            armor = 80, -- tougher: ~44% pet-damage reduction at k=100
            -- A Sundering attacker: drains player Focus on hit (Feature 12).
            attack = { damage = 25, cadence = 2.0, sundering = 20 },
            drop_table = { lava_coins = 30, shadow_tokens = 4, rare_drop_chance = 0.1 },
        },
        infernal_boss = {
            hp = 5000,
            tier = "boss",
            move_speed = 8, -- lumbering
            armor = 200, -- heavily armored (~67% reduction at k=100)
            attack = { damage = 60, cadence = 2.5, sundering = 40 },
            drop_table = { lava_coins = 200, shadow_tokens = 25 },
        },
    },
}
