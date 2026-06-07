--[[
    PlayerBar (client) — City-of-Heroes-style center player bar: a stretched XP pill with a circle on
    each end. Left circle = area emblem; right circle = the LEVEL, ringed by 10 ticks.

    Mechanic (Jason's spec): the XP pill fills; each time it fills completely it adds ONE tick to the
    right circle's ring; 10 ticks = ring full = ready to level up. While ready, the bars recolor and
    the level number alternates with an up-arrow. No health, no submenus. Area-themed via UITheme.

    Reads replicated attributes: Level / XP / XPForNext / PendingLevels (all already published).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerBar = {}
local started = false

local TICKS = 10
local READY_COLOR = Color3.fromRGB(255, 210, 70) -- gold = ready to level up
local TRACK_COLOR = Color3.fromRGB(22, 24, 34)

local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = inst
    return c
end

function PlayerBar.start()
    if started then
        return
    end
    started = true
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")
    local Theme = require(script.Parent.Parent.UI.UITheme)

    local gui = Instance.new("ScreenGui")
    gui.Name = "PlayerBar"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 80
    gui.Parent = pg

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.AnchorPoint = Vector2.new(0.5, 0)
    root.Position = UDim2.new(0.5, 0, 0, 14)
    root.Size = UDim2.fromOffset(440, 60)
    root.BackgroundTransparency = 1
    root.Parent = gui

    -- Left emblem circle
    local emblem = Instance.new("Frame")
    emblem.Name = "Emblem"
    emblem.Size = UDim2.fromOffset(54, 54)
    emblem.Position = UDim2.fromScale(0, 0.5)
    emblem.AnchorPoint = Vector2.new(0, 0.5)
    emblem.BackgroundColor3 = TRACK_COLOR
    corner(emblem, 27)
    local emblemStroke = Instance.new("UIStroke")
    emblemStroke.Thickness = 3
    emblemStroke.Parent = emblem
    emblem.Parent = root
    local emblemIcon = Instance.new("TextLabel")
    emblemIcon.Size = UDim2.fromScale(1, 1)
    emblemIcon.BackgroundTransparency = 1
    emblemIcon.Font = Enum.Font.GothamBlack
    emblemIcon.TextSize = 24
    emblemIcon.Text = "★"
    emblemIcon.Parent = emblem

    -- XP pill (between the circles)
    local pill = Instance.new("Frame")
    pill.Name = "XPPill"
    pill.Position = UDim2.fromOffset(60, 0)
    pill.AnchorPoint = Vector2.new(0, 0.5)
    pill.Position = UDim2.new(0, 60, 0.5, 0)
    pill.Size = UDim2.fromOffset(320, 22)
    pill.BackgroundColor3 = TRACK_COLOR
    corner(pill, 11)
    local pillStroke = Instance.new("UIStroke")
    pillStroke.Thickness = 2
    pillStroke.Parent = pill
    pill.Parent = root
    local xpFill = Instance.new("Frame")
    xpFill.Name = "Fill"
    xpFill.Size = UDim2.new(0, 0, 1, 0)
    xpFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
    corner(xpFill, 11)
    xpFill.Parent = pill
    local xpText = Instance.new("TextLabel")
    xpText.Size = UDim2.fromScale(1, 1)
    xpText.BackgroundTransparency = 1
    xpText.Font = Enum.Font.GothamBold
    xpText.TextSize = 12
    xpText.TextColor3 = Color3.fromRGB(245, 247, 252)
    xpText.Text = ""
    xpText.ZIndex = 3
    xpText.Parent = pill

    -- Right level circle + 10 ticks
    local levelCircle = Instance.new("Frame")
    levelCircle.Name = "Level"
    levelCircle.Size = UDim2.fromOffset(54, 54)
    levelCircle.Position = UDim2.fromScale(1, 0.5)
    levelCircle.AnchorPoint = Vector2.new(1, 0.5)
    levelCircle.BackgroundColor3 = TRACK_COLOR
    corner(levelCircle, 27)
    local levelStroke = Instance.new("UIStroke")
    levelStroke.Thickness = 3
    levelStroke.Parent = levelCircle
    levelCircle.Parent = root
    local levelText = Instance.new("TextLabel")
    levelText.Name = "Num"
    levelText.Size = UDim2.fromScale(1, 1)
    levelText.BackgroundTransparency = 1
    levelText.Font = Enum.Font.GothamBlack
    levelText.TextSize = 22
    levelText.TextColor3 = Color3.fromRGB(245, 247, 252)
    levelText.Text = "1"
    levelText.ZIndex = 3
    levelText.Parent = levelCircle

    -- ticks arranged around the circle (start at top, clockwise)
    local ticks = {}
    local r = 31
    for i = 1, TICKS do
        local ang = math.rad(-90 + (i - 1) * (360 / TICKS))
        local t = Instance.new("Frame")
        t.Name = "Tick" .. i
        t.Size = UDim2.fromOffset(4, 10)
        t.AnchorPoint = Vector2.new(0.5, 0.5)
        t.Position = UDim2.new(0.5, math.cos(ang) * r, 0.5, math.sin(ang) * r)
        t.Rotation = math.deg(ang) + 90
        t.BackgroundColor3 = TRACK_COLOR
        t.BorderSizePixel = 0
        corner(t, 2)
        t.ZIndex = 2
        t.Parent = levelCircle
        ticks[i] = t
    end

    -- ---- data + render ----------------------------------------------------
    local palette = Theme.palette(player)
    local function applyTheme(p)
        palette = p
        emblemStroke.Color = p.primary
        emblemIcon.TextColor3 = p.primary
        pillStroke.Color = p.primary
        levelStroke.Color = p.primary
    end
    Theme.bind(player, applyTheme)

    local blinkOn = true
    local function refresh()
        local level = tonumber(player:GetAttribute("Level"))
            or tonumber(player:GetAttribute("ClaimedLevel"))
            or 1
        local xp = tonumber(player:GetAttribute("XP")) or 0
        local need = tonumber(player:GetAttribute("XPForNext")) or 0
        local pending = tonumber(player:GetAttribute("PendingLevels")) or 0
        local progress = need > 0 and math.clamp(xp / need, 0, 1) or 0
        local ready = pending > 0 or progress >= 1
        local lit = ready and TICKS or math.floor(progress * TICKS)
        local within = ready and 1 or (progress * TICKS - lit) -- linear fill of the current tenth

        -- ring ticks
        for i = 1, TICKS do
            ticks[i].BackgroundColor3 = (i <= lit) and (ready and READY_COLOR or palette.primary)
                or palette.dim
        end
        -- xp pill
        xpFill.Size = UDim2.new(math.clamp(within, ready and 1 or 0.02, 1), 0, 1, 0)
        xpFill.BackgroundColor3 = ready and READY_COLOR or palette.fill
        xpText.Text = need > 0 and string.format("%d / %d XP", math.floor(xp), need) or ""
        -- level number / ready alternation
        if ready then
            levelText.Text = blinkOn and tostring(level) or "▲"
            levelText.TextColor3 = READY_COLOR
            levelStroke.Color = READY_COLOR
        else
            levelText.Text = tostring(level)
            levelText.TextColor3 = palette.text
            levelStroke.Color = palette.primary
        end
    end

    applyTheme(palette)
    refresh()

    local accum, blinkAccum = 0, 0
    RunService.Heartbeat:Connect(function(dt)
        accum += dt
        blinkAccum += dt
        if blinkAccum >= 0.55 then
            blinkAccum = 0
            blinkOn = not blinkOn
        end
        if accum >= 0.2 then
            accum = 0
            refresh()
        end
    end)
end

return PlayerBar
