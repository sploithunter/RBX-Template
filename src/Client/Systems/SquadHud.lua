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
local POWER_ICONS = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("power_icons"))
local PET_ROLES = require(ReplicatedStorage.Configs:WaitForChild("pet_roles"))
local PetBadge = require(script.Parent.Parent.UI.PetBadge)

local SquadHud = {}

local localPlayer = Players.LocalPlayer

-- Resolve a pet's archetype/role chip: PetRole attribute -> by_type[PetType] -> default.
-- Returns { glyph, icon, color (Color3) }, cached per role id.
local ROLE_CACHE = {}
local function roleFor(pet)
    local id = pet:GetAttribute("PetRole")
        or (PET_ROLES.by_type and PET_ROLES.by_type[pet:GetAttribute("PetType")])
        or PET_ROLES.default
    local cached = ROLE_CACHE[id]
    if cached then
        return cached
    end
    local def = (PET_ROLES.roles and PET_ROLES.roles[id]) or {}
    local c = def.color or { 90, 95, 110 }
    cached = {
        glyph = def.glyph or "?",
        icon = def.icon or "",
        color = Color3.fromRGB(c[1] or 90, c[2] or 95, c[3] or 110),
    }
    ROLE_CACHE[id] = cached
    return cached
end

local STATE_COLOR = {
    Healthy = Color3.fromRGB(90, 210, 110),
    Strained = Color3.fromRGB(225, 200, 70),
    Critical = Color3.fromRGB(225, 90, 70),
    Recharging = Color3.fromRGB(120, 130, 150),
    Ready = Color3.fromRGB(95, 170, 235),
    Empty = Color3.fromRGB(70, 70, 80),
}
local SLOT_BAR_COLOR = Color3.fromRGB(235, 150, 70) -- the SLOT timer (thin bar) when a pet is downed
local SHIELD_BAR_COLOR = Color3.fromRGB(95, 170, 235) -- the shield-pool thin bar when alive

