--[[
    AssetPreloadService - Preloads all game assets into ReplicatedStorage.Assets
    
    This service:
    1. Extracts all asset IDs from configuration files
    2. Loads models via InsertService and places them in ReplicatedStorage.Assets.Models.Pets
    3. Creates organized folder structure for instant client access
    4. Handles asset loading failures gracefully
    
    Architecture:
    - Server loads models at startup into ReplicatedStorage.Assets.Models.Pets/
    - Client accesses models directly: ReplicatedStorage.Assets.Models.Pets.Bear.Basic
    - No RemoteFunction needed - simple direct access
]]

local AssetPreloadService = {}
AssetPreloadService.__index = AssetPreloadService

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Service dependencies (injected)
local logger
local petConfig
local soundsConfig
local breakablesConfig

function AssetPreloadService:Init()
    logger = self._modules.Logger
    petConfig = self._modules.ConfigLoader:LoadConfig("pets")
    soundsConfig = self._modules.ConfigLoader:LoadConfig("sounds")
    
    -- Optional: breakables (crystals, etc.)
    local ok, cfg = pcall(function()
        return self._modules.ConfigLoader:LoadConfig("breakables")
    end)
    if ok then
        breakablesConfig = cfg
    else
        breakablesConfig = nil
    end
    
    logger:Info("AssetPreloadService initialized")
end

function AssetPreloadService:Start()
    -- Guard against multiple Start() calls (ModuleLoader already calls Start)
    if self._started then
        logger:Warn("⚠️ AssetPreloadService:Start() called more than once - ignoring subsequent call")
        return
    end
    self._started = true

    logger:Info("🚀 AssetPreloadService:Start() called")
    
    -- Create folder structure for assets
    logger:Info("📁 AssetPreloadService: Creating asset folders...")
    self:CreateAssetFolders()
    
    -- Start loading models into ReplicatedStorage.Assets
    logger:Info("🔄 AssetPreloadService: Spawning LoadAllModelsIntoAssets task...")
    task.spawn(function()
        logger:Info("🔄 AssetPreloadService: LoadAllModelsIntoAssets task started")
        self:LoadAllModelsIntoAssets()
        -- Load breakable models (e.g., crystals)
        self:LoadAllBreakableModelsIntoAssets()
        self:LoadAllSoundsIntoAssets()
        logger:Info("✅ AssetPreloadService: LoadAllModelsIntoAssets task completed")
    end)
    
    -- Set up admin regeneration signal
    logger:Info("🔧 AssetPreloadService: Setting up admin regeneration signal...")
    self:SetupAdminRegenerationSignal()
    
    logger:Info("✅ AssetPreloadService:Start() completed")
end

-- Create folder structure in ReplicatedStorage.Assets
function AssetPreloadService:CreateAssetFolders()
    logger:Info("📁 CreateAssetFolders: Starting...")
    
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    logger:Info("📁 CreateAssetFolders: Assets folder", {
        exists = assets ~= nil,
        path = assets and assets:GetFullName() or "nil"
    })
    
    if not assets then
        logger:Info("📁 CreateAssetFolders: Creating Assets folder...")
        assets = Instance.new("Folder")
        assets.Name = "Assets"
        assets.Parent = ReplicatedStorage
        logger:Info("✅ CreateAssetFolders: Assets folder created")
    end
    
    local models = assets:FindFirstChild("Models")
    logger:Info("📁 CreateAssetFolders: Models folder", {
        exists = models ~= nil,
        path = models and models:GetFullName() or "nil"
    })
    
    if not models then
        logger:Info("📁 CreateAssetFolders: Creating Models folder...")
        models = Instance.new("Folder") 
        models.Name = "Models"
        models.Parent = assets
        logger:Info("✅ CreateAssetFolders: Models folder created")
    end
    
    local pets = models:FindFirstChild("Pets")
    logger:Info("📁 CreateAssetFolders: Pets folder", {
        exists = pets ~= nil,
        path = pets and pets:GetFullName() or "nil"
    })
    
    if not pets then
        logger:Info("📁 CreateAssetFolders: Creating Pets folder...")
        pets = Instance.new("Folder")
        pets.Name = "Pets"
        pets.Parent = models
        logger:Info("✅ CreateAssetFolders: Pets folder created")
    end
    
    -- Ensure Breakables/Crystals folder exists
    local breakables = models:FindFirstChild("Breakables")
    if not breakables then
        breakables = Instance.new("Folder")
        breakables.Name = "Breakables"
        breakables.Parent = models
    end
    local crystals = breakables:FindFirstChild("Crystals")
    if not crystals then
        crystals = Instance.new("Folder")
        crystals.Name = "Crystals"
        crystals.Parent = breakables
    end
    
    -- Ensure Sounds folder exists
    local sounds = assets:FindFirstChild("Sounds")
    if not sounds then
        sounds = Instance.new("Folder")
        sounds.Name = "Sounds"
        sounds.Parent = assets
    end

    logger:Info("✅ CreateAssetFolders: Asset folder structure complete", {
        path = "ReplicatedStorage.Assets"
    })
