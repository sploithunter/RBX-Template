--[[
    GameEvents (client) — one hook for every gameplay event; configs/game_events.lua decides the
    reactions.

    Game code DETECTS an event (a level changed, a death, a hit) and calls GameEvents.fire(name, ctx).
    This dispatcher looks up configs/game_events.lua[name] and applies each configured reaction by
    kind. Reaction handlers are registered here once (sound now; vfx/toast/callback can be added the
    same way). So "react to event X" is config; the only code is firing the event and the generic
    handler for each reaction kind.

      • Local fire:  require this module and call GameEvents.fire("level_up", { level = n })
      • Server fire: Signals.GameEvent:FireClient(player, name, ctx) -> bridged to fire() in start()
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)
local SoundGroups = require(ReplicatedStorage.Shared.Effects.SoundGroups)
local sounds = require(ReplicatedStorage.Configs:WaitForChild("sounds"))
local eventConfig = require(ReplicatedStorage.Configs:WaitForChild("game_events"))

local GameEvents = {}

-- reaction kind -> handler(spec, ctx). Add a new kind here and it's instantly usable from config.
local REACTIONS = {}

-- sound: spec is a key into configs/sounds.lua; play it one-shot on its configured bus.
REACTIONS.sound = function(soundKey)
    local def = soundKey and sounds[soundKey]
    if not (def and def.id) then
        return
    end
    local s = Instance.new("Sound")
    s.SoundId = def.id
    s.Volume = def.volume or 0.7
    s.PlaybackSpeed = def.playback_speed or 1
    SoundGroups.assign(s, def.bus or "ui")
    s.Parent = SoundService
    s:Play()
    s.Ended:Once(function()
        s:Destroy()
    end)
    task.delay(8, function() -- safety cleanup if Ended never fires (unapproved/failed asset)
        if s.Parent then
            s:Destroy()
        end
    end)
end

-- vfx: spec = { kind = "burst", color = {r,g,b}?, count = n? }. A self-contained celebratory burst
-- (neon shards flying outward + fading) at the local player — no asset/CombatFX dependency, so it
-- always renders. More `kind`s can be added here (or routed to CombatFX) without config changes.
REACTIONS.vfx = function(spec)
    spec = type(spec) == "table" and spec or {}
    if spec.kind ~= "burst" then
        return
    end
    local char = Players.LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end
    local c = spec.color
    local color = (type(c) == "table") and Color3.fromRGB(c[1] or 255, c[2] or 255, c[3] or 255)
        or Color3.fromRGB(255, 205, 70)
    local count = tonumber(spec.count) or 16
    local origin = hrp.Position + Vector3.new(0, 2, 0)
    for i = 1, count do
        local part = Instance.new("Part")
        part.Size = Vector3.new(0.35, 0.35, 0.35)
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = color
        part.CFrame = CFrame.new(origin)
        part.Parent = Workspace
        local ang = (i / count) * math.pi * 2
        local dist = 3.5 + (i % 3)
        local target = origin + Vector3.new(math.cos(ang) * dist, 2 + (i % 4), math.sin(ang) * dist)
        TweenService:Create(part, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
            CFrame = CFrame.new(target),
            Transparency = 1,
            Size = Vector3.new(0.05, 0.05, 0.05),
        }):Play()
        task.delay(0.9, function()
            if part.Parent then
                part:Destroy()
            end
        end)
    end
end

