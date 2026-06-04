--[[
    RealmAtmosphere (client) — retint the world to signal the player's current realm (World S3).

    Reuses the SAME map: instead of teleporting to authored heaven/hell geometry, this skins
    Lighting (a ColorCorrectionEffect tint + ClockTime) to a realm theme when the server-published
    `CurrentRealm` player attribute changes — neutral (base) = unchanged, heaven = radiant gold,
    hell = ember dark. Themes are config-as-code (configs/layers.lua `atmosphere`). Lighting is
    client-side, so each player sees their own realm skin (the convenient solo-test path; true
    spatial separation is the production geometry slice, task #157).
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TINT_NAME = "RealmTint"

local DEFAULT_THEMES = {
    tween_seconds = 1.0,
    neutral = { tint = { 1, 1, 1 }, brightness = 0, contrast = 0, clock_time = 14 },
    heaven = { tint = { 1, 0.96, 0.82 }, brightness = 0.12, contrast = 0.1, clock_time = 16 },
    hell = { tint = { 1, 0.62, 0.5 }, brightness = -0.08, contrast = 0.22, clock_time = 4 },
}

local RealmAtmosphere = {}

local function loadAtmosphere()
    local configs = ReplicatedStorage:FindFirstChild("Configs")
    local mod = configs and configs:FindFirstChild("layers")
    if mod and mod:IsA("ModuleScript") then
        local ok, cfg = pcall(require, mod)
        if ok and type(cfg) == "table" and type(cfg.atmosphere) == "table" then
            return cfg.atmosphere
        end
    end
    return DEFAULT_THEMES
end

local function color3(t, fallback)
    if type(t) == "table" and t[1] then
        return Color3.new(t[1], t[2] or t[1], t[3] or t[1])
    end
    return fallback
end

function RealmAtmosphere.start()
    local player = Players.LocalPlayer
    if not player then
        return
    end
    local themes = loadAtmosphere()
    local tweenInfo = TweenInfo.new(
        tonumber(themes.tween_seconds) or 1.0,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )

    local tint = Lighting:FindFirstChild(TINT_NAME)
    if not tint then
        tint = Instance.new("ColorCorrectionEffect")
        tint.Name = TINT_NAME
        tint.Enabled = true
        tint.Parent = Lighting
    end

    local function apply(realm)
        local theme = themes[realm] or themes.neutral or DEFAULT_THEMES.neutral
        TweenService:Create(tint, tweenInfo, {
            TintColor = color3(theme.tint, Color3.new(1, 1, 1)),
            Brightness = tonumber(theme.brightness) or 0,
            Contrast = tonumber(theme.contrast) or 0,
        }):Play()
        local clock = tonumber(theme.clock_time)
        if clock then
            TweenService:Create(Lighting, tweenInfo, { ClockTime = clock }):Play()
        end
    end

    apply(player:GetAttribute("CurrentRealm") or "neutral")
    player:GetAttributeChangedSignal("CurrentRealm"):Connect(function()
        apply(player:GetAttribute("CurrentRealm") or "neutral")
    end)
end

return RealmAtmosphere