end

-- Load all breakable (non-pet) models such as crystals
function AssetPreloadService:LoadAllBreakableModelsIntoAssets()
    logger:Info("🔄 LoadAllBreakableModelsIntoAssets: Starting...")
    
    if not breakablesConfig then
        logger:Warn("LoadAllBreakableModelsIntoAssets: No breakables config found; skipping")
        return
    end
    
    local modelsRoot = ReplicatedStorage.Assets and ReplicatedStorage.Assets:FindFirstChild("Models")
    if not modelsRoot then
        logger:Error("LoadAllBreakableModelsIntoAssets: Models root missing")
        return
    end
    
    local breakablesFolder = modelsRoot:FindFirstChild("Breakables")
    if not breakablesFolder then
        breakablesFolder = Instance.new("Folder")
        breakablesFolder.Name = "Breakables"
        breakablesFolder.Parent = modelsRoot
    end
    
    local crystalsFolder = breakablesFolder:FindFirstChild("Crystals")
    if not crystalsFolder then
        crystalsFolder = Instance.new("Folder")
        crystalsFolder.Name = "Crystals"
        crystalsFolder.Parent = breakablesFolder
    end
    
    local successCount = 0
    local failureCount = 0
    
    -- Iterate crystals in config
    for crystalName, crystalData in pairs(breakablesConfig.crystals or {}) do
        if type(crystalData) == "table" and crystalData.asset_id and crystalData.asset_id ~= "rbxassetid://0" then
            -- Replace any existing model with same name
            local existing = crystalsFolder:FindFirstChild(crystalName)
            if existing then existing:Destroy() end
            
            local transformCF
            if crystalData.default_orientation and type(crystalData.default_orientation) == "table" then
                local ori = crystalData.default_orientation
                transformCF = CFrame.Angles(math.rad(ori.x or 0), math.rad(ori.y or 0), math.rad(ori.z or 0))
            end
            local ok = self:LoadModelIntoFolder(
                crystalData.asset_id,
                crystalsFolder,
                crystalName,
                "crystal_" .. crystalName,
                { transformCF = transformCF }
            )
            if ok then
                successCount += 1
            else
                failureCount += 1
            end
        else
            logger:Warn("LoadAllBreakableModelsIntoAssets: Crystal missing valid asset_id", {name = tostring(crystalName)})
            failureCount += 1
        end
    end
    
    logger:Info("🔄 LoadAllBreakableModelsIntoAssets: Completed", {
        crystals = {
            successful = successCount,
            failed = failureCount,
        }
    })
end

