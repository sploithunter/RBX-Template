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

    -- Phase 0: alignment / Soul (Halo & Horns) — live through the bus + DataService
    local ring = api:Execute(player, "world.ringInfo", { biome = "earth" })
    report:expect(
        "world.ringInfo earth -> clockwise ice",
        ring.ok and ring.result and ring.result.clockwise == "ice",
        ring.error or "ring info wrong"
    )
    report:expectEqual(
        "world.ringInfo earth -> dichotomy desert",
        ring.result and ring.result.dichotomy,
        "desert"
    )

    api:Execute(player, "game.resetAlignment", {})
    local soul0 = api:Execute(player, "soul.get", {})
    report:expectEqual("soul resets to 0", soul0.result and soul0.result.soul, 0)

    api:Execute(player, "game.conquer", { biome = "earth" }) -- first conquest, delta 0
    report:expectEqual(
        "first conquest keeps soul 0",
        api:Execute(player, "soul.get", {}).result.soul,
        0
    )

    local conquerIce = api:Execute(player, "game.conquer", { biome = "ice" }) -- clockwise: +5
    report:expect("game.conquer ice ok", domainOk(conquerIce), conquerIce.error or "conquer failed")
    local afterIce = api:Execute(player, "soul.get", {})
    report:expectEqual("clockwise conquest -> soul 5", afterIce.result and afterIce.result.soul, 5)
    report:expectEqual(
        "soul 5 reads as halo alignment",
        afterIce.result and afterIce.result.alignment,
        "halo"
    )

    api:Execute(player, "game.resetAlignment", {}) -- cleanup

    -- Phase 1: element-at-hatch (Feature 5) + power calc (Feature 6)
    local granted = api:Execute(player, "game.grantPet", { petType = "bear", variant = "basic" })
    report:expect("game.grantPet ok", domainOk(granted), granted.error or "grant failed")
    report:expectEqual(
        "pet hatched in base layer has neutral element",
        granted.result and granted.result.element,
        "neutral"
    )
    report:expect(
        "power is NOT persisted on the stored pet record",
        granted.result and granted.result.hasPowerField == false,
        "stored record should have no power field"
    )

    -- power arithmetic (bear base_power 10): element resonance by realm
    report:expectEqual(
        "light pet in neutral realm -> base 10",
        api:Execute(player, "pet.power", { petType = "bear", element = "light", realm = "neutral" }).result.power,
        10
    )
    report:expectEqual(
        "light pet in Hell (opposing 1.5x) -> 15",
        api:Execute(player, "pet.power", { petType = "bear", element = "light", realm = "hell" }).result.power,
        15
    )
    report:expectEqual(
        "light pet in Heaven (home 1.2x) -> 12",
        api:Execute(player, "pet.power", { petType = "bear", element = "light", realm = "heaven" }).result.power,
        12
    )
    report:expectEqual(
        "golden variant (1.5x) -> 15 in neutral",
        api:Execute(
            player,
            "pet.power",
            { petType = "bear", variant = "golden", element = "neutral", realm = "neutral" }
        ).result.power,
        15
    )

    -- Phase 2: layers & portals (Feature 3) — server-authoritative ascend
    api:Execute(player, "layer.use", { layer = "base" }) -- ensure base
    api:Execute(player, "game.resetAlignment", {})
    report:expectEqual(
        "current layer defaults to base",
        api:Execute(player, "layer.current", {}).result.layer,
        "base"
    )

    -- soul +20 requires a full clockwise ring tour (5 conquests)
    for _, biome in ipairs({ "earth", "ice", "lava", "desert", "beach" }) do
        api:Execute(player, "game.conquer", { biome = biome })
    end
    report:expectEqual(
        "clockwise ring tour -> soul 20",
        api:Execute(player, "soul.get", {}).result.soul,
        20
    )

    report:expectEqual(
        "heaven_1 rejected without tokens",
        api:Execute(player, "layer.use", { layer = "heaven_1" }).result.reason,
        "insufficient_tokens"
    )
    report:expectEqual(
        "rejected ascend keeps player in base",
        api:Execute(player, "layer.current", {}).result.layer,
        "base"
    )

    api:Execute(player, "test.grantCurrency", { currency = "light_tokens", amount = 150 })
    local beforeTokens = api:Execute(player, "automation.getPlayerState", {}).result.currencies.light_tokens
        or 0
    local ascend = api:Execute(player, "layer.use", { layer = "heaven_1" })
    report:expect("ascend to heaven_1 ok", domainOk(ascend), ascend.error or "ascend failed")
    report:expectEqual(
        "now in heaven_1",
        api:Execute(player, "layer.current", {}).result.layer,
        "heaven_1"
    )
    local afterTokens = api:Execute(player, "automation.getPlayerState", {}).result.currencies.light_tokens
        or 0
    report:expectEqual("ascend deducted 100 light tokens", beforeTokens - afterTokens, 100)

    report:expectEqual(
        "hell_1 rejected with positive soul",
        api:Execute(player, "layer.use", { layer = "hell_1" }).result.reason,
        "soul_wrong_direction"
    )

    -- activated deferral: hatching in Heaven now yields a light element
    report:expectEqual(
        "hatch in Heaven -> light element",
        api:Execute(player, "game.grantPet", { petType = "bear", variant = "basic" }).result.element,
        "light"
    )

    -- activated deferral: pet.power follows the current layer (light bear, heaven home 1.2 -> 12)
    local powHeaven = api:Execute(player, "pet.power", { petType = "bear", element = "light" })
    report:expectEqual(
        "pet.power uses current layer realm (heaven)",
        powHeaven.result and powHeaven.result.realm,
        "heaven"
    )
    report:expectEqual(
        "light bear in heaven (current layer) -> 12",
        powHeaven.result and powHeaven.result.power,
        12
    )

    -- cleanup
    api:Execute(player, "layer.use", { layer = "base" })
    api:Execute(player, "game.resetAlignment", {})

    -- Phase 3: party core (Spirit Form + Active Squad + Stack Pool)
    -- clear any leftover squad for idempotency
    for _, ref in ipairs(api:Execute(player, "squad.get", {}).result.squad or {}) do
        api:Execute(player, "squad.remove", { ref = ref })
    end

    local function inSquad(uid)
        for _, r in ipairs(api:Execute(player, "squad.get", {}).result.squad or {}) do
            if r == uid then
                return true
            end
        end
        return false
    end

    -- a UNIQUE pet (huge) has its own uid + spirit-form state
    local unique =
        api:Execute(player, "game.grantPet", { petType = "bear", variant = "basic", huge = true })
    report:expect("granted a unique pet", domainOk(unique), unique.error or "grant failed")
    local uid = unique.result and unique.result.uid

    report:expect(
        "deploy unique pet to squad",
        domainOk(api:Execute(player, "squad.deploy", { ref = uid })),
        "deploy failed"
    )
    report:expect("squad contains the pet", inSquad(uid), "pet not in squad")
    report:expectEqual(
        "healthy pet is deployable",
        api:Execute(player, "spirit.status", { uid = uid }).result.deployable,
        true
    )

    -- down it -> Spirit Form + auto-return from squad
    report:expect(
        "down unique pet ok",
        domainOk(api:Execute(player, "game.downPet", { uid = uid, tier = "mid_tier" })),
        "down failed"
    )
    report:expect("downed pet auto-returned from squad", not inSquad(uid), "pet still in squad")
    report:expectEqual(
        "downed pet is in Spirit Form",
        api:Execute(player, "spirit.status", { uid = uid }).result.state,
        "Spirit Form"
    )
    report:expectEqual(
        "spirit-form pet cannot redeploy",
        api:Execute(player, "squad.deploy", { ref = uid }).result.reason,
        "pet_in_spirit_form"
    )

    -- instant recharge -> deployable again
    report:expect(
        "instant recharge ok",
        domainOk(api:Execute(player, "game.rechargePet", { uid = uid })),
        "recharge failed"
    )
    report:expectEqual(
        "recharged pet is deployable",
        api:Execute(player, "spirit.status", { uid = uid }).result.deployable,
        true
    )
    report:expect(
        "can redeploy after recharge",
        domainOk(api:Execute(player, "squad.deploy", { ref = uid })),
        "redeploy failed"
    )

    -- stack pool model (live through the service)
    report:expectEqual(
        "linear stack contribution 100 x 24/30 = 80",
        api:Execute(
            player,
            "stack.simulate",
            { total = 30, ready = 24, elapsed = 0, basePower = 100, curve = "linear" }
        ).result.contribution,
        80
    )
    report:expectEqual(
        "stack refills lazily to 29 after 1500s",
        api:Execute(
            player,
            "stack.simulate",
            { total = 30, ready = 24, elapsed = 1500, recharge = 300, basePower = 100 }
        ).result.ready,
        29
    )

    api:Execute(player, "squad.remove", { ref = uid }) -- cleanup

    return HttpService:JSONEncode(report:summary())
end

return AutomationSuite
