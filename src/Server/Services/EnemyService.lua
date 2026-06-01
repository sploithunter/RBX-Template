--[[
    EnemyService — live Hell-side combat enemies (Feature 10, slice 1a: offensive loop).

    Spawns enemy entities that pets target + attack exactly like breakables: each enemy is a
    Model under workspace.Game.Enemies with a `BreakableID` (the generic target id the pet
    plumbing already keys on), `HP`/`MaxHP` attributes, an `EnemyId` attribute (the archetype
    from configs/enemies.lua), and a `Contrib` ledger. Pets reduce its HP through the existing
    PetFollowService mining tick (respecting the mining-range gate + attack formations); this
    service owns the enemy LIFECYCLE — spawn, death (award loot to contributors + release the
    pets), despawn.

    Slice 1a is OFFENSIVE + stationary: pets mine the enemy down, it dies, loot is awarded.
    The inverse half (enemy mines the pets -> downed -> Spirit Form, + regen) and chase AI /
    aggro are later slices.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local PetEndurance = require(ReplicatedStorage.Shared.Game.PetEndurance)
local EnemyAI = require(ReplicatedStorage.Shared.Game.EnemyAI)
local AggroTable = require(ReplicatedStorage.Shared.Game.AggroTable)
local CombatRoll = require(ReplicatedStorage.Shared.Game.CombatRoll)
local ActiveSquad = require(ReplicatedStorage.Shared.Game.ActiveSquad)
local CombatMath = require(ReplicatedStorage.Shared.Game.CombatMath)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local EnemyService = {}
EnemyService.__index = EnemyService

function EnemyService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._enemiesConfig = self._configLoader:LoadConfig("enemies")
    self._petFollowConfig = self._configLoader:LoadConfig("pet_follow")
    self._combatConfig = self._configLoader:LoadConfig("combat")
    self._squadConfig = self._configLoader:LoadConfig("squad")
    self._petRoles = self._configLoader:LoadConfig("pet_roles")
    self._nextId = 0
    self._enemies = {} -- targetId -> { model, enemyId, nextAttack }
    -- pet model -> { lastHit } (weak so dead pets GC). Accumulated damage, the downed
    -- flag, and the slot CooldownUntil all live as replicated attributes on the pet so
    -- the squad HUD reads them directly; this table is just server-only hit timing.
    self._petCombat = setmetatable({}, { __mode = "k" })

    -- Squad management: recall a pet (short slot cooldown) / re-summon a recovered one.
    Signals.Squad_Recall.OnServerEvent:Connect(function(player, payload)
        pcall(function()
            self:RecallPet(player, payload)
        end)
    end)
    Signals.Squad_Summon.OnServerEvent:Connect(function(player, payload)
        pcall(function()
            self:SummonPet(player, payload)
        end)
    end)
end

function EnemyService:_combatService()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get("CombatService")
    end)
    return ok and service or nil
end

function EnemyService:_petFollowService()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get("PetFollowService")
    end)
    return ok and service or nil
end

function EnemyService:_enemiesFolder()
    local game = Workspace:FindFirstChild("Game")
    if not game then
        game = Instance.new("Folder")
        game.Name = "Game"
        game.Parent = Workspace
    end
    local folder = game:FindFirstChild("Enemies")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "Enemies"
        folder.Parent = game
    end
    return folder
end

-- Add aggro for an attacker (pet Model / Player) on the enemy identified by `model`.
-- Called when something hurts the enemy (PetFollowService mining) — damage builds threat.
-- No-op if `model` isn't a tracked enemy. Public so other services can feed the table.
function EnemyService:AddAggro(model, key, amount)
    local idVal = model and model:FindFirstChild("BreakableID")
    local entry = idVal and self._enemies[idVal.Value]
    if entry and entry.aggro then
        AggroTable.add(entry.aggro, key, amount)
    end
end

