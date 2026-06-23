--[[
    QuestPanel — the client UI for the reward spine's Quest gate (Phase 8).

    Mirrors the ShopPanel structure (.new / Show(parent) / Hide / GetFrame /
    IsVisible / Destroy) so MenuManager opens it when the "Quest" side-menu button
    is clicked. Data comes live from the server through the GameAPICommand bus
    bridge: `quest.list` (rows with progress + claimable) and `quest.claim`.

        local QuestPanel = require(script.QuestPanel)
        menuManager:RegisterPanel("Quest", QuestPanel.new())
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CloseButton = require(script.Parent.Parent.Components.CloseButton)
local FillBar = require(script.Parent.Parent.FillBar)

local REMOTE_NAME = "GameAPICommand"

-- Palette (teal card aesthetic matching the side menu).
local COLORS = {
    panel = Color3.fromRGB(20, 20, 25),
    panelGradientTop = Color3.fromRGB(30, 30, 40),
    header = Color3.fromRGB(56, 161, 178),
    headerGradient = Color3.fromRGB(43, 134, 148),
    row = Color3.fromRGB(40, 42, 52),
    rowStroke = Color3.fromRGB(70, 74, 88),
    track = Color3.fromRGB(28, 30, 38),
    fill = Color3.fromRGB(46, 204, 113),
    claimable = Color3.fromRGB(46, 204, 113),
    claimableHover = Color3.fromRGB(39, 174, 96),
    locked = Color3.fromRGB(70, 74, 88),
    claimed = Color3.fromRGB(90, 96, 110),
    close = Color3.fromRGB(231, 76, 60),
    text = Color3.fromRGB(255, 255, 255),
    subtext = Color3.fromRGB(200, 205, 215),
    focus = Color3.fromRGB(241, 196, 15), -- gold accent for the ACTIVE (focused) track
}

local QuestPanel = {}
QuestPanel.__index = QuestPanel

function QuestPanel.new()
    local self = setmetatable({}, QuestPanel)
    self.isVisible = false
    self.frame = nil
    self.listFrame = nil
    self.rows = {}
    -- Branch TABS: quests are grouped into tracks (configs/quests.lua); the tab bar filters the
    -- list to one branch. "all" = the cross-branch overview (claimable surfaced first).
    self.tabBar = nil
    self.tabButtons = {}
    self.viewedTab = "all"
    -- focusTrack = the server's ACTIVE track (the one whose grind quests are counting). Distinct
    -- from viewedTab (which branch you're browsing). Set from quest.list's `activeTrack`.
    self.focusTrack = nil
    self.quests = {}
    return self
end

-- Call a bus command through the shared GameAPICommand RemoteFunction. Returns the
-- handler result table ({ ok = ... }) or nil on transport failure.
function QuestPanel:_callBus(name, args)
    local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
    if not remote then
        return nil
    end
    local ok, envelope = pcall(function()
        return remote:InvokeServer(name, args or {})
    end)
    if not ok or type(envelope) ~= "table" then
        return nil
    end
    return envelope.result
end

function QuestPanel:Show(parent)
    if self.isVisible then
        return
    end
    self:_createUI(parent)
    self.isVisible = true
    self:_refresh()
end

function QuestPanel:Hide()
    if not self.isVisible then
        return
    end
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    self.listFrame = nil
    self.rows = {}
    self.isVisible = false
end

function QuestPanel:IsVisible()
    return self.isVisible
end

function QuestPanel:GetFrame()
    return self.frame
end

function QuestPanel:Destroy()
    self:Hide()
end

function QuestPanel:_createUI(parent)
    local frame = Instance.new("Frame")
    frame.Name = "QuestPanel"
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

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.header
    stroke.Thickness = 3
    stroke.Transparency = 0.3
    stroke.Parent = frame

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS.panelGradientTop),
        ColorSequenceKeypoint.new(1, COLORS.panel),
    })
    gradient.Rotation = 45
    gradient.Parent = frame

    self:_createHeader()
    self:_createTabBar()

    -- Scrolling list of quest rows (sits below the header + branch tab bar).
    local list = Instance.new("ScrollingFrame")
    list.Name = "QuestList"
    list.Size = UDim2.new(1, -24, 1, -144)
    list.Position = UDim2.new(0, 12, 0, 136)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 6
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.ZIndex = 101
    list.Parent = frame
    self.listFrame = list

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 10)
    layout.Parent = list

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 4)
    pad.Parent = list

    self:_animateEntrance()
