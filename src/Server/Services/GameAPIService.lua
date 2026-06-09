--[[
    GameAPIService  (SCAFFOLD)

    Server-side owner of the template CommandBus — the single boundary every
    gameplay action flows through. See docs/wiki/AUTOMATION_API_DESIGN.md.

    Three callers, one command set:
      • Network  — clients invoke the `GameAPICommand` RemoteFunction. These are
        UNTRUSTED: origin = Network, isTest = false, so test-only commands and
        privileged paths can never be reached from a real client.
      • Automation/tests — call GameAPIService:Execute(player, name, args) on the
        server (via the Studio MCP `execute_luau`, or an in-Studio test). In
        Studio these may run test-only commands.
      • Internal — other services may dispatch through the bus too.

    Adapter pattern
    ---------------
    Handlers are thin adapters that delegate to existing services resolved from
    the `_G.RBXTemplateServices` locator. We do NOT rewrite services — their
    public methods (e.g. UpgradeService:PurchaseUpgrade) already return
    { ok = ..., reason = ... } domain envelopes, which become the bus result.

    STATUS: scaffold. This service is intentionally NOT yet registered in
    src/Server/init.server.lua. Wiring it into the boot loader + migrating the
    GUI/Signals to dispatch through it is the next step, done once we can verify
    against a clean Studio instance. To register (later), add alongside the other
    services:

        loader:RegisterModule(
            "GameAPIService",
            ServerScriptService.Server.Services.GameAPIService,
            { "Logger" }
        )

    and Start() it with the rest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local CommandBus = require(ReplicatedStorage.Shared.API.CommandBus)
local Validators = require(ReplicatedStorage.Shared.API.Validators)
local ElementResonance = require(ReplicatedStorage.Shared.Game.ElementResonance)
local PowerFormula = require(ReplicatedStorage.Shared.Game.PowerFormula)

local GameAPIService = {}
GameAPIService.__index = GameAPIService

local REMOTE_NAME = "GameAPICommand"

function GameAPIService:Init()
    self._logger = self._modules and self._modules.Logger
    self._bus = CommandBus.new({
        onError = function(err, name)
            if self._logger then
                self._logger:Warn("GameAPI command handler error", {
                    command = name,
                    error = tostring(err),
                })
            end
        end,
    })

    self:_registerCommands()
end

function GameAPIService:Start()
    self:_setupNetworkTransport()

    -- AutomationService (Studio-only) registers its automation.* commands into
    -- this bus from its own Start(), via its injected GameAPIService dependency.
    -- We don't pull it here because the _G locator isn't populated until after
    -- the loader's LoadAll() completes.

    if self._logger then
        self._logger:Info("GameAPIService ready", {
            commands = #self._bus:list(),
            studio = RunService:IsStudio(),
        })
    end
end

-- Resolve a loader-registered service from the global locator established in
-- init.server.lua (_G.RBXTemplateServices:Get(name)). The locator's Get() RAISES
-- for unregistered names, so we pcall and return nil — handlers then report
-- service_unavailable instead of crashing.
function GameAPIService:_service(name)
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get(name)
    end)
    return ok and service or nil
end

-- EggService is required directly at boot (not registered in the loader), so it
-- isn't reachable via the locator. Resolve it via a cached direct require.
function GameAPIService:_eggService()
    if self._egg == nil then
        local ok, egg = pcall(function()
            return require(ServerScriptService.Server.Services.EggService)
        end)
        self._egg = (ok and egg) or false
    end
    return self._egg or nil
end

-- Expose the bus for in-Studio tests / introspection.
function GameAPIService:GetBus()
    return self._bus
end

-- Lazily load + cache a config via the locator's ConfigLoader.
function GameAPIService:_config(name)
    self._configs = self._configs or {}
    if self._configs[name] == nil then
        local configLoader = self:_service("ConfigLoader")
        self._configs[name] = (configLoader and configLoader:LoadConfig(name)) or false
    end
    return self._configs[name] or nil
end

--[[
    Programmatic entry point for automation and server-internal callers.

    player : the acting player (or a Studio test double)
    name   : command name
    args   : payload table
    opts   : optional { origin = CommandBus.Origin.*, isTest = boolean }

    isTest defaults to true ONLY in Studio, so test-only commands are reachable
    from the MCP-driven harness but never in a live server.
]]
function GameAPIService:Execute(player, name, args, opts)
    opts = opts or {}
    local isTest = opts.isTest
    if isTest == nil then
        isTest = RunService:IsStudio()
    end

    return self._bus:execute({
        player = player,
        origin = opts.origin or CommandBus.Origin.Automation,
        isTest = isTest,
    }, name, args)
end

function GameAPIService:_setupNetworkTransport()
    -- Replace any stale remote (e.g. after a Rojo hot-sync in Studio).
    local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
    if existing then
        existing:Destroy()
    end

    local remote = Instance.new("RemoteFunction")
    remote.Name = REMOTE_NAME
    remote.OnServerInvoke = function(player, name, args)
        -- Client-originated: never trusted, never a test.
        return self._bus:execute({
            player = player,
            origin = CommandBus.Origin.Network,
            isTest = false,
        }, name, type(args) == "table" and args or {})
    end
    remote.Parent = ReplicatedStorage
end

--[[
    Register the template's command set. Handlers are thin adapters that resolve
    existing services from the locator and delegate to their public methods; arg
    validation uses the shared Validators module. Reads return { ok = true, ... };
    mutations pass the service's own { ok, reason } envelope through as result.
]]
function GameAPIService:_registerCommands()
    local bus = self._bus

    -- ECONOMY -------------------------------------------------------------
    bus:register("economy.getUpgradeCost", {
        description = "Return the cost to take an upgrade to its next level.",
        validate = function(args)
            return Validators.fields(args, { upgradeId = "string" })
        end,
        handler = function(context, args)
            local upgrades = self:_service("UpgradeService")
            if not upgrades then
                return { ok = false, reason = "service_unavailable" }
            end
            local cost, err = upgrades:GetUpgradeCost(context.player, args.upgradeId)
            if not cost then
                return { ok = false, reason = err or "no_cost" }
            end
            return { ok = true, cost = cost }
        end,
    })

    bus:register("economy.purchaseUpgrade", {
        description = "Purchase the next level of a permanent upgrade.",
        validate = function(args)
            return Validators.fields(args, { upgradeId = "string" })
        end,
        handler = function(context, args)
            local upgrades = self:_service("UpgradeService")
            if not upgrades then
                return { ok = false, reason = "service_unavailable" }
            end
            return upgrades:PurchaseUpgrade(context.player, args.upgradeId)
        end,
    })

    -- ZONES ---------------------------------------------------------------
    bus:register("zone.getUnlocked", {
        description = "List the zones the player has unlocked.",
        handler = function(context)
            local zone = self:_service("ZoneService")
            if not zone then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, zones = zone:GetUnlockedZones(context.player) }
        end,
    })

    bus:register("zone.isUnlocked", {
        description = "Whether a given zone is unlocked for the player.",
        validate = function(args)
            return Validators.fields(args, { zoneId = "string" })
        end,
        handler = function(context, args)
            local zone = self:_service("ZoneService")
            if not zone then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, unlocked = zone:IsZoneUnlocked(context.player, args.zoneId) }
        end,
    })

    bus:register("zone.getUnlockRequirement", {
        description = "Return the unlock requirement payload for a zone.",
        validate = function(args)
            return Validators.fields(args, { zoneId = "string" })
        end,
        handler = function(context, args)
            local zone = self:_service("ZoneService")
            if not zone then
                return { ok = false, reason = "service_unavailable" }
            end
            return {
                ok = true,
                requirement = zone:GetUnlockRequirement(context.player, args.zoneId),
            }
        end,
    })

    bus:register("zone.unlock", {
        description = "Attempt to unlock a zone (server-authoritative).",
        validate = function(args)
            return Validators.fields(args, { zoneId = "string" })
        end,
        handler = function(context, args)
            local zone = self:_service("ZoneService")
            if not zone then
                return { ok = false, reason = "service_unavailable" }
            end
            return zone:UnlockZone(context.player, args.zoneId)
        end,
    })

    bus:register("zone.travel", {
        description = "Travel the player to a target zone (server-authoritative).",
        validate = function(args)
            return Validators.fields(args, { zoneId = "string" })
        end,
        handler = function(context, args)
            local zone = self:_service("ZoneService")
            if not zone then
                return { ok = false, reason = "service_unavailable" }
            end
            return zone:TravelToZone(context.player, args.zoneId)
        end,
    })

    -- EGGS (read / no-mutation) ------------------------------------------
    bus:register("egg.getMaxHatchCount", {
        description = "The configured maximum hatch count (1..99).",
        handler = function()
            local egg = self:_eggService()
            if not egg then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, maxHatch = egg:GetMaxHatchCount() }
        end,
    })

    bus:register("egg.simulateHatch", {
        description = "Preview hatch odds/cost for a request WITHOUT mutating state.",
        validate = function(args)
            return Validators.fields(args, {
                eggType = "string",
                count = { type = "int", min = 1, max = 99, optional = true },
            })
        end,
        handler = function(context, args)
            local egg = self:_eggService()
            if not egg then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, simulation = egg:SimulateHatchBatch(context.player, args) }
        end,
    })

    bus:register("egg.getHatchHistory", {
        description = "Recent hatch history for the player.",
        validate = function(args)
            return Validators.fields(args, {
                limit = { type = "int", min = 1, max = 200, optional = true },
            })
        end,
        handler = function(context, args)
            local egg = self:_eggService()
            if not egg then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, history = egg:GetHatchHistory(context.player, args.limit) }
        end,
    })

    -- INVENTORY (read) ---------------------------------------------------
    bus:register("inventory.get", {
        description = "Return the player's items in a bucket.",
        validate = function(args)
            return Validators.fields(args, { bucket = "string" })
        end,
        handler = function(context, args)
            local inventory = self:_service("InventoryService")
            if not inventory then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, items = inventory:GetInventory(context.player, args.bucket) }
        end,
    })

    bus:register("inventory.slots", {
        description = "Return used/total slot counts for a bucket.",
        validate = function(args)
            return Validators.fields(args, { bucket = "string" })
        end,
        handler = function(context, args)
            local inventory = self:_service("InventoryService")
            if not inventory then
                return { ok = false, reason = "service_unavailable" }
            end
            return {
                ok = true,
                used = inventory:GetUsedSlots(context.player, args.bucket),
                total = inventory:GetTotalSlots(context.player, args.bucket),
            }
        end,
    })

    -- WORLD / ALIGNMENT (Halo & Horns) -----------------------------------
    bus:register("world.ringInfo", {
        description = "Ring topology: biome count, and neighbors/theme/dichotomy for a biome.",
        validate = function(args)
            return Validators.fields(args, { biome = { type = "string", optional = true } })
        end,
        handler = function(_, args)
            local alignment = self:_service("AlignmentService")
            if not alignment then
                return { ok = false, reason = "service_unavailable" }
            end
            local topo = alignment:GetTopology()
            local info = { ok = true, count = topo:count() }
            if type(args.biome) == "string" and topo:has(args.biome) then
                info.biome = args.biome
                info.theme = topo:theme(args.biome)
                info.clockwise = topo:clockwiseNeighbor(args.biome)
                info.counterclockwise = topo:counterclockwiseNeighbor(args.biome)
                info.dichotomy = topo:dichotomyPartner(args.biome)
                info.currency = topo:currency(args.biome)
            end
            return info
        end,
    })

    bus:register("soul.get", {
        description = "The acting player's Soul value, last conquered biome, and alignment.",
        handler = function(context)
            local alignment = self:_service("AlignmentService")
            if not alignment then
                return { ok = false, reason = "service_unavailable" }
            end
            local state = alignment:GetState(context.player)
            if not state then
                return { ok = false, reason = "data_not_loaded" }
            end
            return {
                ok = true,
                soul = state.soul,
                last_conquered_biome = state.last_conquered_biome,
                alignment = state.alignment,
            }
        end,
    })

    -- PETS / POWER (Halo & Horns, Feature 6) -----------------------------
    -- Runtime power = base x variant x level x element-resonance (never persisted).
    bus:register("pet.power", {
        description = "Compute a pet's runtime power for a context (element resonance by realm).",
        validate = function(args)
            return Validators.fields(args, {
                petType = "string",
                variant = { type = "string", optional = true },
                element = { type = "string", optional = true },
                realm = { type = "string", optional = true },
                levelMultiplier = { type = "number", optional = true },
            })
        end,
        handler = function(context, args)
            local pets = self:_config("pets")
            local elements = self:_config("elements")
            if not pets or not pets.getPet or not elements then
                return { ok = false, reason = "config_unavailable" }
            end
            local def = pets.getPet(args.petType, args.variant or "basic")
            if not def then
                return { ok = false, reason = "unknown_pet" }
            end
            local element = args.element or "neutral"
            -- Default the realm to the player's CURRENT layer (power follows where
            -- the player is — Feature 6 dynamic recalculation). Explicit realm wins.
            local realm = args.realm
            if realm == nil then
                local layersConfig = self:_config("layers")
                local layerService = self:_service("LayerService")
                local current = (layerService and layerService:GetCurrentLayer(context.player))
                    or "base"
                realm = (
                    layersConfig
                    and layersConfig.realm_alignment
                    and layersConfig.realm_alignment[current]
                ) or "neutral"
            end
            local elementMult = ElementResonance.multiplier(element, realm, elements)
            local power = PowerFormula.compute({
                base = def.base_power or 1,
                variant = def.power_multiplier or 1,
                level = tonumber(args.levelMultiplier) or 1,
                element = elementMult,
            })
            return {
                ok = true,
                power = power,
                base = def.base_power,
                variant = def.power_multiplier,
                element = element,
                realm = realm,
                elementMultiplier = elementMult,
            }
        end,
    })

    -- LAYERS (Halo & Horns, Feature 3) -----------------------------------
    bus:register("layer.current", {
        description = "The player's current layer.",
        handler = function(context)
            local layers = self:_service("LayerService")
            if not layers then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, layer = layers:GetCurrentLayer(context.player) }
        end,
    })

    bus:register("layer.accessible", {
        description = "Layers the player can currently access (Soul + tokens).",
        handler = function(context)
            local layers = self:_service("LayerService")
            if not layers then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, layers = layers:AccessibleLayers(context.player) }
        end,
    })

    bus:register("layer.use", {
        description = "Ascend/descend to a layer (server-authoritative Soul + token cost).",
        validate = function(args)
            return Validators.fields(args, { layer = "string" })
        end,
        handler = function(context, args)
            local layers = self:_service("LayerService")
            if not layers then
                return { ok = false, reason = "service_unavailable" }
            end
            return layers:UseLayer(context.player, args.layer)
        end,
    })

    -- PARTY: active squad / spirit form / stack pool (Phase 3) -----------
    bus:register("squad.get", {
        description = "The player's active squad (array of pet refs).",
        handler = function(context)
            local s = self:_service("ActiveSquadService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, squad = s:Get(context.player) }
        end,
    })

    bus:register("squad.deploy", {
        description = "Deploy a pet (uid/stack key) to the active squad.",
        validate = function(args)
            return Validators.fields(args, { ref = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("ActiveSquadService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Deploy(context.player, args.ref)
        end,
    })

    bus:register("squad.remove", {
        description = "Remove a pet from the active squad.",
        validate = function(args)
            return Validators.fields(args, { ref = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("ActiveSquadService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Remove(context.player, args.ref)
        end,
    })

    bus:register("squad.swap", {
        description = "Swap one active-squad pet for another (in-combat cooldown).",
        validate = function(args)
            return Validators.fields(args, {
                outRef = "string",
                inRef = "string",
                inCombat = { type = "boolean", optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("ActiveSquadService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Swap(context.player, args.outRef, args.inRef, args.inCombat)
        end,
    })

    bus:register("spirit.status", {
        description = "Spirit-form state + deployability of a unique pet.",
        validate = function(args)
            return Validators.fields(args, {
                uid = "string",
                inHeaven = { type = "boolean", optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("SpiritFormService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Status(context.player, args.uid, args.inHeaven)
        end,
    })

    bus:register("stack.simulate", {
        description = "Run the stacked-pet pool model (refresh + contribution).",
        validate = function(args)
            return Validators.fields(args, {
                total = { type = "int", min = 0 },
                ready = { type = "int", min = 0 },
                elapsed = { type = "int", min = 0, optional = true },
                recharge = { type = "number", optional = true },
                basePower = { type = "number", optional = true },
                curve = { type = "string", optional = true },
            })
        end,
        handler = function(_, args)
            local s = self:_service("StackPoolService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Simulate(args)
        end,
    })

    bus:register("focus.get", {
        description = "The player's Focus pool (current + max).",
        handler = function(context)
            local f = self:_service("FocusService")
            if not f then
                return { ok = false, reason = "service_unavailable" }
            end
            return f:Get(context.player)
        end,
    })

    bus:register("combat.simulate", {
        description = "Deterministic full-fight resolution (auto-target, damage, loot, sundering).",
        validate = function(args)
            return Validators.fields(args, {
                spawner = { type = "string", optional = true },
                partySize = { type = "int", min = 1, optional = true },
                petPowers = { type = "table", optional = true },
                buff = { type = "number", optional = true },
                maxRounds = { type = "int", min = 1, optional = true },
                focusStart = { type = "number", optional = true },
            })
        end,
        handler = function(_, args)
            local combat = self:_service("CombatService")
            if not combat then
                return { ok = false, reason = "service_unavailable" }
            end
            return combat:Simulate(args)
        end,
    })

    bus:register("archetype.get", {
        description = "The player's archetype + its available power pool.",
        handler = function(context)
            local s = self:_service("ArchetypeService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:GetState(context.player)
        end,
    })

    bus:register("archetype.list", {
        description = "All selectable archetypes.",
        handler = function()
            local s = self:_service("ArchetypeService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:List()
        end,
    })

    bus:register("archetype.select", {
        description = "Select the player's archetype (one-time; respec to change).",
        validate = function(args)
            return Validators.fields(args, { archetype = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("ArchetypeService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Select(context.player, args.archetype)
        end,
    })

    bus:register("power.get", {
        description = "The player's selected powers + pending selections + pool.",
        validate = function(args)
            return Validators.fields(args, { level = { type = "int", min = 1, optional = true } })
        end,
        handler = function(context, args)
            local s = self:_service("PowerService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            -- level override honored only in test context (avoids unlocking early)
            return s:GetState(context.player, context.isTest and args.level or nil)
        end,
    })

    bus:register("power.cast", {
        description = "Cast a power immediately by id (enforces its cooldown). For tools/tests.",
        validate = function(args)
            return Validators.fields(args, { powerId = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("PowerService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Cast(context.player, args.powerId)
        end,
    })

    bus:register("power.select", {
        description = "Select a power at level-up (archetype-gated, one per selection level).",
        validate = function(args)
            return Validators.fields(args, {
                powerId = "string",
                level = { type = "int", min = 1, optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("PowerService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Select(context.player, args.powerId, context.isTest and args.level or nil)
        end,
    })

    bus:register("augment.get", {
        description = "The player's augmentation slots + granted/unallocated counts.",
        validate = function(args)
            return Validators.fields(args, { level = { type = "int", min = 1, optional = true } })
        end,
        handler = function(context, args)
            local s = self:_service("AugmentationService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:GetState(context.player, context.isTest and args.level or nil)
        end,
    })

    bus:register("augment.place", {
        description = "Place one empty enhancement slot onto an unlocked power.",
        validate = function(args)
            return Validators.fields(args, {
                powerId = "string",
                slotType = { type = "string", optional = true }, -- accepted-but-ignored (slots are empty)
                level = { type = "int", min = 1, optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("AugmentationService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Place(
                context.player,
                args.powerId,
                args.slotType,
                context.isTest and args.level or nil
            )
        end,
    })

    bus:register("levelup.getState", {
        description = "Claim state for the level-up sequence: claimed/earned/pending + next reward.",
        handler = function(context)
            local s = self:_service("PlayerProgressionService")
            if not s or not s.GetClaimState then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, state = s:GetClaimState(context.player) }
        end,
    })

    bus:register("levelup.claim", {
        description = "Claim ONE pending level (advances ClaimedLevel, pays rewards, fires sequence).",
        validate = function(args)
            return Validators.fields(args, {
                expectedLevel = { type = "int", min = 1, optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("PlayerProgressionService")
            if not s or not s.ClaimLevel then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:ClaimLevel(context.player, args.expectedLevel)
        end,
    })

    bus:register("levelup.commit", {
        description = "Atomically CLAIM the next level + apply the chosen power/slots (all-or-nothing).",
        validate = function(args)
            return Validators.fields(args, {
                expectedLevel = { type = "int", min = 1, optional = true },
                powerId = { type = "string", optional = true },
                picks = { type = "table", optional = true },
                slots = { type = "table", optional = true },
            })
        end,
        handler = function(context, args)
            local prog = self:_service("PlayerProgressionService")
            local powerSvc = self:_service("PowerService")
            local augSvc = self:_service("AugmentationService")
            local dataSvc = self:_service("DataService")
            if not (prog and powerSvc and augSvc and dataSvc) then
                return { ok = false, reason = "service_unavailable" }
            end
            local state = prog:GetClaimState(context.player)
            if state.atMax or not state.canClaim then
                return { ok = false, reason = "nothing_to_claim", state = state }
            end
            local newLevel = state.nextLevel
            if args.expectedLevel and args.expectedLevel ~= newLevel then
                return { ok = false, reason = "stale_level", state = state }
            end
            local entry = state.nextEntry or {}

            if entry.powerPick then
                local powerId = args.powerId or (args.picks and args.picks[1])
                if not powerId then
                    return { ok = false, reason = "pick_required" }
                end
                -- PRE-validate at the post-claim level so claim+select can't half-apply.
                local ok, reason = powerSvc:CanSelectAtLevel(context.player, powerId, newLevel)
                if not ok then
                    return { ok = false, reason = reason or "invalid_pick" }
                end
                prog:ClaimLevel(context.player, state.claimedLevel, true) -- silent: menu owns reveal
                powerSvc:Select(context.player, powerId)
            elseif (tonumber(entry.slots) or 0) > 0 then
                local slots = args.slots or {}
                if #slots < entry.slots then
                    return { ok = false, reason = "slots_required" }
                end
                -- PRE-validate: every slot target is an OWNED power (placement capacity is client-gated
                -- + AugmentationService.Place is the backstop).
                local data = dataSvc:GetData(context.player)
                local owned = {}
                for _, id in ipairs((data and data.Powers) or {}) do
                    owned[id] = true
                end
                for i = 1, entry.slots do
                    if not owned[slots[i]] then
                        return { ok = false, reason = "slot_target_not_owned" }
                    end
                end
                prog:ClaimLevel(context.player, state.claimedLevel, true)
                for i = 1, entry.slots do
                    augSvc:Place(context.player, slots[i])
                end
            else
                prog:ClaimLevel(context.player, state.claimedLevel, true) -- no-choice level (rare)
            end
            return { ok = true, state = prog:GetClaimState(context.player) }
        end,
    })

    bus:register("levelup.bank", {
        description = "[admin] Bank earned levels WITHOUT claiming (test the claim flow). Admin/Studio only.",
        validate = function(args)
            return Validators.fields(args, { count = { type = "int", min = 1, optional = true } })
        end,
        handler = function(context, args)
            -- Client-callable but admin-gated: trusted in test context, else require the IsAdmin attr.
            local isAdmin = context.isTest
                or (context.player and context.player:GetAttribute("IsAdmin") == true)
            if not isAdmin then
                return { ok = false, reason = "not_admin" }
            end
            local s = self:_service("PlayerProgressionService")
            if not s or not s.BankLevels then
                return { ok = false, reason = "service_unavailable" }
            end
            return { ok = true, state = s:BankLevels(context.player, args.count or 1) }
        end,
    })

    bus:register("levelup.grantXp", {
        description = "[admin] Fast-forward: XP to ~98% of next level + the next gate's coins. Admin/Studio only.",
        handler = function(context)
            local isAdmin = context.isTest
                or (context.player and context.player:GetAttribute("IsAdmin") == true)
            if not isAdmin then
                return { ok = false, reason = "not_admin" }
            end
            local s = self:_service("PlayerProgressionService")
            if not s or not s.GrantAlmostLevel then
                return { ok = false, reason = "service_unavailable" }
            end
            local state = s:GrantAlmostLevel(context.player)
            -- Also drop 100k of EVERY area coin so any gate is affordable without grinding it
            -- (overshoot is fine for coins — dev QoL). Premium/tokens (gems, light/shadow) excluded.
            local dataSvc = self:_service("DataService")
            local AREA_COINS = {
                "coins",
                "crystals",
                "grass_coins",
                "ice_coins",
                "lava_coins",
                "desert_coins",
                "beach_coins",
            }
            if dataSvc and dataSvc.AddCurrency then
                for _, c in ipairs(AREA_COINS) do
                    dataSvc:AddCurrency(context.player, c, 100000, "admin_fast_forward")
                end
            end
            return { ok = true, state = state }
        end,
    })

    bus:register("levelup.resetRun", {
        description = "[admin] Wipe powers/slots + drop to L1 (keeps origin) to retest the climb. Admin/Studio only.",
        handler = function(context)
            local isAdmin = context.isTest
                or (context.player and context.player:GetAttribute("IsAdmin") == true)
            if not isAdmin then
                return { ok = false, reason = "not_admin" }
            end
            local arche = self:_service("ArchetypeService")
            local prog = self:_service("PlayerProgressionService")
            local dataSvc = self:_service("DataService")
            if not (arche and prog and dataSvc) then
                return { ok = false, reason = "service_unavailable" }
            end
            -- true new-player reset: clear Powers/Slots/Hotbar AND the origin (re-chosen at L5).
            arche:Respec(context.player, nil)
            prog:SetLevel(context.player, 1)
            local pwr = self:_service("PowerService")
            if pwr and pwr.ReapplyPassives then
                pwr:ReapplyPassives(context.player) -- clear always-on buffs from the wiped powers
            end
            return { ok = true, archetype = nil, state = prog:GetClaimState(context.player) }
        end,
    })

    bus:register("hotbar.get", {
        description = "The player's hotbar bindings (archetype defaults if unset).",
        handler = function(context)
            local s = self:_service("HotbarService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:GetState(context.player)
        end,
    })

    bus:register("hotbar.rebind", {
        description = "Bind/clear a hotbar slot ({type,target} or omit bind to clear).",
        validate = function(args)
            return Validators.fields(args, {
                slot = { type = "int", min = 1 },
                bind = { type = "table", optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("HotbarService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Rebind(context.player, args.slot, args.bind)
        end,
    })

    bus:register("roster.list", {
        description = "The player's named rosters.",
        handler = function(context)
            local s = self:_service("RosterService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:List(context.player)
        end,
    })

    bus:register("roster.create", {
        description = "Create/replace a named roster (max_to_deploy clamps to squad cap).",
        validate = function(args)
            return Validators.fields(args, {
                name = "string",
                orderedPets = "table",
                maxToDeploy = { type = "int", min = 0, optional = true },
                injuryRule = { type = "string", optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("RosterService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Create(
                context.player,
                args.name,
                args.orderedPets,
                args.maxToDeploy,
                args.injuryRule
            )
        end,
    })

    bus:register("roster.invoke", {
        description = "Deploy a roster into the active squad (per its injury rule).",
        validate = function(args)
            return Validators.fields(args, { name = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("RosterService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Invoke(context.player, args.name)
        end,
    })

    bus:register("party.get", {
        description = "The player's party state (members + size).",
        handler = function(context)
            local s = self:_service("PartyService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:GetState(context.player)
        end,
    })

    bus:register("party.simulate", {
        description = "Group math: difficulty scaling, equal loot split, damage attribution.",
        validate = function(args)
            return Validators.fields(args, {
                baseHp = { type = "number", optional = true },
                partySize = { type = "int", min = 1, optional = true },
                loot = { type = "table", optional = true },
                contributions = { type = "table", optional = true },
            })
        end,
        handler = function(_, args)
            local s = self:_service("PartyService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Simulate(args)
        end,
    })

    bus:register("trade.canAdd", {
        description = "Whether an item may be offered in a trade (pets yes unless locked; currencies no).",
        validate = function(args)
            return Validators.fields(args, {
                category = "string",
                id = { type = "string", optional = true },
                locked = { type = "boolean", optional = true },
            })
        end,
        handler = function(_, args)
            local s = self:_service("TradeService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:CanAdd(args.category, { id = args.id, locked = args.locked })
        end,
    })

    -- Two-player escrow trade flow (Feature 19 / Phase 10). Live state is pushed
    -- to both clients via the TradeUpdate RemoteEvent; these are the actions.
    local function tradeAction(method)
        return function(context, args)
            local s = self:_service("TradeService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return method(s, context.player, args)
        end
    end

    bus:register("trade.players", {
        description = "List other players in the server (trade targets).",
        handler = tradeAction(function(s, player)
            return s:ListPlayers(player)
        end),
    })
    bus:register("trade.request", {
        description = "Send a trade request to another player.",
        validate = function(args)
            return Validators.fields(args, { targetUserId = "int" })
        end,
        handler = tradeAction(function(s, player, args)
            return s:Request(player, args.targetUserId)
        end),
    })
    bus:register("trade.respond", {
        description = "Accept or decline an incoming trade request.",
        validate = function(args)
            return Validators.fields(args, { fromUserId = "int", accept = "boolean" })
        end,
        handler = tradeAction(function(s, player, args)
            return s:Respond(player, args.fromUserId, args.accept)
        end),
    })
    bus:register("trade.add", {
        description = "Offer a pet (moves it into escrow).",
        validate = function(args)
            return Validators.fields(args, { uid = "string" })
        end,
        handler = tradeAction(function(s, player, args)
            return s:Add(player, args.uid)
        end),
    })
    bus:register("trade.remove", {
        description = "Pull a pet back out of your offer (returns it from escrow).",
        validate = function(args)
            return Validators.fields(args, { uid = "string" })
        end,
        handler = tradeAction(function(s, player, args)
            return s:Remove(player, args.uid)
        end),
    })
    bus:register("trade.confirm", {
        description = "Confirm your side; both confirmed executes the swap.",
        handler = tradeAction(function(s, player)
            return s:Confirm(player)
        end),
    })
    bus:register("trade.cancel", {
        description = "Cancel the active trade (refunds escrow to both sides).",
        handler = tradeAction(function(s, player)
            return s:Cancel(player)
        end),
    })
    bus:register("trade.state", {
        description = "The player's current trade session view (poll fallback).",
        handler = tradeAction(function(s, player)
            return s:GetState(player)
        end),
    })
    bus:register("trade.myPets", {
        description = "The player's tradeable pets (for the offer picker).",
        handler = tradeAction(function(s, player)
            return s:ListMyPets(player)
        end),
    })

    bus:register("fusion.canFuse", {
        description = "Whether two pet elements may be fused (one Light + one Shadow -> Chaotic).",
        validate = function(args)
            return Validators.fields(args, { elemA = "string", elemB = "string" })
        end,
        handler = function(_, args)
            local s = self:_service("FusionService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:CanFuse(args.elemA, args.elemB)
        end,
    })

    -- REWARD SPINE (Quests / Daily / Shop / Rewards) ----------------------
    bus:register("quest.list", {
        description = "List quests with progress + claimable state.",
        handler = function(context)
            local s = self:_service("QuestService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:List(context.player)
        end,
    })
    bus:register("quest.claim", {
        description = "Claim a quest's reward (gated by its condition + claim policy).",
        validate = function(args)
            return Validators.fields(args, { questId = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("QuestService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Claim(context.player, args.questId)
        end,
    })
    bus:register("daily.status", {
        description = "Daily login streak status (claimable today? current/next streak).",
        validate = function(args)
            return Validators.fields(args, { day = { type = "int", optional = true } })
        end,
        handler = function(context, args)
            local s = self:_service("DailyService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Status(context.player, context.isTest and args.day or nil)
        end,
    })
    bus:register("daily.claim", {
        description = "Claim today's daily login reward and advance the streak.",
        validate = function(args)
            return Validators.fields(args, { day = { type = "int", optional = true } })
        end,
        handler = function(context, args)
            local s = self:_service("DailyService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Claim(context.player, context.isTest and args.day or nil)
        end,
    })
    bus:register("shop.list", {
        description = "List shop offers with affordability + purchase limits.",
        handler = function(context)
            local s = self:_service("ShopService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:List(context.player)
        end,
    })
    bus:register("shop.purchase", {
        description = "Purchase a shop offer (spend cost, grant reward bundle).",
        validate = function(args)
            return Validators.fields(args, { offerId = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("ShopService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Purchase(context.player, args.offerId)
        end,
    })
    bus:register("rewards.summary", {
        description = "Aggregate claimable count across quests + daily (the menu badges).",
        handler = function(context)
            local quest = self:_service("QuestService")
            local daily = self:_service("DailyService")
            local questPending = quest and quest:Pending(context.player) or 0
            local dailyStatus = daily and daily:Status(context.player) or { claimable = false }
            local dailyPending = dailyStatus.claimable and 1 or 0
            return {
                ok = true,
                quest = questPending,
                daily = dailyPending,
                total = questPending + dailyPending,
            }
        end,
    })

    -- SYSTEM --------------------------------------------------------------
    bus:register("system.listCommands", {
        description = "List every command the bus exposes to this caller.",
        handler = function(context)
            local out = {}
            for _, entry in ipairs(bus:list()) do
                -- Hide test-only commands from non-test callers.
                if not entry.testOnly or context.isTest then
                    table.insert(out, entry)
                end
            end
            return { ok = true, commands = out }
        end,
    })

    if RunService:IsStudio() then
        self:_registerTestCommands()
    end
end

-- Test-only commands: setup affordances for the automation harness. Gated by
-- both RunService:IsStudio() (not registered in production) AND the bus's
-- testOnly flag (context.isTest required), so there is no path to them from a
-- live client.
function GameAPIService:_registerTestCommands()
    self._bus:register("test.grantCurrency", {
        description = "[test] Add currency to a player for test setup.",
        testOnly = true,
        validate = function(args)
            if type(args.currency) ~= "string" then
                return false, "currency must be a string"
            end
            if type(args.amount) ~= "number" then
                return false, "amount must be a number"
            end
            return true
        end,
        handler = function(context, args)
            local data = self:_service("DataService")
            if not data then
                return { ok = false, reason = "service_unavailable" }
            end
            data:AddCurrency(context.player, args.currency, args.amount, "automation_test_grant")
            return { ok = true, currency = args.currency, amount = args.amount }
        end,
    })

    -- Reset alignment to a fresh state (for repeatable tests).
    self._bus:register("game.resetAlignment", {
        description = "[test] Reset the player's Soul/conquest state to fresh.",
        testOnly = true,
        handler = function(context)
            local alignment = self:_service("AlignmentService")
            if not alignment then
                return { ok = false, reason = "service_unavailable" }
            end
            return alignment:Reset(context.player)
        end,
    })

    -- Grant a pet and return its record (proves element-at-hatch, Feature 5).
    self._bus:register("game.grantPet", {
        description = "[test] Grant a pet to the player; returns the record incl. element.",
        validate = function(args)
            return Validators.fields(args, {
                petType = "string",
                variant = { type = "string", optional = true },
                element = { type = "string", optional = true },
                huge = { type = "boolean", optional = true },
            })
        end,
        handler = function(context, args)
            local grant = self:_service("PetGrantService")
            if not grant then
                return { ok = false, reason = "service_unavailable" }
            end
            local result = grant:GrantPet(context.player, {
                petType = args.petType,
                variant = args.variant or "basic",
                element = args.element, -- nil -> from layer (base -> neutral)
                huge = args.huge, -- huge -> a unique pet record (own uid)
                source = "phase1_e2e",
            })
            if not result.ok then
                return { ok = false, reason = result.error or "grant_failed" }
            end
            local petData = result.petData or {}
            return {
                ok = true,
                uid = result.uid,
                element = petData.element,
                variant = petData.variant,
                hasPowerField = petData.power ~= nil, -- should be false (power not persisted on the stored record)
            }
        end,
    })

    -- Down / recharge a unique pet (real combat down triggers arrive in Phase 4).
    self._bus:register("game.downPet", {
        description = "[test] Down a unique pet (Spirit Form); auto-returns from squad.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, {
                uid = "string",
                tier = { type = "string", optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("SpiritFormService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Down(context.player, args.uid, args.tier or "mid_tier")
        end,
    })

    -- Reuse an existing unique (huge) test pet of this type, or grant one only if
    -- none exists — so repeated test runs don't accumulate Huge Bears in the
    -- profile. Returns a uid suitable for the Spirit Form / squad tests.
    self._bus:register("game.getOrGrantUniquePet", {
        description = "[test] Reuse an existing huge test pet of this type, or grant one (no accumulation).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { petType = "string" })
        end,
        handler = function(context, args)
            local inventory = self:_service("InventoryService")
            if inventory then
                local bucket = inventory:GetInventory(context.player, "pets")
                local items = bucket and bucket.items
                if items then
                    for uid, rec in pairs(items) do
                        if type(rec) == "table" and rec.huge == true and rec.id == args.petType then
                            return { ok = true, uid = uid, reused = true }
                        end
                    end
                end
            end
            local grant = self:_service("PetGrantService")
            if not grant then
                return { ok = false, reason = "service_unavailable" }
            end
            local result = grant:GrantPet(context.player, {
                petType = args.petType,
                variant = "basic",
                huge = true,
                source = "phase3_e2e",
            })
            if not result.ok then
                return { ok = false, reason = result.error or "grant_failed" }
            end
            return { ok = true, uid = result.uid, reused = false }
        end,
    })

    self._bus:register("game.rechargePet", {
        description = "[test] Instant-recharge a unique pet (clear Spirit Form).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { uid = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("SpiritFormService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:InstantRecharge(context.player, args.uid)
        end,
    })

    -- Focus: cast a power (spend Focus) / regenerate (Feature 12).
    self._bus:register("focus.cast", {
        description = "[test] Spend Focus to cast a power of the given cost.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { cost = { type = "number", min = 0 } })
        end,
        handler = function(context, args)
            local f = self:_service("FocusService")
            if not f then
                return { ok = false, reason = "service_unavailable" }
            end
            return f:Cast(context.player, args.cost)
        end,
    })

    self._bus:register("focus.regenTick", {
        description = "[test] Regenerate Focus over an elapsed number of seconds.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { elapsed = { type = "number", min = 0 } })
        end,
        handler = function(context, args)
            local f = self:_service("FocusService")
            if not f then
                return { ok = false, reason = "service_unavailable" }
            end
            return f:RegenTick(context.player, args.elapsed)
        end,
    })

    -- Combat: a Sundering enemy attack drains the player's Focus (Feature 10/12).
    self._bus:register("combat.sunder", {
        description = "[test] Apply an enemy's Sundering Focus drain to the player.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { enemyId = "string" })
        end,
        handler = function(context, args)
            local combat = self:_service("CombatService")
            if not combat then
                return { ok = false, reason = "service_unavailable" }
            end
            return combat:SunderPlayer(context.player, args.enemyId)
        end,
    })

    -- Combat: credit a defeated enemy's loot (biome currency + Shadow Tokens).
    self._bus:register("combat.awardLoot", {
        description = "[test] Award a defeated enemy's drop table to the player.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { enemyId = "string" })
        end,
        handler = function(context, args)
            local combat = self:_service("CombatService")
            if not combat then
                return { ok = false, reason = "service_unavailable" }
            end
            return combat:AwardLoot(context.player, args.enemyId)
        end,
    })

    -- Combat: the real "down a pet" trigger -> Spirit Form -> squad auto-return.
    self._bus:register("combat.downPet", {
        description = "[test] An enemy downs a pet (Spirit Form at the enemy's tier).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { uid = "string", enemyId = "string" })
        end,
        handler = function(context, args)
            local combat = self:_service("CombatService")
            if not combat then
                return { ok = false, reason = "service_unavailable" }
            end
            return combat:DownPetInCombat(context.player, args.uid, args.enemyId)
        end,
    })

    -- Combat: spawn real enemies in front of the player (dev/test). Studio-gated rather than
    -- testOnly so it's reachable over the player-facing remote (MCP live verification); a no-op
    -- in production. Spawns `count` of `enemyId` (clustered ~16 studs ahead) for AoE testing.
    self._bus:register("combat.spawnEnemy", {
        description = "[studio] Spawn real combat enemies in front of the player for live testing.",
        validate = function(args)
            return Validators.fields(args, {
                enemyId = { type = "string", optional = true },
                count = { type = "int", min = 1, max = 10, optional = true },
                spread = { type = "number", min = 0, optional = true }, -- ring radius (studs)
                forward = { type = "number", optional = true }, -- extra forward distance (far control)
            })
        end,
        handler = function(context, args)
            if not game:GetService("RunService"):IsStudio() then
                return { ok = false, reason = "studio_only" }
            end
            local enemyService = self:_service("EnemyService")
            if not enemyService then
                return { ok = false, reason = "service_unavailable" }
            end
            local count = math.clamp(tonumber(args.count) or 1, 1, 10)
            -- spread the spawns around a ring so they don't stack (default ~6 studs for count>1);
            -- `forward` pushes the whole group further out (for an out-of-AoE-range control dummy).
            local spread = tonumber(args.spread) or (count > 1 and 6 or 0)
            local fwdBase = tonumber(args.forward) or 0
            local spawned, last = 0, nil
            for i = 1, count do
                local angle = (count > 1) and ((i - 1) / count) * 2 * math.pi or 0
                local off = {
                    forward = fwdBase + math.cos(angle) * spread,
                    right = math.sin(angle) * spread,
                }
                last = enemyService:SpawnEnemy(context.player, args.enemyId or "lava_imp", off)
                if type(last) == "table" and last.ok ~= false then
                    spawned += 1
                end
            end
            return { ok = true, spawned = spawned, sample = last }
        end,
    })

    -- Combat: clear all live enemies (dev/test reset). Studio-gated. Sets each enemy's HP to 0 so
    -- the normal defeat path runs (cleanup + removal); no-op in production.
    self._bus:register("combat.clearEnemies", {
        description = "[studio] Remove all live combat enemies (dev/test reset).",
        handler = function(_context)
            if not game:GetService("RunService"):IsStudio() then
                return { ok = false, reason = "studio_only" }
            end
            local g = workspace:FindFirstChild("Game")
            local folder = g and g:FindFirstChild("Enemies")
            local cleared = 0
            if folder then
                for _, m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and (m:GetAttribute("HP") or 0) > 0 then
                        m:SetAttribute("HP", 0) -- triggers EnemyService's defeat handler
                        cleared += 1
                    end
                end
            end
            return { ok = true, cleared = cleared }
        end,
    })

    -- Combat: set the target-priority mode on the player's pets (all, or one PetType). Read by
    -- EnemyService's targeting (src/Shared/Game/TargetPriority.lua); invalid modes fall back to the
    -- squad default. This is the per-pet override the player picks.
    self._bus:register("combat.setTargetPriority", {
        description = "Set a pet target-priority mode (aggro/closest/furthest/strongest/weakest/team_threat).",
        validate = function(args)
            return Validators.fields(args, {
                mode = "string",
                petType = { type = "string", optional = true },
            })
        end,
        handler = function(context, args)
            local folder = workspace:FindFirstChild("PlayerPets")
                and workspace.PlayerPets:FindFirstChild(context.player.Name)
            if not folder then
                return { ok = false, reason = "no_pets" }
            end
            local set = 0
            for _, pet in ipairs(folder:GetChildren()) do
                if
                    pet:IsA("Model")
                    and (not args.petType or pet:GetAttribute("PetType") == args.petType)
                then
                    pet:SetAttribute("TargetPriority", args.mode)
                    set += 1
                end
            end
            return { ok = true, set = set, mode = args.mode }
        end,
    })

    -- Respec ritual (Feature 13): reset powers + slots, optionally re-pick archetype.
    self._bus:register("game.respec", {
        description = "[test] Respec: reset powers/slots; optional new archetype.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { archetype = { type = "string", optional = true } })
        end,
        handler = function(context, args)
            local s = self:_service("ArchetypeService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Respec(context.player, args.archetype)
        end,
    })

    -- Remove a pet ref from all rosters (simulates delete/trade, Feature 17).
    self._bus:register("roster.removePetRef", {
        description = "[test] Remove a pet ref from all rosters (delete/trade).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { petRef = "string" })
        end,
        handler = function(context, args)
            local s = self:_service("RosterService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:RemovePetReference(context.player, args.petRef)
        end,
    })

    -- Drive a biome conquest (real conquest triggers arrive with combat, Phase 4).
    self._bus:register("game.conquer", {
        description = "[test] Apply a biome conquest to the player (shifts Soul).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { biome = "string" })
        end,
        handler = function(context, args)
            local alignment = self:_service("AlignmentService")
            if not alignment then
                return { ok = false, reason = "service_unavailable" }
            end
            return alignment:ApplyConquest(context.player, args.biome)
        end,
    })

    -- Trade rules / execute-gate / audit-record logic without two live players.
    self._bus:register("trade.simulate", {
        description = "[test] Run trade add-rules, both-confirm gate, and audit-record build.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, {
                adds = { type = "table", optional = true },
                offerA = { type = "table", optional = true },
                offerB = { type = "table", optional = true },
                a = { type = "string", optional = true },
                b = { type = "string", optional = true },
                timestamp = { type = "number", optional = true },
            })
        end,
        handler = function(_, args)
            local s = self:_service("TradeService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Simulate(args)
        end,
    })

    self._bus:register("trade.auditLog", {
        description = "[test] Query the trade-history audit log (optionally by userId).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { userId = { type = "int", optional = true } })
        end,
        handler = function(_, args)
            local s = self:_service("TradeService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:GetAuditLog(args.userId)
        end,
    })

    -- Fusion rule + output + record logic without live inventory.
    self._bus:register("fusion.simulate", {
        description = "[test] Run fusion validation, output element/theme, and audit record.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, {
                elemA = "string",
                elemB = "string",
                themeA = { type = "string", optional = true },
                themeB = { type = "string", optional = true },
                timestamp = { type = "number", optional = true },
            })
        end,
        handler = function(_, args)
            local s = self:_service("FusionService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Simulate(args)
        end,
    })

    self._bus:register("fusion.log", {
        description = "[test] Query the fusion-history audit log (optionally by userId).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { userId = { type = "int", optional = true } })
        end,
        handler = function(_, args)
            local s = self:_service("FusionService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:GetFusionLog(args.userId)
        end,
    })

    -- Reward spine test affordances ---------------------------------------
    self._bus:register("test.setCounter", {
        description = "[test] Set a stat counter (drive quest conditions).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { counter = "string", value = "number" })
        end,
        handler = function(context, args)
            local stats = self:_service("StatsService")
            if not stats then
                return { ok = false, reason = "service_unavailable" }
            end
            stats:Set(context.player, args.counter, args.value)
            return { ok = true, counter = args.counter, value = args.value }
        end,
    })

    self._bus:register("test.setLevel", {
        description = "[test] Set the player's level (writes the curve's XP threshold).",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { level = { type = "int", min = 1 } })
        end,
        handler = function(context, args)
            local progression = self:_service("PlayerProgressionService")
            if not progression or not progression.SetLevel then
                return { ok = false, reason = "service_unavailable" }
            end
            local p = progression:SetLevel(context.player, args.level)
            return { ok = true, level = p.level, totalXp = p.totalXp }
        end,
    })

    self._bus:register("reward.grant", {
        description = "[test] Grant an arbitrary reward bundle to the player.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, {
                bundle = "table",
                source = { type = "string", optional = true },
            })
        end,
        handler = function(context, args)
            local s = self:_service("RewardService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Grant(context.player, args.bundle, args.source or "test_grant")
        end,
    })

    self._bus:register("reward.simulate", {
        description = "[test] Normalize a reward bundle without applying it.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { bundle = "table" })
        end,
        handler = function(_, args)
            local s = self:_service("RewardService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:Simulate(args.bundle)
        end,
    })

    self._bus:register("reward.log", {
        description = "[test] Query the reward grant-history audit log.",
        testOnly = true,
        validate = function(args)
            return Validators.fields(args, { userId = { type = "int", optional = true } })
        end,
        handler = function(_, args)
            local s = self:_service("RewardService")
            if not s then
                return { ok = false, reason = "service_unavailable" }
            end
            return s:GetGrantLog(args.userId)
        end,
    })

    self._bus:register("claim.reset", {
        description = "[test] Clear quest claims, daily streak, and shop purchases.",
        testOnly = true,
        handler = function(context)
            local data = self:_service("DataService")
            if not data then
                return { ok = false, reason = "service_unavailable" }
            end
            local profile = data:GetData(context.player)
            profile.QuestClaims = {}
            profile.Daily = { lastDay = nil, streak = 0 }
            profile.ShopPurchases = {}
            return { ok = true }
        end,
    })

    self._bus:register("test.resetAchievements", {
        description = "[test] Clear earned-achievement records (re-arm reward grants).",
        testOnly = true,
        handler = function(context)
            local data = self:_service("DataService")
            if not data then
                return { ok = false, reason = "service_unavailable" }
            end
            local profile = data:GetData(context.player)
            profile.Achievements = { Completed = {} }
            return { ok = true }
        end,
    })
end

return GameAPIService
