--[[
    PowerService — Feature 14 (Power Selection at Level-Up).

    Owns profile.Powers (ordered list of selected power ids). At each selection
    level the player picks ONE power from their archetype's pool; selections
    accumulate + persist. Pure rules: `src/Shared/Game/PowerSelection.lua`;
    archetype gating via `ArchetypeLogic`. Respec (ArchetypeService) clears the list.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PowerSelection = require(ReplicatedStorage.Shared.Game.PowerSelection)
local ArchetypeLogic = require(ReplicatedStorage.Shared.Game.ArchetypeLogic)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local PowerService = {}
PowerService.__index = PowerService

function PowerService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._powersConfig = self._configLoader:LoadConfig("powers")
    self._archetypesConfig = self._configLoader:LoadConfig("archetypes")
    self._cooldowns = setmetatable({}, { __mode = "k" }) -- player -> { powerId -> expiry (os.time) }
end

local function enemiesAlive()
    local game = Workspace:FindFirstChild("Game")
    local folder = game and game:FindFirstChild("Enemies")
    local out = {}
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") and (m:GetAttribute("HP") or 0) > 0 then
                out[#out + 1] = m
            end
        end
    end
    return out
end

-- Apply a cast power's SUPPORT effect (no direct damage — see configs/powers.lua).
function PowerService:_applyEffect(player, kind, now)
    local family = kind.family
    local mag = kind.magnitude or 0
    local dur = kind.duration or 0
    if family == "heal" then
        local pets = Workspace:FindFirstChild("PlayerPets")
            and Workspace.PlayerPets:FindFirstChild(player.Name)
        if pets then
            for _, pet in ipairs(pets:GetChildren()) do
                if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
                    local taken = pet:GetAttribute("CombatDamageTaken") or 0
                    pet:SetAttribute("CombatDamageTaken", math.max(0, taken - mag))
                end
            end
        end
    elseif family == "buff" then
        player:SetAttribute("PetDamageBuff", mag)
        player:SetAttribute("PetDamageBuffUntil", now + dur)
    elseif family == "root" then
        for _, enemy in ipairs(enemiesAlive()) do
            enemy:SetAttribute("RootedUntil", now + dur)
        end
    elseif family == "vulnerable" then
        for _, enemy in ipairs(enemiesAlive()) do
            enemy:SetAttribute("VulnerableMult", mag)
            enemy:SetAttribute("VulnerableUntil", now + dur)
        end
    end
end

-- Cast a power: enforce its cooldown, apply the support effect, tell the client when
-- it recharges (for the hotbar edge-clock). `powerId` matches configs/powers.lua.
function PowerService:Cast(player, powerId)
    local def = self._powersConfig.powers and self._powersConfig.powers[tostring(powerId)]
    if not def then
        return { ok = false, reason = "unknown_power" }
    end
    local now = os.time()
    local cds = self._cooldowns[player]
    if not cds then
        cds = {}
        self._cooldowns[player] = cds
    end
    if cds[powerId] and now < cds[powerId] then
        return { ok = false, reason = "on_cooldown", remaining = cds[powerId] - now }
    end

    local kind = (self._powersConfig.effect_kinds and self._powersConfig.effect_kinds[def.effect])
        or { family = "heal", magnitude = 0, duration = 0 }
    self:_applyEffect(player, kind, now)

    local cd = tonumber(def.cooldown_seconds) or 0
    cds[powerId] = now + cd
    Signals.Power_Cooldown:FireClient(
        player,
        { power = powerId, untilTime = now + cd, cooldown = cd }
    )
    if self._logger then
        self._logger:Info(
            "Power cast",
            { power = powerId, effect = def.effect, family = kind.family }
        )
    end
    return { ok = true, power = powerId, cooldown = cd }
end

function PowerService:_level(player, override)
    if override then
        return math.max(1, math.floor(override))
    end
    local locator = _G.RBXTemplateServices
    local ok, progression = pcall(function()
        return locator and locator:Get("PlayerProgressionService")
    end)
    if ok and progression and progression.GetLevel then
        return progression:GetLevel(player)
    end
    return 1
end

local function powersList(data)
    if type(data.Powers) ~= "table" then
        data.Powers = {}
    end
    return data.Powers
end

function PowerService:GetState(player, levelOverride)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    local selected = powersList(data)
    local level = self:_level(player, levelOverride)
    local levels = self._powersConfig.selection_levels
    local available = ArchetypeLogic.availablePowers(data.Archetype, self._archetypesConfig)
    return {
        ok = true,
        powers = selected,
        pending = PowerSelection.pendingSelections(level, #selected, levels),
        available = available,
    }
end

function PowerService:Select(player, powerId, levelOverride)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    if not data.Archetype then
        return { ok = false, reason = "no_archetype" }
    end
    local selected = powersList(data)
    local level = self:_level(player, levelOverride)
    local available = ArchetypeLogic.availablePowers(data.Archetype, self._archetypesConfig)
    local decision = PowerSelection.canSelect(
        powerId,
        available,
        selected,
        level,
        self._powersConfig.selection_levels
    )
    if not decision.ok then
        return { ok = false, reason = decision.reason }
    end
    table.insert(selected, powerId)
    self._dataService:RequestSave(player, "power_select", { critical = true })
    return { ok = true, powers = selected }
end

return PowerService
