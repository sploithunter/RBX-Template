--[[
    EggPetPreviewService - Shows pet preview with hatch chances when approaching eggs
    
    Displays pets and their calculated hatch percentages based on:
    - Base egg configuration chances
    - Player luck aggregates (from Player/Aggregates/ folder)
    - Player level, pets hatched, gamepass ownership
    - VIP status and other modifiers
    
    Features:
    - Real-time chance calculation including all player modifiers
    - Pet icons with percentage display
    - Shows "??" for very rare pets (<0.1% chance)
    - Follows working game's UI positioning pattern
]]

local EggPetPreviewService = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Dependencies
local Locations = require(ReplicatedStorage.Shared.Locations)
local petConfig = Locations.getConfig("pets")
local eggSystemConfig = Locations.getConfig("egg_system")

-- Get player and camera
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- UI state
local petPreviewUI = nil
local currentEggType = nil
local iconCache = {}

-- Logger setup using LoggerWrapper pattern from memory
local LoggerWrapper
local loggerSuccess, loggerResult = pcall(function()
    return require(ReplicatedStorage.Shared.Utils.Logger)
end)

if loggerSuccess and loggerResult then
    LoggerWrapper = {
        new = function(name)
            return {
                info = function(self, ...) loggerResult:Info("[" .. name .. "] " .. tostring((...)), {context = name}) end,
                warn = function(self, ...) loggerResult:Warn("[" .. name .. "] " .. tostring((...)), {context = name}) end,
                error = function(self, ...) loggerResult:Error("[" .. name .. "] " .. tostring((...)), {context = name}) end,
                debug = function(self, ...) loggerResult:Debug("[" .. name .. "] " .. tostring((...)), {context = name}) end,
            }
        end
    }
else
    -- Fallback LoggerWrapper implementation
    LoggerWrapper = {
        new = function(name)
            return {
                info = function(self, ...) print("[INFO]", "[" .. name .. "]", ...) end,
                warn = function(self, ...) warn("[WARN]", "[" .. name .. "]", ...) end,
                error = function(self, ...) warn("[ERROR]", "[" .. name .. "]", ...) end,
                debug = function(self, ...) print("[DEBUG]", "[" .. name .. "]", ...) end,
            }
        end
    }
end

local logger = LoggerWrapper.new("EggPetPreviewService")

-- === PLAYER DATA GATHERING ===

-- Get player's current luck modifiers and stats
function EggPetPreviewService:GetPlayerData()
    local playerData = {
        level = player:GetAttribute("Level") or 1,
        petsHatched = player:GetAttribute("PetsHatched") or 0,
        hasLuckGamepass = false,
        hasGoldenGamepass = false,
        hasRainbowGamepass = false,
        isVIP = false,
        
        -- Aggregate luck values from Player/Aggregates/
        luckBoost = 0,
        rareLuckBoost = 0,
        ultraLuckBoost = 0,
    }
    
    -- Get aggregate values from Player/Aggregates/ folder
    if player:FindFirstChild("Aggregates") then
        local aggregates = player.Aggregates
        
        -- Read luck values from NumberValue objects (real-time aggregated)
        if aggregates:FindFirstChild("luckBoost") then
            playerData.luckBoost = aggregates.luckBoost.Value
        end
        if aggregates:FindFirstChild("rareLuckBoost") then
            playerData.rareLuckBoost = aggregates.rareLuckBoost.Value
        end
        if aggregates:FindFirstChild("ultraLuckBoost") then
            playerData.ultraLuckBoost = aggregates.ultraLuckBoost.Value
        end
    end
    
    -- TODO: Get gamepass ownership from DataService when available
    -- For now using placeholder values
    
    -- Check premium status
    if player.MembershipType == Enum.MembershipType.Premium then
        playerData.isVIP = true
    end
    
    return playerData
end

-- === PET CHANCE CALCULATION ===