-- Load (once, cached) a real enemy art asset into a sanitized template: PrimaryPart
-- set, every part anchored + non-colliding (movement is PivotTo, not physics), scaled
-- to enemy size. Returns nil on any failure so spawning falls back to the procedural
-- block. Cache stores `false` for known-bad ids so we don't re-yield on every spawn.
function EnemyService:_enemyTemplate(assetId, scale, needsPrimaryPart)
    self._modelCache = self._modelCache or {}
    local cached = self._modelCache[assetId]
    if cached ~= nil then
        return cached or nil
    end

    local ok, container = pcall(function()
        return InsertService:LoadAsset(assetId)
    end)
    local template
    if ok and container then
        template = container:FindFirstChildWhichIsA("Model") or container
        if template ~= container then
            template.Parent = nil
            container:Destroy()
        end
        -- Only auto-assign a PrimaryPart when the config opts in (`needs_primary_part`).
        -- Otherwise we respect the model's own PrimaryPart and treat its absence as a
        -- load failure — so a multi-part model never silently picks the wrong part.
        if needsPrimaryPart and not template.PrimaryPart then
            template.PrimaryPart = template:FindFirstChildWhichIsA("BasePart", true)
        end
        if template.PrimaryPart then
            for _, d in ipairs(template:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Anchored = true
                    d.CanCollide = false
                end
            end
            if scale and scale ~= 1 then
                pcall(function()
                    template:ScaleTo(scale)
                end)
            end
            template.Parent = ServerStorage
        else
            template = nil
        end
    end

    self._modelCache[assetId] = template or false
    if not template and self._logger then
        self._logger:Warn(
            "Enemy model asset unusable; using procedural fallback",
            { asset = assetId }
        )
    end
    return template
end

-- Attach the combat contract every enemy needs regardless of art: the generic target
-- id the pet plumbing keys on, the contrib ledger, HP/armor attributes, and an HP bar
-- sized to sit above the model.
function EnemyService:_attachEnemyDecor(model, body, enemyId, def, targetId)
    local idValue = Instance.new("NumberValue")
    idValue.Name = "BreakableID"
    idValue.Value = targetId
    idValue.Parent = model

    local contrib = Instance.new("Folder")
    contrib.Name = "Contrib"
    contrib.Parent = model

    model:SetAttribute("EnemyId", enemyId)
    model:SetAttribute("HP", def.hp)
    model:SetAttribute("MaxHP", def.hp)
    model:SetAttribute("IsEnemy", true)
    model:SetAttribute("Armor", def.armor or 0) -- defensive stat: mitigates pet damage

    local height = 7
    local okExtents, sz = pcall(function()
        return model:GetExtentsSize()
    end)
    if okExtents and sz then
        height = sz.Y
    end

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(6, 0, 0.8, 0)
    bb.StudsOffset = Vector3.new(0, height / 2 + 1.5, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = body
    bb.Parent = body
    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bg.BorderSizePixel = 0
    bg.Parent = bb
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(1, 1)
    fill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
    fill.BorderSizePixel = 0
    fill.Parent = bg
end

-- Build the enemy model. Uses the configured `model_asset` art when present (cloned
-- from a cached template); otherwise a simple block dummy. PrimaryPart is the body so
-- pet formations surround its pivot, and movement is via PivotTo (parts are anchored).
function EnemyService:_buildModel(enemyId, def, position, targetId)
    local model, body
    if def.model_asset then
        local template =
            self:_enemyTemplate(def.model_asset, def.model_scale, def.needs_primary_part)
        if template then
            model = template:Clone()
            body = model.PrimaryPart
        end
    end

    if not model then
        model = Instance.new("Model")
        body = Instance.new("Part")
        body.Name = "Body"
        body.Shape = Enum.PartType.Block
        body.Size = Vector3.new(5, 7, 5)
        body.Color = Color3.fromRGB(180, 60, 60)
        body.Material = Enum.Material.SmoothPlastic
        body.Anchored = true -- stationary base; chase moves it via PivotTo
        body.CanCollide = false
        body.Parent = model
        model.PrimaryPart = body
    end

    model.Name = "Enemy_" .. enemyId .. "_" .. targetId
    model:PivotTo(CFrame.new(position))
    self:_attachEnemyDecor(model, body, enemyId, def, targetId)
    return model
end

-- Release any pets still targeting this enemy back to following.
function EnemyService:_releasePets(targetId)
    local playerPets = Workspace:FindFirstChild("PlayerPets")
    if not playerPets then
        return
    end
    for _, folder in ipairs(playerPets:GetChildren()) do
        for _, pet in ipairs(folder:GetChildren()) do
            local tid = pet:FindFirstChild("TargetID")
            local tt = pet:FindFirstChild("TargetType")
            if tid and tid.Value == targetId and tt and tt.Value == "Enemy" then
                tid.Value = 0
            end
        end
    end
end

function EnemyService:_onDefeated(targetId)
    local entry = self._enemies[targetId]
    if not entry then
        return
    end
    self._enemies[targetId] = nil
    local model = entry.model

    -- Award loot to every contributor (the pet damage tick records UserId -> amount in Contrib).
    local combat = self:_combatService()
    local contrib = model:FindFirstChild("Contrib")
    if combat and contrib then
        for _, nv in ipairs(contrib:GetChildren()) do
            local userId = tonumber(nv.Name)
            local player = userId and Players:GetPlayerByUserId(userId)
            if player then
                pcall(function()
                    combat:AwardLoot(player, entry.enemyId)
                end)
            end
        end
    end

    self:_releasePets(targetId)
    model:Destroy()
    if self._logger then
        self._logger:Info("Enemy defeated", { enemyId = entry.enemyId, targetId = targetId })
    end
end

-- ===== Defensive inverse mining (slice 1b): enemy attacks pets; pets attack back =====

-- A pet's combat endurance is built on its Power (no HP stat). Read the Power
-- NumberValue the pet plumbing already maintains, falling back to attributes.
function EnemyService:_petPower(pet)
    local nv = pet:FindFirstChild("Power")
    local p = (nv and tonumber(nv.Value))
        or pet:GetAttribute("EffectivePower")
        or pet:GetAttribute("BasePower")
        or 1
    if p < 1 then
        p = 1
    end
    return p
end

-- Pet position: the owning client reports it (anchored pets are client-moved, so
-- the server's own pivot is stale). Fall back to the pivot if no fresh report.
function EnemyService:_petPosition(pet, pfs)
    if pfs and pfs.GetReportedPosition then
        local cf = pfs:GetReportedPosition(pet)
        if cf then
            return cf.Position
        end
    end
    return pet:GetPivot().Position
end

-- Point a pet at this enemy (attack back). Idempotent — only writes on change.
function EnemyService:_assignPetToEnemy(pet, targetId)
    local tt = pet:FindFirstChild("TargetType")
    local tid = pet:FindFirstChild("TargetID")
    if not (tt and tid) then
        return
    end
    if tt.Value ~= "Enemy" or tid.Value ~= targetId then
        tt.Value = "Enemy"
        local tw = pet:FindFirstChild("TargetWorld")
        if tw then
            tw.Value = ""
        end
        tid.Value = targetId
    end
end

-- Lazy endurance bar over the pet (green->red as it takes damage).
function EnemyService:_updateEnduranceBar(pet, taken, power, factor)
    local pp = pet.PrimaryPart
    if not pp then
        return
    end
    local bb = pp:FindFirstChild("EnduranceBar")
    if not bb then
        bb = Instance.new("BillboardGui")
        bb.Name = "EnduranceBar"
        bb.Size = UDim2.new(4, 0, 0.5, 0)
        bb.StudsOffset = Vector3.new(0, 3.5, 0)
        bb.AlwaysOnTop = true
        local bg = Instance.new("Frame")
        bg.Name = "BG"
        bg.Size = UDim2.fromScale(1, 1)
        bg.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        bg.BorderSizePixel = 0
        bg.Parent = bb
        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.fromScale(1, 1)
        fill.BorderSizePixel = 0
        fill.Parent = bg
        bb.Parent = pp
    end
    local frac = PetEndurance.healthFraction(taken, power, factor)
    local fill = bb:FindFirstChild("BG") and bb.BG:FindFirstChild("Fill")
    if fill then
        fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
        fill.BackgroundColor3 =
            Color3.fromRGB(math.floor(215 * (1 - frac)) + 40, math.floor(195 * frac) + 30, 45)
    end
end

function EnemyService:_clearEnduranceBar(pet)
    local pp = pet.PrimaryPart
    if not pp then
        return
    end
    local bb = pp:FindFirstChild("EnduranceBar")
    if bb then
        bb:Destroy()
    end
end

-- Take a pet out of the fight. `reason` "down" (forced, long slot cooldown) or
-- "recall" (player pulled it proactively, short cooldown). The pet hides client-side
-- (PetFollowController) + drops its target; it stays out until the player SUMMONS it
-- once the slot recharges (no auto-revive — recovery is a player action). The slot's
-- recharge end is stamped on the pet as CooldownUntil (os.time) so the HUD counts down.
function EnemyService:_downPet(pet, _now, _eng, reason)
    pet:SetAttribute("CombatDowned", true)
    pet:SetAttribute("DownedReason", reason or "down")
    local cd = ActiveSquad.slotCooldownSeconds(reason or "down", self._squadConfig)
    pet:SetAttribute("CooldownUntil", os.time() + cd)
    local tid = pet:FindFirstChild("TargetID")
    if tid then
        tid.Value = 0 -- stop attacking
    end
    self:_clearEnduranceBar(pet) -- hidden pet shows no in-world bar; the HUD shows state
    if self._logger then
        self._logger:Info("Pet left the fight", { pet = pet.Name, reason = reason or "down" })
    end
end

-- Re-summon a recovered pet back onto the field (clears the downed state + heals it).
function EnemyService:_revivePet(pet)
    pet:SetAttribute("CombatDowned", false)
    pet:SetAttribute("CombatDamageTaken", 0)
    pet:SetAttribute("CooldownUntil", 0)
    pet:SetAttribute("DownedReason", "")
    self:_clearEnduranceBar(pet)
end

-- One enemy hit on a pet (accumulate damage; down it if it crosses the ceiling).
function EnemyService:_hitPet(pet, def, now, eng)
    local power = self:_petPower(pet)
    local factor = self._combatConfig.pet_down_threshold_factor or 1
    local dmg = (def.attack and def.attack.damage) or 0
    -- Hit / crit roll: a miss deals nothing, a crit multiplies the bite (before mitigation).
    local roll =
        CombatRoll.resolve(eng.rolls and eng.rolls.enemy_attack, math.random(), math.random())
    if roll.multiplier <= 0 then
        return -- missed
    end
    dmg = dmg * roll.multiplier
    pet:SetAttribute("LastHitCrit", roll.crit) -- for floating-text feedback (later)
    -- Defensive stat: the pet's Defense (its own + any active DefenseBuff from a power
    -- like Bulwark) mitigates the hit on the armor curve. A real tank survives longer.
    local nowT = os.time()
    -- Defense = innate role toughness (tanks are naturally tanky) + the pet's own Defense
    -- attribute + any active DefenseBuff (Bulwark etc.). All feed the armor curve below.
    local defense = self:_roleDefense(pet) + (pet:GetAttribute("Defense") or 0)
    if (pet:GetAttribute("DefenseBuffUntil") or 0) > nowT then
        defense = defense + (pet:GetAttribute("DefenseBuff") or 0)
    end
    dmg = CombatMath.mitigate(dmg, defense, self._combatConfig.armor_curve_k or 100)
    -- Absorption shield (Stone Skin etc.) soaks mitigated damage before any reaches
    -- endurance; it depletes as it absorbs.
    local shield = pet:GetAttribute("CombatShield") or 0
    if shield > 0 and dmg > 0 then
        local absorbed = math.min(shield, dmg)
        pet:SetAttribute("CombatShield", shield - absorbed)
        dmg = dmg - absorbed
    end
    local taken = PetEndurance.applyHit(pet:GetAttribute("CombatDamageTaken") or 0, dmg)
    pet:SetAttribute("CombatDamageTaken", taken)
    local pc = self._petCombat[pet]
    if not pc then
        pc = {}
        self._petCombat[pet] = pc
    end
    pc.lastHit = now
    self:_updateEnduranceBar(pet, taken, power, factor)
    if PetEndurance.isDowned(taken, power, factor) then
        self:_downPet(pet, now, eng, "down")
    end
end

-- The threat a pet exerts (higher pulls aggro): an explicit Threat attribute marks
-- a tank; otherwise the pet's Power is the default (stronger pets draw more).
-- A role's threat multiplier (tanks pull harder): PetRole attr -> by_type[PetType] ->
-- default; falls back to 1.
function EnemyService:_roleThreatMult(pet)
    local roles = self._petRoles
    if not roles then
        return 1
    end
    local id = pet:GetAttribute("PetRole")
        or (roles.by_type and roles.by_type[pet:GetAttribute("PetType")])
        or roles.default
    local def = roles.roles and roles.roles[id]
    return (def and tonumber(def.threat_mult)) or 1
end

function EnemyService:_petThreat(pet)
    local base = pet:GetAttribute("Threat")
    if not (base and base > 0) then
        base = self:_petPower(pet)
    end
    return base * self:_roleThreatMult(pet)
end

-- A role's innate defense (toughness), added to the pet's Defense before mitigation:
-- PetRole attr -> by_type[PetType] -> default; falls back to 0.
function EnemyService:_roleDefense(pet)
    local roles = self._petRoles
    if not roles then
        return 0
    end
    local id = pet:GetAttribute("PetRole")
        or (roles.by_type and roles.by_type[pet:GetAttribute("PetType")])
        or roles.default
    local def = roles.roles and roles.roles[id]
    return (def and tonumber(def.defense)) or 0
end

-- Does this pet's role auto-taunt (tanks)? PetRole attr -> by_type[PetType] -> default.
function EnemyService:_isTaunt(pet)
    local roles = self._petRoles
    if not roles then
        return false
    end
    local id = pet:GetAttribute("PetRole")
        or (roles.by_type and roles.by_type[pet:GetAttribute("PetType")])
        or roles.default
    local def = roles.roles and roles.roles[id]
    return def ~= nil and def.implicit_taunt == true
end

-- Nearest player whose character is within maxRange of a point (or nil).
function EnemyService:_nearestPlayer(ePos, maxRange)
    local best, bestD
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local d = (hrp.Position - ePos).Magnitude
            if d <= maxRange and (not bestD or d < bestD) then
                best, bestD = player, d
            end
        end
    end
    return best, bestD
end

-- One alive enemy, per tick: PERCEIVE a player (distance x probability) to acquire
-- aggro, CHASE the aggro'd squad until in attack range, and bite the highest-THREAT
-- pet in range (so a tank pet pulls aggro). Drops aggro past the leash range.
function EnemyService:_engageEnemy(entry, targetId, now, eng, dt)
    local model = entry.model
    -- Authoritative position lives in entry.pos (NOT the model pivot): the server
    -- never re-pivots the model after spawn, so its live CFrame is client-owned for
    -- smooth rendering (EnemyMotion). entry.pos drives all server-side combat math.
    local ePos = entry.pos or model:GetPivot().Position
    local atk = eng.attack_range or 11
    local perceptionRange = eng.perception_range or 70
    local leash = eng.leash_range or 90
    local def = self._enemiesConfig.enemies and self._enemiesConfig.enemies[entry.enemyId]
    local pfs = self:_petFollowService()

    -- 1) PERCEPTION: while unaware, notice the nearest player. Within proximity_range it
    -- engages for sure (get close enough and it attacks); out to perception_range it's a
    -- distance-weighted roll.
    if not entry.aggroPlayerName then
        entry.nextPerception = entry.nextPerception or 0
        if now >= entry.nextPerception then
            entry.nextPerception = now + (eng.perception_interval or 0.75)
            local proxRange = (eng.aggro and eng.aggro.proximity_range) or 30
            local player, d = self:_nearestPlayer(ePos, perceptionRange)
            if
                player
                and (d <= proxRange or EnemyAI.shouldNotice(d, perceptionRange, math.random()))
            then
                entry.aggroPlayerName = player.Name
            end
        end
        if not entry.aggroPlayerName then
            return -- still unaware: idle
        end
    end

    -- 2) Resolve the aggro'd player; drop aggro if gone or past the leash.
    local player = Players:FindFirstChild(entry.aggroPlayerName)
    local character = player and player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp or (hrp.Position - ePos).Magnitude > leash then
        self:_releasePets(targetId)
        entry.aggroPlayerName = nil
        return
    end

    -- 3) Aggro: point the (non-downed) squad at this enemy + gather threat candidates.
    local petsFolder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not petsFolder then
        return
    end
    -- Aggro upkeep: assign the (non-downed) squad to this enemy, DECAY the table, and tick
    -- PASSIVE threat (× each pet's Threat stat, so a tank climbs fastest). `valid` is the
    -- set of attackers still eligible to be targeted (present + not downed).
    local aggroCfg = eng.aggro or {}
    AggroTable.decay(entry.aggro, dt or 0.15, aggroCfg.decay_per_second or 4)
    local valid = {}
    local proxRange = aggroCfg.proximity_range or 30
    local proxFloor = aggroCfg.proximity_floor or 6
    for _, pet in ipairs(petsFolder:GetChildren()) do
        if pet:IsA("Model") and pet.PrimaryPart and not pet:GetAttribute("CombatDowned") then
            self:_assignPetToEnemy(pet, targetId)
            valid[pet] = true
            AggroTable.add(
                entry.aggro,
                pet,
                self:_petThreat(pet) * (aggroCfg.passive_per_second or 1.5) * (dt or 0.15)
            )
            -- Proximity floor: a pet within range (and not stealthed) keeps a baseline
            -- aggro so the enemy never disengages from something right next to it.
            if not pet:GetAttribute("Stealth") then
                local d = (self:_petPosition(pet, pfs) - ePos).Magnitude
                if d <= proxRange then
                    AggroTable.reinforce(entry.aggro, pet, proxFloor)
                end
            end
        end
    end

    -- Implicit taunt: every taunt.interval, a taunting pet (tank) re-asserts itself to
    -- `lead` × the highest OTHER attacker so it leads the pack. Not absolute — between
    -- pulses a pet bursting damage can out-aggro and pull the enemy off the tank.
    local tauntCfg = aggroCfg.taunt
    if type(tauntCfg) == "table" and (tauntCfg.lead or 0) > 0 then
        entry.tauntAt = entry.tauntAt or setmetatable({}, { __mode = "k" })
        for pet in pairs(valid) do
            if self:_isTaunt(pet) and (not entry.tauntAt[pet] or now >= entry.tauntAt[pet]) then
                entry.tauntAt[pet] = now + (tauntCfg.interval or 3)
                -- Taunt rolls too: a miss fizzles this pulse; a crit grabs harder (lead × mult).
                local troll =
                    CombatRoll.resolve(eng.rolls and eng.rolls.taunt, math.random(), math.random())
                if troll.multiplier > 0 then
                    local _, topOther = AggroTable.top(entry.aggro, 0, function(k)
                        return valid[k] == true and k ~= pet
                    end)
                    AggroTable.reinforce(
                        entry.aggro,
                        pet,
                        tauntCfg.lead * troll.multiplier * (topOther or 0)
                    )
                end
            end
        end
    end

    -- Target = the highest-aggro attacker still valid. If the top has decayed to/below the
    -- disengage threshold (nothing is hurting this enemy anymore), give up and idle.
    local targetPet = AggroTable.top(entry.aggro, aggroCfg.disengage_threshold or 0.5, function(k)
        return valid[k] == true
    end)
    if not targetPet then
        self:_releasePets(targetId)
        entry.aggroPlayerName = nil
        return
    end

    -- 4) CHASE the aggro target until in attack range. A tank/melee target orbits inside
    -- attack_range so the enemy just holds + bites it; a ranged target kites near the
    -- player, so the enemy has to close the gap. A ROOTED enemy can't move.
    local chaseTo = self:_petPosition(targetPet, pfs)
    local rooted = (model:GetAttribute("RootedUntil") or 0) > os.time()
    local moveSpeed = rooted and 0 or ((def and def.move_speed) or eng.default_move_speed or 12)
    -- Press inside attack_range so the enemy closes into bite range instead of stalling
    -- on its edge (where a kiting target floats just out of reach).
    local chaseStop = math.max(1, atk - (eng.attack_press or 3))
    local np = EnemyAI.chaseStep(
        { x = ePos.X, y = ePos.Y, z = ePos.Z },
        { x = chaseTo.X, y = chaseTo.Y, z = chaseTo.Z },
        moveSpeed,
        dt or 0.15,
        chaseStop
    )
    if math.abs(np.x - ePos.X) > 1e-3 or math.abs(np.z - ePos.Z) > 1e-3 then
        local newPos = Vector3.new(np.x, np.y, np.z)
        local faceTarget = Vector3.new(chaseTo.X, np.y, chaseTo.Z)
        -- Publish the step target instead of pivoting the model. The client (EnemyMotion)
        -- interpolates the visible model toward MoveTarget every frame; because the server
        -- no longer writes the model CFrame, there's no replicated snap to fight, so the
        -- motion is smooth. entry.pos is the authoritative position for combat math, and
        -- MoveTarget is what the mining-distance gate reads.
        model:SetAttribute("MoveTarget", newPos)
        model:SetAttribute("MoveFace", faceTarget)
        entry.pos = newPos
        ePos = newPos
    end

    -- 5) ATTACK: bite the highest-aggro pet that is CURRENTLY within attack range — not
    -- only the chase target. The enemy may be pursuing an unreachable top-aggro pet (a
    -- ranged kiter), but anything in its face (the melee/tank orbiting it) still gets hit.
    local biteTarget = AggroTable.top(entry.aggro, 0, function(k)
        return valid[k] == true and (self:_petPosition(k, pfs) - ePos).Magnitude <= atk
    end)
    entry.nextAttack = entry.nextAttack or 0
    if biteTarget and now >= entry.nextAttack then
        self:_hitPet(biteTarget, def, now, eng)
        entry.nextAttack = now + ((def and def.attack and def.attack.cadence) or 1.5)
    end
