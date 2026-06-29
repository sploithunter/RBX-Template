--[[
    EffectsPanel - Player and Global Effects Management
    
    Features:
    - Display active player effects with timers
    - Show global effects affecting all players
    - Effect activation/deactivation controls
    - Visual effect indicators and progress bars
    - Integration with PlayerEffectsService
    
    Usage:
    local EffectsPanel = require(script.EffectsPanel)
    local effects = EffectsPanel.new()
    MenuManager:RegisterPanel("Effects", effects)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get shared modules
local Locations = require(ReplicatedStorage.Shared.Locations)
local CloseButton = require(script.Parent.Parent.Components.CloseButton)
local FillBar = require(script.Parent.Parent.FillBar)
local PILL = require(ReplicatedStorage.Configs:WaitForChild("pill_ui"))
local UITheme = require(script.Parent.Parent.UITheme)

-- Game-standard panel chrome, patterned 1:1 on AchievementsPanel (Jason: panels share one styling
-- path — area-themed pill border, relative scaling, close-X on top). See AchievementsPanel for the
-- canonical version; TODO extract a shared PanelChrome module to dedupe these three helpers.
local function areaPill()
    local pal = UITheme.palette(Players.LocalPlayer)
    local key = pal.color
    if key == nil or key == "neutral" or not PILL.panels[key] then
        key = "sapphire"
    end
    return key, pal.primary
end

-- Neon hollow pill ring (9-sliced) over an element edge. bleed = px to extend (panel) or inset
-- (rows, +small) the ring; sliceScale lower = thinner + pushed outward (0.10 panel, 0.18 rows).
local function pillBorder(parent, key, zindex, bleed, sliceScale)
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

local COLORS = {
    panel = Color3.fromRGB(20, 20, 25),
    panelGradientTop = Color3.fromRGB(30, 30, 40),
    row = Color3.fromRGB(40, 42, 52),
    text = Color3.fromRGB(255, 255, 255),
    subtext = Color3.fromRGB(200, 205, 215),
}

-- Per-event skin (glyph + accent), keyed by the event's icon code (events.lua `icon`). Covers the
-- weekday calendar + the manual hourly events; anything unknown falls back to the bolt.
-- pillKey maps the event color to a game pill ring key (emerald/citrine/ruby/sapphire/amethyst), so
-- each event row's pill matches its identity color (Mineral Monday's gem → emerald), same pill art
-- the rest of the HUD uses.
local EVENT_SKINS = {
    SECRET = { glyph = "✨", accent = Color3.fromRGB(170, 90, 220), pillKey = "amethyst" },
    CRYS = { glyph = "💎", accent = Color3.fromRGB(46, 204, 113), pillKey = "emerald" },
    COIN = { glyph = "🪙", accent = Color3.fromRGB(241, 196, 15), pillKey = "citrine" },
    LUCK = { glyph = "🍀", accent = Color3.fromRGB(39, 174, 96), pillKey = "emerald" },
    XP = { glyph = "⭐", accent = Color3.fromRGB(52, 152, 219), pillKey = "sapphire" },
    ["2X"] = { glyph = "💰", accent = Color3.fromRGB(231, 76, 60), pillKey = "ruby" },
    DROP = { glyph = "🎁", accent = Color3.fromRGB(155, 89, 182), pillKey = "amethyst" },
    DAY = { glyph = "🍀", accent = Color3.fromRGB(39, 174, 96), pillKey = "emerald" },
}
local DEFAULT_SKIN = { glyph = "⚡", accent = Color3.fromRGB(90, 160, 220), pillKey = "sapphire" }

local function skinFor(effect)
    return EVENT_SKINS[tostring(effect.icon or ""):upper()] or DEFAULT_SKIN
end

-- Load Logger with wrapper (following the established pattern)
local LoggerWrapper
local loggerSuccess, loggerResult = pcall(function()
    return require(Locations.Logger)
end)

if loggerSuccess and loggerResult then
    LoggerWrapper = {
        new = function(name)
            return {
                info = function(self, ...)
                    loggerResult:Info("[" .. name .. "] " .. tostring((...)), { context = name })
                end,
                warn = function(self, ...)
                    loggerResult:Warn("[" .. name .. "] " .. tostring((...)), { context = name })
                end,
                error = function(self, ...)
                    loggerResult:Error("[" .. name .. "] " .. tostring((...)), { context = name })
                end,
                debug = function(self, ...)
                    loggerResult:Debug("[" .. name .. "] " .. tostring((...)), { context = name })
                end,
            }
        end,
    }
else
    LoggerWrapper = {
        new = function(name)
            return {
                info = function(self, ...)
                    print("[" .. name .. "] INFO:", ...)
                end,
                warn = function(self, ...)
                    warn("[" .. name .. "] WARN:", ...)
                end,
                error = function(self, ...)
                    warn("[" .. name .. "] ERROR:", ...)
                end,
                debug = function(self, ...)
                    print("[" .. name .. "] DEBUG:", ...)
                end,
            }
        end,
    }
end

-- Load TemplateManager
local TemplateManager
local templateSuccess, templateResult = pcall(function()
    return require(Locations.TemplateManager)
end)
if templateSuccess and templateResult then
    TemplateManager = templateResult
else
    -- Fallback TemplateManager
    TemplateManager = {
        new = function()
            return {
                CreatePanel = function()
                    return nil
                end,
                CreateFromTemplate = function()
                    return nil
                end,
            }
        end,
    }
end

-- Load UI config
local uiConfig
local configSuccess, configResult = pcall(function()
    return Locations.getConfig("ui")
end)
if configSuccess and configResult then
    uiConfig = configResult
else
    uiConfig = {
        themes = {
            dark = {
                primary = { surface = Color3.fromRGB(40, 40, 45) },
                text = { primary = Color3.fromRGB(255, 255, 255) },
            },
        },
        active_theme = "dark",
        helpers = {
            get_theme = function(config)
                return config.themes.dark
            end,
        },
    }
end

local EffectsPanel = {}
EffectsPanel.__index = EffectsPanel

function EffectsPanel.new()
    local self = setmetatable({}, EffectsPanel)

    self.logger = LoggerWrapper.new("EffectsPanel")
    self.templateManager = TemplateManager.new()

    -- Panel state
    self.isVisible = false
    self.frame = nil
    self.effectsData = {
        playerEffects = {},
        globalEffects = {},
    }

    self.effectDisplays = {}

    return self
end

function EffectsPanel:Show(parent)
    if self.isVisible then
        return
    end

    self:_createUI(parent)
    self:_loadEffectsData()

    self.isVisible = true
    self.logger:info("Effects panel shown")
end

function EffectsPanel:Hide()
    if not self.isVisible then
        return
    end

    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end

    self.isVisible = false
    self.logger:info("Effects panel hidden")
end

function EffectsPanel:_createUI(parent)
    -- AREA/ORIGIN-THEMED panel chrome, patterned on AchievementsPanel: pill border + header take the
    -- player's home-area color; relative sizing scales with the panel; close-X on top.
    self._areaKey = areaPill()
    local _, areaColor = areaPill()
    local headerColor = areaColor or Color3.fromRGB(90, 160, 220)
    local headerDim = headerColor:Lerp(Color3.fromRGB(0, 0, 0), 0.35)

    local frame = Instance.new("Frame")
    frame.Name = "EffectsPanel"
    frame.Size = UDim2.new(0.7, 0, 0.85, 0)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = COLORS.panel
    frame.BorderSizePixel = 0
    frame.ZIndex = 100
    frame.Parent = parent
    self.frame = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 20)
    corner.Parent = frame

    -- Game-standard pill ring around the whole panel (bleed 0 + SliceScale 0.10 — Jason's tune).
    pillBorder(frame, self._areaKey, 130, 0, 0.10)

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS.panelGradientTop),
        ColorSequenceKeypoint.new(1, COLORS.panel),
    })
    gradient.Rotation = 45
    gradient.Parent = frame

    -- Header (relative height, area-themed gradient)
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
    title.Size = UDim2.new(1, -180, 1, 0)
    title.Position = UDim2.new(0, 24, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "⚡ Events"
    title.TextColor3 = COLORS.text
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 102
    title.Parent = header
    local tc = Instance.new("UITextSizeConstraint")
    tc.MaxTextSize = 34
    tc.Parent = title

    -- Close X — sibling of the pill border at Z146 so it's on top (see AchievementsPanel note).
    CloseButton.attach(frame, {
        zindex = 146,
        onClick = function()
            self:Hide()
        end,
    })

    -- Scrolling list of event rows (relative — scales with the panel)
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "EffectsScroll"
    scrollFrame.Size = UDim2.new(0.95, 0, 0.83, 0)
    scrollFrame.Position = UDim2.new(0.03, 0, 0.13, 0)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollFrame.ZIndex = 101
    scrollFrame.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 10)
    layout.Parent = scrollFrame

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 4)
    pad.Parent = scrollFrame

    self.scrollFrame = scrollFrame