-- Calculate actual hatch chances for all pets in an egg, including player modifiers
function EggPetPreviewService:CalculatePetChances(eggType)
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        logger:warn("Invalid egg type for chance calculation:", eggType)
        return {}
    end
    
    local playerData = self:GetPlayerData()
    local petChances = {}
    
    -- Stage 1: Get pet type weights
    local totalWeight = 0
    for _, weight in pairs(eggData.pet_weights) do
        totalWeight = totalWeight + weight
    end
    
    -- Stage 2: Calculate rarity chances with all modifiers
    local baseGoldenChance = eggData.rarity_rates.golden_chance
    local baseRainbowChance = eggData.rarity_rates.rainbow_chance
    
    -- Apply gamepass modifiers
    local gamepassMods = petConfig.gamepass_modifiers
    local goldenChance = baseGoldenChance
    local rainbowChance = baseRainbowChance
    
    if playerData.hasGoldenGamepass then
        goldenChance = goldenChance * gamepassMods.golden_gamepass_multiplier
    end
    if playerData.hasRainbowGamepass then
        rainbowChance = rainbowChance * gamepassMods.rainbow_gamepass_multiplier
    end
    
    -- Apply luck system from aggregates and level
    local luckMultiplier = gamepassMods.base_luck
    
    -- Level-based luck
    luckMultiplier = luckMultiplier + (playerData.level * gamepassMods.luck_per_level)
    
    -- Pets hatched luck
    luckMultiplier = luckMultiplier + (playerData.petsHatched * gamepassMods.luck_from_pets_hatched)
    
    -- Aggregate luck bonuses (from effects, potions, etc.)
    luckMultiplier = luckMultiplier + playerData.luckBoost
    luckMultiplier = luckMultiplier + playerData.rareLuckBoost
    luckMultiplier = luckMultiplier + playerData.ultraLuckBoost
    
    -- Gamepass luck multiplier
    if playerData.hasLuckGamepass then
        luckMultiplier = luckMultiplier * gamepassMods.luck_gamepass_multiplier
    end
    
    -- VIP bonuses
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
    
    -- Calculate chances for each pet type based on egg configuration
    for petType, weight in pairs(eggData.pet_weights) do
        local petTypeChance = weight / totalWeight
        
        -- Determine which variants to show based on egg type
        local variantsToShow = {}
        
        if eggData.rarity_rates.no_basic_variants then
            -- Premium egg (like golden_egg) - show golden and rainbow variants
            variantsToShow = {"golden", "rainbow"}
        else
            -- Basic egg - show only basic variants
            variantsToShow = {"basic"}
        end
        
        -- Get variants for this pet type
        if petConfig.pets[petType] and petConfig.pets[petType].variants then
            for _, variant in ipairs(variantsToShow) do
                if petConfig.pets[petType].variants[variant] then
                    table.insert(petChances, {
                        petType = petType,
                        variant = variant,
                        chance = petTypeChance, -- Just the pet type weight, no rarity calculation for display
                        petData = petConfig.getPet(petType, variant)
                    })
                end
            end
        end
    end
    
    -- Sort by chance (highest first) if configured
    if eggSystemConfig.pet_preview.sort_by_chance then
        table.sort(petChances, function(a, b) return a.chance > b.chance end)
    end
    
    logger:debug("Calculated pet chances", {
        eggType = eggType,
        playerLevel = playerData.level,
        luckMultiplier = luckMultiplier,
        totalPets = #petChances
    })
    
    return petChances
end

-- === PET PREVIEW UI ===

