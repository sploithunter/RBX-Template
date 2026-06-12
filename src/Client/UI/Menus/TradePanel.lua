--[[
    TradePanel — client UI for the escrow two-player trade flow (Phase 10).

    Two layers:
      • List view (opened by the "Trade" side-menu button, via MenuManager): the
        online-player list; click a player to send a trade request.
      • Live layer (own ScreenGui, always present): the incoming-request popup and
        the two-player trade window, driven by the server's TradeUpdate RemoteEvent
        so they appear even when the menu is closed.

    All actions go through the GameAPICommand bus bridge (trade.players/request/
    respond/add/remove/confirm/cancel/myPets); the server pushes live state via
    TradeUpdate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CloseButton = require(script.Parent.Parent.Components.CloseButton)

local REMOTE_NAME = "GameAPICommand"
local UPDATE_REMOTE = "TradeUpdate"

local COLORS = {
    panel = Color3.fromRGB(20, 20, 25),
    header = Color3.fromRGB(56, 161, 178),
    headerGradient = Color3.fromRGB(43, 134, 148),
    row = Color3.fromRGB(40, 42, 52),
    rowStroke = Color3.fromRGB(70, 74, 88),
    you = Color3.fromRGB(46, 120, 170),
    them = Color3.fromRGB(120, 80, 160),
    accept = Color3.fromRGB(46, 204, 113),
    cancel = Color3.fromRGB(231, 76, 60),
    confirmed = Color3.fromRGB(46, 204, 113),
    pending = Color3.fromRGB(120, 124, 138),
    close = Color3.fromRGB(231, 76, 60),
    text = Color3.fromRGB(255, 255, 255),
    subtext = Color3.fromRGB(200, 205, 215),
}

local TradePanel = {}
TradePanel.__index = TradePanel

function TradePanel.new()
    local self = setmetatable({}, TradePanel)
    self.isVisible = false
    self.frame = nil
    self.liveGui = nil
    self.window = nil
    self.requestPopup = nil
    self.state = nil
    -- Listen for server pushes regardless of whether the menu is open.
    task.spawn(function()
        local remote = ReplicatedStorage:WaitForChild(UPDATE_REMOTE, 30)
        if remote then
            remote.OnClientEvent:Connect(function(payload)
                self:_onEvent(payload)
            end)
        end
    end)
    return self
end

function TradePanel:_callBus(name, args)
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

----------------------------------------------------------------------
-- Small UI helpers
----------------------------------------------------------------------

local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = inst
    return inst
end

local function label(parent, text, size, pos, color, font, scaled)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or COLORS.text
    l.Font = font or Enum.Font.Gotham
    l.TextScaled = scaled ~= false
    l.ZIndex = 103
    l.Parent = parent
    return l
end

local function petText(item)
    local v = (item.variant and item.variant ~= "basic") and (item.variant .. " ") or ""
    local huge = item.huge and "HUGE " or ""
    return huge .. v .. tostring(item.id)
end

----------------------------------------------------------------------
-- Menu-button list view (pick a player)
----------------------------------------------------------------------

function TradePanel:Show(parent)
    if self.isVisible then
        return
    end
    local frame = Instance.new("Frame")
    frame.Name = "TradePanel"
    frame.Size = UDim2.new(0.5, 0, 0.7, 0)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = COLORS.panel
    frame.BorderSizePixel = 0
    frame.ZIndex = 100
    frame.Parent = parent
    corner(frame, 20)
    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.header
    stroke.Thickness = 3
    stroke.Transparency = 0.3
    stroke.Parent = frame
    self.frame = frame

    self:_buildHeader(frame, "🤝 Trade", function()
        self:Hide()
    end)

    local hint = label(
        frame,
        "Pick a player to send a trade request:",
        UDim2.new(1, -48, 0, 24),
        UDim2.new(0, 24, 0, 84),
        COLORS.subtext,
        Enum.Font.Gotham
    )
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.ZIndex = 102

    local list = Instance.new("ScrollingFrame")
    list.Name = "PlayerList"
    list.Size = UDim2.new(1, -24, 1, -160)
    list.Position = UDim2.new(0, 12, 0, 116)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 6
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.ZIndex = 101
    list.Parent = frame
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = list
    self.playerList = list

    local refresh = Instance.new("TextButton")
    refresh.Size = UDim2.new(0, 160, 0, 40)
    refresh.Position = UDim2.new(0.5, 0, 1, -30)
    refresh.AnchorPoint = Vector2.new(0.5, 0.5)
    refresh.BackgroundColor3 = COLORS.header
    refresh.Text = "Refresh"
    refresh.TextColor3 = COLORS.text
    refresh.TextScaled = true
    refresh.Font = Enum.Font.GothamBold
    refresh.ZIndex = 102
    refresh.Parent = frame
    corner(refresh, 10)
    local rc = Instance.new("UITextSizeConstraint")
    rc.MaxTextSize = 18
    rc.Parent = refresh
    refresh.Activated:Connect(function()
        self:_refreshPlayers()
    end)

    self.isVisible = true
    self:_refreshPlayers()
end

function TradePanel:Hide()
    if not self.isVisible then
        return
    end
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    self.playerList = nil
    self.isVisible = false
end

function TradePanel:IsVisible()
    return self.isVisible
end

function TradePanel:GetFrame()
    return self.frame
end

function TradePanel:Destroy()
    self:Hide()
end

-- baseZ keeps the header above its parent frame on high-ZIndex surfaces (the pet
-- picker sits at ZIndex 300, so its header children must be > 300).
function TradePanel:_buildHeader(parent, titleText, onClose, baseZ)
    baseZ = baseZ or 101
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 72)
    header.BackgroundColor3 = COLORS.header
    header.BorderSizePixel = 0
    header.ZIndex = baseZ
    header.Parent = parent
    corner(header, 20)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS.header),
        ColorSequenceKeypoint.new(1, COLORS.headerGradient),
    })
    g.Rotation = 90
    g.Parent = header
    local title = label(
        header,
        titleText,
        UDim2.new(1, -150, 1, 0),
        UDim2.new(0, 24, 0, 0),
        COLORS.text,
        Enum.Font.GothamBold
    )
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = baseZ + 2
    local tc = Instance.new("UITextSizeConstraint")
    tc.MaxTextSize = 30
    tc.Parent = title
    -- THE standard close X (shared component; the old "✕" glyph tofu-boxed in Gotham)
    CloseButton.attach(header, {
        zindex = baseZ + 2,
        onClick = onClose,
    })
