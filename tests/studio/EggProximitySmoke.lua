--[[
    Client-coordinated Studio smoke test for egg proximity and hatching.

    Run in play mode through Studio MCP / command bar:

    return require(game:GetService("ReplicatedStorage").Tests.studio.EggProximitySmoke).runText()

    The server-side setup/assertion bridge is `StudioSmokeTestService`, exposed
    only while running in Studio.
]]

local EggProximitySmoke = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_TIMEOUT_SECONDS = 20
local REMOTE_NAME = "StudioSmokeTest"

local function waitFor(description, timeoutSeconds, predicate)
    local deadline = os.clock() + (timeoutSeconds or DEFAULT_TIMEOUT_SECONDS)

    while os.clock() < deadline do
        local result = predicate()
        if result then
            return result
        end
        task.wait(0.1)
    end

    error("Timed out waiting for " .. description)
end

local function getPlayer(options)
    if options.player then
        return options.player
    end

    return Players.LocalPlayer
        or Players:GetPlayers()[1]
        or waitFor("a player", options.timeoutSeconds, function()
            return Players.LocalPlayer or Players:GetPlayers()[1]
        end)
end

local function invoke(remote, action, payload)
    local response = remote:InvokeServer(action, payload or {})
    if type(response) ~= "table" then
        error("Studio smoke bridge returned non-table response")
    end
    if response.ok ~= true then
        error(response.error or ("Studio smoke bridge action failed: " .. tostring(action)))
    end
    return response
end

local function getCurrentTarget(player)
    local gui = player:FindFirstChild("PlayerGui")
    local targetGui = gui and gui:FindFirstChild("EggCurrentTarget")
    local frame = targetGui and targetGui:FindFirstChild("PreviewFrame")
    local target = frame and frame:FindFirstChild("CurrentTarget")

    return target and target.Value or nil, frame
end

local function waitForTarget(player, expectedValue, timeoutSeconds)
    return waitFor("egg current target " .. tostring(expectedValue), timeoutSeconds, function()
        local currentTarget, frame = getCurrentTarget(player)
        if currentTarget == expectedValue then
            return {
                currentTarget = currentTarget,
                visible = frame and frame.Visible or false,
            }
        end
        return nil
    end)
end

function EggProximitySmoke.run(options)
    options = options or {}

    local eggType = options.eggType or "basic_egg"
    local timeoutSeconds = options.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
    local assertUi = options.assertUi ~= false
    local player = getPlayer(options)
    local remote = waitFor(REMOTE_NAME .. " RemoteFunction", timeoutSeconds, function()
        local instance = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
        if instance and instance:IsA("RemoteFunction") then
            return instance
        end
        return nil
    end)

    local started = false
    local success, result = pcall(function()
        local begin = invoke(remote, "BeginEggProximity", { eggType = eggType })
        started = true

        invoke(remote, "MoveEggProximity", { placement = "far" })
        task.wait(0.35)

        if assertUi then
            waitForTarget(player, "None", timeoutSeconds)
        end

        local far = invoke(remote, "HatchEggProximity")
        assert(far.result == "Error", "Far hatch should be rejected")
        assert(
            tostring(far.message):find("Too far", 1, true),
            "Far hatch rejected for wrong reason"
        )
        assert(far.afterCurrency == far.beforeCurrency, "Far hatch changed currency")
        assert(far.afterPetCount == far.beforePetCount, "Far hatch changed pet count")

        task.wait((far.cooldown or 0) + 0.25)

        invoke(remote, "MoveEggProximity", { placement = "near" })
        task.wait(0.35)

        if assertUi then
            local targetState = waitForTarget(player, eggType, timeoutSeconds)
            assert(targetState.visible == true, "Egg target UI was not visible near the egg")
        end

        local near = invoke(remote, "HatchEggProximity")
        assert(type(near.result) == "table" and near.result.success == true, tostring(near.message))
        assert(
            near.afterCurrency == near.beforeCurrency - near.cost,
            "Near hatch did not deduct configured cost"
        )
        assert(near.afterPetCount == near.beforePetCount + 1, "Near hatch did not add one pet")

        invoke(remote, "MoveEggProximity", { placement = "far" })
        task.wait(0.35)

        if assertUi then
            waitForTarget(player, "None", timeoutSeconds)
        end

        return {
            player = player.Name,
            eggType = begin.eggType,
            currency = begin.currency,
            cost = begin.cost,
            originalCurrency = begin.originalCurrency,
            originalPetCount = begin.originalPetCount,
            hatchedPet = near.result.Pet,
            hatchedVariant = near.result.Type,
        }
    end)

    local restoreResponse
    if started then
        restoreResponse = remote:InvokeServer("RestoreEggProximity", {})
    end

    if not success then
        error(result)
    end

    result.restored = type(restoreResponse) == "table" and restoreResponse.restored == true
    return result
end

function EggProximitySmoke.runText(options)
    local result = EggProximitySmoke.run(options)
    return string.format(
        "EggProximitySmoke passed: player=%s egg=%s cost=%d %s hatched=%s/%s restored=%s",
        result.player,
        result.eggType,
        result.cost,
        result.currency,
        tostring(result.hatchedPet),
        tostring(result.hatchedVariant),
        tostring(result.restored)
    )
end

return EggProximitySmoke