end

-- Partial-heal pass over ALL alive (non-downed) pets: chipped pets bleed their damage
-- back once they have been out of combat for the regen delay. Downed pets do NOT auto-
-- heal here — recovery is a player action (Summon) once the slot cooldown elapses.
function EnemyService:_regenPass(now, dt, eng)
    local playerPets = Workspace:FindFirstChild("PlayerPets")
    if not playerPets then
        return
    end
    local delay = (eng.regen and eng.regen.delay_seconds) or 3
    local perSec = (eng.regen and eng.regen.partial_per_second) or 12
    local factor = self._combatConfig.pet_down_threshold_factor or 1
    for _, folder in ipairs(playerPets:GetChildren()) do
        for _, pet in ipairs(folder:GetChildren()) do
            if pet:IsA("Model") and pet.PrimaryPart and not pet:GetAttribute("CombatDowned") then
                local taken = pet:GetAttribute("CombatDamageTaken") or 0
                if taken > 0 then
                    local pc = self._petCombat[pet]
                    local lastHit = (pc and pc.lastHit) or 0
                    if PetEndurance.canRegen(now, lastHit, delay) then
                        local newTaken = PetEndurance.regen(taken, dt, perSec)
                        pet:SetAttribute("CombatDamageTaken", newTaken)
                        if newTaken <= 0 then
                            self:_clearEnduranceBar(pet)
                        else
                            self:_updateEnduranceBar(pet, newTaken, self:_petPower(pet), factor)
                        end
                    end
                end
            end
        end
    end
