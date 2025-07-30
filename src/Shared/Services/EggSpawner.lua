--[[
    EggSpawner Service
    
    Handles dynamic egg spawning and management using asset IDs.
    Creates egg instances at specified spawn points based on configuration.
    
    Usage:
    - Place "EggSpawnPoint" parts in Workspace where eggs should appear
    - Use EggSpawner:SpawnEgg() to create eggs dynamically
    - Eggs are loaded from asset IDs in pet configuration
--]]

local EggSpawner = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local InsertService = game:GetService("InsertService")

-- Dependencies
local petConfig = require(ReplicatedStorage.Configs.pets)

-- Active eggs in the world
local activeEggs = {}

-- === EGG SPAWNING SYSTEM ===

-- Spawn an egg at a specific position
function EggSpawner:SpawnEgg(eggType, position, spawnPoint)
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        warn("Unknown egg type: " .. tostring(eggType))
        return nil
    end
    
    -- Get the egg model asset ID
    local assetId = eggData.egg_model_asset_id
    if not assetId or assetId == "rbxassetid://0" then
        warn("No asset ID configured for egg type: " .. eggType)
        return nil
    end
    
    -- Load the egg model from asset
    local success, eggModel = pcall(function()
        return InsertService:LoadAsset(tonumber(assetId:match("%d+")))
    end)
    
    if not success or not eggModel then
        warn("Failed to load egg asset: " .. assetId)
        return nil
    end
    
    -- Get the actual egg model (first Model child)
    local egg = eggModel:FindFirstChildOfClass("Model")
    if not egg then
        warn("Asset doesn't contain a Model: " .. assetId)
        eggModel:Destroy()
        return nil
    end
    
    -- Setup the egg
    egg.Name = eggData.name
    egg.Parent = workspace
    
    -- Position the egg
    if egg.PrimaryPart then
        egg:SetPrimaryPartCFrame(CFrame.new(position))
    elseif egg:FindFirstChild("Base") then
        egg.Base.CFrame = CFrame.new(position)
    end
    
    -- Add metadata
    local eggInfo = Instance.new("StringValue")
    eggInfo.Name = "EggType"
    eggInfo.Value = eggType
    eggInfo.Parent = egg
    
    local spawnPointRef = Instance.new("ObjectValue")
    spawnPointRef.Name = "SpawnPoint" 
    spawnPointRef.Value = spawnPoint
    spawnPointRef.Parent = egg
    
    print("EggSpawner: Spawned", eggData.name, "at", spawnPoint.Name, "position")
    
    -- Add to active eggs
    activeEggs[egg] = {
        eggType = eggType,
        spawnPoint = spawnPoint,
        spawnTime = tick(),
        eggData = eggData
    }
    
    -- Client will automatically detect this egg via distance-based system
    
    -- Spawn animation
    self:PlaySpawnAnimation(egg)
    
    -- Cleanup when destroyed
    egg.AncestryChanged:Connect(function()
        if not egg.Parent then
            activeEggs[egg] = nil
        end
    end)
    
    eggModel:Destroy() -- Clean up the asset container
    return egg
end

-- Legacy interaction system removed - now using EggInteractionService

-- Play spawn animation
function EggSpawner:PlaySpawnAnimation(egg)
    -- Start small and grow to normal size
    local originalSize = {}
    local parts = {}
    
    for _, part in pairs(egg:GetChildren()) do
        if part:IsA("BasePart") then
            table.insert(parts, part)
            originalSize[part] = part.Size
            part.Size = Vector3.new(0.1, 0.1, 0.1)
        end
    end
    
    -- Animate growth
    for _, part in pairs(parts) do
        local tween = TweenService:Create(
            part,
            TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = originalSize[part]}
        )
        tween:Play()
    end
end

-- === SPAWN POINT MANAGEMENT ===

-- Find all egg spawn points in workspace
function EggSpawner:GetSpawnPoints()
    local spawnPoints = {}
    
    -- Look for parts named "EggSpawnPoint" 
    local function searchForSpawnPoints(parent)
        for _, child in pairs(parent:GetChildren()) do
            if child:IsA("BasePart") and child.Name == "EggSpawnPoint" then
                table.insert(spawnPoints, child)
            end
            searchForSpawnPoints(child)
        end
    end
    
    searchForSpawnPoints(workspace)
    return spawnPoints
end

-- Spawn eggs at all available spawn points
function EggSpawner:PopulateSpawnPoints()
    local spawnPoints = self:GetSpawnPoints()
    
    for _, spawnPoint in pairs(spawnPoints) do
        -- Check if this spawn point has an egg type attribute
        local eggType = spawnPoint:GetAttribute("EggType") or "basic_egg"
        
        -- Only spawn if no egg is already there
        if not self:HasEggAtSpawnPoint(spawnPoint) then
            self:SpawnEgg(eggType, spawnPoint.Position + Vector3.new(0, 3, 0), spawnPoint)
        end
    end
end

-- Check if spawn point already has an egg
function EggSpawner:HasEggAtSpawnPoint(spawnPoint)
    for egg, info in pairs(activeEggs) do
        if info.spawnPoint == spawnPoint then
            return true
        end
    end
    return false
end

-- === UTILITY FUNCTIONS ===

-- Get all active eggs of a specific type
function EggSpawner:GetEggsByType(eggType)
    local eggs = {}
    for egg, info in pairs(activeEggs) do
        if info.eggType == eggType then
            table.insert(eggs, egg)
        end
    end
    return eggs
end

-- Remove an egg (for when it's purchased/hatched)
function EggSpawner:RemoveEgg(egg)
    if activeEggs[egg] then
        activeEggs[egg] = nil
        egg:Destroy()
    end
end

-- Get egg information
function EggSpawner:GetEggInfo(egg)
    return activeEggs[egg]
end

-- Initialize the system
function EggSpawner:Initialize()
    print("EggSpawner: Initializing...")
    
    -- Check workspace first
    print("EggSpawner: Searching for spawn points...")
    local spawnPoints = self:GetSpawnPoints()
    print("EggSpawner: Found " .. #spawnPoints .. " spawn points")
    
    if #spawnPoints == 0 then
        print("EggSpawner: ⚠️ No EggSpawnPoint parts found in workspace!")
        print("EggSpawner: Create a part named 'EggSpawnPoint' and add 'EggType' attribute")
        return
    end
    
    -- Populate initial spawn points
    self:PopulateSpawnPoints()
    
    print("EggSpawner: Initialized with " .. #spawnPoints .. " spawn points")
end

return EggSpawner