-- Load all pet models and generate images into ReplicatedStorage.Assets
function AssetPreloadService:LoadAllModelsIntoAssets()
    logger:Info("🔄 LoadAllModelsIntoAssets: Starting...")
    
    local startTime = tick()
    local modelSuccessCount = 0
    local modelFailureCount = 0
    local imageSuccessCount = 0
    local imageFailureCount = 0
    local totalAssets = 0
    
    logger:Info("🔄 LoadAllModelsIntoAssets: Checking dependencies...")
    logger:Info("🔄 LoadAllModelsIntoAssets: petConfig", {
        exists = petConfig ~= nil,
        type = petConfig and type(petConfig) or "nil"
    })
    
    local petsFolder = ReplicatedStorage.Assets.Models.Pets
    logger:Info("🔄 LoadAllModelsIntoAssets: Pets folder found", {
        petsFolderExists = petsFolder ~= nil,
        petsFolderPath = petsFolder and petsFolder:GetFullName() or "nil"
    })
    
    -- Create eggs folder if it doesn't exist
    local eggsFolder = ReplicatedStorage.Assets.Models:FindFirstChild("Eggs")
    if not eggsFolder then
        eggsFolder = Instance.new("Folder")
        eggsFolder.Name = "Eggs"
        eggsFolder.Parent = ReplicatedStorage.Assets.Models
    end
    
    -- Create Images folder structure if it doesn't exist
    local imagesRoot = ReplicatedStorage.Assets:FindFirstChild("Images")
    if not imagesRoot then
        imagesRoot = Instance.new("Folder")
        imagesRoot.Name = "Images"
        imagesRoot.Parent = ReplicatedStorage.Assets
    end
    
    local petImagesFolder = imagesRoot:FindFirstChild("Pets")
    if not petImagesFolder then
        petImagesFolder = Instance.new("Folder")
        petImagesFolder.Name = "Pets"
        petImagesFolder.Parent = imagesRoot
    end
    
    local eggImagesFolder = imagesRoot:FindFirstChild("Eggs")
    if not eggImagesFolder then
        eggImagesFolder = Instance.new("Folder")
        eggImagesFolder.Name = "Eggs"
        eggImagesFolder.Parent = imagesRoot
    end
    
    -- Load pet models and generate images
    logger:Info("🔄 LoadAllModelsIntoAssets: Pet config loaded", {
        petConfigExists = petConfig ~= nil,
        petsTableExists = petConfig and petConfig.pets ~= nil,
        petCount = petConfig and petConfig.pets and #petConfig.pets or 0
    })
    
    if not petConfig or not petConfig.pets then
        logger:Error("❌ LoadAllModelsIntoAssets: No pet config found!")
        return
    end
    
    logger:Info("🔄 LoadAllModelsIntoAssets: Starting pet loop...")
    for petType, petData in pairs(petConfig.pets) do
        logger:Info("🔄 LoadAllModelsIntoAssets: Processing pet type", {
            petType = petType,
            hasVariants = petData.variants ~= nil,
            variantsCount = petData.variants and #petData.variants or 0
        })
        
        if petData.variants then
            -- Create pet type folders (e.g., "Bear")
            local petTypeFolder = petsFolder:FindFirstChild(petType)
            if not petTypeFolder then
                petTypeFolder = Instance.new("Folder")
                petTypeFolder.Name = petType
                petTypeFolder.Parent = petsFolder
            end
            
            local petImageTypeFolder = petImagesFolder:FindFirstChild(petType)
            if not petImageTypeFolder then
                petImageTypeFolder = Instance.new("Folder")
                petImageTypeFolder.Name = petType
                petImageTypeFolder.Parent = petImagesFolder
            end
            
            for variant, variantData in pairs(petData.variants) do
                totalAssets = totalAssets + 1
                
                if variantData.asset_id and variantData.asset_id ~= "rbxassetid://0" then
                    -- Replace existing variant model to avoid duplicates
                    local existingVariant = petTypeFolder:FindFirstChild(variant)
                    if existingVariant then
                        existingVariant:Destroy()
                    end
                    -- Load 3D model
                    local modelSuccess = self:LoadModelIntoFolder(
                        variantData.asset_id,
                        petTypeFolder,
                        variant,
                        petType .. "_" .. variant
                    )
                    
                    if modelSuccess then
                        modelSuccessCount = modelSuccessCount + 1
                        
                        -- Inject per-variant stats (power/health/type/variant) for runtime use
                        do
                            local variantModel = petTypeFolder:FindFirstChild(variant)
                            if variantModel then
                                local powerValue = (variantData.power or petData.base_power or 1)
                                local healthValue = (variantData.health or petData.base_health or 100)
                                -- Set as attributes for quick access and clone carryover
                                variantModel:SetAttribute("PetType", petType)
                                variantModel:SetAttribute("Variant", variant)
                                variantModel:SetAttribute("Power", powerValue)
                                variantModel:SetAttribute("BaseHealth", healthValue)
                                -- Also create NumberValues for scripts that expect Values on the model
                                local powerNV = variantModel:FindFirstChild("Power")
                                if not powerNV then
                                    powerNV = Instance.new("NumberValue")
                                    powerNV.Name = "Power"
                                    powerNV.Value = powerValue
                                    powerNV.Parent = variantModel
                                else
                                    powerNV.Value = powerValue
                                end
                                local typeSV = variantModel:FindFirstChild("PetType")
                                if not typeSV then
                                    typeSV = Instance.new("StringValue")
                                    typeSV.Name = "PetType"
                                    typeSV.Value = petType
                                    typeSV.Parent = variantModel
                                else
                                    typeSV.Value = petType
                                end
                                local varSV = variantModel:FindFirstChild("Variant")
                                if not varSV then
                                    varSV = Instance.new("StringValue")
                                    varSV.Name = "Variant"
                                    varSV.Value = variant
                                    varSV.Parent = variantModel
                                else
                                    varSV.Value = variant
                                end
                            end
                        end
                        
                        -- Generate image from the loaded model
                        local imageSuccess = self:GenerateImageFromModel(
                            petTypeFolder:FindFirstChild(variant),
                            petImageTypeFolder,
                            variant,
                            petType,
                            variant
                        )
                        
                        if imageSuccess then
                            imageSuccessCount = imageSuccessCount + 1
                        else
                            imageFailureCount = imageFailureCount + 1
                        end
                    else
                        modelFailureCount = modelFailureCount + 1
                        imageFailureCount = imageFailureCount + 1  -- Can't generate image without model
                    end
                else
                    logger:Warn("Pet has no valid asset ID", {
                        petType = petType,
                        variant = variant
                    })
                    modelFailureCount = modelFailureCount + 1
                    imageFailureCount = imageFailureCount + 1
                end
            end
        end
    end
    
    -- Load egg models and generate images
    for eggType, eggData in pairs(petConfig.egg_sources or {}) do
        totalAssets = totalAssets + 1
        
        if eggData.asset_id and eggData.asset_id ~= "rbxassetid://0" then
            -- Replace existing egg model to avoid duplicates
            local existingEgg = eggsFolder:FindFirstChild(eggType)
            if existingEgg then
                existingEgg:Destroy()
            end
            -- Load 3D egg model
            local modelSuccess = self:LoadModelIntoFolder(
                eggData.asset_id,
                eggsFolder,
                eggType,
                eggType .. "_egg"
            )
            
            if modelSuccess then
                modelSuccessCount = modelSuccessCount + 1
                
                -- Generate image from the loaded egg model (same as pets)
                local imageSuccess = self:GenerateImageFromModel(
                    eggsFolder:FindFirstChild(eggType),
                    eggImagesFolder,
                    eggType,
                    eggType,  -- petType parameter (for eggs, use eggType)
                    "egg"     -- variant parameter (all eggs are "egg" variant)
                )
                
                if imageSuccess then
                    imageSuccessCount = imageSuccessCount + 1
                else
                    imageFailureCount = imageFailureCount + 1
                end
            else
                modelFailureCount = modelFailureCount + 1
                imageFailureCount = imageFailureCount + 1  -- Can't generate image without model
            end
        else
            logger:Warn("Egg has no valid asset ID", {
                eggType = eggType
            })
            modelFailureCount = modelFailureCount + 1
            imageFailureCount = imageFailureCount + 1
        end
    end
    
    logger:Info("Asset loading completed", {
        models = {
            successful = modelSuccessCount,
            failed = modelFailureCount
        },
        images = {
            successful = imageSuccessCount,
            failed = imageFailureCount
        },
        total = totalAssets,
        duration = tick() - startTime
    })
    
    -- Signal that asset loading is complete
    _G.AssetsLoadingComplete = true
    if _G.AssetsLoadedEvent then
        _G.AssetsLoadedEvent:Fire()
    end