end

-- Find a player's equipped pet by its squad slot (PositionNumber).
function EnemyService:_findPlayerPetBySlot(player, slotIndex)
    local folder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not folder then
        return nil
    end
    for _, pet in ipairs(folder:GetChildren()) do
        if pet:IsA("Model") then
            local pn = pet:FindFirstChild("PositionNumber")
            if pn and pn.Value == slotIndex then
                return pet
            end
        end
    end
    return nil
end

-- Recall (player action): pull a still-alive pet out of the fight for a SHORT slot
-- cooldown — rewards pulling a Strained/Critical pet before it is forced down.
function EnemyService:RecallPet(player, payload)
    local slot = tonumber(type(payload) == "table" and payload.slot or payload)
    if not slot then
        return
    end
    local pet = self:_findPlayerPetBySlot(player, slot)
    if pet and not pet:GetAttribute("CombatDowned") then
        self:_downPet(pet, os.clock(), self._combatConfig.engagement or {}, "recall")
    end
end

-- Summon (player action): bring a recovered pet back once its slot cooldown elapsed.
function EnemyService:SummonPet(player, payload)
    local slot = tonumber(type(payload) == "table" and payload.slot or payload)
    if not slot then
        return
    end
    local pet = self:_findPlayerPetBySlot(player, slot)
    if not pet or not pet:GetAttribute("CombatDowned") then
        return
    end
    local until_ = pet:GetAttribute("CooldownUntil") or 0
    if os.time() >= until_ then
        self:_revivePet(pet)
    end
