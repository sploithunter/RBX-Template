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

local PetEndurance = require(ReplicatedStorage.Shared.Game.PetEndurance)

local EnemyService = {}
EnemyService.__index = EnemyService

function EnemyService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._enemiesConfig = self._configLoader:LoadConfig("enemies")
    self._petFollowConfig = self._configLoader:LoadConfig("pet_follow")
    self._combatConfig = self._configLoader:LoadConfig("combat")
    self._nextId = 0
    self._enemies = {} -- targetId -> { model, enemyId, nextAttack }
    -- pet model -> { lastHit, downedUntil } (weak so dead pets GC). The accumulated
    -- damage + downed flag live as replicated attributes on the pet (so clients can
    -- show the endurance bar); this table is just server-only timing.
    self._petCombat = setmetatable({}, { __mode = "k" })
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

-- Build the enemy model: a simple stationary dummy (slice 1a). PrimaryPart is the body so pet
-- formations surround its pivot; carries the target id + HP + archetype + contrib ledger.
function EnemyService:_buildModel(enemyId, def, position, targetId)
    local model = Instance.new("Model")
    model.Name = "Enemy_" .. enemyId .. "_" .. targetId

    local body = Instance.new("Part")
    body.Name = "Body"
    body.Shape = Enum.PartType.Block
    body.Size = Vector3.new(5, 7, 5)
    body.Color = Color3.fromRGB(180, 60, 60)
    body.Material = Enum.Material.SmoothPlastic
    body.Anchored = true -- stationary for slice 1a (no physics / no fall)
    body.CanCollide = false
    body.Position = position
    body.Parent = model
    model.PrimaryPart = body

    local idValue = Instance.new("NumberValue")
    idValue.Name = "BreakableID" -- the generic target id the pet plumbing keys on
    idValue.Value = targetId
    idValue.Parent = model

    local contrib = Instance.new("Folder")
    contrib.Name = "Contrib"
    contrib.Parent = model

    model:SetAttribute("EnemyId", enemyId)
    model:SetAttribute("HP", def.hp)
    model:SetAttribute("MaxHP", def.hp)
    model:SetAttribute("IsEnemy", true)

    -- HP bar
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(6, 0, 0.8, 0)
    bb.StudsOffset = Vector3.new(0, 5, 0)
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

    return model
end

-- Assign all of a player's equipped pets to attack this enemy (mirrors BreakableService).
function EnemyService:_assignPets(player, targetId)
    local petsFolder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not petsFolder then
        return
    end
    for _, pet in ipairs(petsFolder:GetChildren()) do
        local tt = pet:FindFirstChild("TargetType")
        local tw = pet:FindFirstChild("TargetWorld")
        local tid = pet:FindFirstChild("TargetID")
        if tt and tid then -- TargetWorld is optional (enemy lookup is world-agnostic)
            tt.Value = "Enemy"
            if tw then
                tw.Value = ""
            end
            tid.Value = targetId
        end
    end
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

-- Down a pet: it took all of its endurance. Out of combat for the long full-defeat
-- heal, then auto-heals (regen pass). Visibly tagged + drops its attack target so
-- it retreats to follow formation.
function EnemyService:_downPet(pet, now, eng)
    pet:SetAttribute("CombatDowned", true)
    local pc = self._petCombat[pet]
    if not pc then
        pc = {}
        self._petCombat[pet] = pc
    end
    pc.downedUntil = now + (eng.full_defeat_heal_seconds or 25)
    local tid = pet:FindFirstChild("TargetID")
    if tid then
        tid.Value = 0 -- stop attacking; back to follow while healing
    end
    local pp = pet.PrimaryPart
    if pp and not pp:FindFirstChild("DownedTag") then
        local bb = Instance.new("BillboardGui")
        bb.Name = "DownedTag"
        bb.Size = UDim2.new(4, 0, 1, 0)
        bb.StudsOffset = Vector3.new(0, 4.6, 0)
        bb.AlwaysOnTop = true
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Text = "DOWNED"
        lbl.TextColor3 = Color3.fromRGB(255, 110, 110)
        lbl.TextStrokeTransparency = 0.3
        lbl.TextScaled = true
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = bb
        bb.Parent = pp
    end
    if self._logger then
        self._logger:Info("Pet downed in combat", { pet = pet.Name })
    end
