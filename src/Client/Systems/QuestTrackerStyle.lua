--[[
    QuestTrackerStyle (client) — move the Current Quest tracker out of the top-right and dock it
    directly BELOW the center player bar, restyled to match (a dark capsule with a blue progress bar
    on top + the quest name below), per assets/ui/reference/player_status_quest_combo_reference.png.

    Scoped post-process of ProfessionalBaseUI's quest_tracker_pane (BaseUI logic untouched). The
    progress fill is area-themed via UITheme (blue default). Idempotent.
]]

local Players = game:GetService("Players")

local QuestTrackerStyle = {}
local started = false

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = p
    return c
end
local function stroke(p, col, t)
    local s = Instance.new("UIStroke")
    s.Color = col
    s.Thickness = t
    s.Parent = p
    return s
end
local function grad(p, a, b)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(a, b)
    g.Parent = p
    return g
end
local function outline(label)
    if not label:FindFirstChildOfClass("UIStroke") then
        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(0, 0, 0)
        s.Thickness = 2
        s.Parent = label
    end
end
local function lighten(c, amt)
    return Color3.fromRGB(
        math.clamp(c.R * 255 + amt, 0, 255),
        math.clamp(c.G * 255 + amt, 0, 255),
        math.clamp(c.B * 255 + amt, 0, 255)
    )
end

function QuestTrackerStyle.start()
    if started then
        return
    end
    started = true
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")

    task.spawn(function()
        local base = pg:WaitForChild("ProfessionalBaseUI", 20)
        local mc = base and base:WaitForChild("MainContainer", 10)
        local pane
        for _ = 1, 30 do
            -- pg-wide recursive: TopHudStack may have adopted the pane into the PlayerBar
            -- capsule's stack before we got here (it is no longer under MainContainer)
            pane = (mc and mc:FindFirstChild("quest_tracker_pane"))
                or pg:FindFirstChild("quest_tracker_pane", true)
            if pane then
                break
            end
            task.wait(0.5)
        end
        if not pane or pane:GetAttribute("Restyled") then
            return
        end
        pane:SetAttribute("Restyled", true)

        -- dock TIGHT below the player bar (Jason: as close as possible) — compact pane.
        pane.AnchorPoint = Vector2.new(0.5, 0)
        pane.Position = UDim2.new(0.5, 0, 0, 68)
        pane.Size = UDim2.fromOffset(380, 48)
        pane.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
        pane.BackgroundTransparency = 0
        corner(pane, 16)
        grad(pane, Color3.fromRGB(58, 60, 70), Color3.fromRGB(28, 30, 38))
        stroke(pane, Color3.fromRGB(20, 22, 28), 2)

        local title = pane:FindFirstChild("QuestTitle")
        if title then
            title.Visible = false -- reference drops the "Current Quest" header
        end

        -- progress bar on TOP
        local pbg = pane:FindFirstChild("ProgressBackground")
        local fill = pbg and pbg:FindFirstChild("Fill") -- FillBar names its fill child "Fill"
        local ptext = pbg and pbg:FindFirstChild("ProgressText")
        if pbg then
            pbg.AnchorPoint = Vector2.new(0.5, 0)
            pbg.Position = UDim2.new(0.5, 0, 0, 6)
            pbg.Size = UDim2.fromOffset(346, 13) -- match the player bar's Focus/XP bar height
            pbg.BackgroundColor3 = Color3.fromRGB(30, 32, 38) -- player-bar track gray
            pbg.ZIndex = 2
            stroke(pbg, Color3.fromRGB(90, 94, 102), 1.5)
        end

        -- quest name on the BOTTOM
        local desc = pane:FindFirstChild("QuestDescription")
        if desc then
            desc.AnchorPoint = Vector2.new(0.5, 1)
            desc.Position = UDim2.new(0.5, 0, 1, -5)
            desc.Size = UDim2.new(1, -20, 0, 22)
            desc.Font = Enum.Font.GothamBlack
            desc.TextScaled = true
            desc.TextColor3 = Color3.fromRGB(245, 248, 255)
            desc.ZIndex = 2
            outline(desc)
        end
        if ptext then
            ptext.TextColor3 = Color3.fromRGB(245, 248, 255)
            ptext.ZIndex = 4
            outline(ptext)
        end

        -- The quest bar is a NEUTRAL gray matching the player-bar capsule (Jason — it shouldn't read
        -- as a loud green/area bar tucked under the player bar). Not area-themed.
        local QUEST_GRAY = Color3.fromRGB(120, 124, 132)
        if fill then
            fill.BackgroundColor3 = QUEST_GRAY
            local g = fill:FindFirstChildOfClass("UIGradient")
            if not g then
                grad(fill, lighten(QUEST_GRAY, 30), QUEST_GRAY)
            else
                g.Color = ColorSequence.new(lighten(QUEST_GRAY, 30), QUEST_GRAY)
            end
        end
    end)
end

return QuestTrackerStyle
