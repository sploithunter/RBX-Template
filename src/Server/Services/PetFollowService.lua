--[[
    PetFollowService — server authority for the pet work loop (issue #4 retry).

    Responsibilities (SERVER ONLY):
      - Make pets non-falling: ANCHOR each pet's parts. Anchored parts obey no
        gravity/physics, so a pet can never drift or fall off the map (the bug the
        legacy teleport-watchdog existed to patch). The client positions them
        kinematically via PivotTo (see PetFollowController).
      - Mining damage tick: read each pet's TargetID, apply damage to the breakable
        via CombatService:ResolvePetDamage + PetCombat (Contrib ledger).
      - Target leash: clear TargetID when the player walks beyond leash_distance so
        the pet returns to following (BreakableService re-assigns when near).

    Movement/visualisation is CLIENT-side (src/Client/Systems/PetFollowController.lua),
    which sets each pet's CFrame every RenderStepped for smooth, never-falling
    motion. Damage stays server-authoritative. Multiplayer position replication
    (other clients seeing a player's pets move) is a documented follow-up.

    Gated on configs/pet_follow.lua `service_owned`.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PetCombat = require(ReplicatedStorage.Shared.Game.PetCombat)
local PetFormation = require(ReplicatedStorage.Shared.Game.PetFormation)
local CombatMath = require(ReplicatedStorage.Shared.Game.CombatMath)
local CombatRoll = require(ReplicatedStorage.Shared.Game.CombatRoll)
local LevelScale = require(ReplicatedStorage.Shared.Game.LevelScale)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local PetFollowService = {}
PetFollowService.__index = PetFollowService

function PetFollowService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._config = self._configLoader:LoadConfig("pet_follow")
    self._combatConfig = self._configLoader:LoadConfig("combat")
    self._petRoles = self._configLoader:LoadConfig("pet_roles")
    self._levelingConfig = self._configLoader:LoadConfig("leveling")
    self._nextHit = {} -- pet model -> os.clock() of next allowed mining hit
    self._petPos = setmetatable({}, { __mode = "k" }) -- pet model -> { pos, t } (weak: dead pets GC)

    -- Owning client reports its pet positions; we use them to gate mining on distance to target.
    Signals.PetReportPositions.OnServerEvent:Connect(function(player, report)
        self:_onPetPositions(player, report)
    end)

    -- Preload any model-based ranged FX (rock throw, future cactus) so the client can use them
    -- (InsertService is server-only). Sanitized templates land in ReplicatedStorage.RangedFXAssets.
    self:_preloadFxAssets()
end

-- Load model_asset ids referenced by ranged_bolt (rock + projectile themes) and stash a
-- sanitized single-part template per id in ReplicatedStorage.RangedFXAssets[tostring(id)],
-- which replicates to clients for RangedFX to clone. Failures are logged + skipped (the
-- client falls back to a procedural block).
function PetFollowService:_preloadFxAssets()
    local bolt = (self._config and self._config.ranged_bolt) or {}
    local ids = {}
    if bolt.rock and bolt.rock.model_asset then
        ids[bolt.rock.model_asset] = true
    end
    if type(bolt.projectile) == "table" then
        for _, theme in pairs(bolt.projectile) do
            if type(theme) == "table" and theme.model_asset then
                ids[theme.model_asset] = true
            end
        end
    end
    if next(ids) == nil then
        return
    end
    local folder = ReplicatedStorage:FindFirstChild("RangedFXAssets")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "RangedFXAssets"
        folder.Parent = ReplicatedStorage
    end
    local InsertService = game:GetService("InsertService")
    for id in pairs(ids) do
        local name = tostring(id)
        if not folder:FindFirstChild(name) then
            task.spawn(function()
                local ok, container = pcall(function()
                    return InsertService:LoadAsset(id)
                end)
                if ok and container then
                    local part = container:FindFirstChildWhichIsA("BasePart", true)
                    if part then
                        part = part:Clone()
                        part.Anchored = true
                        part.CanCollide = false
                        part.CanQuery = false
                        part.CastShadow = false
                        part.Name = name
                        part.Parent = folder
                    elseif self._logger then
                        self._logger:Warn("RangedFX asset has no BasePart", { asset = id })
                    end
                    container:Destroy()
                elseif self._logger then
                    self._logger:Warn("RangedFX asset load failed", { asset = id })
                end
            end)
        end
    end
end

-- Store reported positions for the player's OWN pets only (ignore anything else — anti-grief).
function PetFollowService:_onPetPositions(player, report)
    if type(report) ~= "table" then
        return
    end
    local folder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not folder then
        return
    end
    local now = os.clock()
    local valid = {}
    for _, entry in ipairs(report) do
        local pet = type(entry) == "table" and entry.pet
        local cf = type(entry) == "table" and entry.cf
        if typeof(pet) == "Instance" and pet:IsDescendantOf(folder) and typeof(cf) == "CFrame" then
            self._petPos[pet] = { cf = cf, t = now } -- for the mining gate
            valid[#valid + 1] = entry
        end
    end

    -- Relay to OTHER clients only — they render this player's pets from the server. The owning
    -- client positions its OWN pets locally and is never sent / never applies the server copy,
    -- so its own view stays smooth (no PivotTo here = no stale server transform fighting it).
    if #valid > 0 then
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= player then
                Signals.PetPositionsRelay:FireClient(other, valid)
            end
        end
    end
end

-- The latest client-reported CFrame for a pet (or nil if none/stale-cleaned).
-- EnemyService uses this to measure enemy->pet distance (anchored pets are moved
-- client-side, so the server's own pivot is stale).
function PetFollowService:GetReportedPosition(pet)
    local rec = self._petPos[pet]
    return rec and rec.cf or nil
end

function PetFollowService:_combatService()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get("CombatService")
    end)
    return ok and service or nil
end

function PetFollowService:_enemyService()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get("EnemyService")
    end)
    return ok and service or nil
end

function PetFollowService:Start()
    if not self._config.service_owned then
        if self._logger then
            self._logger:Info("PetFollowService inert (pet_follow.service_owned=false)")
        end
        return
    end
    _G.PetFollowServiceOwned = true -- legacy cloned scripts stand down
    if self._logger then
        self._logger:Info(
            "PetFollowService active — anchored pets, client-driven movement, server damage"
        )
    end
    local accum = 0
    RunService.Heartbeat:Connect(function(dt)
        accum += dt
        if accum < self._config.update_interval then
            return
        end
        accum = 0
        pcall(function()
            self:_tick()
        end)
    end)
end

-- Anchor every part so the pet can't fall/drift (the client moves it via PivotTo).
-- Strips any stale movement constraints from earlier builds. Once per pet.
function PetFollowService:_prepPet(pet)
    if pet:GetAttribute("PetFollowPrepped") then
        return
    end
    for _, name in ipairs({ "_FollowAlign", "_FollowAlignO", "align", "alignO" }) do
        local c = pet:FindFirstChild(name)
        if c then
            c:Destroy()
        end
    end
    for _, d in ipairs(pet:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
        end
    end
    pet:SetAttribute("PetFollowPrepped", true)
end

-- Locate a target Model by id. Enemies (TargetType "Enemy") live under Game.Enemies; breakables
-- under Game.Breakables/<type>/<world>. Both carry a BreakableID — the generic target id.
function PetFollowService:_findBreakable(targetType, world, id)
    local game = Workspace:FindFirstChild("Game")
    if not game then
        return nil
    end
    if targetType == "Enemy" then
        local enemies = game:FindFirstChild("Enemies")
        if not enemies then
            return nil
        end
        for _, desc in ipairs(enemies:GetDescendants()) do
            if desc.Name == "BreakableID" and desc:IsA("NumberValue") and desc.Value == id then
                return desc.Parent
            end
        end
        return nil
    end
    local breakables = game:FindFirstChild("Breakables")
    if not breakables then
        return nil
    end
    local typeFolder = breakables:FindFirstChild(targetType)
    local scope = typeFolder and (typeFolder:FindFirstChild(world) or typeFolder)
    if not scope then
        return nil
    end
    for _, desc in ipairs(scope:GetDescendants()) do
        if desc.Name == "BreakableID" and desc:IsA("NumberValue") and desc.Value == id then
            return desc.Parent
        end
    end
    return nil
end

-- A pet's role damage multiplier (archetype curve): PetRole attr -> by_type[PetType]
-- -> default; falls back to 1. Support/control hit softer, melee/ranged full.
function PetFollowService:_roleDamageMult(pet)
    local roles = self._petRoles
    if not roles then
        return 1
    end
    local id = pet:GetAttribute("PetRole")
        or (roles.by_type and roles.by_type[pet:GetAttribute("PetType")])
        or roles.default
    local def = roles.roles and roles.roles[id]
    return (def and tonumber(def.damage_mult)) or 1
end

-- A pet's effective attack range (mining-gate distance), by combat role: PetRole attr
-- -> pet_roles.by_type[PetType] -> default. Ranged pets reach much further than melee,
-- so they can deal damage from their standoff. Falls back to mining.range.
function PetFollowService:_attackRange(pet)
    local roles = self._petRoles
    local fallback = (self._config.mining and self._config.mining.range) or 9
    if not roles then
        return fallback
    end
    local id = pet:GetAttribute("PetRole")
        or (roles.by_type and roles.by_type[pet:GetAttribute("PetType")])
        or roles.default
    local def = roles.roles and roles.roles[id]
    return (def and tonumber(def.attack_range)) or fallback
end

-- One mining hit on the pet's current target (server-authoritative damage).
function PetFollowService:_mine(player, pet, breakable)
    if pet:GetAttribute("CombatDowned") then
        return -- downed pets are out healing; they neither mine nor fight
    end
    local now = os.clock()
    if self._nextHit[pet] and now < self._nextHit[pet] then
        return
    end
    local combat = self:_combatService()
    if not combat then
        return
    end
    local hp = breakable:GetAttribute("HP") or 0
    if hp <= 0 then
        return
    end

    -- Mining gate: only mine once the pet has reached the target (within mining.range), so move
    -- speed affects mining throughput (DPS ramps as pets arrive). Distance comes from the position
    -- the owning client reports; a missing/stale report falls back to "allow" so the gate can
    -- never break the legacy "near the ore = mines" behaviour.
    local rec = self._petPos[pet]
    local staleSeconds = (self._config.replication and self._config.replication.stale_seconds)
        or 0.5
    local dist
    if rec and (now - rec.t) <= staleSeconds then
        -- Enemies publish their authoritative position as a MoveTarget attribute (the
        -- server no longer pivots the model — the client owns the render CFrame for
        -- smooth motion). Breakables have no such attribute, so fall back to the pivot.
        local targetPos = breakable:GetAttribute("MoveTarget") or breakable:GetPivot().Position
        dist = (rec.cf.Position - targetPos).Magnitude
    end
    local miningRange = self:_attackRange(pet)
    if not PetFormation.inMiningRange(dist, miningRange) then
        return -- pet is reported far from the target — hasn't arrived yet
    end

    local powerNV = pet:FindFirstChild("Power")
    local ctx = {
        power = tonumber(powerNV and powerNV.Value) or 1,
        petId = pet:GetAttribute("PetType"),
        variant = pet:GetAttribute("PetVariant"),
        breakableId = breakable:GetAttribute("BreakableId"),
        currency = breakable:GetAttribute("Currency"),
    }
    local dmg = combat:ResolvePetDamage(player, ctx)
    -- Archetype damage curve: support/control hit softer, melee/ranged full.
    dmg = dmg * self:_roleDamageMult(pet)
    -- Level scaling vs ENEMIES only (crystals have no Level): out-level it -> hit harder.
    if breakable:GetAttribute("EnemyId") then
        local petLevel = pet:GetAttribute("Level") or (player:GetAttribute("Level") or 1)
        local enemyLevel = breakable:GetAttribute("Level") or petLevel
        dmg = dmg * LevelScale.factor(petLevel, enemyLevel, self._levelingConfig.scale)
    end
    -- Support-power modifiers (Feature 14): the player's active damage buff and the
    -- target's vulnerability both scale pet damage (os.time-gated, set by PowerService).
    local nowT = os.time()
    if (player:GetAttribute("PetDamageBuffUntil") or 0) > nowT then
        dmg = dmg * (player:GetAttribute("PetDamageBuff") or 1)
    end
    if (breakable:GetAttribute("VulnerableUntil") or 0) > nowT then
        dmg = dmg * (breakable:GetAttribute("VulnerableMult") or 1)
    end
    -- Defensive stat: an enemy's Armor mitigates pet damage on the armor curve
    -- (crystals have no Armor -> unchanged). Vulnerability above counteracts it.
    local armor = breakable:GetAttribute("Armor") or 0
    if armor > 0 then
        dmg = CombatMath.mitigate(dmg, armor, self._combatConfig.armor_curve_k or 100)
    end
    -- Hit / crit roll: a miss deals nothing this swing, a crit multiplies the damage.
    local roll = CombatRoll.resolve(
        self._combatConfig.engagement
            and self._combatConfig.engagement.rolls
            and self._combatConfig.engagement.rolls.pet_attack,
        math.random(),
        math.random()
    )
    dmg = dmg * roll.multiplier
    pet:SetAttribute("LastHitCrit", roll.crit) -- for floating-text feedback (later)

    dmg = math.floor(dmg + 0.5)
    local applied = PetCombat.applyDamage(hp, dmg)
    breakable:SetAttribute("HP", applied.hp)

    -- Damage builds aggro: hurting an enemy makes it want to attack this pet (the threat
    -- table the enemy targets from). Only enemies carry an EnemyId; crystals don't.
    if breakable:GetAttribute("EnemyId") and applied.contributed > 0 then
        local enemyService = self:_enemyService()
        if enemyService then
            local factor = (
                self._combatConfig.engagement
                and self._combatConfig.engagement.aggro
                and self._combatConfig.engagement.aggro.damage_factor
            ) or 1
            enemyService:AddAggro(breakable, pet, applied.contributed * factor)
        end
    end

    local contrib = breakable:FindFirstChild("Contrib")
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

    self._nextHit[pet] = now + combat:ResolvePetAttackInterval(player, ctx)

    -- Drive the attack VISUAL off the real hit: tell the owning client to play this pet's
    -- effect (bolt/projectile for ranged, impact for melee) at this exact moment + target, so
    -- the animation, impact, sound, crit AND the floating damage number are the swing that
    -- actually happened — not a parallel client timer. Owner-only (their pets are local).
    Signals.Combat_PetHit:FireClient(player, {
        pet = pet,
        target = breakable,
        crit = roll.crit,
        amount = dmg, -- floored, post-roll/mitigation damage (0 on a miss)
        miss = roll.multiplier <= 0,
    })
end

function PetFollowService:_tickPlayer(player)
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local petsFolder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not hrp or not petsFolder then
        return
    end

    for _, pet in ipairs(petsFolder:GetChildren()) do
        if pet:IsA("Model") and pet.PrimaryPart then
            self:_prepPet(pet)
            local targetId = pet:FindFirstChild("TargetID")
            if targetId and targetId.Value ~= 0 then
                local targetType = pet:FindFirstChild("TargetType")
                local targetWorld = pet:FindFirstChild("TargetWorld")
                local breakable = self:_findBreakable(
                    targetType and targetType.Value,
                    targetWorld and targetWorld.Value,
                    targetId.Value
                )
                -- Clear ONLY when the target is gone (mined out / removed), like the
                -- legacy script — never on distance. AutoTargetService owns target
                -- selection + range; a distance leash here fought it and made the
                -- pet flicker between attack and follow during auto-mining.
                if not breakable then
                    targetId.Value = 0 -- target gone -> follow until AutoTargetService reassigns
                else
                    self:_mine(player, pet, breakable)
                end
            end
        end
    end
end

function PetFollowService:_tick()
    for _, player in ipairs(Players:GetPlayers()) do
        self:_tickPlayer(player)
    end
end

return PetFollowService
