--[[
    RealmPortalService — in-world entry to the heaven/hell realms (World S3, test slice).

    Binds a ProximityPrompt to named workspace parts (configs/layers.lua `realm_portals`, e.g.
    Portal_Halo1 -> heaven_1, Portal_Horn1 -> hell_1). Triggering TOGGLES the player between base
    and that realm via LayerService:UseLayer. `bypass_access` (config) forces the entry so the
    realm is reachable for testing before the soul/level/token economy is grindable.

    This reuses the SAME map — the RealmAtmosphere client skin retints the world (heaven = gold,
    hell = ember) on the published CurrentRealm attribute. Not the production realm-geometry path
    (task #157); a convenient solo-test entry. Mirrors AscensionAltarService's prompt setup.
]]

local Workspace = game:GetService("Workspace")

local PROMPT_NAME = "RealmPortalPrompt"

local RealmPortalService = {}
RealmPortalService.__index = RealmPortalService

function RealmPortalService.new()
    local self = setmetatable({}, RealmPortalService)
    self._logger = nil
    self._configLoader = nil
    self._portalsConfig = nil
    return self
end

function RealmPortalService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    local ok, layers = pcall(function()
        return self._configLoader:LoadConfig("layers")
    end)
    self._layersConfig = (ok and type(layers) == "table") and layers or {}
    self._portalsConfig = self._layersConfig.realm_portals or {}
end

function RealmPortalService:_layerService()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, svc = pcall(function()
        return locator:Get("LayerService")
    end)
    return ok and svc or nil
end

function RealmPortalService:_adminService()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, svc = pcall(function()
        return locator:Get("AdminService")
    end)
    return ok and svc or nil
end

function RealmPortalService:_isAdmin(player)
    local admin = self:_adminService()
    return (admin and admin:IsAuthorized(player)) and true or false
end

-- The Maps/<World> folder name for a layer id: "heaven_1" -> "Heaven_1", "base" -> "Home".
local function layerFolderName(layerId)
    if layerId == "base" then
        return "Home"
    end
    local realm, n = tostring(layerId):match("^(%a+)_(%d+)$")
    if realm then
        return realm:sub(1, 1):upper() .. realm:sub(2) .. "_" .. n
    end
    return layerId
end

-- A layer is enterable only if its geometry exists, else the player falls into the void. The
-- stacked worlds are authored incrementally, so most layers have no folder yet.
function RealmPortalService:_layerHasGeometry(layerId)
    local maps = Workspace:FindFirstChild("Maps")
    return (maps and maps:FindFirstChild(layerFolderName(layerId))) and true or false
end

-- Resolve a named workspace instance to a BasePart to host the prompt (Model -> primary/first part).
local function resolvePart(inst)
    if not inst then
        return nil
    end
    if inst:IsA("BasePart") then
        return inst
    end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

-- Direct jump: enter this portal's exact layer; if already standing on it, return to base.
-- (Per-layer toggle lets you hop base -> Halo3 -> Halo5 to test any depth, and step out anywhere.)
function RealmPortalService:_onTriggered(player, destLayer)
    if self._portalsConfig.locked == true then
        -- admin_unlock: admins may pass the lock to TEST realms; everyone else stays blocked.
        if not (self._portalsConfig.admin_unlock == true and self:_isAdmin(player)) then
            return
        end
    end
    local layers = self:_layerService()
    if not layers then
        return
    end
    local current = layers:GetCurrentLayer(player)
    local target = (current == destLayer) and "base" or destLayer
    -- Never teleport INTO a layer whose geometry isn't built yet (a void fall). base is always safe.
    if target ~= "base" and not self:_layerHasGeometry(target) then
        if self._logger then
            self._logger:Info("Realm portal blocked: layer has no geometry", { layer = target })
        end
        return
    end
    local force = self._portalsConfig.bypass_access ~= false
    layers:UseLayer(player, target, { force = force })
end

function RealmPortalService:_ensurePrompt(part, def)
    local prompt = part:FindFirstChild(PROMPT_NAME)
    if prompt and not prompt:IsA("ProximityPrompt") then
        return
    end
    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.Name = PROMPT_NAME
        prompt.RequiresLineOfSight = false
        prompt.Parent = part
    end
    prompt.ActionText = def.action or "Enter Realm"
    prompt.ObjectText = "Realm Portal"
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.HoldDuration = tonumber(self._portalsConfig.prompt_hold) or 0
    prompt.MaxActivationDistance = tonumber(self._portalsConfig.max_distance) or 14
    -- LOCKED gates (no realm content yet): the prompt is dead and the portal wears a big lock badge.
    -- admin_unlock re-enables the prompt so ADMINS can test (the lock badge stays for everyone, and
    -- _onTriggered still gates the action to admins). Config flip re-opens everything for real.
    prompt.Enabled = (self._portalsConfig.locked ~= true)
        or (self._portalsConfig.admin_unlock == true)
    self:_ensureLockBadge(part)

    if not prompt:GetAttribute("RealmPortalConnected") then
        prompt:SetAttribute("RealmPortalConnected", true)
        prompt.Triggered:Connect(function(player)
            self:_onTriggered(player, def.layer)
        end)
    end
    return prompt
end

-- A big lock ON THE PORTAL FACE of a locked gate (programmatic — no 3D asset).
-- SurfaceGuis (front + back), not a billboard: the gates stand back-to-back in
-- Halo/Horn pairs 3 studs apart, and an AlwaysOnTop billboard showed the FAR
-- gate's lock bleeding through the near one (Jason: "two sides to the gate so you
-- get to see both locks"). Surface rendering occludes naturally — one lock per
-- viewing side. Removed when the config unlocks.
function RealmPortalService:_ensureLockBadge(part)
    -- the prompt part is often a FOOT or frame chunk of the portal Model — the lock
    -- belongs on the big glowing face. Pick the model's largest part, and the two
    -- faces perpendicular to its thinnest axis (the flat plane of the oval).
    local host = part
    local model = part:FindFirstAncestorOfClass("Model")
    if model then
        local bestArea = 0
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                local sz = d.Size
                local area = math.max(sz.X * sz.Y, sz.X * sz.Z, sz.Y * sz.Z)
                if area > bestArea then
                    bestArea = area
                    host = d
                end
            end
        end
    end
    local sz = host.Size
    local faceA, faceB
    if sz.Z <= sz.X and sz.Z <= sz.Y then
        faceA, faceB = Enum.NormalId.Front, Enum.NormalId.Back
    elseif sz.X <= sz.Y and sz.X <= sz.Z then
        faceA, faceB = Enum.NormalId.Left, Enum.NormalId.Right
    else
        faceA, faceB = Enum.NormalId.Top, Enum.NormalId.Bottom
    end
    local names = { "RealmLockBadgeFront", "RealmLockBadgeBack", "RealmLockBadge" }
    if self._portalsConfig.locked ~= true then
        for _, holder in ipairs({ part, host }) do
            for _, n in ipairs(names) do
                local g = holder:FindFirstChild(n)
                if g then
                    g:Destroy()
                end
            end
        end
        return
    end
    local function makeFace(face, name)
        if host:FindFirstChild(name) then
            return
        end
        local gui = Instance.new("SurfaceGui")
        gui.Name = name
        gui.Face = face
        gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
        gui.PixelsPerStud = 24
        gui.LightInfluence = 0
        gui.Parent = host
        local lock = Instance.new("TextLabel")
        lock.Size = UDim2.fromScale(0.62, 0.62)
        lock.AnchorPoint = Vector2.new(0.5, 0.5)
        lock.Position = UDim2.fromScale(0.5, 0.45)
        lock.BackgroundTransparency = 1
        lock.Text = "🔒"
        lock.TextScaled = true
        lock.Font = Enum.Font.GothamBlack
        lock.TextColor3 = Color3.fromRGB(255, 255, 255)
        lock.TextStrokeTransparency = 0.2
        lock.Parent = gui
        local caption = Instance.new("TextLabel")
        -- narrow + high enough to fit INSIDE the visible oval (the glow plane runs
        -- behind the dark frame, which cropped a 0.9-wide caption to "OMING SOO")
        caption.Size = UDim2.fromScale(0.52, 0.1)
        caption.AnchorPoint = Vector2.new(0.5, 0)
        caption.Position = UDim2.fromScale(0.5, 0.66)
        caption.BackgroundTransparency = 1
        caption.Text = "COMING SOON"
        caption.TextScaled = true
        caption.Font = Enum.Font.GothamBlack
        caption.TextColor3 = Color3.fromRGB(255, 215, 0)
        caption.TextStrokeTransparency = 0.1
        caption.Parent = gui
    end
    makeFace(faceA, "RealmLockBadgeFront")
    makeFace(faceB, "RealmLockBadgeBack")
end

-- World S3: LoadAsset the Hell-face model once into ReplicatedStorage.RealmModels so the client
-- RealmHellFaces system can clone it (runtime-created, so rojo never prunes it; works on published
-- servers too). No-op if disabled / already loaded / load fails.
function RealmPortalService:_preloadHellFace()
    local cfg = self._layersConfig.hell_faces
    if not cfg or cfg.enabled == false or not cfg.model_asset_id then
        return
    end
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local folder = ReplicatedStorage:FindFirstChild("RealmModels")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "RealmModels"
        folder.Parent = ReplicatedStorage
    end
    local name = cfg.template_name or "HellFace"
    if folder:FindFirstChild(name) then
        return
    end
    local InsertService = game:GetService("InsertService")

    local AssetFetch = require(ReplicatedStorage.Shared.Utils.AssetFetch)
    local ok, container = pcall(function()
        return AssetFetch.load(cfg.model_asset_id)
    end)
    if not ok or not container then
        if self._logger then
            self._logger:Warn("RealmHellFaces: LoadAsset failed", { error = tostring(container) })
        end
        return
    end
    local model = container:GetChildren()[1]
    if model then
        model.Name = name
        -- Anchor the model AND every descendant. NB: when the asset is a single MeshPart,
        -- GetDescendants() does NOT include the part itself — so we must anchor `model` directly,
        -- or the cached template ships unanchored and every spawned head gets physics-flung.
        local function lockPart(p)
            p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
        end
        if model:IsA("BasePart") then
            lockPart(model)
        end
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                lockPart(p)
            end
        end
        if model:IsA("Model") and not model.PrimaryPart then
            model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
        end
        model.Parent = folder
        if self._logger then
            self._logger:Info(
                "RealmHellFaces: cached model in ReplicatedStorage.RealmModels",
                { name = name }
            )
        end
    end
    container:Destroy()
end

function RealmPortalService:Start()
    self:_preloadHellFace()
    local portals = self._portalsConfig.portals or {}
    if #portals == 0 then
        return
    end
    -- Map geometry may stream in slightly after boot; retry a few times for missing parts.
    task.spawn(function()
        for attempt = 1, 10 do
            local allFound = true
            for _, def in ipairs(portals) do
                local inst = Workspace:FindFirstChild(def.part, true)
                local part = resolvePart(inst)
                if part then
                    if not part:GetAttribute("RealmPortalBound") then
                        part:SetAttribute("RealmPortalBound", true)
                        self:_ensurePrompt(part, def)
                        if self._logger then
                            self._logger:Info("RealmPortalService bound portal", {
                                part = def.part,
                                layer = def.layer,
                            })
                        end
                    end
                else
                    allFound = false
                end
            end
            if allFound then
                return
            end
            task.wait(2)
        end
        if self._logger then
            self._logger:Warn(
                "RealmPortalService: some portals never appeared",
                { expected = portals }
            )
        end
    end)
end

return RealmPortalService
