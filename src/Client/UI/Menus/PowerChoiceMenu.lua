--[[
    PowerChoiceMenu — the interactive level-up workflow (Feature 14/15 surface).

    Dual column: NATURAL (generic pool, purple) + one ORIGIN archetype (element-coloured).
    You level up from 1; every level grants SOMETHING to do (config-driven cadence):
      • a power-pick level (in powers.selection_levels) -> pick ONE not-yet-owned power
        that's unlocked at your level (click an "available" row).
      • otherwise -> place 2 enhancement slots onto powers you already own (click an "owned"
        row to add a slot, up to 6 — the slots PowerSlotRow already draws).

    SELF-CONTAINED for now: it keeps its OWN model (level / owned[powerId]=slotCount / pending
    picks + slots) and appends every action to `self.log` ({ action="pick"|"slot", id, level }).
    Nothing hits the server yet — once the flow feels right, each logged action maps 1:1 to a bus
    call (pick -> power.select, slot -> augment.place) + the real endgame effects.

    Opened by the admin "POWER CHOICE" button (later: a level-up nudge). Switching origin via the
    header button RESETS the run so each origin can be walked from L1.

    MenuManager panel interface: new() -> { Show(parent), Hide(), GetFrame() }.
]]

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
local NATURAL_COLOR = Color3.fromRGB(196, 156, 255)
local MAX_LEVEL = 50
local MAX_SLOTS = 6
local SLOTS_PER_ROUND = 2

-- selection levels -> set, for O(1) "is this a power level?"
local SEL = {}
for _, l in ipairs(powersCfg.selection_levels or {}) do
    SEL[l] = true
end

-- what a given level grants: "power" (1, on a selection level) or "slots" (2). L1 grants nothing —
-- the lowest power unlocks at L2, so the first LEVEL UP (to L2) hands you your first pick.
local function grantFor(level)
    if SEL[level] then
        return "power", 1
    end
    return "slots", SLOTS_PER_ROUND
end

local function pickLevelOf(id)
    local def = powersCfg.powers[id]
    return PowerSelection.pickLevel(def and def.unlock_level or 1, powersCfg.selection_levels)
end

local PowerChoiceMenu = {}
PowerChoiceMenu.__index = PowerChoiceMenu

function PowerChoiceMenu.new()
    local self = setmetatable({}, PowerChoiceMenu)
    self.frame = nil
    self.originIndex = 1
    self.level = 1
    self.owned = {} -- [powerId] = slotCount (1..6)
    self.pendingPower = 0
    self.pendingSlots = 0
    self.log = {} -- { { action = "pick"|"slot", id = powerId, level = n }, ... }
    -- ui refs
    self.naturalCol = nil
    self.originCol = nil
    self.originHeader = nil
    self.statusLabel = nil
    self.levelBtn = nil
    return self
end

-- ---- model ---------------------------------------------------------------

function PowerChoiceMenu:_grant(level)
    local kind, n = grantFor(level)
    if kind == "power" then
        self.pendingPower += n
    else
        self.pendingSlots += n
    end
end

function PowerChoiceMenu:_reset()
    self.level = 1
    self.owned = {}
    self.pendingPower = 0
    self.pendingSlots = 0
    self.log = {}
    -- L1 grants nothing; the first LEVEL UP (to L2) hands the first power pick.
end

function PowerChoiceMenu:_levelUp()
    if self.level >= MAX_LEVEL then
        return
    end
    self.level += 1
    self:_grant(self.level)
    self:_render()
end

