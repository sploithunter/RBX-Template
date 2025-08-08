--[[
    BreakableSpawner - Spawns breakable crystals into worlds

    Responsibilities:
    - Reads breakable config (configs/breakables.lua)
    - Uses preloaded assets in ReplicatedStorage.Assets.Models.Breakables.Crystals
    - Spawns crystals at world spawners up to world Max, tracks CurrentItems
    - Respawns when items are removed

    Notes:
    - Does NOT modify scripts inside the crystal models; spawns with parts anchored
    - Relies on GameStructureService to create workspace.Game.Breakables.Crystals.* worlds
]]

local BreakableSpawner = {}
BreakableSpawner.__index = BreakableSpawner

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Injected services
local logger
local configLoader

-- Local state
local breakablesConfig

-- Geometry helpers for crystal star ring
local function getPointOnCircle(radius, degrees)
    return Vector3.new(math.cos(math.rad(degrees)) * radius, 2, math.sin(math.rad(degrees)) * radius)
end

local function updateStarScale(starPart, factor)
    if not starPart or not starPart:IsA("BasePart") then return end
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
    if not parentModel or not parentModel.PrimaryPart then return end
    local star = Instance.new("Part")
    star.Name = "Star"
    star.Size = Vector3.new(1, 1, 1)
    star.Anchored = true
    star.CanCollide = false
    star.Transparency = 1
    star.CFrame = CFrame.new(parentModel.PrimaryPart.Position + Vector3.new(0, parentModel:GetExtentsSize().Y/4, 0))
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
            if not pp then break end
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

function BreakableSpawner:Init()
    logger = self._modules.Logger
    configLoader = self._modules.ConfigLoader

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
        crystalsDefined = (breakablesConfig.crystals and #breakablesConfig.crystals) or 0
    })
end

function BreakableSpawner:Start()
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

function BreakableSpawner:_spawnLoop()
    -- Wait for assets folder
    local assets = ReplicatedStorage:WaitForChild("Assets", 10)
    if not assets then
        logger:Error("BreakableSpawner: Assets folder not found; aborting spawn loop")
        return
    end
    local models = assets:WaitForChild("Models", 10)
    if not models then return end
    local breakables = models:WaitForChild("Breakables", 30)
    if not breakables then
        logger:Error("BreakableSpawner: Assets.Models.Breakables missing; aborting")
        return
    end
    local crystalsAssets = breakables:WaitForChild("Crystals", 30)
    if not crystalsAssets then
        logger:Warn("BreakableSpawner: Crystal assets folder missing after wait; will retry when assets load")
        -- Try to wait for global signal if provided by AssetPreloadService
        if _G.AssetsLoadedEvent then
            _G.AssetsLoadedEvent.Event:Connect(function()
                local b = models:FindFirstChild("Breakables")
                local c = b and b:FindFirstChild("Crystals")
                if c then
                    self:_fillAllWorlds(c)
                end
            end)
        end
    else
        -- If AssetPreloadService exposes a global completion flag, wait for it
        local waited = 0
        while (not _G.AssetsLoadingComplete) and waited < 15 do
            task.wait(0.5)
            waited += 0.5
        end
        -- Also wait until crystals are actually populated
        local start = tick()
        while #crystalsAssets:GetChildren() == 0 and tick() - start < 30 do
            task.wait(0.5)
        end
        self._crystalsAssets = crystalsAssets
        if #crystalsAssets:GetChildren() == 0 then
            logger:Warn("BreakableSpawner: Crystals folder has no children after waits; will keep retrying")
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
    -- Ensure placeholder folders so other systems that WaitForChild on them don't hang
    for _, name in ipairs({"Gold", "Green", "Summer"}) do
        if not breakablesWorlds:FindFirstChild(name) then
            local f = Instance.new("Folder")
            f.Name = name
            f.Parent = breakablesWorlds
        end
    end
    local crystalsWorlds = breakablesWorlds:FindFirstChild("Crystals")
    if not crystalsWorlds then
        logger:Error("BreakableSpawner: workspace.Game.Breakables.Crystals missing; cannot spawn")
        return
    end

    -- Ensure minimal Chaseables tree to satisfy any WaitForChild
    local chaseables = gameFolder:FindFirstChild("Chaseables")
    if not chaseables then
        chaseables = Instance.new("Folder")
        chaseables.Name = "Chaseables"
        chaseables.Parent = gameFolder
    end
    for _, name in ipairs({"Snowman", "Hearts"}) do
        if not chaseables:FindFirstChild(name) then
            local f = Instance.new("Folder")
            f.Name = name
            f.Parent = chaseables
        end
    end

    -- Attach listeners and do initial fill for each world
    for _, worldFolder in ipairs(crystalsWorlds:GetChildren()) do
        if worldFolder:IsA("Folder") then
            self:_setupWorld(worldFolder)
            self:_fillWorld(worldFolder, self._crystalsAssets)
        end
    end

    -- Watch for new worlds added dynamically
    crystalsWorlds.ChildAdded:Connect(function(child)
        if child:IsA("Folder") then
            self:_setupWorld(child)
            self:_fillWorld(child, self._crystalsAssets)
        end
    end)
