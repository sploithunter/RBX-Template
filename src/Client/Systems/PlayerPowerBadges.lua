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
    { attr = "CoinYieldPower", label = "COIN" }, -- Prospector / Windfall
    { attr = "MiningBuff", label = "MINE" }, -- Mother Lode
    { attr = "LuckBuff", label = "LUCK" }, -- Fortune / Huge Fortune
    { attr = "MoveSpeedBuff", label = "SPD" }, -- Swift
    { attr = "RechargeBuff", label = "RCH" }, -- Hasten
    { attr = "XpBuff", label = "XP" }, -- XP Surge
    { attr = "MagnetBuff", label = "MAG" }, -- Magnet (drop pull radius, #167)
}

local BLINK_LEAD = 5 -- seconds: blink in the final stretch
local BLINK_PERIOD = 0.5

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
    row.AnchorPoint = Vector2.new(0.5, 0)
    row.Position = UDim2.new(0.5, 0, 0, 132) -- top-centre, under the player nameplate
    row.Size = UDim2.fromOffset(0, 50)
    row.AutomaticSize = Enum.AutomaticSize.X
    row.BackgroundTransparency = 1
    row.Parent = gui
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
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
                local powerId = localPlayer:GetAttribute(def.attr .. "PowerId")
                local badge = powerId and PetBadge.forPower(powerId)
                local disc = badge and POWER_ICONS.discFor(badge.element, badge.symbol)
                b.disc.Image = disc or ""
                local remaining = untilT - now
                b.timer.Text = math.ceil(remaining) .. "s"
                -- near-expiry blink (timed powers)
                local blink = remaining <= BLINK_LEAD
                local hidden = blink and (os.clock() % BLINK_PERIOD) >= (BLINK_PERIOD * 0.5)
                b.disc.ImageTransparency = hidden and 0.6 or 0
                b.timer.TextColor3 = blink and Color3.fromRGB(255, 180, 120)
                    or Color3.fromRGB(255, 255, 255)
            elseif b then
                b.holder:Destroy()
                badges[def.attr] = nil
            end
        end
    end)
end

return PlayerPowerBadges
