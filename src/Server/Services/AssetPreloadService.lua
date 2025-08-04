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

function AssetPreloadService:Init()
    logger = self._modules.Logger
    petConfig = self._modules.ConfigLoader:LoadConfig("pets")
    
    logger:Info("AssetPreloadService initialized")
end

function AssetPreloadService:Start()
    logger:Info("Starting asset preloading into ReplicatedStorage.Assets...")
    
    -- Create folder structure for assets
    self:CreateAssetFolders()
    
    -- Start loading models into ReplicatedStorage.Assets
    task.spawn(function()
        self:LoadAllModelsIntoAssets()
    end)
end

-- Create folder structure in ReplicatedStorage.Assets
function AssetPreloadService:CreateAssetFolders()
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    if not assets then
        assets = Instance.new("Folder")
        assets.Name = "Assets"
        assets.Parent = ReplicatedStorage
    end
    
    local models = assets:FindFirstChild("Models")
    if not models then
        models = Instance.new("Folder") 
        models.Name = "Models"
        models.Parent = assets
    end
    
    local pets = models:FindFirstChild("Pets")
    if not pets then
        pets = Instance.new("Folder")
        pets.Name = "Pets"
        pets.Parent = models
    end
    
    logger:Info("Created asset folder structure", {
        path = "ReplicatedStorage.Assets.Models.Pets"
    })
end

