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

-- Load all pet models into ReplicatedStorage.Assets.Models.Pets
function AssetPreloadService:LoadAllModelsIntoAssets()
    local startTime = tick()
    local successCount = 0
    local failureCount = 0
    local totalAssets = 0
    
    local petsFolder = ReplicatedStorage.Assets.Models.Pets
    
    -- Load pet models
    for petType, petData in pairs(petConfig.pets or {}) do
        if petData.variants then
            -- Create pet type folder (e.g., "Bear")
            local petTypeFolder = petsFolder:FindFirstChild(petType)
            if not petTypeFolder then
                petTypeFolder = Instance.new("Folder")
                petTypeFolder.Name = petType
                petTypeFolder.Parent = petsFolder
            end
            
            for variant, variantData in pairs(petData.variants) do
                totalAssets = totalAssets + 1
                
                if variantData.asset_id and variantData.asset_id ~= "rbxassetid://0" then
                    local success = self:LoadModelIntoFolder(
                        variantData.asset_id,
                        petTypeFolder,
                        variant,
                        petType .. "_" .. variant
                    )
                    
                    if success then
                        successCount = successCount + 1
                    else
                        failureCount = failureCount + 1
                    end
                else
                    logger:Warn("Pet has no valid asset ID", {
                        petType = petType,
                        variant = variant
                    })
                    failureCount = failureCount + 1
                end
            end
        end
    end
    
    logger:Info("Pet model loading completed", {
        successful = successCount,
        failed = failureCount,
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