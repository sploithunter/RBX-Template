--[[
	Studio smoke test for client auto-hatch stop feedback.

	Run in play mode:

	return require(game:GetService("ReplicatedStorage").Tests.studio.EggAutoHatchSmoke).runText()
]]

local EggAutoHatchSmoke = {}

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

local function prepareInteractionService(eggInteraction)
    local currentTargetService = require(ReplicatedStorage.Shared.Services.EggCurrentTargetService)
    currentTargetService:Initialize()
    eggInteraction:Initialize()
    task.wait(0.5)
    return currentTargetService
end

function EggAutoHatchSmoke.run(options)
    options = options or {}

    local eggType = options.eggType or "basic_egg"
    local timeoutSeconds = options.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
    local player = getPlayer(options)
    local remote = waitFor(REMOTE_NAME .. " RemoteFunction", timeoutSeconds, function()
        local instance = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
        if instance and instance:IsA("RemoteFunction") then
            return instance
        end
        return nil
    end)
    local eggInteraction = require(ReplicatedStorage.Shared.Services.EggInteractionService)

    local started = false
    local interactionPrepared = false
    local currentTargetService = nil
    local success, result = pcall(function()
        currentTargetService = prepareInteractionService(eggInteraction)
        interactionPrepared = true

        local state = eggInteraction:GetHatchPanelDebugState()
        if state.autoHatchEnabled then
            eggInteraction:ToggleAutoHatch()
            task.wait(0.2)
        end

        local begin = invoke(remote, "BeginEggProximity", {
            eggType = eggType,
            setupHatchCount = 1,
            setupCurrencyAmount = 0,
            setupAutoHatchUnlocked = true,
        })
        started = true

        invoke(remote, "MoveEggProximity", { placement = "near" })
        waitFor("egg current target " .. eggType, timeoutSeconds, function()
            return currentTargetService:GetCurrentTarget() == eggType
        end)

        eggInteraction:SetSelectedHatchCount(1)
        eggInteraction:ToggleAutoHatch()

        local stoppedState = waitFor("auto hatch currency stop", timeoutSeconds, function()
            local current = eggInteraction:GetHatchPanelDebugState()
            if
                current.autoHatchEnabled == false
                and tostring(current.statusText):find(
                    "Auto hatch stopped: out of currency",
                    1,
                    true
                )
            then
                return current
            end
            return nil
        end)

        return {
            player = player.Name,
            eggType = begin.eggType,
            currency = begin.currency,
            statusText = stoppedState.statusText,
        }
    end)

    local restoreResponse
    if started then
        restoreResponse = remote:InvokeServer("RestoreEggProximity", {})
    end
    if interactionPrepared then
        eggInteraction:Destroy()
        if currentTargetService then
            currentTargetService:Destroy()
        end
    end

    if not success then
        error(result)
    end

    result.restored = type(restoreResponse) == "table" and restoreResponse.restored == true
    return result
end

function EggAutoHatchSmoke.runText(options)
    local result = EggAutoHatchSmoke.run(options)
    return string.format(
        "EggAutoHatchSmoke passed: player=%s egg=%s currency=%s status=%q restored=%s",
        result.player,
        result.eggType,
        result.currency,
        result.statusText,
        tostring(result.restored)
    )
end

return EggAutoHatchSmoke