-- float: rising announcement text. spec = { color = {r,g,b}?, prefix = ""?, size = px? };
-- the TEXT comes from ctx.name (config stays generic). Anchors at ctx.position (a Vector3 —
-- e.g. the broken crystal) when given, else at the local player.
-- banner: a LINGERING screen-center announcement card — "you got an achievement"-class
-- moments (Jason: floats are too quick for these; and NEVER play a sound without a
-- visual). Text = ctx.name; spec = { seconds (default 5), color {r,g,b} }.
-- One banner at a time: a newer one replaces the current.
local activeBanner
REACTIONS.banner = function(spec, ctx)
    spec = type(spec) == "table" and spec or {}
    local text = (ctx and ctx.name) and tostring(ctx.name) or nil
    if not text then
        return
    end
    local player = Players.LocalPlayer
    local pg = player and player:FindFirstChild("PlayerGui")
    if not pg then
        return
    end
    if activeBanner then
        activeBanner:Destroy()
        activeBanner = nil
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "GameEventBanner"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 60
    local card = Instance.new("Frame")
    card.AnchorPoint = Vector2.new(0.5, 0)
    card.Position = UDim2.new(0.5, 0, 0.22, 0)
    card.Size = UDim2.fromOffset(380, 56)
    card.BackgroundColor3 = Color3.fromRGB(24, 22, 32)
    card.BackgroundTransparency = 0.08
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = card
    local accent = spec.color and Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
        or Color3.fromRGB(255, 200, 90)
    local stroke = Instance.new("UIStroke")
    stroke.Color = accent
    stroke.Thickness = 2.5
    stroke.Parent = card
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -24, 1, -12)
    label.Position = UDim2.fromOffset(12, 6)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = accent
    label.TextScaled = true
    label.Font = Enum.Font.GothamBlack
    label.Parent = card
    card.Parent = gui
    gui.Parent = pg
    pcall(function()
        require(script.Parent.Parent.UI.UIViewportScale).attach(card)
    end)
    activeBanner = gui
    local seconds = tonumber(spec.seconds) or 5
    task.delay(seconds, function()
        if activeBanner == gui then
            -- quick fade then gone
            local TweenService = game:GetService("TweenService")
            local info = TweenInfo.new(0.4)
            TweenService:Create(card, info, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(label, info, { TextTransparency = 1 }):Play()
            TweenService:Create(stroke, info, { Transparency = 1 }):Play()
            task.delay(0.45, function()
                if activeBanner == gui then
                    activeBanner = nil
                end
                gui:Destroy()
            end)
        end
    end)
end

REACTIONS.float = function(spec, ctx)
    spec = type(spec) == "table" and spec or {}
    local text = (ctx and ctx.name) and tostring(ctx.name) or nil
    if not text then
        return
    end
    if spec.prefix then
        text = tostring(spec.prefix) .. text
    end
    local adornee
    if ctx and typeof(ctx.position) == "Vector3" then
        -- world-anchored: a throwaway anchor part at the event position
        local anchor = Instance.new("Part")
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanQuery = false
        anchor.Transparency = 1
        anchor.Size = Vector3.new(0.1, 0.1, 0.1)
        anchor.CFrame = CFrame.new(ctx.position)
        anchor.Parent = Workspace
        task.delay(2, function()
            anchor:Destroy()
        end)
        adornee = anchor
    else
        local char = Players.LocalPlayer.Character
        adornee = char and char:FindFirstChild("HumanoidRootPart")
    end
    if not adornee then
        return
    end
    local c = spec.color
    local color = (type(c) == "table") and Color3.fromRGB(c[1] or 255, c[2] or 255, c[3] or 255)
        or Color3.fromRGB(255, 235, 170)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(spec.size or 360, 44)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = adornee
    bb.Parent = adornee
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBlack
    lbl.TextScaled = true
    lbl.Text = text
    lbl.TextColor3 = color
    lbl.TextStrokeTransparency = 0.3
    lbl.Parent = bb
    TweenService:Create(bb, TweenInfo.new(1.6, Enum.EasingStyle.Quad), {
        StudsOffset = Vector3.new(0, 7, 0),
    }):Play()
    TweenService:Create(lbl, TweenInfo.new(1.6), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    }):Play()
    task.delay(1.7, function()
        bb:Destroy()
    end)
end

-- Fire a named event: apply every configured reaction. `ctx` is forwarded to handlers (future use).
function GameEvents.fire(name, ctx)
    local entry = eventConfig[name]
    if type(entry) ~= "table" then
        return -- no reactions configured for this event
    end
    for kind, spec in pairs(entry) do
        local handler = REACTIONS[kind]
        if handler then
            local ok, err = pcall(handler, spec, ctx)
            if not ok then
                warn(
                    ("GameEvents: reaction '%s' for '%s' failed: %s"):format(
                        kind,
                        name,
                        tostring(err)
                    )
                )
            end
        end
    end
end

-- Bridge server-origin events (death/hit/...) onto the same hook.
function GameEvents.start()
    if Signals.GameEvent then
        Signals.GameEvent.OnClientEvent:Connect(function(name, ctx)
            if type(name) == "string" then
                GameEvents.fire(name, ctx)
            end
        end)
    end
    return GameEvents
end

local _ = Players.LocalPlayer -- ensure client context
return GameEvents
