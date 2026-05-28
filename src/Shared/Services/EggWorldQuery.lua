local CollectionService = game:GetService("CollectionService")

local EggWorldQuery = {}

local function isUsable(instance)
    return instance and instance:IsDescendantOf(workspace)
end

local function readStringValue(instance, name)
    local child = instance:FindFirstChild(name)
    if child and child:IsA("StringValue") then
        return child.Value
    end
    return nil
end

function EggWorldQuery.GetEggType(instance)
    if not instance then
        return nil
    end

    local eggType = instance:GetAttribute("EggType")
        or instance:GetAttribute("EggId")
        or readStringValue(instance, "EggType")
        or readStringValue(instance, "EggId")

    if type(eggType) == "string" and eggType ~= "" then
        return eggType
    end

    return nil
end

function EggWorldQuery.GetAnchor(instance)
    if not instance then
        return nil
    end

    local spawnPointRef = instance:FindFirstChild("SpawnPoint")
    if spawnPointRef and spawnPointRef:IsA("ObjectValue") and isUsable(spawnPointRef.Value) then
        return spawnPointRef.Value
    end

    if instance:IsA("BasePart") then
        return instance
    end

    if instance:IsA("Model") then
        if instance.PrimaryPart then
            return instance.PrimaryPart
        end
        return instance:FindFirstChildWhichIsA("BasePart", true)
    end

    return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function appendCandidate(results, seen, instance)
    if not isUsable(instance) or seen[instance] then
        return
    end

    local eggType = EggWorldQuery.GetEggType(instance)
    local anchor = eggType and EggWorldQuery.GetAnchor(instance)
    if not (eggType and anchor) then
        return
    end

    seen[instance] = true
    table.insert(results, {
        instance = instance,
        eggType = eggType,
        anchor = anchor,
    })
end

function EggWorldQuery.GetEggs()
    local results = {}
    local seen = {}

    for _, instance in ipairs(CollectionService:GetTagged("EggStand")) do
        appendCandidate(results, seen, instance)
    end

    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Model") or instance:IsA("BasePart") then
            appendCandidate(results, seen, instance)
        end
    end

    return results
end

function EggWorldQuery.GetEggsByType(eggType)
    local results = {}
    for _, egg in ipairs(EggWorldQuery.GetEggs()) do
        if egg.eggType == eggType then
            table.insert(results, egg)
        end
    end
    return results
end

function EggWorldQuery.FindEggByType(eggType)
    local eggs = EggWorldQuery.GetEggsByType(eggType)
    return eggs[1] and eggs[1].instance or nil
end

function EggWorldQuery.FindClosestEgg(playerPosition, eggTypes, maxDistance)
    local allowed = {}
    if type(eggTypes) == "table" then
        for _, eggType in ipairs(eggTypes) do
            allowed[eggType] = true
        end
    end

    local closest = nil
    local closestDistance = maxDistance or math.huge

    for _, egg in ipairs(EggWorldQuery.GetEggs()) do
        if (not eggTypes or allowed[egg.eggType]) and egg.anchor then
            local distance = (egg.anchor.Position - playerPosition).Magnitude
            if distance <= closestDistance then
                closest = egg
                closestDistance = distance
            end
        end
    end

    return closest, closestDistance
end

function EggWorldQuery.IsNearEggType(eggType, position, maxDistance)
    for _, egg in ipairs(EggWorldQuery.GetEggsByType(eggType)) do
        if egg.anchor and (position - egg.anchor.Position).Magnitude <= maxDistance then
            return true, egg.instance
        end
    end

    return false, nil
end

function EggWorldQuery.ShouldSpawnVisualAtHook(hook, spawnPointName)
    if not hook or not hook:IsA("BasePart") then
        return false
    end

    local spawnMode = hook:GetAttribute("SpawnMode")
    if spawnMode == "authored" or hook:GetAttribute("AuthoredVisual") == true then
        return false
    end

    if spawnMode == "spawn_model" or hook:GetAttribute("Synthetic") == true then
        return true
    end

    if spawnPointName and hook.Name == spawnPointName then
        return hook.Transparency >= 0.95
    end

    return hook.Transparency >= 0.95
end

return EggWorldQuery