end

-- Nearest alive enemy to a player (for focus-fire). Returns the model or nil.
function EnemyService:_nearestEnemyToPlayer(player)
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return nil
    end
    local best, bestD
    for _, entry in pairs(self._enemies) do
        local model = entry.model
        if model and model.Parent and (model:GetAttribute("HP") or 0) > 0 and model.PrimaryPart then
            local ePos = entry.pos or model:GetPivot().Position
            local d = (ePos - hrp.Position).Magnitude
            if not bestD or d < bestD then
                best, bestD = model, d
            end
        end
    end
    return best
end

-- Tactical command from the hotbar — a squad-wide order (no new power system):
--   focus_fire — every non-downed pet attacks the nearest alive enemy
--   scatter/regroup — clear enemy targets so pets return to follow / auto-mine
--   retreat — recall every non-downed pet (short cooldown), pulling the squad out
function EnemyService:ExecuteTactical(player, command)
    local petsFolder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not petsFolder then
        return
    end

    if command == "focus_fire" then
        local enemy = self:_nearestEnemyToPlayer(player)
        if not enemy then
            return
        end
        local bid = enemy:FindFirstChild("BreakableID")
        local targetId = bid and bid.Value
        if not targetId then
            return
        end
        for _, pet in ipairs(petsFolder:GetChildren()) do
            if pet:IsA("Model") and pet.PrimaryPart and not pet:GetAttribute("CombatDowned") then
                self:_assignPetToEnemy(pet, targetId)
            end
        end
    elseif command == "scatter" or command == "regroup" then
        for _, pet in ipairs(petsFolder:GetChildren()) do
            if pet:IsA("Model") then
                local tid = pet:FindFirstChild("TargetID")
                if tid then
                    tid.Value = 0 -- back to follow / auto-mine
                end
            end
        end
    elseif command == "retreat" then
        for _, pet in ipairs(petsFolder:GetChildren()) do
            if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
                local pn = pet:FindFirstChild("PositionNumber")
                if pn then
                    self:RecallPet(player, { slot = pn.Value })
                end
            end
        end
    end
    if self._logger then
        self._logger:Info("Tactical command", { player = player.Name, command = command })
    end
