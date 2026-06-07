--[[
    PlayerBar (client) — City-of-Heroes-style center player bar: a stretched XP pill with a circle on
    each end. Left circle = area emblem; right circle = the LEVEL, ringed by 10 gear-notch ticks.

    Mechanic (Jason's spec): the XP pill fills; each time it fills completely it lights ONE notch on
    the right circle's ring; 10 notches = ready to level up. While ready the bars recolor gold and the
    level number alternates with an up-arrow. No health, no submenus. Area-themed via UITheme.

    Visual values tuned in Studio edit-mode (beveled gradients + inset fill + gear ring). Reads
    replicated attributes: Level / XP / XPForNext / PendingLevels.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerBar = {}
local started = false

local TICKS = 10
local GOLD = Color3.fromRGB(255, 205, 75)
local GOLD_HI = Color3.fromRGB(255, 230, 150)
local NOTCH_DIM = Color3.fromRGB(52, 60, 82)
local TRACK = Color3.fromRGB(9, 11, 18)
local EM_TOP = Color3.fromRGB(46, 52, 72)
local EM_BOT = Color3.fromRGB(14, 16, 24)
local DARK = Color3.fromRGB(20, 23, 34)

local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = inst
    return c
end
local function strokeOf(inst, col, t)
    local s = Instance.new("UIStroke")
    s.Color = col
    s.Thickness = t or 2
    s.Parent = inst
    return s
end
local function bevel(inst)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(EM_TOP, EM_BOT)
    g.Parent = inst
end
local function lighten(c, amt)
    return Color3.fromRGB(
        math.clamp(c.R * 255 + amt, 0, 255),
        math.clamp(c.G * 255 + amt, 0, 255),
        math.clamp(c.B * 255 + amt, 0, 255)
    )
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

    -- Retire the old top-center name/level card (BaseUI player_info_pane): this bar now owns the
    -- level + XP readout, so the card just overlapped it. Hide it once it exists.
    task.spawn(function()
        local base = pg:WaitForChild("ProfessionalBaseUI", 15)
        local mc = base and base:WaitForChild("MainContainer", 5)
        for _ = 1, 20 do
            local pane = mc and mc:FindFirstChild("player_info_pane")
            if pane then
                pane.Visible = false
                return
            end
            task.wait(0.5)
        end
    end)

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.AnchorPoint = Vector2.new(0.5, 0)
    root.Position = UDim2.new(0.5, 0, 0, 12)
    root.Size = UDim2.fromOffset(420, 50)
    root.BackgroundTransparency = 1
    root.Parent = gui

    -- left emblem
    local emblem = Instance.new("Frame")
    emblem.Size = UDim2.fromOffset(46, 46)
    emblem.AnchorPoint = Vector2.new(0, 0.5)
    emblem.Position = UDim2.new(0, 0, 0.5, 0)
    emblem.BackgroundColor3 = DARK
    corner(emblem, 23)
    bevel(emblem)
    local emblemStroke = strokeOf(emblem, GOLD, 2.5)
    emblem.Parent = root
    local star = Instance.new("TextLabel")
    star.Size = UDim2.fromScale(1, 1)
    star.BackgroundTransparency = 1
    star.Font = Enum.Font.GothamBlack
    star.TextSize = 20
    star.Text = "★"
    star.Parent = emblem

    -- xp pill (track + inset clipped fill)
    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(296, 15)
    pill.AnchorPoint = Vector2.new(0.5, 0.5)
    pill.Position = UDim2.new(0.5, 0, 0.5, 0)
    pill.BackgroundColor3 = TRACK
    corner(pill, 8)
    local pillStroke = strokeOf(pill, Color3.fromRGB(54, 62, 86), 1.5)
    pill.Parent = root
    local fillHolder = Instance.new("Frame")
    fillHolder.Size = UDim2.new(1, -4, 1, -4)
    fillHolder.Position = UDim2.fromOffset(2, 2)
    fillHolder.BackgroundTransparency = 1
    fillHolder.ClipsDescendants = true
    corner(fillHolder, 7)
    fillHolder.Parent = pill
    local xpFill = Instance.new("Frame")
    xpFill.Size = UDim2.new(0, 0, 1, 0)
    xpFill.BackgroundColor3 = Color3.fromRGB(55, 130, 235)
    corner(xpFill, 6)
    xpFill.Parent = fillHolder
    local fillGrad = Instance.new("UIGradient")
    fillGrad.Rotation = 90
    fillGrad.Parent = xpFill
    local xpText = Instance.new("TextLabel")
    xpText.Size = UDim2.fromScale(1, 1)
    xpText.BackgroundTransparency = 1
    xpText.Font = Enum.Font.GothamBold
    xpText.TextSize = 10
    xpText.TextColor3 = Color3.fromRGB(240, 244, 252)
    xpText.Text = ""
    xpText.ZIndex = 4
    xpText.Parent = pill

    -- right level circle + gear notches
    local levelCircle = Instance.new("Frame")
    levelCircle.Size = UDim2.fromOffset(48, 48)
    levelCircle.AnchorPoint = Vector2.new(1, 0.5)
    levelCircle.Position = UDim2.new(1, 0, 0.5, 0)
    levelCircle.BackgroundColor3 = DARK
    corner(levelCircle, 24)
    bevel(levelCircle)
    local levelStroke = strokeOf(levelCircle, GOLD, 2.5)
    levelCircle.Parent = root
    local levelText = Instance.new("TextLabel")
    levelText.Name = "Num"
    levelText.Size = UDim2.fromScale(1, 1)
    levelText.BackgroundTransparency = 1
    levelText.Font = Enum.Font.GothamBlack
    levelText.TextSize = 19
    levelText.TextColor3 = Color3.fromRGB(245, 248, 255)
    levelText.Text = "1"
    levelText.ZIndex = 4
    levelText.Parent = levelCircle
    local ticks = {}
    for i = 1, TICKS do
        local ang = math.rad(-90 + (i - 1) * (360 / TICKS))
        local t = Instance.new("Frame")
        t.Name = "Tick" .. i
        t.Size = UDim2.fromOffset(3, 6)
        t.AnchorPoint = Vector2.new(0.5, 0.5)
        t.Position = UDim2.new(0.5, math.cos(ang) * 27, 0.5, math.sin(ang) * 27)
        t.Rotation = math.deg(ang) + 90
        t.BackgroundColor3 = NOTCH_DIM
        t.BorderSizePixel = 0
        corner(t, 1)
        t.Parent = levelCircle
        ticks[i] = t
    end

    -- ---- data + render ----------------------------------------------------
    local palette = Theme.palette(player)
    local function applyTheme(p)
        palette = p
        emblemStroke.Color = p.primary
        star.TextColor3 = p.primary
        pillStroke.Color = lighten(p.primary, -120)
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
        local within = ready and 1 or (progress * TICKS - lit)
        local accent = ready and GOLD or palette.primary

        emblemStroke.Color = accent
        levelStroke.Color = accent
        star.TextColor3 = accent
        for i = 1, TICKS do
            ticks[i].BackgroundColor3 = (i <= lit) and accent or NOTCH_DIM
        end
        xpFill.Size = UDim2.new(math.clamp(within, ready and 1 or 0.015, 1), 0, 1, 0)
        fillGrad.Color = ready and ColorSequence.new(GOLD_HI, GOLD)
            or ColorSequence.new(lighten(palette.fill, 70), palette.fill)
        xpText.Text = need > 0 and string.format("%d / %d XP", math.floor(xp), need) or ""
        if ready then
            levelText.Text = blinkOn and tostring(level) or "▲"
            levelText.TextColor3 = GOLD_HI
        else
            levelText.Text = tostring(level)
            levelText.TextColor3 = Color3.fromRGB(245, 248, 255)
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
