--[[
    EventLiveLabel — a lower-left "live label" pill for the active global event.

    Jason's spec: a button in the lower-left that shows the CURRENT event's title and glows while one
    is live; click it to open the events list. We reuse the existing data + panel:
      • Data: Signals.ActiveEffects (EventService:BuildClientPayload → .globalEvents = active events,
        each { displayName, icon, remaining/timeRemaining (-1 = permanent), modifiers }).
      • Panel: the registered "Effects" panel (MenuManager) already renders the active global events,
        so the pill just opens it — no parallel UI built.

    Idle  → dim "Events" pill (no event running).
    Active→ glowing pill showing the soonest-expiring event's name + a live countdown; a pulsing
            UIStroke draws the eye ("Secret Luck is ON — go hatch"). Multiple events → "Name +N".

    Standalone ScreenGui (does not touch BaseUI's tray), sits just above the bottom-left button
    cluster. Everything is pcall-guarded so a bad payload can never error the client HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EventLiveLabel = {}

local IDLE_TEXT = "Events"
local IDLE_STROKE = Color3.fromRGB(90, 100, 115)
local LIVE_STROKE = Color3.fromRGB(255, 196, 64) -- golden glow while an event runs
local PANEL_NAME = "Effects" -- the registered panel that lists global events

-- "2h 15m" / "8m 30s" / "45s" / "" for permanent (scheduled all-day events show no countdown)
local function formatRemaining(remaining)
    remaining = tonumber(remaining) or 0
    if remaining < 0 then
        return "" -- permanent / all-day scheduled event: no countdown
    end
    remaining = math.max(0, math.floor(remaining))
    if remaining >= 3600 then
        return string.format(
            "%dh %dm",
            math.floor(remaining / 3600),
            math.floor((remaining % 3600) / 60)
        )
    elseif remaining >= 60 then
        return string.format("%dm %ds", math.floor(remaining / 60), remaining % 60)
    end
    return remaining .. "s"
end

-- The event to headline: the soonest-to-expire active event (permanents sort last). Returns
-- (headline, totalActiveCount) or (nil, 0).
local function pickHeadline(events)
    if type(events) ~= "table" then
        return nil, 0
    end
    local best, bestKey
    local count = 0
    for _, e in ipairs(events) do
        if type(e) == "table" then
            count += 1
            local rem = tonumber(e.remaining or e.timeRemaining) or -1
            -- timed events (rem >= 0) rank ahead of permanents; among timed, soonest first
            local key = rem < 0 and math.huge or rem
            if not best or key < bestKey then
                best, bestKey = e, key
            end
        end
    end
    return best, count
end

function EventLiveLabel.start()
    local player = Players.LocalPlayer
    if not player then
        return
    end
    local playerGui = player:WaitForChild("PlayerGui")

    -- ── build the pill ────────────────────────────────────────────────────
    local gui = Instance.new("ScreenGui")
    gui.Name = "EventLiveLabel"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    -- sits just above the bottom-left menu-button cluster (cluster ≈ 160 tall, 15 from bottom)
    local pill = Instance.new("TextButton")
    pill.Name = "Pill"
    pill.AnchorPoint = Vector2.new(0, 1)
    pill.Position = UDim2.new(0, 15, 1, -200)
    pill.Size = UDim2.new(0, 320, 0, 42)
    pill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    pill.BackgroundTransparency = 0.4
    pill.AutoButtonColor = false
    pill.Text = ""
    pill.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = pill

    local stroke = Instance.new("UIStroke")
    stroke.Color = IDLE_STROKE
    stroke.Thickness = 2
    stroke.Transparency = 0.4
    stroke.Parent = pill

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = pill

    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.BackgroundTransparency = 1
    icon.AnchorPoint = Vector2.new(0, 0.5)
    icon.Position = UDim2.new(0, 0, 0.5, 0)
    icon.Size = UDim2.new(0, 26, 1, 0)
    icon.Text = "📅"
    icon.TextScaled = true
    icon.Parent = pill

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "EventName"
    nameLabel.BackgroundTransparency = 1
    nameLabel.AnchorPoint = Vector2.new(0, 0.5)
    nameLabel.Position = UDim2.new(0, 34, 0.5, 0)
    nameLabel.Size = UDim2.new(1, -34 - 70, 1, 0)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 16
    nameLabel.TextColor3 = Color3.fromRGB(235, 240, 245)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Text = IDLE_TEXT
    nameLabel.Parent = pill

    local timer = Instance.new("TextLabel")
    timer.Name = "Countdown"
    timer.BackgroundTransparency = 1
    timer.AnchorPoint = Vector2.new(1, 0.5)
    timer.Position = UDim2.new(1, 0, 0.5, 0)
    timer.Size = UDim2.new(0, 66, 1, 0)
    timer.Font = Enum.Font.GothamMedium
    timer.TextSize = 14
    timer.TextColor3 = Color3.fromRGB(255, 210, 120)
    timer.TextXAlignment = Enum.TextXAlignment.Right
    timer.Text = ""
    timer.Parent = pill

    -- pulse the stroke while an event is live (created on demand, cancelled when idle)
    local pulse
    local function setLive(isLive)
        if isLive then
            stroke.Color = LIVE_STROKE
            if not pulse then
                pulse = TweenService:Create(
                    stroke,
                    TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                    { Transparency = 0.65 }
                )
                pulse:Play()
            end
        else
            if pulse then
                pulse:Cancel()
                pulse = nil
            end
            stroke.Color = IDLE_STROKE
            stroke.Transparency = 0.4
        end
    end

    -- ── click → open the events (Effects) panel ───────────────────────────
    pill.Activated:Connect(function()
        local mm = _G.MenuManager
        if not mm then
            return
        end
        pcall(function()
            if mm.TogglePanel then
                mm:TogglePanel(PANEL_NAME)
            elseif mm.OpenPanel then
                mm:OpenPanel(PANEL_NAME)
            end
        end)
    end)

    -- ── state from ActiveEffects ──────────────────────────────────────────
    local headline, count = nil, 0
    local function render()
        if not headline then
            nameLabel.Text = IDLE_TEXT
            nameLabel.TextColor3 = Color3.fromRGB(170, 178, 188)
            timer.Text = ""
            setLive(false)
            return
        end
        local title = tostring(headline.displayName or headline.name or "Event")
        if count > 1 then
            title = title .. "  +" .. (count - 1)
        end
        nameLabel.Text = title
        nameLabel.TextColor3 = Color3.fromRGB(255, 244, 210)
        timer.Text = formatRemaining(headline.remaining or headline.timeRemaining)
        setLive(true)
    end

    local ok, Signals = pcall(function()
        return require(ReplicatedStorage.Shared.Network.Signals)
    end)
    if ok and Signals and Signals.ActiveEffects then
        Signals.ActiveEffects.OnClientEvent:Connect(function(payload)
            if type(payload) ~= "table" then
                return
            end
            headline, count = pickHeadline(payload.globalEvents)
            render()
        end)
        -- ask the server for the current state on boot (mirrors EffectsPanel's request)
        pcall(function()
            Signals.ActiveEffects:FireServer({ request = true })
        end)
    end

    -- live countdown: re-render once a second so the timer ticks down between server pushes
    local acc = 0
    RunService.Heartbeat:Connect(function(dt)
        acc += dt
        if acc < 1 then
            return
        end
        acc = 0
        if headline then
            local rem = tonumber(headline.remaining or headline.timeRemaining) or -1
            if rem > 0 then
                headline.remaining = rem - 1
                headline.timeRemaining = rem - 1
                if headline.remaining <= 0 then
                    headline, count = nil, 0 -- expired locally; next server push corrects it
                end
            end
            render()
        end
    end)

    render()
end

return EventLiveLabel
