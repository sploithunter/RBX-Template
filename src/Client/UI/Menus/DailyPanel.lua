--[[
    DailyPanel — the client UI for the reward spine's Daily streak gate (Phase 9).

    Mirrors the ShopPanel/QuestPanel contract (.new / Show / Hide / GetFrame /
    IsVisible / Destroy) so MenuManager opens it from the "Daily" side-menu button.
    Renders the full streak calendar (claimed / today / upcoming), the current streak,
    and a Claim button. Live data via the GameAPICommand bus bridge: `daily.status`
    (calendar + claimable + streak) and `daily.claim`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CloseButton = require(script.Parent.Parent.Components.CloseButton)

local REMOTE_NAME = "GameAPICommand"

local COLORS = {
    panel = Color3.fromRGB(20, 20, 25),
    panelGradientTop = Color3.fromRGB(30, 30, 40),
    header = Color3.fromRGB(56, 161, 178),
    headerGradient = Color3.fromRGB(43, 134, 148),
    dayClaimed = Color3.fromRGB(39, 120, 92),
    dayToday = Color3.fromRGB(46, 204, 113),
    dayUpcoming = Color3.fromRGB(40, 42, 52),
    dayStroke = Color3.fromRGB(70, 74, 88),
    claimable = Color3.fromRGB(46, 204, 113),
    disabled = Color3.fromRGB(70, 74, 88),
    close = Color3.fromRGB(231, 76, 60),
    text = Color3.fromRGB(255, 255, 255),
    subtext = Color3.fromRGB(200, 205, 215),
    gold = Color3.fromRGB(255, 215, 0),
}

local DailyPanel = {}
DailyPanel.__index = DailyPanel

function DailyPanel.new()
    local self = setmetatable({}, DailyPanel)
    self.isVisible = false
    self.frame = nil
    return self
end

function DailyPanel:_callBus(name, args)
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

function DailyPanel:Show(parent)
    if self.isVisible then
        return
    end
    self:_createUI(parent)
    self.isVisible = true
    self:_refresh()
end

function DailyPanel:Hide()
    if not self.isVisible then
        return
    end
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    self.isVisible = false
end

function DailyPanel:IsVisible()
    return self.isVisible
end

function DailyPanel:GetFrame()
    return self.frame
end

function DailyPanel:Destroy()
    self:Hide()
end

function DailyPanel:_createUI(parent)
    local frame = Instance.new("Frame")
    frame.Name = "DailyPanel"
    frame.Size = UDim2.new(0.62, 0, 0.6, 0)
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

    -- Streak summary line.
    self.streakLabel = Instance.new("TextLabel")
    self.streakLabel.Name = "StreakLabel"
    self.streakLabel.Size = UDim2.new(1, -48, 0, 26)
    self.streakLabel.Position = UDim2.new(0, 24, 0, 88)
    self.streakLabel.BackgroundTransparency = 1
    self.streakLabel.Text = "🔥 Streak: …"
    self.streakLabel.TextColor3 = COLORS.gold
    self.streakLabel.TextScaled = true
    self.streakLabel.Font = Enum.Font.GothamBold
    self.streakLabel.TextXAlignment = Enum.TextXAlignment.Left
    self.streakLabel.ZIndex = 102
    self.streakLabel.Parent = frame
    local streakConstraint = Instance.new("UITextSizeConstraint")
    streakConstraint.MaxTextSize = 22
    streakConstraint.Parent = self.streakLabel

    -- Calendar row container.
    local cal = Instance.new("Frame")
    cal.Name = "Calendar"
    cal.Size = UDim2.new(1, -48, 0, 130)
    cal.Position = UDim2.new(0, 24, 0, 124)
    cal.BackgroundTransparency = 1
    cal.ZIndex = 101
    cal.Parent = frame
    self.calendarFrame = cal

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)
    layout.Parent = cal

    -- Claim button.
    self.claimButton = Instance.new("TextButton")
    self.claimButton.Name = "ClaimButton"
    self.claimButton.Size = UDim2.new(0, 220, 0, 54)
    self.claimButton.Position = UDim2.new(0.5, 0, 1, -42)
    self.claimButton.AnchorPoint = Vector2.new(0.5, 0.5)
    self.claimButton.BackgroundColor3 = COLORS.disabled
    self.claimButton.BorderSizePixel = 0
    self.claimButton.Text = "…"
    self.claimButton.TextColor3 = COLORS.text
    self.claimButton.TextScaled = true
    self.claimButton.Font = Enum.Font.GothamBold
    self.claimButton.ZIndex = 102
    self.claimButton.Parent = frame
    local claimCorner = Instance.new("UICorner")
    claimCorner.CornerRadius = UDim.new(0, 12)
    claimCorner.Parent = self.claimButton
    local claimConstraint = Instance.new("UITextSizeConstraint")
    claimConstraint.MaxTextSize = 22
    claimConstraint.Parent = self.claimButton
    self.claimButton.Activated:Connect(function()
        self:_claim()
    end)

    self:_animateEntrance()
end

function DailyPanel:_createHeader()
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 72)
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
    title.Size = UDim2.new(1, -160, 1, 0)
    title.Position = UDim2.new(0, 24, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "📅 Daily Rewards"
    title.TextColor3 = COLORS.text
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 102
    title.Parent = header
    local titleConstraint = Instance.new("UITextSizeConstraint")
    titleConstraint.MaxTextSize = 30
    titleConstraint.Parent = title

    -- THE standard close X (shared component; the old "✕" glyph tofu-boxed in Gotham)
    CloseButton.attach(header, {
        zindex = 102,
        onClick = function()
            self:Hide()
        end,
    })
end

local CURRENCY_LABELS = {
    area_coins = "Area Coins", -- resolves to the zone-you're-in coin at claim
    grass_coins = "Grass Coins",
    ice_coins = "Ice Coins",
    lava_coins = "Lava Coins",
    desert_coins = "Desert Coins",
}

local function rewardLabel(bundle)
    local parts = {}
    for currency, amount in pairs((bundle and bundle.currencies) or {}) do
        table.insert(parts, amount .. " " .. (CURRENCY_LABELS[currency] or currency))
    end
    for _, pet in ipairs((bundle and bundle.pets) or {}) do
        table.insert(parts, (pet.variant and (pet.variant .. " ") or "") .. tostring(pet.id))
    end
    for _, item in ipairs((bundle and bundle.items) or {}) do
        table.insert(parts, (item.qty or 1) .. "x " .. tostring(item.id))
    end
    if (bundle and bundle.experience or 0) > 0 then
        table.insert(parts, bundle.experience .. " XP")
    end
    return table.concat(parts, "\n")
end

function DailyPanel:_refresh()
    local status = self:_callBus("daily.status", {})
    if not status or not status.ok then
        self.streakLabel.Text = "Couldn't load daily rewards."
        return
    end

    self.streakLabel.Text = string.format(
        "🔥 Streak: %d day%s",
        status.streak or 0,
        (status.streak == 1) and "" or "s"
    )

    -- Rebuild calendar day cards.
    for _, ch in ipairs(self.calendarFrame:GetChildren()) do
        if ch:IsA("Frame") then
            ch:Destroy()
        end
    end

    local cycle = status.cycleLength or 7
    local claimDay = status.claimDay or 1
    local claimedThrough = status.claimable and (claimDay - 1) or claimDay
    for day = 1, cycle do
        self:_createDayCard(
            day,
            status.calendar and status.calendar[tostring(day)],
            claimDay,
            claimedThrough,
            status.claimable
        )
    end

    -- Claim button.
    if status.claimable then
        self.claimButton.Text = "Claim Day " .. claimDay
        self.claimButton.BackgroundColor3 = COLORS.claimable
        self.claimButton.AutoButtonColor = true
        self.claimButton.Active = true
    else
        self.claimButton.Text = "Come back tomorrow"
        self.claimButton.BackgroundColor3 = COLORS.disabled
        self.claimButton.AutoButtonColor = false
        self.claimButton.Active = false
    end
end

function DailyPanel:_createDayCard(day, bundle, claimDay, claimedThrough, claimable)
    local isToday = claimable and day == claimDay
    local isClaimed = day <= claimedThrough

    local card = Instance.new("Frame")
    card.Name = "Day_" .. day
    card.Size = UDim2.new(0, 92, 1, 0)
    card.BackgroundColor3 = isToday and COLORS.dayToday
        or (isClaimed and COLORS.dayClaimed or COLORS.dayUpcoming)
    card.BorderSizePixel = 0
    card.LayoutOrder = day
    card.ZIndex = 102
    card.Parent = self.calendarFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = isToday and COLORS.dayToday or COLORS.dayStroke
    stroke.Thickness = isToday and 2 or 1
    stroke.Transparency = isToday and 0 or 0.5
    stroke.Parent = card

    local dayLabel = Instance.new("TextLabel")
    dayLabel.Size = UDim2.new(1, 0, 0, 22)
    dayLabel.Position = UDim2.new(0, 0, 0, 6)
    dayLabel.BackgroundTransparency = 1
    dayLabel.Text = isClaimed and ("Day " .. day .. " ✓") or ("Day " .. day)
    dayLabel.TextColor3 = COLORS.text
    dayLabel.TextScaled = true
    dayLabel.Font = Enum.Font.GothamBold
    dayLabel.ZIndex = 103
    dayLabel.Parent = card
    local dayConstraint = Instance.new("UITextSizeConstraint")
    dayConstraint.MaxTextSize = 14
    dayConstraint.Parent = dayLabel

    local reward = Instance.new("TextLabel")
    reward.Size = UDim2.new(1, -8, 1, -34)
    reward.Position = UDim2.new(0, 4, 0, 30)
    reward.BackgroundTransparency = 1
    reward.Text = rewardLabel(bundle)
    reward.TextColor3 = COLORS.subtext
    reward.TextWrapped = true
    reward.TextScaled = true
    reward.Font = Enum.Font.Gotham
    reward.ZIndex = 103
    reward.Parent = card
    local rewardConstraint = Instance.new("UITextSizeConstraint")
    rewardConstraint.MaxTextSize = 12
    rewardConstraint.Parent = reward
end

function DailyPanel:_claim()
    self.claimButton.Text = "…"
    self.claimButton.Active = false
    self:_callBus("daily.claim", {})
    -- Refresh regardless: success advances the streak, failure (already claimed)
    -- just re-renders the disabled state.
    self:_refresh()
    -- clear the tray "!" immediately (BaseUI's poll would also catch it within a
    -- minute) — direct instance hide, no BaseUI handle needed from a panel
    local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
    local base = pg and pg:FindFirstChild("ProfessionalBaseUI")
    local btn = base and base:FindFirstChild("DailyButton", true)
    local badge = btn and btn:FindFirstChild("Notification")
    if badge then
        badge.Visible = false
    end
end

function DailyPanel:_animateEntrance()
    if not self.frame then
        return
    end
    self.frame.Size = UDim2.new(0.52, 0, 0.5, 0)
    TweenService:Create(
        self.frame,
        TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = UDim2.new(0.62, 0, 0.6, 0) }
    ):Play()
end

return DailyPanel