end

-- Debuffs shown above an enemy. Placeholder colour+label now; set `icon` later.
local ENEMY_DEBUFFS = {
    {
        key = "vuln",
        untilAttr = "VulnerableUntil",
        color = Color3.fromRGB(235, 90, 90),
        label = "VULN",
    },
    {
        key = "root",
        untilAttr = "RootedUntil",
        color = Color3.fromRGB(90, 200, 235),
        label = "ROOT",
    },
}

-- Billboard above the enemy (above its HP bar) showing active debuffs + countdowns.
function EnemyService:_updateDebuffBadges(model, nowTime)
    local pp = model.PrimaryPart
    if not pp then
        return
    end
    local bb = pp:FindFirstChild("DebuffBar")
    if not bb then
        bb = Instance.new("BillboardGui")
        bb.Name = "DebuffBar"
        bb.Size = UDim2.fromOffset(140, 24)
        bb.StudsOffset = Vector3.new(0, 6.4, 0) -- just above the HP bar (+5)
        bb.AlwaysOnTop = true
        bb.Adornee = pp
        bb.Parent = pp
        local lay = Instance.new("UIListLayout")
        lay.FillDirection = Enum.FillDirection.Horizontal
        lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        lay.Padding = UDim.new(0, 3)
        lay.Parent = bb
    end
    for i, d in ipairs(ENEMY_DEBUFFS) do
        local until_ = model:GetAttribute(d.untilAttr) or 0
        local badge = bb:FindFirstChild(d.key)
        if until_ > nowTime then
            if not badge then
                badge = Instance.new("Frame")
                badge.Name = d.key
                badge.Size = UDim2.fromOffset(46, 22)
                badge.BackgroundColor3 = d.color
                badge.BorderSizePixel = 0
                badge.LayoutOrder = i
                badge.Parent = bb
                local c = Instance.new("UICorner")
                c.CornerRadius = UDim.new(0, 5)
                c.Parent = badge
                local icon = Instance.new("ImageLabel")
                icon.Name = "Icon"
                icon.BackgroundTransparency = 1
                icon.Size = UDim2.fromScale(1, 1)
                icon.Image = d.icon or ""
                icon.ZIndex = 3
                icon.Parent = badge
                local lbl = Instance.new("TextLabel")
                lbl.Name = "Label"
                lbl.BackgroundTransparency = 1
                lbl.Size = UDim2.fromScale(1, 1)
                lbl.Font = Enum.Font.GothamBold
                lbl.TextSize = 10
                lbl.TextColor3 = Color3.fromRGB(20, 22, 28)
                lbl.Parent = badge
            end
            local lbl = badge:FindFirstChild("Label")
            if lbl then
                lbl.Text = d.label .. " " .. math.ceil(until_ - nowTime)
            end
        elseif badge then
            badge:Destroy()
        end
    end
