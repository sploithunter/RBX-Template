--[[
    PowerChoiceMenu — the dual-column Power Choice screen (Feature 14 surface).

    Left column = the NEUTRAL/generic pool (purple discs); right column = ONE origin
    archetype's pool (element-coloured discs). Each row is a PowerSlotRow, ordered by
    unlock_level then id (via PowerSelection.menuRows) and gated against the viewing
    level (available / locked). Powers are config-driven — pools from configs/archetypes,
    names/subtitles/levels from configs/powers — so this needs no code change to retune.

    Right now it's opened by the ADMIN "POWER CHOICE" button (AdminController) as a live
    inspector: a SWITCH-ORIGIN button cycles geomancer → sandwalker → cryomancer →
    pyromancer, and − / + step the viewing level (1..50) so the whole cadence can be read
    in-game. The same component is the basis for the real level-up power pick later.

    MenuManager panel interface: new() -> { Show(parent), Hide(), GetFrame() }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local powersCfg = require(Configs:WaitForChild("powers"))
local archetypesCfg = require(Configs:WaitForChild("archetypes"))
local PowerSelection = require(ReplicatedStorage.Shared.Game.PowerSelection)
local PowerSlotRow = require(script.Parent.Parent.PowerSlotRow)

local ORIGINS = { "geomancer", "sandwalker", "cryomancer", "pyromancer" }
local ORIGIN_COLOR = {
    geomancer = Color3.fromRGB(150, 230, 150),
    sandwalker = Color3.fromRGB(240, 215, 130),
    cryomancer = Color3.fromRGB(140, 200, 255),
    pyromancer = Color3.fromRGB(255, 150, 120),
}
local NEUTRAL_COLOR = Color3.fromRGB(196, 156, 255)
local MAX_LEVEL = 50

local PowerChoiceMenu = {}
PowerChoiceMenu.__index = PowerChoiceMenu

function PowerChoiceMenu.new()
    local self = setmetatable({}, PowerChoiceMenu)
    self.frame = nil
    self.originIndex = 1
    self.level = nil -- resolved on Show
    self.originColumn = nil
    self.originHeader = nil
    self.levelLabel = nil
    return self
end

-- one column's rows: clears `holder`, then a PowerSlotRow per menuRow (ordered + gated).
function PowerChoiceMenu:_fillColumn(holder, pool)
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    if not pool then
        return
    end
    local rows =
        PowerSelection.menuRows(pool, powersCfg.powers, self.level, {}, powersCfg.selection_levels)
    for i, r in ipairs(rows) do
        local def = powersCfg.powers[r.id] or {}
        local wrap = Instance.new("Frame")
        wrap.Name = "Row_" .. r.id
        wrap.LayoutOrder = i
        wrap.Size = UDim2.fromScale(0.99, 0.075)
        wrap.BackgroundTransparency = 1
        wrap.Parent = holder
        PowerSlotRow.create(wrap, {
            powerId = r.id,
            name = def.display_name or r.id,
            subtitle = "L" .. tostring(r.pickLevel) .. "    " .. (def.subtitle or ""),
            state = r.state,
            size = UDim2.fromScale(1, 1),
        })
    end
end

function PowerChoiceMenu:_refreshOrigin()
    local origin = ORIGINS[self.originIndex]
    local def = archetypesCfg.archetypes and archetypesCfg.archetypes[origin]
    if self.originHeader then
        self.originHeader.Text = "‹ " .. (def and def.display_name or origin):upper() .. " ›"
        self.originHeader.TextColor3 = ORIGIN_COLOR[origin] or Color3.new(1, 1, 1)
    end
    if self.originColumn then
        self:_fillColumn(self.originColumn, def and def.power_pool)
    end
end

local function makeColumnHolder(parent, xScale)
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(0.46, 0.86)
    f.Position = UDim2.fromScale(xScale, 0.12)
    f.BackgroundTransparency = 1
    f.Parent = parent
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0.004, 0)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = f
    return f
end

function PowerChoiceMenu:Show(parent)
    local lp = Players.LocalPlayer
    local lvl = lp and lp:GetAttribute("Level")
    self.level = math.clamp(math.floor(tonumber(lvl) or 6), 1, MAX_LEVEL)

    local root = Instance.new("Frame")
    root.Name = "PowerChoiceMenu"
    root.Size = UDim2.fromScale(0.5, 0.9)
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.fromScale(0.5, 0.5)
    root.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    root.BorderSizePixel = 0
    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0.02, 0)
    rc.Parent = root
    local rs = Instance.new("UIStroke")
    rs.Color = Color3.fromRGB(70, 64, 96)
    rs.Thickness = 2
    rs.Parent = root
    self.frame = root

    local title = Instance.new("TextLabel")
    title.Size = UDim2.fromScale(0.6, 0.06)
    title.Position = UDim2.fromScale(0.2, 0.015)
    title.BackgroundTransparency = 1
    title.Text = "POWER CHOICE"
    title.TextColor3 = Color3.fromRGB(235, 230, 250)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = root

    -- close button
    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(34, 34)
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -12, 0, 12)
    close.BackgroundColor3 = Color3.fromRGB(120, 50, 60)
    close.Text = "✕"
    close.TextColor3 = Color3.fromRGB(255, 235, 235)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 18
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(1, 0)
    cc.Parent = close
    close.Parent = root
    close.Activated:Connect(function()
        if _G.MenuManager then
            _G.MenuManager:CloseCurrentPanel()
        end
    end)

    -- column headers
    local nHeader = Instance.new("TextLabel")
    nHeader.Size = UDim2.fromScale(0.46, 0.05)
    nHeader.Position = UDim2.fromScale(0.02, 0.065)
    nHeader.BackgroundTransparency = 1
    nHeader.Text = "NATURAL"
    nHeader.TextColor3 = NEUTRAL_COLOR
    nHeader.TextScaled = true
    nHeader.Font = Enum.Font.GothamBold
    nHeader.Parent = root

    local oHeader = Instance.new("TextButton")
    oHeader.Size = UDim2.fromScale(0.46, 0.05)
    oHeader.Position = UDim2.fromScale(0.52, 0.062)
    oHeader.BackgroundColor3 = Color3.fromRGB(46, 43, 60)
    oHeader.BackgroundTransparency = 0.35
    oHeader.AutoButtonColor = true -- pill + hover highlight = reads as a button
    oHeader.Text = ""
    oHeader.TextScaled = true
    oHeader.Font = Enum.Font.GothamBold
    oHeader.Parent = root
    local ohc = Instance.new("UICorner")
    ohc.CornerRadius = UDim.new(0.35, 0)
    ohc.Parent = oHeader
    local ohs = Instance.new("UIStroke")
    ohs.Color = Color3.fromRGB(120, 110, 150)
    ohs.Thickness = 1.5
    ohs.Parent = oHeader
    self.originHeader = oHeader
    oHeader.Activated:Connect(function()
        self.originIndex = (self.originIndex % #ORIGINS) + 1
        self:_refreshOrigin()
    end)

    -- columns + divider
    local neutralCol = makeColumnHolder(root, 0.02)
    self.originColumn = makeColumnHolder(root, 0.52)
    local div = Instance.new("Frame")
    div.Size = UDim2.fromScale(0.0025, 0.8)
    div.Position = UDim2.fromScale(0.5, 0.55)
    div.AnchorPoint = Vector2.new(0.5, 0.5)
    div.BackgroundColor3 = Color3.fromRGB(120, 110, 80)
    div.BorderSizePixel = 0
    div.Parent = root

    -- level stepper (bottom-centre): − [Lv N] + to scrub the whole cadence
    local stepHolder = Instance.new("Frame")
    stepHolder.Size = UDim2.fromScale(0.24, 0.05)
    stepHolder.Position = UDim2.fromScale(0.5, 0.975)
    stepHolder.AnchorPoint = Vector2.new(0.5, 1)
    stepHolder.BackgroundTransparency = 1
    stepHolder.Parent = root
    local sl = Instance.new("UIListLayout")
    sl.FillDirection = Enum.FillDirection.Horizontal
    sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sl.VerticalAlignment = Enum.VerticalAlignment.Center
    sl.Padding = UDim.new(0.03, 0)
    sl.Parent = stepHolder
    local function stepBtn(text, order)
        local b = Instance.new("TextButton")
        b.LayoutOrder = order
        b.Size = UDim2.fromScale(0.22, 1)
        b.BackgroundColor3 = Color3.fromRGB(70, 64, 96)
        b.Text = text
        b.TextColor3 = Color3.fromRGB(235, 230, 250)
        b.Font = Enum.Font.GothamBold
        b.TextScaled = true
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0.4, 0)
        bc.Parent = b
        b.Parent = stepHolder
        return b
    end
    local minus = stepBtn("−", 1)
    local lvlLabel = Instance.new("TextLabel")
    lvlLabel.LayoutOrder = 2
    lvlLabel.Size = UDim2.fromScale(0.44, 1)
    lvlLabel.BackgroundTransparency = 1
    lvlLabel.TextColor3 = Color3.fromRGB(235, 230, 250)
    lvlLabel.Font = Enum.Font.GothamMedium
    lvlLabel.TextScaled = true
    lvlLabel.Parent = stepHolder
    self.levelLabel = lvlLabel
    local plus = stepBtn("+", 3)
    local function refreshLevel()
        lvlLabel.Text = "Viewing  Level " .. self.level
    end
    local function step(delta)
        self.level = math.clamp(self.level + delta, 1, MAX_LEVEL)
        refreshLevel()
        self:_fillColumn(neutralCol, archetypesCfg.generic_pool)
        self:_refreshOrigin()
    end
    minus.Activated:Connect(function()
        step(-1)
    end)
    plus.Activated:Connect(function()
        step(1)
    end)

    -- initial fill
    self:_fillColumn(neutralCol, archetypesCfg.generic_pool)
    self:_refreshOrigin()
    refreshLevel()

    root.Parent = parent
end

function PowerChoiceMenu:Hide()
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    self.originColumn = nil
    self.originHeader = nil
    self.levelLabel = nil
end

function PowerChoiceMenu:GetFrame()
    return self.frame
end

return PowerChoiceMenu
