--[[
    BreakableSpawner - Spawns breakable crystals into worlds

    Responsibilities:
    - Reads breakable config (configs/breakables.lua)
    - Uses preloaded assets in ReplicatedStorage.Assets.Models.Breakables.Crystals
    - Spawns crystals at world spawners up to world Max, tracks CurrentItems
    - Respawns when items are removed

    Notes:
    - Does NOT modify scripts inside the crystal models; spawns with parts anchored
    - Uses WorldBindingService map hooks when available, with legacy folder fallback
]]

local BreakableSpawner = {}
BreakableSpawner.__index = BreakableSpawner

-- Silence verbose debug prints (mining / health-bar chatter that fired on every click).
-- Warnings and errors still surface via warn(). Toggle for local debugging.
local __RAW_PRINT = print
local __PRINT_ENABLED = false
local function print(...)
    if __PRINT_ENABLED then
        __RAW_PRINT(...)
    end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

-- Injected services
local logger
local configLoader
local eventService
local worldBindingService
local petProgressionService

-- Local state
local breakablesConfig

-- Geometry helpers for crystal star ring
local function getPointOnCircle(radius, degrees)
    return Vector3.new(
        math.cos(math.rad(degrees)) * radius,
        2,
        math.sin(math.rad(degrees)) * radius
    )
end

local function updateStarScale(starPart, factor)
    if not starPart or not starPart:IsA("BasePart") then
        return
    end
    local baseRadius = starPart:GetAttribute("BaseRadius") or 10
    local pointCount = starPart:GetAttribute("PointCount") or 108
    local increment = 360 / pointCount
    -- Ease the shrink so it never collapses too small; keeps pets from interweaving
    local eased = math.pow(math.clamp(factor, 0, 1), 0.6)
    local minScale = 0.35
    local scale = math.max(minScale, eased)
    local radius = baseRadius * scale
    for i = 1, pointCount do
        local name = "StarPos" .. tostring(i)
        local attach = starPart:FindFirstChild(name)
        if attach and attach:IsA("Attachment") then
            attach.Position = getPointOnCircle(radius, increment * i)
        end
    end
end

local function createStarRing(parentModel, radius, pointCount)
    -- Create a simple anchor part above the crystal with attachments where pets can align
    if not parentModel or not parentModel.PrimaryPart then
        return
    end
    local star = Instance.new("Part")
    star.Name = "Star"
    star.Size = Vector3.new(1, 1, 1)
    star.Anchored = true
    star.CanCollide = false
    star.Transparency = 1
    star.CFrame = CFrame.new(
        parentModel.PrimaryPart.Position + Vector3.new(0, parentModel:GetExtentsSize().Y / 4, 0)
    )
    star.Parent = parentModel

    local count = tonumber(pointCount) or 108
    local increment = 360 / count
    star:SetAttribute("BaseRadius", radius)
    star:SetAttribute("PointCount", count)
    for i = 1, count do
        local attach = Instance.new("Attachment")
        attach.Name = "StarPos" .. tostring(i)
        attach.Position = getPointOnCircle(radius, increment * i)
        attach.Parent = star

        -- Create a small invisible box with an attachment named "Pet" for pets to align to
        local box = Instance.new("Part")
        box.Name = "StarBox" .. tostring(i)
        box.Size = Vector3.new(1, 1, 1)
        box.Anchored = false
        box.CanCollide = false
        box.Massless = true
        box.Transparency = 1
        box.Position = star.Position
        box.Parent = star

        local centerAttachment = Instance.new("Attachment")
        centerAttachment.Name = "Center"
        centerAttachment.Parent = box

        local petAttachment = Instance.new("Attachment")
        petAttachment.Name = "Pet"
        petAttachment.Parent = box

        local alignP = Instance.new("AlignPosition")
        alignP.Name = "AlignPosition"
        alignP.Attachment0 = centerAttachment
        alignP.Attachment1 = attach
        alignP.Responsiveness = 100
        alignP.RigidityEnabled = true
        alignP.MaxForce = 1e12
        alignP.Parent = box

        local alignO = Instance.new("AlignOrientation")
        alignO.Name = "AlignOrientation"
        alignO.Attachment0 = centerAttachment
        alignO.Attachment1 = attach
        alignO.Responsiveness = 100
        alignO.RigidityEnabled = true
        alignO.MaxTorque = 1e12
        alignO.Parent = box
    end

    -- Spin the ring smoothly around world Y-axis (ignore model tilt),
    -- accelerate and shrink continuously as HP drops with visual smoothing
    task.spawn(function()
        local angle = 0
        local baseSpeed = math.rad(120) -- faster base spin
        local hpVisual = 1 -- smoothed HP fraction [0..1]
        while star.Parent == parentModel and parentModel.Parent do
            local dt = RunService.Heartbeat:Wait()
            local pp = parentModel.PrimaryPart
            if not pp then
                break
            end
            local maxHp = tonumber(parentModel:GetAttribute("MaxHP")) or 0
            local hp = tonumber(parentModel:GetAttribute("HP")) or 0
            local fracTarget = (maxHp > 0) and math.clamp(hp / maxHp, 0, 1) or 1
            -- Exponential smoothing to avoid steps
            local response = math.clamp(12 * dt, 0, 1) -- faster response
            hpVisual = hpVisual + (fracTarget - hpVisual) * response
            -- Spin scale ramps up aggressively near death (easeOut)
            local speedScale = 1 + math.pow(1 - hpVisual, 1.5) * 6 -- up to 7x
            angle += baseSpeed * speedScale * dt
            -- Smooth upward rise toward the end
            local rise = 10 * (1 - hpVisual) * (1 - hpVisual)
            local yBase = parentModel:GetExtentsSize().Y / 4
            local base = CFrame.new(pp.Position + Vector3.new(0, yBase + rise, 0))
            star.CFrame = base * CFrame.Angles(0, angle, 0)
            -- Resize ring every frame for smoothness
            updateStarScale(star, hpVisual)
        end
    end)
    return star
end

local function getWorldConfig(worldName)
    return (breakablesConfig.worlds and breakablesConfig.worlds[worldName]) or {}
end

local function getSpawnSettings(worldName)
    local defaults = (breakablesConfig.defaults and breakablesConfig.defaults.spawn_settings) or {}
    local worldCfg = getWorldConfig(worldName)
    local worldSettings = worldCfg.spawn_settings or {}
    local settings = table.clone(defaults)
    for key, value in pairs(worldSettings) do
        settings[key] = value
    end
    return settings
end

local function getConfiguredPosition(value, fallback, surfaceY)
    if type(value) ~= "table" then
        return fallback
    end

    local x = tonumber(value.x or value.X) or fallback.X
    local y = tonumber(value.y or value.Y) or surfaceY or fallback.Y
    local z = tonumber(value.z or value.Z) or fallback.Z
    return Vector3.new(x, y, z)
end

