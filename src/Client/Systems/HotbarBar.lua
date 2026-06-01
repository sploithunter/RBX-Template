--[[
    HotbarBar — lower-center power/command bar (Feature 16 UI, slice B).

    20 slots laid out as two rows of 10 (bottom row 1-0, top row Shift+1-0), plus a
    farming-mode cycle button on the left (Off -> Low -> High) that drives the
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

local Signals = require(ReplicatedStorage.Shared.Network.Signals)

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
    Low = Color3.fromRGB(90, 200, 120),
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
        local abbr = { focus_fire = "Focus", scatter = "Scatter", regroup = "Regroup", retreat = "Retreat" }
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
    root.Position = UDim2.new(0.5, 0, 1, -8)
    root.Size = UDim2.fromOffset(rowWidth + SLOT + PAD, SLOT * 2 + PAD)
    root.BackgroundTransparency = 1
    root.Parent = gui

    -- Farming cycle button (left of the bar).
    local farmBtn = Instance.new("TextButton")
    farmBtn.Name = "Farming"
    farmBtn.AnchorPoint = Vector2.new(0, 1)
    farmBtn.Position = UDim2.fromOffset(0, SLOT * 2 + PAD)
    farmBtn.Size = UDim2.fromOffset(SLOT, SLOT * 2 + PAD)
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
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 6)
            c.Parent = b

            local key = Instance.new("TextLabel")
            key.Name = "Key"
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

            b.MouseButton1Click:Connect(function()
                Signals.Hotbar_Activate:FireServer({ slot = slot })
            end)
            cards[slot] = { frame = b, bind = lbl }
        end
    end
    makeRow(SLOT, 10) -- TOP row (upper): slots 11-20 = Shift+1-0
    makeRow(SLOT * 2 + PAD, 0) -- BOTTOM row (primary, nearest hand): slots 1-10 = 1-0

    -- Render bindings pushed from the server.
    local function applyState(state)
        if type(state) ~= "table" or type(state.hotbar) ~= "table" then
            return
        end
        for slot = 1, 20 do
            local card = cards[slot]
            if card then
                local bind = state.hotbar[tostring(slot)] or state.hotbar[slot]
                card.bind.Text = bindLabel(bind)
                card.frame.BackgroundColor3 = bind and (TYPE_COLOR[bind.type] or Color3.fromRGB(26, 28, 38))
                    or Color3.fromRGB(26, 28, 38)
                card.frame.BackgroundTransparency = bind and 0.05 or 0.4
            end
        end
    end
    Signals.Hotbar_State.OnClientEvent:Connect(applyState)
    Signals.Hotbar_RequestState:FireServer()
    -- Re-request when pets/loadout likely changed.
    task.delay(2, function()
        Signals.Hotbar_RequestState:FireServer()
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

    -- Farming-mode cycle: Off -> Low -> High -> Off, driven by the auto-target toggles.
    -- Low = "free" targeting on, High = "paid" on; we flip whichever differs to reach
    -- the next state. The label tracks the server's authoritative status.
    local status = { free = false, paid = false }
    local function modeOf()
        if status.paid then
            return "High"
        elseif status.free then
            return "Low"
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
            wantFree, wantPaid = true, false -- -> Low
        elseif m == "Low" then
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
end

return HotbarBar