end

function QuestPanel:_createHeader()
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 76)
    header.BackgroundColor3 = COLORS.header
    header.BorderSizePixel = 0
    header.ZIndex = 101
    header.Parent = self.frame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 20)
    headerCorner.Parent = header

    local headerGradient = Instance.new("UIGradient")
    headerGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS.header),
        ColorSequenceKeypoint.new(1, COLORS.headerGradient),
    })
    headerGradient.Rotation = 90
    headerGradient.Parent = header

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -180, 1, 0)
    title.Position = UDim2.new(0, 24, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🎯 Quests"
    title.TextColor3 = COLORS.text
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 102
    title.Parent = header

    local titleConstraint = Instance.new("UITextSizeConstraint")
    titleConstraint.MaxTextSize = 34
    titleConstraint.Parent = title

    -- THE standard close X (shared component; the old "✕" glyph tofu-boxed in Gotham)
    CloseButton.attach(header, {
        zindex = 102,
        onClick = function()
            self:Hide()
        end,
    })
end

-- Sort rank for the cross-branch "All" view: claimable first, then in-progress, then done.
local function claimRank(q)
    if q.claimable then
        return 0
    elseif not q.progress or not q.progress.met then
        return 1
    end
    return 2
end

-- Horizontal, scrollable strip of branch tabs (sits between the header and the list). Tabs
-- themselves are filled in by _buildTabs once quest.list reveals which branches exist.
local TAB_BAR_Y = 84
local TAB_BAR_H = 44

function QuestPanel:_createTabBar()
    local bar = Instance.new("ScrollingFrame")
    bar.Name = "TabBar"
    bar.Size = UDim2.new(1, -24, 0, TAB_BAR_H)
    bar.Position = UDim2.new(0, 12, 0, TAB_BAR_Y)
    bar.BackgroundTransparency = 1
    bar.BorderSizePixel = 0
    bar.ScrollBarThickness = 4
    bar.ScrollingDirection = Enum.ScrollingDirection.X
    bar.CanvasSize = UDim2.new(0, 0, 0, 0)
    bar.AutomaticCanvasSize = Enum.AutomaticSize.X
    bar.ZIndex = 101
    bar.Parent = self.frame
    self.tabBar = bar

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 6)
    layout.Parent = bar
end

-- One tab button. `key` = "all" or a track id; `hasClaimable` adds a green dot so you can see
-- which branch has something waiting without opening it.
function QuestPanel:_makeTab(key, label, order, hasClaimable)
    local active = self.viewedTab == key
    local btn = Instance.new("TextButton")
    btn.Name = "Tab_" .. key
    btn.AutomaticSize = Enum.AutomaticSize.X
    btn.Size = UDim2.new(0, 0, 1, -8)
    local focused = self.focusTrack ~= nil and key == self.focusTrack
    btn.Text = (focused and "▶ " or "") .. label
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 16
    btn.TextColor3 = active and COLORS.text or COLORS.subtext
    btn.BackgroundColor3 = active and COLORS.header or COLORS.row
    btn.AutoButtonColor = true
    btn.LayoutOrder = order
    btn.ZIndex = 102
    btn.Parent = self.tabBar

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 16)
    pad.PaddingRight = UDim.new(0, 16)
    pad.Parent = btn

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = btn

    -- Gold outline on the ACTIVE (focused) track so you can tell it apart from the one you're viewing.
    if focused then
        local fstroke = Instance.new("UIStroke")
        fstroke.Color = COLORS.focus
        fstroke.Thickness = 2
        fstroke.Parent = btn
    end

    if hasClaimable then
        local dot = Instance.new("Frame")
        dot.Name = "ClaimDot"
        dot.Size = UDim2.fromOffset(10, 10)
        dot.AnchorPoint = Vector2.new(1, 0)
        dot.Position = UDim2.new(1, -2, 0, 3)
        dot.BackgroundColor3 = COLORS.claimable
        dot.BorderSizePixel = 0
        dot.ZIndex = 103
        dot.Parent = btn
        local dc = Instance.new("UICorner")
        dc.CornerRadius = UDim.new(1, 0)
        dc.Parent = dot
    end

    btn.Activated:Connect(function()
        if self.viewedTab ~= key then
            self.viewedTab = key
            self:_restyleTabs()
            self:_renderRows()
        end
    end)
    self.tabButtons[key] = btn
