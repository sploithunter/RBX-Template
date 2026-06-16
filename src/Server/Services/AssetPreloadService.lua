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
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetFetch = require(ReplicatedStorage.Shared.Utils.AssetFetch)
local PetVariantVisuals = require(ReplicatedStorage.Shared.Services.PetVariantVisuals)
local MeshAssembly = require(ReplicatedStorage.Shared.Assets.MeshAssembly)

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
        logger:Warn(
            "⚠️ AssetPreloadService:Start() called more than once - ignoring subsequent call"
        )
        return
    end
    self._started = true

    logger:Info("🚀 AssetPreloadService:Start() called")

    -- Create folder structure for assets
    logger:Info("📁 AssetPreloadService: Creating asset folders...")
    self:CreateAssetFolders()
    ReplicatedStorage.Assets:SetAttribute("PetThumbnailsReady", false)
    ReplicatedStorage.Assets:SetAttribute("PetThumbnailCount", 0)
    ReplicatedStorage.Assets:SetAttribute("PetThumbnailFailures", 0)

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
        path = assets and assets:GetFullName() or "nil",
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
        path = models and models:GetFullName() or "nil",
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
        path = pets and pets:GetFullName() or "nil",
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
        path = "ReplicatedStorage.Assets",
    })
end

local function createHealthBillboard(parentPart)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BillboardGui"
    billboard.Size = UDim2.new(0, 110, 0, 16)
    billboard.StudsOffset = Vector3.new(0, 2.2, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 75
    billboard.Parent = parentPart

    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.new(0, 100, 0, 10)
    background.Position = UDim2.new(0, 5, 0, 3)
    background.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    background.BorderSizePixel = 0
    background.Parent = billboard

    local health = Instance.new("Frame")
    health.Name = "Health"
    health.Size = UDim2.new(0, 100, 0, 10)
    health.BackgroundColor3 = Color3.fromRGB(45, 220, 95)
    health.BorderSizePixel = 0
    health.Parent = background
end

local function createCoinStackModel()
    local model = Instance.new("Model")
    model.Name = "CoinStack"

    local hitbox = Instance.new("Part")
    hitbox.Name = "Hitbox"
    hitbox.Size = Vector3.new(3.5, 2.2, 3.5)
    hitbox.Transparency = 1
    hitbox.Anchored = true
    hitbox.CanCollide = false
    hitbox.CanTouch = false
    hitbox.CanQuery = true
    hitbox.Parent = model
    model.PrimaryPart = hitbox

    for i = 1, 6 do
        local coin = Instance.new("Part")
        coin.Name = "Coin" .. tostring(i)
        coin.Shape = Enum.PartType.Cylinder
        coin.Size = Vector3.new(2.7, 0.22, 2.7)
        coin.Anchored = true
        coin.CanCollide = false
        coin.CanTouch = false
        coin.CanQuery = true
        coin.Material = Enum.Material.Metal
        coin.Color = Color3.fromRGB(255, 205, 55)
        coin.CFrame = CFrame.new((i % 2) * 0.08, (i - 1) * 0.2, ((i + 1) % 2) * 0.08)
            * CFrame.Angles(0, math.rad(i * 19), 0)
        coin.Parent = model
    end

    local sparkle = Instance.new("PointLight")
    sparkle.Name = "CoinGlow"
    sparkle.Color = Color3.fromRGB(255, 220, 95)
    sparkle.Brightness = 0.8
    sparkle.Range = 8
    sparkle.Parent = hitbox

    createHealthBillboard(hitbox)
    model:PivotTo(CFrame.identity)
    return model
end

local function createProceduralBreakableModel(kind)
    if kind == "coin_stack" then
        return createCoinStackModel()
    end
    return nil
end

local function normalizedAssetTransform(transform)
    if type(transform) ~= "table" then
        return {}
    end

    local normalized = {}
    if tonumber(transform.scale) then
        normalized.scale = tonumber(transform.scale)
    end
    if tonumber(transform.huge_scale) then
        normalized.hugeScale = tonumber(transform.huge_scale)
    elseif tonumber(transform.hugeScale) then
        normalized.hugeScale = tonumber(transform.hugeScale)
    end

    if type(transform.orientation) == "table" then
        normalized.orientation = {
            x = tonumber(transform.orientation.x) or 0,
            y = tonumber(transform.orientation.y) or 0,
            z = tonumber(transform.orientation.z) or 0,
        }
    end

    return normalized
end

local function mergeAssetTransforms(baseTransform, overrideTransform)
    local merged = normalizedAssetTransform(baseTransform)
    local override = normalizedAssetTransform(overrideTransform)

    if override.scale ~= nil then
        merged.scale = override.scale
    end
    if override.hugeScale ~= nil then
        merged.hugeScale = override.hugeScale
    end
    if override.orientation ~= nil then
        merged.orientation = override.orientation
    end

    merged.scale = merged.scale or 1
    merged.hugeScale = merged.hugeScale or 1
    merged.orientation = merged.orientation or { x = 0, y = 0, z = 0 }
    return merged
end

function AssetPreloadService:ResolvePetAssetTransform(petData, variantData)
    return mergeAssetTransforms(
        petData and petData.asset_transform,
        variantData and variantData.asset_transform
    )
end

function AssetPreloadService:ApplyConfiguredModelTransform(model, options)
    if not model or not model:IsA("Model") or type(options) ~= "table" then
        return
    end

    local scale = tonumber(options.scale)
    if scale and scale > 0 and math.abs(scale - 1) > 0.001 then
        local ok, err = pcall(function()
            model:ScaleTo(scale)
        end)
        if not ok then
            logger:Warn("Failed to apply configured model scale", {
                model = model.Name,
                scale = scale,
                error = tostring(err),
            })
        end
    end

    local transformCF = options.transformCF
    if not transformCF and type(options.orientation) == "table" then
        local orientation = options.orientation
        transformCF = CFrame.Angles(
            math.rad(orientation.x or 0),
            math.rad(orientation.y or 0),
            math.rad(orientation.z or 0)
        )
    end

    if transformCF then
        pcall(function()
            model:PivotTo(transformCF)
        end)
    end
end

function AssetPreloadService:ApplyPetTransformAttributes(model, transformOptions)
    if not model or not model:IsA("Model") or type(transformOptions) ~= "table" then
        return
    end

    local orientation = transformOptions.orientation or {}
    model:SetAttribute("AssetScale", tonumber(transformOptions.scale) or 1)
    model:SetAttribute("HugeScale", tonumber(transformOptions.hugeScale) or 1)
    model:SetAttribute("OrientationX", tonumber(orientation.x) or 0)
    model:SetAttribute("OrientationY", tonumber(orientation.y) or 0)
    model:SetAttribute("OrientationZ", tonumber(orientation.z) or 0)
end

function AssetPreloadService:NormalizePetModelParts(model)
    if not model or not model:IsA("Model") then
        return
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.Massless = true
            descendant.AssemblyLinearVelocity = Vector3.new()
            descendant.AssemblyAngularVelocity = Vector3.new()
        end
    end
end

-- Load all breakable (non-pet) models such as crystals
function AssetPreloadService:LoadAllBreakableModelsIntoAssets()
    logger:Info("🔄 LoadAllBreakableModelsIntoAssets: Starting...")

    if not breakablesConfig then
        logger:Warn("LoadAllBreakableModelsIntoAssets: No breakables config found; skipping")
        return
    end

    local modelsRoot = ReplicatedStorage.Assets
        and ReplicatedStorage.Assets:FindFirstChild("Models")
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

    -- Iterate crystals/breakables in config
    for crystalName, crystalData in pairs(breakablesConfig.crystals or {}) do
        if type(crystalData) == "table" and crystalData.procedural_asset then
            local existing = crystalsFolder:FindFirstChild(crystalName)
            if existing then
                existing:Destroy()
            end

            local model = createProceduralBreakableModel(crystalData.procedural_asset)
            if model then
                model.Name = crystalName
                model.Parent = crystalsFolder
                successCount += 1
            else
                logger:Warn("LoadAllBreakableModelsIntoAssets: Unknown procedural breakable", {
                    name = tostring(crystalName),
                    proceduralAsset = tostring(crystalData.procedural_asset),
                })
                failureCount += 1
            end
        elseif
            type(crystalData) == "table"
            and crystalData.asset_id
            and crystalData.asset_id ~= "rbxassetid://0"
        then
            -- Replace any existing model with same name
            local existing = crystalsFolder:FindFirstChild(crystalName)
            if existing then
                existing:Destroy()
            end

            local transformCF
            if
                crystalData.default_orientation
                and type(crystalData.default_orientation) == "table"
            then
                local ori = crystalData.default_orientation
                transformCF =
                    CFrame.Angles(math.rad(ori.x or 0), math.rad(ori.y or 0), math.rad(ori.z or 0))
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
            logger:Warn(
                "LoadAllBreakableModelsIntoAssets: Crystal missing valid asset_id",
                { name = tostring(crystalName) }
            )
            failureCount += 1
        end
    end

    logger:Info("🔄 LoadAllBreakableModelsIntoAssets: Completed", {
        crystals = {
            successful = successCount,
            failed = failureCount,
        },
    })
end

-- Load all pet models and generate images into ReplicatedStorage.Assets
function AssetPreloadService:LoadAllModelsIntoAssets()
    logger:Info("🔄 LoadAllModelsIntoAssets: Starting...")
    ReplicatedStorage.Assets:SetAttribute("PetThumbnailsReady", false)
    ReplicatedStorage.Assets:SetAttribute("PetThumbnailCount", 0)
    ReplicatedStorage.Assets:SetAttribute("PetThumbnailFailures", 0)

    local startTime = tick()
    local modelSuccessCount = 0
    local modelFailureCount = 0
    local imageSuccessCount = 0
    local imageFailureCount = 0
    local totalAssets = 0

    logger:Info("🔄 LoadAllModelsIntoAssets: Checking dependencies...")
    logger:Info("🔄 LoadAllModelsIntoAssets: petConfig", {
        exists = petConfig ~= nil,
        type = petConfig and type(petConfig) or "nil",
    })

    local petsFolder = ReplicatedStorage.Assets.Models.Pets
    logger:Info("🔄 LoadAllModelsIntoAssets: Pets folder found", {
        petsFolderExists = petsFolder ~= nil,
        petsFolderPath = petsFolder and petsFolder:GetFullName() or "nil",
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
        petCount = petConfig and petConfig.pets and #petConfig.pets or 0,
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
            variantsCount = petData.variants and #petData.variants or 0,
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
                local transformOptions = self:ResolvePetAssetTransform(petData, variantData)

                local hasMeshAsset = type(variantData.mesh_asset) == "string"
                    and variantData.mesh_asset ~= ""
                    and variantData.mesh_asset ~= "rbxassetid://0"
                local hasAssetId = variantData.asset_id and variantData.asset_id ~= "rbxassetid://0"

                if hasMeshAsset or hasAssetId then
                    local existingVariant = petTypeFolder:FindFirstChild(variant)
                    local modelSuccess

                    if hasMeshAsset then
                        -- Combine path: textured MeshPart from a separately-uploaded mesh + texture
                        -- (FBX->Model uploads come out untextured). Mirrors the enemy/gem combine.
                        if existingVariant then
                            existingVariant:Destroy()
                        end
                        modelSuccess = self:BuildMeshPartModelIntoFolder(
                            variantData.mesh_asset,
                            variantData.texture_asset,
                            petTypeFolder,
                            variant,
                            petType .. "_" .. variant,
                            transformOptions
                        )
                    elseif variantData.asset_source == "rojo" then
                        if existingVariant and existingVariant:IsA("Model") then
                            logger:Info("Using Rojo-managed pet model", {
                                petType = petType,
                                variant = variant,
                                path = existingVariant:GetFullName(),
                            })
                            self:SetPreferredPrimaryPart(existingVariant)
                            existingVariant:PivotTo(CFrame.identity)
                            self:ApplyConfiguredModelTransform(existingVariant, transformOptions)
                            self:WeldModelParts(existingVariant)
                            self:NormalizePetModelParts(existingVariant)
                            self:AddPetSystemComponents(existingVariant)
                            modelSuccess = true
                        else
                            logger:Warn("Rojo-managed pet model missing", {
                                petType = petType,
                                variant = variant,
                                expectedPath = petTypeFolder:GetFullName() .. "." .. variant,
                            })
                            modelSuccess = false
                        end
                    else
                        -- Replace existing variant model to avoid duplicates
                        if existingVariant then
                            existingVariant:Destroy()
                        end
                        -- Load 3D model
                        modelSuccess = self:LoadModelIntoFolder(
                            variantData.asset_id,
                            petTypeFolder,
                            variant,
                            petType .. "_" .. variant,
                            transformOptions
                        )
                    end

                    if modelSuccess then
                        modelSuccessCount = modelSuccessCount + 1

                        -- Inject per-variant stats (power/health/type/variant) for runtime use
                        do
                            local variantModel = petTypeFolder:FindFirstChild(variant)
                            if variantModel then
                                local resolvedPetData = petConfig.getPet
                                    and petConfig.getPet(petType, variant)
                                local powerValue = (resolvedPetData and resolvedPetData.power)
                                    or petData.base_power
                                    or 1
                                local healthValue = (resolvedPetData and resolvedPetData.health)
                                    or petData.base_health
                                    or 100
                                -- Set as attributes for quick access and clone carryover
                                variantModel:SetAttribute("PetType", petType)
                                variantModel:SetAttribute("Variant", variant)
                                variantModel:SetAttribute("Power", powerValue)
                                variantModel:SetAttribute("BaseHealth", healthValue)
                                self:ApplyPetTransformAttributes(variantModel, transformOptions)
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
                        imageFailureCount = imageFailureCount + 1 -- Can't generate image without model
                    end
                else
                    logger:Warn("Pet has no valid asset ID", {
                        petType = petType,
                        variant = variant,
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

        local hasEggMesh = type(eggData.mesh_asset) == "string"
            and eggData.mesh_asset ~= ""
            and eggData.mesh_asset ~= "rbxassetid://0"
        local hasEggModel = eggData.asset_id and eggData.asset_id ~= "rbxassetid://0"

        if hasEggMesh or hasEggModel then
            -- Replace existing egg model to avoid duplicates
            local existingEgg = eggsFolder:FindFirstChild(eggType)
            if existingEgg then
                existingEgg:Destroy()
            end

            local modelSuccess
            if hasEggMesh then
                -- THE single combine path: FBX->Model egg uploads import untextured (grey), so an
                -- egg ships mesh_asset (+ texture_asset) and we build the textured Model here, the
                -- same way pets/enemies/gems do, then store it in Assets.Models.Eggs like any model.
                local eggModel = MeshAssembly.build(
                    eggData.mesh_asset,
                    eggData.texture_asset,
                    { modelName = eggType }
                )
                if eggModel then
                    eggModel.Parent = eggsFolder
                    modelSuccess = true
                else
                    logger:Warn("Egg mesh combine failed; trying asset_id", { eggType = eggType })
                end
            end
            if not modelSuccess and hasEggModel then
                -- Fallback: packaged Model (may be untextured for FBX uploads).
                modelSuccess = self:LoadModelIntoFolder(
                    eggData.asset_id,
                    eggsFolder,
                    eggType,
                    eggType .. "_egg"
                )
            end

            if modelSuccess then
                modelSuccessCount = modelSuccessCount + 1

                -- Generate image from the loaded egg model (same as pets)
                local imageSuccess = self:GenerateImageFromModel(
                    eggsFolder:FindFirstChild(eggType),
                    eggImagesFolder,
                    eggType,
                    eggType, -- petType parameter (for eggs, use eggType)
                    "egg" -- variant parameter (all eggs are "egg" variant)
                )

                if imageSuccess then
                    imageSuccessCount = imageSuccessCount + 1
                else
                    imageFailureCount = imageFailureCount + 1
                end
            else
                modelFailureCount = modelFailureCount + 1
                imageFailureCount = imageFailureCount + 1 -- Can't generate image without model
            end
        else
            logger:Warn("Egg has no valid asset ID", {
                eggType = eggType,
            })
            modelFailureCount = modelFailureCount + 1
            imageFailureCount = imageFailureCount + 1
        end
    end

    logger:Info("Asset loading completed", {
        models = {
            successful = modelSuccessCount,
            failed = modelFailureCount,
        },
        images = {
            successful = imageSuccessCount,
            failed = imageFailureCount,
        },
        total = totalAssets,
        duration = tick() - startTime,
    })

    ReplicatedStorage.Assets:SetAttribute("PetThumbnailsReady", true)
    ReplicatedStorage.Assets:SetAttribute("PetThumbnailCount", imageSuccessCount)
    ReplicatedStorage.Assets:SetAttribute("PetThumbnailFailures", imageFailureCount)

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
            if soundData.volume then
                s.Volume = soundData.volume
            end
            if soundData.playback_speed then
                s.PlaybackSpeed = soundData.playback_speed
            end
            s.Parent = soundsFolder
            count += 1
        end
    end
    logger:Info("🔊 LoadAllSoundsIntoAssets: Completed", { count = count })
end

-- Load a single model into a folder
-- Build a textured pet model from a separately-uploaded MESH + TEXTURE — the same combine enemies
-- and gems use (AssetService:CreateMeshPartAsync + MeshPart.TextureID = imageId). FBX->Model uploads
-- come out untextured, so meshy pets ship `mesh_asset` (+ optional `texture_asset`) instead of a
-- packaged `asset_id` Model. Parents a Model (named folderName, PrimaryPart = the mesh) into
-- parentFolder and runs the SAME pet post-processing as LoadModelIntoFolder. Returns true on success.
function AssetPreloadService:BuildMeshPartModelIntoFolder(
    meshId,
    textureId,
    parentFolder,
    folderName,
    debugName,
    options
)
    if not meshId or not parentFolder then
        return false
    end

    local success, result = pcall(function()
        -- THE single combine path (shared with enemies/gems/eggs): mesh + texture -> textured Model.
        local modelClone = MeshAssembly.build(meshId, textureId, { modelName = folderName })
        if not modelClone then
            error("MeshAssembly.build returned nil for " .. tostring(meshId))
        end

        -- Identical post-processing to LoadModelIntoFolder so meshy pets behave the same.
        self:SetPreferredPrimaryPart(modelClone)
        modelClone:PivotTo(CFrame.identity)
        self:ApplyConfiguredModelTransform(modelClone, options)
        self:WeldModelParts(modelClone)

        local isPetFolder = (parentFolder.Name == "Pets")
            or (parentFolder.Parent and parentFolder.Parent.Name == "Pets")
        if isPetFolder then
            self:NormalizePetModelParts(modelClone)
            self:AddPetSystemComponents(modelClone)
        end

        modelClone.Parent = parentFolder
        return true
    end)

    if not success then
        logger:Warn("Failed to build mesh-combine pet model", {
            meshId = tostring(meshId),
            textureId = tostring(textureId),
            debugName = debugName,
            error = tostring(result),
        })
        return false
    end

    logger:Info("✅ BuildMeshPartModelIntoFolder: textured pet model built", {
        meshId = tostring(meshId),
        debugName = debugName,
        path = parentFolder:GetFullName() .. "." .. tostring(folderName),
    })
    return true
end

function AssetPreloadService:LoadModelIntoFolder(
    assetId,
    parentFolder,
    folderName,
    debugName,
    options
)
    logger:Info("🔄 LoadModelIntoFolder: Starting", {
        assetId = assetId,
        debugName = debugName,
        targetFolder = folderName,
        parentFolder = parentFolder and parentFolder.Name or "nil",
    })

    local cleanId = assetId:match("%d+")
    if not cleanId then
        logger:Error("❌ LoadModelIntoFolder: Invalid asset ID format", {
            assetId = assetId,
            debugName = debugName,
        })
        return false
    end

    logger:Info("🔄 LoadModelIntoFolder: Clean ID extracted", {
        cleanId = cleanId,
        assetId = assetId,
    })

    local success, result = pcall(function()
        logger:Info("🔄 LoadModelIntoFolder: Loading asset via InsertService", {
            cleanId = cleanId,
        })

        local loadedAsset = AssetFetch.load(tonumber(cleanId))
        if not loadedAsset then
            error("Failed to load asset: " .. cleanId)
        end

        logger:Info("✅ LoadModelIntoFolder: Asset loaded successfully", {
            cleanId = cleanId,
            loadedAssetExists = loadedAsset ~= nil,
        })

        local model = loadedAsset:FindFirstChildOfClass("Model")
        if not model then
            -- Some uploads are a bare MeshPart/part (mesh-only asset, like the enemy meshes)
            -- rather than a packaged Model. Wrap the first BasePart in a Model so mesh-based pets
            -- and eggs load instead of failing. Errors only if there's no usable part at all.
            local part = loadedAsset:FindFirstChildWhichIsA("BasePart", true)
            if part then
                local wrap = Instance.new("Model")
                wrap.Name = folderName or "WrappedMesh"
                part.Parent = wrap
                wrap.PrimaryPart = part
                wrap.Parent = loadedAsset
                model = wrap
                logger:Info("🔧 LoadModelIntoFolder: wrapped a bare MeshPart in a Model", {
                    cleanId = cleanId,
                    partClass = part.ClassName,
                })
            end
        end
        if not model then
            error("No Model or MeshPart found in asset: " .. cleanId)
        end

        logger:Info("✅ LoadModelIntoFolder: Model found in asset", {
            modelName = model.Name,
            modelType = model.ClassName,
        })

        -- Clone and organize the model
        local modelClone = model:Clone()
        modelClone.Name = folderName

        logger:Info("✅ LoadModelIntoFolder: Model cloned", {
            originalName = model.Name,
            newName = modelClone.Name,
        })

        -- Choose a stable PrimaryPart and pivot model to origin before welding
        self:SetPreferredPrimaryPart(modelClone)
        modelClone:PivotTo(CFrame.identity)

        self:ApplyConfiguredModelTransform(modelClone, options)

        -- Weld all parts together to prevent falling apart
        logger:Info("🔧 LoadModelIntoFolder: Welding model parts...")
        self:WeldModelParts(modelClone)

        -- If this is a pet model, add all the required pet system components
        local isPetFolder = false
        if parentFolder then
            -- We are called with parentFolder either being `Pets` or a child of it (pet type folder)
            isPetFolder = (parentFolder.Name == "Pets")
                or (parentFolder.Parent and parentFolder.Parent.Name == "Pets")
        end
        if isPetFolder then
            self:NormalizePetModelParts(modelClone)
            logger:Info("🔧 LoadModelIntoFolder: Adding pet system components...")
            self:AddPetSystemComponents(modelClone)
        end

        modelClone.Parent = parentFolder

        logger:Info("✅ LoadModelIntoFolder: Model parented to folder", {
            modelName = modelClone.Name,
            parentFolder = parentFolder.Name,
        })

        -- Clean up the original asset
        loadedAsset:Destroy()

        logger:Info("✅ LoadModelIntoFolder: Model successfully loaded into folder", {
            assetId = assetId,
            debugName = debugName,
            modelName = modelClone.Name,
            path = parentFolder:GetFullName() .. "." .. folderName,
        })

        return true
    end)

    if not success then
        logger:Warn("Failed to load model", {
            assetId = assetId,
            debugName = debugName,
            error = tostring(result),
        })
        return false
    end

    return true
end

-- Prefer Face/Head as PrimaryPart when available
function AssetPreloadService:SetPreferredPrimaryPart(model)
    if not model or not model:IsA("Model") then
        return
    end
    local chosen = model.PrimaryPart
    local firstPart = nil
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            firstPart = firstPart or d
            local n = string.lower(d.Name)
            if string.find(n, "face") or string.find(n, "head") then
                chosen = d
                break
            end
        end
    end
    chosen = chosen or firstPart
    if chosen then
        model.PrimaryPart = chosen
    end
end

-- Generate a ViewportFrame image from a loaded model (works for both pets and eggs)
function AssetPreloadService:GenerateImageFromModel(
    model,
    parentFolder,
    folderName,
    itemType,
    variant
)
    if not model or not model:IsA("Model") then
        logger:Warn("Invalid model for image generation", {
            itemType = itemType,
            variant = variant,
            modelExists = model ~= nil,
            modelType = model and model.ClassName or "nil",
        })
        return false
    end

    local success, result = pcall(function()
        -- Get camera configuration (works for both pets and eggs)
        local cameraConfig = self:GetCameraConfig(itemType)

        -- Position model for image capture - RESET BOTH POSITION AND ROTATION
        local modelClone = model:Clone()
        if petConfig.pets[itemType] then
            PetVariantVisuals.ApplyServerMetadata(modelClone, itemType, variant)
            PetVariantVisuals.ApplyStaticVisuals(modelClone)
        end
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
        local angleYRad = math.rad(cameraConfig.angle_y) -- Horizontal rotation (around Y-axis)
        local angleXRad = math.rad(cameraConfig.angle_x) -- Vertical rotation (elevation)

        -- Use spherical coordinates: distance, horizontal angle, vertical angle
        local cameraOffset = Vector3.new(
            math.sin(angleYRad) * math.cos(angleXRad) * cameraConfig.distance, -- X: affected by both angles
            math.sin(angleXRad) * cameraConfig.distance, -- Y: vertical elevation
            math.cos(angleYRad) * math.cos(angleXRad) * cameraConfig.distance -- Z: affected by both angles
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
        viewport.Size = UDim2.new(1, 0, 1, 0) -- Full size, will be scaled by UI
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
                offset = cameraConfig.offset,
            },
            calculatedPosition = cameraPosition,
            modelSize = modelSize,
            isEgg = petConfig.egg_sources[itemType] ~= nil,
        })

        return true
    end)

    if success then
        return true
    else
        logger:Error("Failed to generate image", {
            itemType = itemType,
            variant = variant,
            error = result,
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
        path = "ReplicatedStorage.Assets.Models.Pets." .. petType .. "." .. variant,
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
    if not assetsFolder then
        return nil
    end

    local imagesRoot = assetsFolder:FindFirstChild("Images")
    if not imagesRoot then
        return nil
    end

    local imagesFolder = imagesRoot:FindFirstChild("Pets")
    if not imagesFolder then
        return nil
    end

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
        path = "ReplicatedStorage.Assets.Images.Pets." .. petType .. "." .. variant,
    })

    return nil
end

-- Get egg image from ReplicatedStorage.Assets (for external access)
function AssetPreloadService:GetEggImageFromAssets(eggType)
    local imagesRoot = ReplicatedStorage.Assets:FindFirstChild("Images")
    if not imagesRoot then
        return nil
    end

    local eggImagesFolder = imagesRoot:FindFirstChild("Eggs")
    if not eggImagesFolder then
        return nil
    end

    local eggImage = eggImagesFolder:FindFirstChild(eggType)
    if eggImage then
        return eggImage:Clone()
    end

    logger:Warn("Egg image not found in assets", {
        eggType = eggType,
        path = "ReplicatedStorage.Assets.Images.Eggs." .. eggType,
    })

    return nil
end

-- Check if an image is available in assets
function AssetPreloadService:IsImageInAssets(petType, variant)
    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if not assetsFolder then
        return false
    end

    local imagesRoot = assetsFolder:FindFirstChild("Images")
    if not imagesRoot then
        return false
    end

    local imagesFolder = imagesRoot:FindFirstChild("Pets")
    if not imagesFolder then
        return false
    end

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
        folderPath = petsFolder:GetFullName(),
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
                userId = player.UserId,
            })
            return
        end

        logger:Info("Admin force regeneration triggered", {
            player = player.Name,
            userId = player.UserId,
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
            modelName = model.Name,
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
        weldsCreated = weldCount,
    })
end

-- Add all required pet system components to a pet model
function AssetPreloadService:AddPetSystemComponents(petModel)
    logger:Info("🔧 AddPetSystemComponents: Starting...", {
        modelExists = petModel ~= nil,
        modelType = petModel and petModel.ClassName or "nil",
        modelName = petModel and petModel.Name or "nil",
    })

    if not petModel or not petModel:IsA("Model") then
        logger:Error("❌ AddPetSystemComponents: Invalid pet model for component addition", {
            modelExists = petModel ~= nil,
            modelType = petModel and petModel.ClassName or "nil",
        })
        return
    end

    logger:Info("🔧 AddPetSystemComponents: Adding components to model", {
        modelName = petModel.Name,
    })

    -- 1. Create the values the service-owned pet system reads (PetFollowService /
    -- PetFollowController + EnemyService). The legacy follow Values (Pos/Refresh/Timer/AttackPos)
    -- and the `Follow` script are gone — that whole code path was deleted.
    local values = {
        { name = "TargetID", class = "NumberValue", value = 0 },
        { name = "PetID", class = "NumberValue", value = 0 },
        { name = "PetSize", class = "Vector3Value", value = Vector3.new(1, 1, 1) },
        { name = "PositionNumber", class = "NumberValue", value = 0 },
        { name = "TargetType", class = "StringValue", value = "" },
        { name = "TargetWorld", class = "StringValue", value = "" },
    }

    for _, valueData in pairs(values) do
        local value = petModel:FindFirstChild(valueData.name)
        if not value or not value:IsA(valueData.class) then
            if value then
                value:Destroy()
            end
            value = Instance.new(valueData.class)
            value.Name = valueData.name
            value.Parent = petModel
        end
        value.Value = valueData.value
    end

    -- 2. Strip any `Follow` script baked into the uploaded pet ASSET. The repo no longer
    -- contains, creates, or enables this legacy script anywhere — but it can ride along inside
    -- the LoadAsset'd pet model (the original game shipped it in the asset). LoadAsset content
    -- isn't in the repo, so the only way to keep it off spawned pets is to delete it on load.
    do
        local stale = petModel:FindFirstChild("Follow")
        while stale do
            stale:Destroy()
            stale = petModel:FindFirstChild("Follow")
        end
    end

    -- 3. Add attachmentPet to the pet model's PrimaryPart
    if petModel.PrimaryPart then
        local attachmentPet = petModel.PrimaryPart:FindFirstChild("attachmentPet")
        if not attachmentPet or not attachmentPet:IsA("Attachment") then
            if attachmentPet then
                attachmentPet:Destroy()
            end
            attachmentPet = Instance.new("Attachment")
            attachmentPet.Name = "attachmentPet"
            attachmentPet.Parent = petModel.PrimaryPart
        end
    end

    -- 4. Set initial pet size
    petModel.PetSize.Value = petModel:GetExtentsSize()

    logger:Info("✅ AddPetSystemComponents: Pet system components added to model", {
        modelName = petModel.Name,
        valuesCreated = #values,
        hasFollowScript = petModel:FindFirstChild("Follow") ~= nil,
        hasAttachmentPet = petModel.PrimaryPart
            and petModel.PrimaryPart:FindFirstChild("attachmentPet") ~= nil,
        totalChildren = #petModel:GetChildren(),
    })
end

return AssetPreloadService