-- Load all pet models and generate images into ReplicatedStorage.Assets
function AssetPreloadService:LoadAllModelsIntoAssets()
    local startTime = tick()
    local modelSuccessCount = 0
    local modelFailureCount = 0
    local imageSuccessCount = 0
    local imageFailureCount = 0
    local totalAssets = 0
    
    local petsFolder = ReplicatedStorage.Assets.Models.Pets
    
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
    for petType, petData in pairs(petConfig.pets or {}) do
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
                    -- Load 3D model
                    local modelSuccess = self:LoadModelIntoFolder(
                        variantData.asset_id,
                        petTypeFolder,
                        variant,
                        petType .. "_" .. variant
                    )
                    
                    if modelSuccess then
                        modelSuccessCount = modelSuccessCount + 1
                        
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
            -- Load 3D egg model
            local modelSuccess = self:LoadModelIntoFolder(
                eggData.asset_id,
                eggsFolder,
                eggType,
                eggType .. "_egg"
            )
            
            if modelSuccess then
                modelSuccessCount = modelSuccessCount + 1
                
                -- Generate image from the loaded egg model
                local imageSuccess = self:GenerateEggImageFromModel(
                    eggsFolder:FindFirstChild(eggType),
                    eggImagesFolder,
                    eggType,
                    eggType
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
end

-- Load a single model into a folder
function AssetPreloadService:LoadModelIntoFolder(assetId, parentFolder, folderName, debugName)
    local cleanId = assetId:match("%d+")
    if not cleanId then
        logger:Warn("Invalid asset ID format", {
            assetId = assetId,
            debugName = debugName
        })
        return false
    end
    
    logger:Debug("Loading model into folder", {
        assetId = assetId,
        debugName = debugName,
        targetFolder = folderName
    })
    
    local success, result = pcall(function()
        local loadedAsset = InsertService:LoadAsset(tonumber(cleanId))
        if not loadedAsset then
            error("Failed to load asset: " .. cleanId)
        end
        
        local model = loadedAsset:FindFirstChildOfClass("Model")
        if not model then
            error("No Model found in asset: " .. cleanId)
        end
        
        -- Clone and organize the model
        local modelClone = model:Clone()
        modelClone.Name = folderName
        modelClone.Parent = parentFolder
        
        -- Clean up the original asset
        loadedAsset:Destroy()
        
        logger:Debug("Model successfully loaded into folder", {
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
        return false
    end
    
    return true
end

-- Generate a ViewportFrame image from a loaded model
function AssetPreloadService:GenerateImageFromModel(model, parentFolder, folderName, petType, variant)
    if not model or not model:IsA("Model") then
        logger:Warn("Invalid model for image generation", {
            petType = petType,
            variant = variant,
            modelExists = model ~= nil,
            modelType = model and model.ClassName or "nil"
        })
        return false
    end
    
    local success, result = pcall(function()
        -- Get camera configuration from pet config
        local cameraConfig = self:GetCameraConfig(petType)
        
        -- Position model for image capture
        local modelClone = model:Clone()
        local modelCFrame, modelSize = modelClone:GetBoundingBox()
        
        if modelClone.PrimaryPart then
            modelClone:SetPrimaryPartCFrame(CFrame.new(0, 0, 0))
        else
            modelClone:MoveTo(Vector3.new(0, 0, 0))
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
        
        logger:Info("Generated image for pet", {
            petType = petType,
            variant = variant,
            cameraConfig = {
                distance = cameraConfig.distance,
                angle_y = cameraConfig.angle_y,
                angle_x = cameraConfig.angle_x,
                offset = cameraConfig.offset
            },
            calculatedPosition = cameraPosition,
            modelSize = modelSize,
            storagePath = "ReplicatedStorage.Assets.Images.Pets." .. petType .. "." .. folderName
        })
        
        return true
    end)
    
    if success then
        return true
    else
        logger:Error("Failed to generate image", {
            petType = petType,
            variant = variant,
            error = result
        })
        return false
    end
end

-- Generate a ViewportFrame image from a loaded egg model
function AssetPreloadService:GenerateEggImageFromModel(model, parentFolder, eggType, folderName)
    if not model or not model:IsA("Model") then
        logger:Warn("Invalid egg model for image generation", {
            eggType = eggType,
            modelExists = model ~= nil,
            modelType = model and model.ClassName or "nil"
        })
        return false
    end
    
    local success, result = pcall(function()
        -- Get camera configuration from egg config (or use default)
        local eggData = petConfig.egg_sources[eggType]
        local cameraConfig = (eggData and eggData.camera) or petConfig.asset_images.default_egg_camera
        
        -- Position model for image capture
        local modelClone = model:Clone()
        local modelCFrame, modelSize = modelClone:GetBoundingBox()
        
        if modelClone.PrimaryPart then
            modelClone:SetPrimaryPartCFrame(CFrame.new(0, 0, 0))
        else
            modelClone:MoveTo(Vector3.new(0, 0, 0))
        end
        
        -- Calculate camera position using spherical coordinates (same as pets)
        local angleYRad = math.rad(cameraConfig.angle_y)  -- Horizontal rotation (around Y-axis)
        local angleXRad = math.rad(cameraConfig.angle_x)  -- Vertical rotation (elevation)
        
        local cameraOffset = Vector3.new(
            math.sin(angleYRad) * math.cos(angleXRad) * cameraConfig.distance,
            math.sin(angleXRad) * cameraConfig.distance,
            math.cos(angleYRad) * math.cos(angleXRad) * cameraConfig.distance
        )
        
        local cameraPosition = cameraOffset + cameraConfig.offset
        
        -- Remove existing ViewportFrame if it exists (for regeneration)
        local existingViewport = parentFolder:FindFirstChild(folderName)
        if existingViewport then
            existingViewport:Destroy()
        end
        
        -- Create ViewportFrame for this egg
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
        
        logger:Info("Generated image for egg", {
            eggType = eggType,
            cameraConfig = {
                distance = cameraConfig.distance,
                angle_y = cameraConfig.angle_y,
                angle_x = cameraConfig.angle_x,
                offset = cameraConfig.offset,
                lighting = cameraConfig.lighting
            },
            calculatedPosition = cameraPosition,
            modelSize = modelSize,
            storagePath = "ReplicatedStorage.Assets.Images.Eggs." .. folderName
        })
        
        return true
    end)
    
    if success then
        return true
    else
        logger:Error("Failed to generate egg image", {
            eggType = eggType,
            error = result
        })
        return false
    end
end

-- Get camera configuration for pet type
function AssetPreloadService:GetCameraConfig(petType)
    local assetImageConfig = petConfig.asset_images
    
    -- Get camera config from the pet's definition, fallback to default
    local petData = petConfig.pets[petType]
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

return AssetPreloadService