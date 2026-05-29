--[[
    Studio smoke test for config-driven egg unlock requirements.

    Run in play mode:

    return require(game:GetService("ReplicatedStorage").Tests.studio.EggUnlockSmoke).runText()
]]

local EggUnlockSmoke = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_TIMEOUT_SECONDS = 25
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

local function beginLockedEgg(remote, eggType, eggsHatched)
    return invoke(remote, "BeginEggProximity", {
        eggType = eggType,
        setupTemporaryEggStand = true,
        setupCounters = {
            eggs_hatched = eggsHatched,
        },
        setupCurrencyAmount = 5000,
        setupPetInventoryEmpty = true,
        setupPetStorageAvailableSlots = 2,
        setupAutoHatchUnlocked = true,
        setupGoldenModeUnlocked = true,
        setupChargedModeUnlocked = true,
        setupFastHatchUnlocked = true,
        setupSkipHatchUnlocked = true,
        setupMaxHatchCount = 5,
    })
end

function EggUnlockSmoke.run(options)
    options = options or {}
    local eggType = options.eggType or "golden_egg"
    local timeoutSeconds = options.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
    local player = getPlayer(options)
    local remote = waitFor(REMOTE_NAME .. " RemoteFunction", timeoutSeconds, function()
        local instance = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
        if instance and instance:IsA("RemoteFunction") then
            return instance
        end
        return nil
    end)

    local restoreNeeded = false
    local result = {}
    local success, err = pcall(function()
        local lockedBegin = beginLockedEgg(remote, eggType, 9)
        restoreNeeded = true
        invoke(remote, "MoveEggProximity", { placement = "near" })
        task.wait(0.25)

        local locked = invoke(remote, "HatchEggProximity", {
            batch = true,
            requestedCount = 1,
        })
        assert(type(locked.result) == "table", "Locked egg response was not a table")
        assert(locked.result.success == false, "Locked egg hatch unexpectedly succeeded")
        assert(locked.result.code == "egg_locked", "Locked egg returned wrong error code")
        assert(locked.afterCurrency == locked.beforeCurrency, "Locked egg changed currency")
        assert(locked.afterPetCount == locked.beforePetCount, "Locked egg changed pet inventory")
        assert(
            locked.result.details and locked.result.details.required == 10,
            "Locked egg response missed required unlock amount"
        )
        assert(
            locked.result.details and locked.result.details.current == 9,
            "Locked egg response missed current unlock progress"
        )
        result.lockedCode = locked.result.code
        result.required = locked.result.details.required
        result.current = locked.result.details.current
        result.currency = lockedBegin.currency

        invoke(remote, "RestoreEggProximity", {})
        restoreNeeded = false
        task.wait(0.4)

        local unlockedBegin = beginLockedEgg(remote, eggType, 10)
        restoreNeeded = true
        invoke(remote, "MoveEggProximity", { placement = "near" })
        task.wait(0.25)

        local unlocked = invoke(remote, "HatchEggProximity", {
            batch = true,
            requestedCount = 1,
        })
        assert(type(unlocked.result) == "table", "Unlocked egg response was not a table")
        assert(unlocked.result.success == true, "Unlocked egg hatch did not succeed")
        assert(unlocked.result.hatchCount == 1, "Unlocked egg hatch count mismatch")
        assert(
            unlocked.afterCurrency == unlocked.beforeCurrency - unlocked.result.TotalCost,
            "Unlocked egg deducted wrong currency"
        )
        assert(
            unlocked.afterPetCount == unlocked.beforePetCount + 1,
            "Unlocked egg did not add pet"
        )
        result.hatchedPet = unlocked.result.Pet
        result.hatchedVariant = unlocked.result.Type
        result.unlockedCurrency = unlockedBegin.currency

        invoke(remote, "RestoreEggProximity", {})
        restoreNeeded = false
    end)

    local restoreResponse
    if restoreNeeded then
        restoreResponse = remote:InvokeServer("RestoreEggProximity", {})
    end

    if not success then
        error(err)
    end

    result.restored = restoreNeeded == false
        or (type(restoreResponse) == "table" and restoreResponse.restored == true)
    result.player = player.Name
    result.eggType = eggType
    return result
end

function EggUnlockSmoke.runText(options)
    local result = EggUnlockSmoke.run(options)
    return string.format(
        "EggUnlockSmoke passed: player=%s egg=%s locked=%s %d/%d hatched=%s/%s restored=%s",
        result.player,
        result.eggType,
        tostring(result.lockedCode),
        result.current,
        result.required,
        tostring(result.hatchedPet),
        tostring(result.hatchedVariant),
        tostring(result.restored)
    )
end

return EggUnlockSmoke
