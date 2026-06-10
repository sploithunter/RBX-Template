--[[
    TutorialController (client) — renders the server-pushed tutorial state (Signals.TutorialState,
    TutorialFlow.stateFor shape). Three guidance surfaces, all torn down between steps:

      capsule  — the objective card. Docks INTO the TopHudStack (under the player bar, where
                 the quest tracker lives — Jason: the tutorial IS the new player's quest) and
                 HIDES the quest_tracker_pane while active; quests reappear there when done.
                 Falls back to a bottom-center ScreenGui if the stack never shows up.
      beacon   — target.kind == "egg": pulsing BillboardGui over the NEAREST world egg (egg models
                 carry an EggInfo child — same detection as the BootLoader gate), re-aimed every 2s
      pulse    — target.kind == "ui": breathing gold UIStroke around the named GuiObject, found
                 recursively in PlayerGui with retry (e.g. LevelUpButton only exists when pending)

    Progress is server-authoritative; this never advances anything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local GOLD = Color3.fromRGB(255, 205, 70)

local TutorialController = {}
local started = false

local gui -- ScreenGui (capsule lives here)
local capsule, stepLabel, titleLabel, bodyLabel
local beacon -- BillboardGui (parented to the current nearest egg)
local pulseStroke -- UIStroke on the current ui target
local stepToken = 0 -- bumps every state push; loops check it to die

local questPane -- quest_tracker_pane (hidden while the tutorial runs)
local docked = false
local tutorialActive = false

-- one rule: while the tutorial runs (and we're docked in the stack), quests yield the spot
local function syncQuestPane()
    if docked and questPane then
        questPane.Visible = not tutorialActive
    end
end

local function buildCapsule(pg)
    gui = Instance.new("ScreenGui")
    gui.Name = "TutorialGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 40
    gui.IgnoreGuiInset = true

    capsule = Instance.new("Frame")
    capsule.Name = "Objective"
    capsule.AnchorPoint = Vector2.new(0.5, 1)
    capsule.Position = UDim2.new(0.5, 0, 1, -140) -- fallback spot (above the hotbar)
    capsule.Size = UDim2.fromOffset(360, 88) -- room for 3-line bodies (farm step)
    capsule.BackgroundColor3 = Color3.fromRGB(24, 22, 34)
    capsule.BackgroundTransparency = 0.12
    capsule.Visible = false
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = capsule
    local stroke = Instance.new("UIStroke")
    stroke.Color = GOLD
    stroke.Thickness = 2
    stroke.Parent = capsule

    stepLabel = Instance.new("TextLabel")
    stepLabel.BackgroundTransparency = 1
    stepLabel.Size = UDim2.new(1, -20, 0, 16)
    stepLabel.Position = UDim2.fromOffset(10, 6)
    stepLabel.Font = Enum.Font.GothamBold
    stepLabel.TextSize = 11
    stepLabel.TextColor3 = GOLD
    stepLabel.TextXAlignment = Enum.TextXAlignment.Left
    stepLabel.Parent = capsule

    titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Size = UDim2.new(1, -20, 0, 18)
    titleLabel.Position = UDim2.fromOffset(10, 21)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 15
    titleLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = capsule

    bodyLabel = Instance.new("TextLabel")
    bodyLabel.BackgroundTransparency = 1
    bodyLabel.Size = UDim2.new(1, -20, 0, 42)
    bodyLabel.Position = UDim2.fromOffset(10, 41)
    bodyLabel.Font = Enum.Font.Gotham
    bodyLabel.TextSize = 12
    bodyLabel.TextWrapped = true
    bodyLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
    bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
    bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
    bodyLabel.Parent = capsule

    capsule.Parent = gui
    gui.Parent = pg
    require(script.Parent.Parent.UI.UIViewportScale).attach(capsule)

    -- Dock into the TopHudStack (above the quest tracker, same screen home as quests).
    -- The stack's capsule already carries a ViewportScale, so ours goes when we move in.
    task.spawn(function()
        local barGui = pg:WaitForChild("PlayerBar", 20)
        local cap = barGui and barGui:WaitForChild("Capsule", 10)
        local stack = cap and cap:WaitForChild("TopHudStack", 10)
        if not (stack and capsule) then
            return -- fallback: stays bottom-center in its own gui
        end
        local own = capsule:FindFirstChild("ViewportScale")
        if own then
            own:Destroy()
        end
        capsule.LayoutOrder = 0 -- above the quest tracker slot
        capsule.Parent = stack
        docked = true
        questPane = stack:FindFirstChild("quest_tracker_pane")
            or stack:WaitForChild("quest_tracker_pane", 15)
        if gui then
            gui:Destroy()
            gui = nil
        end
        syncQuestPane()
    end)
end

local function clearGuidance()
    if beacon then
        beacon:Destroy()
        beacon = nil
    end
    if pulseStroke then
        pulseStroke:Destroy()
        pulseStroke = nil
    end
end

local function nearestEgg()
    local char = Players.LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local best, bestDist
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") and child:FindFirstChild("EggInfo") then
            local pivot = child:GetPivot().Position
            local d = hrp and (pivot - hrp.Position).Magnitude or 0
            if not best or d < bestDist then
                best, bestDist = child, d
            end
        end
    end
    return best
end

local function showEggBeacon(token)
    beacon = Instance.new("BillboardGui")
    beacon.Name = "TutorialBeacon"
    beacon.Size = UDim2.fromOffset(120, 56)
    beacon.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
    beacon.AlwaysOnTop = true
    beacon.MaxDistance = 500
    local arrow = Instance.new("TextLabel")
    arrow.BackgroundTransparency = 1
    arrow.Size = UDim2.fromScale(1, 1)
    arrow.Font = Enum.Font.GothamBlack
    arrow.TextSize = 22
    arrow.TextColor3 = GOLD
    arrow.TextStrokeTransparency = 0.4
    arrow.Text = "⬇ HATCH"
    arrow.Parent = beacon

    -- keep it on the NEAREST egg + bob it (cheap: re-aim every 2s, bob via sine each frame)
    task.spawn(function()
        local t0 = os.clock()
        while token == stepToken and beacon do
            local egg = nearestEgg()
            if egg then
                beacon.Parent = egg
            end
            local reaim = os.clock() + 2
            while token == stepToken and beacon and os.clock() < reaim do
                beacon.StudsOffsetWorldSpace =
                    Vector3.new(0, 6 + math.sin((os.clock() - t0) * 3) * 0.8, 0)
                RunService.RenderStepped:Wait()
            end
        end
    end)
end

local function showUiPulse(token, name)
    task.spawn(function()
        local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
        -- the target may not exist yet (LevelUpButton appears with pending levels) — poll politely
        local target
        while token == stepToken and not target do
            target = pg:FindFirstChild(name, true)
            if not target then
                task.wait(1)
            end
        end
        if token ~= stepToken or not target then
            return
        end
        pulseStroke = Instance.new("UIStroke")
        pulseStroke.Color = GOLD
        pulseStroke.Thickness = 3
        pulseStroke.Parent = target
        local t0 = os.clock()
        while token == stepToken and pulseStroke do
            pulseStroke.Transparency = 0.25 + 0.55 * (0.5 + 0.5 * math.sin((os.clock() - t0) * 4))
            RunService.RenderStepped:Wait()
        end
    end)
end

local function apply(state)
    stepToken += 1
    clearGuidance()
    if type(state) ~= "table" or state.done then
        tutorialActive = false
        if capsule then
            capsule.Visible = false
        end
        syncQuestPane() -- hand the spot back to quests
        return
    end
    tutorialActive = true
    syncQuestPane()
    stepLabel.Text = ("TUTORIAL  %d / %d"):format(state.index or 1, state.total or 1)
        .. (
            (state.need or 1) > 1 and ("   ·   %d / %d"):format(state.count or 0, state.need) or ""
        )
    titleLabel.Text = state.title or ""
    bodyLabel.Text = state.body or ""
    capsule.Visible = true

    local target = state.target or {}
    if target.kind == "egg" then
        showEggBeacon(stepToken)
    elseif target.kind == "ui" and type(target.name) == "string" then
        showUiPulse(stepToken, target.name)
    end
end

function TutorialController.start()
    if started then
        return
    end
    started = true
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    buildCapsule(pg)
    Signals.TutorialState.OnClientEvent:Connect(apply)
    -- pull current state — the server's join-time push may predate this connection
    Signals.TutorialState:FireServer()
end

return TutorialController