-- click a row: place a slot on it (owned + slots pending) OR pick it (available + pick pending).
function PowerChoiceMenu:_onRow(id)
    if self.owned[id] then
        if self.pendingSlots > 0 and self.owned[id] < MAX_SLOTS then
            self.owned[id] += 1
            self.pendingSlots -= 1
            self.log[#self.log + 1] = { action = "slot", id = id, level = self.level }
            self:_render()
        end
    else
        if self.pendingPower > 0 and pickLevelOf(id) <= self.level then
            self.owned[id] = 1 -- a freshly-picked power comes with its inherent first slot
            self.pendingPower -= 1
            self.log[#self.log + 1] = { action = "pick", id = id, level = self.level }
            self:_render()
        end
    end
end

-- ---- render --------------------------------------------------------------

function PowerChoiceMenu:_statusText()
    if self.pendingPower > 0 then
        return ("PICK A POWER  (%d left)"):format(self.pendingPower), Color3.fromRGB(150, 230, 150)
    elseif self.pendingSlots > 0 then
        return ("PLACE A SLOT  (%d left) — click an owned power"):format(self.pendingSlots),
            Color3.fromRGB(140, 200, 255)
    end
    return "All set — Level Up", Color3.fromRGB(200, 200, 210)
end

function PowerChoiceMenu:_fillColumn(holder, pool)
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    if not pool then
        return
    end
    local ownedSet = {}
    for id in pairs(self.owned) do
        ownedSet[id] = true
    end
    local rows = PowerSelection.menuRows(
        pool,
        powersCfg.powers,
        self.level,
        ownedSet,
        powersCfg.selection_levels
    )
    for i, r in ipairs(rows) do
        local def = powersCfg.powers[r.id] or {}
        -- a row is ACTIONABLE this beat if you can act on it now (pick it / slot it)
        local actionable = (
            r.state == "owned"
            and self.pendingSlots > 0
            and (self.owned[r.id] or 0) < MAX_SLOTS
        ) or (r.state == "available" and self.pendingPower > 0)
        local wrap = Instance.new("TextButton")
        wrap.Name = "Row_" .. r.id
        wrap.LayoutOrder = i
        wrap.Size = UDim2.fromScale(0.99, 0.075)
        wrap.BackgroundTransparency = 1
        wrap.AutoButtonColor = false
        wrap.Text = ""
        wrap.Parent = holder
        wrap.Activated:Connect(function()
            self:_onRow(r.id)
        end)
        PowerSlotRow.create(wrap, {
            powerId = r.id,
            name = def.display_name or r.id,
            subtitle = "L" .. tostring(r.pickLevel) .. "    " .. (def.subtitle or ""),
            state = r.state,
            slotCount = self.owned[r.id] or 1,
            size = UDim2.fromScale(1, 1),
        })
        -- subtle "you can act here" glow
        if actionable then
            local glow = Instance.new("UIStroke")
            glow.Color = (r.state == "owned") and Color3.fromRGB(140, 200, 255)
                or Color3.fromRGB(150, 230, 150)
            glow.Thickness = 2
            glow.Transparency = 0.15
            local bar = wrap:FindFirstChild("PowerRow") and wrap.PowerRow:FindFirstChild("Bar")
            if bar then
                glow.Parent = bar
            end
        end
    end
end

function PowerChoiceMenu:_refreshOrigin()
    local origin = ORIGINS[self.originIndex]
    local def = archetypesCfg.archetypes and archetypesCfg.archetypes[origin]
    if self.originHeader then
        self.originHeader.Text = "‹ " .. (def and def.display_name or origin):upper() .. " ›"
        self.originHeader.TextColor3 = ORIGIN_COLOR[origin] or Color3.new(1, 1, 1)
    end
    if self.originCol then
        self:_fillColumn(self.originCol, def and def.power_pool)
    end
end

function PowerChoiceMenu:_render()
    if self.naturalCol then
        self:_fillColumn(self.naturalCol, archetypesCfg.generic_pool)
    end
    self:_refreshOrigin()
    if self.statusLabel then
        local txt, col = self:_statusText()
        self.statusLabel.Text = txt
        self.statusLabel.TextColor3 = col
    end
    if self.levelBtn then
        self.levelBtn.Text = (self.level >= MAX_LEVEL) and ("MAX (L" .. MAX_LEVEL .. ")")
            or ("LEVEL UP  ▶   (L" .. self.level .. ")")
        self.levelBtn.AutoButtonColor = self.level < MAX_LEVEL
    end
end

-- ---- build ---------------------------------------------------------------

local function makeColumnHolder(parent, xScale)
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(0.46, 0.82)
    f.Position = UDim2.fromScale(xScale, 0.14)
    f.BackgroundTransparency = 1
    f.Parent = parent
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0.004, 0)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = f
    return f
end

local function chip(parent, text, size, pos, color, order)
    local b = Instance.new("TextButton")
    b.LayoutOrder = order or 0
    b.Size = size
    b.Position = pos
    b.AnchorPoint = Vector2.new(0.5, 0.5)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(20, 20, 28)
    b.Font = Enum.Font.GothamBold
    b.TextScaled = true
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.4, 0)
    c.Parent = b
    return b
