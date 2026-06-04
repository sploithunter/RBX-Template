--[[
    RealmHellFaces (client) — "the watcher": a giant demon head that haunts HELL 5 (World S3).

    Only ever appears in Hell 5. Clones the cached Hell-head model (ReplicatedStorage.RealmModels,
    preloaded server-side by RealmPortalService), scales it up huge, darkens the face into shadow,
    and raycast-seats two recessed Neon eyes deep in the sockets. Then it:
      - APPEARS INTERMITTENTLY: rolls a chance every few seconds to fade in or back out, so it's
        not always there — you catch it watching, then it's gone.
      - FOLLOWS THE PLAYER: glides each frame to hover at ~45 deg up, 200 studs out, always turning
        to face you (head + eyes are one Model moved via PivotTo).
    Despawns when you leave Hell 5. Client-side (each player sees their own). Knobs: layers.lua
    `hell_faces`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local function darken(part, color, materialName)
    part.Material = Enum.Material[materialName or "SmoothPlastic"] or Enum.Material.SmoothPlastic
    part.Color = color
end

-- Raycast-seat two Neon eyes into the mesh sockets, recessed for a sunken glow. Parents them under
-- `parent` (the assembly Model) and returns { {part=, light=, base=} } for fade control.
local function seatEyes(head, eyesCfg, parent)
    local eyes = {}
    if type(eyesCfg) ~= "table" or eyesCfg.enabled == false then
        return eyes
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
    local prevQuery = head.CanQuery
    head.CanQuery = true

    local cf = head.CFrame
    local fcenter, L, U, R = cf.Position, cf.LookVector, cf.UpVector, cf.RightVector
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { head }

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
        eye.Parent = parent
        eyes[#eyes + 1] = { part = eye, light = light, base = lightBrightness }
    end

    head.CanQuery = prevQuery
    return eyes
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
    if not template or not template:IsA("BasePart") then
        return -- preload missing / unexpected shape
    end

    local container = Workspace:FindFirstChild("RealmHellFaces")
    if not container then
        container = Instance.new("Folder")
        container.Name = "RealmHellFaces"
        container.Parent = Workspace
    end

    local scale = tonumber(cfg.scale) or 240
    local faceColor = c255(cfg.face_color, Color3.fromRGB(35, 12, 10))

    -- where the head wants to be this instant: off at follow_distance / follow_height, facing player
    local function targetCFrame()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local c = (hrp and hrp.Position) or Vector3.new(0, 0, 0)
        local az = math.rad(tonumber(cfg.follow_azimuth_deg) or 0)
        local dist = tonumber(cfg.follow_distance) or 200
        local h = tonumber(cfg.follow_height) or 200
        local pos = Vector3.new(c.X + math.cos(az) * dist, c.Y + h, c.Z + math.sin(az) * dist)
        return CFrame.lookAt(pos, c)
    end

    local function applyVis(head, eyes, vis)
        head.Transparency = 1 - vis
        for _, e in ipairs(eyes) do
            e.part.Transparency = 1 - vis
            e.light.Brightness = e.base * vis
            e.light.Enabled = vis > 0.02
        end
    end

    local session -- { alive, present, vis, current, model, head, eyes, heartbeat }

    local function teardown()
        if not session then
            return
        end
        session.alive = false
        if session.heartbeat then
            session.heartbeat:Disconnect()
        end
        if session.model then
            session.model:Destroy()
        end
        session = nil
    end

    local function spawn()
        teardown()
        local s = { alive = true, present = false, vis = 0 }
        s.current = targetCFrame()

        local model = Instance.new("Model")
        model.Name = "HellHead"
        local head = template:Clone()
        local m = math.max(head.Size.X, head.Size.Y, head.Size.Z, 0.01)
        head.Size = head.Size * (scale / m)
        head.CFrame = s.current
        darken(head, faceColor, cfg.face_material)
        head.Parent = model
        model.PrimaryPart = head
        model.Parent = container

        s.eyes = seatEyes(head, cfg.eyes, model) -- raycast against the seated head
        s.model, s.head = model, head
        applyVis(head, s.eyes, 0) -- start hidden; fade in when present

        -- intermittent presence: roll to appear/vanish on an interval (first roll immediate)
        task.spawn(function()
            while s.alive do
                s.present = math.random() < (tonumber(cfg.appear_chance) or 0.4)
                task.wait(tonumber(cfg.appear_interval) or 12)
            end
        end)

        -- glide-follow + fade every frame
        local smoothing = math.clamp(tonumber(cfg.follow_smoothing) or 0.04, 0.001, 1)
        local fadeSeconds = math.max(tonumber(cfg.fade_seconds) or 1.5, 0.01)
        s.heartbeat = RunService.Heartbeat:Connect(function(dt)
            if not s.alive or not model.Parent then
                return
            end
            s.current = s.current:Lerp(targetCFrame(), smoothing)
            model:PivotTo(s.current)
            local goal = s.present and 1 or 0
            local step = dt / fadeSeconds
            if s.vis < goal then
                s.vis = math.min(goal, s.vis + step)
            elseif s.vis > goal then
                s.vis = math.max(goal, s.vis - step)
            end
            applyVis(head, s.eyes, s.vis)
        end)

        session = s
    end

    local function refresh()
        local inHell = player:GetAttribute("CurrentRealm") == "hell"
        local layer = tostring(player:GetAttribute("CurrentLayer") or "")
        local only = cfg.only_layer
        local matches = inHell and (only == nil or layer == only)
        if matches then
            if not session then
                spawn()
            end
        else
            teardown()
        end
    end

    refresh()
    player:GetAttributeChangedSignal("CurrentLayer"):Connect(refresh)
end

return RealmHellFaces
