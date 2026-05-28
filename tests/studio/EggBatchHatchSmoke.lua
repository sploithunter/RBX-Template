--[[
    Studio smoke test for server-authoritative batch egg hatching.

    Run in play mode:

    return require(game:GetService("ReplicatedStorage").Tests.studio.EggBatchHatchSmoke).runText()
]]

local EggBatchHatchSmoke = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage.Shared.Locations)
local eggSystemConfig = Locations.getConfig("egg_system")

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

function EggBatchHatchSmoke.run(options)
    options = options or {}

    local eggType = options.eggType or "basic_egg"
    local requestedCount = math.max(2, math.floor(tonumber(options.requestedCount) or 5))
    local timeoutSeconds = options.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
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
            setupHatchCount = requestedCount,
        })
        started = true

        invoke(remote, "MoveEggProximity", { placement = "near" })
        task.wait(0.35)

        local batch = invoke(remote, "HatchEggProximity", {
            batch = true,
            requestedCount = requestedCount,
        })
        assert(
            type(batch.result) == "table" and batch.result.success == true,
            tostring(batch.message)
        )
        assert(batch.result.requestedCount == requestedCount, "Batch response lost requested count")
        assert(batch.result.hatchCount == requestedCount, "Batch did not hatch requested count")
        assert(type(batch.result.results) == "table", "Batch response missing results")
        assert(#batch.result.results == requestedCount, "Batch result count mismatch")
        assert(
            batch.afterCurrency == batch.beforeCurrency - (batch.cost * requestedCount),
            "Batch did not deduct the combined configured cost"
        )
        assert(
            batch.afterPetCount == batch.beforePetCount + requestedCount,
            "Batch did not add the expected number of pets"
        )

        local rapid = invoke(remote, "HatchEggProximity", {
            batch = true,
            requestedCount = 1,
        })
        assert(
            type(rapid.result) == "table" and rapid.result.success == false,
            "Rapid hatch was not rejected"
        )
        assert(rapid.result.code == "hatch_locked", "Rapid hatch rejected for wrong reason")
        assert(rapid.afterCurrency == rapid.beforeCurrency, "Rapid rejected hatch changed currency")
        assert(
            rapid.afterPetCount == rapid.beforePetCount,
            "Rapid rejected hatch changed pet count"
        )

        task.wait((batch.cooldown or 0) + 0.25)
        local partialFundsCount = math.max(1, requestedCount - 2)
        invoke(remote, "RestoreEggProximity", {})
        started = false
        begin = invoke(remote, "BeginEggProximity", {
            eggType = eggType,
            setupHatchCount = requestedCount,
            setupCurrencyAmount = begin.cost * partialFundsCount,
        })
        started = true
        invoke(remote, "MoveEggProximity", { placement = "near" })
        task.wait(0.2)

        local partialFunds = invoke(remote, "HatchEggProximity", {
            batch = true,
            requestedCount = requestedCount,
        })
        assert(
            type(partialFunds.result) == "table" and partialFunds.result.success == true,
            "Partial funds hatch failed"
        )
        assert(
            partialFunds.result.hatchCount == partialFundsCount,
            "Partial funds hatch count mismatch"
        )
        assert(partialFunds.result.stopReason == "currency", "Partial funds stop reason mismatch")
        assert(
            partialFunds.afterCurrency
                == partialFunds.beforeCurrency - (partialFunds.cost * partialFundsCount),
            "Partial funds deducted wrong amount"
        )

        task.wait((partialFunds.cooldown or 0) + 0.25)
        invoke(remote, "RestoreEggProximity", {})
        started = false
        local goldenCount = math.min(2, requestedCount)
        local goldenMultiplier = math.max(
            1,
            tonumber(
                eggSystemConfig.hatching
                    and eggSystemConfig.hatching.shop_stubs
                    and eggSystemConfig.hatching.shop_stubs.golden_mode
                    and eggSystemConfig.hatching.shop_stubs.golden_mode.cost_multiplier
            ) or 20
        )
        begin = invoke(remote, "BeginEggProximity", {
            eggType = eggType,
            setupHatchCount = goldenCount,
            setupCurrencyAmount = begin.cost * goldenMultiplier * goldenCount,
            setupGoldenModeUnlocked = true,
        })
        started = true
        invoke(remote, "MoveEggProximity", { placement = "near" })
        task.wait(0.2)

        local golden = invoke(remote, "HatchEggProximity", {
            batch = true,
            requestedCount = goldenCount,
            options = {
                goldenMode = true,
            },
        })
        assert(
            type(golden.result) == "table" and golden.result.success == true,
            "Golden hatch failed"
        )
        assert(golden.result.hatchCount == goldenCount, "Golden hatch count mismatch")
        assert(
            golden.result.options and golden.result.options.goldenMode == true,
            "Golden mode not echoed"
        )
        assert(
            golden.afterCurrency
                == golden.beforeCurrency - (golden.cost * goldenMultiplier * goldenCount),
            "Golden hatch deducted wrong amount"
        )
        for _, entry in ipairs(golden.result.results or {}) do
            assert(entry.Type ~= "basic", "Golden mode hatched a basic variant")
        end

        return {
            player = player.Name,
            eggType = begin.eggType,
            currency = begin.currency,
            cost = begin.cost,
            requestedCount = requestedCount,
            hatchCount = batch.result.hatchCount,
            partialFundsCount = partialFunds.result.hatchCount,
            goldenCount = golden.result.hatchCount,
            stopReason = batch.result.stopReason,
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

function EggBatchHatchSmoke.runText(options)
    local result = EggBatchHatchSmoke.run(options)
    return string.format(
        "EggBatchHatchSmoke passed: player=%s egg=%s count=%d partialFunds=%d golden=%d cost=%d %s stop=%s restored=%s",
        result.player,
        result.eggType,
        result.hatchCount,
        result.partialFundsCount,
        result.goldenCount,
        result.cost,
        result.currency,
        tostring(result.stopReason),
        tostring(result.restored)
    )
end

return EggBatchHatchSmoke
