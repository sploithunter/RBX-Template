--[[
    BootOrchestrator (server) — owns the event-driven boot milestone graph.

    See docs/BOOT_ORCHESTRATION.md. Responsibilities:
      1. Validate the configs/boot.lua dependency graph at boot (loud error if cyclic / a
         required milestone has no declared producer) — the next race caught at startup.
      2. Observe every BootReadiness.signal and LOG it ([BOOT] milestone ready), warning on any
         undeclared milestone — the permanent, structured replacement for the lag-hunt perf tags.
      3. Mirror milestone state to ReplicatedStorage.BootStatus (one bool attribute per server
         milestone) so clients gate the loading screen on REAL server readiness, not workspace
         symptom-polls.

    Services produce/consume milestones by requiring BootReadiness directly
    (signal/await) — this service only validates, mirrors, and logs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootReadiness = require(ReplicatedStorage.Shared.Boot.BootReadiness)
local BootGraph = require(ReplicatedStorage.Shared.Boot.BootGraph)

local BootOrchestrator = {}
BootOrchestrator.__index = BootOrchestrator

local STATUS_FOLDER_NAME = "BootStatus"

function BootOrchestrator:Init()
    self._logger = self._modules.Logger
    assert(self._logger, "BootOrchestrator: Logger dependency missing")

    local ok, bootConfig = pcall(function()
        return require(ReplicatedStorage.Configs:WaitForChild("boot"))
    end)
    if not ok or type(bootConfig) ~= "table" then
        self._logger:Error("BootOrchestrator: configs/boot.lua failed to load; boot graph inert", {
            error = tostring(bootConfig),
        })
        self._milestones = {}
        bootConfig = { milestones = {} }
    else
        self._milestones = bootConfig.milestones or {}
    end
    self._config = bootConfig

    -- Validate the dependency graph LOUDLY at boot.
    local valid, errors = BootGraph.validate(self._milestones)
    if not valid then
        for _, msg in ipairs(errors) do
            self._logger:Error("BootOrchestrator: invalid boot graph", { problem = msg })
        end
    else
        self._logger:Info("BootOrchestrator: boot graph valid", {
            order = table.concat(BootGraph.order(self._milestones), " -> "),
        })
    end

    -- Create the client-facing mirror with one (false) attribute per server milestone.
    local folder = ReplicatedStorage:FindFirstChild(STATUS_FOLDER_NAME)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = STATUS_FOLDER_NAME
        folder.Parent = ReplicatedStorage
    end
    self._statusFolder = folder
    for name in pairs(self._milestones) do
        if folder:GetAttribute(name) == nil then
            folder:SetAttribute(name, false)
        end
    end
end

function BootOrchestrator:Start()
    -- Seed the mirror from any milestone already signalled before this observer attaches
    -- (a producer with no dependencies may signal during its own Init/Start).
    for name, info in pairs(BootReadiness.snapshot()) do
        if info.ready then
            self:_onMilestone(name)
        end
    end

    -- Mirror + log every future signal.
    BootReadiness.observe(function(name)
        self:_onMilestone(name)
    end)
end

function BootOrchestrator:_onMilestone(name)
    if self._statusFolder and self._statusFolder:GetAttribute(name) ~= true then
        self._statusFolder:SetAttribute(name, true)
    end
    if self._milestones[name] then
        self._logger:Info("[BOOT] milestone ready", {
            milestone = name,
            background = self._milestones[name].background == true,
        })
    else
        -- A BootReadiness signal with no matching declaration — almost certainly a typo.
        self._logger:Warn("[BOOT] signalled an undeclared milestone", { milestone = name })
        if self._statusFolder then
            self._statusFolder:SetAttribute(name, true)
        end
    end
end

return BootOrchestrator