end

function EnemyService:_revivePet(pet)
    pet:SetAttribute("CombatDowned", false)
    pet:SetAttribute("CombatDamageTaken", 0)
    local pp = pet.PrimaryPart
    if pp then
        local tag = pp:FindFirstChild("DownedTag")
        if tag then
            tag:Destroy()
        end
    end
    self:_clearEnduranceBar(pet)
end

-- One enemy hit on a pet (accumulate damage; down it if it crosses the ceiling).
function EnemyService:_hitPet(pet, def, now, eng)
    local power = self:_petPower(pet)
    local factor = self._combatConfig.pet_down_threshold_factor or 1
    local dmg = (def.attack and def.attack.damage) or 0
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
        self:_downPet(pet, now, eng)
    end
end

-- One alive enemy: aggro every non-downed pet of nearby players (they attack back),
-- then bite the closest pet within attack range on the enemy's cadence.
function EnemyService:_engageEnemy(entry, targetId, now, eng)
    local model = entry.model
    local ePos = model:GetPivot().Position
    local aggro = eng.aggro_range or 45
    local atk = eng.attack_range or 11
    local pfs = self:_petFollowService()

    local closest, closestDist
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local pets = Workspace:FindFirstChild("PlayerPets")
            and Workspace.PlayerPets:FindFirstChild(player.Name)
        if hrp and pets and (hrp.Position - ePos).Magnitude <= aggro then
            for _, pet in ipairs(pets:GetChildren()) do
                if
                    pet:IsA("Model")
                    and pet.PrimaryPart
                    and not pet:GetAttribute("CombatDowned")
                then
                    self:_assignPetToEnemy(pet, targetId)
                    local d = (self:_petPosition(pet, pfs) - ePos).Magnitude
                    if d <= atk and (not closestDist or d < closestDist) then
                        closest, closestDist = pet, d
                    end
                end
            end
        end
    end

    local def = self._enemiesConfig.enemies and self._enemiesConfig.enemies[entry.enemyId]
    local cadence = (def and def.attack and def.attack.cadence) or 1.5
    entry.nextAttack = entry.nextAttack or 0
    if closest and now >= entry.nextAttack then
        self:_hitPet(closest, def, now, eng)
        entry.nextAttack = now + cadence
    end
end

-- Heal pass over ALL players' pets (runs even with no enemies): downed pets fully
-- heal after their long timer; partially-damaged pets bleed damage back once they
-- have been out of combat for the regen delay (the faster, partial heal).
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
            if pet:IsA("Model") and pet.PrimaryPart then
                if pet:GetAttribute("CombatDowned") then
                    local pc = self._petCombat[pet]
                    if pc and pc.downedUntil and now >= pc.downedUntil then
                        self:_revivePet(pet)
                    end
                else
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
end

function EnemyService:_combatTick(dt)
    local eng = self._combatConfig.engagement or {}
    local now = os.clock()
    self:_regenPass(now, dt, eng)
    for targetId, entry in pairs(self._enemies) do
        local model = entry.model
        if model and model.Parent and (model:GetAttribute("HP") or 0) > 0 then
            self:_engageEnemy(entry, targetId, now, eng)
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
    self._enemies[targetId] = { model = model, enemyId = enemyId }

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

    self:_assignPets(player, targetId)
    if self._logger then
        self._logger:Info("Enemy spawned", { enemyId = enemyId, targetId = targetId, hp = def.hp })
    end
    return { ok = true, targetId = targetId, enemyId = enemyId, hp = def.hp }
end

return EnemyService
