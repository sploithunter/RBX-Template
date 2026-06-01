--[[
    SquadHud — City-of-Heroes-style right-side squad strip (Feature 10 HUD, slice 3).

    A persistent vertical strip of cards, one per equipped pet in PositionNumber order
    (stable, so players keep a preferred arrangement). Each card shows the pet's name,
    a state badge (Healthy/Strained/Critical/Recharging/Ready), a health bar, and a
    recharge countdown when it's out of the fight.

    Selection drives "assist" targeting (the CoH elegance): click a card OR the pet in
    the world to select that slot. Ally/support actions act on the selected pet; an
    enemy/debuff power would act on the enemy that pet is targeting (shown as the assist
    target). v1 wires Recall + Summon (Squad_Recall/Squad_Summon); Heal/Buff are stubbed
    until the player-power system is online.

    Reads slot state straight off the workspace pet attributes (no server UI feed):
    PetType / Variant / Power / CombatDamageTaken / CombatDowned / CooldownUntil /
    PositionNumber / TargetID. Pure visualisation + the two slot remotes.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local PetEndurance = require(ReplicatedStorage.Shared.Game.PetEndurance)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local SquadHud = {}

local localPlayer = Players.LocalPlayer

local STATE_COLOR = {
    Healthy = Color3.fromRGB(90, 210, 110),
    Strained = Color3.fromRGB(225, 200, 70),
    Critical = Color3.fromRGB(225, 90, 70),
    Recharging = Color3.fromRGB(120, 130, 150),
    Ready = Color3.fromRGB(95, 170, 235),
    Empty = Color3.fromRGB(70, 70, 80),
}

local function petsFolder()
    local pp = Workspace:FindFirstChild("PlayerPets")
    return pp and pp:FindFirstChild(localPlayer.Name)
end

local function petPower(pet)
    local nv = pet:FindFirstChild("Power")
    local p = (nv and tonumber(nv.Value)) or pet:GetAttribute("EffectivePower") or 1
    return (p and p >= 1) and p or 1
end

local function petSlot(pet)
    local pn = pet:FindFirstChild("PositionNumber")
    return pn and pn.Value or 0
end

-- Resolve the live state the HUD renders for one pet.
local function readSlot(pet, factor, thresholds)
    local power = petPower(pet)
    local damage = pet:GetAttribute("CombatDamageTaken") or 0
    local downed = pet:GetAttribute("CombatDowned") == true
    local cdRemaining = 0
    local state
    if downed then
        cdRemaining = math.max(0, (pet:GetAttribute("CooldownUntil") or 0) - os.time())
        state = cdRemaining > 0 and "Recharging" or "Ready"
    else
        state = PetEndurance.state(damage, power, factor, thresholds)
    end
    return {
        slot = petSlot(pet),
        name = tostring(pet:GetAttribute("PetType") or pet.Name),
        variant = tostring(pet:GetAttribute("Variant") or "basic"),
        healthFraction = PetEndurance.healthFraction(damage, power, factor),
        downed = downed,
        state = state,
        cdRemaining = cdRemaining,
    }
end

-- Timed buffs/debuffs to show as badges on a pet's card. Read off the pet (or the
-- player, for squad-wide buffs). Placeholder colour + short label now; set `icon`
-- to an asset id later to swap the label for the real art.
local PET_EFFECTS = {
    { key = "defense", source = "pet", untilAttr = "DefenseBuffUntil", color = Color3.fromRGB(235, 190, 70), label = "DEF" },
    { key = "damage", source = "player", untilAttr = "PetDamageBuffUntil", color = Color3.fromRGB(235, 90, 90), label = "DMG" },
    { key = "shield", source = "pet", poolAttr = "CombatShield", color = Color3.fromRGB(95, 170, 235), label = "SH" },
}

local function activeEffectsFor(pet, player, now)
    local out = {}
    for _, e in ipairs(PET_EFFECTS) do
        local src = (e.source == "player") and player or pet
        if e.untilAttr then
            local until_ = src:GetAttribute(e.untilAttr) or 0
            if until_ > now then
                out[#out + 1] =
                    { key = e.key, color = e.color, label = e.label, timer = math.ceil(until_ - now) .. "s", icon = e.icon }
            end
        elseif e.poolAttr then
            local v = src:GetAttribute(e.poolAttr) or 0
            if v > 0 then
                out[#out + 1] =
                    { key = e.key, color = e.color, label = e.label, timer = tostring(math.floor(v)), icon = e.icon }
            end
        end
    end
    return out
end

-- A small status badge (icon-ready: an empty ImageLabel sits over the placeholder).
local function makeBadge(parent)
    local f = Instance.new("Frame")
    f.Size = UDim2.fromOffset(24, 24)
    f.BorderSizePixel = 0
    f.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 5)
    c.Parent = f
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.BackgroundTransparency = 1
    icon.Size = UDim2.fromScale(1, 1)
    icon.Image = ""
    icon.ZIndex = 3
    icon.Parent = f
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0.6, 0)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 9
    label.TextColor3 = Color3.fromRGB(20, 22, 28)
    label.Parent = f
    local timer = Instance.new("TextLabel")
    timer.Name = "Timer"
    timer.BackgroundTransparency = 1
    timer.Position = UDim2.fromScale(0, 0.55)
    timer.Size = UDim2.new(1, 0, 0.45, 0)
    timer.Font = Enum.Font.GothamBold
    timer.TextSize = 9
    timer.TextColor3 = Color3.fromRGB(20, 22, 28)
    timer.Parent = f
    return { frame = f, icon = icon, label = label, timer = timer }
end

-- Reconcile a card's badges against the pet's active effects (stack toward centre).
local function updateBadges(card, effects)
    local seen = {}
    for i, eff in ipairs(effects) do
        seen[eff.key] = true
        local b = card.badges[eff.key]
        if not b then
            b = makeBadge(card.status)
            b.frame.Name = eff.key
            card.badges[eff.key] = b
        end
        b.frame.LayoutOrder = i
        b.frame.BackgroundColor3 = eff.color
        b.label.Text = (eff.icon and eff.icon ~= "") and "" or eff.label
        b.icon.Image = eff.icon or ""
        b.timer.Text = eff.timer or ""
    end
    for key, b in pairs(card.badges) do
        if not seen[key] then
            b.frame:Destroy()
            card.badges[key] = nil
        end
    end
end

function SquadHud.start()
    local config = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("combat"))
    local factor = config.pet_down_threshold_factor or 1
    local thresholds = config.degradation or { strained_at = 0.6, critical_at = 0.3 }

    local gui = Instance.new("ScreenGui")
    gui.Name = "SquadHud"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    gui.Parent = localPlayer:WaitForChild("PlayerGui")

    -- Right-edge container, vertically centred.
    local root = Instance.new("Frame")
    root.Name = "Strip"
    root.AnchorPoint = Vector2.new(1, 0.5)
    root.Position = UDim2.new(1, -8, 0.5, 0)
    root.Size = UDim2.fromOffset(186, 10)
    root.AutomaticSize = Enum.AutomaticSize.Y
    root.BackgroundTransparency = 1
    root.Parent = gui
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.Padding = UDim.new(0, 4)
    layout.Parent = root

    local selectedSlot = nil
    local cards = {} -- slot -> { frame, refs... }
    local worldHighlight = Instance.new("Highlight")
    worldHighlight.Name = "SquadSelectHighlight"
    worldHighlight.FillTransparency = 0.6
    worldHighlight.OutlineColor = Color3.fromRGB(95, 170, 235)
    worldHighlight.Enabled = false
    worldHighlight.Parent = gui

    local function setSelected(slot)
        selectedSlot = slot
        -- world highlight follows the selected pet
        worldHighlight.Adornee = nil
        worldHighlight.Enabled = false
        local folder = petsFolder()
        if folder then
            for _, pet in ipairs(folder:GetChildren()) do
                if pet:IsA("Model") and petSlot(pet) == slot then
                    worldHighlight.Adornee = pet
                    worldHighlight.Enabled = not pet:GetAttribute("CombatDowned")
                end
            end
        end
    end

    -- Build one card (returns refs for live updates).
    local function makeCard(slot)
        local frame = Instance.new("TextButton")
        frame.Name = "Slot_" .. slot
        frame.AutoButtonColor = false
        frame.Text = ""
        frame.Size = UDim2.fromOffset(186, 56)
        frame.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
        frame.BackgroundTransparency = 0.1
        frame.BorderSizePixel = 0
        frame.LayoutOrder = slot
        frame.Parent = root
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = frame
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(95, 170, 235)
        stroke.Thickness = 2
        stroke.Transparency = 1 -- shown when selected
        stroke.Parent = frame

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Name = "Name"
        nameLbl.BackgroundTransparency = 1
        nameLbl.Position = UDim2.fromOffset(8, 4)
        nameLbl.Size = UDim2.new(1, -16, 0, 18)
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 14
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextColor3 = Color3.fromRGB(235, 235, 245)
        nameLbl.Parent = frame

        local stateLbl = Instance.new("TextLabel")
        stateLbl.Name = "State"
        stateLbl.BackgroundTransparency = 1
        stateLbl.Position = UDim2.fromOffset(8, 4)
        stateLbl.Size = UDim2.new(1, -16, 0, 18)
        stateLbl.Font = Enum.Font.GothamMedium
        stateLbl.TextSize = 12
        stateLbl.TextXAlignment = Enum.TextXAlignment.Right
        stateLbl.Parent = frame

        local barBg = Instance.new("Frame")
        barBg.Name = "BarBg"
        barBg.Position = UDim2.fromOffset(8, 26)
        barBg.Size = UDim2.new(1, -16, 0, 10)
        barBg.BackgroundColor3 = Color3.fromRGB(15, 16, 22)
        barBg.BorderSizePixel = 0
        barBg.Parent = frame
        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 4)
        barCorner.Parent = barBg
        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.fromScale(1, 1)
        fill.BorderSizePixel = 0
        fill.Parent = barBg
        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 4)
        fillCorner.Parent = fill

        local cdLbl = Instance.new("TextLabel")
        cdLbl.Name = "Cooldown"
        cdLbl.BackgroundTransparency = 1
        cdLbl.Position = UDim2.fromOffset(8, 38)
        cdLbl.Size = UDim2.new(1, -16, 0, 16)
        cdLbl.Font = Enum.Font.Gotham
        cdLbl.TextSize = 11
        cdLbl.TextXAlignment = Enum.TextXAlignment.Left
        cdLbl.TextColor3 = Color3.fromRGB(180, 190, 205)
        cdLbl.Parent = frame

        -- Status-badge row: anchored at the card's left edge, growing toward screen
        -- centre (left) as more buffs/debuffs stack on this pet.
        local status = Instance.new("Frame")
        status.Name = "Status"
        status.AnchorPoint = Vector2.new(1, 0.5)
        status.Position = UDim2.new(0, -4, 0.5, 0)
        status.Size = UDim2.fromOffset(0, 24)
        status.AutomaticSize = Enum.AutomaticSize.X
        status.BackgroundTransparency = 1
        status.Parent = frame
        local sLayout = Instance.new("UIListLayout")
        sLayout.FillDirection = Enum.FillDirection.Horizontal
        sLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        sLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        sLayout.SortOrder = Enum.SortOrder.LayoutOrder
        sLayout.Padding = UDim.new(0, 3)
        sLayout.Parent = status

        frame.MouseButton1Click:Connect(function()
            setSelected(slot)
        end)

        return {
            frame = frame,
            stroke = stroke,
            name = nameLbl,
            state = stateLbl,
            fill = fill,
            cd = cdLbl,
            status = status,
            badges = {},
        }
    end

    -- Shared action row (acts on the selected slot).
    local actions = Instance.new("Frame")
    actions.Name = "Actions"
    actions.Size = UDim2.fromOffset(186, 30)
    actions.BackgroundTransparency = 1
    actions.LayoutOrder = 9999
    actions.Parent = root
    local aLayout = Instance.new("UIListLayout")
    aLayout.FillDirection = Enum.FillDirection.Horizontal
    aLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    aLayout.Padding = UDim.new(0, 4)
    aLayout.Parent = actions

    local function actionButton(label, color, enabled, onClick)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(44, 28)
        b.Text = label
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.TextColor3 = enabled and Color3.fromRGB(20, 22, 28) or Color3.fromRGB(150, 150, 160)
        b.BackgroundColor3 = enabled and color or Color3.fromRGB(55, 58, 70)
        b.AutoButtonColor = enabled
        b.BorderSizePixel = 0
        b.Active = enabled
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = b
        b.Parent = actions
        if enabled and onClick then
            b.MouseButton1Click:Connect(onClick)
        end
        return b
    end

    actionButton("Recall", Color3.fromRGB(225, 200, 70), true, function()
        if selectedSlot then
            Signals.Squad_Recall:FireServer({ slot = selectedSlot })
        end
    end)
    actionButton("Summon", Color3.fromRGB(95, 170, 235), true, function()
        if selectedSlot then
            Signals.Squad_Summon:FireServer({ slot = selectedSlot })
        end
    end)
    actionButton("Heal", Color3.fromRGB(90, 210, 110), false) -- via Powers (soon)
    actionButton("Buff", Color3.fromRGB(180, 130, 235), false) -- via Powers (soon)

    -- World click-to-select: clicking a visible pet selects its slot.
    local mouse = localPlayer:GetMouse()
    mouse.Button1Down:Connect(function()
        local target = mouse.Target
        if not target then
            return
        end
        local model = target:FindFirstAncestorWhichIsA("Model")
        local folder = petsFolder()
        if model and folder and model:IsDescendantOf(folder) then
            setSelected(petSlot(model))
        end
    end)

    -- Keyboard cycle (default Tab, config-assignable; hold Shift to go backward).
    local controls = require(ReplicatedStorage.Configs:WaitForChild("controls"))
    local cycleName = (controls.keybinds and controls.keybinds.squad_cycle) or "Tab"
    local okKey, cycleKey = pcall(function()
        return Enum.KeyCode[cycleName]
    end)
    if not okKey or not cycleKey then
        cycleKey = Enum.KeyCode.Tab
    end

    local function orderedSlots()
        local slots = {}
        local folder = petsFolder()
        if folder then
            for _, pet in ipairs(folder:GetChildren()) do
                if pet:IsA("Model") and pet.PrimaryPart then
                    slots[#slots + 1] = petSlot(pet)
                end
            end
        end
        table.sort(slots)
        return slots
    end

    local function cycle(dir)
        local slots = orderedSlots()
        if #slots == 0 then
            return
        end
        local idx
        for i, s in ipairs(slots) do
            if s == selectedSlot then
                idx = i
                break
            end
        end
        if not idx then
            idx = dir > 0 and 1 or #slots
        else
            idx = ((idx - 1 + dir) % #slots) + 1
        end
        setSelected(slots[idx])
    end

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return -- don't cycle while typing in a TextBox, etc.
        end
        if input.KeyCode == cycleKey then
            local reverse = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            cycle(reverse and -1 or 1)
        end
    end)

    -- Reconcile + refresh the strip.
    local accum = 0
    RunService.RenderStepped:Connect(function(dt)
        accum += dt
        if accum < 0.2 then
            return
        end
        accum = 0
        local folder = petsFolder()
        local present = {}
        if folder then
            for _, pet in ipairs(folder:GetChildren()) do
                if pet:IsA("Model") and pet.PrimaryPart then
                    local s = readSlot(pet, factor, thresholds)
                    present[s.slot] = true
                    local card = cards[s.slot]
                    if not card then
                        card = makeCard(s.slot)
                        cards[s.slot] = card
                    end
                    card.name.Text = s.name .. (s.variant ~= "basic" and (" (" .. s.variant .. ")") or "")
                    card.state.Text = s.state
                    card.state.TextColor3 = STATE_COLOR[s.state] or STATE_COLOR.Empty
                    card.fill.Size = UDim2.fromScale(math.clamp(s.healthFraction, 0, 1), 1)
                    card.fill.BackgroundColor3 = STATE_COLOR[s.downed and "Recharging" or s.state]
                        or STATE_COLOR.Healthy
                    if s.downed then
                        card.cd.Text = s.cdRemaining > 0 and ("Recharging  " .. s.cdRemaining .. "s")
                            or "READY — Summon"
                    else
                        card.cd.Text = ""
                    end
                    card.stroke.Transparency = (selectedSlot == s.slot) and 0 or 1
                    card.frame.BackgroundTransparency = (selectedSlot == s.slot) and 0 or 0.1
                    updateBadges(card, activeEffectsFor(pet, localPlayer, os.time()))
                end
            end
        end
        -- drop cards for unequipped slots
        for slot, card in pairs(cards) do
            if not present[slot] then
                card.frame:Destroy()
                cards[slot] = nil
            end
        end
        -- keep the world highlight tracking the selected pet's downed visibility
        if selectedSlot and worldHighlight.Adornee then
            worldHighlight.Enabled = not worldHighlight.Adornee:GetAttribute("CombatDowned")
        end
    end)
end

return SquadHud