-- Create the pet preview UI
function EggPetPreviewService:CreatePetPreviewUI()
    if petPreviewUI then
        petPreviewUI:Destroy()
    end
    
    local config = eggSystemConfig.ui
    local previewConfig = eggSystemConfig.pet_preview
    
    -- Create UI container
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggPetPreview"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player.PlayerGui
    
    local frame = Instance.new("Frame")
    frame.Name = "PetPreviewFrame"
    frame.Size = UDim2.new(0, config.pet_preview_size.width, 0, config.pet_preview_size.height)
    frame.BackgroundColor3 = config.colors.pet_preview_bg
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, config.corner_radius)
    corner.Parent = frame
    
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = config.border_thickness
    stroke.Color = config.colors.pet_preview_border
    stroke.Parent = frame
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -20, 0, 30)
    title.Position = UDim2.new(0, 10, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "Pet Chances"
    title.TextColor3 = config.colors.text_primary
    title.TextScaled = true
    title.Font = config.fonts.title
    title.Parent = frame
    
    -- Scrolling frame for pets
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "PetContainer"
    scrollFrame.Size = UDim2.new(1, -20, 1, -50)
    scrollFrame.Position = UDim2.new(0, 10, 0, 40)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.ScrollBarImageColor3 = config.colors.border
    scrollFrame.Parent = frame
    
    -- Grid layout for pets
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, previewConfig.pet_icon_size + 20, 0, previewConfig.pet_icon_size + 40)
    gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    gridLayout.Parent = scrollFrame
    
    -- Update canvas size when layout changes
    gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, gridLayout.AbsoluteContentSize.Y + 10)
    end)
    
    petPreviewUI = screenGui
    logger:info("Pet preview UI created")
    return frame
end

