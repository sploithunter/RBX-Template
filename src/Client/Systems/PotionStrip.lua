--[[
    PotionStrip — the hotbar potion row (Potions S2b client).

    A small strip beside the power hotbar with one circular bottle-slot per owned potion:
      • a LIQUID FILL that rises with the brew-meter charge and drains in real time (on-theme for
        a potion — the bottle empties; tap to top it up). Interpolated between the server's 1s
        PotionUpdate pushes so the drain is smooth.
      • an axis-tinted ring + the potion icon.
      • a COUNT badge (how many you own) — ticks down as you drink, greys out at 0.
      • a seconds-left number while the buff is active.
    Tap = drink one (potion.drink bus command). Pure render of server state (SSOT): the server owns
    the charge + inventory; the strip just shows the pushed PotionUpdate state.

    NOTE: a literal pie/radial is a quick swap if preferred — the liquid fill was chosen because the
    item is a bottle. Enemy-debuff (throwable) potions are S2b+ and aren't shown here yet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BUS_REMOTE = "GameAPICommand"
local UPDATE_REMOTE = "PotionUpdate"
local SLOT = 52

local PotionStrip = {}

local function color3(c)
    if type(c) == "table" then
        return Color3.fromRGB(c[1] or 200, c[2] or 200, c[3] or 200)
    end
    return Color3.fromRGB(200, 200, 200)
end

local function callBus(name, args)
    local remote = ReplicatedStorage:FindFirstChild(BUS_REMOTE)
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

function PotionStrip.start()
    local player = Players.LocalPlayer
    if not player then
        return
    end
    local pg = player:WaitForChild("PlayerGui")

    local gui = Instance.new("ScreenGui")
    gui.Name = "PotionStrip"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = pg

    -- a row to the LEFT of the centered power hotbar (which sits at 0.5, bottom)
    local row = Instance.new("Frame")
    row.Name = "Row"
    row.AnchorPoint = Vector2.new(1, 1)
    row.Position = UDim2.new(0.5, -250, 1, -26)
    row.Size = UDim2.fromOffset(4 * (SLOT + 6), SLOT)
    row.BackgroundTransparency = 1
    row.Parent = gui
    local lay = Instance.new("UIListLayout")
    lay.FillDirection = Enum.FillDirection.Horizontal
    lay.HorizontalAlignment = Enum.HorizontalAlignment.Right
    lay.VerticalAlignment = Enum.VerticalAlignment.Bottom
    lay.Padding = UDim.new(0, 6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = row
    pcall(function()
        require(player.PlayerScripts.Client.UI.UIViewportScale).attach(row, { min = 0.6 })
    end)

    -- live state from PotionUpdate (+ a local clock so the fill interpolates between 1s pushes)
    local meters = {} -- meterId -> { charge, drain_seconds, color }
    local pushClock = os.clock()
    local slotByPotion = {} -- potionId -> { frame, fill, count, secs, meter }

    local function liveCharge(meterId)
        local m = meters[meterId]
        if not m then
            return 0
        end
        local c = (m.charge or 0) - (os.clock() - pushClock) / math.max(1, m.drain_seconds or 1)
        return math.clamp(c, 0, 1)
    end

    local function buildSlot(potion, order)
        local btn = Instance.new("TextButton")
        btn.Name = "Potion_" .. potion.id
        btn.Size = UDim2.fromOffset(SLOT, SLOT)
        btn.LayoutOrder = order
        btn.Text = ""
        btn.BackgroundColor3 = Color3.fromRGB(22, 24, 31)
        btn.AutoButtonColor = true
        btn.ClipsDescendants = true
        btn.Parent = row
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(1, 0)
        c.Parent = btn
        local axis = color3(meters[potion.meter] and meters[potion.meter].color)
        local ring = Instance.new("UIStroke")
        ring.Color = axis
        ring.Thickness = 2.5
        ring.Parent = btn

        -- the liquid: a bottom-anchored frame whose height scales with the charge
        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.AnchorPoint = Vector2.new(0.5, 1)
        fill.Position = UDim2.fromScale(0.5, 1)
        fill.Size = UDim2.new(1, 0, 0, 0)
        fill.BackgroundColor3 = axis
        fill.BackgroundTransparency = 0.35
        fill.BorderSizePixel = 0
        fill.ZIndex = 2
        fill.Parent = btn

        local icon = Instance.new("TextLabel")
        icon.Size = UDim2.fromScale(1, 1)
        icon.BackgroundTransparency = 1
        icon.Text = tostring(potion.icon or "🧪")
        icon.TextScaled = true
        icon.ZIndex = 3
        icon.Parent = btn
        local ip = Instance.new("UIPadding")
        ip.PaddingTop = UDim.new(0, 8)
        ip.PaddingBottom = UDim.new(0, 8)
        ip.PaddingLeft = UDim.new(0, 8)
        ip.PaddingRight = UDim.new(0, 8)
        ip.Parent = icon

        local count = Instance.new("TextLabel")
        count.Size = UDim2.fromOffset(22, 16)
        count.Position = UDim2.new(1, -23, 0, 2)
        count.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
        count.BackgroundTransparency = 0.2
        count.Text = "×" .. tostring(potion.count or 0)
        count.TextColor3 = Color3.fromRGB(255, 255, 255)
        count.TextScaled = true
        count.Font = Enum.Font.GothamBold
        count.ZIndex = 4
        count.Parent = btn
        local cc = Instance.new("UICorner")
        cc.CornerRadius = UDim.new(0, 5)
        cc.Parent = count

        local secs = Instance.new("TextLabel")
        secs.Size = UDim2.new(1, 0, 0, 14)
        secs.Position = UDim2.new(0, 0, 1, -15)
        secs.BackgroundTransparency = 1
        secs.Text = ""
        secs.TextColor3 = Color3.fromRGB(255, 255, 255)
        secs.TextStrokeTransparency = 0.3
        secs.TextScaled = true
        secs.Font = Enum.Font.GothamBold
        secs.ZIndex = 4
        secs.Parent = btn
        local sc = Instance.new("UITextSizeConstraint")
        sc.MaxTextSize = 12
        sc.Parent = secs

        btn.Activated:Connect(function()
            callBus("potion.drink", { potionId = potion.id })
        end)

        return {
            frame = btn,
            fill = fill,
            count = count,
            secs = secs,
            meter = potion.meter,
            ring = ring,
        }
    end

    local function render(state)
        -- clear
        for _, s in pairs(slotByPotion) do
            s.frame:Destroy()
        end
        slotByPotion = {}
        meters = (state and state.meters) or {}
        pushClock = os.clock()
        local potions = (state and state.potions) or {}
        for i, p in ipairs(potions) do
            slotByPotion[p.id] = buildSlot(p, i)
            slotByPotion[p.id].count.Text = "×" .. tostring(p.count or 0)
        end
    end

    -- initial pull + live pushes
    task.spawn(function()
        local st = callBus("potion.state", {})
        if st then
            render(st)
        end
    end)
    local remote = ReplicatedStorage:WaitForChild(UPDATE_REMOTE, 30)
    if remote then
        remote.OnClientEvent:Connect(function(state)
            render(state)
        end)
    end

    -- interpolate the fill + seconds each frame
    RunService.RenderStepped:Connect(function()
        for _, s in pairs(slotByPotion) do
            local m = meters[s.meter]
            local charge = liveCharge(s.meter)
            s.fill.Size = UDim2.new(1, 0, charge, 0)
            if charge > 0 and m then
                local remaining = charge * (m.drain_seconds or 0)
                s.secs.Text = remaining >= 1 and tostring(math.ceil(remaining)) or ""
            else
                s.secs.Text = ""
            end
        end
    end)
end

return PotionStrip
