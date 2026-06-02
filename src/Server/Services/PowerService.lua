--[[
    PowerService — Feature 14 (Power Selection at Level-Up).

    Owns profile.Powers (ordered list of selected power ids). At each selection
    level the player picks ONE power from their archetype's pool; selections
    accumulate + persist. Pure rules: `src/Shared/Game/PowerSelection.lua`;
    archetype gating via `ArchetypeLogic`. Respec (ArchetypeService) clears the list.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local PowerSelection = require(ReplicatedStorage.Shared.Game.PowerSelection)
local ArchetypeLogic = require(ReplicatedStorage.Shared.Game.ArchetypeLogic)
local AmplifiedBurst = require(ReplicatedStorage.Shared.Game.AmplifiedBurst)
local PetCombat = require(ReplicatedStorage.Shared.Game.PetCombat)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

-- Placeholder cast VFX colour per effect family (swap for real art later).
local FAMILY_COLOR = {
    heal = Color3.fromRGB(90, 210, 110),
    buff = Color3.fromRGB(235, 150, 60),
    defense_buff = Color3.fromRGB(235, 200, 70),
    absorb = Color3.fromRGB(235, 200, 70),
    root = Color3.fromRGB(90, 200, 235),
    vulnerable = Color3.fromRGB(235, 90, 90),
}

-- Temporary burst around the caster so AoE powers are visible (expands + fades, ~0.7s).
local function spawnCastVisual(player, family)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end
    local fx = Instance.new("Part")
    fx.Name = "PowerCastFX"
    fx.Shape = Enum.PartType.Ball
    fx.Material = Enum.Material.Neon
    fx.Color = FAMILY_COLOR[family] or Color3.fromRGB(220, 220, 220)
    fx.Transparency = 0.45
    fx.Anchored = true
    fx.CanCollide = false
    fx.CanQuery = false
    fx.Massless = true
    fx.Size = Vector3.new(3, 3, 3)
    fx.CFrame = CFrame.new(hrp.Position)
    fx.Parent = Workspace
    TweenService:Create(
        fx,
        TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = Vector3.new(26, 26, 26), Transparency = 1 }
    ):Play()
    Debris:AddItem(fx, 0.8)
end

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

-- Is the player's squad engaged with an enemy? Gates offensive powers — see Cast. Friendly powers
-- don't call this. Primary signal: a pet is actively attacking an ENEMY (its TargetID is set and
-- TargetType == "Enemy") — literally "the pet is targeting something", robust to boss size and
-- distance. Fallback: an alive enemy within engage_radius of the squad (covers the brief window
-- after an assist target before a pet has latched on).
function PowerService:_hasEngagedEnemy(player)
    local pets = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)

    -- (a) any pet attacking an enemy
    if pets then
        for _, pet in ipairs(pets:GetChildren()) do
            if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
                local tid = pet:FindFirstChild("TargetID")
                local ttype = pet:FindFirstChild("TargetType")
                if tid and tid.Value ~= 0 and ttype and tostring(ttype.Value) == "Enemy" then
                    return true
                end
            end
        end
    end

    -- (b) fallback: an alive enemy near the squad
    local enemies = enemiesAlive()
    if #enemies == 0 then
        return false
    end
    local sx, sz, n = 0, 0, 0
    if pets then
        for _, pet in ipairs(pets:GetChildren()) do
            if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") and pet.PrimaryPart then
                sx, sz, n = sx + pet.PrimaryPart.Position.X, sz + pet.PrimaryPart.Position.Z, n + 1
            end
        end
    end
    local squadPos
    if n > 0 then
        squadPos = Vector3.new(sx / n, 0, sz / n)
    else
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return false
        end
        squadPos = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
    end
    local engageR = tonumber(self._powersConfig.engage_radius) or 60
    for _, e in ipairs(enemies) do
        local pp = e.PrimaryPart or e:FindFirstChildWhichIsA("BasePart")
        if
            pp
            and (Vector3.new(pp.Position.X, 0, pp.Position.Z) - squadPos).Magnitude <= engageR
        then
            return true
        end
    end
    return false
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
                    if taken > 0 then
                        local healed = math.min(taken, mag)
                        pet:SetAttribute("CombatDamageTaken", math.max(0, taken - mag))
                        -- Instant-effect tell: blinking heal badge on the card (3s, mirrors
                        -- combat.engagement.instant_fx_seconds) — same feedback as auto-heal.
                        pet:SetAttribute("HealFxUntil", now + 3)
                        if healed >= 1 then
                            Signals.Combat_Heal:FireClient(
                                player,
                                { target = pet, amount = math.floor(healed + 0.5) }
                            )
                        end
                    end
                end
            end
        end
    elseif family == "buff" then
        player:SetAttribute("PetDamageBuff", mag)
        player:SetAttribute("PetDamageBuffUntil", now + dur)
    elseif family == "absorb" then
        -- shield: add an absorption pool the squad soaks damage with before endurance. With a
        -- duration it ALSO times out (no permanent armor): stamp CombatShieldUntil + schedule a
        -- clear; a re-cast pushes the stamp later so an older timer won't drop a fresh shield.
        local pets = Workspace:FindFirstChild("PlayerPets")
            and Workspace.PlayerPets:FindFirstChild(player.Name)
        if pets then
            for _, pet in ipairs(pets:GetChildren()) do
                if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
                    pet:SetAttribute("CombatShield", (pet:GetAttribute("CombatShield") or 0) + mag)
                    if dur and dur > 0 then
                        pet:SetAttribute("CombatShieldUntil", now + dur)
                        task.delay(dur, function()
                            if
                                pet.Parent
                                and (pet:GetAttribute("CombatShieldUntil") or 0) <= os.time()
                            then
                                pet:SetAttribute("CombatShield", 0)
                                pet:SetAttribute("CombatShieldUntil", 0)
                            end
                        end)
                    end
                end
            end
        end
    elseif family == "defense_buff" then
        -- Bulwark: temporary +Defense (armor) on the squad = damage reduction
        local pets = Workspace:FindFirstChild("PlayerPets")
            and Workspace.PlayerPets:FindFirstChild(player.Name)
        if pets then
            for _, pet in ipairs(pets:GetChildren()) do
                if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
                    pet:SetAttribute("DefenseBuff", mag)
                    pet:SetAttribute("DefenseBuffUntil", now + dur)
                end
            end
        end
    elseif family == "root" then
        for _, enemy in ipairs(enemiesAlive()) do
            enemy:SetAttribute("RootedUntil", now + dur)
        end
    elseif family == "vulnerable" then
        for _, enemy in ipairs(enemiesAlive()) do
            enemy:SetAttribute("VulnerableMult", mag)
            enemy:SetAttribute("VulnerableUntil", now + dur)
        end
    elseif family == "amplified_burst" then
        self:_amplifiedBurst(player, kind, now)
    end
