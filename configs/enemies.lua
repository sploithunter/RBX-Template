--[[
    Enemies — Halo & Horns [PROTOTYPE] (Feature 10: Combat).

    Enemy archetypes. Each enemy has:
      role       — combat role, the MIRROR of the pet roles (configs/pet_roles.lua):
                   tank | melee | ranged | support. A TAG for now (drives the enemy HUD
                   threat read + future role-motion: tanks plant, ranged kite, etc.). Movement
                   is NOT yet role-driven — that lands as a separate A/B pass so we can compare.
      hp         — base health (10x world: pools x10 both sides, damage untouched —
                   see configs/combat.lua pet_down_threshold_factor; scaled by party size at spawn)
      tier       — Spirit Form cooldown tier applied to a pet this enemy downs
                   (maps to configs/spirit_form.lua cooldown_tiers)
      attack     — { damage, cadence, sundering }
                     damage    = damage dealt to a targeted pet per hit
                     cadence   = seconds between attacks
                     sundering = Focus drained from the player per hit (0 = none)
      auto_heal  — (support) { interval, amount, range }: mends the most-hurt nearby enemy.
      model_asset— uploaded model id (cloned via AssetFetch → PlaceAssets cache). Omit and the
                   service builds a procedural block (placeholder until the art is imported).
      drop_table — currency/token amounts on defeat (numeric = deterministic; *_chance = random).

    EARTH enemy faction (the starter biome's wild creatures, the dark mirror of your Earth pets):
      tank=bear · melee=rabid_dog · ranged=murder_crow + vicious_cat · support=rabid_bunny.
    Read by CombatService via ConfigLoader; pure math lives in `src/Shared/Game/CombatMath.lua`.
]]

return {
    -- Proximity baddie spawners (Jason): map parts named BaddieSpawner* spawn a wave when a
    -- player comes near — "a taste of combat before they decide to go up or down the tree."
    spawners = {
        part_prefix = "BaddieSpawner",
        radius = 50, -- studs: trigger distance from the part
        -- RANDOM cooldown (Jason: "sometimes you'll get more than one") — each trigger rolls a
        -- value in [min,max]; a short roll can land a second wave while the first is still up.
        cooldown = { min = 30, max = 120 },
        -- hard cap on LIVING baddies per spawner (don't bury the player / stockpile for the next).
        max_alive = 8,
        scatter = 8, -- studs: random spread around the part so the wave isn't a stack
        -- VARIETY (Jason): weighted compositions, not just "3 imps / 1 bear". Mixed-role packs make
        -- the role + surround systems sing — a healer behind a tank reads totally differently from a
        -- melee swarm. Weight = relative frequency (rarer = scarier). NOTE: rabid_dog/murder_crow/
        -- vicious_cat render as PLACEHOLDER blocks until their meshes are uploaded — the comps are
        -- wired and play now; the art swaps in later.
        waves = {
            -- common: a fast melee swarm
            { weight = 10, units = { { enemy = "rabid_dog", count = 3 } } },
            -- common: a lone bruiser to soak
            { weight = 9, units = { { enemy = "raging_bear", count = 1 } } },
            -- a murder of crows — ranged harass, fragile (focus them down)
            { weight = 7, units = { { enemy = "murder_crow", count = 3 } } },
            -- backline healer + escorts: kill the bunny first or grind forever
            {
                weight = 6,
                units = {
                    { enemy = "rabid_bunny", count = 1 },
                    { enemy = "rabid_dog", count = 2 },
                },
            },
            -- warband: tank anchor + melee + a sniper
            {
                weight = 6,
                units = {
                    { enemy = "raging_bear", count = 1 },
                    { enemy = "rabid_dog", count = 2 },
                    { enemy = "murder_crow", count = 1 },
                },
            },
            -- ambush: ranged duo + a flanking cat
            {
                weight = 5,
                units = {
                    { enemy = "murder_crow", count = 2 },
                    { enemy = "vicious_cat", count = 1 },
                },
            },
            -- THE SCARY TEAM (Jason): a full role-balanced pack — a bruiser wall, a healer keeping
            -- it alive, melee crowding in, and a sniper picking off your backline. Rare, and a real
            -- check on a one-note squad (you want your OWN tank/heal to answer it).
            {
                weight = 2,
                units = {
                    { enemy = "ember_brute", count = 1 }, -- tank wall
                    { enemy = "rabid_bunny", count = 1 }, -- healer (kill first)
                    { enemy = "rabid_dog", count = 3 }, -- melee crowd
                    { enemy = "murder_crow", count = 2 }, -- snipers
                },
            },
        },
    },

    enemies = {
        -- ============================ EARTH FACTION ============================
        -- MELEE — fast, fragile, gets in your face (the new cube_dog art).
        rabid_dog = {
            role = "melee",
            hp = 1400,
            display_name = "Rabid Dog",
            tier = "trash_mob",
            move_speed = 16, -- quick + aggressive
            armor = 0,
            -- Real art (cube_dog): mesh + texture uploaded separately to the Open Simulator group,
            -- combined at spawn via CreateMeshPartAsync (the gem pattern) — no InsertService fetch.
            mesh_asset = "rbxassetid://139565210250366",
            texture_asset = "rbxassetid://87011938206497",
            model_scale = 4,
            gait = { style = "waddle", bob_height = 0.5, tilt_degrees = 14, stride_length = 4 },
            attack = { damage = 12, cadence = 1.3, sundering = 0 },
            drop_table = { grass_coins = 9, shadow_tokens = 1 },
        },
        -- RANGED — a murder of crows: hits a touch harder, very squishy (the new raven art).
        murder_crow = {
            role = "ranged",
            hp = 850,
            display_name = "Murder Crow",
            tier = "trash_mob",
            move_speed = 14,
            armor = 0,
            -- Real art (raven): mesh + texture combined at spawn via CreateMeshPartAsync.
            mesh_asset = "rbxassetid://79312260838341",
            texture_asset = "rbxassetid://120154730842284",
            model_scale = 4,
            gait = { style = "hop", bob_height = 0.7, tilt_degrees = 6, stride_length = 5 },
            attack = { damage = 14, cadence = 1.6, sundering = 0 },
            drop_table = { grass_coins = 10, shadow_tokens = 1 },
        },
        -- RANGED — a vicious cat: a second ranged flavour, slightly tankier than the crow (grumpy_cat).
        vicious_cat = {
            role = "ranged",
            hp = 1000,
            display_name = "Vicious Cat",
            tier = "trash_mob",
            move_speed = 15,
            armor = 0,
            -- Real art (grumpy_cat): mesh + texture combined at spawn via CreateMeshPartAsync.
            mesh_asset = "rbxassetid://140220411587261",
            texture_asset = "rbxassetid://89093502801465",
            model_scale = 4,
            gait = { style = "waddle", bob_height = 0.5, tilt_degrees = 10, stride_length = 4 },
            attack = { damage = 13, cadence = 1.5, sundering = 0 },
            drop_table = { grass_coins = 10, shadow_tokens = 2 },
        },
        -- SUPPORT — the rabid bunny, now wearing its REAL art: the "Midnight Horned Rabbit"
        -- jackalope (a dark, antlered hare). An enemy HEALER that mends the most-hurt nearby enemy;
        -- kill it first to flip the fight. Mesh + texture combined at spawn via CreateMeshPartAsync
        -- (the gem pattern) — uploaded self-serve to the Open Simulator group (see the manifest /
        -- scripts/pet_pipeline.md). NB: texture_asset is the resolved IMAGE id, not the Decal id the
        -- Open Cloud upload returns (MeshPart.TextureID needs the underlying image, else it renders grey).
        rabid_bunny = {
            role = "support",
            hp = 1100,
            display_name = "Jackalope",
            tier = "trash_mob",
            move_speed = 13,
            armor = 0,
            mesh_asset = "rbxassetid://111943527947344",
            texture_asset = "rbxassetid://71212761122379",
            model_scale = 4,
            gait = { style = "waddle", bob_height = 0.5, tilt_degrees = 16, stride_length = 3.5 },
            attack = { damage = 6, cadence = 2.0, sundering = 0 },
            auto_heal = { interval = 2.5, amount = 100, range = 45 },
            drop_table = { grass_coins = 12, shadow_tokens = 2 },
        },
        -- TANK — the bear: thick hide, soaks for the pack (the bear art). The wall of the faction.
        raging_bear = {
            role = "tank",
            hp = 3500,
            display_name = "Raging Bear",
            tier = "mid_tier",
            move_speed = 11, -- charges in faster than the brute
            armor = 70, -- thick hide: ~41% pet-damage reduction at k=100
            model_asset = 99990991951749,
            model_scale = 5,
            needs_primary_part = true,
            gait = { style = "waddle", bob_height = 0.8, tilt_degrees = 12, stride_length = 6 },
            attack = { damage = 22, cadence = 1.8, sundering = 0 },
            drop_table = { grass_coins = 35, shadow_tokens = 4, rare_drop_chance = 0.12 },
        },

        -- ============================ LAVA / HELL FACTION (existing) ============================
        lava_imp = {
            role = "melee",
            hp = 1200,
            display_name = "Lava Imp",
            tier = "trash_mob",
            move_speed = 15,
            armor = 0,
            -- No model: Lava faction is unmodeled, so the service builds a procedural placeholder
            -- block. (It USED to borrow the bunny art 110801864701636 — but that asset is now the
            -- rabid_bunny support enemy, so spawning an imp looked like spawning rabbits. Jason.)
            gait = { style = "waddle", bob_height = 0.5, tilt_degrees = 16, stride_length = 3.5 },
            attack = { damage = 10, cadence = 1.5, sundering = 0 },
            drop_table = { lava_coins = 8, shadow_tokens = 1 },
        },
        ember_brute = {
            role = "tank",
            hp = 4000,
            display_name = "Ember Brute",
            tier = "mid_tier",
            move_speed = 10, -- heavier, slower
            armor = 80, -- tougher: ~44% pet-damage reduction at k=100
            gait = { style = "march", bob_height = 0.9, tilt_degrees = 4, stride_length = 7 },
            -- A Sundering attacker: drains player Focus on hit (Feature 12).
            attack = { damage = 25, cadence = 2.0, sundering = 20 },
            drop_table = { lava_coins = 30, shadow_tokens = 4, rare_drop_chance = 0.1 },
        },
        ember_acolyte = {
            role = "support",
            hp = 2000,
            display_name = "Ember Acolyte",
            tier = "trash_mob",
            move_speed = 13,
            armor = 0,
            attack = { damage = 8, cadence = 2.0, sundering = 0 },
            -- Enemy HEALER: restores HP to the most-hurt nearby enemy (mirrors the support role).
            auto_heal = { interval = 2.0, amount = 120, range = 45 },
            drop_table = { lava_coins = 12, shadow_tokens = 2 },
        },
        dire_bear = {
            role = "tank",
            hp = 65000,
            display_name = "Dire Bear",
            tier = "boss",
            move_speed = 8, -- lumbering colossus
            armor = 230, -- ~70% pet-damage reduction at k=100
            model_asset = 99990991951749,
            model_scale = 11,
            needs_primary_part = true,
            gait = { style = "march", bob_height = 1.4, tilt_degrees = 3, stride_length = 11 },
            attack = { damage = 75, cadence = 2.6, sundering = 35 },
            drop_table = { lava_coins = 280, shadow_tokens = 32, rare_drop_chance = 0.5 },
        },
        infernal_boss = {
            role = "tank",
            hp = 50000,
            display_name = "Infernal Boss",
            tier = "boss",
            move_speed = 8, -- lumbering
            armor = 200, -- heavily armored (~67% reduction at k=100)
            gait = { style = "march", bob_height = 1.3, tilt_degrees = 3, stride_length = 10 },
            attack = { damage = 60, cadence = 2.5, sundering = 40 },
            drop_table = { lava_coins = 200, shadow_tokens = 25 },
        },

        -- [TEST] Tanky harmless dummy for measuring damage/AoE. Enormous HP, zero attack, stationary.
        training_dummy = {
            role = "tank",
            hp = 1000000,
            display_name = "Training Dummy",
            tier = "trash_mob",
            move_speed = 0,
            armor = 0,
            attack = { damage = 0, cadence = 999, sundering = 0 },
            gait = { style = "march", bob_height = 0, tilt_degrees = 0, stride_length = 0 },
            drop_table = {},
        },
    },
}