end

function TradePanel:_refreshPlayers()
    if not self.playerList then
        return
    end
    for _, ch in ipairs(self.playerList:GetChildren()) do
        if ch:IsA("Frame") then
            ch:Destroy()
        end
    end
    local result = self:_callBus("trade.players", {})
    local players = result and result.players or {}
    if #players == 0 then
        local empty = label(
            self.playerList,
            "No other players online to trade with.",
            UDim2.new(1, 0, 0, 50),
            UDim2.new(0, 0, 0, 0),
            COLORS.subtext,
            Enum.Font.Gotham
        )
        empty.ZIndex = 102
        local ec = Instance.new("UITextSizeConstraint")
        ec.MaxTextSize = 18
        ec.Parent = empty
        return
    end
    for i, p in ipairs(players) do
        self:_playerRow(p, i)
    end
end

function TradePanel:_playerRow(p, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 56)
    row.BackgroundColor3 = COLORS.row
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.ZIndex = 102
    row.Parent = self.playerList
    corner(row, 10)

    -- "Lv N  name" — the Level attribute is server-published and replicates to every
    -- client, so other players' levels read directly (Jason: "can we put the players
    -- level?")
    local other = Players:GetPlayerByUserId(p.userId)
    local lvl = other and other:GetAttribute("Level")
    local name = label(
        row,
        (lvl and ("Lv %d   "):format(lvl) or "") .. p.name,
        UDim2.new(1, -140, 1, 0),
        UDim2.new(0, 14, 0, 0),
        COLORS.text,
        Enum.Font.GothamBold
    )
    name.TextXAlignment = Enum.TextXAlignment.Left
    local nc = Instance.new("UITextSizeConstraint")
    nc.MaxTextSize = 18
    nc.Parent = name

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 110, 0, 40)
    btn.Position = UDim2.new(1, -122, 0.5, -20)
    btn.BackgroundColor3 = p.busy and COLORS.pending or COLORS.accept
    btn.Text = p.busy and "Busy" or "Request"
    btn.TextColor3 = COLORS.text
    btn.TextScaled = true
    btn.Font = Enum.Font.GothamBold
    btn.Active = not p.busy
    btn.AutoButtonColor = not p.busy
    btn.ZIndex = 103
    btn.Parent = row
    corner(btn, 8)
    local bc = Instance.new("UITextSizeConstraint")
    bc.MaxTextSize = 16
    bc.Parent = btn
    if not p.busy then
        btn.Activated:Connect(function()
            local res = self:_callBus("trade.request", { targetUserId = p.userId })
            btn.Text = (res and res.ok) and "Sent ✓" or "Failed"
            btn.Active = false
            btn.AutoButtonColor = false
        end)
    end