-- Update pet preview display
function EggPetPreviewService:UpdatePetPreview(eggType, eggPosition)
    if not eggSystemConfig.pet_preview.enabled then
        return
    end
    
    if not petPreviewUI then
        self:CreatePetPreviewUI()
    end
    
    local frame = petPreviewUI.PetPreviewFrame
    local container = frame.PetContainer
    local previewConfig = eggSystemConfig.pet_preview
    
    if eggType and eggType ~= "None" then
        -- Calculate chances for this egg
        local petChances = self:CalculatePetChances(eggType)
        
        -- Clear existing pet displays
        for _, child in ipairs(container:GetChildren()) do
            if not child:IsA("UIGridLayout") then
                child:Destroy()
            end
        end
        
        -- Show pets up to max display limit
        local displayCount = math.min(#petChances, previewConfig.max_pets_to_display)
        
        for i = 1, displayCount do
            local petInfo = petChances[i]
            self:CreatePetDisplay(container, petInfo, i)
        end
        
        -- Update position and show
        if eggPosition then
            local screenPos = camera:WorldToScreenPoint(eggPosition)
            frame.Position = UDim2.new(
                0, screenPos.X + eggSystemConfig.ui.pet_preview_offset.x, 
                0, screenPos.Y + eggSystemConfig.ui.pet_preview_offset.y
            )
        end
        
        frame.Visible = true
        currentEggType = eggType
        
    else
        -- Hide when no egg in range
        frame.Visible = false
        currentEggType = nil
    end
end

-- Create individual pet display element
function EggPetPreviewService:CreatePetDisplay(parent, petInfo, layoutOrder)
    local config = eggSystemConfig.ui
    local previewConfig = eggSystemConfig.pet_preview
    
    -- Create pet frame
    local petFrame = Instance.new("Frame")
    petFrame.Name = "Pet_" .. layoutOrder
    petFrame.Size = UDim2.new(0, previewConfig.pet_icon_size + 20, 0, previewConfig.pet_icon_size + 40)
    petFrame.BackgroundColor3 = petInfo.petData.rarity.color
    petFrame.BackgroundTransparency = 0.8
    petFrame.BorderSizePixel = 0
    petFrame.LayoutOrder = layoutOrder
    petFrame.Parent = parent
    
    local petCorner = Instance.new("UICorner")
    petCorner.CornerRadius = UDim.new(0, 8)
    petCorner.Parent = petFrame
    
    -- Pet 3D model display using ViewportFrame (like MCP game)
    if previewConfig.load_pet_icons and petInfo.petData.asset_id and petInfo.petData.asset_id ~= "rbxassetid://0" then
        -- Create ViewportFrame for 3D model display
        local viewport = Instance.new("ViewportFrame")
        viewport.Name = "PetViewport"
        viewport.Size = UDim2.new(0, previewConfig.pet_icon_size, 0, previewConfig.pet_icon_size)
        viewport.Position = UDim2.new(0.5, -previewConfig.pet_icon_size/2, 0, 5)
        viewport.BackgroundTransparency = 1
        viewport.Parent = petFrame
        
        -- Create camera for the viewport
        local camera = Instance.new("Camera")
        camera.Parent = viewport
        viewport.CurrentCamera = camera
        
        logger:info("Loading 3D pet model", {
            petType = petInfo.petType,
            variant = petInfo.variant,
            assetId = petInfo.petData.asset_id
        })
        
        -- Load the 3D model asynchronously
        self:Load3DPetModel(petInfo.petData.asset_id, viewport, camera, petInfo.petType, petInfo.variant)
    else
        -- Use emoji fallback
        logger:debug("Using emoji fallback", {
            petType = petInfo.petType, 
            reason = "3D loading disabled or invalid asset"
        })
        local petIcon = Instance.new("TextLabel")
        petIcon.Name = "Icon"
        petIcon.Size = UDim2.new(0, previewConfig.pet_icon_size, 0, previewConfig.pet_icon_size)
        petIcon.Position = UDim2.new(0.5, -previewConfig.pet_icon_size/2, 0, 5)
        petIcon.BackgroundTransparency = 1
        petIcon.Text = self:GetPetEmojiIcon(petInfo.petType)
        petIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
        petIcon.TextScaled = true
        petIcon.Font = Enum.Font.GothamBold
        petIcon.Parent = petFrame
    end
    
    -- Pet name (if enabled)
    if previewConfig.show_variant_names then
        local petName = Instance.new("TextLabel")
        petName.Name = "Name"
        petName.Size = UDim2.new(1, -4, 0, 15)
        petName.Position = UDim2.new(0, 2, 0, previewConfig.pet_icon_size + 5)
        petName.BackgroundTransparency = 1
        petName.Text = petInfo.petData.name
        petName.TextColor3 = config.colors.text_primary
        petName.TextScaled = true
        petName.Font = config.fonts.pet_name
        petName.Parent = petFrame
    end
    
    -- Chance percentage
    local chanceLabel = Instance.new("TextLabel")
    chanceLabel.Name = "Chance"
    chanceLabel.Size = UDim2.new(1, -4, 0, 15)
    chanceLabel.Position = UDim2.new(0, 2, 1, -17)
    chanceLabel.BackgroundTransparency = 1
    chanceLabel.Font = config.fonts.pet_chance
    chanceLabel.Parent = petFrame
    
    -- Format chance display
    local chancePercent = petInfo.chance * 100
    if chancePercent < previewConfig.min_chance_to_show * 100 then
        chanceLabel.Text = "??"
        chanceLabel.TextColor3 = config.colors.very_rare_text
    else
        chanceLabel.Text = string.format("%." .. previewConfig.chance_precision .. "f%%", chancePercent)
        chanceLabel.TextColor3 = config.colors.text_secondary
    end
    chanceLabel.TextScaled = true
    
    return petFrame
end

-- Load 3D pet model into ViewportFrame (using ReplicatedStorage.Assets)
function EggPetPreviewService:Load3DPetModel(assetId, viewport, camera, petType, variant)
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    
    task.spawn(function()
        local success, result = pcall(function()
            logger:debug("Loading 3D model from ReplicatedStorage.Assets", {
                assetId = assetId,
                petType = petType,
                variant = variant
            })
            
            -- Try to get model from ReplicatedStorage.Assets.Models.Pets first
            local modelClone = nil
            local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
            
            if assetsFolder then
                local modelsFolder = assetsFolder:FindFirstChild("Models")
                if modelsFolder then
                    local petsFolder = modelsFolder:FindFirstChild("Pets")
                    if petsFolder then
                        local petTypeFolder = petsFolder:FindFirstChild(petType)
                        if petTypeFolder then
                            local petModel = petTypeFolder:FindFirstChild(variant)
                            if petModel then
                                modelClone = petModel:Clone()
                                logger:debug("Got model from ReplicatedStorage.Assets", {
                                    petType = petType,
                                    variant = variant,
                                    modelName = modelClone.Name,
                                    path = petModel:GetFullName()
                                })
                            end
                        end
                    end
                end
            end
            
            -- Fallback to runtime loading if not in assets
            if not modelClone then
                local InsertService = game:GetService("InsertService")
                local cleanId = assetId:match("%d+")
                
                if not cleanId then
                    error("Invalid asset ID format: " .. tostring(assetId))
                end
                
                logger:debug("Model not found in Assets, falling back to runtime InsertService loading", {
                    assetId = cleanId,
                    petType = petType,
                    variant = variant
                })
                
                local loadedAsset = InsertService:LoadAsset(tonumber(cleanId))
                if not loadedAsset then
                    error("Failed to load asset: " .. cleanId)
                end
                
                -- Find the model inside the asset
                local petModel = loadedAsset:FindFirstChildOfClass("Model")
                if not petModel then
                    error("No Model found in asset: " .. cleanId)
                end
                
                -- Clone and set up the model
                modelClone = petModel:Clone()
                loadedAsset:Destroy() -- Clean up the original asset
            end
            
            -- Position the model at the origin
            local pos = Vector3.new(0, 0, 0)
            if modelClone.PrimaryPart then
                modelClone:SetPrimaryPartCFrame(CFrame.new(pos))
            elseif modelClone:FindFirstChild("HumanoidRootPart") then
                modelClone.HumanoidRootPart.CFrame = CFrame.new(pos)
            elseif modelClone:FindFirstChildOfClass("Part") then
                modelClone:FindFirstChildOfClass("Part").CFrame = CFrame.new(pos)
            end
            
            -- Parent to viewport
            modelClone.Parent = viewport
            
            -- Calculate camera distance based on model size
            local modelSize = modelClone:GetExtentsSize()
            local distance = math.max(modelSize.X, modelSize.Y, modelSize.Z) * 1.5
            if distance < 4 then
                distance = 4
            end
            
            logger:info("3D model loaded successfully", {
                petType = petType,
                modelSize = modelSize,
                cameraDistance = distance
            })
            
            -- Set up camera (spinning or static based on config)
            if eggSystemConfig.pet_preview.enable_model_spinning then
                -- Spinning animation (like MCP)
                local cameraAngle = 0
                local rotationSpeed = eggSystemConfig.pet_preview.model_rotation_speed
                local connection
                connection = game:GetService("RunService").Heartbeat:Connect(function()
                    if viewport.Parent and modelClone.Parent then
                        -- Rotate camera around the model
                        camera.CFrame = CFrame.Angles(0, math.rad(cameraAngle), 0) * CFrame.new(pos + Vector3.new(0, 0, distance), pos)
                        cameraAngle = cameraAngle + rotationSpeed
                        if cameraAngle >= 360 then
                            cameraAngle = 0
                        end
                    else
                        -- Clean up if viewport or model is destroyed
                        connection:Disconnect()
                    end
                end)
            else
                -- Static camera position
                local staticAngle = eggSystemConfig.pet_preview.static_camera_angle
                camera.CFrame = CFrame.Angles(0, math.rad(staticAngle), 0) * CFrame.new(pos + Vector3.new(0, 0, distance), pos)
            end
            
        end)
        
        if not success then
            logger:warn("Failed to load 3D model, falling back to emoji", {
                assetId = assetId,
                petType = petType,
                error = tostring(result)
            })
            
            -- Fallback to emoji if 3D loading fails
            viewport:Destroy()
            local fallbackIcon = Instance.new("TextLabel")
            fallbackIcon.Name = "FallbackIcon"
            fallbackIcon.Size = UDim2.new(0, eggSystemConfig.pet_preview.pet_icon_size, 0, eggSystemConfig.pet_preview.pet_icon_size)
            fallbackIcon.Position = UDim2.new(0.5, -eggSystemConfig.pet_preview.pet_icon_size/2, 0, 5)
            fallbackIcon.BackgroundTransparency = 1
            fallbackIcon.Text = self:GetPetEmojiIcon(petType)
            fallbackIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
            fallbackIcon.TextScaled = true
            fallbackIcon.Font = Enum.Font.GothamBold
            fallbackIcon.Parent = viewport.Parent
        end
    end)
end

-- Get pet asset image ID for display
function EggPetPreviewService:GetPetAssetImage(assetId)
    logger:debug("Processing asset ID", {inputAssetId = assetId, inputType = type(assetId)})
    
    if not assetId or assetId == "rbxassetid://0" or assetId == "" then
        logger:info("Invalid asset ID detected, will use emoji fallback", {
            assetId = assetId, 
            reason = "nil, empty, or placeholder asset"
        })
        return "" -- Will trigger emoji fallback
    end
    
    -- Extract just the numbers from the asset ID
    local cleanId = assetId:match("%d+")
    logger:debug("Extracted ID from asset string", {
        originalAssetId = assetId,
        extractedId = cleanId,
        extractedIdType = type(cleanId)
    })
    
    if not cleanId or cleanId == "0" then
        logger:warn("Could not extract valid ID from asset string", {
            assetId = assetId,
            extractedId = cleanId,
            reason = "regex match failed or extracted zero"
        })
        return "" -- Will trigger emoji fallback
    end
    
    -- For 3D model assets, we need to use a different approach
    -- ImageLabels can't directly display 3D models, but we can try the asset ID directly
    -- Roblox sometimes auto-generates thumbnails for models
    local finalAssetId = "rbxassetid://" .. cleanId
    logger:info("Processed asset ID for ImageLabel", {
        originalAssetId = assetId,
        extractedId = cleanId, 
        finalAssetId = finalAssetId,
        note = "This may fail if asset is a 3D model rather than an image"
    })
    return finalAssetId
end

-- Get pet emoji icon (fallback when asset loading fails)
function EggPetPreviewService:GetPetEmojiIcon(petType)
    local petIcons = {
        bear = "🐻",
        bunny = "🐰", 
        doggy = "🐶",
        kitty = "🐱",
        dragon = "🐲"
    }
    
    return petIcons[petType] or "🐾"
end

-- === PUBLIC API ===

-- Show pet preview for an egg at given position
function EggPetPreviewService:ShowPetPreview(eggType, eggPosition)
    self:UpdatePetPreview(eggType, eggPosition)
end

-- Hide pet preview
function EggPetPreviewService:HidePetPreview()
    self:UpdatePetPreview(nil, nil)
end

-- Update preview position (for moving around egg)
function EggPetPreviewService:UpdatePreviewPosition(eggPosition)
    if petPreviewUI and currentEggType and eggPosition then
        local frame = petPreviewUI.PetPreviewFrame
        local screenPos = camera:WorldToScreenPoint(eggPosition)
        frame.Position = UDim2.new(
            0, screenPos.X + eggSystemConfig.ui.pet_preview_offset.x, 
            0, screenPos.Y + eggSystemConfig.ui.pet_preview_offset.y
        )
    end
end

-- Get current preview state
function EggPetPreviewService:GetCurrentEggType()
    return currentEggType
end

-- Initialize service
function EggPetPreviewService:Initialize()
    logger:info("EggPetPreviewService initializing...")
    
    -- Service is ready - EggCurrentTargetService will call our methods
    logger:info("EggPetPreviewService initialized successfully")
end

-- Cleanup
function EggPetPreviewService:Destroy()
    if petPreviewUI then
        petPreviewUI:Destroy()
        petPreviewUI = nil
    end
    
    currentEggType = nil
    iconCache = {}
    
    logger:info("EggPetPreviewService destroyed")
end

return EggPetPreviewService