end

function BreakableSpawner:_fillAllWorlds(crystalsAssets)
    local gameFolder = workspace:FindFirstChild("Game")
    if not gameFolder then return end
    local breakablesWorlds = gameFolder:FindFirstChild("Breakables")
    if not breakablesWorlds then return end
    local crystalsWorlds = breakablesWorlds:FindFirstChild("Crystals")
    if not crystalsWorlds then return end
    self._crystalsAssets = crystalsAssets
    for _, worldFolder in ipairs(crystalsWorlds:GetChildren()) do
        if worldFolder:IsA("Folder") then
            self:_fillWorld(worldFolder, crystalsAssets)
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
    if not max then
        max = Instance.new("NumberValue")
        max.Name = "Max"
        -- use config if available
        local worldConfig = (breakablesConfig.worlds and breakablesConfig.worlds[worldFolder.Name]) or nil
        local defaultMax = (breakablesConfig.defaults and breakablesConfig.defaults.max_per_world) or 25
        max.Value = (worldConfig and worldConfig.max) or defaultMax
        max.Parent = worldFolder
    end

    -- Maintain count when items removed
    items.ChildRemoved:Connect(function()
        task.defer(function()
            local c = current.Value
            if c > 0 then current.Value = c - 1 end
            local worldCfg = breakablesConfig.worlds and breakablesConfig.worlds[worldFolder.Name]
            local placeCfg = worldCfg and worldCfg.spawn_settings or {}
            local minDelay = tonumber(placeCfg.respawn_min_seconds or 5)
            local maxDelay = tonumber(placeCfg.respawn_max_seconds or 60)
            local delaySec = math.random(minDelay, maxDelay)
            task.delay(delaySec, function()
                self:_trySpawnOne(worldFolder)
            end)
        end)
    end)
end

function BreakableSpawner:_fillWorld(worldFolder, crystalsAssets)
    local current = worldFolder:FindFirstChild("CurrentItems")
    local max = worldFolder:FindFirstChild("Max")
    if not (current and max) then return end
    local deficit = math.max(0, (max.Value or 0) - (current.Value or 0))
    for i = 1, deficit do
        self:_trySpawnOne(worldFolder)
    end
end