-- "Ns" under a minute, "M:SS" above (a 5-min pet lockout shouldn't read "284s").
local function formatTime(sec)
    sec = math.max(0, math.ceil(sec))
    if sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
    end
    return sec .. "s"
end

-- Continuous health-bar colour: green (full) -> yellow (half) -> red (empty), so the
-- fill itself reads the pet's condition (no separate state label needed).
local HP_GREEN = Color3.fromRGB(70, 205, 95)
local HP_YELLOW = Color3.fromRGB(235, 200, 60)
local HP_RED = Color3.fromRGB(220, 70, 70)

-- How far the role badge pokes off the card's inner (left) edge: the badge's anchor-X fraction.
-- 0 = flush inside, 0.5 = half overhangs. Bigger = more "hanging off" the gems-pill style.
local BADGE_OVERHANG = 0.35
local function healthColor(f)
    f = math.clamp(f, 0, 1)
    if f >= 0.5 then
        return HP_YELLOW:Lerp(HP_GREEN, (f - 0.5) * 2)
    end
    return HP_RED:Lerp(HP_YELLOW, f * 2)
end

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

-- The model a pet is currently attacking/mining: its TargetID resolves to an enemy (or crystal) by
-- matching that id to the target's BreakableID child — the same id space the server assigns. Scans
-- only the relevant folder (Enemies vs Breakables) via TargetType. nil when the pet has no target.
local function resolveTargetModel(pet)
    local tid = pet:FindFirstChild("TargetID")
    if not tid or tid.Value == 0 then
        return nil
    end
    local id = tid.Value
    local game = Workspace:FindFirstChild("Game")
    if not game then
        return nil
    end
    local tt = pet:FindFirstChild("TargetType")
    local isEnemy = tt and tostring(tt.Value) == "Enemy"
    if isEnemy then
        local enemies = game:FindFirstChild("Enemies")
        if enemies then
            for _, m in ipairs(enemies:GetChildren()) do
                local bid = m:FindFirstChild("BreakableID")
                if bid and bid.Value == id then
                    return m
                end
            end
        end
    else
        local breakables = game:FindFirstChild("Breakables")
        if breakables then
            for _, m in ipairs(breakables:GetDescendants()) do
                if m:IsA("Model") then
                    local bid = m:FindFirstChild("BreakableID")
                    if bid and bid.Value == id then
                        return m
                    end
                end
            end
        end
    end
    return nil
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
    local maxEnd = PetEndurance.maxEndurance(power, factor)
    local shield = pet:GetAttribute("CombatShield") or 0
    return {
        slot = petSlot(pet),
        name = tostring(pet:GetAttribute("PetType") or pet.Name),
        variant = tostring(pet:GetAttribute("Variant") or "basic"),
        healthFraction = PetEndurance.healthFraction(damage, power, factor),
        -- Shield (absorption pool) as a fraction of the pet's endurance ceiling, for the
        -- thin secondary bar. Capped at 1 so a big shield just fills it.
        shieldFraction = maxEnd > 0 and math.clamp(shield / maxEnd, 0, 1) or 0,
        downed = downed,
        state = state,
        cdRemaining = cdRemaining,
        -- #179 down-lockout: the SLOT's own (shorter) timer + whether this pet is a unique special
        -- (so the recovery bar scales to the 5-min pet lockout, not the 1-min slot).
        slotRemaining = math.max(0, (pet:GetAttribute("SlotLockUntil") or 0) - os.time()),
        special = pet:GetAttribute("LockoutSpecial") == true,
    }
end

-- Timed buffs/debuffs to show as badges on a pet's card. Read off the pet (or the
-- player, for squad-wide buffs). Placeholder colour + short label now; set `icon`
-- to an asset id later to swap the label for the real art.
-- `powerIdAttr`: the attribute PowerService stamps with the power that applied this buff. When
-- present, the badge resolves THAT power's disc (PetBadge) so it matches the hotbar + world icon;
-- `icon` is only the fallback when no power tagged it.
local PET_EFFECTS = {
    {
        key = "defense",
        source = "pet",
        untilAttr = "DefenseBuffUntil",
        powerIdAttr = "DefenseBuffPowerId",
        color = Color3.fromRGB(235, 190, 70),
        label = "DEF",
        icon = POWER_ICONS.status.defense,
    },
    {
        key = "damage",
        source = "player",
        untilAttr = "PetDamageBuffUntil",
        powerIdAttr = "PetDamageBuffPowerId",
        color = Color3.fromRGB(235, 90, 90),
        label = "DMG",
        icon = POWER_ICONS.status.damage,
    },
    -- Instant effects flash a blinking pulse badge (no countdown) for their FX window so
    -- you can see what just happened. heal = the support/heal-power tell (HealFxUntil).
    {
        key = "heal",
        source = "pet",
        untilAttr = "HealFxUntil",
        color = Color3.fromRGB(90, 210, 110),
        label = "HEAL",
        icon = POWER_ICONS.discFor("earth", "plus"), -- green heal cross (bunny support)
        pulse = true,
    },
    -- Support-pet AURAS a pet currently HAS (every affected pet, not just the buffer). Fixed
    -- element-disc per kind so the badge reads the providing biome: defense=ice, offense=lava,
    -- yield=desert. The buffer pet itself wears its badge too (it's one of the allies).
    -- `steady = true`: this buff is CONTINUOUSLY REFRESHED while the buffer pet is deployed (it's
    -- effectively permanent), so the badge sits solid — no countdown, no near-expiry blink. (Timed
    -- powers below keep their countdown + blink-when-about-to-expire.)
    {
        key = "teamdef",
        source = "pet",
        untilAttr = "TeamDefenseBuffUntil",
        stacksAttr = "TeamDefenseBuffStacks", -- # of penguin buffers -> badge pile + xN
        steady = true,
        color = Color3.fromRGB(120, 180, 255),
        label = "DEF",
        icon = POWER_ICONS.discFor("ice", "armor_chest"),
    },
    {
        key = "offense",
        source = "pet",
        untilAttr = "OffenseFxUntil",
        stacksAttr = "OffenseFxUntilStacks", -- # of lava buffers -> badge pile + xN
        steady = true,
        color = Color3.fromRGB(235, 120, 90),
        label = "ATK",
        icon = POWER_ICONS.discFor("fire", "chevrons_up"),
    },
    {
        key = "yield",
        source = "pet",
        untilAttr = "YieldFxUntil",
        stacksAttr = "YieldFxUntilStacks", -- # of desert buffers -> badge pile + xN
        steady = true,
        color = Color3.fromRGB(235, 205, 90),
        label = "COIN",
        icon = POWER_ICONS.discFor("desert", "coins_up"),
    },
    -- Armor/absorb shield: now time-limited (CombatShieldUntil), so it shows as a countdown badge
    -- on the card (the thin blue bar still shows the remaining pool magnitude).
    {
        key = "shield",
        source = "pet",
        untilAttr = "CombatShieldUntil",
        powerIdAttr = "CombatShieldPowerId",
        color = Color3.fromRGB(235, 200, 70),
        label = "ARM",
        icon = POWER_ICONS.status.shield,
    },
}

local function activeEffectsFor(pet, player, now)
    local out = {}
    for idx, e in ipairs(PET_EFFECTS) do
        local src = (e.source == "player") and player or pet
        -- Resolve the FULL badge (element disc + tinted ring) from the POWER that applied this buff
        -- so it matches the hotbar / role badge / world shield; fall back to the static icon (no
        -- ring) when nothing tagged it.
        local icon = e.icon
        local ringImg, ringColor
        if e.powerIdAttr then
            local badge = PetBadge.forPower(src:GetAttribute(e.powerIdAttr))
            local disc = badge and POWER_ICONS.discFor(badge.element, badge.symbol)
            if disc then
                icon = disc
                ringImg = POWER_ICONS.rings[badge.ring] or POWER_ICONS.rings.aura
                ringColor = POWER_ICONS.elementColor3(badge.element, "dark")
            end
        end
        if e.untilAttr then
            local until_ = src:GetAttribute(e.untilAttr) or 0
            if until_ > now then
                out[#out + 1] = {
                    key = e.key,
                    color = e.color,
                    label = e.label,
                    -- Pulse/steady effects show no countdown; timed buffs do.
                    timer = (e.pulse or e.steady) and "" or (math.ceil(until_ - now) .. "s"),
                    icon = icon,
                    ringImg = ringImg,
                    ringColor = ringColor,
                    steady = e.steady, -- steady buffs never blink (continuously refreshed = permanent)
                    remaining = until_ - now, -- seconds left (drives the expiry blink)
                    order = idx, -- stable PET_EFFECTS position (steady badges sort by this, not time)
                    -- # of same-kind sources stacked into this buff (e.g. 3 lava pets -> ATK x3) so the
                    -- card can pile the badge + show "xN" (same buff stacks; different ones stay separate).
                    stacks = e.stacksAttr and (src:GetAttribute(e.stacksAttr) or 1) or nil,
                }
            end
        elseif e.poolAttr then
            local v = src:GetAttribute(e.poolAttr) or 0
            if v > 0 then
                out[#out + 1] = {
                    key = e.key,
                    color = e.color,
                    label = e.label,
                    timer = tostring(math.floor(v)),
                    icon = icon,
                    ringImg = ringImg,
                    ringColor = ringColor,
                    order = idx,
                }
            end
        end
    end
    return out
end

-- A small status badge — one per buff INSTANCE (duplicates included). Positioned manually by
-- updateBadges so same-kind instances overlap by half (a coin-stack); each blinks on its own timer.
local BADGE_PX = 30
local function makeBadge(parent)
    local f = Instance.new("Frame")
    f.Size = UDim2.fromOffset(BADGE_PX, BADGE_PX)
    f.BorderSizePixel = 0
    f.ClipsDescendants = true -- crop the icon's zoomed-out transparent border
    f.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = f
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.BackgroundTransparency = 1
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.fromScale(0.5, 0.5)
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Size = UDim2.fromScale(1, 1) -- zoom set per-icon in updateBadges
    icon.Image = ""
    icon.Parent = f
    -- Tinted element ring framing the disc (power-applied buffs only; hidden otherwise).
    local ring = Instance.new("ImageLabel")
    ring.Name = "Ring"
    ring.BackgroundTransparency = 1
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.fromScale(0.5, 0.5)
    ring.Size = UDim2.fromScale(1, 1)
    ring.ScaleType = Enum.ScaleType.Fit
    ring.Image = ""
    ring.Visible = false
    ring.Parent = f
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
    return { frame = f, icon = icon, ring = ring, label = label, timer = timer }
end

-- Under the GUI's Sibling ZIndexBehavior, a badge frame's ZIndex governs the whole badge vs its
-- sibling badges (descendants keep their own intra-badge order). A more-urgent (later) instance
-- gets a higher ZIndex so it draws OVER the coin it overlaps — its blink stays visible on top.

-- Reconcile a card's badges against the pet's active effects. Ordered so the SHORTEST
-- remaining sits leftmost (toward screen centre, most urgent): the row grows left under
-- HorizontalAlignment.Right, so a higher LayoutOrder = further left. The blink loop owns
-- live transparency (badges are never hidden/destroyed mid-blink, so the row never shifts).
local BADGE_GAP = 3
local function updateBadges(card, effects, blinkLead)
    -- ONE badge per buff INSTANCE (duplicates included): N lava buffers -> N ATK badges; the renderer
    -- is per-instance so distinct-expiry sources blink independently — only the coin within blinkLead
    -- of dropping flashes, not the whole stack.
    local instances = {}
    for _, eff in ipairs(effects) do
        local n = math.max(1, math.floor(eff.stacks or 1))
        for k = 1, n do
            instances[#instances + 1] = { eff = eff, k = k }
        end
    end
    -- Order: TIMED by shortest-remaining toward the centre EDGE (most urgent leftmost); STEADY auras
    -- hold a fixed slot by PET_EFFECTS index (no refresh jitter). Same-kind instances end up adjacent.
    table.sort(instances, function(a, b)
        local ae, be = a.eff, b.eff
        local aSteady, bSteady = ae.steady or false, be.steady or false
        if aSteady ~= bSteady then
            return bSteady -- timed first -> leftmost edge
        end
        if aSteady then
            if (ae.order or 0) ~= (be.order or 0) then
                return (ae.order or 0) < (be.order or 0)
            end
            return a.k < b.k
        end
        if (ae.remaining or math.huge) ~= (be.remaining or math.huge) then
            return (ae.remaining or math.huge) > (be.remaining or math.huge) -- shortest -> leftmost
        end
        return a.k < b.k
    end)

    local seen = {}
    -- Position manually: adjacent DUPLICATES (same kind) overlap by HALF a badge (a coin-stack);
    -- different kinds get the normal gap. Lay out right(least urgent)->left(most urgent); the row is
    -- anchored at the card's left edge and grows toward screen centre.
    local OVERLAP = math.floor(BADGE_PX / 2)
    local rightX = 0
    for i, inst in ipairs(instances) do
        local eff = inst.eff
        local id = eff.key .. "#" .. inst.k
        seen[id] = true
        local b = card.badges[id]
        if not b then
            b = makeBadge(card.status)
            b.frame.Name = id
            card.badges[id] = b
        end
        -- per-INSTANCE blink: only THIS coin flashes when IT is within blinkLead of expiry.
        b.blinking = not eff.steady and eff.remaining ~= nil and eff.remaining <= (blinkLead or 0)
        local hasIcon = eff.icon and eff.icon ~= ""
        b.frame.BackgroundColor3 = eff.color
        b.bgBase = hasIcon and 1 or 0 -- icon badges: transparent backing (no square chip behind the disc)
        b.label.Text = hasIcon and "" or eff.label
        b.icon.Image = eff.icon or ""
        if eff.ringImg then
            b.ring.Image = eff.ringImg
            b.ring.ImageColor3 = eff.ringColor or Color3.fromRGB(70, 76, 96)
            b.ring.Visible = true
            b.icon.Size = UDim2.fromScale(0.72, 0.72)
        else
            b.ring.Visible = false
            if hasIcon then
                local s = POWER_ICONS.scaleFor(eff.icon) -- zoom past the art's transparent border
                b.icon.Size = UDim2.fromScale(s, s)
            end
        end
        -- Only the FRONT (most-urgent) coin of a same-kind stack prints the countdown, so the pile
        -- doesn't stamp the same number on every coin underneath.
        local nextInst = instances[i + 1]
        local frontOfStack = not (nextInst and nextInst.eff.key == eff.key)
        b.timer.Text = (frontOfStack and eff.timer) or ""
        -- advance the right-edge offset: overlap-by-half when this instance duplicates the previous.
        local prev = instances[i - 1]
        if prev then
            rightX = rightX + ((prev.eff.key == eff.key) and OVERLAP or (BADGE_PX + BADGE_GAP))
        end
        b.frame.AnchorPoint = Vector2.new(1, 0.5)
        b.frame.Position = UDim2.new(1, -rightX, 0.5, 0)
        b.frame.ZIndex = 2 + i -- later = more urgent (leftmost) = on top, so its blink shows
    end
    card.status.Size = UDim2.fromOffset(rightX + BADGE_PX, BADGE_PX)
    for key, b in pairs(card.badges) do
        if not seen[key] then
            b.frame:Destroy()
            card.badges[key] = nil
        end
    end
end

function SquadHud.start()
    local config = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("combat"))
    local squadCfg = require(ReplicatedStorage.Configs:WaitForChild("squad"))
    local lockoutDur = {
        -- the EXACT special pet's recovery (5 min); a stack pet rides the slot timer
        petSpecial = (squadCfg.down_lockout and squadCfg.down_lockout.pet_lockout_seconds) or 300,
        slot = (squadCfg.slot_recovery and squadCfg.slot_recovery.down_cooldown_seconds) or 60,
    }
    local factor = config.pet_down_threshold_factor or 1
    local thresholds = config.degradation or { strained_at = 0.6, critical_at = 0.3 }
    local badgeCfg = config.status_badges or {}
    local blinkLead = badgeCfg.blink_lead_seconds or 5
    local blinkPeriod = badgeCfg.blink_period_seconds or 0.5

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
    local assistTargetBid = nil -- the enemy BreakableID the squad is directed to focus (Z / click)
    local cards = {} -- slot -> { frame, refs... }
    local worldHighlight = Instance.new("Highlight")
    worldHighlight.Name = "SquadSelectHighlight"
    worldHighlight.FillTransparency = 0.6
    worldHighlight.OutlineColor = Color3.fromRGB(95, 170, 235)
    worldHighlight.Enabled = false
    worldHighlight.Parent = gui

    -- The selected pet's TARGET (what it's attacking/mining) — a warmer amber outline, distinct from
    -- the blue pet selection, so "this pet → that enemy" reads at a glance. Follows the live target.
    local targetHighlight = Instance.new("Highlight")
    targetHighlight.Name = "SquadTargetHighlight"
    targetHighlight.FillTransparency = 0.75
    targetHighlight.FillColor = Color3.fromRGB(255, 180, 70)
    targetHighlight.OutlineColor = Color3.fromRGB(255, 160, 40)
    targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    targetHighlight.Enabled = false
    targetHighlight.Parent = gui

    local function setSelected(slot)
        selectedSlot = slot
        -- Tell the server which pet is selected, so single-target buffs (aegis / ironclad) land on
        -- it. The slot IS the pet's PositionNumber, which the server matches in _targetPets.
        pcall(function()
            Signals.Combat_SelectPetTarget:FireServer({ slot = slot or 0 })
        end)
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

    -- Keep the target highlight on whatever the SELECTED pet is currently attacking/mining. Polled
    -- (~6 Hz) rather than per-frame — the pet's target only changes occasionally, and resolving it
    -- scans a folder. Clears when nothing is selected or the selected pet has no target.
    task.spawn(function()
        while gui.Parent do
            task.wait(0.15)
            local foe
            if selectedSlot then
                local folder = petsFolder()
                if folder then
                    for _, pet in ipairs(folder:GetChildren()) do
                        if pet:IsA("Model") and petSlot(pet) == selectedSlot then
                            if not pet:GetAttribute("CombatDowned") then
                                foe = resolveTargetModel(pet)
                            end
                            break
                        end
                    end
                end
            end
            if foe and foe.Parent then
                targetHighlight.Adornee = foe
                targetHighlight.Enabled = true
            else
                targetHighlight.Adornee = nil
                targetHighlight.Enabled = false
            end
        end
    end)

    -- Build one card (returns refs for live updates).
    local function makeCard(slot)
        local frame = Instance.new("TextButton")
        frame.Name = "Slot_" .. slot
        frame.AutoButtonColor = false
        frame.Text = ""
        frame.Size = UDim2.fromOffset(186, 44)
        frame.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
        frame.BackgroundTransparency = 0.1
        frame.BorderSizePixel = 0
        frame.LayoutOrder = slot
        frame.Parent = root
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = frame
        -- Always-on subtle outline on the black bar (so the badge poking off its edge reads);
        -- brightens to the selection blue when this slot is selected/cycled (see render loop).
        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- draw a real outer border (Contextual was invisible here)
        stroke.Color = Color3.fromRGB(70, 76, 96)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.4
        stroke.Parent = frame

        -- Archetype/role chip on the left (tank/melee/ranged/support/control). Coloured
        -- letter glyph now; swaps to art when a role gets an icon in configs/pet_roles.
        local roleChip = Instance.new("Frame")
        roleChip.Name = "Role"
        -- Anchored so the badge pokes off the card's inner edge (the "gems" look) — relative, no
        -- pixel offset. BADGE_OVERHANG is the knob: anchor-X fraction, bigger = hangs further left.
        roleChip.AnchorPoint = Vector2.new(BADGE_OVERHANG, 0.5)
        roleChip.Position = UDim2.new(0, 0, 0.5, 0)
        -- Relative: fill the card, then an aspect-ratio constraint (FitWithinMaxSize) squares it
        -- to the smaller axis = the card's HEIGHT. Scales with the card automatically — no pixels.
        roleChip.Size = UDim2.new(1, 0, 1, 0)
        roleChip.BorderSizePixel = 0
        roleChip.ClipsDescendants = false
        roleChip.Parent = frame
        local roleAspect = Instance.new("UIAspectRatioConstraint")
        roleAspect.AspectRatio = 1
        roleAspect.AspectType = Enum.AspectType.FitWithinMaxSize
        roleAspect.Parent = roleChip
        local roleCorner = Instance.new("UICorner")
        roleCorner.CornerRadius = UDim.new(0, 6)
        roleCorner.Parent = roleChip
        local roleGlyph = Instance.new("TextLabel")
        roleGlyph.Name = "Glyph"
        roleGlyph.BackgroundTransparency = 1
        roleGlyph.Size = UDim2.fromScale(1, 1)
        roleGlyph.Font = Enum.Font.GothamBold
        roleGlyph.TextSize = 14
        roleGlyph.TextColor3 = Color3.fromRGB(255, 255, 255)
        roleGlyph.TextStrokeTransparency = 0.5
        roleGlyph.Parent = roleChip
        -- The badge: a colored element DISC (roleIcon) inset behind a tinted framing RING
        -- (roleRing), built once and re-skinned each tick by PetBadge.apply. Falls back to the
        -- coloured glyph above when the (element, role) combo has no uploaded disc art.
        local roleIcon = Instance.new("ImageLabel")
        roleIcon.Name = "Icon"
        roleIcon.BackgroundTransparency = 1
        roleIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        roleIcon.Position = UDim2.fromScale(0.5, 0.5)
        roleIcon.Size = UDim2.fromScale(0.82, 0.82)
        roleIcon.ScaleType = Enum.ScaleType.Fit
        roleIcon.ZIndex = 2
        roleIcon.Image = ""
        roleIcon.Parent = roleChip
        local roleRing = Instance.new("ImageLabel")
        roleRing.Name = "Ring"
        roleRing.BackgroundTransparency = 1
        roleRing.AnchorPoint = Vector2.new(0.5, 0.5)
        roleRing.Position = UDim2.fromScale(0.5, 0.5)
        roleRing.Size = UDim2.fromScale(1, 1)
        roleRing.ScaleType = Enum.ScaleType.Fit
        roleRing.ZIndex = 3
        roleRing.Image = ""
        roleRing.Parent = roleChip

        -- Compact health bar: a near-black backing (so white text stays legible as the
        -- fill drains), a fill that goes green->yellow->red, the pet NAME inside it, and
        -- a right-aligned note (recharge countdown / Summon when downed). Rounded corners.
        local barBg = Instance.new("Frame")
        barBg.Name = "BarBg"
        barBg.Position = UDim2.fromOffset(40, 9)
        barBg.Size = UDim2.new(1, -48, 0, 20)
        barBg.BackgroundColor3 = Color3.fromRGB(12, 13, 18)
        barBg.BorderSizePixel = 0
        barBg.ClipsDescendants = true
        barBg.Parent = frame
        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 6)
        barCorner.Parent = barBg

        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.fromScale(1, 1)
        fill.BorderSizePixel = 0
        fill.ZIndex = 2
        fill.Parent = barBg
        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 6)
        fillCorner.Parent = fill

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Name = "Name"
        nameLbl.BackgroundTransparency = 1
        nameLbl.Position = UDim2.fromOffset(8, 0)
        nameLbl.Size = UDim2.new(1, -16, 1, 0)
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 13
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLbl.TextStrokeTransparency = 0.4 -- keeps it readable over any fill colour
        nameLbl.ZIndex = 3
        nameLbl.Parent = barBg

        local noteLbl = Instance.new("TextLabel")
        noteLbl.Name = "Note"
        noteLbl.BackgroundTransparency = 1
        noteLbl.Position = UDim2.fromOffset(8, 0)
        noteLbl.Size = UDim2.new(1, -16, 1, 0)
        noteLbl.Font = Enum.Font.GothamBold
        noteLbl.TextSize = 11
        noteLbl.TextXAlignment = Enum.TextXAlignment.Right
        noteLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        noteLbl.TextStrokeTransparency = 0.4
        noteLbl.ZIndex = 3
        noteLbl.Parent = barBg

        -- Thin secondary bar = shield absorption pool (blue), CoH endurance-bar style.
        -- Hidden when the pet has no shield; rounded (pill) corners.
        local shieldBg = Instance.new("Frame")
        shieldBg.Name = "ShieldBg"
        shieldBg.Position = UDim2.fromOffset(40, 31)
        shieldBg.Size = UDim2.new(1, -48, 0, 4)
        shieldBg.BackgroundColor3 = Color3.fromRGB(12, 13, 18)
        shieldBg.BorderSizePixel = 0
        shieldBg.ClipsDescendants = true
        shieldBg.Visible = false
        shieldBg.Parent = frame
        local shieldCorner = Instance.new("UICorner")
        shieldCorner.CornerRadius = UDim.new(1, 0)
        shieldCorner.Parent = shieldBg
        local shieldFill = Instance.new("Frame")
        shieldFill.Name = "ShieldFill"
        shieldFill.Size = UDim2.fromScale(0, 1)
        shieldFill.BackgroundColor3 = Color3.fromRGB(95, 170, 235)
        shieldFill.BorderSizePixel = 0
        shieldFill.Parent = shieldBg
        local shieldFillCorner = Instance.new("UICorner")
        shieldFillCorner.CornerRadius = UDim.new(1, 0)
        shieldFillCorner.Parent = shieldFill

        -- Status-badge row: anchored at the card's left edge, growing toward screen
        -- centre (left) as more buffs/debuffs stack on this pet.
        local status = Instance.new("Frame")
        status.Name = "Status"
        status.AnchorPoint = Vector2.new(1, 0.5)
        -- Start left of the overhanging role badge (which pokes ~15px off the card edge) so the
        -- status badges grow further toward centre without colliding with it.
        status.Position = UDim2.new(0, -20, 0.5, 0)
        -- Width is set by updateBadges (badges are positioned manually so same-kind ones can overlap
        -- by half — a UIListLayout's uniform spacing can't do the coin-stack).
        status.Size = UDim2.fromOffset(0, 30)
        status.AutomaticSize = Enum.AutomaticSize.None
        status.BackgroundTransparency = 1
        status.Parent = frame

        -- Admin-only ✕ KILL button (top-right): force THIS slot's pet down so the lockout / Spirit
        -- Form fires with no enemies — fast testing. Shown only while admin mode is ON (the same
        -- AdminOverlaysOn toggle that reveals the dev overlays).
        local killBtn = Instance.new("TextButton")
        killBtn.Name = "AdminKill"
        killBtn.Size = UDim2.fromOffset(20, 20)
        killBtn.AnchorPoint = Vector2.new(1, 0)
        killBtn.Position = UDim2.new(1, -2, 0, 2)
        killBtn.BackgroundColor3 = Color3.fromRGB(185, 45, 45)
        killBtn.Text = "✕"
        killBtn.Font = Enum.Font.GothamBold
        killBtn.TextSize = 13
        killBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        killBtn.ZIndex = 10
        killBtn.Visible = localPlayer:GetAttribute("AdminOverlaysOn") == true
        local killCorner = Instance.new("UICorner")
        killCorner.CornerRadius = UDim.new(1, 0)
        killCorner.Parent = killBtn
        killBtn.Parent = frame
        killBtn.Activated:Connect(function()
            Signals.Squad_AdminKill:FireServer({ slot = slot })
        end)
        localPlayer:GetAttributeChangedSignal("AdminOverlaysOn"):Connect(function()
            killBtn.Visible = localPlayer:GetAttribute("AdminOverlaysOn") == true
        end)

        frame.MouseButton1Click:Connect(function()
            -- A downed pet whose cooldown has elapsed shows "Summon" — clicking the card
            -- re-summons it. Otherwise a click just selects the slot (assist target).
            local c = cards[slot]
            if c and c.summonReady then
                Signals.Squad_Summon:FireServer({ slot = slot })
            else
                setSelected(slot)
            end
        end)

        return {
            frame = frame,
            stroke = stroke,
            name = nameLbl,
            note = noteLbl,
            fill = fill,
            shieldBg = shieldBg,
            shieldFill = shieldFill,
            roleChip = roleChip,
            roleGlyph = roleGlyph,
            roleIcon = roleIcon,
            roleRing = roleRing,
            status = status,
            badges = {},
        }
    end

    -- (Removed the per-slot Recall/Summon/Heal/Buff action row — squad control now
    -- lives on the bottom hotbar. Card selection still drives assist-target + cycle.)

    -- World click: clicking a pet selects its slot; clicking an ENEMY directs the squad
    -- to focus it (assist target). Clicking empty space clears the assist.
    local function enemiesFolder()
        local g = Workspace:FindFirstChild("Game")
        return g and g:FindFirstChild("Enemies")
    end
    local mouse = localPlayer:GetMouse()
    mouse.Button1Down:Connect(function()
        local target = mouse.Target
        local model = target and target:FindFirstAncestorWhichIsA("Model")
        local pets = petsFolder()
        if model and pets and model:IsDescendantOf(pets) then
            setSelected(petSlot(model))
            return
        end
        local enemies = enemiesFolder()
        if model and enemies and model:IsDescendantOf(enemies) then
            local bid = model:FindFirstChild("BreakableID")
            assistTargetBid = bid and bid.Value or nil
            Signals.Combat_SetAssist:FireServer({ targetId = bid and bid.Value or 0 })
        elseif not model then
            assistTargetBid = nil
            Signals.Combat_SetAssist:FireServer({ targetId = 0 }) -- clicked empty -> clear
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

    -- Enemy assist cycle (Z): step the assist target through nearby enemies (and, if
    -- configured, mining targets), directing the squad to focus one. Mirrors the Q cycle.
    local enemyCycleName = (controls.keybinds and controls.keybinds.enemy_cycle) or "Z"
    local okE, enemyCycleKey = pcall(function()
        return Enum.KeyCode[enemyCycleName]
    end)
    if not okE or not enemyCycleKey then
        enemyCycleKey = Enum.KeyCode.Z
    end
    local ecCfg = controls.enemy_cycle or {}
    local cycleRange = ecCfg.range or 80
    local includeMining = ecCfg.include_mining == true

    local function orderedEnemies()
        local out = {}
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return out
        end
        local function add(m)
            if m and m:IsA("Model") and m.PrimaryPart and (m:GetAttribute("HP") or 0) > 0 then
                local bid = m:FindFirstChild("BreakableID")
                if bid then
                    local d = (m.PrimaryPart.Position - hrp.Position).Magnitude
                    if d <= cycleRange then
                        out[#out + 1] = { bid = bid.Value, dist = d }
                    end
                end
            end
        end
        local enemies = enemiesFolder()
        if enemies then
            for _, m in ipairs(enemies:GetChildren()) do
                add(m)
            end
        end
        if includeMining then
            local g = Workspace:FindFirstChild("Game")
            local breakables = g and g:FindFirstChild("Breakables")
            if breakables then
                for _, d in ipairs(breakables:GetDescendants()) do
                    if d.Name == "BreakableID" and d:IsA("NumberValue") then
                        add(d.Parent)
                    end
                end
            end
        end
        table.sort(out, function(a, b)
            return a.dist < b.dist
        end)
        return out
    end

    local function cycleEnemy(dir)
        local list = orderedEnemies()
        if #list == 0 then
            assistTargetBid = nil
            Signals.Combat_SetAssist:FireServer({ targetId = 0 })
            return
        end
        local idx
        for i, e in ipairs(list) do
            if e.bid == assistTargetBid then
                idx = i
                break
            end
        end
        if not idx then
            idx = (dir > 0) and 1 or #list
        else
            idx = ((idx - 1 + dir) % #list) + 1
        end
        assistTargetBid = list[idx].bid
        Signals.Combat_SetAssist:FireServer({ targetId = assistTargetBid })
    end

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return -- don't cycle while typing in a TextBox, etc.
        end
        local reverse = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        if input.KeyCode == cycleKey then
            cycle(reverse and -1 or 1)
        elseif input.KeyCode == enemyCycleKey then
            cycleEnemy(reverse and -1 or 1)
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
                    card.name.Text = s.name
                        .. (s.variant ~= "basic" and (" (" .. s.variant .. ")") or "")
                    -- Archetype/role badge: element DISC + tinted aura RING (the universal
                    -- PetBadge). Element from the pet's origin; role from PetRole/by_type. Falls
                    -- back to the coloured letter glyph when that (element, role) has no disc art.
                    local role = roleFor(pet)
                    local roleId = pet:GetAttribute("PetRole")
                        or (PET_ROLES.by_type and PET_ROLES.by_type[pet:GetAttribute("PetType")])
                        or PET_ROLES.default
                    local element = PetBadge.elementForPetType(pet:GetAttribute("PetType"))
                    local hasBadge = PetBadge.apply(card.roleIcon, card.roleRing, element, roleId)
                    card.roleChip.BackgroundColor3 = role.color
                    card.roleChip.BackgroundTransparency = hasBadge and 1 or 0
                    card.roleGlyph.Visible = not hasBadge
                    card.roleGlyph.Text = role.glyph
                    if s.downed then
                        -- TWO BARS (down-lockout). Main = THIS pet's recovery (drains as it heals; a
                        -- unique special scales to the 5-min lockout, a stack to the 1-min slot). The
                        -- thin bar below = the SLOT's 1-min timer, so you can see when to re-summon
                        -- this pet vs. when the slot frees for a different / stack pet.
                        local petTotal = (s.special and lockoutDur.petSpecial) or lockoutDur.slot
                        local petFrac = (petTotal > 0 and s.cdRemaining > 0)
                                and math.clamp(s.cdRemaining / petTotal, 0, 1)
                            or (s.cdRemaining > 0 and 1 or 0)
                        card.fill.Size = UDim2.fromScale(s.cdRemaining > 0 and petFrac or 1, 1)
                        card.fill.BackgroundColor3 = s.cdRemaining > 0 and STATE_COLOR.Recharging
                            or STATE_COLOR.Ready
                        card.note.Text = s.cdRemaining > 0 and formatTime(s.cdRemaining) or "Summon"
                        card.summonReady = s.cdRemaining <= 0
                    else
                        -- Health fill drains + recolours green->yellow->red.
                        card.fill.Size = UDim2.fromScale(math.clamp(s.healthFraction, 0, 1), 1)
                        card.fill.BackgroundColor3 = healthColor(s.healthFraction)
                        card.note.Text = ""
                        card.summonReady = false
                    end
                    -- Thin secondary bar: the SLOT timer (orange) when downed, else the shield pool (blue).
                    if s.downed then
                        local slotFrac = lockoutDur.slot > 0
                                and math.clamp(s.slotRemaining / lockoutDur.slot, 0, 1)
                            or 0
                        card.shieldBg.Visible = s.slotRemaining > 0
                        card.shieldFill.Size = UDim2.fromScale(slotFrac, 1)
                        card.shieldFill.BackgroundColor3 = SLOT_BAR_COLOR
                    else
                        local shieldF = s.shieldFraction or 0
                        card.shieldBg.Visible = shieldF > 0
                        card.shieldFill.Size = UDim2.fromScale(shieldF, 1)
                        card.shieldFill.BackgroundColor3 = SHIELD_BAR_COLOR
                    end
                    -- Selection = an OUTLINE only (the gems-pill look): the dark bar stays dark, just
                    -- the stroke pops to bright blue. No background colour change (that swamped it).
                    local isSel = selectedSlot == s.slot
                    card.stroke.Color = isSel and Color3.fromRGB(120, 200, 255)
                        or Color3.fromRGB(70, 76, 96)
                    card.stroke.Transparency = isSel and 0 or 0.5
                    card.stroke.Thickness = isSel and 3 or 1.5
                    card.frame.BackgroundTransparency = isSel and 0 or 0.1
                    updateBadges(card, activeEffectsFor(pet, localPlayer, os.time()), blinkLead)
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

    -- Expiry blink: runs every frame (not the 0.2s reconcile) so the flash is smooth.
    -- Blinks via TRANSPARENCY (not Visible) so the badge keeps its layout slot — the row
    -- doesn't re-pack/shift each blink. Badges flagged `blinking` fade on a tuned cycle.
    RunService.RenderStepped:Connect(function()
        local on = (os.clock() % blinkPeriod) < (blinkPeriod * 0.5)
        for _, card in pairs(cards) do
            for _, b in pairs(card.badges) do
                local hidden = b.blinking and not on
                b.icon.ImageTransparency = hidden and 1 or 0
                b.ring.ImageTransparency = hidden and 1 or 0
                b.label.TextTransparency = hidden and 1 or 0
                b.timer.TextTransparency = hidden and 1 or 0
                b.frame.BackgroundTransparency = hidden and 1 or (b.bgBase or 0)
            end
        end
    end)
end

return SquadHud
