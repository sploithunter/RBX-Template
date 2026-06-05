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
local function seatEyes(head, eyesCfg)
    local eyes = {}
    if type(eyesCfg) ~= "table" or eyesCfg.enabled == false then
        return eyes
    end
    local up = tonumber(eyesCfg.up) or 30
    local side = tonumber(eyesCfg.side) or 35
    local recess = tonumber(eyesCfg.recess) or 18
    local lightColor = c255(eyesCfg.light_color, Color3.fromRGB(255, 40, 18))
    local lightBrightness = tonumber(eyesCfg.light_brightness) or 22
    local lightRange = tonumber(eyesCfg.light_range) or 60

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

        -- LIGHT in the socket (no solid orb): an Attachment pinned to the head at the socket, with
        -- a PointLight, so the eye glows from within and rides with the head automatically.
        local att = Instance.new("Attachment")
        att.Name = sign > 0 and "EyeL" or "EyeR"
        att.WorldPosition = epos
        att.Parent = head
        local light = Instance.new("PointLight")
        light.Color = lightColor
        light.Brightness = lightBrightness
        light.Range = lightRange
        light.Shadows = true
        light.Parent = att
        eyes[#eyes + 1] = { light = light, base = lightBrightness }
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

    -- Movement tuning (mirrors pet_follow.movement: frame-rate-independent exp approach + a hard
    -- speed cap + a catchup snap). KITES: holds a `dist`-radius ring along its current bearing, so
    -- closing in on it pushes it away (it never lets you walk up to it), and it gently turns to keep
    -- facing you. The speed cap means it can never accelerate without bound regardless.
    local lerpRate = math.max(tonumber(cfg.follow_lerp_rate) or 4, 0.1)
    local maxSpeed = math.max(tonumber(cfg.max_travel_speed) or 120, 1)
    local catchup = math.max(tonumber(cfg.catchup_distance) or 400, 1)
    local turnRate = math.max(tonumber(cfg.face_turn_rate) or 2, 0.1)
    local az = math.rad(tonumber(cfg.follow_azimuth_deg) or 0)
    local dist = tonumber(cfg.follow_distance) or 100
    local heightOff = tonumber(cfg.follow_height) or 100
    local bearingSeed = Vector3.new(math.cos(az), 0, math.sin(az)) -- until it has a real bearing

    local function playerPos()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        return (hrp and hrp.Position) or Vector3.new(0, 0, 0)
    end

    -- kite target: hold `dist` horizontally along the head's CURRENT bearing, `heightOff` up
    local function targetPos(from)
        local c = playerPos()
        local horiz = Vector3.new(from.X - c.X, 0, from.Z - c.Z)
        local bearing = horiz.Magnitude > 1 and horiz.Unit or bearingSeed
        return Vector3.new(c.X + bearing.X * dist, c.Y + heightOff, c.Z + bearing.Z * dist)
    end

    local function applyVis(head, eyes, vis)
        head.Transparency = 1 - vis
        for _, e in ipairs(eyes) do
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
        -- Defensive: wipe ANY stale heads in the container (e.g. an old contaminated head that got
        -- saved into the place, or a leftover from a prior session) so we always run exactly one,
        -- clean, anchored head.
        container:ClearAllChildren()
        local s = { alive = true, present = false, vis = 0 }
        s.pos = Vector3.new(
            playerPos().X + bearingSeed.X * dist,
            playerPos().Y + heightOff,
            playerPos().Z + bearingSeed.Z * dist
        )
        s.current = CFrame.lookAt(s.pos, playerPos())

        local model = Instance.new("Model")
        model.Name = "HellHead"
        local head = template:Clone()
        -- CRITICAL: anchor the head. The template MeshPart ships unanchored (the preload's
        -- GetDescendants() loop never touches the part itself), so without this the head is
        -- physics-simulated and fights the per-frame PivotTo — jittering wildly and flinging any
        -- child parts thousands of studs. Anchored = PivotTo is the sole authority = rock steady.
        head.Anchored = true
        head.CanCollide = false
        head.CanQuery = false
        head.Massless = true
        local m = math.max(head.Size.X, head.Size.Y, head.Size.Z, 0.01)
        head.Size = head.Size * (scale / m)
        head.CFrame = s.current
        darken(head, faceColor, cfg.face_material)
        head.Parent = model
        model.PrimaryPart = head
        model.Parent = container

        s.eyes = seatEyes(head, cfg.eyes) -- socket lights pinned to the seated head
        s.model, s.head = model, head
        applyVis(head, s.eyes, 0) -- start hidden; fade in when present

        -- intermittent presence: roll to appear/vanish on an interval (first roll immediate)
        task.spawn(function()
            while s.alive do
                s.present = math.random() < (tonumber(cfg.appear_chance) or 0.4)
                task.wait(tonumber(cfg.appear_interval) or 12)
            end
        end)

        -- glide-follow (capped exp approach, no spin) + fade every frame
        local fadeSeconds = math.max(tonumber(cfg.fade_seconds) or 1.5, 0.01)
        s.heartbeat = RunService.Heartbeat:Connect(function(dt)
            if not s.alive or not model.Parent then
                return
            end
            -- frame-rate-independent exponential approach toward the kite target, HARD-capped at
            -- maxSpeed so it can never accelerate without bound; snap on a real teleport.
            local tp = targetPos(s.pos)
            local delta = tp - s.pos
            local d = delta.Magnitude
            if d > catchup then
                s.pos = tp
            elseif d > 1e-3 then
                local alpha = 1 - math.exp(-lerpRate * dt)
                local moveDist = math.min(d * alpha, maxSpeed * dt)
                s.pos = s.pos + delta.Unit * moveDist
            end
            -- gently turn to keep facing the player (slow slerp -> tracks you, never whips/spins)
            local desired = CFrame.lookAt(s.pos, playerPos())
            local rot = s.current.Rotation:Lerp(desired.Rotation, 1 - math.exp(-turnRate * dt))
            s.current = CFrame.new(s.pos) * rot
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
    -- Listen to BOTH attributes: LayerService may publish CurrentLayer and CurrentRealm in either
    -- order, so a CurrentLayer-only listener can fire while CurrentRealm is briefly stale and skip
    -- the spawn. Watching both makes the Hell-5 gate fire regardless of publish order.
    player:GetAttributeChangedSignal("CurrentLayer"):Connect(refresh)
    player:GetAttributeChangedSignal("CurrentRealm"):Connect(refresh)
end

return RealmHellFaces
