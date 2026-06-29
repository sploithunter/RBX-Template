--[[
    PanelChrome — THE shared exterior for menu panels (Jason 2026-06-29: "build the exterior of each
    of these menus with the same code base and require it in — you get the outside window, the X in
    its correct position, the outside pill, the code that changes colors. Single code path").

    `build(parent, opts)` returns the themed window shell:
      • outer Frame (relative size, dark gradient fill, rounded corner)
      • area/origin-colored pill BORDER (the outer edge — nothing extends past it)
      • header bar (relative height, area-color gradient) + left-aligned TextScaled title
      • the standard close X as a FRAME sibling at Z146 (on top of the 130 border, Sibling z-order)
    → { frame, header, areaKey, areaColor }. The caller fills content under `frame`.

    `scrollPane(frame, opts)` returns the standard list pane: full width, bottom 70% of the parent
    (Size {1,0,0.7,0} @ {0.5,0,0.3,0}) with a vertical UIListLayout + content padding — so every
    panel's list is the same relative width/height with the same entry treatment. All overridable.

    Also exposes `areaPill` / `pillBorder` / `pillPanel` for rows/tabs.

        local PanelChrome = require(script.Parent.Parent.Components.PanelChrome)
        local shell = PanelChrome.build(parent, { name = "EffectsPanel", title = "⚡ Events",
            onClose = function() self:Hide() end })
        local list = PanelChrome.scrollPane(shell.frame)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CloseButton = require(script.Parent.CloseButton)
local PILL = require(ReplicatedStorage.Configs:WaitForChild("pill_ui"))
local UITheme = require(script.Parent.Parent.UITheme)

local PanelChrome = {}

local COLORS = {
    panel = Color3.fromRGB(20, 20, 25),
    panelGradientTop = Color3.fromRGB(30, 30, 40),
    text = Color3.fromRGB(255, 255, 255),
}
PanelChrome.COLORS = COLORS

-- The player's HOME-AREA/origin palette → a valid pill key (fire=ruby, ice=sapphire, …), falling
-- back to sapphire. Same rule the tray/HUD use, so panels re-tint to match when origin is picked.
function PanelChrome.areaPill()
    local pal = UITheme.palette(Players.LocalPlayer)
    local key = pal.color
    if key == nil or key == "neutral" or not PILL.panels[key] then
        key = "sapphire"
    end
    return key, pal.primary
end

-- Neon hollow pill ring (9-sliced) over an element edge. bleed = px to extend (panel) or inset
-- (rows, +small) the ring; sliceScale lower = thinner + pushed outward (0.10 panel, 0.18 tabs,
-- 0.08 rows). The ring center is transparent so content shows through.
function PanelChrome.pillBorder(parent, key, zindex, bleed, sliceScale)
    bleed = bleed or 8
    local img = Instance.new("ImageLabel")
    img.Name = "PillBorder"
    img.BackgroundTransparency = 1
    img.Image = PILL.frames[key] or PILL.frames.sapphire
    img.ScaleType = Enum.ScaleType.Slice
    img.SliceCenter = Rect.new(180, 180, 330, 330)
    img.SliceScale = sliceScale or 0.18
    img.AnchorPoint = Vector2.new(0.5, 0.5)
    img.Position = UDim2.fromScale(0.5, 0.5)
    img.Size = UDim2.new(1, bleed, 1, bleed)
    img.ZIndex = zindex or 105
    img.Parent = parent
    return img
end

-- Filled pill PANEL (rounded gloss fill) for tab/button backgrounds. INSET vs the frame so the pill
-- ring is always the outer edge (nothing expands beyond the pill). Sits BELOW the label.
function PanelChrome.pillPanel(parent, key, zindex)
    local img = Instance.new("ImageLabel")
    img.Name = "PillPanel"
    img.BackgroundTransparency = 1
    img.Image = PILL.panels[key] or PILL.panels.sapphire
    img.ScaleType = Enum.ScaleType.Slice
    img.SliceCenter = Rect.new(180, 180, 330, 330)
    img.SliceScale = 0.18
    img.AnchorPoint = Vector2.new(0.5, 0.5)
    img.Position = UDim2.fromScale(0.5, 0.5)
    img.Size = UDim2.new(1, -10, 1, -10)
    img.ZIndex = zindex or 100
    img.Parent = parent
    return img
end

-- Build the themed window shell. opts: { name, title, onClose, size?, parent? }.
function PanelChrome.build(parent, opts)
    opts = opts or {}
    local areaKey, areaColor = PanelChrome.areaPill()
    local headerColor = areaColor or Color3.fromRGB(90, 160, 220)
    local headerDim = headerColor:Lerp(Color3.fromRGB(0, 0, 0), 0.35)

    local frame = Instance.new("Frame")
    frame.Name = opts.name or "Panel"
    frame.Size = opts.size or UDim2.new(0.7, 0, 0.85, 0)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = COLORS.panel
    frame.BorderSizePixel = 0
    frame.ZIndex = 100
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 20)
    corner.Parent = frame

    -- Outer pill ring: area-themed, the very edge (bleed 0 + SliceScale 0.10 — Jason's tune).
    PanelChrome.pillBorder(frame, areaKey, 130, 0, 0.10)

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS.panelGradientTop),
        ColorSequenceKeypoint.new(1, COLORS.panel),
    })
    gradient.Rotation = 45
    gradient.Parent = frame

    -- Header — relative height, area-color gradient.
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(0.99, 0, 0.1, 0)
    header.Position = UDim2.new(0.5, 0, 0, 0)
    header.AnchorPoint = Vector2.new(0.5, 0)
    header.BackgroundColor3 = headerColor
    header.BorderSizePixel = 0
    header.ZIndex = 101
    header.Parent = frame
    local hc = Instance.new("UICorner")
    hc.CornerRadius = UDim.new(0, 20)
    hc.Parent = header
    local hg = Instance.new("UIGradient")
    hg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, headerColor),
        ColorSequenceKeypoint.new(1, headerDim),
    })
    hg.Rotation = 90
    hg.Parent = header

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -180, 1, 0)
    title.Position = UDim2.new(0, 24, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = opts.title or "Panel"
    title.TextColor3 = COLORS.text
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 102
    title.Parent = header
    local tc = Instance.new("UITextSizeConstraint")
    tc.MaxTextSize = 34
    tc.Parent = title

    -- Close X — sibling of the pill border at Z146 so it's truly on top (under Sibling
    -- ZIndexBehavior, an X nested in the header would sit below the 130 border).
    CloseButton.attach(frame, {
        zindex = 146,
        onClick = opts.onClose,
    })

    return { frame = frame, header = header, areaKey = areaKey, areaColor = headerColor }
end

-- Standard list pane: full width, bottom 70% of the parent (Jason's spec). Overridable via opts:
-- { name, size, position, anchor, padding (between rows), inset (L/R content px) }.
function PanelChrome.scrollPane(frame, opts)
    opts = opts or {}
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = opts.name or "List"
    scroll.Size = opts.size or UDim2.new(1, 0, 0.7, 0)
    scroll.Position = opts.position or UDim2.new(0.5, 0, 0.3, 0)
    scroll.AnchorPoint = opts.anchor or Vector2.new(0.5, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ZIndex = 101
    scroll.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, opts.padding or 10)
    layout.Parent = scroll

    local inset = opts.inset or 14 -- keep rows off the outer pill border
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.PaddingLeft = UDim.new(0, inset)
    pad.PaddingRight = UDim.new(0, inset)
    pad.Parent = scroll

    return scroll, layout
end

return PanelChrome
