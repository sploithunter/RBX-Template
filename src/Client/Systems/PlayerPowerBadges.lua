--[[
    PlayerPowerBadges — a small HUD row of the PLAYER's own active power buffs.

    The squad cards show buffs on the PETS; this shows the buffs the player cast on THEMSELF
    (Mountain's Strength, Prospector, Fortune, Swift, Hasten, XP Surge, …). Each is a player
    attribute `<Buff>` + `<Buff>Until` (an os.time stamp) + `<Buff>PowerId` (which power applied
    it). The badge is the universal two-layer disc resolved via PetBadge.forPower(powerId) — same
    art as the hotbar/cards — with a countdown that blinks in its last few seconds.

    Row sits top-centre, just under the player nameplate. Steady (refreshed) player buffs are rare,
    so these all show a countdown + near-expiry blink (timed-power behaviour, per Jason's rule).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local POWER_ICONS = require(ReplicatedStorage.Configs:WaitForChild("power_icons"))
local PetBadge = require(script.Parent.Parent.UI.PetBadge)

local PlayerPowerBadges = {}
local localPlayer = Players.LocalPlayer

-- The player self-power buffs to surface, in display order. label = short tag under the icon.
local BUFFS = {
    { attr = "PetDamageBuff", label = "DMG" }, -- Mountain's Strength
    { attr = "CritBuff", label = "CRIT" }, -- Critical Strike
    { attr = "CoinYieldPower", label = "COIN" }, -- Prospector / Windfall
    { attr = "LuckBuff", label = "LUCK" }, -- Fortune / Huge Fortune (purple clover)
    -- bunny support aura: GREEN clover (earth disc + clover_lucky — composed from
    -- existing assets, Jason's spec). Fixed badge: no PowerId to resolve.
    {
        attr = "HatchLuckBuff",
        label = "LUCK",
        fixed = { element = "earth", symbol = "clover_lucky" },
        steady = true, -- continuously refreshed aura: solid badge, no countdown/blink
    },
    { attr = "MoveSpeedBuff", label = "SPD" }, -- Swift
    { attr = "RechargeBuff", label = "RCH" }, -- Hasten
    { attr = "XpBuff", label = "XP" }, -- XP Surge
    { attr = "MagnetBuff", label = "MAG" }, -- Magnet (drop pull radius, #167)
}

local BLINK_LEAD = 5 -- seconds: blink in the final stretch
local BLINK_PERIOD = 0.5
local PERMANENT_THRESHOLD = 86400 * 30 -- >30 days remaining = always-on (passive/toggle) -> "ON"

local function makeBadge(parent, order)
    local holder = Instance.new("Frame")
    holder.Name = "PBadge"
    holder.Size = UDim2.fromOffset(38, 50)
    holder.BackgroundTransparency = 1
    holder.LayoutOrder = order
    holder.Parent = parent

    local disc = Instance.new("ImageLabel")
    disc.Name = "Disc"
    disc.Size = UDim2.fromOffset(36, 36)
    disc.Position = UDim2.fromScale(0.5, 0)
    disc.AnchorPoint = Vector2.new(0.5, 0)
    disc.BackgroundTransparency = 1
    disc.ScaleType = Enum.ScaleType.Fit
    disc.Parent = holder

    local timer = Instance.new("TextLabel")
    timer.Name = "Timer"
    timer.Size = UDim2.new(1, 0, 0, 12)
    timer.Position = UDim2.fromScale(0, 1)
    timer.AnchorPoint = Vector2.new(0, 1)
    timer.BackgroundTransparency = 1
    timer.Font = Enum.Font.GothamBold
    timer.TextScaled = true
    timer.TextColor3 = Color3.fromRGB(255, 255, 255)
    timer.TextStrokeTransparency = 0.4
    timer.Parent = holder

    return { holder = holder, disc = disc, timer = timer }
end

function PlayerPowerBadges.start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "PlayerPowerBadges"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.Parent = localPlayer:WaitForChild("PlayerGui")

    local row = Instance.new("Frame")
    row.Name = "Row"
    -- SINGLE ROW growing LEFTWARD from the player bar's left edge (Jason: players can carry
    -- a lot of buffs even at high levels, so one row stacking left scales best). Right edge
    -- pinned beside the capsule, vertically centred on it; new badges extend left.
    -- Parented INTO the capsule, so it inherits the bar's viewport scale and moves with it.
    row.AnchorPoint = Vector2.new(1, 0.5)
    row.Position = UDim2.new(0, -10, 0.5, 0)
    row.Size = UDim2.fromOffset(0, 50)
    row.AutomaticSize = Enum.AutomaticSize.X
    row.BackgroundTransparency = 1
    row.ZIndex = 8
    task.spawn(function()
        local pg = localPlayer:WaitForChild("PlayerGui")
        local bar = pg:WaitForChild("PlayerBar", 20)
        local cap = bar and bar:WaitForChild("Capsule", 10)
        if cap then
            row.Parent = cap
            gui:Destroy() -- the standalone gui is no longer needed
        else
            row.Parent = gui -- fallback: original floating placement
        end
    end)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right -- stack from the bar outward (leftward)
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = row

    local badges = {} -- attr -> badge

    RunService.RenderStepped:Connect(function()
        local now = os.time()
        for i, def in ipairs(BUFFS) do
            local untilT = localPlayer:GetAttribute(def.attr .. "Until") or 0
            local active = untilT > now
            local b = badges[def.attr]
            if active then
                if not b then
                    b = makeBadge(row, i)
                    badges[def.attr] = b
                end
                local disc
                if def.fixed then
                    disc = POWER_ICONS.discFor(def.fixed.element, def.fixed.symbol)
                else
                    local powerId = localPlayer:GetAttribute(def.attr .. "PowerId")
                    local badge = powerId and PetBadge.forPower(powerId)
                    disc = badge and POWER_ICONS.discFor(badge.element, badge.symbol)
                end
                b.disc.Image = disc or ""
                local remaining = untilT - now
                -- PASSIVE / TOGGLE buffs (Magnet/Swift/Hasten/XP) are always-on: their `Until` is a
                -- far-future sentinel. Show "ON", not a ~73-year countdown.
                local permanent = def.steady == true
                    or (localPlayer:GetAttribute(def.attr .. "Toggle") == true)
                    or remaining > PERMANENT_THRESHOLD
                if permanent then
                    -- stacked sources render as a coin-stack PILE of discs (Jason: "the
                    -- stacking makes it more powerful... rather than just having numbers"),
                    -- matching the squad-card pile. Half-overlap; capped so it can't sprawl.
                    local stacks =
                        math.min(tonumber(localPlayer:GetAttribute(def.attr .. "Stacks")) or 1, 5)
                    b.extra = b.extra or {}
                    for n = 1, stacks - 1 do
                        if not b.extra[n] then
                            local d = b.disc:Clone()
                            d.Name = "Stack" .. n
                            d.ZIndex = b.disc.ZIndex - n -- behind the front disc
                            d.Parent = b.holder
                            b.extra[n] = d
                        end
                        b.extra[n].Image = b.disc.Image
                        b.extra[n].Position = UDim2.new(0.5, n * 18, 0, 0) -- fan right, half-overlap
                        b.extra[n].ImageTransparency = 0
                    end
                    for n = stacks, #b.extra do -- prune dropped stacks
                        if b.extra[n] then
                            b.extra[n]:Destroy()
                            b.extra[n] = nil
                        end
                    end
                    b.holder.Size = UDim2.fromOffset(38 + (stacks - 1) * 18, 50)
                    b.timer.Text = "ON"
                    b.timer.TextColor3 = Color3.fromRGB(150, 230, 150)
                    b.disc.ImageTransparency = 0
                else
                    b.timer.Text = math.ceil(remaining) .. "s"
                    -- near-expiry blink (timed powers)
                    local blink = remaining <= BLINK_LEAD
                    local hidden = blink and (os.clock() % BLINK_PERIOD) >= (BLINK_PERIOD * 0.5)
                    b.disc.ImageTransparency = hidden and 0.6 or 0
                    b.timer.TextColor3 = blink and Color3.fromRGB(255, 180, 120)
                        or Color3.fromRGB(255, 255, 255)
                end
            elseif b then
                b.holder:Destroy()
                badges[def.attr] = nil -- pile discs die with the holder
            end
        end
    end)
end

return PlayerPowerBadges