end

-- Cataclysm-style "damage" power (firewall-safe, §16.5/§17.8): a burst that lands on the squad's
-- engagement and whose size is an AMPLIFICATION of the squad's own attack power, credited to the
-- pets (HP + Contrib, exactly like a pet swing). Then a molten pool lingers as vulnerability.
function PowerService:_amplifiedBurst(player, kind, now)
    local pets = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)

    -- Squad attack total + centroid (living, non-downed pets).
    local squadAttack, sx, sz, n = 0, 0, 0, 0
    if pets then
        for _, pet in ipairs(pets:GetChildren()) do
            if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") and pet.PrimaryPart then
                local p = pet.PrimaryPart.Position
                sx, sz, n = sx + p.X, sz + p.Z, n + 1
                local pw = pet:FindFirstChild("Power")
                squadAttack = squadAttack + (tonumber(pw and pw.Value) or 0)
            end
        end
    end
    local squadPos
    if n > 0 then
        squadPos = Vector3.new(sx / n, 0, sz / n)
    else
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        squadPos = (hrp and Vector3.new(hrp.Position.X, 0, hrp.Position.Z)) or Vector3.new(0, 0, 0)
    end

    -- Gather alive enemies with their flat distance to the squad.
    local engaged = {}
    for _, e in ipairs(enemiesAlive()) do
        local pp = e.PrimaryPart or e:FindFirstChildWhichIsA("BasePart")
        if pp then
            local d = (Vector3.new(pp.Position.X, 0, pp.Position.Z) - squadPos).Magnitude
            engaged[#engaged + 1] = { model = e, pos = pp.Position, d = d }
        end
    end

    -- Engagement centre: centroid of enemies near the squad, else the nearest enemy, else the squad.
    local engageR = tonumber(kind.engage_radius) or 60
    local near = {}
    for _, it in ipairs(engaged) do
        if it.d <= engageR then
            near[#near + 1] = it
        end
    end
    local center
    if #near > 0 then
        local cx, cy, cz = 0, 0, 0
        for _, it in ipairs(near) do
            cx, cy, cz = cx + it.pos.X, cy + it.pos.Y, cz + it.pos.Z
        end
        center = Vector3.new(cx / #near, cy / #near, cz / #near)
    elseif #engaged > 0 then
        table.sort(engaged, function(a, b)
            return a.d < b.d
        end)
        center = engaged[1].pos
    else
        center = Vector3.new(squadPos.X, 3, squadPos.Z) -- no enemies: visual only
    end

    -- Apply the pet-scaled burst to enemies in radius (HP + Contrib), then drop the molten pool.
    local radius = tonumber(kind.radius) or 14
    local hits = {}
    for _, it in ipairs(engaged) do
        local dist = (it.pos - center).Magnitude
        if dist <= radius then
            local dmg =
                AmplifiedBurst.atDistance(squadAttack, kind.magnitude, dist, radius, kind.falloff)
            if dmg > 0 then
                local hp = it.model:GetAttribute("HP") or 0
                local applied = PetCombat.applyDamage(hp, dmg)
                it.model:SetAttribute("HP", applied.hp)
                local contrib = it.model:FindFirstChild("Contrib")
                if contrib then
                    local key = tostring(player.UserId)
                    local nv = contrib:FindFirstChild(key)
                    if not nv then
                        nv = Instance.new("NumberValue")
                        nv.Name = key
                        nv.Parent = contrib
                    end
                    nv.Value += applied.contributed
                end
                -- molten pool: lingering vulnerability so pets keep shredding the survivors
                it.model:SetAttribute("VulnerableMult", tonumber(kind.pit_vulnerable) or 1.5)
                it.model:SetAttribute("VulnerableUntil", now + (tonumber(kind.pit_duration) or 4))
                hits[#hits + 1] = { pos = it.pos, amount = applied.contributed }
            end
        end
    end

    Signals.Power_AreaFx:FireClient(player, {
        element = "lava",
        variant = "targeted",
        center = center,
        radius = radius,
        pit = true,
        hits = hits,
    })
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

    -- Target gate: an offensive power reaches the enemy THROUGH the pets, so it can't fire unless
    -- the squad is engaged with one (the pet is fighting something). Friendly powers (heal/buff/
    -- shield) target your own pets and skip the gate. Refused casts don't spend the cooldown.
    local enemyTargeted = self._powersConfig.enemy_targeted_families
        and self._powersConfig.enemy_targeted_families[kind.family]
    if enemyTargeted and not self:_hasEngagedEnemy(player) then
        return { ok = false, reason = "no_target" }
    end

    self:_applyEffect(player, kind, now)
    if kind.family ~= "amplified_burst" then
        pcall(spawnCastVisual, player, kind.family) -- placeholder caster burst (area powers show at the target)
    end

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
