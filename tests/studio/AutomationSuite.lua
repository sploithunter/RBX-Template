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
    -- Pets actively mine (PetFollowService), so a little currency may accrue in
    -- the grant->read window; require the +500 grant landed, tolerate small income.
    report:expect(
        "coins increased by grant (+500, modulo mining income)",
        afterCoins >= beforeCoins + 500 and afterCoins < beforeCoins + 900,
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
        -- Pets now actively mine (PetFollowService), so a little currency may
        -- accrue between restore and read. The restore must roll back the 500
        -- grant; tolerate small background income (a failed restore = +500).
        report:expect(
            "coins restored to baseline (modulo background mining income)",
            restoredCoins >= beforeCoins and restoredCoins < beforeCoins + 400,
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

    -- isolation: zero any light_tokens left over from prior runs so the
    -- no-tokens rejection is deterministic (the ascend below spends 100 of 150,
    -- leaving residue that would otherwise accumulate across runs).
    local residualLT = api:Execute(player, "automation.getPlayerState", {}).result.currencies.light_tokens
        or 0
    if residualLT > 0 then
        api:Execute(
            player,
            "test.grantCurrency",
            { currency = "light_tokens", amount = -residualLT }
        )
    end

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

    -- Phase 4: Combat (Feature 10) + Focus (Feature 12), live through the bus.

    -- Focus pool: refill to baseline, then cast / reject / sunder.
    api:Execute(player, "focus.regenTick", { elapsed = 1000 }) -- top up to max
    local focus0 = api:Execute(player, "focus.get", {})
    report:expectEqual("focus tops up to max", focus0.result and focus0.result.focus, 100)

    local cast = api:Execute(player, "focus.cast", { cost = 20 })
    report:expectEqual(
        "casting a 20-cost power leaves focus 80",
        cast.result and cast.result.focus,
        80
    )

    local overCast = api:Execute(player, "focus.cast", { cost = 999 })
    report:expectEqual(
        "casting beyond the pool is rejected (insufficient_focus)",
        overCast.result and overCast.result.reason,
        "insufficient_focus"
    )
    report:expectEqual(
        "rejected cast does not spend focus (still 80)",
        api:Execute(player, "focus.get", {}).result.focus,
        80
    )

    local sunder = api:Execute(player, "combat.sunder", { enemyId = "ember_brute" })
    report:expectEqual(
        "a Sundering brute drains 20 focus (80 -> 60)",
        sunder.result and sunder.result.focus,
        60
    )
    api:Execute(player, "focus.regenTick", { elapsed = 1000 }) -- restore

    -- Combat simulation: two strong pets clear the Hell-1 Lava spawner; loot is
    -- biome currency (lava_coins) + Shadow Tokens (Feature 10).
    local sim = api:Execute(player, "combat.simulate", {
        spawner = "hell_1_lava",
        petPowers = { 300, 300 },
    })
    report:expect("combat.simulate dispatches", domainOk(sim), sim.error or "sim failed")
    report:expectEqual(
        "simulated encounter ends (all enemies defeated)",
        sim.result and sim.result.ended,
        true
    )
    report:expectEqual(
        "all 5 spawner enemies defeated",
        sim.result and sim.result.enemiesDefeated,
        5
    )
    report:expectEqual(
        "loot totals biome currency: 4*8 + 30 = 62 lava_coins",
        sim.result and sim.result.loot and sim.result.loot.lava_coins,
        62
    )
    report:expectEqual(
        "loot totals Shadow Tokens: 4*1 + 4 = 8 (Hell drops)",
        sim.result and sim.result.loot and sim.result.loot.shadow_tokens,
        8
    )

    -- Real combat "down" trigger (deferred from Phase 3): an enemy downs a
    -- squad pet -> Spirit Form at the enemy's tier -> auto-return from the squad.
    report:expect("unique pet is deployed before combat-down", inSquad(uid), "pet not deployed")
    local downCombat = api:Execute(player, "combat.downPet", { uid = uid, enemyId = "lava_imp" })
    report:expect(
        "combat.downPet ok",
        domainOk(downCombat),
        downCombat.error or "combat down failed"
    )
    report:expectEqual(
        "downed at the enemy's content tier (lava_imp -> trash_mob)",
        downCombat.result and downCombat.result.tier,
        "trash_mob"
    )
    report:expect(
        "combat-downed pet auto-returned from squad",
        not inSquad(uid),
        "pet still in squad"
    )
    report:expectEqual(
        "combat-downed pet is in Spirit Form",
        api:Execute(player, "spirit.status", { uid = uid }).result.state,
        "Spirit Form"
    )

    api:Execute(player, "game.rechargePet", { uid = uid }) -- cleanup
    api:Execute(player, "squad.remove", { ref = uid }) -- cleanup

    -- issue #4: PetFollowService owns the pet work loop (service-owned movement).
    report:expect(
        "PetFollowService is registered",
        _G.RBXTemplateServices:Get("PetFollowService") ~= nil,
        "PetFollowService not in the locator"
    )
    report:expectEqual("PetFollowService owns movement (flag set)", _G.PetFollowServiceOwned, true)

    local petsFolder = workspace:FindFirstChild("PlayerPets")
        and workspace.PlayerPets:FindFirstChild(player.Name)
    local petModels = {}
    if petsFolder then
        for _, m in ipairs(petsFolder:GetChildren()) do
            if m:IsA("Model") and m.PrimaryPart then
                table.insert(petModels, m)
            end
        end
    end
    report:expect("player has spawned follow pets", #petModels > 0, "no pets spawned")

    local allUnanchored = #petModels > 0
    for _, m in ipairs(petModels) do
        if m.PrimaryPart.Anchored then
            allUnanchored = false
        end
    end
    report:expect(
        "spawned pets are unanchored (movement system drives physics)",
        allUnanchored,
        "a pet is still anchored"
    )

    -- Mining (no regression): pets only mine breakables within the player's leash
    -- (they follow elsewhere). Teleport the player next to a live crystal so a
    -- target is in range, then confirm the service-owned work loop damages it
    -- (HP drops / fully mined / mining income rises).
    local function findById(id)
        local breakables = workspace:FindFirstChild("Game")
            and workspace.Game:FindFirstChild("Breakables")
        if not breakables then
            return nil
        end
        for _, desc in ipairs(breakables:GetDescendants()) do
            if desc.Name == "BreakableID" and desc:IsA("NumberValue") and desc.Value == id then
                return desc.Parent
            end
        end
        return nil
    end

    -- Any crystal with HP > 0, plus its world position.
    local function findAnyCrystal()
        local breakables = workspace:FindFirstChild("Game")
            and workspace.Game:FindFirstChild("Breakables")
        local crystals = breakables and breakables:FindFirstChild("Crystals")
        if not crystals then
            return nil
        end
        for _, desc in ipairs(crystals:GetDescendants()) do
            if desc.Name == "BreakableID" and desc:IsA("NumberValue") then
                local model = desc.Parent
                local hp = model and model:GetAttribute("HP")
                if hp and hp > 0 and model.GetPivot then
                    return model, model:GetPivot().Position
                end
            end
        end
        return nil
    end

    local function coinsNow()
        local s = api:Execute(player, "automation.getPlayerState", {})
        return (s.ok and s.result and s.result.currencies and s.result.currencies.coins) or 0
    end

    local crystal, cpos = findAnyCrystal()
    if crystal and cpos then
        -- stand next to the crystal so BreakableService assigns it + it's in leash
        api:Execute(
            player,
            "automation.teleportForSetup",
            { x = cpos.X + 8, y = cpos.Y, z = cpos.Z }
        )
        task.wait(1.5)
    end

    local startCoins = coinsNow()
    local baselineHp = {} -- breakable -> hp first seen
    local minedProof = false
    local deadline = os.clock() + 6
    while os.clock() < deadline and not minedProof do
        for _, pet in ipairs(petModels) do
            local tid = pet:FindFirstChild("TargetID")
            if tid and tid.Value ~= 0 then
                local b = findById(tid.Value)
                if b then
                    local hp = b:GetAttribute("HP")
                    if hp then
                        if baselineHp[b] == nil then
                            baselineHp[b] = hp
                        elseif hp < baselineHp[b] then
                            minedProof = true
                        end
                    end
                end
            end
        end
        if not minedProof and coinsNow() > startCoins then
            minedProof = true -- pets earned mining rewards
        end
        if not minedProof then
            task.wait(0.5)
        end
    end
    report:expect(
        "service-owned pets mine a nearby breakable (HP drops / income rises)",
        minedProof,
        "no mining activity observed in 6s next to a crystal — mining loop may not be firing"
    )

    return HttpService:JSONEncode(report:summary())
end

return AutomationSuite
