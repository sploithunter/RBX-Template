--[[
    RealmHellFaces (client) — a giant demon head looming in the Hell sky (World S3).

    When the player is in a hell layer, clones the cached Hell-head model
    (ReplicatedStorage.RealmModels.<template>, preloaded server-side by RealmPortalService),
    scales it up huge, and hangs it OFF TO ONE SIDE high in the sky (not straight overhead —
    Roblox cameras hate looking straight up), facing the player. The face body is darkened so it
    recedes into shadow; two Neon eyes are RAYCAST-SEATED into the actual mesh sockets and recessed
    so they glow from deep in the skull. Despawns when you leave Hell. Client-side (each player sees
    their own). Depth-scaled: with per_depth_count > 0, deeper layers add more faces around you.
    All knobs in configs/layers.lua `hell_faces`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- Darken the head so it recedes into shadow (only the eyes should read).
local function darken(face, color, materialName)
    local mat = Enum.Material[materialName or "SmoothPlastic"] or Enum.Material.SmoothPlastic
    local function apply(p)
        p.Material = mat
        p.Color = color
    end
    if face:IsA("BasePart") then
        apply(face)
    elseif face:IsA("Model") then
        for _, d in ipairs(face:GetDescendants()) do
            if d:IsA("BasePart") then
                apply(d)
            end
        end
    end
end

-- Raycast-seat two Neon eyes into the mesh sockets and recess them for a sunken, glowing look.
local function seatEyes(face, eyesCfg)
    if type(eyesCfg) ~= "table" or eyesCfg.enabled == false then
        return
    end
    local up = tonumber(eyesCfg.up) or 30
    local side = tonumber(eyesCfg.side) or 35
    local recess = tonumber(eyesCfg.recess) or 30
    local sizeN = tonumber(eyesCfg.size) or 34
    local orbColor = c255(eyesCfg.color, Color3.fromRGB(255, 30, 12))
    local lightColor = c255(eyesCfg.light_color, Color3.fromRGB(255, 40, 18))
    local lightBrightness = tonumber(eyesCfg.light_brightness) or 14
    local lightRange = tonumber(eyesCfg.light_range) or 95

    -- Raycasts need the head queryable; the preload sets CanQuery=false, so toggle it for the cast.
    local prevQuery = face:IsA("BasePart") and face.CanQuery or nil
    if face:IsA("BasePart") then
        face.CanQuery = true
    end

    local cf = face:IsA("Model") and face:GetPivot() or face.CFrame
    local fcenter = cf.Position
    local L, U, R = cf.LookVector, cf.UpVector, cf.RightVector

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { face }

    for _, sign in ipairs({ 1, -1 }) do
        local lateral = U * up + R * (side * sign)
        local res = Workspace:Raycast(fcenter + L * 400 + lateral, -L * 800, params)
        local epos = res and (res.Position - L * recess) or (fcenter + lateral + L * 45)

        local eye = Instance.new("Part")
        eye.Name = sign > 0 and "HellEyeL" or "HellEyeR"
        eye.Shape = Enum.PartType.Ball
        eye.Anchored, eye.CanCollide, eye.CanQuery, eye.CastShadow = true, false, false, false
        eye.Material = Enum.Material.Neon
        eye.Color = orbColor
        eye.Size = Vector3.new(sizeN, sizeN, sizeN)
        eye.CFrame = CFrame.new(epos)
        local light = Instance.new("PointLight")
        light.Color = lightColor
        light.Brightness = lightBrightness
        light.Range = lightRange
        light.Parent = eye
        eye.Parent = face
    end

    if face:IsA("BasePart") and prevQuery ~= nil then
        face.CanQuery = prevQuery
    end
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

    local scale = tonumber(cfg.scale) or 240
    local height = tonumber(cfg.height) or 350
    local distance = tonumber(cfg.distance) or 450
    local azimuth = math.rad(tonumber(cfg.azimuth_deg) or 0)
    local faceColor = c255(cfg.face_color, Color3.fromRGB(35, 12, 10))

    local function placeOneFace(center, az)
        local face = template:Clone()
        -- scale to target max-dimension (Model -> ScaleTo; single MeshPart -> resize)
        if face:IsA("Model") then
            if not face.PrimaryPart then
                face.PrimaryPart = face:FindFirstChildWhichIsA("BasePart", true)
            end
            local e = face:GetExtentsSize()
            face:ScaleTo(scale / math.max(e.X, e.Y, e.Z, 0.01))
        elseif face:IsA("BasePart") then
            local m = math.max(face.Size.X, face.Size.Y, face.Size.Z, 0.01)
            face.Size = face.Size * (scale / m)
        end

        -- off to one side, high, facing the player
        local pos = Vector3.new(
            center.X + math.cos(az) * distance,
            center.Y + height,
            center.Z + math.sin(az) * distance
        )
        local cf = CFrame.lookAt(pos, center)
        if face:IsA("Model") then
            face:PivotTo(cf)
        elseif face:IsA("BasePart") then
            face.CFrame = cf
        end

        darken(face, faceColor, cfg.face_material)
        face.Parent = container -- parent first so the eye raycasts hit it in the world
        seatEyes(face, cfg.eyes)
    end

    local function spawnFaces(depth)
        container:ClearAllChildren()
        local count = (tonumber(cfg.base_count) or 1)
            + (depth - 1) * (tonumber(cfg.per_depth_count) or 0)
        if count < 1 then
            count = 1
        end
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local center = (hrp and hrp.Position) or Vector3.new(0, 0, 0)
        for i = 1, count do
            -- single face sits at the base azimuth; extra (depth) faces ring around the player
            local az = azimuth + (count > 1 and ((i - 1) / count) * math.pi * 2 or 0)
            placeOneFace(center, az)
        end
    end

    local function refresh()
        if (player:GetAttribute("CurrentRealm")) == "hell" then
            local layer = tostring(player:GetAttribute("CurrentLayer") or "hell_1")
            local depth = tonumber(layer:match("_(%d+)$")) or 1
            spawnFaces(depth)
        else
            container:ClearAllChildren()
        end
    end

    refresh()
    player:GetAttributeChangedSignal("CurrentLayer"):Connect(refresh)
end

return RealmHellFaces