end

function EffectsPanel:_loadEffectsData()
    self.effectsData = {
        playerEffects = {},
        globalEffects = {},
    }

    local signals = require(ReplicatedStorage.Shared.Network.Signals)
    signals.ActiveEffects:FireServer({ request = true })
    self:_updateEffectsDisplay()
end

function EffectsPanel:_updateEffectsDisplay()
    -- Clear existing displays
    for _, display in pairs(self.effectDisplays) do
        display:Destroy()
    end
    self.effectDisplays = {}

    local layoutOrder = 1
    local globals = self.effectsData.globalEffects or {}
    local players = self.effectsData.playerEffects or {}

    -- Active global EVENTS lead — this is the "Events" button's surface. Only render the
    -- header when the section actually has entries (an empty section header looked like a
    -- broken placeholder row).
    if #globals > 0 then
        self:_createSectionHeader("Active Events", layoutOrder)
        layoutOrder = layoutOrder + 1
        for _, effect in ipairs(globals) do
            self:_createEffectDisplay(effect, "global", layoutOrder)
            layoutOrder = layoutOrder + 1
        end
    end

    -- The player's own active effects, if any.
    if #players > 0 then
        self:_createSectionHeader("Your Effects", layoutOrder)
        layoutOrder = layoutOrder + 1
        for _, effect in ipairs(players) do
            self:_createEffectDisplay(effect, "player", layoutOrder)
            layoutOrder = layoutOrder + 1
        end
    end

    if #globals == 0 and #players == 0 then
        self:_createSectionHeader("No active effects right now", layoutOrder)
    end
