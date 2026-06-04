--[[
    AscensionAltarService — the "trainer" you visit to claim TRAINING level-ups.

    Hybrid level-up (City-of-Heroes style): filler levels auto-claim in the field, but power /
    slot / milestone levels stall until you walk to the Ascension Altar and trigger its
    ProximityPrompt. Triggering it calls PlayerProgressionService:ClaimLevel (server-side, and
    the prompt itself is distance-validated by Roblox), which fires the reveal modal.

    The altar is a world part tagged "AscensionAltar". If the map already has a tagged part we
    bind to it; otherwise we spawn a placeholder glowing pillar at configs/level_track.lua
    `altar.position` (reskin later — the logic keys off the TAG, not the visual). Mirrors the
    ProximityPrompt setup in EnchantService:_ensureStationPrompt.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ALTAR_TAG = "AscensionAltar"
local PROMPT_NAME = "AscendPrompt"

local AscensionAltarService = {}
AscensionAltarService.__index = AscensionAltarService

function AscensionAltarService.new()
    local self = setmetatable({}, AscensionAltarService)
    self._logger = nil
    self._configLoader = nil
    self._altarConfig = nil
    return self
end

function AscensionAltarService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    local okTrack, track = pcall(function()
        return self._configLoader:LoadConfig("level_track")
    end)
    self._altarConfig = (okTrack and type(track) == "table" and track.altar) or {}
end

function AscensionAltarService:_progression()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, svc = pcall(function()
        return locator:Get("PlayerProgressionService")
    end)
    return ok and svc or nil
end

local function vec(t, fallback)
    if type(t) == "table" and t[1] then
        return Vector3.new(t[1], t[2] or 0, t[3] or 0)
    end
    return fallback
end

local function color(t, fallback)
    if type(t) == "table" and t[1] then
        return Color3.fromRGB(t[1], t[2] or 0, t[3] or 0)
    end
    return fallback
end

-- Find an existing tagged altar part, or spawn a placeholder pillar at the config position.
function AscensionAltarService:_ensureAltarPart()
    local tagged = CollectionService:GetTagged(ALTAR_TAG)
    for _, inst in ipairs(tagged) do
        if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
            return inst
        end
        -- a tagged Model: use its PrimaryPart or first BasePart
        if inst:IsA("Model") then
            local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
            if part then
                return part
            end
        end
    end

    -- No tagged altar in the map — spawn a placeholder pillar (reskin later).
    local cfg = self._altarConfig or {}
    local part = Instance.new("Part")
    part.Name = "AscensionAltar"
    part.Anchored = true
    part.CanCollide = true
    part.Size = vec(cfg.size, Vector3.new(6, 12, 6))
    part.Position = vec(cfg.position, Vector3.new(0, 6, 0))
    part.Material = Enum.Material.Neon
    part.Color = color(cfg.color, Color3.fromRGB(255, 205, 70))
    part.Transparency = 0.1
    CollectionService:AddTag(part, ALTAR_TAG)
    part.Parent = Workspace
    return part
end

function AscensionAltarService:_ensurePrompt(part)
    local cfg = self._altarConfig or {}
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
    local keyName = cfg.key or "E"
    prompt.KeyboardKeyCode = Enum.KeyCode[keyName] or Enum.KeyCode.E
    prompt.ActionText = cfg.action_text or "Ascend"
    prompt.ObjectText = cfg.object_text or "Ascension Altar"
    prompt.MaxActivationDistance = tonumber(cfg.max_distance) or 14
    prompt.HoldDuration = tonumber(cfg.hold_duration) or 0
    prompt.Enabled = true

    if not prompt:GetAttribute("AscendPromptConnected") then
        prompt:SetAttribute("AscendPromptConnected", true)
        prompt.Triggered:Connect(function(player)
            self:_onTriggered(player)
        end)
    end
    return prompt
end

-- Claim the next TRAINING level for the player (the prompt is already distance-validated).
function AscensionAltarService:_onTriggered(player)
    local prog = self:_progression()
    if not prog or not prog.GetClaimState then
        return
    end
    local state = prog:GetClaimState(player)
    if (state.pendingTraining or 0) <= 0 then
        return -- nothing owed at the altar (filler auto-claims in the field)
    end
    -- Compare-and-increment guards the claim; ClaimLevel fires the reveal modal + rolls any
    -- following filler via _advanceAuto.
    prog:ClaimLevel(player, state.claimedLevel)
end

function AscensionAltarService:Start()
    if self._altarConfig and self._altarConfig.enabled == false then
        return
    end
    local ok, err = pcall(function()
        local part = self:_ensureAltarPart()
        if part then
            self:_ensurePrompt(part)
        end
    end)
    if not ok and self._logger then
        self._logger:Warn("AscensionAltarService failed to place altar", { error = tostring(err) })
    elseif self._logger then
        self._logger:Info("AscensionAltarService active (Ascension Altar placed)")
    end
end

return AscensionAltarService