end

-- Recolor tabs to reflect the active branch (cheap; no rebuild).
function QuestPanel:_restyleTabs()
    for key, btn in pairs(self.tabButtons) do
        local active = key == self.viewedTab
        btn.BackgroundColor3 = active and COLORS.header or COLORS.row
        btn.TextColor3 = active and COLORS.text or COLORS.subtext
    end
end

-- (Re)build the tab strip from the branches present in the quest list. Keeps the current
-- selection if it still exists, else falls back to "All".
function QuestPanel:_buildTabs(quests)
    for _, btn in pairs(self.tabButtons) do
        btn:Destroy()
    end
    self.tabButtons = {}

    local seen, tracks, claimableByTrack = {}, {}, {}
    for _, q in ipairs(quests) do
        local t = q.track or "misc"
        if not seen[t] then
            seen[t] = true
            table.insert(
                tracks,
                { key = t, title = q.trackTitle or t, order = q.trackOrder or math.huge }
            )
        end
        if q.claimable then
            claimableByTrack[t] = true
        end
    end
    table.sort(tracks, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.title < b.title
    end)

    -- Drop a stale selection (e.g. a branch that no longer appears).
    local stillValid = self.viewedTab == "all"
    for _, t in ipairs(tracks) do
        if t.key == self.viewedTab then
            stillValid = true
        end
    end
    if not stillValid then
        self.viewedTab = "all"
    end

    self:_makeTab("all", "All", 0, false)
    for i, t in ipairs(tracks) do
        self:_makeTab(t.key, t.title, i, claimableByTrack[t.key] == true)
    end
end

