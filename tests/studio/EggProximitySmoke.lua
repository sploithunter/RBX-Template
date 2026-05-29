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

local function getHatchPanel(player)
    local gui = player:FindFirstChild("PlayerGui")
    local panelGui = gui and gui:FindFirstChild("EggHatchPanel")
    local panel = panelGui and panelGui:FindFirstChild("Panel")
    return panel
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

local function waitForHatchPanel(player, expectedVisible, timeoutSeconds)
    return waitFor(
        "egg hatch panel visibility " .. tostring(expectedVisible),
        timeoutSeconds,
        function()
            local panel = getHatchPanel(player)
            if panel and panel.Visible == expectedVisible then
                return panel
            end
            if expectedVisible == false and not panel then
                return true
            end
            return nil
        end
    )
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
        local begin = invoke(remote, "BeginEggProximity", {
            eggType = eggType,
            setupGoldenModeUnlocked = false,
            setupChargedModeUnlocked = false,
            setupFastHatchUnlocked = false,
            setupSkipHatchUnlocked = false,
        })
        started = true

        invoke(remote, "MoveEggProximity", { placement = "far" })
        task.wait(0.35)

        if assertUi then
            waitForTarget(player, "None", timeoutSeconds)
            waitForHatchPanel(player, false, timeoutSeconds)
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
            local hatchPanel = waitForHatchPanel(player, true, timeoutSeconds)
            assert(hatchPanel:FindFirstChild("Hatch"), "Hatch panel missing Hatch button")
            assert(hatchPanel:FindFirstChild("Max"), "Hatch panel missing Max button")
            assert(hatchPanel:FindFirstChild("Auto"), "Hatch panel missing Auto button")
            assert(hatchPanel:FindFirstChild("Count"), "Hatch panel missing count display")
            local settings = hatchPanel:FindFirstChild("SettingsDrawer")
            assert(settings, "Hatch panel missing settings drawer")
            local helpText = settings:FindFirstChild("HelpText")
            assert(helpText, "Hatch panel missing config-driven help text")
            assert(
                settings:FindFirstChild("pet_types_bear"),
                "Hatch panel missing pet-family auto-delete filter"
            )
            assert(
                settings:FindFirstChild("Mode_goldenMode"),
                "Hatch panel missing Golden mode toggle"
            )
            assert(
                settings.Mode_goldenMode:GetAttribute("HelpText"),
                "Golden mode toggle missing help text"
            )
            assert(
                settings.Mode_goldenMode:GetAttribute("ModeState") == "locked",
                "Golden mode toggle did not expose locked state"
            )
            assert(
                settings.Mode_goldenMode:GetAttribute("LockedHelpText"),
                "Golden mode toggle missing locked help text"
            )
            assert(
                settings:FindFirstChild("Mode_chargedMode"),
                "Hatch panel missing Charged mode toggle"
            )
            assert(
                settings:FindFirstChild("Mode_skipHatch"),
                "Hatch panel missing Skip mode toggle"
            )
            local modeStatus = settings:FindFirstChild("ModeStatus")
            assert(modeStatus, "Hatch panel missing mode status text")
            assert(
                tostring(modeStatus.Text):find("Locked:", 1, true),
                "Hatch panel mode status did not explain locked modes"
            )
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
            waitForHatchPanel(player, false, timeoutSeconds)
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
