--[[
    DiagnosticsService – lightweight runtime health-check runner

    Admin calls Signals.RunDiagnostics → server executes a suite of quick
    Lua-level assertions (no asset loading) and returns a summary.
    The service is intentionally simple so it can run even in live servers
    without long stalls.

    Later we can swap the body out for TestEZ once tests are replicated to the
    live place, but this already gives a one-click confirmation that the core
    services and Net signals are wired correctly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Signals      = require(ReplicatedStorage.Shared.Network.Signals)

local DiagnosticsService = {}
DiagnosticsService.__index = DiagnosticsService

function DiagnosticsService:Init()
    self._logger          = self._modules.Logger
    self._inventory       = self._modules.InventoryService
    self._economy         = self._modules.EconomyService
    self._rateLimit       = self._modules.RateLimitService
    self._dataService     = self._modules.DataService

    -- Bind Net handler once services are ready
    Signals.RunDiagnostics.OnServerEvent:Connect(function(player)
        self:_runDiagnostics(player)
    end)

    self._logger:Info("DiagnosticsService initialised – ready for RunDiagnostics events")
end

function DiagnosticsService:Start() end -- nothing asynchronous

---------------------------------------------------------------------
-- INTERNAL
---------------------------------------------------------------------

function DiagnosticsService:_runDiagnostics(player)
    local summary = {
        passed   = 0,
        failed   = 0,
        failures = {},
        timestamp = os.time(),
    }

    local function check(condition, description)
        if condition then
            summary.passed += 1
        else
            summary.failed += 1
            table.insert(summary.failures, description)
        end
    end

    -- Basic service presence
    check(self._inventory ~= nil, "InventoryService missing")
    check(self._economy   ~= nil, "EconomyService missing")
    check(self._rateLimit ~= nil, "RateLimitService missing")

    -- Inventory config sanity
    if self._inventory and self._inventory._inventoryConfig then
        local cfg = self._inventory._inventoryConfig
        check(cfg.buckets ~= nil, "Inventory buckets config nil")
        check(cfg.settings ~= nil, "Inventory settings config nil")
    else
        check(false, "Inventory config unavailable")
    end

    -- RateLimitService live clock
    if self._rateLimit and self._rateLimit._serverClock then
        local srvClock = self._rateLimit._serverClock:GetServerTime()
        check(type(srvClock) == "number", "ServerClock invalid")
    else
        check(false, "RateLimitService ServerClock missing")
    end

    -- Simple data check on requesting player
    if self._dataService then
        local data = self._dataService:GetData(player)
        check(data ~= nil, "Player data not loaded")
        if data and data.Inventory then
            check(type(data.Inventory) == "table", "Player inventory format invalid")
        end
    else
        check(false, "DataService missing")
    end

    summary.total = summary.passed + summary.failed

    Signals.RunDiagnostics:FireClient(player, summary)

    self._logger:Info("Diagnostics run for player", {player = player.Name, passed = summary.passed, failed = summary.failed})
end

return DiagnosticsService