-- Render the quest rows for the active branch. "All" surfaces claimable first (an actionable
-- overview); a single branch shows its ladder in order (head first, then what's coming).
function QuestPanel:_renderRows()
    if not self.listFrame then
        return
    end
    for _, row in ipairs(self.rows) do
        row:Destroy()
    end
    self.rows = {}

    local filtered = {}
    for _, q in ipairs(self.quests or {}) do
        if self.viewedTab == "all" or q.track == self.viewedTab then
            table.insert(filtered, q)
        end
    end
    if #filtered == 0 then
        self:_emptyState("No quests in this branch yet.")
        return
    end

    if self.viewedTab == "all" then
        table.sort(filtered, function(a, b)
            local ra, rb = claimRank(a), claimRank(b)
            if ra ~= rb then
                return ra < rb
            end
            return (a.name or a.id) < (b.name or b.id)
        end)
    else
        table.sort(filtered, function(a, b)
            return (a.order or 0) < (b.order or 0)
        end)
    end

    -- On a single branch, lead with the activation banner (Activate / Active / Always tracked).
    if self.viewedTab ~= "all" then
        local hasGrind = false
        for _, q in ipairs(filtered) do
            if q.activationGated then
                hasGrind = true
                break
            end
        end
        local banner = self:_activationControl(self.viewedTab, hasGrind)
        if banner then
            table.insert(self.rows, banner)
        end
    end

    for i, quest in ipairs(filtered) do
        table.insert(self.rows, self:_createQuestRow(quest, i))
    end
end

-- The per-branch activation control shown atop a single-branch view:
--   • this branch is the focus  -> a green "Active — counting" banner
--   • has grind quests, not focus -> a gold "▶ Activate this branch" button (switches focus here)
--   • only milestones           -> a subtle "Always tracked" note (no activation needed)
function QuestPanel:_activationControl(track, hasGrind)
    local isFocus = self.focusTrack ~= nil and track == self.focusTrack

    local row = Instance.new("Frame")
    row.Name = "ActivationBanner"
    row.Size = UDim2.new(1, 0, 0, 44)
    row.BackgroundColor3 = isFocus and COLORS.fill or (hasGrind and COLORS.row or COLORS.track)
    row.BackgroundTransparency = isFocus and 0.15 or 0
    row.BorderSizePixel = 0
    row.LayoutOrder = 0 -- always first
    row.ZIndex = 102
    row.Parent = self.listFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = row

    if isFocus then
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -24, 1, 0)
        label.Position = UDim2.new(0, 12, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = "▶ Active branch — quests are counting"
        label.TextColor3 = COLORS.text
        label.Font = Enum.Font.GothamBold
        label.TextScaled = true
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 103
        label.Parent = row
        local c = Instance.new("UITextSizeConstraint")
        c.MaxTextSize = 18
        c.Parent = label
    elseif hasGrind then
        local stroke = Instance.new("UIStroke")
        stroke.Color = COLORS.focus
        stroke.Thickness = 2
        stroke.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = "▶ Activate this branch (start its quests counting)"
        btn.TextColor3 = COLORS.focus
        btn.Font = Enum.Font.GothamBold
        btn.TextScaled = true
        btn.AutoButtonColor = false
        btn.ZIndex = 103
        btn.Parent = row
        local c = Instance.new("UITextSizeConstraint")
        c.MaxTextSize = 18
        c.Parent = btn
        btn.Activated:Connect(function()
            self:_callBus("quest.setActiveTrack", { track = track })
            self:_refresh()
        end)
    else
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -24, 1, 0)
        label.Position = UDim2.new(0, 12, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = "Always tracked — no activation needed"
        label.TextColor3 = COLORS.subtext
        label.Font = Enum.Font.Gotham
        label.TextScaled = true
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 103
        label.Parent = row
        local c = Instance.new("UITextSizeConstraint")
        c.MaxTextSize = 16
        c.Parent = label
    end

    return row
end

-- Rebuild from a fresh quest.list call: cache the data, refresh the tabs, render the branch.
function QuestPanel:_refresh()
    if not self.listFrame then
        return
    end
    local result = self:_callBus("quest.list", {})
    local quests = result and result.quests
    if type(quests) ~= "table" then
        for _, row in ipairs(self.rows) do
            row:Destroy()
        end
        self.rows = {}
        self:_emptyState("Couldn't load quests.")
        return
    end
    self.quests = quests
    self.focusTrack = result.activeTrack -- which branch is currently counting (may be nil)
    self:_buildTabs(quests)
    self:_renderRows()
end

function QuestPanel:_emptyState(text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 60)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLORS.subtext
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.ZIndex = 102
    label.Parent = self.listFrame

    local constraint = Instance.new("UITextSizeConstraint")
    constraint.MaxTextSize = 20
    constraint.Parent = label

    table.insert(self.rows, label)
end

local function rewardSummary(reward)
    -- reward = { currencies = { coins = 100 }, items = {...}, pets = {...} }
    local parts = {}
    for currency, amount in pairs((reward and reward.currencies) or {}) do
        table.insert(parts, string.format("%d %s", amount, currency))
    end
    for _, item in ipairs((reward and reward.items) or {}) do
        table.insert(parts, string.format("%dx %s", item.qty or 1, item.id))
    end
    for _, pet in ipairs((reward and reward.pets) or {}) do
        table.insert(parts, "pet: " .. tostring(pet.id))
    end
    if #parts == 0 then
        return ""
    end
    return "Reward: " .. table.concat(parts, ", ")
end

function QuestPanel:_createQuestRow(quest, order)
    local progress = quest.progress or { current = 0, target = 1, fraction = 0, met = false }

    local row = Instance.new("Frame")
    row.Name = "Quest_" .. tostring(quest.id)
    row.Size = UDim2.new(1, 0, 0, 96)
    row.BackgroundColor3 = COLORS.row
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.ZIndex = 102
    row.Parent = self.listFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = row

    local stroke = Instance.new("UIStroke")
    stroke.Color = quest.claimable and COLORS.claimable or COLORS.rowStroke
    stroke.Thickness = quest.claimable and 2 or 1
    stroke.Transparency = quest.claimable and 0.1 or 0.5
    stroke.Parent = row

    -- Title
    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -150, 0, 26)
    name.Position = UDim2.new(0, 16, 0, 10)
    name.BackgroundTransparency = 1
    name.Text = (quest.locked and "🔒 " or "") .. (quest.name or quest.id)
    name.TextColor3 = quest.locked and COLORS.subtext or COLORS.text
    name.TextScaled = true
    name.Font = Enum.Font.GothamBold
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.ZIndex = 103
    name.Parent = row

    local nameConstraint = Instance.new("UITextSizeConstraint")
    nameConstraint.MaxTextSize = 20
    nameConstraint.Parent = name

    -- Description / reward line
    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, -150, 0, 18)
    desc.Position = UDim2.new(0, 16, 0, 36)
    desc.BackgroundTransparency = 1
    local rewardText = rewardSummary(quest.reward)
    local trackTag = quest.trackTitle and ("[" .. quest.trackTitle .. "]  ") or ""
    desc.Text = trackTag
        .. (quest.description or "")
        .. (rewardText ~= "" and ("   •   " .. rewardText) or "")
    desc.TextColor3 = COLORS.subtext
    desc.TextScaled = true
    desc.Font = Enum.Font.Gotham
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.ZIndex = 103
    desc.Parent = row

    local descConstraint = Instance.new("UITextSizeConstraint")
    descConstraint.MaxTextSize = 14
    descConstraint.Parent = desc

    -- Progress bar track (shared FillBar). A paused grind quest (its branch isn't the focus) shows
    -- a muted fill so it reads as "not currently counting".
    local fraction = math.clamp(progress.fraction or 0, 0, 1)
    local track = FillBar.create({
        parent = row,
        size = UDim2.new(1, -150, 0, 14),
        position = UDim2.new(0, 16, 1, -26),
        bgColor = COLORS.track,
        fillColor = quest.paused and COLORS.locked or COLORS.fill,
        fraction = fraction,
        zIndex = 103,
    })

    local progressText = Instance.new("TextLabel")
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.BackgroundTransparency = 1
    progressText.Text = string.format("%d / %d", progress.current or 0, progress.target or 0)
        .. (quest.paused and "  ⏸" or "")
    progressText.TextColor3 = COLORS.text
    progressText.TextScaled = true
    progressText.Font = Enum.Font.GothamMedium
    progressText.ZIndex = 105
    progressText.Parent = track

    local progressConstraint = Instance.new("UITextSizeConstraint")
    progressConstraint.MaxTextSize = 11
    progressConstraint.Parent = progressText

    -- Claim button
    local claim = Instance.new("TextButton")
    claim.Name = "ClaimButton"
    claim.Size = UDim2.new(0, 116, 0, 64)
    claim.Position = UDim2.new(1, -130, 0.5, -32)
    claim.BorderSizePixel = 0
    claim.TextColor3 = COLORS.text
    claim.TextScaled = true
    claim.Font = Enum.Font.GothamBold
    claim.ZIndex = 104
    claim.Parent = row

    local claimCorner = Instance.new("UICorner")
    claimCorner.CornerRadius = UDim.new(0, 10)
    claimCorner.Parent = claim

    local claimConstraint = Instance.new("UITextSizeConstraint")
    claimConstraint.MaxTextSize = 18
    claimConstraint.Parent = claim

    local claimedOnce = (quest.claimedCount or 0) > 0
    if quest.claimable then
        claim.Text = "Claim"
        claim.BackgroundColor3 = COLORS.claimable
        claim.AutoButtonColor = true
        claim.Active = true
        claim.Activated:Connect(function()
            self:_claim(quest.id, claim)
        end)
    elseif claimedOnce and not quest.repeatable then
        claim.Text = "Claimed ✓"
        claim.BackgroundColor3 = COLORS.claimed
        claim.AutoButtonColor = false
        claim.Active = false
    else
        claim.Text = "Locked"
        claim.BackgroundColor3 = COLORS.locked
        claim.AutoButtonColor = false
        claim.Active = false
    end

    return row
end

function QuestPanel:_claim(questId, button)
    if button then
        button.Text = "…"
        button.Active = false
    end
    local result = self:_callBus("quest.claim", { questId = questId })
    if result and result.ok then
        self:_refresh() -- counters/claimable state changed
    elseif button then
        button.Text = "Claim"
        button.Active = true
    end
end

function QuestPanel:_animateEntrance()
    if not self.frame then
        return
    end
    self.frame.Size = UDim2.new(0.6, 0, 0.75, 0)
    local tween = TweenService:Create(
        self.frame,
        TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = UDim2.new(0.7, 0, 0.85, 0) }
    )
    tween:Play()
end

return QuestPanel
