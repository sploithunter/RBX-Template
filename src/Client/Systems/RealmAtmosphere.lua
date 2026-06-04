--[[
    RealmAtmosphere (client) — re-dress the world to signal the player's current realm (World S3).

    Reuses the SAME map: instead of teleporting to authored heaven/hell geometry, this skins
    Lighting (ColorCorrection tint, Ambient/OutdoorAmbient, Fog, ClockTime) + an Atmosphere haze
    to a realm theme when the server-published `CurrentRealm` attribute changes. Heaven = radiant
    gold, hell = ember dark (lit enough to fight), neutral (base) = the map's CAPTURED original look
    (restored, never imposed). A brief centered banner announces the realm so it's instantly clear.

    Themes are config-as-code (configs/layers.lua `atmosphere`). Lighting is client-side, so each
    player sees their own realm skin (the convenient solo-test path; true spatial separation is the
    production geometry slice, task #157).
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TINT_NAME = "RealmTint"

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
    return { tween_seconds = 1.2 }
end

local function c01(t, fallback)
    if type(t) == "table" and t[1] then
        return Color3.new(t[1], t[2] or t[1], t[3] or t[1])
    end
    return fallback
end

local function c255(t, fallback)
    if type(t) == "table" and t[1] then
        return Color3.fromRGB(t[1], t[2] or t[1], t[3] or t[1])
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
        tonumber(themes.tween_seconds) or 1.2,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )

    -- Capture the map's original look so "neutral" restores it exactly (never imposes defaults).
    local original = {
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        FogColor = Lighting.FogColor,
        FogEnd = Lighting.FogEnd,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
    }

    local tint = Lighting:FindFirstChild(TINT_NAME)
    if not tint then
        tint = Instance.new("ColorCorrectionEffect")
        tint.Name = TINT_NAME
        tint.Enabled = true
        tint.Parent = Lighting
    end

    -- Reuse an existing Atmosphere if the map has one (and remember its originals); otherwise
    -- create one we manage and switch off (density 0) when neutral.
    local atmos = Lighting:FindFirstChildWhichIsA("Atmosphere")
    local atmosCreated = false
    local atmosOriginal
    if atmos then
        atmosOriginal = {
            Density = atmos.Density,
            Offset = atmos.Offset,
            Color = atmos.Color,
            Decay = atmos.Decay,
            Glare = atmos.Glare,
            Haze = atmos.Haze,
        }
    else
        atmos = Instance.new("Atmosphere")
        atmos.Density = 0
        atmos.Parent = Lighting
        atmosCreated = true
    end

    local function tween(inst, goal)
        TweenService:Create(inst, tweenInfo, goal):Play()
    end

    local function banner(realm)
        local gui = player:FindFirstChild("PlayerGui")
        if not gui then
            return
        end
        local screen = gui:FindFirstChild("RealmBanner")
        if not screen then
            screen = Instance.new("ScreenGui")
            screen.Name = "RealmBanner"
            screen.ResetOnSpawn = false
            screen.IgnoreGuiInset = true
            screen.Parent = gui
            local label = Instance.new("TextLabel")
            label.Name = "Label"
            label.AnchorPoint = Vector2.new(0.5, 0.5)
            label.Position = UDim2.new(0.5, 0, 0.28, 0)
            label.Size = UDim2.new(0.6, 0, 0, 60)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBlack
            label.TextSize = 42
            label.TextStrokeTransparency = 0.4
            label.TextTransparency = 1
            label.Parent = screen
        end
        local label = screen:FindFirstChild("Label")
        if not label then
            return
        end
        if realm == "heaven" then
            label.Text = "✦  HEAVEN  ✦"
            label.TextColor3 = Color3.fromRGB(255, 240, 180)
        elseif realm == "hell" then
            label.Text = "☠  HELL  ☠"
            label.TextColor3 = Color3.fromRGB(255, 110, 90)
        else
            label.Text = "Returned to the Base Realm"
            label.TextColor3 = Color3.fromRGB(235, 235, 245)
        end
        label.TextTransparency = 1
        TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
        task.delay(2.2, function()
            if label and label.Parent then
                TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
            end
        end)
    end

    local function apply(realm)
        local theme = themes[realm]
        if not theme then
            -- Neutral / base: restore the captured original look.
            tween(Lighting, original)
            tween(tint, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0 })
            if atmosCreated then
                tween(atmos, { Density = 0 })
            elseif atmosOriginal then
                tween(atmos, atmosOriginal)
            end
            return
        end
        tween(Lighting, {
            Ambient = c255(theme.ambient, original.Ambient),
            OutdoorAmbient = c255(theme.outdoor_ambient, original.OutdoorAmbient),
            FogColor = c255(theme.fog_color, original.FogColor),
            FogEnd = tonumber(theme.fog_end) or original.FogEnd,
            Brightness = tonumber(theme.brightness) or original.Brightness,
            ClockTime = tonumber(theme.clock_time) or original.ClockTime,
        })
        tween(tint, {
            TintColor = c01(theme.tint, Color3.new(1, 1, 1)),
            Brightness = tonumber(theme.brightness) or 0,
            Contrast = tonumber(theme.contrast) or 0,
        })
        local a = theme.atmosphere
        if type(a) == "table" then
            tween(atmos, {
                Density = tonumber(a.density) or 0.3,
                Offset = tonumber(a.offset) or 0.1,
                Color = c255(a.color, Color3.fromRGB(200, 200, 200)),
                Decay = c255(a.decay, Color3.fromRGB(150, 150, 150)),
                Glare = tonumber(a.glare) or 0.2,
                Haze = tonumber(a.haze) or 1.5,
            })
        end
    end

    local function onRealm()
        local realm = player:GetAttribute("CurrentRealm") or "neutral"
        apply(realm)
        banner(realm)
    end

    -- Apply current state silently on join (no banner spam), then react to changes.
    apply(player:GetAttribute("CurrentRealm") or "neutral")
    player:GetAttributeChangedSignal("CurrentRealm"):Connect(onRealm)
end

return RealmAtmosphere
