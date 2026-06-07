--[[
    HotbarBar — lower-center power/command bar (Feature 16 UI, slice B).

    20 slots laid out as two rows of 10 (bottom row 1-0, top row Shift+1-0), plus a
    farming-mode cycle button on the left (Off -> Near -> High) that drives the
    auto-target toggles. Slots are fed by the server (Hotbar_State); pressing a slot's
    key OR clicking it fires Hotbar_Activate(slot), which the server resolves to the
    bound power / tactical / pet-summon.

    Keys: bottom row = 1..9,0 ; top row = Shift+1..9,0. (No Ctrl — the browser eats
    Ctrl+1-9.) The default Roblox Backpack is disabled so the number keys are free.
    The buttons are the cross-platform source of truth; keys are a desktop shortcut.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)
local POWER_ICONS = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("power_icons"))
local PILL = require(ReplicatedStorage.Configs:WaitForChild("pill_ui"))
local PetBadge = require(script.Parent.Parent.UI.PetBadge)

local HotbarBar = {}

local localPlayer = Players.LocalPlayer

-- KeyCode -> base digit slot (1..10). Shift adds 10 (slots 11..20).
local DIGIT_SLOT = {
    [Enum.KeyCode.One] = 1,
    [Enum.KeyCode.Two] = 2,
    [Enum.KeyCode.Three] = 3,
    [Enum.KeyCode.Four] = 4,
    [Enum.KeyCode.Five] = 5,
    [Enum.KeyCode.Six] = 6,
    [Enum.KeyCode.Seven] = 7,
    [Enum.KeyCode.Eight] = 8,
    [Enum.KeyCode.Nine] = 9,
    [Enum.KeyCode.Zero] = 10,
}

local TYPE_COLOR = {
    power = Color3.fromRGB(150, 110, 235),
    tactical = Color3.fromRGB(230, 170, 60),
    roster = Color3.fromRGB(70, 170, 230),
    pet = Color3.fromRGB(90, 200, 120),
}
local FARM_COLOR = {
    Off = Color3.fromRGB(70, 72, 84),
    Near = Color3.fromRGB(90, 200, 120),
    High = Color3.fromRGB(230, 120, 70),
}

local function keyLabel(slot)
    local digit = slot
    if slot > 10 then
        digit = slot - 10
    end
    local d = (digit == 10) and "0" or tostring(digit)
    return slot > 10 and ("⇧" .. d) or d
end

-- Short label for a bind so the slot reads at a glance.
local function bindLabel(bind)
    if not bind then
        return ""
    end
    local t = tostring(bind.target or "")
    if bind.type == "tactical" then
        local abbr =
            { focus_fire = "Focus", scatter = "Scatter", regroup = "Regroup", retreat = "Retreat" }
        return abbr[t] or t
    end
    -- power/roster/pet: trim to something readable
    t = t:gsub("_", " ")
    if #t > 9 then
        t = t:sub(1, 8) .. "…"
    end
    return t
end