end

function PowerChoiceMenu:Show(parent)
    local root = Instance.new("Frame")
    root.Name = "PowerChoiceMenu"
    root.Size = UDim2.fromScale(0.5, 0.92)
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
    title.Size = UDim2.fromScale(0.6, 0.05)
    title.Position = UDim2.fromScale(0.2, 0.012)
    title.BackgroundTransparency = 1
    title.Text = "POWER CHOICE"
    title.TextColor3 = Color3.fromRGB(235, 230, 250)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = root

    -- status line (what to do this beat)
    local status = Instance.new("TextLabel")
    status.Size = UDim2.fromScale(0.8, 0.035)
    status.Position = UDim2.fromScale(0.5, 0.075)
    status.AnchorPoint = Vector2.new(0.5, 0)
    status.BackgroundTransparency = 1
    status.Text = ""
    status.TextScaled = true
    status.Font = Enum.Font.GothamMedium
    status.Parent = root
    self.statusLabel = status

    -- close
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

    -- headers
    local nHeader = Instance.new("TextLabel")
    nHeader.Size = UDim2.fromScale(0.46, 0.045)
    nHeader.Position = UDim2.fromScale(0.02, 0.105)
    nHeader.BackgroundTransparency = 1
    nHeader.Text = "NATURAL"
    nHeader.TextColor3 = NATURAL_COLOR
    nHeader.TextScaled = true
    nHeader.Font = Enum.Font.GothamBold
    nHeader.Parent = root

    local oHeader = Instance.new("TextButton")
    oHeader.Size = UDim2.fromScale(0.46, 0.045)
    oHeader.Position = UDim2.fromScale(0.52, 0.103)
    oHeader.BackgroundColor3 = Color3.fromRGB(46, 43, 60)
    oHeader.BackgroundTransparency = 0.35
    oHeader.AutoButtonColor = true
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
        self:_reset() -- a new origin = a fresh run from L1
        self:_render()
    end)

    -- columns + divider
    self.naturalCol = makeColumnHolder(root, 0.02)
    self.originCol = makeColumnHolder(root, 0.52)
    local div = Instance.new("Frame")
    div.Size = UDim2.fromScale(0.0025, 0.78)
    div.Position = UDim2.fromScale(0.5, 0.55)
    div.AnchorPoint = Vector2.new(0.5, 0.5)
    div.BackgroundColor3 = Color3.fromRGB(120, 110, 80)
    div.BorderSizePixel = 0
    div.Parent = root

    -- bottom controls: LEVEL UP (advance + grant) + RESET
    self.levelBtn = chip(
        root,
        "LEVEL UP  ▶",
        UDim2.fromScale(0.3, 0.05),
        UDim2.fromScale(0.42, 0.965),
        Color3.fromRGB(120, 205, 130),
        1
    )
    self.levelBtn.Activated:Connect(function()
        self:_levelUp()
    end)
    local resetBtn = chip(
        root,
        "↺ RESET",
        UDim2.fromScale(0.16, 0.05),
        UDim2.fromScale(0.74, 0.965),
        Color3.fromRGB(150, 120, 200),
        2
    )
    resetBtn.Activated:Connect(function()
        self:_reset()
        self:_render()
    end)

    self:_reset()
    self:_render()
    root.Parent = parent
end

function PowerChoiceMenu:Hide()
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    self.naturalCol = nil
    self.originCol = nil
    self.originHeader = nil
    self.statusLabel = nil
    self.levelBtn = nil
end

function PowerChoiceMenu:GetFrame()
    return self.frame
end

return PowerChoiceMenu
