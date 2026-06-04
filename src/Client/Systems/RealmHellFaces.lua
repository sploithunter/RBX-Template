--[[
    RealmHellFaces (client) — floating demon faces in the Hell sky (World S3).

    When the player is in a hell layer, clones the cached Hell-face model
    (ReplicatedStorage.RealmModels.<template>, preloaded server-side by RealmPortalService),
    scales it up huge, and hangs a ring of them very high overhead looking DOWN at the player,
    each with a dim pulsing light inside. Depth-scaled: Hell 1 = one distant face, Hell 5 = a full
    ring. Despawns when you leave Hell. Client-side (each player sees their own); composes with the
    skybox + depth-scaled lighting. All knobs in configs/layers.lua `hell_faces`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RealmHellFaces = {}

local function loadConfig()
    local configs = ReplicatedStorage:FindFirstChild("Configs")
    local mod = configs and configs:FindFirstChild("layers")
    if mod and mod:IsA("ModuleScript") then
        local ok, cfg = pcall(require, mod)
        if ok and type(cfg) == "table" and type(cfg.hell_faces) == "table" then
            return cfg.hell_faces
        end
    end
    return nil
end

local function c255(t, fallback)
    if type(t) == "table" and t[1] then
        return Color3.fromRGB(t[1], t[2] or t[1], t[3] or t[1])
    end
    return fallback
end

function RealmHellFaces.start()
    local player = Players.LocalPlayer
    if not player then
        return
    end
    local cfg = loadConfig()
    if not cfg or cfg.enabled == false then
        return
    end

    local folder = ReplicatedStorage:WaitForChild("RealmModels", 30)
    local template = folder and folder:WaitForChild(cfg.template_name or "HellFace", 30)
    if not template then
        return -- server preload not present; nothing to spawn
    end

    local container = Workspace:FindFirstChild("RealmHellFaces")
    if not container then
        container = Instance.new("Folder")
        container.Name = "RealmHellFaces"
        container.Parent = Workspace
    end

    local scale = tonumber(cfg.scale) or 100
    local height = tonumber(cfg.height) or 600
    local spread = tonumber(cfg.spread) or 480

    local function spawnRing(depth)
        container:ClearAllChildren()
        local count = (tonumber(cfg.base_count) or 1)
            + (depth - 1) * (tonumber(cfg.per_depth_count) or 1)
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local center = (hrp and hrp.Position) or Vector3.new(0, 0, 0)
        for i = 1, count do
            local face = template:Clone()
            if face:IsA("Model") then
                if not face.PrimaryPart then
                    face.PrimaryPart = face:FindFirstChildWhichIsA("BasePart", true)
                end
                local extent = face:GetExtentsSize()
                local maxdim = math.max(extent.X, extent.Y, extent.Z, 0.01)
                face:ScaleTo(scale / maxdim)
            end
            local angle = (i / count) * math.pi * 2
            local pos = center
                + Vector3.new(
                    math.cos(angle) * spread,
                    height + (i % 3) * (height * 0.08),
                    math.sin(angle) * spread
                )
            local cf = CFrame.lookAt(pos, center) -- stare down at the player
            if face:IsA("Model") then
                face:PivotTo(cf)
            elseif face:IsA("BasePart") then
                face.CFrame = cf
            end
            local lp = (face:IsA("Model") and face.PrimaryPart) or (face:IsA("BasePart") and face)
            if lp then
                local light = Instance.new("PointLight")
                light.Color = c255(cfg.light_color, Color3.fromRGB(255, 45, 25))
                light.Brightness = tonumber(cfg.light_brightness) or 3
                light.Range = tonumber(cfg.light_range) or 180
                light.Parent = lp
                local pulse = TweenInfo.new(
                    tonumber(cfg.pulse_seconds) or 2.4,
                    Enum.EasingStyle.Sine,
                    Enum.EasingDirection.InOut,
                    -1,
                    true
                )
                TweenService
                    :Create(light, pulse, { Brightness = tonumber(cfg.pulse_brightness) or 5 })
                    :Play()
            end
            face.Parent = container
        end
    end

    local function refresh()
        if (player:GetAttribute("CurrentRealm")) == "hell" then
            local layer = tostring(player:GetAttribute("CurrentLayer") or "hell_1")
            local depth = tonumber(layer:match("_(%d+)$")) or 1
            spawnRing(depth)
        else
            container:ClearAllChildren()
        end
    end

    refresh()
    player:GetAttributeChangedSignal("CurrentLayer"):Connect(refresh)
end

return RealmHellFaces
