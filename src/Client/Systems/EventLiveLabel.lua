--[[
    EventLiveLabel — drives the THEMED tray "Events" button (the EffectsButton, skinned by
    MenuTrayStyle to match Settings/Daily/Quest) as a live indicator for the active global event.

    No new UI is built here — the button comes from BaseUI's menu_buttons_pane and is skinned by
    MenuTrayStyle. This controller just reflects live state onto it:
      • idle  → label "Events", no glow.
      • active→ label = the soonest-expiring event's name (wraps, e.g. "Secret Sunday"), and a golden
               pulsing UIStroke draws the eye ("Secret Sunday is ON — go hatch").
    Data: Signals.ActiveEffects (EventService:BuildClientPayload → .globalEvents). The button's CLICK
    (open the Effects panel) is handled by BaseUI's config (name="Effects"), not here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventLiveLabel = {}

local IDLE_TEXT = "Events"
local IDLE_COLOR = Color3.fromRGB(235, 240, 245)
local LIVE_COLOR = Color3.fromRGB(255, 244, 200)
local LIVE_GLOW = Color3.fromRGB(255, 196, 64)

-- Soonest-to-expire active event (permanents sort last); returns (event, totalCount) or (nil, 0).
local function pickHeadline(events)
    if type(events) ~= "table" then
        return nil, 0
    end
    local best, bestKey, count = nil, nil, 0
    for _, e in ipairs(events) do
        if type(e) == "table" then
            count += 1
            local rem = tonumber(e.remaining or e.timeRemaining) or -1
            local key = rem < 0 and math.huge or rem
            if not best or key < bestKey then
                best, bestKey = e, key
            end
        end
    end
    return best, count
end

-- Find the tray button BaseUI created (named "<name>Button") anywhere under PlayerGui.
local function findButton(playerGui, timeout)
    local deadline = os.clock() + (timeout or 12)
    while os.clock() < deadline do
        local found
        for _, d in ipairs(playerGui:GetDescendants()) do
            if d.Name == "EffectsButton" and (d:IsA("GuiButton") or d:IsA("GuiObject")) then
                found = d
                break
            end
        end
        if found then
            return found
        end
        task.wait(0.25)
    end
    return nil
end

function EventLiveLabel.start()
    local player = Players.LocalPlayer
    if not player then
        return
    end
    local playerGui = player:WaitForChild("PlayerGui")

    task.spawn(function()
        local button = findButton(playerGui, 15)
        if not button then
            return -- the Events button isn't in the tray (e.g. config change) — nothing to drive
        end
        local label = button:FindFirstChild("Label", true)

        -- our own glow stroke (named, so it never collides with MenuTrayStyle's pill border)
        local glow = Instance.new("UIStroke")
        glow.Name = "EventGlow"
        glow.Color = LIVE_GLOW
        glow.Thickness = 0
        glow.Transparency = 1
        glow.Parent = button

        local pulse
        local function setGlow(on)
            if on then
                glow.Thickness = 2.5
                if not pulse then
                    pulse = game:GetService("TweenService"):Create(
                        glow,
                        TweenInfo.new(
                            0.9,
                            Enum.EasingStyle.Sine,
                            Enum.EasingDirection.InOut,
                            -1,
                            true
                        ),
                        { Transparency = 0.7 }
                    )
                    pulse:Play()
                end
                glow.Transparency = 0.1
            else
                if pulse then
                    pulse:Cancel()
                    pulse = nil
                end
                glow.Thickness = 0
                glow.Transparency = 1
            end
        end

        if label and label:IsA("TextLabel") then
            label.TextWrapped = true -- let "Secret Sunday" stack within the small cell
        end

        local headline, count = nil, 0
        local function render()
            if label and label:IsA("TextLabel") then
                if headline then
                    local title = tostring(headline.displayName or headline.name or "Event")
                    if count > 1 then
                        title = title .. " +" .. (count - 1)
                    end
                    label.Text = title
                    label.TextColor3 = LIVE_COLOR
                else
                    label.Text = IDLE_TEXT
                    label.TextColor3 = IDLE_COLOR
                end
            end
            setGlow(headline ~= nil)
        end

        local okS, Signals = pcall(function()
            return require(ReplicatedStorage.Shared.Network.Signals)
        end)
        if okS and Signals and Signals.ActiveEffects then
            Signals.ActiveEffects.OnClientEvent:Connect(function(payload)
                if type(payload) ~= "table" then
                    return
                end
                headline, count = pickHeadline(payload.globalEvents)
                render()
            end)
            pcall(function()
                Signals.ActiveEffects:FireServer({ request = true })
            end)
        end

        render()
    end)
end

return EventLiveLabel
