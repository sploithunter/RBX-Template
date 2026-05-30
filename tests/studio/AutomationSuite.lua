--[[
    AutomationSuite — Studio integration scenarios driven entirely through the
    GameAPI command bus (no GUI). This is the runtime tier of the remote dev
    pipeline (see docs/wiki/REMOTE_DEV_PIPELINE.md).

    HOW TO RUN (via the Roblox Studio MCP, with the game in Play and the server
    running so _G.RBXTemplateServices exists):

        local suite = require(game.ReplicatedStorage.Tests.studio.AutomationSuite)
        return suite.run()

    Returns a JSON string: { suite, ok, passed, failed, total, cases }. The MCP
    reads it; `ok == true` means every scenario passed. State read back through
    the bus is the source of truth (screenshots are only a backstop).

    Every action goes through GameAPIService:Execute, exercising the exact path
    the GUI/network would — including validation, test-only gating, the
    economy adapter, and the automation.* movement/state commands.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local TestReport = require(ReplicatedStorage.Shared.API.TestReport)

local AutomationSuite = {}

local function getApi()
    local locator = _G.RBXTemplateServices
    return locator and locator:Get("GameAPIService")
end

local function listHasCommand(listResult, name)
    if not listResult.ok or type(listResult.result) ~= "table" then
        return false
    end
    for _, command in ipairs(listResult.result.commands or {}) do
        if command.name == name then
            return true
        end
    end
    return false
end

-- envelope.ok (dispatch) AND envelope.result.ok (domain) both true
local function domainOk(envelope)
    return envelope.ok == true and type(envelope.result) == "table" and envelope.result.ok == true
end

function AutomationSuite.run(opts)
    opts = opts or {}
    local report = TestReport.new("AutomationSuite")

    local api = getApi()
    if not api then
        report:record(
            "locate GameAPIService",
            false,
            "_G.RBXTemplateServices:Get('GameAPIService') is nil — start Play so the server is running"
        )
        return HttpService:JSONEncode(report:summary())
    end

    local player = opts.player or Players:GetPlayers()[1]
    if not player then
        report:record(
            "find test player",
            false,
            "no players in session — start Play (solo) first"
        )
        return HttpService:JSONEncode(report:summary())
    end

    -- 1) Command listing (and automation.* present under Studio gating)
    local list = api:Execute(player, "system.listCommands", {})
    report:expect("system.listCommands dispatches", list.ok, list.error)
    report:expect(
        "listing includes automation.navigateTo",
        listHasCommand(list, "automation.navigateTo"),
        "automation.* not registered — is AutomationService loaded (Studio only)?"
    )

    -- 2) Economy adapter dispatches (delegates to UpgradeService)
    local cost = api:Execute(player, "economy.getUpgradeCost", { upgradeId = "pet_equip_slots" })
    report:expect("economy.getUpgradeCost dispatches", cost.ok, cost.error)

    -- 3) Validation rejects bad args at the boundary
    local badArgs = api:Execute(player, "economy.purchaseUpgrade", { upgradeId = 123 })
    report:expectEqual("purchaseUpgrade rejects non-string id", badArgs.code, "validation_failed")

    -- 4) Test-only gating: a network-origin caller (isTest=false) is forbidden
    local forbidden = api:Execute(
        player,
        "test.grantCurrency",
        { currency = "coins", amount = 1 },
        { isTest = false }
    )
    report:expectEqual("test.grantCurrency forbidden when not test", forbidden.code, "forbidden")

    -- 5) Snapshot → grant → verify → (teleport) → restore round-trip
    local snap = api:Execute(player, "automation.snapshotState", {})
    report:expect("snapshotState ok", domainOk(snap), snap.error or "snapshot failed")
    local snapshotId = snap.ok and snap.result and snap.result.snapshotId

    local before = api:Execute(player, "automation.getPlayerState", {})
    local beforeCoins = (
        before.ok
        and before.result
        and before.result.currencies
        and before.result.currencies.coins
    ) or 0

    local grant = api:Execute(player, "test.grantCurrency", { currency = "coins", amount = 500 })
    report:expect("grantCurrency ok (test context)", domainOk(grant), grant.error or "grant failed")

    local after = api:Execute(player, "automation.getPlayerState", {})
    local afterCoins = (
        after.ok
        and after.result
        and after.result.currencies
        and after.result.currencies.coins
    ) or 0
    report:expect(
        "coins increased by grant",
        afterCoins == beforeCoins + 500,
        `before={beforeCoins} after={afterCoins}`
    )

    -- Optional: exercise the movement service's setup teleport (fast, deterministic)
    local beforePos = before.ok and before.result and before.result.position
    if beforePos then
        local tp = api:Execute(player, "automation.teleportForSetup", {
            x = beforePos.x + 50,
            y = beforePos.y,
            z = beforePos.z,
        })
        report:expect("teleportForSetup ok", domainOk(tp), tp.error or "teleport failed")
    end

    if snapshotId then
        local restore = api:Execute(player, "automation.restoreState", { snapshotId = snapshotId })
        report:expect("restoreState ok", domainOk(restore), restore.error or "restore failed")
        local restored = api:Execute(player, "automation.getPlayerState", {})
        local restoredCoins = (
            restored.ok
            and restored.result
            and restored.result.currencies
            and restored.result.currencies.coins
        ) or 0
        report:expect(
            "coins restored to baseline",
            restoredCoins == beforeCoins,
            `baseline={beforeCoins} restored={restoredCoins}`
        )
    end

    return HttpService:JSONEncode(report:summary())
end

return AutomationSuite
