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
    local layers = self:_layerService()
    if not layers then
        return
    end
    local force = self._portalsConfig.bypass_access ~= false
    local current = layers:GetCurrentLayer(player)
    local target = (current == destLayer) and "base" or destLayer
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
    prompt.Enabled = true

    if not prompt:GetAttribute("RealmPortalConnected") then
        prompt:SetAttribute("RealmPortalConnected", true)
        prompt.Triggered:Connect(function(player)
            self:_onTriggered(player, def.layer)
        end)
    end
    return prompt
end

function RealmPortalService:Start()
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