end

-- Preload all configured sounds into ReplicatedStorage.Assets.Sounds
function AssetPreloadService:LoadAllSoundsIntoAssets()
    logger:Info("🔊 LoadAllSoundsIntoAssets: Starting...")
    local soundsFolder = ReplicatedStorage.Assets:FindFirstChild("Sounds")
    if not soundsFolder then
        logger:Error("❌ LoadAllSoundsIntoAssets: Sounds folder missing")
        return
    end

    local count = 0
    for name, soundData in pairs(soundsConfig or {}) do
        if type(soundData) == "table" and soundData.id then
            local sound = soundsFolder:FindFirstChild(name)
            if sound then
                sound:Destroy()
            end
            local s = Instance.new("Sound")
            s.Name = name
            s.SoundId = soundData.id
            if soundData.volume then s.Volume = soundData.volume end
            if soundData.playback_speed then s.PlaybackSpeed = soundData.playback_speed end
            s.Parent = soundsFolder
            count += 1
        end
    end
    logger:Info("🔊 LoadAllSoundsIntoAssets: Completed", {count = count})
end

-- Load a single model into a folder
function AssetPreloadService:LoadModelIntoFolder(assetId, parentFolder, folderName, debugName, options)
    logger:Info("🔄 LoadModelIntoFolder: Starting", {
        assetId = assetId,
        debugName = debugName,
        targetFolder = folderName,
        parentFolder = parentFolder and parentFolder.Name or "nil"
    })
    
    local cleanId = assetId:match("%d+")
    if not cleanId then
        logger:Error("❌ LoadModelIntoFolder: Invalid asset ID format", {
            assetId = assetId,
            debugName = debugName
        })
        return false
    end
    
    logger:Info("🔄 LoadModelIntoFolder: Clean ID extracted", {
        cleanId = cleanId,
        assetId = assetId
    })
    
    local success, result = pcall(function()
        logger:Info("🔄 LoadModelIntoFolder: Loading asset via InsertService", {
            cleanId = cleanId
        })
        
        local loadedAsset = InsertService:LoadAsset(tonumber(cleanId))
        if not loadedAsset then
            error("Failed to load asset: " .. cleanId)
        end
        
        logger:Info("✅ LoadModelIntoFolder: Asset loaded successfully", {
            cleanId = cleanId,
            loadedAssetExists = loadedAsset ~= nil
        })
        
        local model = loadedAsset:FindFirstChildOfClass("Model")
        if not model then
            error("No Model found in asset: " .. cleanId)
        end
        
        logger:Info("✅ LoadModelIntoFolder: Model found in asset", {
            modelName = model.Name,
            modelType = model.ClassName
        })
        
        -- Clone and organize the model
        local modelClone = model:Clone()
        modelClone.Name = folderName
        
        logger:Info("✅ LoadModelIntoFolder: Model cloned", {
            originalName = model.Name,
            newName = modelClone.Name
        })
        
        -- Choose a stable PrimaryPart and pivot model to origin before welding
        self:SetPreferredPrimaryPart(modelClone)
        modelClone:PivotTo(CFrame.identity)
        -- Weld all parts together to prevent falling apart
        logger:Info("🔧 LoadModelIntoFolder: Welding model parts...")
        self:WeldModelParts(modelClone)

        -- Optional transform (e.g., default orientation for breakables)
        if options and options.transformCF then
            logger:Info("🔧 LoadModelIntoFolder: Applying transformCF", {
                hasPrimaryPart = modelClone.PrimaryPart ~= nil
            })
            pcall(function()
                modelClone:PivotTo(options.transformCF)
            end)
        end
        
        -- If this is a pet model, add all the required pet system components
        local isPetFolder = false
        if parentFolder then
            -- We are called with parentFolder either being `Pets` or a child of it (pet type folder)
            isPetFolder = (parentFolder.Name == "Pets") or (parentFolder.Parent and parentFolder.Parent.Name == "Pets")
        end
        if isPetFolder then
            logger:Info("🔧 LoadModelIntoFolder: Adding pet system components...")
            self:AddPetSystemComponents(modelClone)
        end
        
        modelClone.Parent = parentFolder
        
        logger:Info("✅ LoadModelIntoFolder: Model parented to folder", {
            modelName = modelClone.Name,
            parentFolder = parentFolder.Name
        })
        
        -- Clean up the original asset
        loadedAsset:Destroy()
        
        logger:Info("✅ LoadModelIntoFolder: Model successfully loaded into folder", {
            assetId = assetId,
            debugName = debugName,
            modelName = modelClone.Name,
            path = parentFolder:GetFullName() .. "." .. folderName
        })
        
        return true
    end)

    if not success then
        logger:Warn("Failed to load model", {
            assetId = assetId,
            debugName = debugName,
            error = tostring(result)
        })
        -- In Studio, also surface the original engine error so the clickable "Grant access" link appears
        local RunService = game:GetService("RunService")
        if RunService:IsStudio() then
            warn(result)
        end
        return false
    end
    return true
