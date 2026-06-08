--[[
    PowerSlotRow — a single CoH-style "power with its enhancement slots" widget.

        local row = PowerSlotRow.create(parent, {
            powerId = "fortune",          -- drives the disc badge (PetBadge.forPower)
            name = "Luck",                -- display name (defaults to the power's display_name)
            subtitle = "Targeted DoT",    -- SHORT description tag (full description won't fit the bar)
            slotCount = 6,                -- enhancement slots on the bar (1..6)
            selected = 6,                 -- highlighted slot index (optional)
            size = UDim2.fromOffset(540, 60),
            theme = PowerSlotRow.THEMES.blue,  -- palette (generic→purple is just a different theme)
        })
        row.setSelected(3); row.setSubtitle("Targeted DoT"); row.destroy()

    A glossy ROUND capsule (UICorner pill) holds the power's disc inset at the left, its name +
    short subtitle, and a row of enhancement-slot circles. Each slot is a Fill (gradient circle, inset)
    framed by a Border ring (the round ring art on top) — so the ring reads as the rim, not inside the
    fill. Built against assets/ui/reference/power_slotting_reference.png. Visuals match the values
    tuned live in Studio (StarterGui.ZZ_SlotOverlay).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerIcons = require(ReplicatedStorage.Configs:WaitForChild("power_icons"))
local PetBadge = require(script.Parent.PetBadge)

local RING_IMAGE = "rbxassetid://121697559002218" -- round ring frame (rim for slots + disc)

local PowerSlotRow = {}

-- Slot X centres (scale of the bar width) + Y; reproduces the tuned layout. The row spreads N slots
-- evenly from FIRST_X to LAST_X regardless of count, so 1..6 all look right.
local FIRST_X, LAST_X, SLOT_Y = 0.177, 0.930, 1.0233
local MAX_SLOTS = 6

-- Palettes. Swap the whole row's look by passing a different theme (generic→purple later).
PowerSlotRow.THEMES = {
    blue = {
        bar = Color3.fromRGB(40, 120, 230),
        barGrad = { Color3.fromRGB(95, 175, 255), Color3.fromRGB(40, 120, 230), Color3.fromRGB(20, 80, 190) },
        barStroke = Color3.fromRGB(15, 55, 130),
        slotFillGrad = { Color3.fromRGB(140, 187, 244), Color3.fromRGB(46, 132, 236), Color3.fromRGB(29, 85, 153) },
        slotRim = Color3.fromRGB(18, 70, 160),
        slotRimSelected = Color3.fromRGB(120, 205, 255),
        discRim = Color3.fromRGB(120, 120, 128),
    },
}

local function corner(o, scale)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(scale or 1, 0)
    c.Parent = o
    return c
end

local function vGradient(o, colors, rotation)
    local g = Instance.new("UIGradient")
    g.Rotation = rotation or 90
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, colors[1]),
        ColorSequenceKeypoint.new(0.5, colors[2]),
        ColorSequenceKeypoint.new(1, colors[3]),
    })
    g.Parent = o
    return g
end

-- a top sheen (white, fading down) used on the bar and inside each slot
local function gloss(parent, size, pos)
    local gl = Instance.new("Frame")
    gl.Name = "Gloss"
    gl.Size = size
    gl.Position = pos
    gl.AnchorPoint = Vector2.new(0.5, 0.5)
    gl.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    gl.BackgroundTransparency = 0.5
    gl.Parent = parent
    corner(gl)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    g.Parent = gl
    return gl
end

-- one enhancement slot: Fill (gradient circle, inset) + Border (ring rim on top).
local function buildSlot(theme, selected)
    local s = Instance.new("Frame")
    s.BackgroundTransparency = 1

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.AnchorPoint = Vector2.new(0.5, 0.5)
    fill.Position = UDim2.fromScale(0.5, 0.5)
    fill.Size = UDim2.fromScale(0.82, 0.82)
    fill.BackgroundColor3 = theme.slotFillGrad[2]
    fill.Parent = s
    corner(fill)
    vGradient(fill, theme.slotFillGrad)
    gloss(fill, UDim2.fromScale(0.6, 0.34), UDim2.new(0.5, 0, 0.26, 0))

    local border = Instance.new("ImageLabel")
    border.Name = "Border"
    border.BackgroundTransparency = 1
    border.Size = UDim2.fromScale(1, 1)
    border.Image = RING_IMAGE
    border.ImageColor3 = selected and theme.slotRimSelected or theme.slotRim
    border.Parent = s
    return s
end

-- the power disc (authored badge image inset, framed by a ring).
local function buildDisc(parent, powerId, height, theme)
    local disc = Instance.new("Frame")
    disc.Name = "Disc"
    disc.Size = UDim2.fromOffset(height + 5, height + 5)
    disc.Position = UDim2.new(0, -2, 0.5, 0)
    disc.AnchorPoint = Vector2.new(0, 0.5)
    disc.BackgroundTransparency = 1
    disc.Parent = parent

    local badge = PetBadge.forPower(powerId)
    local discImg = badge and PowerIcons.discFor(badge.element, badge.symbol) or nil

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.BackgroundTransparency = 1
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.fromScale(0.5, 0.5)
    icon.Size = UDim2.fromScale(0.86, 0.86)
    icon.Image = discImg or ""
    icon.Parent = disc

    local border = Instance.new("ImageLabel")
    border.Name = "Border"
    border.BackgroundTransparency = 1
    border.Size = UDim2.fromScale(1, 1)
    border.Image = RING_IMAGE
    border.ImageColor3 = theme.discRim
    border.Parent = disc
    return disc
end

-- create(parent, opts) -> { root, setSelected, setSubtitle, setName, destroy }
function PowerSlotRow.create(parent, opts)
    opts = opts or {}
    local theme = opts.theme or PowerSlotRow.THEMES.blue
    local size = opts.size or UDim2.fromOffset(540, 60)
    local height = size.Y.Offset > 0 and size.Y.Offset or 60
    local slotCount = math.clamp(tonumber(opts.slotCount) or 6, 1, MAX_SLOTS)
    local slotSize = math.floor(height * 1.13 + 0.5)

    local root = Instance.new("Frame")
    root.Name = "PowerRow"
    root.Size = size
    root.BackgroundTransparency = 1
    root.Parent = parent

    -- bar: round glossy capsule
    local bar = Instance.new("Frame")
    bar.Name = "Bar"
    bar.Size = UDim2.fromScale(1, 1)
    bar.BackgroundColor3 = theme.bar
    bar.Parent = root
    corner(bar)
    vGradient(bar, theme.barGrad)
    local bs = Instance.new("UIStroke")
    bs.Color = theme.barStroke
    bs.Thickness = 2
    bs.Parent = bar
    gloss(bar, UDim2.new(1, -16, 0.4, 0), UDim2.new(0.5, 0, 0, 4 + height * 0.2))

    buildDisc(bar, opts.powerId, height, theme)

    -- name (top-left) + subtitle (top-right; the SHORT description tag)
    local name = Instance.new("TextLabel")
    name.Name = "PowerName"
    name.BackgroundTransparency = 1
    name.Position = UDim2.new(0, height + 12, 0, 6)
    name.Size = UDim2.new(0, 220, 0, 22)
    name.Font = Enum.Font.GothamBold
    name.TextSize = 19
    name.TextColor3 = Color3.fromRGB(255, 255, 255)
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Text = opts.name or ""
    name.Parent = bar

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.BackgroundTransparency = 1
    subtitle.AnchorPoint = Vector2.new(1, 0)
    subtitle.Position = UDim2.new(1, -16, 0, 9)
    subtitle.Size = UDim2.new(0, 240, 0, 16)
    subtitle.Font = Enum.Font.GothamMedium
    subtitle.TextSize = 12
    subtitle.TextColor3 = Color3.fromRGB(214, 226, 245)
    subtitle.TextTransparency = 0.08
    subtitle.TextXAlignment = Enum.TextXAlignment.Right
    subtitle.Text = opts.subtitle or ""
    subtitle.Visible = (opts.subtitle ~= nil and opts.subtitle ~= "")
    subtitle.Parent = bar

    -- slots
    local slotsFolder = Instance.new("Frame")
    slotsFolder.Name = "Slots"
    slotsFolder.Size = UDim2.fromScale(1, 1)
    slotsFolder.BackgroundTransparency = 1
    slotsFolder.Parent = bar

    local slots = {}
    for i = 1, slotCount do
        local s = buildSlot(theme, opts.selected == i)
        s.Name = "Slot" .. i
        s.Size = UDim2.fromOffset(slotSize, slotSize)
        s.AnchorPoint = Vector2.new(0.5, 0.5)
        local fx = slotCount == 1 and (FIRST_X + LAST_X) / 2
            or (FIRST_X + (LAST_X - FIRST_X) * ((i - 1) / (slotCount - 1)))
        s.Position = UDim2.new(fx, 0, SLOT_Y, 0)
        s.Parent = slotsFolder
        slots[i] = s
    end

    local handle = { root = root }
    function handle.setName(t)
        name.Text = t or ""
    end
    function handle.setSubtitle(t)
        subtitle.Text = t or ""
        subtitle.Visible = (t ~= nil and t ~= "")
    end
    function handle.setSelected(idx)
        for i, s in ipairs(slots) do
            local b = s:FindFirstChild("Border")
            if b then
                b.ImageColor3 = (i == idx) and theme.slotRimSelected or theme.slotRim
            end
        end
    end
    function handle.destroy()
        root:Destroy()
    end
    return handle
end

return PowerSlotRow