end

function EffectsPanel:_createSectionHeader(title, layoutOrder)
    -- Slim, left-aligned section header with an accent underline (replaces the big flat blue bar).
    local header = Instance.new("Frame")
    header.Name = title .. "Header"
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundTransparency = 1
    header.LayoutOrder = layoutOrder
    header.Parent = self.scrollFrame

    local accentDot = Instance.new("Frame")
    accentDot.Size = UDim2.fromOffset(4, 16)
    accentDot.Position = UDim2.new(0, 4, 0.5, -8)
    accentDot.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
    accentDot.BorderSizePixel = 0
    accentDot.Parent = header
    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = accentDot

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -24, 1, 0)
    label.Position = UDim2.new(0, 16, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = string.upper(title)
    label.TextColor3 = Color3.fromRGB(215, 220, 230)
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = header

    -- track it so the next refresh DESTROYS it (headers used to leak: only effect rows were
    -- tracked, so every ActiveEffects payload stacked another "Player Effects"/"Global Effects")
    table.insert(self.effectDisplays, header)
end

function EffectsPanel:_createEffectDisplay(effect, _effectType, layoutOrder)
    local skin = skinFor(effect)
    local DARK = Color3.fromRGB(22, 24, 31)

    local card = Instance.new("Frame")
    card.Name = tostring(effect.id or effect.name or "effect") .. "Display"
    card.Size = UDim2.new(1, 0, 0, 80)
    card.BackgroundColor3 = COLORS.row
    card.BorderSizePixel = 0
    card.LayoutOrder = layoutOrder
    card.ZIndex = 102
    card.Parent = self.scrollFrame
    table.insert(self.effectDisplays, card)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = card

    -- subtle top->bottom sheen for depth
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.88),
        NumberSequenceKeypoint.new(1, 1),
    })
    grad.Parent = card

    -- Game pill ring in the event's color (Mineral Monday's gem → emerald), same as Achievements
    -- rows: bleed 2 (centered on the edge) + SliceScale 0.08. Hollow ring → content shows through.
    pillBorder(card, skin.pillKey or "sapphire", 105, 2, 0.08)

    -- icon disc (accent-tinted, ringed). ZIndex 103 > card's 102 so it shows (Sibling behavior).
    local disc = Instance.new("Frame")
    disc.Size = UDim2.fromOffset(54, 54)
    disc.Position = UDim2.new(0, 24, 0.5, -27)
    disc.BackgroundColor3 = skin.accent:Lerp(DARK, 0.4)
    disc.BorderSizePixel = 0
    disc.ZIndex = 103
    disc.Parent = card
    local discCorner = Instance.new("UICorner")
    discCorner.CornerRadius = UDim.new(1, 0)
    discCorner.Parent = disc
    local discRing = Instance.new("UIStroke")
    discRing.Color = skin.accent
    discRing.Thickness = 2
    discRing.Transparency = 0.1
    discRing.Parent = disc

    local glyph = Instance.new("TextLabel")
    glyph.Size = UDim2.fromScale(1, 1)
    glyph.BackgroundTransparency = 1
    glyph.Text = skin.glyph
    glyph.TextSize = 28
    glyph.ZIndex = 104
    glyph.Parent = disc

    -- title
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -210, 0, 22)
    nameLabel.Position = UDim2.new(0, 92, 0, 14)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = tostring(effect.name or effect.displayName or effect.id or "Event")
    nameLabel.TextColor3 = COLORS.text
    nameLabel.TextSize = 19
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.ZIndex = 103
    nameLabel.Parent = card

    -- effect / description line (what it does)
    local descLabel = Instance.new("TextLabel")
    descLabel.Size = UDim2.new(1, -210, 0, 34)
    descLabel.Position = UDim2.new(0, 92, 0, 38)
    descLabel.BackgroundTransparency = 1
    descLabel.Text = (effect.description ~= nil and effect.description ~= "")
            and tostring(effect.description)
        or "Active event"
    descLabel.TextColor3 = COLORS.subtext
    descLabel.TextSize = 13
    descLabel.Font = Enum.Font.Gotham
    descLabel.TextXAlignment = Enum.TextXAlignment.Left
    descLabel.TextYAlignment = Enum.TextYAlignment.Top
    descLabel.TextWrapped = true
    descLabel.ZIndex = 103
    descLabel.Parent = card

    -- status pill (right): Permanent or a live countdown
    local remaining = tonumber(effect.remaining or effect.timeRemaining or 0) or 0
    local duration = tonumber(effect.duration or remaining) or remaining
    local pill = Instance.new("TextLabel")
    pill.Size = UDim2.fromOffset(96, 26)
    pill.Position = UDim2.new(1, -110, 0, 14)
    pill.BackgroundColor3 = skin.accent:Lerp(DARK, 0.15)
    pill.Text = remaining == -1 and "Permanent"
        or string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60)
    pill.TextColor3 = Color3.fromRGB(255, 255, 255)
    pill.TextSize = 12
    pill.Font = Enum.Font.GothamMedium
    pill.ZIndex = 104
    pill.Parent = card
    local pillCorner = Instance.new("UICorner")
    pillCorner.CornerRadius = UDim.new(1, 0)
    pillCorner.Parent = pill

    -- progress bar for timed events (accent-filled)
    if remaining ~= -1 then
        local progress = duration > 0 and math.clamp(remaining / duration, 0, 1) or 0
        FillBar.create({
            parent = card,
            size = UDim2.new(1, -112, 0, 4),
            position = UDim2.new(0, 92, 1, -14),
            cornerRadius = UDim.new(0, 2),
            bgColor = Color3.fromRGB(55, 58, 68),
            fillColor = skin.accent,
            fraction = progress,
            zIndex = 103, -- above the card (102) so it shows under Sibling z-order
        })
    end