end

-- Prefer Face/Head as PrimaryPart when available
function AssetPreloadService:SetPreferredPrimaryPart(model)
    if not model or not model:IsA("Model") then return end
    local chosen = model.PrimaryPart
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            local n = string.lower(d.Name)
            if string.find(n, "face") or string.find(n, "head") then
                chosen = d
                break
            end
        end
    end
    if chosen then
        model.PrimaryPart = chosen
    end
end

    -- Generate a ViewportFrame image from a loaded model (works for both pets and eggs)
    function AssetPreloadService:GenerateImageFromModel(model, parentFolder, folderName, itemType, variant)
        if not model or not model:IsA("Model") then
            logger:Warn("Invalid model for image generation", {
                itemType = itemType,
                variant = variant,
                modelExists = model ~= nil,
                modelType = model and model.ClassName or "nil"
            })
            return false
        end
        
        local success, result = pcall(function()
            -- Get camera configuration (works for both pets and eggs)
            local cameraConfig = self:GetCameraConfig(itemType)
            
            -- Position model for image capture - RESET BOTH POSITION AND ROTATION
            local modelClone = model:Clone()
            local modelCFrame, modelSize = modelClone:GetBoundingBox()
            
            -- Always reset to identity CFrame (0,0,0 position + no rotation)
            if modelClone.PrimaryPart then
                modelClone:SetPrimaryPartCFrame(CFrame.identity)
            else
                -- For models without PrimaryPart, manually set each part to origin with no rotation
                local modelCenter = modelClone:GetBoundingBox()
                
                -- Set each part to identity CFrame (0,0,0 position, no rotation)
                for _, part in pairs(modelClone:GetDescendants()) do
                    if part:IsA("BasePart") then
                        -- Calculate offset from model center
                        local offset = part.Position - modelCenter.Position
                        -- Set to origin plus offset, with no rotation
                        part.CFrame = CFrame.new(offset)
                    end
                end
            end
        
        -- Calculate camera position based on configuration using proper spherical coordinates
        local angleYRad = math.rad(cameraConfig.angle_y)  -- Horizontal rotation (around Y-axis)
        local angleXRad = math.rad(cameraConfig.angle_x)  -- Vertical rotation (elevation)
        
        -- Use spherical coordinates: distance, horizontal angle, vertical angle
        local cameraOffset = Vector3.new(
            math.sin(angleYRad) * math.cos(angleXRad) * cameraConfig.distance,  -- X: affected by both angles
            math.sin(angleXRad) * cameraConfig.distance,                       -- Y: vertical elevation
            math.cos(angleYRad) * math.cos(angleXRad) * cameraConfig.distance   -- Z: affected by both angles
        )
        
        local cameraPosition = cameraOffset + cameraConfig.offset
        
        -- Remove existing ViewportFrame if it exists (for regeneration)
        local existingViewport = parentFolder:FindFirstChild(folderName)
        if existingViewport then
            existingViewport:Destroy()
        end
        
        -- Create ViewportFrame for this pet
        local viewport = Instance.new("ViewportFrame")
        viewport.Name = folderName
        viewport.Size = UDim2.new(1, 0, 1, 0)  -- Full size, will be scaled by UI
        viewport.BackgroundTransparency = 1
        viewport.Parent = parentFolder
        
        -- Create and configure camera
        local camera = Instance.new("Camera")
        camera.CFrame = CFrame.lookAt(cameraPosition, Vector3.new(0, 0, 0))
        camera.Parent = viewport
        viewport.CurrentCamera = camera
        
        -- Add model to viewport
        modelClone.Parent = viewport
        
        logger:Info("Generated ViewportFrame image", {
            itemType = itemType,
            variant = variant,
            cameraConfig = {
                distance = cameraConfig.distance,
                angle_y = cameraConfig.angle_y,
                angle_x = cameraConfig.angle_x,
                offset = cameraConfig.offset
            },
            calculatedPosition = cameraPosition,
            modelSize = modelSize,
            isEgg = petConfig.egg_sources[itemType] ~= nil
        })
        
        return true
    end)
    
    if success then
        return true
    else
        logger:Error("Failed to generate image", {
            itemType = itemType,
            variant = variant,
            error = result
        })
        return false
    end
