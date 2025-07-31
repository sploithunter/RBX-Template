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
    
    -- === VIEWPORT DISPLAY SETTINGS ===
    viewport = {
        default_zoom = 1.5,  -- Default camera zoom for all pets (1.5x closer than original)
        
        -- Default display settings (can be overridden per pet variant)
        default_show_name = true,          -- Show pet names by default
        default_container_transparency = 0.8,  -- Default container transparency
        default_container_bg = "rarity",   -- Default background ("rarity" or Color3)
        default_name_color = Color3.fromRGB(0, 0, 139),  -- Dark blue name text color (contrast with white)
        default_chance_color = Color3.fromRGB(139, 0, 0), -- Dark red chance text color
    },
    
    -- === RARITY SYSTEM (Visual/Organization Only) ===
    rarities = {
        common = {
            name = "Common",
            color = Color3.fromRGB(150, 150, 150),  -- Gray
            glow = false,
        },
        uncommon = {
            name = "Uncommon", 
            color = Color3.fromRGB(0, 255, 0),      -- Green
            glow = false,
        },
        rare = {
            name = "Rare",
            color = Color3.fromRGB(0, 100, 255),    -- Blue
            glow = true,
            glow_color = Color3.fromRGB(100, 150, 255),
        },
        epic = {
            name = "Epic",
            color = Color3.fromRGB(128, 0, 128),    -- Purple
            glow = true,
            glow_color = Color3.fromRGB(180, 100, 255),
        },
        legendary = {
            name = "Legendary",
            color = Color3.fromRGB(255, 215, 0),    -- Gold
            glow = true,
            glow_color = Color3.fromRGB(255, 255, 150),
        },
        mythic = {
            name = "Mythic",
            color = Color3.fromRGB(255, 0, 255),    -- Magenta
            glow = true,
            glow_color = Color3.fromRGB(255, 150, 255),
            particle_effects = true,
        }
    },
    
    -- === VARIANT TYPES ===
    variants = {
        basic = {
            name = "Basic",
            rarity = "common",
            special_effects = false,
        },
        golden = {
            name = "Golden", 
            rarity = "epic",
            special_effects = true,
            effects = {"golden_sparkle", "coin_bonus"},
        },
        rainbow = {
            name = "Rainbow",
            rarity = "mythic",
            special_effects = true,
            effects = {"rainbow_trail", "all_bonus", "luck_boost"},
        }
    },
    
    -- === PET DEFINITIONS ===
    pets = {
        -- BEAR FAMILY
        bear = {
            name = "Bear",
            category = "forest",
            base_power = 10,
            base_health = 150,
            
            variants = {
                basic = {
                    asset_id = "rbxassetid://102676279378350",
                    display_name = "Bear",
                    power = 10,
                    health = 150,
                    abilities = {"scratch"},
                    -- Uses default viewport_zoom (1.5)
                    
                    -- Uses default display settings
                },
                golden = {
                    asset_id = "rbxassetid://107758879638540", 
                    display_name = "Golden Bear",
                    power = 50,  -- base_power * golden multiplier
                    health = 750, -- base_health * golden multiplier  
                    abilities = {"golden_scratch", "coin_magnet"},
                    -- Uses default viewport_zoom (1.5)
                },
                rainbow = {
                    asset_id = "rbxassetid://92437511216136",
                    display_name = "Rainbow Bear", 
                    power = 500, -- base_power * rainbow multiplier
                    health = 7500, -- base_health * rainbow multiplier
                    abilities = {"rainbow_scratch", "ultimate_magnet", "luck_aura"},
                    -- Uses default viewport_zoom (1.5)
                }
            }
        },
        
        -- BUNNY FAMILY  
        bunny = {
            name = "Bunny",
            category = "meadow",
            base_power = 8,
            base_health = 120,
            
            variants = {
                basic = {
                    asset_id = "rbxassetid://119448221139567",
                    display_name = "Bunny",
                    power = 8,
                    health = 120,
                    abilities = {"hop_attack"},
                    viewport_zoom = 1.8,  -- Bunnies are smaller, zoom in more
                    
                    -- Uses default display settings
                },
                golden = {
                    asset_id = "rbxassetid://133150464787030",
                    display_name = "Golden Bunny", 
                    power = 40,
                    health = 600,
                    abilities = {"golden_hop", "speed_boost"},
                    viewport_zoom = 1.8,  -- Golden bunny zoom
                },
                rainbow = {
                    asset_id = "rbxassetid://113112612195316",
                    display_name = "Rainbow Bunny",
                    power = 400, 
                    health = 6000,
                    abilities = {"rainbow_hop", "time_warp", "double_luck"},
                    viewport_zoom = 1.8,  -- Rainbow bunny zoom
                }
            }
        },
        
        -- DOGGY FAMILY
        doggy = {
            name = "Doggy", 
            category = "domestic",
            base_power = 12,
            base_health = 140,
            
            variants = {
                basic = {
                    asset_id = "rbxassetid://95584496209726",
                    display_name = "Doggy",
                    power = 12,
                    health = 140, 
                    abilities = {"bark_stun"},
                    -- Uses default viewport_zoom (1.5)
                    
                    -- Uses default display settings
                },
                golden = {
                    asset_id = "rbxassetid://97337398672225",
                    display_name = "Golden Doggy",
                    power = 60,
                    health = 700,
                    abilities = {"golden_bark", "loyalty_bonus"},
                    -- Uses default viewport_zoom (1.5)
                },
                rainbow = {
                    asset_id = "rbxassetid://139772169909973", 
                    display_name = "Rainbow Doggy",
                    power = 600,
                    health = 7000,
                    abilities = {"rainbow_bark", "pack_leader", "infinite_loyalty"},
                    -- Uses default viewport_zoom (1.5)
                }
            }
        },
        
        -- DRAGON FAMILY
        dragon = {
            name = "Dragon",
            category = "mythical", 
            base_power = 25,
            base_health = 200,
            
            variants = {
                basic = {
                    asset_id = "rbxassetid://71645322477288",
                    display_name = "Dragon",
                    power = 25,
                    health = 200,
                    abilities = {"fire_breath"},
                    viewport_zoom = 1.2,  -- Dragons are large, zoom out slightly
                },
                golden = {
                    asset_id = "rbxassetid://91261941530299",
                    display_name = "Golden Dragon", 
                    power = 125,
                    health = 1000,
                    abilities = {"golden_flame", "treasure_sense"},
                    viewport_zoom = 1.2,  -- Golden dragon zoom
                },
                rainbow = {
                    asset_id = "rbxassetid://120821607721730",
                    display_name = "Rainbow Dragon",
                    power = 1250,
                    health = 10000, 
                    abilities = {"prismatic_breath", "reality_burn", "cosmic_flight"},
                    viewport_zoom = 1.2,  -- Rainbow dragon zoom
                    
                    -- Display overrides (optional - overrides viewport defaults)
                    display_container_bg = Color3.fromRGB(255, 0, 255),  -- Magenta bg for Rainbow Dragon
                    display_container_transparency = 0.3,  -- More opaque for mythic pet
                    display_show_name = true,  -- Always show name for rainbow variants
                }
            }
        },
        
        -- KITTY FAMILY
        kitty = {
            name = "Kitty",
            category = "domestic",
            base_power = 9,
            base_health = 110,
            
            variants = {
                basic = {
                    asset_id = "rbxassetid://73405612786363",
                    display_name = "Kitty", 
                    power = 9,
                    health = 110,
                    abilities = {"claw_swipe"},
                    viewport_zoom = 1.6,  -- Kitties are small, zoom in more
                },
                golden = {
                    asset_id = "rbxassetid://131968646516737",
                    display_name = "Golden Kitty",
                    power = 45,
                    health = 550,
                    abilities = {"golden_claws", "stealth_bonus"},
                    viewport_zoom = 1.6,  -- Golden kitty zoom
                },
                rainbow = {
                    asset_id = "rbxassetid://124744079930917",
                    display_name = "Rainbow Kitty", 
                    power = 450,
                    health = 5500,
                    abilities = {"rainbow_claws", "nine_lives", "shadow_step"},
                    viewport_zoom = 1.6,  -- Rainbow kitty zoom
                }
            }
        }
    },
    
    -- === ABILITIES SYSTEM ===
    abilities = {
        -- Basic Abilities
        scratch = { damage_multiplier = 1.2, cooldown = 2 },
        hop_attack = { damage_multiplier = 1.1, speed_boost = 1.5, cooldown = 3 },
        bark_stun = { stun_duration = 1, damage_multiplier = 1.0, cooldown = 4 },
        fire_breath = { damage_multiplier = 2.0, area_damage = true, cooldown = 5 },
        claw_swipe = { damage_multiplier = 1.3, crit_chance = 0.2, cooldown = 2 },
        
        -- Golden Abilities  
        golden_scratch = { damage_multiplier = 1.5, coin_bonus = 2.0, cooldown = 2 },
        golden_hop = { damage_multiplier = 1.4, speed_boost = 2.0, coin_bonus = 1.5, cooldown = 3 },
        golden_bark = { stun_duration = 2, damage_multiplier = 1.3, coin_bonus = 1.8, cooldown = 4 },
        golden_flame = { damage_multiplier = 2.5, area_damage = true, coin_bonus = 3.0, cooldown = 5 },
        golden_claws = { damage_multiplier = 1.6, crit_chance = 0.3, coin_bonus = 2.2, cooldown = 2 },
        
        -- Rainbow Abilities (Ultimate)
        rainbow_scratch = { damage_multiplier = 3.0, all_bonus = 5.0, luck_boost = 0.5, cooldown = 1 },
        rainbow_hop = { damage_multiplier = 2.8, speed_boost = 5.0, time_warp = true, cooldown = 2 },
        rainbow_bark = { stun_duration = 5, damage_multiplier = 2.6, pack_leader = true, cooldown = 3 },
        prismatic_breath = { damage_multiplier = 5.0, reality_burn = true, cosmic_flight = true, cooldown = 4 },
        rainbow_claws = { damage_multiplier = 3.2, crit_chance = 0.8, nine_lives = true, cooldown = 1 },
        
        -- Special Effects
        coin_magnet = { coin_attraction_range = 50 },
        speed_boost = { movement_speed = 1.5 },
        loyalty_bonus = { damage_to_owner_enemies = 2.0 },
        treasure_sense = { rare_drop_chance = 1.5 },
        stealth_bonus = { dodge_chance = 0.3 },
        luck_aura = { party_luck_boost = 2.0 },
        pack_leader = { nearby_pet_damage = 1.5 },
        infinite_loyalty = { never_abandons_owner = true },
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
        luck_gamepass_multiplier = 2.0,      -- 2x luck boost
        golden_gamepass_multiplier = 2.0,    -- 2x golden chance
        rainbow_gamepass_multiplier = 3.0,   -- 3x rainbow chance
        
        -- Luck system configuration
        base_luck = 1.0,                     -- Default luck multiplier
        max_luck = 100.0,                    -- Maximum luck value achievable
        luck_per_level = 0.1,                -- Luck gained per player level
        luck_from_pets_hatched = 0.01,       -- Luck gained per pet hatched
        
        -- VIP benefits
        vip_luck_bonus = 1.5,                -- 1.5x luck for VIP players
        vip_golden_bonus = 1.2,              -- 1.2x golden chance for VIP
        vip_rainbow_bonus = 1.5,             -- 1.5x rainbow chance for VIP
    },
    
    -- === EGG SOURCES (Two-Stage Hatching System) ===
    egg_sources = {
        basic_egg = {
            name = "Basic Egg",
            description = "Contains all your favorite pets in Basic, Golden, and Rainbow variants!",
            cost = 100,
            currency = "coins",
            egg_model_asset_id = "rbxassetid://77451518796778", -- BasicEgg model
            icon_asset_id = "rbxassetid://77451518796778", -- Use same for icon for now
            unlock_requirement = nil, -- Always available
            
            -- Stage 1: Pet Selection (which animal) - TESTING RARE PERCENTAGES
            pet_weights = {
                bear = 24990,   -- ~25% chance to get a bear
                bunny = 24990,  -- ~25% chance to get a bunny  
                doggy = 24990,  -- ~25% chance to get a doggy
                kitty = 10,     -- 0.01% chance to get a kitty (10/100000)
                dragon = 1,     -- 0.001% chance to get a dragon (1/100000) - should show "??"
            },
            
            -- Stage 2: Rarity Calculation (basic/golden/rainbow)
            rarity_rates = {
                golden_chance = 0.05,   -- 5% base chance for golden
                rainbow_chance = 0.005, -- 0.5% base chance for rainbow
                -- Remaining 94.5% will be basic
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
        
        golden_egg = {
            name = "Golden Egg",
            description = "Premium egg - Only Golden and Rainbow pets, no Basic variants!",
            cost = 1000, 
            currency = "gems",
            egg_model_asset_id = "rbxassetid://83992435784076", -- Golden_BasicEgg model
            icon_asset_id = "rbxassetid://83992435784076", -- Use same for icon for now
            unlock_requirement = {type = "pets_hatched", amount = 10},
            
            -- Stage 1: Pet Selection (same animals as BasicEgg)
            pet_weights = {
                bear = 25,    -- 25% chance to get a bear
                bunny = 25,   -- 25% chance to get a bunny
                doggy = 25,   -- 25% chance to get a doggy
                kitty = 20,   -- 20% chance to get a kitty
                dragon = 5,   -- 5% chance to get a dragon
            },
            
            -- Stage 2: Rarity Calculation (NO BASIC VARIANTS)
            rarity_rates = {
                golden_chance = 0.95,  -- 95% chance for golden
                rainbow_chance = 0.05, -- 5% chance for rainbow
                -- 0% chance for basic (premium egg!)
                no_basic_variants = true, -- Flag for hatching script
            },
            
            -- Gamepass & Luck Modifiers
            modifier_support = {
                supports_luck_gamepass = true,
                supports_golden_gamepass = false, -- Already guaranteed golden+
                supports_rainbow_gamepass = true,
                max_luck_multiplier = 5.0, -- Lower cap since already premium
            },
            
            hatching_time = 30, -- 30 seconds of anticipation
            guaranteed_shiny_chance = 0.1, -- 10% chance for extra sparkles
            bonus_xp = 50,
        }
        
        -- Future eggs (disabled for now)
        --[[
        rainbow_egg = {
            name = "Rainbow Egg", 
            description = "Mythical rainbow pets with ultimate power",
            cost = 10000,
            currency = "gems", 
            egg_model_asset_id = "rbxassetid://0", -- Add when you have rainbow egg model
            icon_asset_id = "rbxassetid://0",
            unlock_requirement = {type = "golden_pets_hatched", amount = 5},
            
            possible_pets = {
                {pet = "bear", variant = "rainbow", weight = 20, display_rate = "20%"},
                {pet = "bunny", variant = "rainbow", weight = 20, display_rate = "20%"},
                {pet = "doggy", variant = "rainbow", weight = 20, display_rate = "20%"},
                {pet = "kitty", variant = "rainbow", weight = 20, display_rate = "20%"},
                {pet = "dragon", variant = "rainbow", weight = 20, display_rate = "20%"},
            },
            
            hatching_time = 300,
            guaranteed_shiny_chance = 1.0,
            bonus_xp = 500,
            special_hatch_animation = true,
        }
        --]]
    }
}

-- === UTILITY FUNCTIONS ===

-- Get a specific pet variant
function petConfig.getPet(petType, variant)
    variant = variant or "basic"
    if petConfig.pets[petType] and petConfig.pets[petType].variants[variant] then
        local pet = petConfig.pets[petType]
        local petVariant = pet.variants[variant]
        local variantInfo = petConfig.variants[variant]
        local rarity = petConfig.rarities[variantInfo.rarity]
        
        -- Create base pet data
        local petData = {
            -- Pet info
            name = petVariant.display_name,
            asset_id = petVariant.asset_id,
            category = pet.category,
            
            -- Stats  
            power = petVariant.power,
            health = petVariant.health,
            abilities = petVariant.abilities,
            
            -- Meta info
            variant = variant,
            rarity = rarity,
            variant_info = variantInfo,
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
    if not petConfig.pets[petType] then return nil end
    
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
            local variantInfo = petConfig.variants[variant]
            if variantInfo.rarity == targetRarity then
                table.insert(pets, petConfig.getPet(petType, variant))
            end
        end
    end
    return pets
end

-- Calculate effective power (includes level progression)
function petConfig.getEffectivePower(petType, variant, level)
    level = level or 1
    local pet = petConfig.getPet(petType, variant)
    if not pet then return 0 end
    
    local basePower = pet.power
    local levelMultiplier = 1 + (level - 1) * 0.1 -- 10% per level
    
    return math.floor(basePower * levelMultiplier)
end

-- === TWO-STAGE HATCHING SIMULATION ===

-- Simulate egg hatching with gamepass/luck modifiers
function petConfig.simulateHatch(eggType, playerData)
    playerData = playerData or {}
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then return nil end
    
    -- Stage 1: Select pet type based on weights
    local totalWeight = 0
    for _, weight in pairs(eggData.pet_weights) do
        totalWeight = totalWeight + weight
    end
    
    local randomValue = math.random() * totalWeight
    local currentWeight = 0
    local selectedPet = nil
    
    for petType, weight in pairs(eggData.pet_weights) do
        currentWeight = currentWeight + weight
        if randomValue <= currentWeight then
            selectedPet = petType
            break
        end
    end
    
    if not selectedPet then return nil end
    
    -- Stage 2: Calculate rarity with modifiers
    local goldenChance = eggData.rarity_rates.golden_chance
    local rainbowChance = eggData.rarity_rates.rainbow_chance
    
    -- Apply gamepass modifiers
    local gamepassMods = petConfig.gamepass_modifiers
    if playerData.hasGoldenGamepass then
        goldenChance = goldenChance * gamepassMods.golden_gamepass_multiplier
    end
    if playerData.hasRainbowGamepass then
        rainbowChance = rainbowChance * gamepassMods.rainbow_gamepass_multiplier
    end
    
    -- Apply luck system
    local luckMultiplier = gamepassMods.base_luck
    if playerData.level then
        luckMultiplier = luckMultiplier + (playerData.level * gamepassMods.luck_per_level)
    end
    if playerData.petsHatched then
        luckMultiplier = luckMultiplier + (playerData.petsHatched * gamepassMods.luck_from_pets_hatched)
    end
    if playerData.hasLuckGamepass then
        luckMultiplier = luckMultiplier * gamepassMods.luck_gamepass_multiplier
    end
    if playerData.isVIP then
        goldenChance = goldenChance * gamepassMods.vip_golden_bonus
        rainbowChance = rainbowChance * gamepassMods.vip_rainbow_bonus
    end
    
    -- Cap luck at maximum
    local maxLuck = eggData.modifier_support.max_luck_multiplier or gamepassMods.max_luck
    luckMultiplier = math.min(luckMultiplier, maxLuck)
    
    -- Apply luck to chances
    goldenChance = goldenChance * luckMultiplier
    rainbowChance = rainbowChance * luckMultiplier
    
    -- Determine rarity
    local rarityRoll = math.random()
    local selectedVariant = "basic"
    
    if eggData.rarity_rates.no_basic_variants then
        -- Premium egg - only golden/rainbow
        if rarityRoll <= rainbowChance then
            selectedVariant = "rainbow"
        else
            selectedVariant = "golden"
        end
    else
        -- Normal egg - basic/golden/rainbow
        if rarityRoll <= rainbowChance then
            selectedVariant = "rainbow"
        elseif rarityRoll <= rainbowChance + goldenChance then
            selectedVariant = "golden"
        else
            selectedVariant = "basic"
        end
    end
    
    return {
        pet = selectedPet,
        variant = selectedVariant,
        finalGoldenChance = goldenChance,
        finalRainbowChance = rainbowChance,
        luckMultiplier = luckMultiplier,
        petData = petConfig.getPet(selectedPet, selectedVariant)
    }
end

-- Example usage for testing
function petConfig.testHatching()
    local playerData = {
        level = 10,
        petsHatched = 25,
        hasLuckGamepass = true,
        hasGoldenGamepass = false,
        hasRainbowGamepass = false,
        isVIP = true,
    }
    
    print("=== Hatching Simulation ===")
    for i = 1, 10 do
        local result = petConfig.simulateHatch("basic_egg", playerData)
        if result then
            print(string.format("Hatch %d: %s %s (Power: %d)", 
                i, result.variant, result.pet, result.petData.power))
        end
    end
end

return petConfig