end

-- Update effects data (call this periodically)
function EffectsPanel:UpdateEffects(newEffectsData)
    if newEffectsData then
        if newEffectsData.effects and newEffectsData.effects.globalEffects then
            self.effectsData = {
                playerEffects = newEffectsData.effects.playerEffects
                    or self.effectsData.playerEffects
                    or {},
                globalEffects = newEffectsData.effects.globalEffects
                    or self.effectsData.globalEffects
                    or {},
            }
        elseif newEffectsData.globalEvents then
            self.effectsData = {
                playerEffects = self.effectsData.playerEffects or {},
                globalEffects = newEffectsData.globalEvents,
            }
        elseif newEffectsData.playerEffects or newEffectsData.globalEffects then
            self.effectsData = {
                playerEffects = newEffectsData.playerEffects
                    or self.effectsData.playerEffects
                    or {},
                globalEffects = newEffectsData.globalEffects
                    or self.effectsData.globalEffects
                    or {},
            }
        else
            local playerEffects = {}
            for effectId, effect in pairs(newEffectsData.effects or newEffectsData) do
                if type(effect) == "table" then
                    effect.id = effect.id or effectId
                    effect.name = effect.name or effect.displayName or effectId
                    effect.remaining = effect.remaining or effect.timeRemaining
                    table.insert(playerEffects, effect)
                end
            end
            self.effectsData = {
                playerEffects = playerEffects,
                globalEffects = self.effectsData.globalEffects or {},
            }
        end
    end

    if self.isVisible then
        self:_updateEffectsDisplay()
    end
end

-- Public interface methods
function EffectsPanel:IsVisible()
    return self.isVisible
end

function EffectsPanel:GetFrame()
    return self.frame
end

function EffectsPanel:Destroy()
    self:Hide()
    self.logger:info("Effects panel destroyed")
end

return EffectsPanel