function BreakableSpawner:_selectCrystalName(worldName)
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
                return e.name
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
    if #names == 0 then return nil end
    local idx = math.random(1, #names)
    return names[idx]
end

function BreakableSpawner:_getSpawnerParts(worldFolder)
    local spawners = {}
    for _, child in ipairs(worldFolder:GetChildren()) do
        if child:IsA("BasePart") and (child.Name == "Spawner" or child.Name == "DarkSpawner" or child.Name:find("Spawner")) then
            table.insert(spawners, child)
        end
    end
    return spawners
end

-- Find a spawner that doesn't currently have a crystal near it
function BreakableSpawner:_findFreeSpawner(worldFolder)
    local itemsFolder = worldFolder:FindFirstChild("Items")
    local spawners = self:_getSpawnerParts(worldFolder)
    if #spawners == 0 then return nil end

    -- Shuffle spawners to distribute load
    for i = #spawners, 2, -1 do
        local j = math.random(1, i)
        spawners[i], spawners[j] = spawners[j], spawners[i]
    end

    local worldCfg = breakablesConfig.worlds and breakablesConfig.worlds[worldFolder.Name]
    local placeCfg = worldCfg and worldCfg.spawn_settings or {}
    local clearRadius = tonumber(placeCfg.min_distance or 12)

    for _, spawner in ipairs(spawners) do
        local occupied = false
        if itemsFolder then
            for _, child in ipairs(itemsFolder:GetChildren()) do
                if child:IsA("Model") and child.PrimaryPart then
                    local d = (child.PrimaryPart.Position - spawner.Position).Magnitude
                    if d < clearRadius then
                        occupied = true
                        break
                    end
                end
            end
        end
        if not occupied then
            return spawner
        end
    end
    return nil
end

function BreakableSpawner:_trySpawnOne(worldFolder)
    local current = worldFolder:FindFirstChild("CurrentItems")
    local max = worldFolder:FindFirstChild("Max")
    if not (current and max) then return end
    if current.Value >= max.Value then return end

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

    local crystalName = self:_selectCrystalName(worldFolder.Name)
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
        logger:Warn("BreakableSpawner: Crystal asset missing", { name = crystalName, available = present })
        return
    end

    local spawners = self:_getSpawnerParts(worldFolder)
    if #spawners == 0 then
        logger:Warn("BreakableSpawner: No spawner parts in world", { world = worldFolder.Name })
        return
    end
    local spawner = self:_findFreeSpawner(worldFolder)
    if not spawner then
        -- All spawners are currently occupied within clear radius; skip for now
        return
    end

    -- Clone and prepare model
    local model = assetModel:Clone()
    model.Name = crystalName

    -- Anchor all parts so crystals stay in place
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
        end
    end

    -- Determine placement/orientation settings
    local worldCfg = breakablesConfig.worlds and breakablesConfig.worlds[worldFolder.Name]
    local placeCfg = worldCfg and worldCfg.spawn_settings or {upright = true, embed_ratio = 0.25, min_distance = 12}

    -- Compute height offsets
    local heightOffset = 1
    if string.find(crystalName, "Program") or string.find(crystalName, "DarkDesert") then
        heightOffset = 12
    elseif string.find(crystalName, "Dark") or string.find(crystalName, "Big") then
        heightOffset = 7
    elseif string.find(crystalName, "Medium") then
        heightOffset = 2
    else
        heightOffset = 1
    end

    -- Orientation: preserve model's default pitch/roll from assets, add random yaw
    local yaw = math.rad(math.random(0, 359))
    local baseCF = spawner.CFrame * CFrame.new(0, heightOffset, 0)
    local targetCFrame
    if placeCfg.upright then
        -- Keep the model's asset orientation (pitch/roll), only randomize yaw around world Y
        local pivot = model:GetPivot()
        local orientOnly = pivot - pivot.Position
        targetCFrame = CFrame.new(baseCF.Position) * CFrame.Angles(0, yaw, 0) * orientOnly
    else
        -- Free rotation: yaw only
        targetCFrame = CFrame.new(baseCF.Position) * CFrame.Angles(0, yaw, 0)
    end
    pcall(function()
        model:PivotTo(targetCFrame)
    end)

    -- Embed fraction of height below ground to avoid floating
    local sizeY = model:GetExtentsSize().Y
    local embed = math.clamp(tonumber(placeCfg.embed_ratio or 0.25), 0, 0.9)
    if embed > 0 then
        pcall(function()
            model:PivotTo(model:GetPivot() * CFrame.new(0, -sizeY * embed, 0))
        end)
    end

    -- Simple de-overlap: if another crystal is too close, nudge sideways (up to few tries)
    local minDist = tonumber(placeCfg.min_distance or 12)
    local itemsFolder = worldFolder:FindFirstChild("Items")
    local tries = 0
    while tries < 4 and itemsFolder do
        local tooClose = false
        for _, other in ipairs(itemsFolder:GetChildren()) do
            if other:IsA("Model") and other ~= model and other.PrimaryPart and model.PrimaryPart then
                local d = (other.PrimaryPart.Position - model.PrimaryPart.Position).Magnitude
                if d < minDist then
                    tooClose = true
                    break
                end
            end
        end
        if tooClose then
            tries += 1
            local angle = math.rad(math.random(0,359))
            local step = minDist * 0.75
            pcall(function()
                model:PivotTo(model:GetPivot() * CFrame.new(math.cos(angle)*step, 0, math.sin(angle)*step))
            end)
        else
            break
        end
    end

    -- Optional attributes for downstream logic (mirrors MCP fields)
    model:SetAttribute("BreakableType", "Crystal")
    model:SetAttribute("CrystalName", crystalName)
    model:SetAttribute("World", worldFolder.Name)

    -- Set gameplay attributes if present in config
    local data = breakablesConfig.crystals[crystalName]
    if type(data) == "table" then
        local maxhp = tonumber(data.health or 0)
        local value = tonumber(data.value or 0)
        model:SetAttribute("MaxHP", maxhp)
        model:SetAttribute("HP", maxhp)
        model:SetAttribute("Value", value)
        model:SetAttribute("Currency", tostring(data.currency or "crystals"))
        model:SetAttribute("Boost", 0)
        model:SetAttribute("MaxBoost", 100)
    end

    -- Unique breakable ID (for targeting). Using random large int similar to MCP
    local idValue = Instance.new("NumberValue")
    idValue.Name = "BreakableID"
    idValue.Value = math.random(2, 2^30) + math.random(2, 2^30)
    idValue.Parent = model

    -- Contribution tracking (per-player damage)
    local contribFolder = Instance.new("Folder")
    contribFolder.Name = "Contrib"
    contribFolder.Parent = model

    -- Bind health bar UI (if present in model)
    -- Match MCP: find any descendant BillboardGui with a child Frame named 'Health'
    local billboards = {}
    local healthFrames = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BillboardGui") then
            table.insert(billboards, d)
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
        if #healthFrames == 0 then return end
        local maxHp = tonumber(model:GetAttribute("MaxHP")) or 0
        local hp = tonumber(model:GetAttribute("HP")) or 0
        print("updateHealthBar", maxHp, hp)
        if maxHp <= 0 then return end
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
        if not pp then return end
        local bbg = pp:FindFirstChild("BoostBillboardGui")
        if not bbg then return end
        local boostFrame = bbg:FindFirstChild("Boost")
        if not boostFrame then
            local container = bbg:FindFirstChildWhichIsA("Frame")
            boostFrame = container and container:FindFirstChild("Boost")
        end
        if not boostFrame then return end
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
            if bb then bb.MaxDistance = 75 end
            local bbb = pp:FindFirstChild("BoostBillboardGui")
            if bbb then bbb.MaxDistance = 75 end
                local hum = pp:FindFirstChild("EngineHumSound")
                if hum and hum:IsA("Sound") then hum:Play() end
            -- Play a soft engage sound if present
            local soft = pp:FindFirstChild("littleBreakSound")
            if soft and soft:IsA("Sound") then
                if math.random(1, 3) == 1 then soft:Play() end
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
                if star then star:Destroy() end
                local pp = model.PrimaryPart
                if pp then
                    local bb = pp:FindFirstChild("BillboardGui")
                    if bb then bb.MaxDistance = 25 end
                    local bbb = pp:FindFirstChild("BoostBillboardGui")
                    if bbb then bbb.MaxDistance = 1 end
                    local hum = pp:FindFirstChild("EngineHumSound")
                    if hum and hum:IsA("Sound") then hum:Stop() end
                    -- Optional soft stop cue
                    local soft = pp:FindFirstChild("littleBreakSound")
                    if soft and soft:IsA("Sound") then
                        if math.random(1, 5) == 1 then soft:Play() end
                    end
                end
            end
        end)
    end

    -- Award/destroy handler when HP reaches 0 from any source
    local function handleDeath()
        if not model.Parent then return end
        if model:GetAttribute("Dead") then return end
        model:SetAttribute("Dead", true)
        -- Compute awards based on contributions
        local currencyType = tostring(model:GetAttribute("Currency") or "coins")
        local valueAmount = tonumber(model:GetAttribute("Value") or 0)
        local economy = (self._moduleLoader and self._moduleLoader:Get("EconomyService")) or (self._modules and self._modules.EconomyService)
        if economy and valueAmount > 0 then
            local total = 0
            for _, v in ipairs(contribFolder:GetChildren()) do
                if v:IsA("NumberValue") then total += v.Value end
            end
            if total <= 0 then
                -- No contributions recorded; nothing to award
            else
                local remainder = valueAmount
                local topUserId, topAmount = nil, -math.huge
                for _, v in ipairs(contribFolder:GetChildren()) do
                    if v:IsA("NumberValue") and v.Value > 0 then
                        local share = math.floor(valueAmount * (v.Value / total))
                        remainder -= share
                        local plr = Players:GetPlayerByUserId(tonumber(v.Name))
                        if plr and share > 0 then
                            pcall(function()
                                economy:AddCurrency(plr, currencyType, share, "crystal_break_split")
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
                        pcall(function()
                            economy:AddCurrency(topPlayer, currencyType, remainder, "crystal_break_remainder")
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

        -- Decrement world counts
        local itemsFolder = worldFolder:FindFirstChild("Items")
        local current = worldFolder:FindFirstChild("CurrentItems")
        if current then
            task.defer(function()
                current.Value = math.max(0, (current.Value or 1) - 1)
            end)
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
        local breakablesRoot = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Breakables")
        if not breakablesRoot then return end
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
        if not petInstancesFolder then return end
        local playerPets = petInstancesFolder:FindFirstChild(player.Name)
        if not playerPets then return end
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
            local bb = pp:FindFirstChild("BillboardGui"); if bb then bb.MaxDistance = 75 end
            local bbb = pp:FindFirstChild("BoostBillboardGui"); if bbb then bbb.MaxDistance = 75 end
            local hum = pp:FindFirstChild("EngineHumSound"); if hum and hum:IsA("Sound") then hum:Play() end
        end
        -- Nudge boost
        local b = tonumber(model:GetAttribute("Boost")) or 0
        local m = tonumber(model:GetAttribute("MaxBoost")) or 100
        b += 1
        if b <= m then model:SetAttribute("Boost", b) end
    end

    -- Add click-to-assign-pets and damage (server-side)
    local breakableIdForLogs = (model:FindFirstChild("BreakableID") and model.BreakableID.Value) or 0
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
            print("[Breakables] Clicked", breakableIdForLogs, player.Name, "HP:", before, "->", after, "part:", part.Name)

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
end

return BreakableSpawner