end

-- Note: Eggs now use the same GenerateImageFromModel function as pets

-- Get camera configuration for pet type or egg type
function AssetPreloadService:GetCameraConfig(itemType)
    local assetImageConfig = petConfig.asset_images
    
    -- Check if it's an egg first
    local eggData = petConfig.egg_sources[itemType]
    if eggData then
        -- It's an egg - use egg camera config or egg default
        return (eggData and eggData.camera) or assetImageConfig.default_egg_camera
    end
    
    -- It's a pet - use pet camera config or pet default
    local petData = petConfig.pets[itemType]
    local cameraConfig = (petData and petData.camera) or assetImageConfig.default_camera
    
    return cameraConfig
end

-- Get model from ReplicatedStorage.Assets (for external access if needed)
function AssetPreloadService:GetModelFromAssets(petType, variant)
    local petsFolder = ReplicatedStorage.Assets.Models.Pets
    local petTypeFolder = petsFolder:FindFirstChild(petType)
    
    if petTypeFolder then
        local model = petTypeFolder:FindFirstChild(variant)
        if model then
            return model:Clone()
        end
    end
    
    logger:Warn("Model not found in assets", {
        petType = petType,
        variant = variant,
        path = "ReplicatedStorage.Assets.Models.Pets." .. petType .. "." .. variant
    })
    
    return nil
