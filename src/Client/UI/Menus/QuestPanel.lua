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
}

local QuestPanel = {}
QuestPanel.__index = QuestPanel

function QuestPanel.new()
    local self = setmetatable({}, QuestPanel)
    self.isVisible = false
    self.frame = nil
    self.listFrame = nil
    self.rows = {}
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

    -- Scrolling list of quest rows.
    local list = Instance.new("ScrollingFrame")
    list.Name = "QuestList"
    list.Size = UDim2.new(1, -24, 1, -100)
    list.Position = UDim2.new(0, 12, 0, 92)
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

    local close = Instance.new("TextButton")
    close.Name = "CloseButton"
    close.Size = UDim2.new(0, 52, 0, 52)
    close.Position = UDim2.new(1, -64, 0, 12)
    close.BackgroundColor3 = COLORS.close
    close.BorderSizePixel = 0
    close.Text = "✕"
    close.TextColor3 = COLORS.text
    close.TextScaled = true
    close.Font = Enum.Font.GothamBold
    close.ZIndex = 102
    close.Parent = header

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 26)
    closeCorner.Parent = close

    close.Activated:Connect(function()
        self:Hide()
    end)
end

-- Rebuild the list from a fresh quest.list call.
function QuestPanel:_refresh()
    if not self.listFrame then
        return
    end
    for _, row in ipairs(self.rows) do
        row:Destroy()
    end
    self.rows = {}

    local result = self:_callBus("quest.list", {})
    local quests = result and result.quests
    if type(quests) ~= "table" then
        self:_emptyState("Couldn't load quests.")
        return
    end
    if #quests == 0 then
        self:_emptyState("No quests available yet.")
        return
    end

    -- Claimable first, then in-progress, then claimed/done.
    table.sort(quests, function(a, b)
        local function rank(q)
            if q.claimable then
                return 0
            elseif not q.progress or not q.progress.met then
                return 1
            end
            return 2
        end
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then
            return ra < rb
        end
        return (a.name or a.id) < (b.name or b.id)
    end)

    for i, quest in ipairs(quests) do
        table.insert(self.rows, self:_createQuestRow(quest, i))
    end
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
    desc.Text = (quest.description or "")
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

    -- Progress bar track
    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -150, 0, 14)
    track.Position = UDim2.new(0, 16, 1, -26)
    track.BackgroundColor3 = COLORS.track
    track.BorderSizePixel = 0
    track.ZIndex = 103
    track.Parent = row

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fraction = math.clamp(progress.fraction or 0, 0, 1)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(fraction, 0, 1, 0)
    fill.BackgroundColor3 = COLORS.fill
    fill.BorderSizePixel = 0
    fill.ZIndex = 104
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local progressText = Instance.new("TextLabel")
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.BackgroundTransparency = 1
    progressText.Text = string.format("%d / %d", progress.current or 0, progress.target or 0)
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
