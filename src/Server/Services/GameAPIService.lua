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

local CommandBus = require(ReplicatedStorage.Shared.API.CommandBus)

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

-- Resolve a sibling service from the global locator established in
-- init.server.lua (_G.RBXTemplateServices:Get(name)).
function GameAPIService:_service(name)
    local locator = _G.RBXTemplateServices
    return locator and locator:Get(name)
end

-- Expose the bus for in-Studio tests / introspection.
function GameAPIService:GetBus()
    return self._bus
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
    Register the template's command set. These few are illustrative adapters
    showing the shape; the full migration registers one command per existing
    action (egg hatch, zone travel, inventory ops, etc.).
]]
function GameAPIService:_registerCommands()
    local bus = self._bus

    -- Read-only: quote an upgrade's next-level cost.
    bus:register("economy.getUpgradeCost", {
        description = "Return the cost to take an upgrade to its next level.",
        validate = function(args)
            if type(args.upgradeId) ~= "string" then
                return false, "upgradeId must be a string"
            end
            return true
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

    -- Mutating, server-authoritative: purchase an upgrade. Delegates straight to
    -- the existing service method, whose envelope becomes the bus result.
    bus:register("economy.purchaseUpgrade", {
        description = "Purchase the next level of a permanent upgrade.",
        validate = function(args)
            if type(args.upgradeId) ~= "string" then
                return false, "upgradeId must be a string"
            end
            return true
        end,
        handler = function(context, args)
            local upgrades = self:_service("UpgradeService")
            if not upgrades then
                return { ok = false, reason = "service_unavailable" }
            end
            return upgrades:PurchaseUpgrade(context.player, args.upgradeId)
        end,
    })

    -- Introspection: list available commands (handy for an automation driver).
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
end

return GameAPIService