end

-- Check if a model is available in assets
function AssetPreloadService:IsModelInAssets(petType, variant)
    local petsFolder = ReplicatedStorage.Assets.Models.Pets
    local petTypeFolder = petsFolder:FindFirstChild(petType)
    
    if petTypeFolder then
        return petTypeFolder:FindFirstChild(variant) ~= nil
    end
    
    return false
end

-- Get image from ReplicatedStorage.Assets (for external access)
function AssetPreloadService:GetImageFromAssets(petType, variant)
    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if not assetsFolder then return nil end
    
    local imagesRoot = assetsFolder:FindFirstChild("Images")
    if not imagesRoot then return nil end
    
    local imagesFolder = imagesRoot:FindFirstChild("Pets")
    if not imagesFolder then return nil end
    
    local petTypeFolder = imagesFolder:FindFirstChild(petType)
    if petTypeFolder then
        local image = petTypeFolder:FindFirstChild(variant)
        if image then
            return image:Clone()
        end
    end
    
    logger:Warn("Image not found in assets", {
        petType = petType,
        variant = variant,
        path = "ReplicatedStorage.Assets.Images.Pets." .. petType .. "." .. variant
    })
    
    return nil
end

-- Get egg image from ReplicatedStorage.Assets (for external access)
function AssetPreloadService:GetEggImageFromAssets(eggType)
    local imagesRoot = ReplicatedStorage.Assets:FindFirstChild("Images")
    if not imagesRoot then return nil end
    
    local eggImagesFolder = imagesRoot:FindFirstChild("Eggs")
    if not eggImagesFolder then return nil end
    
    local eggImage = eggImagesFolder:FindFirstChild(eggType)
    if eggImage then
        return eggImage:Clone()
    end
    
    logger:Warn("Egg image not found in assets", {
        eggType = eggType,
        path = "ReplicatedStorage.Assets.Images.Eggs." .. eggType
    })
    
    return nil
end

-- Check if an image is available in assets
function AssetPreloadService:IsImageInAssets(petType, variant)
    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if not assetsFolder then return false end
    
    local imagesRoot = assetsFolder:FindFirstChild("Images")
    if not imagesRoot then return false end
    
    local imagesFolder = imagesRoot:FindFirstChild("Pets")
    if not imagesFolder then return false end
    
    local petTypeFolder = imagesFolder:FindFirstChild(petType)
    if petTypeFolder then
        return petTypeFolder:FindFirstChild(variant) ~= nil
    end
    
    return false
end

-- Get loading statistics
function AssetPreloadService:GetLoadingStats()
    local petsFolder = ReplicatedStorage.Assets.Models.Pets
    local petCount = 0
    local variantCount = 0
    
    for _, petTypeFolder in ipairs(petsFolder:GetChildren()) do
        if petTypeFolder:IsA("Folder") then
            petCount = petCount + 1
            for _, variant in ipairs(petTypeFolder:GetChildren()) do
                if variant:IsA("Model") then
                    variantCount = variantCount + 1
                end
            end
        end
    end
    
    return {
        petTypes = petCount,
        totalVariants = variantCount,
        folderPath = petsFolder:GetFullName()
    }
end

-- Set up admin signal for force regeneration
function AssetPreloadService:SetupAdminRegenerationSignal()
    local Signals = require(ReplicatedStorage.Shared.Network.Signals)
    local AdminChecker = require(ReplicatedStorage.Shared.Utils.AdminChecker)
    
    Signals.ForceRegenerateAssets.OnServerEvent:Connect(function(player, data)
        if not AdminChecker:IsAdmin(player) then
            logger:Warn("Non-admin attempted asset regeneration", {
                player = player.Name,
                userId = player.UserId
            })
            return
        end
        
        logger:Info("Admin force regeneration triggered", {
            player = player.Name,
            userId = player.UserId
        })
        
        -- Force regenerate all assets
        self:LoadAllModelsIntoAssets()
    end)
end

