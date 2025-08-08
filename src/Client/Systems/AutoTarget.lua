--[[
    AutoTarget (Client Module)
    - Polls current world breakables and picks a target based on player flags:
      FreeTarget => lowest value, PaidTarget => highest value
    - Sends Breakables_Attack with selected BreakableID to server (server assigns pets)
    - Runs continuously with small throttle; status is server-driven (see AutoTargetService)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local AutoTarget = {}
AutoTarget.__index = AutoTarget
AutoTarget._singleton = nil

local lastSelect = 0
local SELECT_INTERVAL = 0.3

local function getWorldShort(world)
    if world == "SpawnWorld" then return "Spawn" end
    return world
end

local function findCandidate(selectHighest)
    local gameFolder = workspace:FindFirstChild("Game")
    if not gameFolder then return nil end
    local breakables = gameFolder:FindFirstChild("Breakables")
    if not breakables then return nil end

    local currentWorldVal = localPlayer:FindFirstChild("CurrentWorld")
    local worldName = currentWorldVal and currentWorldVal.Value or "Spawn"
    local worldShort = getWorldShort(worldName)

    local bestModel = nil
    local bestVal = nil

    local function consider(model)
        if not model or not model:IsA("Model") then return end
        local id = model:FindFirstChild("BreakableID")
        if not id then return end
        local val = tonumber(model:GetAttribute("Value") or 0)
        if not bestVal then
            bestVal = val
            bestModel = model
        else
            if selectHighest then
                if val > bestVal then bestVal = val; bestModel = model end
            else
                if val < bestVal then bestVal = val; bestModel = model end
            end
        end
    end

    -- Gold
    local gold = breakables:FindFirstChild("Gold")
    if gold then
        local worldFolder = gold:FindFirstChild(worldShort)
        local items = worldFolder and worldFolder:FindFirstChild("Items")
        if items then
            for _, m in ipairs(items:GetChildren()) do
                consider(m)
            end
        end
    end

    -- Crystals
    local crystals = breakables:FindFirstChild("Crystals")
    if crystals then
        local worldFolder = crystals:FindFirstChild(worldShort)
        local items = worldFolder and worldFolder:FindFirstChild("Items")
        if items then
            for _, m in ipairs(items:GetChildren()) do
                consider(m)
            end
        end
    end

    -- Green/events
    local green = breakables:FindFirstChild("Green")
    if green then
        local worldFolder = green:FindFirstChild(worldShort)
        local items = worldFolder and worldFolder:FindFirstChild("Items")
        if items then
            for _, m in ipairs(items:GetChildren()) do
                consider(m)
            end
        end
    end

    return bestModel
end

function AutoTarget.new()
    if AutoTarget._singleton then return AutoTarget._singleton end
    local self = setmetatable({
        status = { free = false, paid = false },
        running = false,
    }, AutoTarget)

    -- Track server status
    Signals.AutoTarget_Status.OnClientEvent:Connect(function(s)
        self.status.free = s.free and true or false
        self.status.paid = s.paid and true or false
    end)

    -- Request initial status on start (server sends status on PlayerAdded, but ensure sync)
    task.delay(0.5, function()
        Signals.AutoTarget_ToggleFree:FireServer() -- noop flip to get a status echo if needed
        task.wait(0.1)
        Signals.AutoTarget_ToggleFree:FireServer() -- flip back
    end)

    AutoTarget._singleton = self
    return AutoTarget._singleton
end

function AutoTarget:ToggleFree()
    Signals.AutoTarget_ToggleFree:FireServer()
end

function AutoTarget:TogglePaid()
    Signals.AutoTarget_TogglePaid:FireServer()
end

function AutoTarget:Start()
    if self.running then return end
    self.running = true

    task.spawn(function()
        while self.running do
            RunService.Heartbeat:Wait()
            local now = tick()
            if (now - lastSelect) >= SELECT_INTERVAL then
                lastSelect = now
                local activeMode = nil
                if self.status.paid then activeMode = "high" elseif self.status.free then activeMode = "low" end
                if activeMode then
                    local selectHighest = (activeMode == "high")
                    local model = findCandidate(selectHighest)
                    if model and model:FindFirstChild("BreakableID") then
                        local id = model.BreakableID.Value
                        Signals.Breakables_Attack:FireServer({ id = id })
                    else
                        -- nothing found in world; try again soon
                    end
                end
            end
        end
    end)
end

function AutoTarget:Stop()
    self.running = false
end

return AutoTarget