end

----------------------------------------------------------------------
-- Live layer: request popup + trade window (own ScreenGui)
----------------------------------------------------------------------

function TradePanel:_ensureLiveGui()
    if self.liveGui and self.liveGui.Parent then
        return self.liveGui
    end
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "TradeLive"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 50
    gui.Parent = pg
    self.liveGui = gui
    return gui
end

function TradePanel:_onEvent(payload)
    if type(payload) ~= "table" then
        return
    end
    if payload.type == "request" then
        self:_showRequestPopup(payload.fromUserId, payload.fromName)
    elseif payload.type == "opened" or payload.type == "updated" then
        self.state = payload.state
        self:_renderWindow(payload.state)
    elseif payload.type == "completed" then
        self:_toast("Trade complete!")
        self:_closeWindow()
    elseif payload.type == "cancelled" then
        self:_toast("Trade cancelled.")
        self:_closeWindow()
    elseif payload.type == "declined" then
        self:_toast("Trade request declined.")
    end
end

function TradePanel:_showRequestPopup(fromUserId, fromName)
    self:_closeRequestPopup()
    local gui = self:_ensureLiveGui()
    local pop = Instance.new("Frame")
    pop.Name = "RequestPopup"
    pop.Size = UDim2.new(0, 360, 0, 150)
    pop.Position = UDim2.new(0.5, 0, 0, 200)
    pop.AnchorPoint = Vector2.new(0.5, 0)
    pop.BackgroundColor3 = COLORS.panel
    pop.ZIndex = 200
    pop.Parent = gui
    corner(pop, 14)
    local s = Instance.new("UIStroke")
    s.Color = COLORS.header
    s.Thickness = 2
    s.Parent = pop
    self.requestPopup = pop

    local msg = label(
        pop,
        (fromName or "A player") .. " wants to trade",
        UDim2.new(1, -20, 0, 50),
        UDim2.new(0, 10, 0, 16),
        COLORS.text,
        Enum.Font.GothamBold
    )
    msg.ZIndex = 202 -- above the popup frame (200)
    msg.TextWrapped = true
    local mc = Instance.new("UITextSizeConstraint")
    mc.MaxTextSize = 20
    mc.Parent = msg

    local function actionButton(text, color, x, accept)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.42, 0, 0, 48)
        b.Position = UDim2.new(x, 0, 1, -60)
        b.BackgroundColor3 = color
        b.Text = text
        b.TextColor3 = COLORS.text
        b.TextScaled = true
        b.Font = Enum.Font.GothamBold
        b.ZIndex = 201
        b.Parent = pop
        corner(b, 10)
        local c = Instance.new("UITextSizeConstraint")
        c.MaxTextSize = 18
        c.Parent = b
        b.Activated:Connect(function()
            self:_callBus("trade.respond", { fromUserId = fromUserId, accept = accept })
            self:_closeRequestPopup()
        end)
    end
    actionButton("Accept", COLORS.accept, 0.05, true)
    actionButton("Decline", COLORS.cancel, 0.53, false)
end

function TradePanel:_closeRequestPopup()
    if self.requestPopup then
        self.requestPopup:Destroy()
        self.requestPopup = nil
    end
end

function TradePanel:_toast(text)
    local gui = self:_ensureLiveGui()
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(0, 320, 0, 44)
    t.Position = UDim2.new(0.5, 0, 0, 40)
    t.AnchorPoint = Vector2.new(0.5, 0)
    t.BackgroundColor3 = COLORS.header
    t.Text = text
    t.TextColor3 = COLORS.text
    t.TextScaled = true
    t.Font = Enum.Font.GothamBold
    t.ZIndex = 210
    t.Parent = gui
    corner(t, 10)
    local c = Instance.new("UITextSizeConstraint")
    c.MaxTextSize = 18
    c.Parent = t
    task.delay(2.5, function()
        if t and t.Parent then
            t:Destroy()
        end
    end)