-- Weld all parts in a model together to prevent them from falling apart
function AssetPreloadService:WeldModelParts(model)
    if not model or not model:IsA("Model") then
        return
    end
    
    -- Get all BaseParts in the model
    local parts = {}
    for _, descendant in pairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end
    
    if #parts <= 1 then
        return -- Nothing to weld
    end
    
    -- Determine the root part to weld everything to
    local rootPart = model.PrimaryPart
    
    -- If no PrimaryPart, try to find a part named "Head", "Face", or use the first part
    if not rootPart then
        for _, part in pairs(parts) do
            if part.Name:lower():find("head") or part.Name:lower():find("face") then
                rootPart = part
                break
            end
        end
        
        -- If still no root part, use the first part
        if not rootPart and #parts > 0 then
            rootPart = parts[1]
        end
    end
    
    if not rootPart then
        logger:Warn("Could not determine root part for welding", {
            modelName = model.Name
        })
        return
    end
    
    -- Weld all other parts to the root part
    local weldCount = 0
    for _, part in pairs(parts) do
        if part ~= rootPart and part.Parent then
            -- If the initial separation from root is excessive, snap the part to the root
            local delta = (part.Position - rootPart.Position)
            if math.abs(delta.X) > 5 or math.abs(delta.Y) > 5 or math.abs(delta.Z) > 5 then
                part.CFrame = rootPart.CFrame
            end
            -- Create a WeldConstraint to join the parts
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = rootPart
            weld.Part1 = part
            weld.Parent = rootPart
            
            -- Unanchor the part since it's now welded
            part.Anchored = false
            
            weldCount = weldCount + 1
        end
    end
    
    -- Ensure the root part is unanchored so the whole model can move
    rootPart.Anchored = false
    
    -- Set the PrimaryPart if it wasn't already set
    if not model.PrimaryPart then
        model.PrimaryPart = rootPart
    end
    
    logger:Debug("Welded model parts", {
        modelName = model.Name,
        rootPart = rootPart.Name,
        totalParts = #parts,
        weldsCreated = weldCount
    })
end

-- Add all required pet system components to a pet model
function AssetPreloadService:AddPetSystemComponents(petModel)
    logger:Info("🔧 AddPetSystemComponents: Starting...", {
        modelExists = petModel ~= nil,
        modelType = petModel and petModel.ClassName or "nil",
        modelName = petModel and petModel.Name or "nil"
    })
    
    if not petModel or not petModel:IsA("Model") then
        logger:Error("❌ AddPetSystemComponents: Invalid pet model for component addition", {
            modelExists = petModel ~= nil,
            modelType = petModel and petModel.ClassName or "nil"
        })
        return
    end
    
    logger:Info("🔧 AddPetSystemComponents: Adding components to model", {
        modelName = petModel.Name
    })
    
    -- 1. Create all required values on the pet model
    local values = {
        {name = "TargetID", class = "NumberValue", value = 0},
        {name = "PetID", class = "NumberValue", value = 0},
        {name = "PetSize", class = "Vector3Value", value = Vector3.new(1,1,1)},
        {name = "Pos", class = "Vector3Value", value = Vector3.new(0,0,0)},
        {name = "PositionNumber", class = "NumberValue", value = 0},
        {name = "Refresh", class = "BoolValue", value = false},
        {name = "TargetType", class = "StringValue", value = ""},
        {name = "TargetWorld", class = "StringValue", value = ""},
        {name = "Timer", class = "NumberValue", value = 0},
        {name = "AttackPos", class = "StringValue", value = ""}
    }
    
    for _, valueData in pairs(values) do
        local value = Instance.new(valueData.class)
        value.Name = valueData.name
        value.Value = valueData.value
        value.Parent = petModel
    end
    
    -- 2. Add Follow script placeholder to the pet model (disabled)
    -- NOTE: Do not set `Script.Source` at runtime; it is read-only in live games.
    local followScript = Instance.new("Script")
    followScript.Name = "Follow"
    followScript.Disabled = true
    followScript.Parent = petModel
    
    -- 3. Add attachmentPet to the pet model's PrimaryPart
    if petModel.PrimaryPart then
        local attachmentPet = Instance.new("Attachment")
        attachmentPet.Name = "attachmentPet"
        attachmentPet.Parent = petModel.PrimaryPart
    end
    
    -- 4. Set initial pet size
    petModel.PetSize.Value = petModel:GetExtentsSize()
    
    logger:Info("✅ AddPetSystemComponents: Pet system components added to model", {
        modelName = petModel.Name,
        valuesCreated = #values,
        hasFollowScript = petModel:FindFirstChild("Follow") ~= nil,
        hasAttachmentPet = petModel.PrimaryPart and petModel.PrimaryPart:FindFirstChild("attachmentPet") ~= nil,
        totalChildren = #petModel:GetChildren()
    })
end

return AssetPreloadService