end

-- A support pet's auto-heal config (role.auto_heal), or nil.
function EnemyService:_roleAutoHeal(pet)
    local roles = self._petRoles
    if not roles then
        return nil
    end
    local id = pet:GetAttribute("PetRole")
        or (roles.by_type and roles.by_type[pet:GetAttribute("PetType")])
        or roles.default
    local def = roles.roles and roles.roles[id]
    return def and def.auto_heal
end

-- A green heal puff above a pet (world-side "tell" that it was just healed). Expands +
-- fades over ~0.7s; cleaned by Debris.
function EnemyService:_spawnHealVisual(pet)
    local pp = pet.PrimaryPart
    if not pp then
        return
    end
    local fx = Instance.new("Part")
    fx.Name = "HealFX"
    fx.Shape = Enum.PartType.Ball
    fx.Material = Enum.Material.Neon
    fx.Color = Color3.fromRGB(95, 225, 120)
    fx.Transparency = 0.35
    fx.Anchored = true
    fx.CanCollide = false
    fx.CanQuery = false
    fx.Massless = true
    fx.Size = Vector3.new(2, 2, 2)
    fx.CFrame = pp.CFrame
    fx.Parent = Workspace
    TweenService:Create(
        fx,
        TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = Vector3.new(8, 8, 8), Transparency = 1 }
    ):Play()
    Debris:AddItem(fx, 0.8)
end