end

function TradePanel:_closeWindow()
    if self.window then
        self.window:Destroy()
        self.window = nil
    end
    self:_hideCardTooltip()
    self.state = nil
end

-- Build (or rebuild) the two-player trade window from a state view.
-- THREE PANELS (Jason: "borrow from the inventory menu... full icon, hover info"):
-- left = YOUR tradeable pets (inventory-style cards, click to offer), middle = your
-- offer (click to pull back), right = their offer (read-only). Mirrored per client.
local PetCardStyle = require(script.Parent.Parent.PetCardStyle)
local VARIANT_COLORS = { -- tooltip stroke accents only; cards use PetCardStyle chrome
    basic = Color3.fromRGB(120, 125, 140),
    golden = Color3.fromRGB(255, 200, 60),
    rainbow = Color3.fromRGB(255, 90, 210),
}

function TradePanel:_renderWindow(state)
    self:_closeWindow()
    local gui = self:_ensureLiveGui()
    local win = Instance.new("Frame")
    win.Name = "TradeWindow"
    win.Size = UDim2.new(0, 960, 0, 540)
    win.Position = UDim2.new(0.5, 0, 0.5, 0)
    win.AnchorPoint = Vector2.new(0.5, 0.5)
    win.BackgroundColor3 = COLORS.panel
    win.ZIndex = 100
    win.Parent = gui
    corner(win, 18)
    local s = Instance.new("UIStroke")
    s.Color = COLORS.header
    s.Thickness = 3
    s.Parent = win
    -- pixel-designed window: shrink on small viewports (same fix as the HUD)
    pcall(function()
        require(script.Parent.Parent.UIViewportScale).attach(win, { min = 0.55 })
    end)
    self.window = win

    self:_buildHeader(win, "🤝 Trading with " .. (state.them.name or "Player"), function()
        self:_callBus("trade.cancel", {})
    end)

    -- what's already in my offer: specials by uid; stack COPIES counted by kind
    -- (each escrowed copy has its own offer-uid — the count is the display truth)
    local offered = {} -- [uid] = true (specials)
    local offeredCount = {} -- [id|variant|huge] = n (stack copies)
    local function kindKey(it)
        return tostring(it.id)
            .. "|"
            .. tostring(it.variant or "basic")
            .. "|"
            .. tostring(it.huge == true)
    end
    for _, item in ipairs(state.you.items or {}) do
        offered[item.uid] = true
        local k = kindKey(item)
        offeredCount[k] = (offeredCount[k] or 0) + 1
    end

    -- aggregate same-kind offer items into ONE card xN (click removes one copy)
    local function aggregate(items)
        local groups, order = {}, {}
        for _, item in ipairs(items or {}) do
            local k = kindKey(item)
            local g = groups[k]
            if not g then
                g = table.clone(item)
                g.count = 0
                g.uids = {}
                groups[k] = g
                order[#order + 1] = g
            end
            g.count += 1
            g.uids[#g.uids + 1] = item.uid
        end
        return order
    end

    local result = self:_callBus("trade.myPets", {})
    local myPets = (result and result.pets) or {}
    table.sort(myPets, function(a, b)
        return tostring(a.id) .. tostring(a.variant) < tostring(b.id) .. tostring(b.variant)
    end)

    local colW = 1 / 3
    self:_petColumn(win, "Your Pets", myPets, {
        pos = UDim2.new(0, 14, 0, 84),
        size = UDim2.new(colW, -20, 1, -156),
        tint = COLORS.row,
        offered = offered,
        offeredCount = offeredCount,
        kindKey = kindKey,
        onClick = function(pet)
            self:_callBus("trade.add", { uid = pet.uid })
        end,
    })
    self:_petColumn(
        win,
        ("Your Offer (%d)"):format(#(state.you.items or {})),
        aggregate(state.you.items),
        {
            pos = UDim2.new(colW, 8, 0, 84),
            size = UDim2.new(colW, -16, 1, -156),
            tint = COLORS.you,
            confirmed = state.you.confirmed,
            emptyText = "Click your pets to offer them",
            onClick = function(pet)
                -- aggregated card: pull ONE copy back (last escrowed uid in the group)
                local uid = pet.uids and pet.uids[#pet.uids] or pet.uid
                self:_callBus("trade.remove", { uid = uid })
            end,
        }
    )
    self:_petColumn(
        win,
        (state.them.name or "Them") .. ("'s Offer (%d)"):format(#(state.them.items or {})),
        aggregate(state.them.items),
        {
            pos = UDim2.new(2 * colW, 2, 0, 84),
            size = UDim2.new(colW, -16, 1, -156),
            tint = COLORS.them,
            confirmed = state.them.confirmed,
            emptyText = "Nothing offered yet",
        }
    )

    -- Confirm + Cancel.
    local confirm = Instance.new("TextButton")
    confirm.Size = UDim2.new(0, 200, 0, 48)
    confirm.Position = UDim2.new(0.5, -106, 1, -58)
    confirm.AnchorPoint = Vector2.new(0.5, 0)
    confirm.BackgroundColor3 = state.you.confirmed and COLORS.pending or COLORS.accept
    confirm.Text = state.you.confirmed and "Confirmed ✓ (waiting…)" or "Confirm"
    confirm.TextColor3 = COLORS.text
    confirm.TextScaled = true
    confirm.Font = Enum.Font.GothamBold
    confirm.Active = not state.you.confirmed
    confirm.ZIndex = 103
    confirm.Parent = win
    corner(confirm, 10)
    local cc = Instance.new("UITextSizeConstraint")
    cc.MaxTextSize = 16
    cc.Parent = confirm
    confirm.Activated:Connect(function()
        self:_callBus("trade.confirm", {})
    end)

    local cancel = Instance.new("TextButton")
    cancel.Size = UDim2.new(0, 110, 0, 48)
    cancel.Position = UDim2.new(0.5, 104, 1, -58)
    cancel.AnchorPoint = Vector2.new(0.5, 0)
    cancel.BackgroundColor3 = COLORS.cancel
    cancel.Text = "Cancel"
    cancel.TextColor3 = COLORS.text
    cancel.TextScaled = true
    cancel.Font = Enum.Font.GothamBold
    cancel.ZIndex = 103
    cancel.Parent = win
    corner(cancel, 10)
    local cancc = Instance.new("UITextSizeConstraint")
    cancc.MaxTextSize = 16
    cancc.Parent = cancel
    cancel.Activated:Connect(function()
        self:_callBus("trade.cancel", {})
    end)
end

-- One titled column holding a GRID of pet cards. opts: pos, size, tint, confirmed,
-- offered (uid set -> "in offer" badge), onClick(pet) (nil = read-only), emptyText.
function TradePanel:_petColumn(parent, titleText, items, opts)
    local col = Instance.new("Frame")
    col.Size = opts.size
    col.Position = opts.pos
    col.BackgroundColor3 = opts.tint or COLORS.row
    col.BackgroundTransparency = 0.72
    col.ZIndex = 101
    col.Parent = parent
    corner(col, 12)

    local head = label(
        col,
        titleText .. (opts.confirmed and "  ✓" or ""),
        UDim2.new(1, -12, 0, 24),
        UDim2.new(0, 8, 0, 6),
        opts.confirmed and COLORS.confirmed or COLORS.text,
        Enum.Font.GothamBold
    )
    head.TextXAlignment = Enum.TextXAlignment.Left
    local hc = Instance.new("UITextSizeConstraint")
    hc.MaxTextSize = 17
    hc.Parent = head

    local grid = Instance.new("ScrollingFrame")
    grid.Size = UDim2.new(1, -12, 1, -40)
    grid.Position = UDim2.new(0, 6, 0, 34)
    grid.BackgroundTransparency = 1
    grid.BorderSizePixel = 0
    grid.ScrollBarThickness = 4
    grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
    grid.CanvasSize = UDim2.new(0, 0, 0, 0)
    grid.ZIndex = 102
    grid.Parent = col
    local lay = Instance.new("UIGridLayout")
    lay.CellSize = UDim2.new(0, 88, 0, 96)
    lay.CellPadding = UDim2.new(0, 6, 0, 6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = grid

    if #(items or {}) == 0 and opts.emptyText then
        local empty = label(
            col,
            opts.emptyText,
            UDim2.new(1, -20, 0, 36),
            UDim2.new(0, 10, 0.45, 0),
            COLORS.subtext,
            Enum.Font.Gotham
        )
        empty.TextWrapped = true
        empty.ZIndex = 103
        local ec = Instance.new("UITextSizeConstraint")
        ec.MaxTextSize = 14
        ec.Parent = empty
    end

    for i, pet in ipairs(items or {}) do
        self:_petCard(grid, pet, i, opts)
    end
end

-- Inventory-style card: generated pet image (emoji fallback), name plate, variant
-- stroke, HUGE chip, lock overlay, hover tooltip + highlight.
function TradePanel:_petCard(parent, pet, order, opts)
    -- ESCROW ALREADY REMOVED offered copies from the inventory record, so the
    -- server's quantity IS the remaining count — subtracting offeredN again
    -- double-decremented (Jason: "when I offer one it decrements by two"). The
    -- offered chip is informational only; fully-escrowed stacks/specials simply
    -- vanish from this column (they're in the offer column).
    local quantity = tonumber(pet.quantity) or 1
    local remaining = quantity
    local offeredN = 0
    if opts.offeredCount and opts.kindKey then
        offeredN = opts.offeredCount[opts.kindKey(pet)] or 0
    end
    local inOffer = false
    local clickable = opts.onClick ~= nil and not pet.locked

    local card = Instance.new("TextButton")
    card.Text = ""
    card.LayoutOrder = order
    card.AutoButtonColor = clickable
    card.Active = clickable
    card.ZIndex = 103
    card.Parent = parent
    corner(card, 12)
    -- the REAL pet-card chrome (rarity ring + variant ring/background, animated per
    -- config) — same config the inventory cards render from (PetCardStyle)
    PetCardStyle.applyChrome(card, pet.rarity_id, pet.variant, pet.id)

    -- icon: pre-generated pet image viewport (same source the inventory uses)
    local icon
    pcall(function()
        local img = ReplicatedStorage:FindFirstChild("Assets")
        img = img and img:FindFirstChild("Images")
        img = img and img:FindFirstChild("Pets")
        img = img and img:FindFirstChild(tostring(pet.id))
        img = img and img:FindFirstChild(tostring(pet.variant or "basic"))
        if img then
            icon = img:Clone()
        end
    end)
    if icon then
        icon.Name = "PetImage"
        icon.Size = UDim2.new(1, -10, 1, -30)
        icon.Position = UDim2.new(0, 5, 0, 4)
        icon.BackgroundTransparency = 1
        icon.ZIndex = 104
        icon.Parent = card
    else
        local fallback = Instance.new("TextLabel")
        fallback.Size = UDim2.new(1, 0, 1, -26)
        fallback.BackgroundTransparency = 1
        fallback.Text = "🐾"
        fallback.TextScaled = true
        fallback.ZIndex = 104
        fallback.Parent = card
    end

    -- xN badge: offer cards show the aggregated count; inventory stacks show what
    -- REMAINS offerable (the number that answers "do I have more of these?")
    local badgeN = pet.count or (quantity > 1 and remaining) or nil
    if badgeN and badgeN > 1 then
        local qty = Instance.new("TextLabel")
        qty.Size = UDim2.new(0, 30, 0, 18)
        qty.Position = UDim2.new(1, -32, 0, 2)
        qty.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
        qty.BackgroundTransparency = 0.25
        qty.Text = "×" .. tostring(badgeN or remaining)
        qty.TextColor3 = COLORS.text
        qty.TextScaled = true
        qty.Font = Enum.Font.GothamBold
        qty.ZIndex = 106
        qty.Parent = card
        corner(qty, 6)
        local qc = Instance.new("UITextSizeConstraint")
        qc.MaxTextSize = 13
        qc.Parent = qty
    end
    -- some of this kind escrowed: gold chip so the split is visible at a glance
    if offeredN > 0 and not inOffer then
        local chip = Instance.new("TextLabel")
        chip.Size = UDim2.new(0, 64, 0, 16)
        chip.Position = UDim2.new(0, 3, 0, 2)
        chip.BackgroundColor3 = Color3.fromRGB(120, 95, 20)
        chip.BackgroundTransparency = 0.2
        chip.Text = offeredN .. " offered"
        chip.TextColor3 = Color3.fromRGB(255, 225, 140)
        chip.TextScaled = true
        chip.Font = Enum.Font.GothamBold
        chip.ZIndex = 106
        chip.Parent = card
        corner(chip, 6)
        local cc2 = Instance.new("UITextSizeConstraint")
        cc2.MaxTextSize = 11
        cc2.Parent = chip
    end

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -6, 0, 22)
    name.Position = UDim2.new(0, 3, 1, -24)
    name.BackgroundTransparency = 1
    name.Text = petText(pet) .. (pet.serial and (" #" .. tostring(pet.serial)) or "")
    name.TextColor3 = COLORS.text
    name.TextScaled = true
    name.Font = Enum.Font.GothamBold
    name.ZIndex = 105
    name.Parent = card
    local nc = Instance.new("UITextSizeConstraint")
    nc.MaxTextSize = 12
    nc.Parent = name

    if pet.locked or inOffer then
        local overlay = Instance.new("TextLabel")
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
        overlay.BackgroundTransparency = 0.45
        overlay.Text = pet.locked and "🔒" or "✓ offered"
        overlay.TextColor3 = COLORS.text
        overlay.TextScaled = true
        overlay.Font = Enum.Font.GothamBold
        overlay.ZIndex = 106
        overlay.Parent = card
        corner(overlay, 10)
        local oc = Instance.new("UITextSizeConstraint")
        oc.MaxTextSize = pet.locked and 26 or 14
        oc.Parent = overlay
    end

    -- hover: tooltip (name / variant / element / huge / lock reason) + lift
    card.MouseEnter:Connect(function()
        self:_showCardTooltip(card, pet)
        if clickable then
            card.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        end
    end)
    card.MouseLeave:Connect(function()
        self:_hideCardTooltip()
        card.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    end)

    if clickable then
        card.Activated:Connect(function()
            self:_hideCardTooltip()
            opts.onClick(pet)
        end)
    end
end

function TradePanel:_showCardTooltip(card, pet)
    self:_hideCardTooltip()
    local gui = self:_ensureLiveGui()
    local tip = Instance.new("Frame")
    tip.Name = "TradeCardTooltip"
    tip.Size = UDim2.new(0, 180, 0, 0)
    tip.AutomaticSize = Enum.AutomaticSize.Y
    tip.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    tip.BackgroundTransparency = 0.06
    tip.ZIndex = 400
    tip.Parent = gui
    corner(tip, 8)
    local st = Instance.new("UIStroke")
    st.Color = VARIANT_COLORS[pet.variant] or VARIANT_COLORS.basic
    st.Thickness = 2
    st.Parent = tip
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = tip
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 2)
    list.Parent = tip

    local lines = {
        petText(pet) .. (pet.serial and (" #" .. tostring(pet.serial)) or ""),
        "Variant: " .. tostring(pet.variant or "basic"),
    }
    local qty = tonumber(pet.quantity) or 1
    if qty > 1 then
        lines[#lines + 1] = "Owned: ×" .. qty
    end
    if pet.count and pet.count > 1 then
        lines[#lines + 1] = "In offer: ×" .. pet.count
    end
    if pet.level then
        lines[#lines + 1] = "Level: " .. tostring(pet.level)
    end
    if pet.element and pet.element ~= "neutral" then
        lines[#lines + 1] = "Element: " .. tostring(pet.element)
    end
    if pet.huge then
        lines[#lines + 1] = "HUGE"
    end
    if pet.locked then
        lines[#lines + 1] = "🔒 Locked — can't be traded"
    end
    for i, text in ipairs(lines) do
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 16)
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = i == 1 and COLORS.text or COLORS.subtext
        l.TextSize = i == 1 and 14 or 12
        l.Font = i == 1 and Enum.Font.GothamBold or Enum.Font.Gotham
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.LayoutOrder = i
        l.ZIndex = 401
        l.Parent = tip
    end

    -- pin beside the card (right side, flips left near the screen edge)
    local cam = workspace.CurrentCamera
    local vpX = cam and cam.ViewportSize.X or 1280
    local x = card.AbsolutePosition.X + card.AbsoluteSize.X + 8
    if x + 190 > vpX then
        x = card.AbsolutePosition.X - 188
    end
    tip.Position = UDim2.fromOffset(x, card.AbsolutePosition.Y)
    self.cardTooltip = tip
end

function TradePanel:_hideCardTooltip()
    if self.cardTooltip then
        self.cardTooltip:Destroy()
        self.cardTooltip = nil
    end
end

return TradePanel
