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

function TradePanel:_buildHeader(parent, titleText, onClose)
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 72)
    header.BackgroundColor3 = COLORS.header
    header.BorderSizePixel = 0
    header.ZIndex = 101
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
    local tc = Instance.new("UITextSizeConstraint")
    tc.MaxTextSize = 30
    tc.Parent = title
    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 48, 0, 48)
    close.Position = UDim2.new(1, -60, 0, 12)
    close.BackgroundColor3 = COLORS.close
    close.Text = "✕"
    close.TextColor3 = COLORS.text
    close.TextScaled = true
    close.Font = Enum.Font.GothamBold
    close.ZIndex = 102
    close.Parent = header
    corner(close, 24)
    close.Activated:Connect(onClose)
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

    local name = label(
        row,
        p.name,
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
        UDim2.new(1, -20, 0, 40),
        UDim2.new(0, 10, 0, 12),
        COLORS.text,
        Enum.Font.GothamBold
    )
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
    self:_closePetPicker()
    self.state = nil
end

-- Build (or rebuild) the two-player trade window from a state view.
function TradePanel:_renderWindow(state)
    self:_closeWindow()
    local gui = self:_ensureLiveGui()
    local win = Instance.new("Frame")
    win.Name = "TradeWindow"
    win.Size = UDim2.new(0, 640, 0, 420)
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
    self.window = win

    self:_buildHeader(win, "🤝 Trading with " .. (state.them.name or "Player"), function()
        self:_callBus("trade.cancel", {})
    end)

    -- Two offer columns.
    self:_offerColumn(win, "You", state.you, true, UDim2.new(0, 16, 0, 84))
    self:_offerColumn(win, state.them.name or "Them", state.them, false, UDim2.new(0.5, 8, 0, 84))

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

function TradePanel:_offerColumn(parent, titleText, side, mine, pos)
    local col = Instance.new("Frame")
    col.Size = UDim2.new(0.5, -24, 1, -156)
    col.Position = pos
    col.BackgroundColor3 = mine and COLORS.you or COLORS.them
    col.BackgroundTransparency = 0.7
    col.ZIndex = 101
    col.Parent = parent
    corner(col, 12)

    local head = label(
        col,
        titleText .. (side.confirmed and "  ✓" or ""),
        UDim2.new(1, -12, 0, 24),
        UDim2.new(0, 8, 0, 6),
        side.confirmed and COLORS.confirmed or COLORS.text,
        Enum.Font.GothamBold
    )
    head.TextXAlignment = Enum.TextXAlignment.Left
    local hc = Instance.new("UITextSizeConstraint")
    hc.MaxTextSize = 18
    hc.Parent = head

    local items = Instance.new("ScrollingFrame")
    items.Size = UDim2.new(1, -12, 1, mine and -78 or -40)
    items.Position = UDim2.new(0, 6, 0, 34)
    items.BackgroundTransparency = 1
    items.BorderSizePixel = 0
    items.ScrollBarThickness = 4
    items.AutomaticCanvasSize = Enum.AutomaticSize.Y
    items.CanvasSize = UDim2.new(0, 0, 0, 0)
    items.ZIndex = 102
    items.Parent = col
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 4)
    lay.Parent = items

    for i, item in ipairs(side.items or {}) do
        local r = Instance.new("TextButton")
        r.Size = UDim2.new(1, -6, 0, 30)
        r.BackgroundColor3 = COLORS.row
        r.Text = petText(item) .. (mine and "   ✕" or "")
        r.TextColor3 = COLORS.text
        r.TextScaled = true
        r.Font = Enum.Font.Gotham
        r.TextXAlignment = Enum.TextXAlignment.Left
        r.LayoutOrder = i
        r.AutoButtonColor = mine
        r.Active = mine
        r.ZIndex = 103
        r.Parent = items
        corner(r, 6)
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 8)
        pad.Parent = r
        local rcst = Instance.new("UITextSizeConstraint")
        rcst.MaxTextSize = 14
        rcst.Parent = r
        if mine then
            r.Activated:Connect(function()
                self:_callBus("trade.remove", { uid = item.uid })
            end)
        end
    end

    if mine then
        local add = Instance.new("TextButton")
        add.Size = UDim2.new(1, -12, 0, 34)
        add.Position = UDim2.new(0, 6, 1, -38)
        add.BackgroundColor3 = COLORS.accept
        add.Text = "+ Add Pet"
        add.TextColor3 = COLORS.text
        add.TextScaled = true
        add.Font = Enum.Font.GothamBold
        add.ZIndex = 103
        add.Parent = col
        corner(add, 8)
        local ac = Instance.new("UITextSizeConstraint")
        ac.MaxTextSize = 15
        ac.Parent = add
        add.Activated:Connect(function()
            self:_openPetPicker()
        end)
    end
end

----------------------------------------------------------------------
-- Pet picker (offer one of your pets)
----------------------------------------------------------------------

function TradePanel:_openPetPicker()
    self:_closePetPicker()
    local gui = self:_ensureLiveGui()
    local picker = Instance.new("Frame")
    picker.Name = "PetPicker"
    picker.Size = UDim2.new(0, 320, 0, 380)
    picker.Position = UDim2.new(0.5, 0, 0.5, 0)
    picker.AnchorPoint = Vector2.new(0.5, 0.5)
    picker.BackgroundColor3 = COLORS.panel
    picker.ZIndex = 300
    picker.Parent = gui
    corner(picker, 14)
    local s = Instance.new("UIStroke")
    s.Color = COLORS.header
    s.Thickness = 2
    s.Parent = picker
    self.petPicker = picker

    self:_buildHeader(picker, "Choose a pet", function()
        self:_closePetPicker()
    end)

    local list = Instance.new("ScrollingFrame")
    list.Size = UDim2.new(1, -16, 1, -84)
    list.Position = UDim2.new(0, 8, 0, 78)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 5
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.ZIndex = 301
    list.Parent = picker
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 5)
    lay.Parent = list

    local result = self:_callBus("trade.myPets", {})
    local pets = result and result.pets or {}
    if #pets == 0 then
        local empty = label(
            list,
            "No tradeable pets.",
            UDim2.new(1, 0, 0, 40),
            UDim2.new(0, 0, 0, 0),
            COLORS.subtext,
            Enum.Font.Gotham
        )
        empty.ZIndex = 302
        return
    end
    for i, pet in ipairs(pets) do
        local r = Instance.new("TextButton")
        r.Size = UDim2.new(1, -6, 0, 34)
        r.BackgroundColor3 = pet.locked and COLORS.pending or COLORS.row
        r.Text = petText(pet) .. (pet.locked and "  🔒" or "")
        r.TextColor3 = COLORS.text
        r.TextScaled = true
        r.Font = Enum.Font.Gotham
        r.TextXAlignment = Enum.TextXAlignment.Left
        r.LayoutOrder = i
        r.Active = not pet.locked
        r.AutoButtonColor = not pet.locked
        r.ZIndex = 302
        r.Parent = list
        corner(r, 6)
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 8)
        pad.Parent = r
        local rcst = Instance.new("UITextSizeConstraint")
        rcst.MaxTextSize = 14
        rcst.Parent = r
        if not pet.locked then
            r.Activated:Connect(function()
                self:_callBus("trade.add", { uid = pet.uid })
                self:_closePetPicker()
            end)
        end
    end
end

function TradePanel:_closePetPicker()
    if self.petPicker then
        self.petPicker:Destroy()
        self.petPicker = nil
    end
end

return TradePanel
