--[[
    Pet Configuration System
    
    Organizes pets by animal type with multiple variants (Basic, Golden, Rainbow)
    Includes power levels, rarities, and game mechanics for a complete pet system.
    
    Structure:
    - pets[animal_type][variant] = { stats, asset_id, etc. }
    - Easy to expand with new animals and variants
    - Balanced progression system with clear rarity tiers
--]]

local petConfig = {
    version = "1.0.0",

    -- Place an egg model (egg_sources id) centered inside a named map stand. The EggStandPlacement
    -- server script clones the loaded egg model and centers it at the stand's UIanchor (or pivot).
    -- Just name the stand + the egg here — no per-instance attributes/tags needed.
    -- Value may be a string (egg id) OR a table for tuning:
    --   { egg = "<id>", scale = <number>, offset_y = <studs> }
    --   scale    multiplies the egg model's size (Model:ScaleTo), default 1
    --   offset_y raises the egg above the stand anchor in studs, default 0
    egg_stand_placements = {
        ["BasicEarth"] = { egg = "earth_egg", scale = 3.5, offset_y = 0.5 },
        ["BasicEmber"] = { egg = "ember_egg", scale = 3.5, offset_y = 0.5 },
        ["BasicIce"] = { egg = "ice_egg", scale = 3.5, offset_y = 0.5 },
        ["BasicSand"] = { egg = "sand_egg", scale = 3.5, offset_y = 0.5 },
    },

    -- Eternal pets scale to a percentage of the player's "eternal power base"
    -- (the average of their top-N non-eternal pets, N = equip capacity). Huge
    -- pets use this percent (1.2 = 120%); balance-tunable. The pet's huge_base_power
    -- acts as a floor (see PetPower / PetHandler resolveEffectivePetPower).
    eternal = {
        huge_power_percent = 120,
        -- CREATOR pin (Jason: the huge creator pet is "essential for scaling work" and
        -- must ALWAYS be the strongest pet in the game — "we will never make a pet
        -- stronger"): a huge pet whose species category is "creator" scales at THIS
        -- percent instead of huge_power_percent. TWO reserved class slots sit between
        -- huge (120) and the pin, for future top tiers (titans 150, colossals 180,
        -- 30-point class steps) — the creator stays one full gap above even those.
        -- Variant-scaled like everything: 210 / 263 / 315 (the rainbow apex).
        creator_power_percent = 210,
        -- ETERNAL LEVEL BONUS (Jason, 2026-06-12): pet leveling shows up in the
        -- eternal OUTPUT too — one cap, normalized by the pet's max level:
        --   bonus = level_bonus_max x (level-1)/(maxLevel-1)
        -- A 100-level huge earns ~0.25%/level, a 50-level secret 0.5%/level, both
        -- landing exactly +25% at the capstone. Floors keep their own +2%/level
        -- (pet_progression.power_scaling); this multiplies the baseline x percent
        -- side only. A maxed lower class KNOCKS on the next class's door without
        -- passing it (basic secret 85 -> 106 vs basic huge 120).
        level_bonus_max = 0.25,
        -- UNIQUE => ETERNAL (Jason, 2026-06-12: "if pet is unique it is eternal").
        -- Rarity defaults applied when a species has no explicit eternal block.
        -- Hierarchy: huge 120 > exclusive 90 > secret 85 (Jason: exclusives outrank
        -- secrets — "you either have to meet a creator or buy an egg", an act of
        -- access; secrets are a lucky roll). The creator SPECIES is just an
        -- exclusive (no one-off block); the huge apex pins at creator_power_percent
        -- (130) above everything. All percents scale by variant
        -- (x1 / x1.25 / x1.5 — pet_roles.variant_effect_multipliers).
        default_percent_by_rarity = {
            exclusive = 90, -- 90 / 113 / 135
            secret = 85, -- 85 / 106 / 128
        },
        -- The eternal power base = average of the player's top-N pets (N = equip
        -- capacity). By default eternal/huge pets are EXCLUDED from that baseline
        -- (so their power never feeds the baseline that defines them). Set true to
        -- include them — simpler, and acceptable since a fixed base power only
        -- falls in relevance as stronger non-eternal pets are hatched over time.
        baseline_includes_eternal = false,
    },

    serials = {
        store_name = "PetSerials_v1",
    },

    -- DELETION POLICY (Jason: "we will never allow the deletion of Huges or
    -- Exclusives... or anything above that. It's simply denied."): server-enforced
    -- at the player DELETE intent (InventoryService) and the auto-delete hatch
    -- filter. Trading and fusion are NOT deletion and stay open (huges are
    -- tradeable); Admin_RetirePet is the scalpel and bypasses. Add future top
    -- classes (titan/colossal) to denied_rarities when they exist.
    deletion = {
        deny_huge = true,
        deny_creator = true,
        denied_rarities = {
            exclusive = true,
            creator = true,
        },
    },

    enchanting = {
        -- Stackable pets stay compact. Enchants are only applied to unique pets
        -- whose rarity has slots here, or to stack pets after a future promotion flow.
        -- Add future rarities here to change capacity without touching services.
        -- NOTE: a rarity here is FORCED unique (per-uid record) — mythic was removed
        -- by Storage v2 D1/D2: mythics are stackable with a hatch-rolled STACK enchant
        -- (configs/enchants.lua stack_enchants), not per-uid enchantable records.
        max_enchantments_by_rarity = {
            secret = 2,
            exclusive = 2,
            huge = 3,
        },
        default_max_enchantments = 0,
        hatch_rolls_enabled = true,
    },

    provenance = {
        -- Valuable pets should remember who created the copy. This uses enchant
        -- capacity so future tiers above Huge inherit the rule by config.
        hatcher_source_min_enchantments = 3,
        hatcher_source_rarities = {},
    },

    -- === TEST MODE (for Studio/dev validation) ===
    -- Enable to dramatically increase chances to obtain rare variants and pets
    -- so designers can validate stacking and special handling quickly.
    test_mode = {
        enabled = false,
        super_luck = false,
        force_pet = nil,
        force_variant = nil,
        pet_weight_overrides = nil,
        rarity_overrides = nil,
    },

    -- === VIEWPORT DISPLAY SETTINGS ===
    viewport = {
        default_zoom = 1.5, -- Default camera zoom for all pets (1.5x closer than original)

        -- Default display settings (can be overridden per pet variant)
        default_show_name = true, -- Show pet names by default
        default_container_transparency = 0.8, -- Default container transparency
        default_container_bg = "rarity", -- Default background ("rarity" or Color3)
        default_name_color = Color3.fromRGB(0, 0, 139), -- Dark blue name text color (contrast with white)
        default_chance_color = Color3.fromRGB(139, 0, 0), -- Dark red chance text color
    },

    -- === UI DISPLAY CONFIGURATION ===
    ui_display = {
        -- Choose display method for different UI contexts
        -- "images" = Use pre-generated images (fast, consistent, good for animations)
        -- "viewports" = Use 3D ViewportFrames (dynamic, real-time 3D)
        -- "user" = Let player choose in settings (respects user_preferences)

        inventory = "user", -- Let players choose display method
        egg_preview = "user", -- Let players choose display method
        shop_display = "images", -- Developer-controlled (always images)
        animations = "images", -- Always use images for animations (performance)

        -- User preference system
        user_preferences = {
            -- Default preferences for new players
            defaults = {
                inventory = "images", -- Default to images for performance
                egg_preview = "images", -- Default to images for consistency
                shop_display = "images", -- Not user-configurable anyway
            },

            -- Developer control over user preferences
            allow_user_control = {
                inventory = true, -- Players can change inventory display
                egg_preview = true, -- Players can change egg preview display
                shop_display = false, -- Developer forces shop to use images
                animations = false, -- Developer forces animations to use images
            },

            -- Performance warnings (shown when user picks viewports)
            performance_warnings = {
                enabled = true,
                viewport_warning = "3D models may reduce performance on lower-end devices",
                show_fps_warning = true, -- Show FPS impact warning
            },

            -- Auto-detect performance mode
            auto_performance = {
                enabled = true,
                force_images_below_fps = 30, -- Force images if FPS drops below 30
                monitor_duration = 10, -- Monitor FPS for 10 seconds after change
            },
        },

        -- Per-context override settings (developer can still force specific methods)
        context_overrides = {
            -- inventory = "viewports",      -- Force inventory to use 3D ViewportFrames
            -- egg_preview = "images",       -- Force egg preview to use images
            -- animations = "images",        -- This is already enforced above
        },
    },

    -- === ASSET IMAGE GENERATION SETTINGS ===
    asset_images = {
        -- Default camera settings for pets without specific config
        default_camera = {
            distance = 3.5,
            angle_y = 0,
            angle_x = 180,
            offset = Vector3.new(0, 0, 0),
            lighting = "default",
        },

        -- Default camera settings for eggs without specific config
        default_egg_camera = {
            distance = 3.5,
            angle_y = 0,
            angle_x = 180,
            offset = Vector3.new(0, 0, 0),
            lighting = "default",
        },

        -- Image generation settings
        image_size = 512, -- 512x512 for high quality
        background_color = Color3.fromRGB(0, 0, 0), -- Transparent background
        lighting_presets = {
            default = {
                ambient = Color3.fromRGB(100, 100, 100),
                directional = Color3.fromRGB(255, 255, 255),
                directional_angle = Vector3.new(-45, 45, 0),
            },
            dramatic = {
                ambient = Color3.fromRGB(50, 50, 80),
                directional = Color3.fromRGB(255, 240, 200),
                directional_angle = Vector3.new(-60, 30, 0),
            },
        },
    },

    -- === RARITY SYSTEM (Visual/Organization Only) ===
    rarities = {
        -- Normal tiers (stackable)
        common = {
            name = "Common",
            color = Color3.fromRGB(150, 150, 150), -- Gray
            glow = false,
        },
        uncommon = {
            name = "Uncommon",
            color = Color3.fromRGB(0, 255, 0), -- Green
            glow = false,
        },
        rare = {
            name = "Rare",
            color = Color3.fromRGB(0, 100, 255), -- Blue
            glow = true,
            glow_color = Color3.fromRGB(100, 150, 255),
        },
        epic = {
            name = "Epic",
            color = Color3.fromRGB(128, 0, 128), -- Purple
            glow = true,
            glow_color = Color3.fromRGB(180, 100, 255),
        },
        legendary = {
            name = "Legendary",
            color = Color3.fromRGB(255, 215, 0), -- Gold
            glow = true,
            glow_color = Color3.fromRGB(255, 255, 150),
        },
        mythic = { -- internal id; display name is fully configurable
            name = "Mythical",
            color = Color3.fromRGB(255, 0, 255), -- Magenta
            glow = true,
            glow_color = Color3.fromRGB(255, 150, 255),
            particle_effects = true,
        },
        -- Special tiers (unique pets)
        secret = {
            name = "Secret",
            color = Color3.fromRGB(255, 140, 0), -- Orange-gold
            glow = true,
            glow_color = Color3.fromRGB(255, 220, 120),
            particle_effects = true,
        },
        exclusive = {
            name = "Exclusive",
            color = Color3.fromRGB(0, 255, 255), -- Cyan
            glow = true,
            glow_color = Color3.fromRGB(150, 255, 255),
            particle_effects = true,
        },
        huge = {
            name = "Huge",
            color = Color3.fromRGB(255, 90, 210),
            glow = true,
            glow_color = Color3.fromRGB(255, 180, 245),
            particle_effects = true,
        },
    },

    -- === VARIANT TYPES ===
    variants = {
        -- `rarity` is a fallback for simple configs. Project pets should set
        -- family-level `pets.<id>.rarity`; variants are visual/stat treatments.
        basic = {
            name = "Basic",
            rarity = "common",
            power_multiplier = 1,
            health_multiplier = 1,
            special_effects = false,
        },
        golden = {
            name = "Golden",
            rarity = "epic",
            power_multiplier = 1.5,
            health_multiplier = 1.5,
            special_effects = true,
            effects = { "golden_sparkle", "coin_bonus" },
        },
        rainbow = {
            name = "Rainbow",
            rarity = "mythic",
            power_multiplier = 2,
            health_multiplier = 2,
            special_effects = true,
            effects = { "rainbow_trail", "all_bonus", "luck_boost" },
        },
    },

    -- === PET DEFINITIONS ===
    pets = {
        -- BEAR FAMILY
        bear = {
            display_name = "Bear",
            category = "forest",
            rarity = "common",
            base_power = 10,
            base_health = 150,

            -- Huge bears: a much higher base power (used only when the pet carries
            -- the huge trait — normal bears stay at base_power 10). Combined with
            -- the huge eternal scaling (100% of top-team average) this makes huge
            -- bears genuinely strong + raises the team baseline.
            huge_base_power = 100,

            -- Huge bears are visually larger. `huge_scale` is applied only to pets
            -- with the huge trait (see PetHandler.applyHugePetScale); normal bears
            -- render at `scale`.
            asset_transform = {
                scale = 1,
                huge_scale = 3,
                orientation = { x = 0, y = 0, z = 0 },
            },

            -- Camera configuration for image generation
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },

            variants = {
                basic = {
                    asset_id = "rbxassetid://102676279378350",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Bear",
                    abilities = { "scratch" },
                    -- Uses default viewport_zoom (1.5)

                    -- Uses default display settings
                },
                golden = {
                    asset_id = "rbxassetid://107758879638540",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Golden Bear",
                    abilities = { "golden_scratch", "coin_magnet" },
                    -- Uses default viewport_zoom (1.5)
                },
                rainbow = {
                    asset_id = "rbxassetid://92437511216136",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Rainbow Bear",
                    abilities = { "rainbow_scratch", "ultimate_magnet", "luck_aura" },
                    -- Uses default viewport_zoom (1.5)
                },
            },
        },

        -- EMBER FAMILY (lava biome — EmberEgg). One asset per pet for now; golden/rainbow reuse
        -- the basic model until dedicated art exists (so variant-dependent systems don't break).
        emberling = {
            display_name = "Emberling",
            category = "lava",
            rarity = "common",
            base_power = 12,
            base_health = 130,
            -- Ember meshes are tight, full-silhouette MeshParts; pull the inventory-card camera back
            -- a touch so the art doesn't overflow the card (card-only — not the in-world size).
            viewport_zoom = 1.5,
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://102018563424862",
                    image_id = "rbxassetid://0",
                    display_name = "Emberling",
                    abilities = { "fire_breath" },
                },
                golden = {
                    asset_id = "rbxassetid://125491041555430",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Emberling",
                    abilities = { "golden_flame", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://102018563424862",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Emberling",
                    abilities = { "prismatic_breath", "luck_aura" },
                },
            },
        },
        emberfox = {
            display_name = "Emberfox",
            category = "lava",
            rarity = "uncommon",
            base_power = 16,
            base_health = 150,
            viewport_zoom = 1.5, -- ember card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://117740863969382",
                    image_id = "rbxassetid://0",
                    display_name = "Emberfox",
                    abilities = { "fire_breath" },
                },
                golden = {
                    asset_id = "rbxassetid://131332151549245",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Emberfox",
                    abilities = { "golden_flame", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://117740863969382",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Emberfox",
                    abilities = { "prismatic_breath", "luck_aura" },
                },
            },
        },
        emberimp = {
            display_name = "Ember Imp",
            category = "lava",
            rarity = "rare",
            base_power = 22,
            base_health = 170,
            viewport_zoom = 1.5, -- ember card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://111062651596295",
                    image_id = "rbxassetid://0",
                    display_name = "Ember Imp",
                    abilities = { "fire_breath" },
                },
                golden = {
                    asset_id = "rbxassetid://127129905024932",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Ember Imp",
                    abilities = { "golden_flame", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://111062651596295",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Ember Imp",
                    abilities = { "prismatic_breath", "luck_aura" },
                },
            },
        },
        emberowl = {
            display_name = "Ember Owl",
            category = "lava",
            rarity = "epic",
            base_power = 30,
            base_health = 200,
            viewport_zoom = 1.5, -- ember card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://138609231264349",
                    image_id = "rbxassetid://0",
                    display_name = "Ember Owl",
                    abilities = { "fire_breath" },
                },
                golden = {
                    asset_id = "rbxassetid://133184779588286",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Ember Owl",
                    abilities = { "golden_flame", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://138609231264349",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Ember Owl",
                    abilities = { "prismatic_breath", "luck_aura" },
                },
            },
        },
        emberlion = {
            display_name = "Ember Lion",
            category = "lava",
            rarity = "legendary",
            base_power = 42,
            base_health = 260,
            viewport_zoom = 1.5, -- ember card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://123822224997280",
                    image_id = "rbxassetid://0",
                    display_name = "Ember Lion",
                    abilities = { "fire_breath" },
                },
                golden = {
                    asset_id = "rbxassetid://87755009672242",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Ember Lion",
                    abilities = { "golden_flame", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://123822224997280",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Ember Lion",
                    abilities = { "prismatic_breath", "luck_aura" },
                },
            },
        },

        -- ICE FAMILY (BasicIce egg). Ice-biome pets; same scale/framing as the ember family.
        snowflakeowl = {
            display_name = "Snowflake Owl",
            category = "ice",
            rarity = "common",
            base_power = 12,
            base_health = 130,
            viewport_zoom = 1.5, -- ice card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://83292549021438",
                    image_id = "rbxassetid://0",
                    display_name = "Snowflake Owl",
                    abilities = { "scratch" },
                },
                golden = {
                    asset_id = "rbxassetid://86818999673257",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Snowflake Owl",
                    abilities = { "golden_scratch", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://83292549021438",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Snowflake Owl",
                    abilities = { "rainbow_scratch", "luck_aura" },
                },
            },
        },
        snowfox = {
            display_name = "Snow Fox",
            category = "ice",
            rarity = "uncommon",
            base_power = 16,
            base_health = 150,
            viewport_zoom = 1.5, -- ice card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://72606573858620",
                    image_id = "rbxassetid://0",
                    display_name = "Snow Fox",
                    abilities = { "scratch" },
                },
                golden = {
                    asset_id = "rbxassetid://108502787971065",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Snow Fox",
                    abilities = { "golden_scratch", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://72606573858620",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Snow Fox",
                    abilities = { "rainbow_scratch", "luck_aura" },
                },
            },
        },
        penguin = {
            display_name = "Penguin",
            category = "ice",
            rarity = "rare",
            base_power = 22,
            base_health = 170,
            viewport_zoom = 1.5, -- ice card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://102826053899109",
                    image_id = "rbxassetid://0",
                    display_name = "Penguin",
                    abilities = { "scratch" },
                },
                golden = {
                    asset_id = "rbxassetid://137944510499979",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Penguin",
                    abilities = { "golden_scratch", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://102826053899109",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Penguin",
                    abilities = { "rainbow_scratch", "luck_aura" },
                },
            },
        },
        snowleopard = {
            display_name = "Snow Leopard",
            category = "ice",
            rarity = "epic",
            base_power = 30,
            base_health = 200,
            viewport_zoom = 1.5, -- ice card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://84866938216699",
                    image_id = "rbxassetid://0",
                    display_name = "Snow Leopard",
                    abilities = { "claw_swipe" },
                },
                golden = {
                    asset_id = "rbxassetid://86681945642413",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Snow Leopard",
                    abilities = { "golden_claws", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://84866938216699",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Snow Leopard",
                    abilities = { "rainbow_claws", "luck_aura" },
                },
            },
        },
        polarbear = {
            display_name = "Polar Bear",
            category = "ice",
            rarity = "legendary",
            base_power = 42,
            base_health = 260,
            -- THE APEX-PREDATOR TANK (Jason): tank role (pet_roles.by_type — toughness,
            -- taunt, threat) but FULL damage — these per-pet aptitudes override the tank
            -- role's 0.6, so it hits like a fighter while soaking like a tank. Rare
            -- enough (legendary, maybe rarer later) to justify breaking the role curve.
            mining_mult = 1.0,
            combat_mult = 1.0,
            viewport_zoom = 1.5, -- ice card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://71993023026266",
                    image_id = "rbxassetid://0",
                    display_name = "Polar Bear",
                    abilities = { "claw_swipe" },
                },
                golden = {
                    asset_id = "rbxassetid://87286616937220",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Polar Bear",
                    abilities = { "golden_claws", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://71993023026266",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Polar Bear",
                    abilities = { "rainbow_claws", "luck_aura" },
                },
            },
        },

        -- SAND FAMILY (BasicSand egg). Desert-biome pets; same scale/framing as ember/ice.
        fennec = {
            display_name = "Fennec",
            category = "desert",
            rarity = "common",
            base_power = 12,
            base_health = 130,
            viewport_zoom = 1.5, -- sand card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://77266088122632",
                    image_id = "rbxassetid://0",
                    display_name = "Fennec",
                    abilities = { "scratch" },
                },
                golden = {
                    asset_id = "rbxassetid://85924824230409",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Fennec",
                    abilities = { "golden_scratch", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://77266088122632",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Fennec",
                    abilities = { "rainbow_scratch", "luck_aura" },
                },
            },
        },
        camel = {
            display_name = "Camel",
            category = "desert",
            rarity = "uncommon",
            base_power = 16,
            base_health = 150,
            viewport_zoom = 1.5, -- sand card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://86029647986485",
                    image_id = "rbxassetid://0",
                    display_name = "Camel",
                    abilities = { "scratch" },
                },
                golden = {
                    asset_id = "rbxassetid://115312269011682",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Camel",
                    abilities = { "golden_scratch", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://86029647986485",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Camel",
                    abilities = { "rainbow_scratch", "luck_aura" },
                },
            },
        },
        meerkat = {
            display_name = "Meerkat",
            category = "desert",
            rarity = "rare",
            base_power = 22,
            base_health = 170,
            viewport_zoom = 1.5, -- sand card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://83699970022054",
                    image_id = "rbxassetid://0",
                    display_name = "Meerkat",
                    abilities = { "scratch" },
                },
                golden = {
                    asset_id = "rbxassetid://119309359317545",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Meerkat",
                    abilities = { "golden_scratch", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://83699970022054",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Meerkat",
                    abilities = { "rainbow_scratch", "luck_aura" },
                },
            },
        },
        desertiguana = {
            display_name = "Desert Iguana",
            category = "desert",
            rarity = "epic",
            base_power = 30,
            base_health = 200,
            viewport_zoom = 1.5, -- sand card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://129139046533482",
                    image_id = "rbxassetid://0",
                    display_name = "Desert Iguana",
                    abilities = { "claw_swipe" },
                },
                golden = {
                    asset_id = "rbxassetid://140708476776029",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Desert Iguana",
                    abilities = { "golden_claws", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://129139046533482",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Desert Iguana",
                    abilities = { "rainbow_claws", "luck_aura" },
                },
            },
        },
        scorpion = {
            display_name = "Scorpion",
            category = "desert",
            rarity = "legendary",
            base_power = 42,
            base_health = 260,
            viewport_zoom = 1.5, -- sand card framing (see emberling note)
            asset_transform = { scale = 1.6, huge_scale = 3, orientation = { x = 0, y = 0, z = 0 } },
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            variants = {
                basic = {
                    asset_id = "rbxassetid://113134007876507",
                    image_id = "rbxassetid://0",
                    display_name = "Scorpion",
                    abilities = { "claw_swipe" },
                },
                golden = {
                    asset_id = "rbxassetid://130738884436725",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Scorpion",
                    abilities = { "golden_claws", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://113134007876507",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Scorpion",
                    abilities = { "rainbow_claws", "luck_aura" },
                },
            },
        },

        -- BUNNY FAMILY
        bunny = {
            display_name = "Bunny",
            category = "meadow",
            rarity = "common",
            base_power = 8,
            base_health = 120,

            -- Camera configuration for image generation
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, -0.5, 0),
                lighting = "default",
            },

            variants = {
                basic = {
                    asset_id = "rbxassetid://119448221139567",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Bunny",
                    abilities = { "hop_attack" },
                    viewport_zoom = 1.8, -- Bunnies are smaller, zoom in more

                    -- Uses default display settings
                },
                golden = {
                    asset_id = "rbxassetid://133150464787030",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Golden Bunny",
                    abilities = { "golden_hop", "speed_boost" },
                    viewport_zoom = 1.8, -- Golden bunny zoom
                },
                rainbow = {
                    asset_id = "rbxassetid://113112612195316",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Rainbow Bunny",
                    abilities = { "rainbow_hop", "time_warp", "double_luck" },
                    viewport_zoom = 1.8, -- Rainbow bunny zoom
                },
            },
        },

        -- DOGGY FAMILY
        doggy = {
            display_name = "Doggy",
            category = "domestic",
            rarity = "common",
            base_power = 12,
            base_health = 140,

            -- Camera configuration for image generation
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },

            variants = {
                basic = {
                    asset_id = "rbxassetid://95584496209726",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Doggy",
                    abilities = { "bark_stun" },
                    -- Uses default viewport_zoom (1.5)

                    -- Uses default display settings
                },
                golden = {
                    asset_id = "rbxassetid://97337398672225",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Golden Doggy",
                    abilities = { "golden_bark", "loyalty_bonus" },
                    -- Uses default viewport_zoom (1.5)
                },
                rainbow = {
                    asset_id = "rbxassetid://139772169909973",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Rainbow Doggy",
                    abilities = { "rainbow_bark", "pack_leader", "infinite_loyalty" },
                    -- Uses default viewport_zoom (1.5)
                },
            },
        },

        -- DRAGON FAMILY
        dragon = {
            display_name = "Dragon",
            category = "mythical",
            rarity = "secret",
            base_power = 25,
            base_health = 200,
            -- eternal via the SECRET rarity default (eternal.default_percent_by_rarity)

            -- Camera configuration for image generation
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 1, 0),
                lighting = "dramatic",
            },

            variants = {
                basic = {
                    asset_id = "rbxassetid://71645322477288",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Dragon",
                    abilities = { "fire_breath" },
                    viewport_zoom = 2.0, -- Dragons need higher zoom to appear properly sized
                },
                golden = {
                    asset_id = "rbxassetid://91261941530299",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Golden Dragon",
                    abilities = { "golden_flame", "treasure_sense" },
                    viewport_zoom = 2.0, -- Golden dragon zoom (increased for proper size)
                },
                rainbow = {
                    asset_id = "rbxassetid://120821607721730",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Rainbow Dragon",
                    abilities = { "prismatic_breath", "reality_burn", "cosmic_flight" },
                    viewport_zoom = 2.0, -- Rainbow dragon zoom (increased for proper size)

                    -- Display overrides (optional - overrides viewport defaults)
                    display_container_bg = Color3.fromRGB(255, 0, 255), -- Magenta bg for Rainbow Dragon
                    display_container_transparency = 0.3, -- More opaque for mythic pet
                    display_show_name = true, -- Always show name for rainbow variants
                },
            },
        },

        -- KITTY FAMILY
        kitty = {
            display_name = "Kitty",
            category = "domestic",
            rarity = "legendary", -- was mislabeled common (10/75k odds); luck must boost it,
            base_power = 14, -- blaster: hits HARDER than melee (doggy 12) — it pays in fragility + shoot/kite pauses (Jason)
            base_health = 110,

            -- Camera configuration for image generation
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, -0.3, 0),
                lighting = "default",
            },

            variants = {
                basic = {
                    asset_id = "rbxassetid://73405612786363",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Kitty",
                    abilities = { "claw_swipe" },
                    viewport_zoom = 1.6, -- Kitties are small, zoom in more
                },
                golden = {
                    asset_id = "rbxassetid://131968646516737",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Golden Kitty",
                    abilities = { "golden_claws", "stealth_bonus" },
                    viewport_zoom = 1.6, -- Golden kitty zoom
                },
                rainbow = {
                    asset_id = "rbxassetid://124744079930917",
                    image_id = "rbxassetid://0", -- TODO: Generate from 3D model
                    display_name = "Rainbow Kitty",
                    abilities = { "rainbow_claws", "nine_lives", "shadow_step" },
                    viewport_zoom = 1.6, -- Rainbow kitty zoom
                },
            },
        },

        -- CREATOR / MEET REWARD FAMILY
        -- TWO PETS, ONE MODEL (Jason): the EXCLUSIVE colorado (meet-egg / wild — two
        -- buffs, no eternal) and the CREATOR-class colorado_creator (the apex — every
        -- buff + eternal) are different species that share the same 3D assets.
        colorado = {
            display_name = "Colorado",
            category = "creator",
            rarity = "exclusive",
            base_power = 100,
            base_health = 500,

            -- Imported avatar-like models often arrive with different facing/scale.
            -- `scale` is the normal model multiplier, `huge_scale` is applied to
            -- owned pets marked with the huge trait, and `orientation` is degrees.
            asset_transform = {
                scale = 1,
                huge_scale = 3,
                orientation = { x = 0, y = 0, z = 0 },
            },

            camera = {
                distance = 4,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },

            variants = {
                basic = {
                    asset_id = "rbxassetid://100466492312776",
                    image_id = "rbxassetid://0",
                    display_name = "Colorado",
                    abilities = { "creator_wave" },
                },
                golden = {
                    asset_id = "rbxassetid://121192248833075",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Colorado",
                    abilities = { "creator_wave", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://100466492312776",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Colorado",
                    abilities = { "creator_wave", "luck_aura" },
                },
            },
        },

        colorado_creator = {
            display_name = "Creator Colorado",
            category = "creator",
            rarity = "exclusive",
            base_power = 100,
            base_health = 500,
            -- eternal via the EXCLUSIVE rarity default (no one-off block — Jason);
            -- the HUGE apex pins at eternal.creator_power_percent via its category

            asset_transform = {
                scale = 1,
                huge_scale = 3,
                orientation = { x = 0, y = 0, z = 0 },
            },

            camera = {
                distance = 4,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },

            variants = {
                basic = {
                    asset_id = "rbxassetid://100466492312776",
                    image_id = "rbxassetid://0",
                    display_name = "Creator Colorado",
                    abilities = { "creator_wave" },
                },
                golden = {
                    asset_id = "rbxassetid://121192248833075",
                    image_id = "rbxassetid://0",
                    display_name = "Golden Creator Colorado",
                    abilities = { "creator_wave", "coin_magnet" },
                },
                rainbow = {
                    asset_id = "rbxassetid://100466492312776",
                    image_id = "rbxassetid://0",
                    display_name = "Rainbow Creator Colorado",
                    abilities = { "creator_wave", "luck_aura" },
                },
            },
        },
    },

    -- === ABILITIES SYSTEM ===
    abilities = {
        -- Basic Abilities
        scratch = { damage_multiplier = 1.2, cooldown = 2 },
        hop_attack = { damage_multiplier = 1.1, speed_boost = 1.5, cooldown = 3 },
        bark_stun = { stun_duration = 1, damage_multiplier = 1.0, cooldown = 4 },
        fire_breath = { damage_multiplier = 2.0, area_damage = true, cooldown = 5 },
        claw_swipe = { damage_multiplier = 1.3, crit_chance = 0.2, cooldown = 2 },
        creator_wave = { damage_multiplier = 2.0, luck_boost = 0.25, cooldown = 3 },

        -- Golden Abilities
        golden_scratch = { damage_multiplier = 1.5, coin_bonus = 2.0, cooldown = 2 },
        golden_hop = { damage_multiplier = 1.4, speed_boost = 2.0, coin_bonus = 1.5, cooldown = 3 },
        golden_bark = { stun_duration = 2, damage_multiplier = 1.3, coin_bonus = 1.8, cooldown = 4 },
        golden_flame = {
            damage_multiplier = 2.5,
            area_damage = true,
            coin_bonus = 3.0,
            cooldown = 5,
        },
        golden_claws = {
            damage_multiplier = 1.6,
            crit_chance = 0.3,
            coin_bonus = 2.2,
            cooldown = 2,
        },

        -- Rainbow Abilities (Ultimate)
        rainbow_scratch = {
            damage_multiplier = 3.0,
            all_bonus = 5.0,
            luck_boost = 0.5,
            cooldown = 1,
        },
        rainbow_hop = { damage_multiplier = 2.8, speed_boost = 5.0, time_warp = true, cooldown = 2 },
        rainbow_bark = {
            stun_duration = 5,
            damage_multiplier = 2.6,
            pack_leader = true,
            cooldown = 3,
        },
        prismatic_breath = {
            damage_multiplier = 5.0,
            reality_burn = true,
            cosmic_flight = true,
            cooldown = 4,
        },
        rainbow_claws = {
            damage_multiplier = 3.2,
            crit_chance = 0.8,
            nine_lives = true,
            cooldown = 1,
        },

        -- Special Effects
        coin_magnet = { coin_attraction_range = 50 },
        speed_boost = { movement_speed = 1.5 },
        ultimate_magnet = { coin_attraction_range = 125, rare_drop_pull = true },
        loyalty_bonus = { damage_to_owner_enemies = 2.0 },
        treasure_sense = { rare_drop_chance = 1.5 },
        stealth_bonus = { dodge_chance = 0.3 },
        luck_aura = { party_luck_boost = 2.0 },
        time_warp = { attack_speed_multiplier = 1.5, cooldown_reduction = 0.25 },
        double_luck = { party_luck_boost = 2.0 },
        pack_leader = { nearby_pet_damage = 1.5 },
        infinite_loyalty = { never_abandons_owner = true },
        reality_burn = { damage_over_time = true, armor_ignore = 0.5 },
        cosmic_flight = { can_fly = true, phase_through_walls = true },
        nine_lives = { revive_on_death = true, max_revives = 9 },
        shadow_step = { teleport_to_enemies = true },
    },

    -- === GAMEPASS & LUCK CONFIGURATION ===
    gamepass_modifiers = {
        -- Gamepass IDs (replace with your actual gamepass IDs)
        luck_gamepass_id = 0,
        golden_gamepass_id = 0,
        rainbow_gamepass_id = 0,

        -- Gamepass multipliers
        luck_gamepass_multiplier = 2.0, -- DEV ONLY: test_mode.super_luck ramp (multiplicative)
        -- PAID LUCK (Jason, 2026-06-12): the luck gamepass ADDS a flat bonus, and only
        -- to the SPECIES channel ("2x is usually additive — added to your luck, not
        -- multiplied over your current luck" + "gamepasses don't apply to variants,
        -- just shifts your odds for pets"). +1.0 = the advertised "2x" for a fresh
        -- 1.0x player; the 10-bunny endgame stack goes 5.56x -> 6.56x (not 11x), and
        -- golden/rainbow rates don't move at all (paid luck stays out of the
        -- tradeable variant supply). See docs/wiki/HATCH_LUCK.md.
        luck_gamepass_bonus = 1.0,
        golden_gamepass_multiplier = 2.0, -- 2x golden chance
        rainbow_gamepass_multiplier = 3.0, -- 3x rainbow chance

        -- Luck system configuration
        base_luck = 1.0, -- Default luck multiplier
        max_luck = 100.0, -- Maximum luck value achievable
        -- Luck progression (Jason: no hard caps, no runaway terms).
        -- LEVEL: diminishing-doubling curve — +per_doubling each time the level
        -- doubles past first_bonus_at (log2; bounded by the level cap anyway).
        -- eased 0.5 -> 0.3 (Jason: "we're scaling player luck really really steeply")
        level_luck = { per_doubling = 0.3, first_bonus_at = 3 },
        -- VARIANT LUCK DAMPING (Jason): variant (golden/rainbow) chances see only this
        -- fraction of the luck multiplier — species luck (the index chase) stays FULL
        -- potency, but luck stops triple-dipping into variant rates. 1 = undamped.
        variant_luck_weight = 0.5,
        -- COLLECTION (replaces the old per-hatch volume term, which a parked 24/7
        -- auto-hatcher farmed for free): bonus = max_bonus x the fraction of the
        -- OBTAINABLE pet index discovered (species x variants + huges — from
        -- PetIndexService:GetCompletion, fed in as playerData.indexCompletion).
        -- 100% collection = the full bonus: a natural cap that grows with content;
        -- volume-hatching pets you already found earns nothing.
        -- CURVED (Jason: "20% is super easy... 90% is much more difficult than 80%...
        -- we need to curve it"): bonus = max_bonus x completion^curve_exponent. The
        -- exponent was FIT FROM SIMULATION (25k-hatch journey, gate checks at
        -- 50/100/.../25000): completion is ~log-linear in effort (27% at 50 hatches,
        -- 50% at 250, 80% at 5000, 95% at 25000), and 2.5 makes the BONUS track
        -- effort: 40% completion (free, from leveling) pays ~10% of max; 80% pays
        -- ~57%; the grind past 90% earns the rest. 1 = old linear behavior.
        index_luck = { max_bonus = 2.0, curve_exponent = 2.5 },
        -- ENDGAME BASELINE (Jason, 2026-06-12, scripts/hatch_progression.luau): a
        -- 90%-index player effectively ALWAYS has 3 rainbow bunnies equipped
        -- (+0.75 boost) — "they're not that hard to hatch... we can just assume
        -- it". So balance against L7 / 90% / bunnies = 3.81x luck, ~12% golden,
        -- ~1.2% rainbow as the endgame floor (10-bunny full squad: 5.56x / ~16%
        -- golden / ~1.5% rainbow). Price/design future luck products against
        -- THIS baseline, not the no-bunny mid-game one. The luck gamepass adds
        -- +1.0 species-only on top (see luck_gamepass_bonus above): variant
        -- rates are unchanged by paid luck BY DESIGN.

        -- VIP benefits
        vip_luck_bonus = 1.5, -- 1.5x luck for VIP players
        vip_golden_bonus = 1.2, -- 1.2x golden chance for VIP
        vip_rainbow_bonus = 1.5, -- 1.5x rainbow chance for VIP
    },

    -- === EGG SOURCES (Two-Stage Hatching System) ===
    egg_sources = {
        -- MEET-THE-CREATOR egg (Jason): not purchasable, not placed in the world —
        -- hatched from the eggs INVENTORY bucket (MeetCreatorService.HatchEggItem).
        -- One species (the creator's), standard golden/rainbow channels (luck
        -- applies normally), and a slim huge chance — "the system takes care of
        -- golden/rainbow; use normal mechanics."
        colorado_egg = {
            name = "Colorado Egg",
            description = "A gift from ColoradoPlays himself. Hatches a Colorado!",
            cost = 0,
            currency = "coins",
            purchasable = false,
            -- STATED odds are REAL odds (fixed_odds): no luck of any kind applies to
            -- inventory-item eggs — Roblox paid-egg policy + one clean rule
            fixed_odds = true,
            huge = { chance = 0.01, pets = { colorado = 1 } }, -- 1 in 100: the jackpot, stated
            asset_id = "rbxassetid://94487781424433", -- 3D egg (PlaceAssets-cached)
            image_id = "rbxassetid://120328710003120",
            unlock_requirement = nil,

            pet_weights = {
                colorado = 1, -- the only species; variants via standard channels
            },
            rarity_rates = {
                golden_chance = 0.05, -- standard
                rainbow_chance = 0.005, -- standard
            },
            variant_rolls = {
                enabled = true,
                allow_basic = true,
                allow_golden = true,
                allow_rainbow = true,
                cost_multiplier = 20,
            },
            modifier_support = {
                supports_luck_gamepass = true,
                supports_golden_gamepass = true,
                supports_rainbow_gamepass = true,
                max_luck_multiplier = 10.0,
            },
            hatching_time = 3,
            guaranteed_shiny_chance = 0,
            bonus_xp = 0,
        },

        basic_egg = {
            name = "Basic Egg",
            description = "Contains all your favorite pets in Basic, Golden, and Rainbow variants!",
            cost = 100,
            currency = "coins",
            -- ORTHOGONAL HUGE (was the gated curated-bear block): "extremely extremely
            -- extremely rare" — the jackpot now applies to whatever species rolled
            -- (bear included), variant preserved. THE knob; tune freely.
            huge = { chance = 0.00002, any_pet = true }, -- 1 in 50,000 hatches
            asset_id = "rbxassetid://77451518796778", -- 3D BasicEgg model for import
            image_id = "rbxassetid://0", -- Generated from 3D model
            unlock_requirement = nil, -- Always available

            -- Camera configuration for egg image generation
            camera = {
                distance = 3.5,
                angle_y = 0, -- Same as working pets
                angle_x = 180, -- Same as working pets
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            animation = {
                authored_visual_scale = 1.55,
            },

            -- Stage 1: Pet Selection (which animal) - TESTING RARE PERCENTAGES
            pet_weights = {
                -- relative weights (share = weight/sum): commons ~33% each. kitty/dragon
                -- were 10/1 test placeholders for the "??" display — real odds now:
                bear = 24990,
                bunny = 24990,
                doggy = 24990,
                kitty = 500, -- ~0.66% (~1 in 150): the learnable "rare exists" moment
                dragon = 38, -- ~0.05% (~1 in 2,000): SECRET — hidden from all odds displays; farmable with luck
            },

            -- Stage 2: Rarity Calculation (basic/golden/rainbow)
            rarity_rates = {
                golden_chance = 0.05, -- 5% base chance for golden
                rainbow_chance = 0.005, -- 0.5% base chance for rainbow
                -- Remaining 94.5% will be basic
            },
            variant_rolls = {
                enabled = true,
                allow_basic = true,
                allow_golden = true,
                allow_rainbow = true,
                cost_multiplier = 20, -- Applied only if this egg is configured to remove basic rolls.
            },

            -- Gamepass & Luck Modifiers (applied in hatching script)
            modifier_support = {
                supports_luck_gamepass = true,
                supports_golden_gamepass = true,
                supports_rainbow_gamepass = true,
                max_luck_multiplier = 10.0, -- Cap luck at 10x for balance
            },

            -- Egg-specific bonuses
            hatching_time = 3, -- 3 seconds of anticipation
            guaranteed_shiny_chance = 0, -- No guarantees
            bonus_xp = 0,
        },

        -- EmberEgg (lava biome). Place a "Egg hatcher" / EggStand part in the Lava 1 zone with
        -- attribute EggId = "ember_egg" (markers.lua) to spawn it there. Hatches the Ember family.
        ember_egg = {
            name = "Ember Egg",
            description = "Lava-biome egg — hatches the Ember pets (Emberling up to Ember Lion).",
            world_placeable = true,
            cost = 250,
            currency = "lava_coins",
            -- ORTHOGONAL HUGE (Jason: "perfectly fine to have a huge roll for any pet" —
            -- the jackpot applies to whatever species stage 1 rolled, variant preserved,
            -- so huge golden/rainbow rarities COMPOUND). THE knob; tune freely.
            huge = { chance = 0.00002, any_pet = true }, -- 1 in 50,000 hatches
            asset_id = "rbxassetid://79770174701008",
            image_id = "rbxassetid://0",
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            -- Stage 1: which ember pet (rarer = lower weight).
            pet_weights = {
                emberling = 45,
                emberfox = 30,
                emberimp = 18,
                emberowl = 6,
                emberlion = 1,
            },
            -- Stage 2: variant rarity (basic mostly; small golden/rainbow chance).
            rarity_rates = {
                golden_chance = 0.05,
                rainbow_chance = 0.005,
            },
            variant_rolls = {
                enabled = true,
                allow_basic = true,
                allow_golden = true,
                allow_rainbow = true,
                cost_multiplier = 20,
            },
            modifier_support = {
                supports_luck_gamepass = true,
                supports_golden_gamepass = true,
                supports_rainbow_gamepass = true,
                max_luck_multiplier = 10.0,
            },
            hatching_time = 3,
            guaranteed_shiny_chance = 0,
            bonus_xp = 0,
        },

        -- IceEgg (ice biome). Place an EggStand part in the Ice zone with attribute
        -- EggId = "ice_egg" (or via egg_stand_placements["BasicIce"]). Hatches the Ice family.
        ice_egg = {
            name = "Ice Egg",
            description = "Ice-biome egg — hatches the Ice pets (Snowflake Owl up to Polar Bear).",
            world_placeable = true,
            cost = 250,
            currency = "ice_coins",
            -- ORTHOGONAL HUGE (Jason: "perfectly fine to have a huge roll for any pet" —
            -- the jackpot applies to whatever species stage 1 rolled, variant preserved,
            -- so huge golden/rainbow rarities COMPOUND). THE knob; tune freely.
            huge = { chance = 0.00002, any_pet = true }, -- 1 in 50,000 hatches
            asset_id = "rbxassetid://96544163202240",
            image_id = "rbxassetid://0",
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            -- Stage 1: which ice pet (rarer = lower weight; weights are RELATIVE —
            -- only the sum defines the odds, so fractions are fine).
            pet_weights = {
                snowflakeowl = 45,
                snowfox = 30,
                penguin = 18,
                snowleopard = 6,
                -- THE APEX-PREDATOR-TANK chase (Jason): tuned so a player has a 50%
                -- chance to own one within 500 hatches -> p = 1 - 0.5^(1/500) ≈ 1/721
                -- per hatch -> weight 0.1374 against the 99 points above. (A flat
                -- 1-in-500 weight would actually land 63% within 500 — exponentials.)
                polarbear = 0.1374,
            },
            -- Stage 2: variant rarity (basic mostly; small golden/rainbow chance).
            rarity_rates = {
                golden_chance = 0.05,
                rainbow_chance = 0.005,
            },
            variant_rolls = {
                enabled = true,
                allow_basic = true,
                allow_golden = true,
                allow_rainbow = true,
                cost_multiplier = 20,
            },
            modifier_support = {
                supports_luck_gamepass = true,
                supports_golden_gamepass = true,
                supports_rainbow_gamepass = true,
                max_luck_multiplier = 10.0,
            },
            hatching_time = 3,
            guaranteed_shiny_chance = 0,
            bonus_xp = 0,
        },

        -- SandEgg (desert biome). Place an EggStand part in the Desert zone with attribute
        -- EggId = "sand_egg" (or via egg_stand_placements["BasicSand"]). Hatches the Sand family.
        sand_egg = {
            name = "Sand Egg",
            description = "Desert-biome egg — hatches the Sand pets (Fennec up to Scorpion).",
            world_placeable = true,
            cost = 250,
            currency = "desert_coins",
            -- ORTHOGONAL HUGE (Jason: "perfectly fine to have a huge roll for any pet" —
            -- the jackpot applies to whatever species stage 1 rolled, variant preserved,
            -- so huge golden/rainbow rarities COMPOUND). THE knob; tune freely.
            huge = { chance = 0.00002, any_pet = true }, -- 1 in 50,000 hatches
            asset_id = "rbxassetid://86278537786961",
            image_id = "rbxassetid://0",
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            -- Stage 1: which sand pet (rarer = lower weight).
            pet_weights = {
                fennec = 45,
                camel = 30,
                meerkat = 18,
                desertiguana = 6,
                scorpion = 1,
            },
            -- Stage 2: variant rarity (basic mostly; small golden/rainbow chance).
            rarity_rates = {
                golden_chance = 0.05,
                rainbow_chance = 0.005,
            },
            variant_rolls = {
                enabled = true,
                allow_basic = true,
                allow_golden = true,
                allow_rainbow = true,
                cost_multiplier = 20,
            },
            modifier_support = {
                supports_luck_gamepass = true,
                supports_golden_gamepass = true,
                supports_rainbow_gamepass = true,
                max_luck_multiplier = 10.0,
            },
            hatching_time = 3,
            guaranteed_shiny_chance = 0,
            bonus_xp = 0,
        },

        -- EarthEgg (grass biome) — the STARTER egg on the Spawn island (BasicEarth stand).
        -- Costs grass_coins, but new players receive a 100 grass_coins starter grant (see
        -- configs/currencies.lua defaultAmount) so the first hatch is affordable before mining.
        -- Hatches the existing grass/earth pets (same roster as basic_egg); their meshes will be
        -- re-pointed to new earth asset IDs later — keep the pet entries as-is for now.
        earth_egg = {
            name = "Earth Egg",
            description = "Grass-biome starter egg — hatches the Earth pets (Bunny, Doggy, Bear...).",
            world_placeable = true,
            cost = 100,
            currency = "grass_coins",
            -- ORTHOGONAL HUGE (Jason: "perfectly fine to have a huge roll for any pet" —
            -- the jackpot applies to whatever species stage 1 rolled, variant preserved,
            -- so huge golden/rainbow rarities COMPOUND). THE knob; tune freely.
            huge = { chance = 0.00002, any_pet = true }, -- 1 in 50,000 hatches
            asset_id = "rbxassetid://95237477079273",
            image_id = "rbxassetid://0",
            camera = {
                distance = 3.5,
                angle_y = 0,
                angle_x = 180,
                offset = Vector3.new(0, 0, 0),
                lighting = "default",
            },
            -- Stage 1: which earth pet (same roster/weights as the original basic_egg).
            pet_weights = {
                bear = 24990,
                bunny = 24990,
                doggy = 24990,
                kitty = 500, -- ~0.66% — matched to basic_egg (was a 10/1 test placeholder)
                dragon = 38, -- ~0.05% SECRET — hidden from all odds displays
            },
            -- Stage 2: variant rarity (basic mostly; small golden/rainbow chance).
            rarity_rates = {
                golden_chance = 0.05,
                rainbow_chance = 0.005,
            },
            variant_rolls = {
                enabled = true,
                allow_basic = true,
                allow_golden = true,
                allow_rainbow = true,
                cost_multiplier = 20,
            },
            modifier_support = {
                supports_luck_gamepass = true,
                supports_golden_gamepass = true,
                supports_rainbow_gamepass = true,
                max_luck_multiplier = 10.0,
            },
            hatching_time = 3,
            guaranteed_shiny_chance = 0,
            bonus_xp = 0,
        },

        -- NOTE (Jason): separate golden/rainbow premium eggs are GONE — remnants of the
        -- old design. There is one egg per source with golden/rainbow as a hidden variant
        -- roll (rarity_rates). If a "golden hatch" returns, it is a SETTING on the same
        -- egg — pay a cost multiple, no basic chance — i.e. variant_rolls with
        -- allow_basic = false + cost_multiplier (see colorado_egg's variant_rolls),
        -- NOT a new egg_sources entry.
    },
}

-- === UTILITY FUNCTIONS ===

-- Get a specific pet variant
function petConfig.getPet(petType, variant)
    variant = variant or "basic"
    if petConfig.pets[petType] and petConfig.pets[petType].variants[variant] then
        local pet = petConfig.pets[petType]
        local petVariant = pet.variants[variant]
        local variantInfo = petConfig.variants[variant]
        local rarityKey = pet.rarity or variantInfo.rarity
        if petVariant.rarity_override and petConfig.rarities[petVariant.rarity_override] then
            rarityKey = petVariant.rarity_override
        end
        local rarity = petConfig.rarities[rarityKey]
        local powerMultiplier = petVariant.power_multiplier or variantInfo.power_multiplier or 1
        local healthMultiplier = petVariant.health_multiplier or variantInfo.health_multiplier or 1
        local power = petVariant.power
            or math.max(1, math.floor((pet.base_power or 1) * powerMultiplier + 0.5))
        local health = petVariant.health
            or math.max(1, math.floor((pet.base_health or 1) * healthMultiplier + 0.5))

        -- Create base pet data
        local petData = {
            -- Pet info
            id = petType,
            family_display_name = pet.display_name or pet.name,
            name = pet.display_name or pet.name,
            variant_display_name = petVariant.display_name,
            asset_id = petVariant.asset_id,
            category = pet.category,
            camera = petVariant.camera or pet.camera,
            -- Inventory-card framing zoom (card-only; does NOT affect in-world pet size, which is
            -- asset_transform.scale). The card auto-fits the model bbox; distance = bbox/viewport_zoom,
            -- so a LOWER value pushes the camera back and shrinks the art. Defaults to 1.5 in the panel.
            viewport_zoom = petVariant.viewport_zoom or pet.viewport_zoom,

            -- Stats
            power = power,
            health = health,
            base_power = pet.base_power,
            huge_base_power = petVariant.huge_base_power or pet.huge_base_power,
            base_health = pet.base_health,
            power_multiplier = powerMultiplier,
            health_multiplier = healthMultiplier,
            abilities = petVariant.abilities,
            eternal = petVariant.eternal or pet.eternal,

            -- Meta info
            variant = variant,
            rarity = rarity,
            rarity_id = rarityKey,
            variant_info = variantInfo,
            asset_transform = petVariant.asset_transform or pet.asset_transform,
        }

        -- Include all additional variant properties (like display_* settings)
        for key, value in pairs(petVariant) do
            -- Don't override existing keys, but add any new ones
            if petData[key] == nil then
                petData[key] = value
            end
        end

        return petData
    end
    return nil
end

-- Get all variants of a pet type
function petConfig.getAllVariants(petType)
    if not petConfig.pets[petType] then
        return nil
    end

    local variants = {}
    for variantName, _ in pairs(petConfig.pets[petType].variants) do
        variants[variantName] = petConfig.getPet(petType, variantName)
    end
    return variants
end

-- Get pets by rarity
function petConfig.getPetsByRarity(targetRarity)
    local pets = {}
    for petType, petData in pairs(petConfig.pets) do
        for variant, _ in pairs(petData.variants) do
            local pet = petConfig.getPet(petType, variant)
            if pet and pet.rarity_id == targetRarity then
                table.insert(pets, pet)
            end
        end
    end
    return pets
end

-- Calculate effective power (includes level progression)
function petConfig.getEffectivePower(petType, variant, level)
    level = level or 1
    local pet = petConfig.getPet(petType, variant)
    if not pet then
        return 0
    end

    local basePower = pet.power
    local progressionConfig = nil
    pcall(function()
        progressionConfig = require(script.Parent.pet_progression)
    end)
    local scaling = progressionConfig and progressionConfig.power_scaling or {}
    local perLevel = tonumber(scaling.percent_per_level) or 0
    local maxBonus = tonumber(scaling.max_bonus_percent) or 0
    local bonus = math.min(maxBonus, math.max(0, (level - 1) * perLevel))
    local levelMultiplier = 1 + bonus

    return math.floor(basePower * levelMultiplier)
end

-- === TWO-STAGE HATCHING SIMULATION ===

function petConfig.getEggCost(eggType)
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        return nil
    end

    local cost = tonumber(eggData.cost) or 0
    local variantRolls = eggData.variant_rolls
    -- no-basic eggs charge the variant_rolls cost_multiplier (the "golden hatch is a
    -- paid setting on the same egg" mechanism; the legacy no_basic_variants flag died
    -- with golden_egg)
    local noBasicMode = variantRolls and variantRolls.allow_basic == false

    if noBasicMode and variantRolls and variantRolls.cost_multiplier ~= nil then
        cost = cost * math.max(0, tonumber(variantRolls.cost_multiplier) or 1)
    end

    return math.floor(cost + 0.5)
end

-- Simulate egg hatching with gamepass/luck modifiers
function petConfig.simulateHatch(eggType, playerData)
    playerData = playerData or {}
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        return nil
    end

    -- Test mode hard override (force outcome)
    if petConfig.test_mode and petConfig.test_mode.enabled then
        local forcedPet = petConfig.test_mode.force_pet
        local forcedVariant = petConfig.test_mode.force_variant
        if forcedPet or forcedVariant then
            local pet = forcedPet or next(eggData.pet_weights) -- fallback to first
            local variant = forcedVariant or "basic"
            return {
                pet = pet,
                variant = variant,
                finalGoldenChance = 0,
                finalRainbowChance = 0,
                luckMultiplier = 1,
                petData = petConfig.getPet(pet, variant),
            }
        end
    end

    -- Stage 1: Select pet type based on weights
    local totalWeight = 0
    local petWeights = eggData.pet_weights

    -- Apply test mode weight overrides
    if
        petConfig.test_mode
        and petConfig.test_mode.enabled
        and petConfig.test_mode.pet_weight_overrides
        and petConfig.test_mode.pet_weight_overrides[eggType]
    then
        local overrides = petConfig.test_mode.pet_weight_overrides[eggType]
        petWeights = table.clone(eggData.pet_weights)
        for pet, w in pairs(overrides) do
            petWeights[pet] = w
        end
    end

    -- LUCK (Jason: "luck should affect everything" — it multiplies the probability of
    -- every rare outcome). Computed up front; reweights RARE SPECIES below and scales
    -- golden/rainbow in stage 2. Replaces the old best-of-N reroll model (which needed
    -- an ambiguous "best" ranking and leaked plain commons).
    local gamepassMods = petConfig.gamepass_modifiers
    -- FIXED ODDS (Jason / Roblox policy): inventory-item eggs (Meet-The-Creator,
    -- exclusives, anything purchasable) hatch at exactly their STATED odds — no
    -- luck, no gamepass multipliers, no boosts, and firstHatchLuck is NOT consumed
    -- (it stays armed for the player's first WORLD egg). One flag on the egg def.
    if eggData.fixed_odds == true then
        local fixedWeights = petWeights
        local totalW = 0
        for _, w in pairs(fixedWeights) do
            totalW = totalW + w
        end
        local roll = math.random() * totalW
        local selectedPet
        for petName, w in pairs(fixedWeights) do
            roll = roll - w
            if roll <= 0 then
                selectedPet = petName
                break
            end
        end
        selectedPet = selectedPet or next(fixedWeights)
        -- huge stage at the flat stated chance (any_pet: the rolled species goes huge —
        -- this is how a purchasable exclusive egg can carry a STATED huge chance)
        local hugeData = eggData.huge
        if
            hugeData
            and (tonumber(hugeData.chance) or 0) > 0
            and math.random() < hugeData.chance
        then
            local hp = (hugeData.any_pet == true and selectedPet) or next(hugeData.pets or {})
            if hp then
                return {
                    pet = hp,
                    variant = "basic",
                    huge = true,
                    finalGoldenChance = 0,
                    finalRainbowChance = 0,
                    luckMultiplier = 1,
                    petData = petConfig.getPet(hp, "basic"),
                }
            end
        end
        -- variant at the flat stated channel rates
        local rates = eggData.rarity_rates or {}
        local g = tonumber(rates.golden_chance) or 0
        local r = tonumber(rates.rainbow_chance) or 0
        local vroll = math.random()
        local variant = "basic"
        if vroll < r then
            variant = "rainbow"
        elseif vroll < r + g then
            variant = "golden"
        end
        return {
            pet = selectedPet,
            variant = variant,
            finalGoldenChance = g,
            finalRainbowChance = r,
            luckMultiplier = 1,
            petData = petConfig.getPet(selectedPet, variant),
        }
    end

    -- Diminishing-returns progression bonus: +per_doubling each doubling past
    -- first_bonus_at (log2 curve, no hard cap — late growth just slows).
    local function curveBonus(count, curve)
        count = tonumber(count) or 0
        if not curve or count <= 0 then
            return 0
        end
        return (curve.per_doubling or 0) * math.log(1 + count / (curve.first_bonus_at or 1), 2)
    end

    local luckMultiplier = gamepassMods.base_luck
    luckMultiplier = luckMultiplier + curveBonus(playerData.level, gamepassMods.level_luck)
    -- collection completion (0..1 from the pet index, fed by EggService) x weight —
    -- naturally capped at max_bonus when the whole obtainable index is discovered
    local indexLuck = gamepassMods.index_luck
    if indexLuck then
        local completion = math.clamp(tonumber(playerData.indexCompletion) or 0, 0, 1)
        -- effort curve: early completion is nearly free; the bonus tracks the GRIND
        local curved = completion ^ (tonumber(indexLuck.curve_exponent) or 1)
        luckMultiplier = luckMultiplier + (tonumber(indexLuck.max_bonus) or 0) * curved
    end
    if playerData.luckBoost then
        luckMultiplier = luckMultiplier + playerData.luckBoost
    end
    -- PAID LUCK: ADDITIVE + SPECIES-ONLY (Jason). The gamepass adds a flat bonus
    -- like every other luck source (it can't compound over level/index/bunnies),
    -- and only the SPECIES roll sees it — the golden/rainbow channels below read
    -- earnedLuck, so paid luck never inflates the tradeable variant supply.
    local earnedLuck = luckMultiplier
    if playerData.hasLuckGamepass then
        luckMultiplier = luckMultiplier + (tonumber(gamepassMods.luck_gamepass_bonus) or 0)
    end
    if petConfig.test_mode and petConfig.test_mode.enabled and petConfig.test_mode.super_luck then
        -- dev knob (not a product): multiplicative, and it hits EVERY channel
        luckMultiplier = luckMultiplier * gamepassMods.luck_gamepass_multiplier
        earnedLuck = earnedLuck * gamepassMods.luck_gamepass_multiplier
    end
    local maxLuck = eggData.modifier_support.max_luck_multiplier or gamepassMods.max_luck
    luckMultiplier = math.min(luckMultiplier, maxLuck)
    earnedLuck = math.min(earnedLuck, maxLuck)
    -- FIRST EGG EVER: one-roll mega-luck (consumed here; post-cap so it's a true 50x)
    if playerData.firstHatchLuck then
        local firstLuck = tonumber(playerData.firstHatchLuck) or 1
        luckMultiplier = luckMultiplier * firstLuck
        earnedLuck = earnedLuck * firstLuck
        playerData.firstHatchLuck = nil
    end

    -- species reweight: everything rarer than COMMON gets its weight multiplied by luck
    if luckMultiplier > 1 then
        local adjusted = table.clone(petWeights)
        for petType, weight in pairs(petWeights) do
            local family = petConfig.pets[petType]
            if family and family.rarity and family.rarity ~= "common" then
                adjusted[petType] = weight * luckMultiplier
            end
        end
        petWeights = adjusted
    end

    local secretLuckBoost = tonumber(playerData.secretLuckBoost) or 0
    if secretLuckBoost > 0 then
        local adjustedWeights = table.clone(petWeights)
        for petType, weight in pairs(petWeights) do
            local petFamily = petConfig.pets[petType]
            if petFamily and petFamily.rarity == "secret" then
                adjustedWeights[petType] = weight * (1 + secretLuckBoost)
            end
        end
        petWeights = adjustedWeights
    end

    for _, weight in pairs(petWeights) do
        totalWeight = totalWeight + weight
    end

    local randomValue = math.random() * totalWeight
    local currentWeight = 0
    local selectedPet = nil

    for petType, weight in pairs(petWeights) do
        currentWeight = currentWeight + weight
        if randomValue <= currentWeight then
            selectedPet = petType
            break
        end
    end

    if not selectedPet then
        return nil
    end

    -- Stage 2: Calculate rarity with modifiers
    local goldenChance = eggData.rarity_rates.golden_chance
    local rainbowChance = eggData.rarity_rates.rainbow_chance

    -- Test mode rarity overrides
    if
        petConfig.test_mode
        and petConfig.test_mode.enabled
        and petConfig.test_mode.rarity_overrides
        and petConfig.test_mode.rarity_overrides[eggType]
    then
        local ro = petConfig.test_mode.rarity_overrides[eggType]
        goldenChance = ro.golden_chance or goldenChance
        rainbowChance = ro.rainbow_chance or rainbowChance
    end

    -- Apply gamepass modifiers
    if playerData.hasGoldenGamepass then
        goldenChance = goldenChance * gamepassMods.golden_gamepass_multiplier
    end
    if playerData.hasRainbowGamepass then
        rainbowChance = rainbowChance * gamepassMods.rainbow_gamepass_multiplier
    end

    -- (luck was computed BEFORE stage 1 — it reweights the species roll too)
    if playerData.isVIP then
        goldenChance = goldenChance * gamepassMods.vip_golden_bonus
        rainbowChance = rainbowChance * gamepassMods.vip_rainbow_bonus
    end

    -- Apply luck to chances — STAGED CHANNELS (Jason): every stage has its own luck
    -- on top of the general multiplier, so events/powers/gamepasses can target ONE
    -- outcome ("2x rainbow weekend") without touching the others:
    --   species : luckMultiplier (+ secretLuckBoost for secrets)   [stage 1]
    --   golden  : luckMultiplier * goldenLuckBoost                 [stage 2]
    --   rainbow : luckMultiplier * rainbowLuckBoost                [stage 2]
    --   huge    : hugeLuckBoost (fractional attempts)              [stage 2.5]
    -- VARIANT LUCK DAMPING: variants see a WEIGHTED multiplier (1 + (mult-1) x weight)
    -- so species luck stays steep while golden/rainbow inflation is tamed. Source is
    -- earnedLuck — the luck gamepass bonus is species-only and never lands here.
    local variantLuck = 1 + (earnedLuck - 1) * (tonumber(gamepassMods.variant_luck_weight) or 1)
    goldenChance = goldenChance * variantLuck * (tonumber(playerData.goldenLuckBoost) or 1)
    rainbowChance = rainbowChance * variantLuck * (tonumber(playerData.rainbowLuckBoost) or 1)

    -- Stage 2.5: HUGE roll (Jason's design): huges are SEPARATE unique pets, never a
    -- variant. The normal pet above is the QUEUED outcome; the player then gets
    -- `attempts` shots at the huge jackpot (attempts = their huge luck multiple — a 3x
    -- huge luck = 3 rolls, Jason's hold-in-queue-and-reroll model). Per-egg config:
    --   egg_sources.<egg>.huge = { chance = 0.00002, pets = { bear = 1 } }  -- curated list
    --   egg_sources.<egg>.huge = { chance = 0.00002, any_pet = true }       -- ORTHOGONAL
    -- chance = 0 / no table = huges not hatchable from this egg.
    --
    -- ANY_PET (Jason: "it's perfectly fine to have a huge roll for any pet... a huge
    -- secret dragon would be radically rare because you'd have to roll a dragon and
    -- then roll huge on top"): the jackpot applies to WHATEVER species stage 1 rolled —
    -- huge becomes a third orthogonal axis (species x variant x huge) and compound
    -- rarity emerges instead of being authored. any_pet huges fall through to the
    -- variant roll below (huge golden/rainbow exist; their eternal percent scales
    -- by variant_effect_multipliers); curated-list huges stay basic (legacy shape).
    -- Power needs no per-species authoring: huges are ETERNAL (120% of the player's
    -- baseline), so a huge owl and a huge bear hit identically — species is identity.
    local hugeCfg = eggData.huge
    local hugeChance = hugeCfg and tonumber(hugeCfg.chance) or 0
    local rolledHuge = false
    if hugeChance > 0 and (hugeCfg.any_pet == true or (hugeCfg.pets and next(hugeCfg.pets))) then
        -- fractional attempts (Jason): 2.75x luck = 2 rolls + a 75% chance of a third —
        -- expected attempts exactly equals the multiplier, and at jackpot-tier chances
        -- attempts and pure odds-multiplication are mathematically equivalent
        local hugeLuck = math.max(1, tonumber(playerData.hugeLuckBoost) or 1)
        local attempts = math.floor(hugeLuck)
        if math.random() < (hugeLuck - attempts) then
            attempts += 1
        end
        for _ = 1, attempts do
            if math.random() <= hugeChance then
                if hugeCfg.any_pet == true then
                    -- orthogonal: the stage-1 species IS the huge; variant rolls below
                    rolledHuge = true
                    break
                end
                -- curated jackpot: weighted pick among this egg's huge-capable species
                local hugeTotal = 0
                for _, w in pairs(hugeCfg.pets) do
                    hugeTotal = hugeTotal + w
                end
                local r, acc = math.random() * hugeTotal, 0
                local hugePet
                for petType, w in pairs(hugeCfg.pets) do
                    acc = acc + w
                    if r <= acc then
                        hugePet = petType
                        break
                    end
                end
                if hugePet then
                    return {
                        pet = hugePet,
                        variant = "basic",
                        huge = true,
                        finalGoldenChance = 0,
                        finalRainbowChance = 0,
                        luckMultiplier = luckMultiplier,
                        petData = petConfig.getPet(hugePet, "basic"),
                    }
                end
            end
        end
    end

    -- Determine rarity
    local rarityRoll = math.random()
    local selectedVariant = "basic"

    local variantRolls = eggData.variant_rolls or {}
    local variantRollsEnabled = variantRolls.enabled ~= false
    local allowBasic = variantRolls.allow_basic ~= false
    local allowGolden = variantRolls.allow_golden ~= false
    local allowRainbow = variantRolls.allow_rainbow ~= false
    local hatchOptions = playerData.hatchOptions or {}
    if hatchOptions.goldenMode == true then
        allowBasic = false
    end

    if not variantRollsEnabled then
        selectedVariant = "basic"
    elseif not allowBasic then
        -- No-basic roll (goldenMode hatch setting or allow_basic = false) - only golden/rainbow
        if allowRainbow and rarityRoll <= rainbowChance then
            selectedVariant = "rainbow"
        elseif allowGolden then
            selectedVariant = "golden"
        else
            selectedVariant = "basic"
        end
    else
        -- Normal egg - basic/golden/rainbow
        if allowRainbow and rarityRoll <= rainbowChance then
            selectedVariant = "rainbow"
        elseif allowGolden and rarityRoll <= rainbowChance + goldenChance then
            selectedVariant = "golden"
        else
            selectedVariant = "basic"
        end
    end

    return {
        pet = selectedPet,
        variant = selectedVariant,
        huge = rolledHuge or nil, -- any_pet huge: stage-1 species + rolled variant, huge on top
        finalGoldenChance = goldenChance,
        finalRainbowChance = rainbowChance,
        luckMultiplier = luckMultiplier,
        petData = petConfig.getPet(selectedPet, selectedVariant),
    }
end

-- Example usage for testing
function petConfig.testHatching()
    local playerData = {
        level = 10,
        indexCompletion = 0.25,
        hasLuckGamepass = true,
        hasGoldenGamepass = false,
        hasRainbowGamepass = false,
        isVIP = true,
    }

    print("=== Hatching Simulation ===")
    for i = 1, 10 do
        local result = petConfig.simulateHatch("basic_egg", playerData)
        if result then
            print(
                string.format(
                    "Hatch %d: %s %s (Power: %d)",
                    i,
                    result.variant,
                    result.pet,
                    result.petData.power
                )
            )
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- EGG HATCHING ANIMATION CONFIG
-- ═══════════════════════════════════════════════════════════════════════════════════

petConfig.hatching_animation = {
    -- Animation timing settings
    timing = {
        screen_clear_duration = 1.0, -- How long to animate UI elements off-screen
        shake_duration = 2.0, -- How long eggs shake before hatching
        flash_duration = 0.5, -- Duration of flash effect
        reveal_duration = 1.0, -- Duration of pet reveal animation
        result_display_time = 2.0, -- How long to show result before restoring screen
        screen_restore_duration = 1.0, -- How long to animate UI elements back
        stagger_delay = 0.2, -- Delay between each egg in sequence
    },

    -- Visual effects settings
    effects = {
        shake_rotation = 5, -- Degrees of rotation during shake
        shake_frequency = 0.1, -- Time between shake movements
        flash_color = Color3.fromRGB(255, 255, 255),
        flash_intensity = 1.0, -- Flash transparency (0 = invisible, 1 = opaque)
    },

    -- Grid layout settings
    grid = {
        padding = 20, -- Space between eggs in pixels
        min_egg_size = 60, -- Minimum size for each egg
        max_egg_size = 120, -- Maximum size for each egg
        container_padding = 40, -- Padding around entire grid
    },

    -- Performance settings
    performance = {
        max_simultaneous_animations = 25, -- Limit concurrent animations
        use_images_only = true, -- Always use images for animations (never viewports)
        enable_sound_effects = true, -- Enable hatching sound effects
    },

    -- Grid layouts for different egg counts (auto-calculated but can be overridden)
    custom_layouts = {
        -- Example: Force specific layout for certain counts
        -- [5] = {columns = 3, rows = 2, name = "custom_5"},
    },
}

return petConfig
