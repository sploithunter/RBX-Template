--[[
    PlayerBar (client) — City-of-Heroes-style center player bar built from Jason's PILL ART:
    glossy pill_panel + pill_frame badges (emblem + level) in the home-area color, and a glossy
    pill_panel XP fill. Reads the area via UITheme; the pill images swap with the area.

    Mechanic (Jason's spec): the XP pill fills; each full fill lights ONE tick around the level badge;
    10 ticks = ready to level up -> badges flip to citrine (gold) and the level number alternates with
    an up-arrow. No health, no submenus. Reads Level / XP / XPForNext / PendingLevels.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PILL = require(ReplicatedStorage.Configs:WaitForChild("pill_ui"))

local PlayerBar = {}
local started = false

local TICKS = 10
local READY_KEY = "citrine" -- gold-ish pill = ready to level up
local TICK_DIM = Color3.fromRGB(40, 48, 66)

local function pillKey(palette)
    -- palette.color is one of sapphire/emerald/ruby/citrine/neutral — the pill keys. The neutral pill
    -- is solid WHITE (white star/number would vanish on it), so before a home area is chosen we fall
    -- back to the sapphire (blue) pill as the default look.
    local key = palette.color
    if key == nil or key == "neutral" or not PILL.panels[key] then
        key = "sapphire"
    end
    return key
end
local function lighten(c, amt)
    return Color3.fromRGB(
        math.clamp(c.R * 255 + amt, 0, 255),
        math.clamp(c.G * 255 + amt, 0, 255),
        math.clamp(c.B * 255 + amt, 0, 255)
    )
end
local function imageLabel(parent, image, z)
    local l = Instance.new("ImageLabel")
    l.BackgroundTransparency = 1
    l.ScaleType = Enum.ScaleType.Fit
    l.Image = image
    l.ZIndex = z or 1
    l.Parent = parent
    return l
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

    -- Retire the old top-center name/level card (BaseUI player_info_pane) — this bar owns level + XP.
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
    root.Position = UDim2.new(0.5, 0, 0, 14)
    root.Size = UDim2.fromOffset(440, 52)
    root.BackgroundTransparency = 1
    root.Parent = gui

    -- left emblem: panel + frame + star
    local emblem = imageLabel(root, PILL.panels.neutral, 1)
    emblem.Size = UDim2.fromOffset(50, 50)
    emblem.AnchorPoint = Vector2.new(0, 0.5)
    emblem.Position = UDim2.new(0, 0, 0.5, 0)
    local emblemFrame = imageLabel(emblem, PILL.frames.neutral, 2)
    emblemFrame.Size = UDim2.fromScale(1.18, 1.18)
    emblemFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    emblemFrame.Position = UDim2.fromScale(0.5, 0.5)
    local star = Instance.new("TextLabel")
    star.Size = UDim2.fromScale(1, 1)
    star.BackgroundTransparency = 1
    star.Font = Enum.Font.GothamBlack
    star.TextSize = 22
    star.Text = "★"
    star.TextColor3 = Color3.fromRGB(255, 255, 255)
    star.ZIndex = 3
    star.Parent = emblem

    -- xp bar: dark track + clipped glossy panel fill + text
    local track = Instance.new("Frame")
    track.Size = UDim2.fromOffset(300, 18)
    track.AnchorPoint = Vector2.new(0.5, 0.5)
    track.Position = UDim2.new(0.5, 0, 0.5, 0)
    track.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 9)
    trackCorner.Parent = track
    local trackStroke = Instance.new("UIStroke")
    trackStroke.Thickness = 2
    trackStroke.Color = Color3.fromRGB(70, 110, 180)
    trackStroke.Parent = track
    track.Parent = root
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -4, 1, -4)
    holder.Position = UDim2.fromOffset(2, 2)
    holder.BackgroundTransparency = 1
    holder.ClipsDescendants = true
    local holderCorner = Instance.new("UICorner")
    holderCorner.CornerRadius = UDim.new(0, 8)
    holderCorner.Parent = holder
    holder.Parent = track
    local fill = imageLabel(holder, PILL.panels.neutral, 1)
    fill.ScaleType = Enum.ScaleType.Crop
    fill.Size = UDim2.new(0, 0, 1, 0)
    local xpText = Instance.new("TextLabel")
    xpText.Size = UDim2.fromScale(1, 1)
    xpText.BackgroundTransparency = 1
    xpText.Font = Enum.Font.GothamBold
    xpText.TextSize = 11
    xpText.TextColor3 = Color3.fromRGB(245, 248, 255)
    xpText.Text = ""
    xpText.ZIndex = 4
    xpText.Parent = track

    -- level badge: panel + frame + number + 10 tick dots
    local levelBadge = imageLabel(root, PILL.panels.neutral, 1)
    levelBadge.Size = UDim2.fromOffset(50, 50)
    levelBadge.AnchorPoint = Vector2.new(1, 0.5)
    levelBadge.Position = UDim2.new(1, 0, 0.5, 0)
    local levelFrame = imageLabel(levelBadge, PILL.frames.neutral, 3)
    levelFrame.Size = UDim2.fromScale(1.18, 1.18)
    levelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    levelFrame.Position = UDim2.fromScale(0.5, 0.5)
    local levelText = Instance.new("TextLabel")
    levelText.Name = "Num"
    levelText.Size = UDim2.fromScale(1, 1)
    levelText.BackgroundTransparency = 1
    levelText.Font = Enum.Font.GothamBlack
    levelText.TextSize = 20
    levelText.TextColor3 = Color3.fromRGB(255, 255, 255)
    levelText.Text = "1"
    levelText.ZIndex = 4
    levelText.Parent = levelBadge
    local ticks = {}
    for i = 1, TICKS do
        local ang = math.rad(-90 + (i - 1) * (360 / TICKS))
        local t = Instance.new("Frame")
        t.Name = "Tick" .. i
        t.Size = UDim2.fromOffset(5, 5)
        t.AnchorPoint = Vector2.new(0.5, 0.5)
        t.Position = UDim2.new(0.5, math.cos(ang) * 34, 0.5, math.sin(ang) * 34)
        t.BackgroundColor3 = TICK_DIM
        t.BorderSizePixel = 0
        local tc = Instance.new("UICorner")
        tc.CornerRadius = UDim.new(1, 0)
        tc.Parent = t
        t.ZIndex = 2
        t.Parent = levelBadge
        ticks[i] = t
    end

    -- ---- data + render ----------------------------------------------------
    local palette = Theme.palette(player)
    local curKey = nil
    local function setPills(key)
        if key == curKey then
            return
        end
        curKey = key
        emblem.Image = PILL.panels[key]
        emblemFrame.Image = PILL.frames[key]
        fill.Image = PILL.panels[key]
        levelBadge.Image = PILL.panels[key]
        levelFrame.Image = PILL.frames[key]
    end
    local function applyTheme(p)
        palette = p
        trackStroke.Color = lighten(p.primary, -40)
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

        setPills(ready and READY_KEY or pillKey(palette))
        local litColor = ready and Color3.fromRGB(255, 225, 120) or lighten(palette.primary, 40)
        for i = 1, TICKS do
            ticks[i].BackgroundColor3 = (i <= lit) and litColor or TICK_DIM
        end
        fill.Size = UDim2.new(math.clamp(within, ready and 1 or 0.015, 1), 0, 1, 0)
        xpText.Text = need > 0 and string.format("%d / %d XP", math.floor(xp), need) or ""
        if ready then
            levelText.Text = blinkOn and tostring(level) or "▲"
        else
            levelText.Text = tostring(level)
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