local function horizontalDistance(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt((dx * dx) + (dz * dz))
end

local function randomPointInCircle(center, radius)
    if radius <= 0 then
        return center
    end

    local angle = math.random() * math.pi * 2
    local distance = math.sqrt(math.random()) * radius
    return center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function randomPointInSpawnerBounds(spawner, margin)
    local halfX = math.max(0, (spawner.Size.X * 0.5) - margin)
    local halfZ = math.max(0, (spawner.Size.Z * 0.5) - margin)
    local localX = (math.random() * 2 - 1) * halfX
    local localZ = (math.random() * 2 - 1) * halfZ
    return spawner.CFrame:PointToWorldSpace(Vector3.new(localX, 0, localZ))
end

local function randomPointInBalancedSpawnerCell(spawner, margin, cellSize, itemsFolder)
    local halfX = math.max(0, (spawner.Size.X * 0.5) - margin)
    local halfZ = math.max(0, (spawner.Size.Z * 0.5) - margin)
    if halfX <= 0 or halfZ <= 0 then
        return spawner.Position
    end

    local resolvedCellSize = math.max(8, tonumber(cellSize) or 36)
    local columns = math.max(1, math.floor((halfX * 2) / resolvedCellSize))
    local rows = math.max(1, math.floor((halfZ * 2) / resolvedCellSize))
    local cellWidth = (halfX * 2) / columns
    local cellDepth = (halfZ * 2) / rows

    local counts = {}
    for column = 1, columns do
        counts[column] = {}
        for row = 1, rows do
            counts[column][row] = 0
        end
    end

    if itemsFolder then
        for _, child in ipairs(itemsFolder:GetChildren()) do
            if child:IsA("Model") and child.PrimaryPart then
                local localPosition = spawner.CFrame:PointToObjectSpace(child.PrimaryPart.Position)
                if
                    localPosition.X >= -halfX
                    and localPosition.X <= halfX
                    and localPosition.Z >= -halfZ
                    and localPosition.Z <= halfZ
                then
                    local column = math.clamp(
                        math.floor((localPosition.X + halfX) / cellWidth) + 1,
                        1,
                        columns
                    )
                    local row =
                        math.clamp(math.floor((localPosition.Z + halfZ) / cellDepth) + 1, 1, rows)
                    counts[column][row] += 1
                end
            end
        end
    end

    local lowestCount = math.huge
    local cells = {}
    for column = 1, columns do
        for row = 1, rows do
            local count = counts[column][row]
            if count < lowestCount then
                lowestCount = count
                table.clear(cells)
            end
            if count == lowestCount then
                table.insert(cells, { column = column, row = row })
            end
        end
    end

    local cell = cells[math.random(1, #cells)]
    local minX = -halfX + ((cell.column - 1) * cellWidth)
    local maxX = minX + cellWidth
    local minZ = -halfZ + ((cell.row - 1) * cellDepth)
    local maxZ = minZ + cellDepth
    local localX = minX + (math.random() * (maxX - minX))
    local localZ = minZ + (math.random() * (maxZ - minZ))

    return spawner.CFrame:PointToWorldSpace(Vector3.new(localX, 0, localZ))
end

local function numberFromAttributeOrConfig(instance, attributeName, configValue, fallback)
    local attributeValue = instance:GetAttribute(attributeName)
    if attributeValue ~= nil then
        return tonumber(attributeValue) or fallback
    end
    return tonumber(configValue) or fallback
end

local function shouldSampleSpawnerSurface(spawner, placeCfg)
    local surfaceOnly = spawner:GetAttribute("SurfaceOnly")
    if surfaceOnly ~= nil then
        return surfaceOnly == true
    end

    local mode = placeCfg.surface_mode or placeCfg.spawn_surface_mode
    return mode == "surface" or mode == "spawner_surface" or mode == "raycast"
end

local function shouldBalanceSpawnerCells(spawner, placeCfg)
    local balanced = spawner:GetAttribute("BalancedCells")
    if balanced ~= nil then
        return balanced == true
    end

    local mode = placeCfg.distribution_mode or placeCfg.spawn_distribution
    return mode == "balanced_cells" or mode == "grid"
end

local function raycastSpawnerSurface(spawner, candidate, placeCfg)
    if not shouldSampleSpawnerSurface(spawner, placeCfg) then
        return candidate
    end

    local raycastHeight = numberFromAttributeOrConfig(
        spawner,
        "RaycastHeight",
        placeCfg.surface_raycast_height,
        math.max(80, spawner.Size.Y + 40)
    )
    local normalMinY =
        numberFromAttributeOrConfig(spawner, "NormalMinY", placeCfg.surface_normal_min_y, 0.75)
    local origin = Vector3.new(
        candidate.X,
        spawner.Position.Y + (spawner.Size.Y * 0.5) + raycastHeight,
        candidate.Z
    )

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { spawner }
    params.IgnoreWater = true

    local result = workspace:Raycast(origin, Vector3.new(0, -raycastHeight * 2, 0), params)
    if not result or result.Instance ~= spawner then
        return nil
    end
    if result.Normal.Y < normalMinY then
        return nil
    end

    return result.Position
end

local function isIgnoredSpawnObstacle(part, spawner)
    if not part or part == spawner then
        return true
    end
    if part:IsDescendantOf(spawner) then
        return true
    end
    if not part.CanQuery then
        return true
    end
    if part.Transparency >= 0.95 and not part.CanCollide then
        return true
    end
    if CollectionService:HasTag(part, "SpawnZone") and part.Transparency >= 0.95 then
        return true
    end
    local gameFolder = workspace:FindFirstChild("Game")
    if gameFolder and part:IsDescendantOf(gameFolder) then
        return true
    end
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character and part:IsDescendantOf(character) then
            return true
        end
    end
    return false
end

local function getSpawnClearanceMode(spawner, placeCfg)
    local mode = spawner:GetAttribute("ClearanceMode") or spawner:GetAttribute("ObstacleMode")
    if type(mode) == "string" and mode ~= "" then
        return string.lower(mode)
    end

    mode = placeCfg.clearance_mode or placeCfg.obstacle_mode
    if type(mode) == "string" and mode ~= "" then
        return string.lower(mode)
    end

    return "box"
end

local function hasBoxSpawnClearance(spawner, candidate, placeCfg, clearanceRadius)
    local clearanceHeight = numberFromAttributeOrConfig(
        spawner,
        "ClearanceHeight",
        placeCfg.spawn_clearance_height or placeCfg.clearance_height,
        10
    )
    local yOffset = numberFromAttributeOrConfig(
        spawner,
        "ClearanceYOffset",
        placeCfg.spawn_clearance_y_offset,
        clearanceHeight * 0.5
    )

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { spawner }
    params.MaxParts = 40

    local parts = workspace:GetPartBoundsInBox(
        CFrame.new(candidate + Vector3.new(0, yOffset, 0)),
        Vector3.new(clearanceRadius * 2, clearanceHeight, clearanceRadius * 2),
        params
    )

    for _, part in ipairs(parts) do
        if not isIgnoredSpawnObstacle(part, spawner) then
            return false
        end
    end

    return true
end

local function hasRaySampleSpawnClearance(spawner, candidate, placeCfg, clearanceRadius)
    local sampleCount = math.max(
        0,
        numberFromAttributeOrConfig(spawner, "RaySampleCount", placeCfg.ray_sample_count, 8)
    )
    local rayHeight = numberFromAttributeOrConfig(
        spawner,
        "ObstacleRaycastHeight",
        placeCfg.obstacle_raycast_height or placeCfg.clearance_raycast_height,
        18
    )
    local rayDepth = numberFromAttributeOrConfig(
        spawner,
        "ObstacleRaycastDepth",
        placeCfg.obstacle_raycast_depth or placeCfg.clearance_raycast_depth,
        1.5
    )
    local offsets = { Vector3.new(0, 0, 0) }
    if sampleCount > 0 and clearanceRadius > 0 then
        for i = 1, sampleCount do
            local angle = ((i - 1) / sampleCount) * math.pi * 2
            table.insert(
                offsets,
                Vector3.new(math.cos(angle) * clearanceRadius, 0, math.sin(angle) * clearanceRadius)
            )
        end
    end

    local filterDescendants = {}
    local gameFolder = workspace:FindFirstChild("Game")
    if gameFolder then
        table.insert(filterDescendants, gameFolder)
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(filterDescendants, player.Character)
        end
    end

    for _, offset in ipairs(offsets) do
        local origin = candidate + offset + Vector3.new(0, rayHeight, 0)
        local direction = Vector3.new(0, -(rayHeight + rayDepth), 0)
        local exclusions = table.clone(filterDescendants)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclusions
        params.IgnoreWater = true

        local foundSurface = false
        for _ = 1, 8 do
            local result = workspace:Raycast(origin, direction, params)
            if not result then
                break
            end

            local part = result.Instance
            if part == spawner or part:IsDescendantOf(spawner) then
                foundSurface = true
                break
            end

            if not isIgnoredSpawnObstacle(part, spawner) then
                return false
            end

            table.insert(exclusions, part)
            params.FilterDescendantsInstances = exclusions
        end

        if not foundSurface then
            return false
        end
    end

    return true
end

local function hasSpawnClearance(spawner, candidate, placeCfg)
    local clearanceRadius = numberFromAttributeOrConfig(
        spawner,
        "ClearanceRadius",
        placeCfg.spawn_clearance_radius or placeCfg.clearance_radius,
        0
    )
    if clearanceRadius <= 0 then
        return true
    end

    local mode = getSpawnClearanceMode(spawner, placeCfg)
    if mode == "ray_samples" or mode == "raycasts" or mode == "rays" then
        return hasRaySampleSpawnClearance(spawner, candidate, placeCfg, clearanceRadius)
    end

    return hasBoxSpawnClearance(spawner, candidate, placeCfg, clearanceRadius)
end

local function selectSpawnZone(zones)
    if type(zones) ~= "table" or #zones == 0 then
        return nil
    end

    local totalWeight = 0
    for _, zone in ipairs(zones) do
        totalWeight += tonumber(zone.weight or 1)
    end

    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, zone in ipairs(zones) do
        cumulative += tonumber(zone.weight or 1)
        if roll <= cumulative then
            return zone
        end
    end

    return zones[#zones]
end

local function ensureConfiguredFolderTree(gameFolder)
    local structure = breakablesConfig.structure or {}
    for sectionName, sectionConfig in pairs(structure.folders or {}) do
        local sectionFolder = gameFolder:FindFirstChild(sectionName)
        if not sectionFolder then
            sectionFolder = Instance.new("Folder")
            sectionFolder.Name = sectionName
            sectionFolder.Parent = gameFolder
        end

        for groupName in pairs(sectionConfig) do
            if not sectionFolder:FindFirstChild(groupName) then
                local groupFolder = Instance.new("Folder")
                groupFolder.Name = groupName
                groupFolder.Parent = sectionFolder
            end
        end
    end

    local breakablesFolder = gameFolder:FindFirstChild("Breakables")
    local crystalsFolder = breakablesFolder and breakablesFolder:FindFirstChild("Crystals")
    if crystalsFolder then
        for areaId in pairs(breakablesConfig.worlds or {}) do
            if not crystalsFolder:FindFirstChild(areaId) then
                local worldFolder = Instance.new("Folder")
                worldFolder.Name = areaId
                worldFolder.Parent = crystalsFolder
            end
        end
    end
end

function BreakableSpawner:Init()
    logger = self._modules.Logger
    configLoader = self._modules.ConfigLoader
    eventService = self._modules.EventService
    worldBindingService = self._modules.WorldBindingService
    petProgressionService = self._modules.PetProgressionService

    -- Load config (safe)
    local ok, cfg = pcall(function()
        return configLoader:LoadConfig("breakables")
    end)
    if not ok then
        logger:Warn("BreakableSpawner: No breakables config found", { error = tostring(cfg) })
        breakablesConfig = { crystals = {} }
    else
        breakablesConfig = cfg or { crystals = {} }
    end

    logger:Info("BreakableSpawner initialized", {
        crystalsDefined = (breakablesConfig.crystals and #breakablesConfig.crystals) or 0,
    })
end

function BreakableSpawner:Start()
    if worldBindingService and worldBindingService.AreaEntered then
        worldBindingService.AreaEntered:Connect(function(_, areaId)
            self:_fillAreaWorld(areaId)
        end)
    end

    task.spawn(function()
        self:_spawnLoop()
    end)

    -- Periodic top-up attempts in case assets arrive later or removals aren't caught
    task.spawn(function()
        while true do
            task.wait(5)
            local crystalsAssets = self._crystalsAssets
            if crystalsAssets then
                self:_fillAllWorlds(crystalsAssets)
            end
        end
    end)
end

function BreakableSpawner:_isWorldActive(worldName)
    if not worldBindingService or not worldBindingService.IsAreaActive then
        return true
    end

    return worldName == "Spawn" or worldBindingService:IsAreaActive(worldName)
end

function BreakableSpawner:_fillAreaWorld(areaId)
    if not self._crystalsAssets then
        return
    end

    local gameFolder = workspace:FindFirstChild("Game")
    local breakablesWorlds = gameFolder and gameFolder:FindFirstChild("Breakables")
    local crystalsWorlds = breakablesWorlds and breakablesWorlds:FindFirstChild("Crystals")
    local worldFolder = crystalsWorlds and crystalsWorlds:FindFirstChild(areaId)
    if worldFolder and worldFolder:IsA("Folder") then
        self:_fillWorld(worldFolder, self._crystalsAssets)
    end
end

function BreakableSpawner:_spawnLoop()
    -- Wait for assets folder
    local assets = ReplicatedStorage:WaitForChild("Assets", 10)
    if not assets then
        logger:Error("BreakableSpawner: Assets folder not found; aborting spawn loop")
        return
    end
    local models = assets:WaitForChild("Models", 10)
    if not models then
        return
    end
    local breakables = models:WaitForChild("Breakables", 30)
    if not breakables then
        logger:Error("BreakableSpawner: Assets.Models.Breakables missing; aborting")
        return
    end
    local crystalsAssets = breakables:WaitForChild("Crystals", 30)
    if not crystalsAssets then
        logger:Warn(
            "BreakableSpawner: Crystal assets folder missing after wait; will retry when assets load"
        )
        breakables.ChildAdded:Connect(function(child)
            if child.Name == "Crystals" and child:IsA("Folder") then
                self:_fillAllWorlds(child)
            end
        end)
    else
        local start = tick()
        while #crystalsAssets:GetChildren() == 0 and tick() - start < 30 do
            task.wait(0.5)
        end
        self._crystalsAssets = crystalsAssets
        if #crystalsAssets:GetChildren() == 0 then
            logger:Warn(
                "BreakableSpawner: Crystals folder has no children after waits; will keep retrying"
            )
        else
            local names = {}
            for _, child in ipairs(crystalsAssets:GetChildren()) do
                table.insert(names, child.Name)
            end
            logger:Info("BreakableSpawner: Crystal assets ready", { count = #names, names = names })
        end
    end

    -- Locate worlds structure
    local gameFolder = workspace:WaitForChild("Game", 10)
    if not gameFolder then
        logger:Error("BreakableSpawner: workspace.Game missing; cannot spawn")
        return
    end
    local breakablesWorlds = gameFolder:FindFirstChild("Breakables")
    if not breakablesWorlds then
        logger:Error("BreakableSpawner: workspace.Game.Breakables missing; cannot spawn")
        return
    end
    ensureConfiguredFolderTree(gameFolder)

    local crystalsWorlds = breakablesWorlds:FindFirstChild("Crystals")
    if not crystalsWorlds then
        logger:Error("BreakableSpawner: workspace.Game.Breakables.Crystals missing; cannot spawn")
        return
    end

    -- Attach listeners and do initial fill for each world
    for _, worldFolder in ipairs(crystalsWorlds:GetChildren()) do
        if worldFolder:IsA("Folder") then
            self:_setupWorld(worldFolder)
            if self:_isWorldActive(worldFolder.Name) then
                self:_fillWorld(worldFolder)
            end
        end
    end

    -- Watch for new worlds added dynamically
    crystalsWorlds.ChildAdded:Connect(function(child)
        if child:IsA("Folder") then
            self:_setupWorld(child)
            if self:_isWorldActive(child.Name) then
                self:_fillWorld(child)
            end
        end
    end)
end

function BreakableSpawner:_fillAllWorlds(crystalsAssets)
    local gameFolder = workspace:FindFirstChild("Game")
    if not gameFolder then
        return
    end
    local breakablesWorlds = gameFolder:FindFirstChild("Breakables")
    if not breakablesWorlds then
        return
    end
    local crystalsWorlds = breakablesWorlds:FindFirstChild("Crystals")
    if not crystalsWorlds then
        return
    end
    self._crystalsAssets = crystalsAssets
    for _, worldFolder in ipairs(crystalsWorlds:GetChildren()) do
        if worldFolder:IsA("Folder") and self:_isWorldActive(worldFolder.Name) then
            self:_fillWorld(worldFolder)
        end
    end
end

function BreakableSpawner:_setupWorld(worldFolder)
    local items = worldFolder:FindFirstChild("Items")
    if not items then
        items = Instance.new("Folder")
        items.Name = "Items"
        items.Parent = worldFolder
    end

    local current = worldFolder:FindFirstChild("CurrentItems")
    if not current then
        current = Instance.new("NumberValue")
        current.Name = "CurrentItems"
        current.Value = 0
        current.Parent = worldFolder
    end

    local max = worldFolder:FindFirstChild("Max")
    local worldConfig = getWorldConfig(worldFolder.Name)
    local defaultMax = (breakablesConfig.defaults and breakablesConfig.defaults.max_per_world) or 25
    local configuredMax = tonumber(worldConfig.max or defaultMax) or defaultMax
    if worldBindingService and worldBindingService.GetSpawnZonesForSpawner then
        local boundSpawners =
            worldBindingService:GetSpawnZonesForSpawner(worldFolder.Name, "spawn_crystals")
        for _, spawner in ipairs(boundSpawners or {}) do
            local override = tonumber(spawner:GetAttribute("MaxCountOverride"))
            if override then
                configuredMax = override
                break
            end
        end
    end
    if not max then
        max = Instance.new("NumberValue")
        max.Name = "Max"
        max.Parent = worldFolder
    end
    max.Value = configuredMax

    -- Maintain count when items removed
    items.ChildRemoved:Connect(function()
        task.defer(function()
            local c = current.Value
            if c > 0 then
                current.Value = c - 1
            end
            local placeCfg = getSpawnSettings(worldFolder.Name)
            local minDelay = tonumber(placeCfg.respawn_min_seconds or 5)
            local maxDelay = tonumber(placeCfg.respawn_max_seconds or 60)
            local delaySec = math.random(minDelay, maxDelay)
            task.delay(delaySec, function()
                self:_trySpawnOne(worldFolder)
            end)
        end)
    end)
end

function BreakableSpawner:_fillWorld(worldFolder)
    if not self:_isWorldActive(worldFolder.Name) then
        return
    end

    local current = worldFolder:FindFirstChild("CurrentItems")
    local max = worldFolder:FindFirstChild("Max")
    if not (current and max) then
        return
    end
    local deficit = math.max(0, (max.Value or 0) - (current.Value or 0))
    for _ = 1, deficit do
        self:_trySpawnOne(worldFolder)
    end
end

function BreakableSpawner:_selectCrystalSpawn(worldName)
    -- Prefer per-world weighted spawn table if provided
    local worldCfg = breakablesConfig.worlds and breakablesConfig.worlds[worldName]
    local tableCfg = worldCfg and worldCfg.spawn_table
    if type(tableCfg) == "table" and #tableCfg > 0 then
        local total = 0
        for _, e in ipairs(tableCfg) do
            total += tonumber(e.weight or 1)
        end
        local roll = math.random() * total
        local acc = 0
        for _, e in ipairs(tableCfg) do
            acc += tonumber(e.weight or 1)
            if roll <= acc then
                return e.name, e
            end
        end
    end

    -- Fallback: uniform selection across defined crystals
    local names = {}
    for name, data in pairs(breakablesConfig.crystals or {}) do
        if type(data) == "table" and data.asset_id then
            table.insert(names, name)
        end
    end
    if #names == 0 then
        return nil
    end
    local idx = math.random(1, #names)
    return names[idx], nil
end

function BreakableSpawner:_getSpawnerParts(worldFolder)
    if worldBindingService and worldBindingService.GetSpawnZonesForSpawner then
        local boundSpawners =
            worldBindingService:GetSpawnZonesForSpawner(worldFolder.Name, "spawn_crystals")
        if type(boundSpawners) == "table" and #boundSpawners > 0 then
            return boundSpawners
        end
    end

    local spawners = {}
    for _, child in ipairs(worldFolder:GetChildren()) do
        if
            child:IsA("BasePart")
            and (
                child.Name == "SpawnArea"
                or child.Name == "CrystalSpawnArea"
                or child.Name == "Spawner"
                or child.Name == "DarkSpawner"
                or child.Name:find("Spawner")
            )
        then
            table.insert(spawners, child)
        end
    end
    return spawners
end

-- Find a placement point inside a spawner's configured area.
function BreakableSpawner:_findSpawnPoint(worldFolder)
    local itemsFolder = worldFolder:FindFirstChild("Items")
    local spawners = self:_getSpawnerParts(worldFolder)
    if #spawners == 0 then
        return nil, nil
    end

    -- Shuffle spawners to distribute load
    for i = #spawners, 2, -1 do
        local j = math.random(1, i)
        spawners[i], spawners[j] = spawners[j], spawners[i]
    end

    local placeCfg = getSpawnSettings(worldFolder.Name)
    local defaultMinDistance = tonumber(placeCfg.min_distance or 12)
    local spawnRadius = tonumber(placeCfg.spawn_radius or 0)
    local spawnAttempts = math.max(1, tonumber(placeCfg.spawn_attempts or 12))
    local surfaceY = tonumber(placeCfg.surface_y)
    local exclusionRadius = tonumber(placeCfg.spawn_exclusion_radius or 0)
    local zones = type(placeCfg.spawn_zones) == "table" and placeCfg.spawn_zones or nil
    local useSpawnerBounds = placeCfg.use_spawner_bounds ~= false
    local spawnerMargin = tonumber(placeCfg.spawn_area_margin or 0)

    for _, spawner in ipairs(spawners) do
        local currentSpawnerMargin = numberFromAttributeOrConfig(
            spawner,
            "SpawnAreaMargin",
            placeCfg.spawn_area_margin,
            spawnerMargin
        )
        local currentSpawnAttempts = math.max(
            1,
            numberFromAttributeOrConfig(
                spawner,
                "SpawnAttempts",
                placeCfg.spawn_attempts,
                spawnAttempts
            )
        )
        local currentMinDistance = numberFromAttributeOrConfig(
            spawner,
            "MinDistance",
            placeCfg.min_distance,
            defaultMinDistance
        )
        local spawnerPosition = spawner.Position
        if surfaceY then
            spawnerPosition = Vector3.new(spawner.Position.X, surfaceY, spawner.Position.Z)
        end

        local spawnCenter = getConfiguredPosition(placeCfg.spawn_center, spawnerPosition, surfaceY)
        local exclusionCenter =
            getConfiguredPosition(placeCfg.spawn_exclusion_center, spawnCenter, surfaceY)

        for _ = 1, currentSpawnAttempts do
            local zone = selectSpawnZone(zones)
            local zoneCenter = spawnCenter
            local zoneRadius = spawnRadius
            if zone then
                zoneCenter = getConfiguredPosition(zone.center, spawnCenter, surfaceY)
                zoneRadius = tonumber(zone.radius or spawnRadius)
            end

            local hasAreaBounds = useSpawnerBounds
                and not zone
                and (spawner.Size.X > 1 or spawner.Size.Z > 1)
            local candidate
            if hasAreaBounds and shouldBalanceSpawnerCells(spawner, placeCfg) then
                local cellSize =
                    numberFromAttributeOrConfig(spawner, "CellSize", placeCfg.cell_size, 36)
                candidate = randomPointInBalancedSpawnerCell(
                    spawner,
                    currentSpawnerMargin,
                    cellSize,
                    itemsFolder
                )
            elseif hasAreaBounds then
                candidate = randomPointInSpawnerBounds(spawner, currentSpawnerMargin)
            else
                candidate = randomPointInCircle(zoneCenter, zoneRadius)
            end
            if shouldSampleSpawnerSurface(spawner, placeCfg) then
                candidate = raycastSpawnerSurface(spawner, candidate, placeCfg)
                if not candidate then
                    continue
                end
            elseif surfaceY then
                candidate = Vector3.new(candidate.X, surfaceY, candidate.Z)
            end

            local insideExclusion = exclusionRadius > 0
                and horizontalDistance(candidate, exclusionCenter) < exclusionRadius
            local tooClose = insideExclusion

            if not tooClose and itemsFolder then
                for _, child in ipairs(itemsFolder:GetChildren()) do
                    if child:IsA("Model") and child.PrimaryPart then
                        if
                            horizontalDistance(child.PrimaryPart.Position, candidate)
                            < currentMinDistance
                        then
                            tooClose = true
                            break
                        end
                    end
                end
            end

            if not tooClose and not hasSpawnClearance(spawner, candidate, placeCfg) then
                tooClose = true
            end

            if not tooClose then
                return spawner, candidate
            end
        end
    end
    return nil, nil
end

function BreakableSpawner:_trySpawnOne(
    worldFolder,
    forcedCrystalName,
    forcedSpawnOverrides,
    ignoreMax
)
    if not self:_isWorldActive(worldFolder.Name) then
        return
    end

    local current = worldFolder:FindFirstChild("CurrentItems")
    local max = worldFolder:FindFirstChild("Max")
    if not (current and max) then
        return
    end
    if not ignoreMax and current.Value >= max.Value then
        return
    end

    local crystalsAssets = self._crystalsAssets
    if not crystalsAssets then
        -- As a fallback, attempt to locate now
        local assetsRoot = ReplicatedStorage:FindFirstChild("Assets")
        local modelsRoot = assetsRoot and assetsRoot:FindFirstChild("Models")
        local breakablesRoot = modelsRoot and modelsRoot:FindFirstChild("Breakables")
        crystalsAssets = breakablesRoot and breakablesRoot:FindFirstChild("Crystals")
        if crystalsAssets then
            self._crystalsAssets = crystalsAssets
            -- Wait until children exist
            local start = tick()
            while #crystalsAssets:GetChildren() == 0 and tick() - start < 30 do
                task.wait(0.5)
            end
        else
            return
        end
    end

    if #crystalsAssets:GetChildren() == 0 then
        return
    end

    local crystalName, spawnOverrides = forcedCrystalName, forcedSpawnOverrides
    if not crystalName then
        crystalName, spawnOverrides = self:_selectCrystalSpawn(worldFolder.Name)
    end
    if not crystalName then
        logger:Warn("BreakableSpawner: No crystals available to spawn")
        return
    end

    local assetModel = crystalsAssets:FindFirstChild(crystalName)
    if not assetModel or not assetModel:IsA("Model") then
        local present = {}
        for _, child in ipairs(crystalsAssets:GetChildren()) do
            table.insert(present, child.Name)
        end
        logger:Warn(
            "BreakableSpawner: Crystal asset missing",
            { name = crystalName, available = present }
        )
        return
    end

    local spawner, spawnPosition = self:_findSpawnPoint(worldFolder)
    if not spawner then
        logger:Warn("BreakableSpawner: No spawner parts in world", { world = worldFolder.Name })
        return
    end

    -- Clone and prepare model
    local model = assetModel:Clone()
    model.Name = crystalName

    local crystalCfg = breakablesConfig.crystals and breakablesConfig.crystals[crystalName]
    local crystalPlacement = (type(crystalCfg) == "table" and type(crystalCfg.placement) == "table")
            and table.clone(crystalCfg.placement)
        or {}
    if type(spawnOverrides) == "table" and type(spawnOverrides.placement) == "table" then
        for key, value in pairs(spawnOverrides.placement) do
            crystalPlacement[key] = value
        end
    end

    local function resolveStat(key, fallback)
        if type(spawnOverrides) == "table" and spawnOverrides[key] ~= nil then
            return spawnOverrides[key]
        end
        if type(crystalCfg) == "table" and crystalCfg[key] ~= nil then
            return crystalCfg[key]
        end
        return fallback
    end

    local scale = tonumber(resolveStat("scale", 1)) or 1
    if scale > 0 and scale ~= 1 then
        pcall(function()
            model:ScaleTo(scale)
        end)
    end

    local physicsCfg = (type(crystalCfg) == "table" and type(crystalCfg.physics) == "table")
            and crystalCfg.physics
        or {}

    -- Anchor all parts so breakables stay in place; per-breakable config can tune collision/query.
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            if physicsCfg.anchored ~= nil then
                d.Anchored = physicsCfg.anchored == true
            else
                d.Anchored = true
            end
            if physicsCfg.can_collide ~= nil then
                d.CanCollide = physicsCfg.can_collide == true
            end
            if physicsCfg.can_touch ~= nil then
                d.CanTouch = physicsCfg.can_touch == true
            end
            if physicsCfg.can_query ~= nil then
                d.CanQuery = physicsCfg.can_query == true
            end
        end
    end

    -- Determine placement/orientation settings
    local placeCfg = getSpawnSettings(worldFolder.Name)
    local sinkDepth = tonumber(crystalPlacement.sink_depth or placeCfg.sink_depth or 0)
    local surfaceY = tonumber(placeCfg.surface_y)

    -- Orientation: preserve model's default pitch/roll from assets, add random yaw
    local yaw = math.rad(math.random(0, 359))
    local basePosition = spawnPosition or spawner.Position
    local targetCFrame
    if placeCfg.upright then
        -- Keep the model's asset orientation (pitch/roll), only randomize yaw around world Y
        local pivot = model:GetPivot()
        local orientOnly = pivot - pivot.Position
        targetCFrame = CFrame.new(basePosition) * CFrame.Angles(0, yaw, 0) * orientOnly
    else
        -- Free rotation: yaw only
        targetCFrame = CFrame.new(basePosition) * CFrame.Angles(0, yaw, 0)
    end
    pcall(function()
        model:PivotTo(targetCFrame)
    end)

    -- Align by bounding box so assets with odd pivots still sit/sink consistently.
    local boundsCFrame, boundsSize = model:GetBoundingBox()
    local embed = math.clamp(tonumber(placeCfg.embed_ratio or 0.25), 0, 0.9)
    local totalSink = (boundsSize.Y * embed) + sinkDepth
    local floorY = surfaceY or basePosition.Y
    local currentBottomY = boundsCFrame.Position.Y - (boundsSize.Y * 0.5)
    local targetBottomY = floorY - totalSink
    local yDelta = targetBottomY - currentBottomY
    if math.abs(yDelta) > 0.001 then
        pcall(function()
            model:PivotTo(model:GetPivot() + Vector3.new(0, yDelta, 0))
        end)
    end

    -- Simple de-overlap: if another crystal is too close, nudge sideways (up to few tries)
    local minDist = numberFromAttributeOrConfig(spawner, "MinDistance", placeCfg.min_distance, 12)
    local itemsFolder = worldFolder:FindFirstChild("Items")
    local tries = 0
    while tries < 4 and itemsFolder do
        local tooClose = false
        for _, other in ipairs(itemsFolder:GetChildren()) do
            if
                other:IsA("Model")
                and other ~= model
                and other.PrimaryPart
                and model.PrimaryPart
            then
                local d = (other.PrimaryPart.Position - model.PrimaryPart.Position).Magnitude
                if d < minDist then
                    tooClose = true
                    break
                end
            end
        end
        if tooClose then
            tries += 1
            local angle = math.rad(math.random(0, 359))
            local step = minDist * 0.75
            pcall(function()
                model:PivotTo(
                    model:GetPivot() * CFrame.new(math.cos(angle) * step, 0, math.sin(angle) * step)
                )
            end)
        else
            break
        end
    end

    local finalPivot = model:GetPivot()
    local dropFromHeight = tonumber(
        crystalPlacement.drop_from_height or placeCfg.drop_from_height or 0
    ) or 0
    local dropDuration = tonumber(crystalPlacement.drop_duration or placeCfg.drop_duration or 0.6)
        or 0.6
    if dropFromHeight > 0 then
        model:PivotTo(finalPivot + Vector3.new(0, dropFromHeight, 0))
    end

    -- Optional attributes for downstream logic (mirrors MCP fields)
    model:SetAttribute("BreakableType", "Crystal")
    model:SetAttribute("CrystalName", crystalName)
    model:SetAttribute("World", worldFolder.Name)

    -- Set gameplay attributes if present in config
    if type(crystalCfg) == "table" then
        local maxhp = tonumber(resolveStat("health", 0)) or 0
        local value = tonumber(resolveStat("value", 0)) or 0
        model:SetAttribute("MaxHP", maxhp)
        model:SetAttribute("HP", maxhp)
        model:SetAttribute("Value", value)
        model:SetAttribute("Currency", tostring(resolveStat("currency", "crystals")))
        model:SetAttribute("Scale", scale)
        model:SetAttribute("Boost", 0)
        model:SetAttribute("MaxBoost", 100)
    end

    -- Unique breakable ID (for targeting). Using random large int similar to MCP
    local idValue = Instance.new("NumberValue")
    idValue.Name = "BreakableID"
    idValue.Value = math.random(2, 2 ^ 30) + math.random(2, 2 ^ 30)
    idValue.Parent = model

    -- Contribution tracking (per-player damage)
    local contribFolder = Instance.new("Folder")
    contribFolder.Name = "Contrib"
    contribFolder.Parent = model

    -- Bind health bar UI (if present in model)
    -- Match MCP: find any descendant BillboardGui with a child Frame named 'Health'
    local healthFrames = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BillboardGui") then
            d.MaxDistance = 75
            local hf = d:FindFirstChild("Health")
            if hf and hf:IsA("Frame") then
                table.insert(healthFrames, hf)
            end
        end
    end
    local function repopulateHealthFrames()
        table.clear(healthFrames)
        -- Deep scan all descendants; handle multiple nested Billboards
        print("[HB] scanning model:", model:GetFullName())
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BillboardGui") then
                d.MaxDistance = 75
                print("[HB] BillboardGui:", d:GetFullName())
                local hf = d:FindFirstChild("Health")
                if hf then
                    print("[HB] direct Health found:", hf:GetFullName())
                else
                    -- Some rigs put the Health under a container frame
                    local container = d:FindFirstChildWhichIsA("Frame")
                    if container then
                        print("[HB] container frame:", container:GetFullName())
                        hf = container:FindFirstChild("Health")
                        if hf then
                            print("[HB] container Health found:", hf:GetFullName())
                        end
                    end
                end
                if hf and (hf:IsA("Frame") or hf:IsA("ImageLabel") or hf:IsA("TextLabel")) then
                    table.insert(healthFrames, hf)
                    print("[HB] added Health frame; total=", #healthFrames)
                end
            end
        end
        print("[HB] repopulate done; total healthFrames=", #healthFrames)
    end

    local function updateHealthBar()
        if #healthFrames == 0 then
            repopulateHealthFrames()
        end
        print("updateHealthBar", #healthFrames)
        if #healthFrames == 0 then
            return
        end
        local maxHp = tonumber(model:GetAttribute("MaxHP")) or 0
        local hp = tonumber(model:GetAttribute("HP")) or 0
        print("updateHealthBar", maxHp, hp)
        if maxHp <= 0 then
            return
        end
        -- MCP behavior: width is percent [0..100] pixels, fixed height 10px
        local percentPx = math.max(0, math.floor((hp / maxHp) * 100))
        for _, frame in ipairs(healthFrames) do
            frame.Size = UDim2.new(0, percentPx, 0, 10)
        end
    end
    updateHealthBar()
    model:GetAttributeChangedSignal("HP"):Connect(function()
        updateHealthBar()
        local star = model:FindFirstChild("Star")
        if star then
            local maxHp = tonumber(model:GetAttribute("MaxHP")) or 0
            local hp = tonumber(model:GetAttribute("HP")) or 0
            if maxHp > 0 then
                local frac = math.clamp(hp / maxHp, 0, 1)
                updateStarScale(star, frac)
                star:SetAttribute("SpinSpeedScale", 1 + (1 - frac) * 1.5)
            end
        end
    end)

    -- Boost bar hookup
    local function updateBoostBar()
        local pp = model.PrimaryPart
        if not pp then
            return
        end
        local bbg = pp:FindFirstChild("BoostBillboardGui")
        if not bbg then
            return
        end
        local boostFrame = bbg:FindFirstChild("Boost")
        if not boostFrame then
            local container = bbg:FindFirstChildWhichIsA("Frame")
            boostFrame = container and container:FindFirstChild("Boost")
        end
        if not boostFrame then
            return
        end
        local b = tonumber(model:GetAttribute("Boost")) or 0
        local mb = tonumber(model:GetAttribute("MaxBoost")) or 100
        local percentPx = (mb > 0) and math.max(0, math.floor((b / mb) * 100)) or 0
        if boostFrame:IsA("GuiObject") then
            boostFrame.Size = UDim2.new(0, percentPx, 0, 10)
        end
    end
    updateBoostBar()
    model:GetAttributeChangedSignal("Boost"):Connect(updateBoostBar)

    -- Decay boost over time similar to MCP
    task.spawn(function()
        while model.Parent do
            task.wait(1)
            local b = tonumber(model:GetAttribute("Boost")) or 0
            if b > 0 then
                model:SetAttribute("Boost", math.max(0, b - 1))
            end
        end
    end)

    -- Add star ring for pet attack alignment when first pet arrives
    do
        local petsFolder = model:FindFirstChild("Pets")
        if not petsFolder then
            petsFolder = Instance.new("Folder")
            petsFolder.Name = "Pets"
            petsFolder.Parent = model
        end
        local teamBoost = model:FindFirstChild("TeamBoost")
        if not teamBoost then
            teamBoost = Instance.new("NumberValue")
            teamBoost.Name = "TeamBoost"
            teamBoost.Value = 0
            teamBoost.Parent = model
        end
        local efficiency = model:FindFirstChild("Efficiency")
        if not efficiency then
            efficiency = Instance.new("NumberValue")
            efficiency.Name = "Efficiency"
            efficiency.Value = 1
            efficiency.Parent = model
        end
        petsFolder.ChildAdded:Connect(function(child)
            -- Expect child is a NumberValue carrying PetID, with sub-values Leadership/Efficiency, mirroring MCP
            if not model:FindFirstChild("Star") then
                local radius = model:GetExtentsSize().X + 12
                createStarRing(model, radius, 108) -- >99 points for up to 99 pets
            end
            local lead = child:FindFirstChild("Leadership")
            if lead and typeof(lead.Value) == "number" then
                teamBoost.Value = teamBoost.Value + lead.Value
            end
            local eff = child:FindFirstChild("Efficiency")
            if eff and typeof(eff.Value) == "number" then
                efficiency.Value = efficiency.Value + eff.Value
            end
            -- Enable crystal SFX/UI when pets engage
            local pp = model.PrimaryPart
            if pp then
                local bb = pp:FindFirstChild("BillboardGui")
                if bb then
                    bb.MaxDistance = 75
                end
                local bbb = pp:FindFirstChild("BoostBillboardGui")
                if bbb then
                    bbb.MaxDistance = 75
                end
                local hum = pp:FindFirstChild("EngineHumSound")
                if hum and hum:IsA("Sound") then
                    hum:Play()
                end
                -- Play a soft engage sound if present
                local soft = pp:FindFirstChild("littleBreakSound")
                if soft and soft:IsA("Sound") then
                    if math.random(1, 3) == 1 then
                        soft:Play()
                    end
                end
            end
        end)
        petsFolder.ChildRemoved:Connect(function(child)
            local lead = child:FindFirstChild("Leadership")
            if lead and typeof(lead.Value) == "number" then
                teamBoost.Value = math.max(0, teamBoost.Value - lead.Value)
            end
            local eff = child:FindFirstChild("Efficiency")
            if eff and typeof(eff.Value) == "number" then
                efficiency.Value = math.max(1, efficiency.Value - eff.Value)
            end
            if #petsFolder:GetChildren() == 0 then
                local star = model:FindFirstChild("Star")
                if star then
                    star:Destroy()
                end
                local pp = model.PrimaryPart
                if pp then
                    local bb = pp:FindFirstChild("BillboardGui")
                    if bb then
                        bb.MaxDistance = 25
                    end
                    local bbb = pp:FindFirstChild("BoostBillboardGui")
                    if bbb then
                        bbb.MaxDistance = 1
                    end
                    local hum = pp:FindFirstChild("EngineHumSound")
                    if hum and hum:IsA("Sound") then
                        hum:Stop()
                    end
                    -- Optional soft stop cue
                    local soft = pp:FindFirstChild("littleBreakSound")
                    if soft and soft:IsA("Sound") then
                        if math.random(1, 5) == 1 then
                            soft:Play()
                        end
                    end
                end
            end
        end)
    end

    -- Award/destroy handler when HP reaches 0 from any source
    local function handleDeath()
        if not model.Parent then
            return
        end
        if model:GetAttribute("Dead") then
            return
        end
        model:SetAttribute("Dead", true)
        local stats = self._moduleLoader and self._moduleLoader:Get("StatsService")
        -- Compute awards based on contributions
        local currencyType = tostring(model:GetAttribute("Currency") or "coins")
        local valueAmount = tonumber(model:GetAttribute("Value") or 0)
        local economy = (self._moduleLoader and self._moduleLoader:Get("EconomyService"))
            or (self._modules and self._modules.EconomyService)

        local function resolvePlayerAward(player, baseAmount)
            baseAmount = tonumber(baseAmount) or 0
            if economy and economy.ResolveRewardAmount and baseAmount > 0 then
                local resolvedAmount = economy:ResolveRewardAmount(baseAmount, {
                    player = player,
                    kind = "breakable_reward",
                    currency = currencyType,
                    breakableId = model:GetAttribute("BreakableId"),
                    source = "BreakableSpawner",
                })
                return resolvedAmount
            elseif eventService and baseAmount > 0 then
                local rewardMultiplier = eventService:GetModifier("breakable_reward_multiplier", 1)
                    or 1
                local currencyMultiplier = eventService:GetModifier(
                    currencyType .. "_reward_multiplier",
                    1
                ) or 1
                return math.max(0, math.floor(baseAmount * rewardMultiplier * currencyMultiplier))
            end
            return baseAmount
        end

        if economy and valueAmount > 0 then
            local total = 0
            for _, v in ipairs(contribFolder:GetChildren()) do
                if v:IsA("NumberValue") then
                    total += v.Value
                end
            end
            if total > 0 then
                local remainder = valueAmount
                local topUserId, topAmount = nil, -math.huge
                for _, v in ipairs(contribFolder:GetChildren()) do
                    if v:IsA("NumberValue") and v.Value > 0 then
                        local share = math.floor(valueAmount * (v.Value / total))
                        remainder -= share
                        local plr = Players:GetPlayerByUserId(tonumber(v.Name))
                        if plr and share > 0 then
                            local resolvedShare = resolvePlayerAward(plr, share)
                            pcall(function()
                                economy:AddCurrency(
                                    plr,
                                    currencyType,
                                    resolvedShare,
                                    "crystal_break_split"
                                )
                                if stats then
                                    stats:Increment(plr, "breakables_broken", 1)
                                end
                                if
                                    petProgressionService
                                    and petProgressionService.AwardBreakableDestroyed
                                then
                                    petProgressionService:AwardBreakableDestroyed(plr, {
                                        world = model:GetAttribute("World"),
                                        breakableId = model:GetAttribute("BreakableId"),
                                        crystalName = model:GetAttribute("CrystalName"),
                                        currency = currencyType,
                                        source = "BreakableSpawner",
                                    })
                                end
                            end)
                        end
                        if v.Value > topAmount then
                            topAmount = v.Value
                            topUserId = tonumber(v.Name)
                        end
                    end
                end
                if remainder > 0 and topUserId then
                    local topPlayer = Players:GetPlayerByUserId(topUserId)
                    if topPlayer then
                        local resolvedRemainder = resolvePlayerAward(topPlayer, remainder)
                        pcall(function()
                            economy:AddCurrency(
                                topPlayer,
                                currencyType,
                                resolvedRemainder,
                                "crystal_break_remainder"
                            )
                        end)
                    end
                end
            end
        end
        -- Play break sound and destroy
        local container = model:FindFirstChild(model.Name) or model
        local sound = container:FindFirstChild("bigBreakSound")
        if sound and sound:IsA("Sound") then
            sound:Play()
            task.delay(sound.TimeLength or 0.2, function()
                if model and model.Parent then
                    model:Destroy()
                end
            end)
        else
            if model and model.Parent then
                model:Destroy()
            end
        end
    end

    model:GetAttributeChangedSignal("HP"):Connect(function()
        local hp = tonumber(model:GetAttribute("HP")) or 0
        if hp <= 0 then
            handleDeath()
        end
    end)

    -- Tag with spawner for diagnostics
    model:SetAttribute("Spawner", spawner.Name)
    -- Helpers for pet assignment
    local function removePetIdFromBreakables(petId)
        local breakablesRoot = workspace:FindFirstChild("Game")
            and workspace.Game:FindFirstChild("Breakables")
        if not breakablesRoot then
            return
        end
        local function scan(folder)
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Folder") and child.Name == "Pets" then
                    for _, y in ipairs(child:GetChildren()) do
                        if y:IsA("NumberValue") and y.Value == petId then
                            y:Destroy()
                        end
                    end
                end
                if #child:GetChildren() > 0 then
                    scan(child)
                end
            end
        end
        scan(breakablesRoot)
    end

    local function assignPlayerPetsToTarget(player)
        local petInstancesFolder = workspace:FindFirstChild("PlayerPets")
        if not petInstancesFolder then
            return
        end
        local playerPets = petInstancesFolder:FindFirstChild(player.Name)
        if not playerPets then
            return
        end
        local targetId = model:FindFirstChild("BreakableID") and model.BreakableID.Value or 0
        for _, petInst in ipairs(playerPets:GetChildren()) do
            local petIdVal = petInst:FindFirstChild("PetID")
            local targetIdVal = petInst:FindFirstChild("TargetID")
            local targetTypeVal = petInst:FindFirstChild("TargetType")
            local targetWorldVal = petInst:FindFirstChild("TargetWorld")
            if petIdVal and targetIdVal and targetTypeVal and targetWorldVal then
                if targetIdVal.Value ~= targetId then
                    removePetIdFromBreakables(petIdVal.Value)
                    -- Add entry to this crystal's Pets folder
                    local petsFolder = model:FindFirstChild("Pets") or Instance.new("Folder")
                    petsFolder.Name = "Pets"
                    petsFolder.Parent = model
                    local numInstance = Instance.new("NumberValue")
                    numInstance.Name = "Pet"
                    numInstance.Value = petIdVal.Value
                    local leadership = Instance.new("NumberValue")
                    leadership.Name = "Leadership"
                    leadership.Value = 0
                    leadership.Parent = numInstance
                    local tactics = Instance.new("NumberValue")
                    tactics.Name = "Tactics"
                    tactics.Value = 0
                    tactics.Parent = numInstance
                    local eff = Instance.new("NumberValue")
                    eff.Name = "Efficiency"
                    eff.Value = 1
                    eff.Parent = numInstance
                    numInstance.Parent = petsFolder

                    targetTypeVal.Value = "Crystals"
                    targetWorldVal.Value = worldFolder.Name
                    targetIdVal.Value = targetId
                end
            end
        end
        -- Visual/audio feedback
        local pp = model.PrimaryPart
        if pp then
            local bb = pp:FindFirstChild("BillboardGui")
            if bb then
                bb.MaxDistance = 75
            end
            local bbb = pp:FindFirstChild("BoostBillboardGui")
            if bbb then
                bbb.MaxDistance = 75
            end
            local hum = pp:FindFirstChild("EngineHumSound")
            if hum and hum:IsA("Sound") then
                hum:Play()
            end
        end
        -- Nudge boost
        local b = tonumber(model:GetAttribute("Boost")) or 0
        local m = tonumber(model:GetAttribute("MaxBoost")) or 100
        b += 1
        if b <= m then
            model:SetAttribute("Boost", b)
        end
    end

    -- Add click-to-assign-pets and damage (server-side)
    local breakableIdForLogs = (model:FindFirstChild("BreakableID") and model.BreakableID.Value)
        or 0
    local function attachClick(part)
        local cd = Instance.new("ClickDetector")
        cd.MaxActivationDistance = 50
        cd.Parent = part
        cd.MouseClick:Connect(function(player)
            print("Breakable clicked", player.Name)
            -- Assign player's pets to this target and play SFX/UI
            assignPlayerPetsToTarget(player)
            local hp = tonumber(model:GetAttribute("HP")) or 0
            if hp <= 0 then
                print("[Breakables] Click ignored (0 HP)", breakableIdForLogs, player.Name)
                return
            end
            local before = hp
            local after = math.max(0, hp - 5)
            model:SetAttribute("HP", after)
            print(
                "[Breakables] Clicked",
                breakableIdForLogs,
                player.Name,
                "HP:",
                before,
                "->",
                after,
                "part:",
                part.Name
            )

            -- Record contribution
            local delta = before - after
            local key = tostring(player.UserId)
            local nv = contribFolder:FindFirstChild(key)
            if not nv then
                nv = Instance.new("NumberValue")
                nv.Name = key
                nv.Value = 0
                nv.Parent = contribFolder
            end
            nv.Value += math.max(0, delta)
        end)
    end
    if model.PrimaryPart then
        attachClick(model.PrimaryPart)
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d ~= model.PrimaryPart then
            attachClick(d)
        end
    end
    -- Parent to Items and update count
    model.Parent = worldFolder:FindFirstChild("Items")
    current.Value = current.Value + 1

    if dropFromHeight > 0 then
        task.spawn(function()
            local startPivot = model:GetPivot()
            local elapsed = 0
            local duration = math.max(0.05, dropDuration)

            while model.Parent and elapsed < duration do
                local dt = RunService.Heartbeat:Wait()
                elapsed += dt
                local alpha = math.clamp(elapsed / duration, 0, 1)
                local eased = 1 - math.pow(1 - alpha, 3)
                model:PivotTo(startPivot:Lerp(finalPivot, eased))
            end

            if model.Parent then
                model:PivotTo(finalPivot)
            end
        end)
    end

    return model
end

function BreakableSpawner:SpawnBreakableForStudioSmoke(areaId, breakableId)
    if not RunService:IsStudio() then
        return nil, "studio_only"
    end

    if type(areaId) ~= "string" or areaId == "" then
        return nil, "invalid_area"
    end
    if type(breakableId) ~= "string" or breakableId == "" then
        return nil, "invalid_breakable"
    end
    if not (breakablesConfig.crystals and breakablesConfig.crystals[breakableId]) then
        return nil, "unknown_breakable"
    end

    local crystalsRoot = workspace:FindFirstChild("Game")
        and workspace.Game:FindFirstChild("Breakables")
        and workspace.Game.Breakables:FindFirstChild("Crystals")
    local worldFolder = crystalsRoot and crystalsRoot:FindFirstChild(areaId)
    if not worldFolder then
        return nil, "missing_area_folder"
    end

    self:_setupWorld(worldFolder)

    local model = self:_trySpawnOne(worldFolder, breakableId, nil, true)
    if not model then
        return nil, "spawn_failed"
    end

    return model
end

return BreakableSpawner