-- Support pets (role.auto_heal) periodically mend the most-hurt non-downed ally in their
-- own squad — reduce its accumulated CombatDamageTaken. The squad healer keeps the tank up.
function EnemyService:_supportPass(now)
    local playerPets = Workspace:FindFirstChild("PlayerPets")
    if not playerPets then
        return
    end
    self._supportAt = self._supportAt or setmetatable({}, { __mode = "k" })
    local factor = self._combatConfig.pet_down_threshold_factor or 1
    for _, folder in ipairs(playerPets:GetChildren()) do
        for _, pet in ipairs(folder:GetChildren()) do
            if pet:IsA("Model") and pet.PrimaryPart and not pet:GetAttribute("CombatDowned") then
                local heal = self:_roleAutoHeal(pet)
                if
                    heal
                    and (heal.amount or 0) > 0
                    and (not self._supportAt[pet] or now >= self._supportAt[pet])
                then
                    self._supportAt[pet] = now + (heal.interval or 1.5)
                    -- most-hurt non-downed ally in this squad
                    local target, worst
                    for _, ally in ipairs(folder:GetChildren()) do
                        if ally:IsA("Model") and not ally:GetAttribute("CombatDowned") then
                            local taken = ally:GetAttribute("CombatDamageTaken") or 0
                            if taken > 0 and (not worst or taken > worst) then
                                worst, target = taken, ally
                            end
                        end
                    end
                    if target then
                        local newTaken = math.max(
                            0,
                            (target:GetAttribute("CombatDamageTaken") or 0) - heal.amount
                        )
                        target:SetAttribute("CombatDamageTaken", newTaken)
                        if newTaken <= 0 then
                            self:_clearEnduranceBar(target)
                        else
                            self:_updateEnduranceBar(
                                target,
                                newTaken,
                                self:_petPower(target),
                                factor
                            )
                        end
                        -- Visual tell: blinking heal badge (HealFxUntil) + world heal puff,
                        -- so an instant heal is visible even though it has no duration.
                        local fxSec = (
                            self._combatConfig.engagement
                            and self._combatConfig.engagement.instant_fx_seconds
                        ) or 3
                        target:SetAttribute("HealFxUntil", os.time() + fxSec)
                        self:_spawnHealVisual(target)
                    end
                end
            end
        end
    end
end

function EnemyService:_combatTick(dt)
    local eng = self._combatConfig.engagement or {}
    local now = os.clock()
    local nowTime = os.time()
    self:_regenPass(now, dt, eng)
    self:_supportPass(now)
    for targetId, entry in pairs(self._enemies) do
        local model = entry.model
        if model and model.Parent and (model:GetAttribute("HP") or 0) > 0 then
            self:_engageEnemy(entry, targetId, now, eng, dt)
            self:_updateDebuffBadges(model, nowTime)
        end
    end
end

function EnemyService:Start()
    -- Share PetFollowService's gate: if the service-owned pet loop is off, the
    -- legacy scripts own pets and this combat layer stays inert.
    if not (self._petFollowConfig and self._petFollowConfig.service_owned) then
        return
    end
    local interval = self._petFollowConfig.update_interval or 0.15
    local accum = 0
    RunService.Heartbeat:Connect(function(dt)
        accum += dt
        if accum < interval then
            return
        end
        local step = accum
        accum = 0
        pcall(function()
            self:_combatTick(step)
        end)
    end)
    if self._logger then
        self._logger:Info("EnemyService combat loop active (inverse mining)")
    end
end

-- Public: spawn a stationary enemy near the player and engage their pets.
function EnemyService:SpawnEnemy(player, enemyId)
    enemyId = tostring(enemyId or "lava_imp")
    local def = self._enemiesConfig.enemies and self._enemiesConfig.enemies[enemyId]
    if not def then
        return { ok = false, reason = "unknown_enemy" }
    end

    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return { ok = false, reason = "no_character" }
    end

    local spawnCfg = self._petFollowConfig.enemy_spawn or {}
    local dist = tonumber(spawnCfg.distance) or 16
    local flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
    flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
    local position = hrp.Position + flat * dist + Vector3.new(0, 3, 0)

    self._nextId += 1
    local targetId = self._nextId
    local model = self:_buildModel(enemyId, def, position, targetId)
    model.Parent = self:_enemiesFolder()
    -- entry.pos = authoritative position (server never re-pivots the model after this
    -- initial placement). Seed MoveTarget so the gate + client render have a value
    -- before the first chase step.
    self._enemies[targetId] = {
        model = model,
        enemyId = enemyId,
        pos = position,
        aggro = AggroTable.new(),
    }
    model:SetAttribute("MoveTarget", position)
    model:SetAttribute("MoveFace", Vector3.new(hrp.Position.X, position.Y, hrp.Position.Z))

    -- Watch HP -> death; also drive the HP bar.
    model:GetAttributeChangedSignal("HP"):Connect(function()
        local hp = model:GetAttribute("HP") or 0
        local maxHp = model:GetAttribute("MaxHP") or 1
        local fill = model.PrimaryPart
            and model.PrimaryPart:FindFirstChild("BillboardGui")
            and model.PrimaryPart.BillboardGui:FindFirstChild("Frame")
            and model.PrimaryPart.BillboardGui.Frame:FindFirstChild("Fill")
        if fill then
            fill.Size = UDim2.fromScale(math.clamp(hp / math.max(maxHp, 1), 0, 1), 1)
        end
        if hp <= 0 then
            self:_onDefeated(targetId)
        end
    end)

    -- Admin-spawned enemies engage the spawning player immediately (skip the
    -- perception roll — the combat tick handles chase + threat targeting from here).
    self._enemies[targetId].aggroPlayerName = player.Name
    if self._logger then
        self._logger:Info("Enemy spawned", { enemyId = enemyId, targetId = targetId, hp = def.hp })
    end
    return { ok = true, targetId = targetId, enemyId = enemyId, hp = def.hp }
end

return EnemyService