function HotbarBar.start()
    -- Free the number keys: this game uses a custom inventory, not the Roblox Backpack.
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name = "HotbarBar"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = localPlayer:WaitForChild("PlayerGui")

    local SLOT = 46
    local PAD = 4
    local rowWidth = 10 * SLOT + 9 * PAD

    local root = Instance.new("Frame")
    root.Name = "Bar"
    root.AnchorPoint = Vector2.new(0.5, 1)
    root.Position = UDim2.new(0.5, 0, 1, -20)
    root.Size = UDim2.fromOffset(rowWidth + SLOT + PAD, SLOT * 2 + PAD)
    root.BackgroundTransparency = 1
    root.Parent = gui

    -- Blue neon pill_frame wrapping the whole bar (9-slice so the wide bar keeps proper corners;
    -- transparent inside AND outside, so the game shows through and the slots sit on top).
    local barFrame = Instance.new("ImageLabel")
    barFrame.Name = "PillFrame"
    barFrame.BackgroundTransparency = 1
    barFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    barFrame.Position = UDim2.fromScale(0.5, 0.5)
    barFrame.Size = UDim2.new(1, 46, 1, 30)
    barFrame.Image = PILL.frames.sapphire
    barFrame.ScaleType = Enum.ScaleType.Slice
    barFrame.SliceCenter = Rect.new(180, 180, 330, 330)
    barFrame.ZIndex = 0
    barFrame.Parent = root

    -- Farming cycle button (left of the bar).
    local farmBtn = Instance.new("TextButton")
    farmBtn.Name = "Farming"
    farmBtn.AnchorPoint = Vector2.new(0, 1)
    farmBtn.Position = UDim2.fromOffset(3, SLOT * 2 + PAD - 7) -- nudged up so its ring clears the frame's bottom border
    farmBtn.Size = UDim2.fromOffset(SLOT - 6, SLOT - 6) -- square (bottom-left), pairs with the Edit square above
    farmBtn.AutoButtonColor = false
    farmBtn.Font = Enum.Font.GothamBold
    farmBtn.TextSize = 12
    farmBtn.TextColor3 = Color3.fromRGB(240, 240, 245)
    farmBtn.Text = "Farm\nOff"
    farmBtn.BackgroundColor3 = FARM_COLOR.Off
    farmBtn.BorderSizePixel = 0
    farmBtn.Parent = root
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = farmBtn
    end

    -- Assignment (edit) state: the palette pushed by the server + a forward-declared
    -- picker opener so a slot click can open it while in edit mode.
    local available = { powers = {}, tacticals = {} }
    local editMode = false
    local openPicker

    -- Cooldown overlay on a (circular) slot, reusing the golden/rainbow-pet shimmer:
    -- while recharging the icon dims, a rainbow UIGradient ring spins around it (same
    -- look as the inventory variant ring), and a seconds countdown shows the exact time
    -- left. Returns set(elapsed, secondsLeft); elapsed >= 1 (ready) hides it.
    local RAINBOW = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 90, 90)),
        ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 205, 70)),
        ColorSequenceKeypoint.new(0.4, Color3.fromRGB(95, 230, 120)),
        ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 185, 255)),
        ColorSequenceKeypoint.new(0.8, Color3.fromRGB(185, 120, 255)),
        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 90, 90)),
    })
    local function attachRadial(slotBtn)
        local holder = Instance.new("Frame")
        holder.Name = "Cool"
        holder.Size = UDim2.fromScale(1, 1)
        holder.BackgroundTransparency = 1
        holder.Visible = false
        holder.ZIndex = 4
        holder.Parent = slotBtn

        local dim = Instance.new("Frame") -- darkens the icon while recharging
        dim.Size = UDim2.fromScale(1, 1)
        dim.BackgroundColor3 = Color3.fromRGB(6, 7, 11)
        dim.BackgroundTransparency = 0.45
        dim.BorderSizePixel = 0
        dim.ZIndex = 4
        dim.Parent = holder
        local dc = Instance.new("UICorner")
        dc.CornerRadius = UDim.new(1, 0)
        dc.Parent = dim

        local ring = Instance.new("UIStroke") -- the spinning rainbow shimmer
        ring.Thickness = 3
        ring.Parent = dim
        local grad = Instance.new("UIGradient")
        grad.Color = RAINBOW
        grad.Parent = ring

        local num = Instance.new("TextLabel")
        num.BackgroundTransparency = 1
        num.Size = UDim2.fromScale(1, 1)
        num.Font = Enum.Font.GothamBold
        num.TextSize = 16
        num.TextColor3 = Color3.fromRGB(255, 255, 255)
        num.TextStrokeTransparency = 0.3
        num.ZIndex = 5
        num.Text = ""
        num.Parent = holder

        return function(elapsed, secondsLeft)
            if not elapsed or elapsed >= 1 then
                holder.Visible = false
                return
            end
            holder.Visible = true
            num.Text = secondsLeft and tostring(math.ceil(secondsLeft)) or ""
            grad.Rotation = (os.clock() * 160) % 360 -- continuous shimmer spin
        end
    end

    -- Two rows of 10 slots. Bottom row = slots 1-10, top row = 11-20.
    local cards = {}
    local function makeRow(yOffset, base)
        for i = 1, 10 do
            local slot = base + i
            local b = Instance.new("TextButton")
            b.Name = "Slot_" .. slot
            b.AnchorPoint = Vector2.new(0, 1)
            b.Position = UDim2.fromOffset(SLOT + PAD + (i - 1) * (SLOT + PAD), yOffset)
            b.Size = UDim2.fromOffset(SLOT, SLOT)
            b.AutoButtonColor = false
            b.Text = ""
            b.BackgroundColor3 = Color3.fromRGB(26, 28, 38)
            b.BackgroundTransparency = 0.15
            b.BorderSizePixel = 0
            b.Parent = root
            b.ClipsDescendants = true
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(1, 0) -- circular slot
            c.Parent = b

            local iconImg = Instance.new("ImageLabel")
            iconImg.Name = "Icon"
            iconImg.BackgroundTransparency = 1
            iconImg.Position = UDim2.fromScale(0.5, 0.5)
            iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
            iconImg.ScaleType = Enum.ScaleType.Fit
            iconImg.Size = UDim2.fromScale(1, 1) -- zoom set per-icon in applyState (border crop)
            iconImg.Image = ""
            iconImg.ZIndex = 2
            iconImg.Parent = b

            -- Directional targeting ring framing the disc (powers only; hidden otherwise).
            local ringImg = Instance.new("ImageLabel")
            ringImg.Name = "Ring"
            ringImg.BackgroundTransparency = 1
            ringImg.Position = UDim2.fromScale(0.5, 0.5)
            ringImg.AnchorPoint = Vector2.new(0.5, 0.5)
            ringImg.ScaleType = Enum.ScaleType.Fit
            ringImg.Size = UDim2.fromScale(1, 1)
            ringImg.Image = ""
            ringImg.Visible = false
            ringImg.ZIndex = 3
            ringImg.Parent = b

            local key = Instance.new("TextLabel")
            key.Name = "Key"
            key.ZIndex = 3
            key.BackgroundTransparency = 1
            key.Position = UDim2.fromOffset(3, 1)
            key.Size = UDim2.fromOffset(SLOT - 6, 13)
            key.Font = Enum.Font.GothamBold
            key.TextSize = 11
            key.TextXAlignment = Enum.TextXAlignment.Left
            key.TextColor3 = Color3.fromRGB(150, 155, 170)
            key.Text = keyLabel(slot)
            key.Parent = b

            local lbl = Instance.new("TextLabel")
            lbl.Name = "Bind"
            lbl.BackgroundTransparency = 1
            lbl.Position = UDim2.fromOffset(2, 14)
            lbl.Size = UDim2.fromOffset(SLOT - 4, SLOT - 16)
            lbl.Font = Enum.Font.GothamMedium
            lbl.TextSize = 10
            lbl.TextWrapped = true
            lbl.TextColor3 = Color3.fromRGB(235, 235, 245)
            lbl.Text = ""
            lbl.Parent = b

            local cool = attachRadial(b)

            b.MouseButton1Click:Connect(function()
                if editMode then
                    openPicker(slot)
                else
                    Signals.Hotbar_Activate:FireServer({ slot = slot })
                end
            end)
            cards[slot] = {
                frame = b,
                bind = lbl,
                cool = cool,
                bindObj = nil,
                icon = iconImg,
                ring = ringImg,
            }
        end
    end
    makeRow(SLOT, 10) -- TOP row (upper): slots 11-20 = Shift+1-0
    makeRow(SLOT * 2 + PAD, 0) -- BOTTOM row (primary, nearest hand): slots 1-10 = 1-0

    -- Render bindings pushed from the server.
    local stateApplied = false -- true once a non-empty hotbar has landed (stops join-retry)
    local function applyState(state)
        if type(state) ~= "table" or type(state.hotbar) ~= "table" then
            return
        end
        if next(state.hotbar) ~= nil then
            stateApplied = true
        end
        if type(state.available) == "table" then
            available = state.available
        end
        for slot = 1, 20 do
            local card = cards[slot]
            if card then
                local bind = state.hotbar[tostring(slot)] or state.hotbar[slot]
                card.bindObj = bind
                -- Power slots render the universal badge: element disc + tinted directional ring
                -- (the ring's SHAPE = targeting). Falls back to the old flat icon, then to text.
                local badge = bind and bind.type == "power" and PetBadge.forPower(bind.target)
                    or nil
                local discImg = badge and POWER_ICONS.discFor(badge.element, badge.symbol) or nil
                local hasArt = false
                if discImg then
                    card.icon.Image = discImg
                    card.icon.Size = UDim2.fromScale(0.82, 0.82) -- inset so the ring frames it
                    card.ring.Image = POWER_ICONS.rings[badge.ring] or POWER_ICONS.rings.aura
                    card.ring.ImageColor3 = POWER_ICONS.elementColor3(badge.element, "dark")
                    card.ring.Visible = true
                    card.bind.Visible = false
                    hasArt = true
                else
                    -- Fallback: old flat power icon (no ring), else the text label.
                    local icon = bind and bind.type == "power" and POWER_ICONS.powers[bind.target]
                        or nil
                    card.icon.Image = icon or ""
                    if icon then
                        local s = POWER_ICONS.scaleFor(icon) -- zoom past the art's transparent border
                        card.icon.Size = UDim2.fromScale(s, s)
                    end
                    card.ring.Visible = false
                    card.bind.Visible = not icon
                    hasArt = icon ~= nil
                end
                card.bind.Text = bindLabel(bind)
                card.frame.BackgroundColor3 = bind
                        and (TYPE_COLOR[bind.type] or Color3.fromRGB(26, 28, 38))
                    or Color3.fromRGB(26, 28, 38)
                -- With real art present, let it stand on a clear slot; keep the coloured
                -- placeholder for text-only / empty slots so they're still legible.
                card.frame.BackgroundTransparency = hasArt and 1 or (bind and 0.05 or 0.4)
            end
        end
    end
    Signals.Hotbar_State.OnClientEvent:Connect(applyState)
    Signals.Hotbar_RequestState:FireServer()

    -- Power cooldowns -> the per-slot radial edge-clock. Stamp the local clock when the
    -- push arrives so the sweep is smooth (server untilTime is only 1s-granular).
    local powerCooldowns = {} -- powerId -> { startClock, cooldown }
    Signals.Power_Cooldown.OnClientEvent:Connect(function(p)
        if type(p) == "table" and p.power and (p.cooldown or 0) > 0 then
            powerCooldowns[p.power] = { startClock = os.clock(), cooldown = p.cooldown }
        end
    end)
    RunService.Heartbeat:Connect(function()
        local nowC = os.clock()
        for slot = 1, 20 do
            local card = cards[slot]
            if card and card.cool then
                local b = card.bindObj
                local cd = b and b.type == "power" and powerCooldowns[b.target]
                if cd then
                    local since = nowC - cd.startClock
                    card.cool(since / cd.cooldown, cd.cooldown - since)
                else
                    card.cool(1) -- ready / not a power -> hide the clock
                end
            end
        end
    end)
    -- Join race: the first request can beat the server's profile/hotbar load, leaving
    -- the bar blank. Keep re-requesting (backing off) until a non-empty state lands.
    task.spawn(function()
        for _ = 1, 10 do
            if stateApplied then
                break
            end
            task.wait(1)
            Signals.Hotbar_RequestState:FireServer()
        end
    end)

    -- Number-key activation: digit -> slot (bottom row), Shift+digit -> +10 (top row).
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        local base = DIGIT_SLOT[input.KeyCode]
        if base then
            local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            local slot = shift and (base + 10) or base
            Signals.Hotbar_Activate:FireServer({ slot = slot })
        end
    end)

    -- Farming-mode cycle: Off -> Near -> High -> Off, driven by the auto-target toggles.
    -- Near = "free" targeting on (auto_systems free_mode = nearest), High = "paid" on
    -- (highest_value); we flip whichever differs to reach the next state. The label tracks
    -- the server's authoritative status.
    local status = { free = false, paid = false }
    local function modeOf()
        if status.paid then
            return "High"
        elseif status.free then
            return "Near"
        end
        return "Off"
    end
    local function paintFarm()
        local m = modeOf()
        farmBtn.Text = "Farm\n" .. m
        farmBtn.BackgroundColor3 = FARM_COLOR[m]
    end
    Signals.AutoTarget_Status.OnClientEvent:Connect(function(s)
        status.free = s.free and true or false
        status.paid = s.paid and true or false
        paintFarm()
    end)
    paintFarm()

    farmBtn.MouseButton1Click:Connect(function()
        -- next desired state
        local m = modeOf()
        local wantFree, wantPaid
        if m == "Off" then
            wantFree, wantPaid = true, false -- -> Near
        elseif m == "Near" then
            wantFree, wantPaid = false, true -- -> High
        else
            wantFree, wantPaid = false, false -- -> Off
        end
        if status.free ~= wantFree then
            Signals.AutoTarget_ToggleFree:FireServer()
        end
        if status.paid ~= wantPaid then
            Signals.AutoTarget_TogglePaid:FireServer()
        end
    end)

    -- ===== Assignment: Edit toggle + per-slot picker =====
    local editBtn = Instance.new("TextButton")
    editBtn.Name = "Edit"
    editBtn.AnchorPoint = Vector2.new(0, 1)
    editBtn.Position = UDim2.fromOffset(3, SLOT) -- square, top-left, directly above the Farm square
    editBtn.Size = UDim2.fromOffset(SLOT - 6, SLOT - 6)
    editBtn.TextSize = 12
    editBtn.AutoButtonColor = false
    editBtn.Font = Enum.Font.GothamBold
    editBtn.TextSize = 11
    editBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
    editBtn.Text = "Edit"
    editBtn.BackgroundColor3 = Color3.fromRGB(60, 63, 76)
    editBtn.BorderSizePixel = 0
    editBtn.Parent = root
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = editBtn
    end

    -- Blue pill_frame ring around the Edit + Farm squares, so they read as power-bar buttons like the
    -- ringed slots (transparent center -> the button + label show through).
    local function ringButton(btn)
        local r = Instance.new("ImageLabel")
        r.Name = "Ring"
        r.BackgroundTransparency = 1
        r.AnchorPoint = Vector2.new(0.5, 0.5)
        r.Position = UDim2.fromScale(0.5, 0.5)
        r.Size = UDim2.fromScale(1.12, 1.12)
        r.Image = PILL.frames.sapphire
        r.ScaleType = Enum.ScaleType.Fit
        r.ZIndex = 9
        r.Parent = btn
    end
    ringButton(editBtn)
    ringButton(farmBtn)

    local pickerFrame
    local function closePicker()
        if pickerFrame then
            pickerFrame:Destroy()
            pickerFrame = nil
        end
    end

    -- Build the assignment picker for a slot: powers (server palette), pet summons
    -- (the player's equipped squad), tacticals, and Clear. Selecting one rebinds.
    openPicker = function(slot)
        closePicker()
        local p = Instance.new("Frame")
        p.Name = "Picker"
        p.AnchorPoint = Vector2.new(0.5, 1)
        p.Position = UDim2.new(0.5, 0, 1, -(SLOT * 2 + PAD + 18))
        p.Size = UDim2.fromOffset(320, 280)
        p.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
        p.BorderSizePixel = 0
        p.Parent = gui
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = p
        pickerFrame = p

        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Size = UDim2.new(1, -28, 0, 24)
        title.Position = UDim2.fromOffset(10, 4)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 13
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextColor3 = Color3.fromRGB(255, 215, 120)
        title.Text = "Assign slot " .. slot
        title.Parent = p

        local close = Instance.new("TextButton")
        close.Size = UDim2.fromOffset(22, 22)
        close.Position = UDim2.new(1, -26, 0, 5)
        close.Text = "✕"
        close.Font = Enum.Font.GothamBold
        close.TextSize = 14
        close.TextColor3 = Color3.fromRGB(230, 230, 235)
        close.BackgroundColor3 = Color3.fromRGB(50, 52, 64)
        close.BorderSizePixel = 0
        close.Parent = p
        close.MouseButton1Click:Connect(closePicker)

        local listFrame = Instance.new("ScrollingFrame")
        listFrame.Position = UDim2.fromOffset(6, 30)
        listFrame.Size = UDim2.new(1, -12, 1, -36)
        listFrame.BackgroundTransparency = 1
        listFrame.BorderSizePixel = 0
        listFrame.ScrollBarThickness = 6
        listFrame.CanvasSize = UDim2.new()
        listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        listFrame.Parent = p
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 3)
        layout.Parent = listFrame

        local order = 0
        local function header(text)
            order += 1
            local h = Instance.new("TextLabel")
            h.Size = UDim2.new(1, 0, 0, 16)
            h.BackgroundTransparency = 1
            h.Font = Enum.Font.GothamBold
            h.TextSize = 11
            h.TextXAlignment = Enum.TextXAlignment.Left
            h.TextColor3 = Color3.fromRGB(150, 155, 170)
            h.Text = text
            h.LayoutOrder = order
            h.Parent = listFrame
        end
        local function entry(label, color, bind)
            order += 1
            local e = Instance.new("TextButton")
            e.Size = UDim2.new(1, 0, 0, 24)
            e.AutoButtonColor = true
            e.Font = Enum.Font.GothamMedium
            e.TextSize = 12
            e.TextXAlignment = Enum.TextXAlignment.Left
            e.Text = "  " .. label
            e.TextColor3 = Color3.fromRGB(235, 235, 245)
            e.BackgroundColor3 = color
            e.BorderSizePixel = 0
            e.LayoutOrder = order
            e.Parent = listFrame
            local ec = Instance.new("UICorner")
            ec.CornerRadius = UDim.new(0, 4)
            ec.Parent = e
            e.MouseButton1Click:Connect(function()
                Signals.Hotbar_Rebind:FireServer({ slot = slot, bind = bind })
                closePicker()
            end)
        end

        header("Powers")
        for _, id in ipairs(available.powers or {}) do
            entry((tostring(id):gsub("_", " ")), TYPE_COLOR.power, { type = "power", target = id })
        end
        header("Summon pet")
        local pf = Workspace:FindFirstChild("PlayerPets")
            and Workspace.PlayerPets:FindFirstChild(localPlayer.Name)
        if pf then
            for _, pet in ipairs(pf:GetChildren()) do
                local pn = pet:FindFirstChild("PositionNumber")
                if pet:IsA("Model") and pn then
                    local nm = tostring(pet:GetAttribute("PetType") or pet.Name)
                    entry(
                        "Summon " .. nm .. " (#" .. pn.Value .. ")",
                        TYPE_COLOR.pet,
                        { type = "pet", target = tostring(pn.Value) }
                    )
                end
            end
        end
        header("Tactical")
        for _, cmd in ipairs(available.tacticals or {}) do
            entry(
                (tostring(cmd):gsub("_", " ")),
                TYPE_COLOR.tactical,
                { type = "tactical", target = cmd }
            )
        end
        header("")
        entry("✖ Clear slot", Color3.fromRGB(70, 50, 50), nil)
    end

    local function paintEdit()
        editBtn.Text = editMode and "Done" or "Edit"
        editBtn.BackgroundColor3 = editMode and Color3.fromRGB(235, 170, 60)
            or Color3.fromRGB(60, 63, 76)
    end
    editBtn.MouseButton1Click:Connect(function()
        editMode = not editMode
        if not editMode then
            closePicker()
        end
        paintEdit()
    end)
end

return HotbarBar
