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

local fireGameEvent = require(ReplicatedStorage.Shared.Network.FireGameEvent)
local PetRevive = require(script.Parent.Parent.PetRevive)
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")
local AssetService = game:GetService("AssetService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local AssetFetch = require(ReplicatedStorage.Shared.Utils.AssetFetch)

local PetEndurance = require(ReplicatedStorage.Shared.Game.PetEndurance)
local EnemyAI = require(ReplicatedStorage.Shared.Game.EnemyAI)
local PetMeander = require(ReplicatedStorage.Shared.Game.PetMeander)
local RingSeparate = require(ReplicatedStorage.Shared.Game.RingSeparate)
local AggroTable = require(ReplicatedStorage.Shared.Game.AggroTable)
local CombatRoll = require(ReplicatedStorage.Shared.Game.CombatRoll)
local Accuracy = require(ReplicatedStorage.Shared.Game.Accuracy)
local LevelScale = require(ReplicatedStorage.Shared.Game.LevelScale)
local ActiveSquad = require(ReplicatedStorage.Shared.Game.ActiveSquad)
local CombatMath = require(ReplicatedStorage.Shared.Game.CombatMath)
local CombatOrigin = require(ReplicatedStorage.Shared.Game.CombatOrigin)
local TargetPriority = require(ReplicatedStorage.Shared.Game.TargetPriority)
local SupportAura = require(ReplicatedStorage.Shared.Game.SupportAura)
local PetLockout = require(ReplicatedStorage.Shared.Game.PetLockout)
local ZoneResolver = require(ReplicatedStorage.Shared.Game.ZoneResolver)
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
    self._levelingConfig = self._configLoader:LoadConfig("leveling")
    self._originConfig = (self._configLoader:LoadConfig("combat_fx") or {}).origin or {}
    self._powersConfig = self._configLoader:LoadConfig("powers") -- combat_vfx.on_hit (e.g. dodge pops)
    -- Territorial engagement: the SAME area bounds ZoneTrackerService uses for the player's
    -- CurrentArea SSOT, so an enemy's home area (resolved from where it spawned) and a player's
    -- CurrentArea are compared in one id space (Spawn/Meadow/Lava/Ice/Desert).
    local areasConfig = self._configLoader:LoadConfig("areas")
    self._areaBounds = (areasConfig and ZoneResolver.boundsFromAreas(areasConfig)) or {}
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
    -- Admin testing: force a slot's pet DOWN (reason "down" => triggers the lockout) with no enemies.
    Signals.Squad_AdminKill.OnServerEvent:Connect(function(player, payload)
        pcall(function()
            self:AdminKillPet(player, payload)
        end)
    end)

    -- Assist target: the player directs the squad to focus an enemy (its BreakableID),
    -- or 0 to clear. Pets prefer this over their aggro-picked target (player's edge).
    Signals.Combat_SetAssist.OnServerEvent:Connect(function(player, payload)
        local id = tonumber(type(payload) == "table" and payload.targetId or payload) or 0
        player:SetAttribute("CombatAssistTarget", id)
    end)

    -- Buff target: the selected squad pet (its PositionNumber slot), used by single-target
    -- defensive powers so a shield/armor lands on one pet instead of the whole squad. 0 clears.
    Signals.Combat_SelectPetTarget.OnServerEvent:Connect(function(player, payload)
        local slot = tonumber(type(payload) == "table" and payload.slot or payload) or 0
        player:SetAttribute("CombatBuffTarget", slot)
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

-- Set (or clear, with nil) the player whose squad this enemy is fighting. entry.aggroPlayerName
-- stays the server SoT; AggroOwner is its replicated read-only shadow so the client EnemyHud can
-- list only the foes engaged with ITS squad (every aggro mutation goes through here).
function EnemyService:_setAggroOwner(entry, name)
    entry.aggroPlayerName = name
    if name then
        entry.everEngaged = true -- has fought at least once -> eligible for idle-despawn when abandoned
    end
    local model = entry.model
    if model and model.Parent then
        model:SetAttribute("AggroOwner", name or "")
    end
end

-- COMBAT ONRAMP gate (configs/combat.lua engagement.min_engage_level). Below the threshold a
-- player is invisible to combat: enemies won't aggress them and their pets won't pull (they keep
-- mining), so early levels are a peaceful onramp with the enemies on display. Combat switches on
-- at min_engage_level. 0/1/absent = no gate (everyone fights).
function EnemyService:_engagesCombat(player)
    if not player then
        return false
    end
    local eng = self._combatConfig and self._combatConfig.engagement
    local minLvl = eng and tonumber(eng.min_engage_level)
    if not minLvl or minLvl <= 1 then
        return true
    end
    return (player:GetAttribute("Level") or 1) >= minLvl
end

-- The area id at a world position (Spawn/Meadow/Lava/Ice/Desert), or nil outside every area. Same
-- resolver + bounds as the player CurrentArea SSOT, so the two ids compare 1:1.
function EnemyService:_areaAt(pos)
    if not pos or not next(self._areaBounds) then
        return nil
    end
    return ZoneResolver.resolve(pos, self._areaBounds)
end

-- TERRITORIAL gate (Jason): an enemy only engages a player who is in ITS area — so a foe across a
-- wall in a different biome won't be dragged through it by proximity; it stays loitering. Lava
-- fights in lava, ice in ice, etc. An enemy with no resolved home area (spawned off-grid) has no
-- gate (engages anyone).
function EnemyService:_inTerritory(entry, player)
    local home = entry.homeArea
    if not home then
        return true
    end
    return player:GetAttribute("CurrentArea") == home
end

-- Add aggro for an attacker (pet Model / Player) on the enemy identified by `model`.
-- Called when something hurts the enemy (PetFollowService mining) — damage builds threat.
-- No-op if `model` isn't a tracked enemy. Public so other services can feed the table.
function EnemyService:AddAggro(model, key, amount)
    local idVal = model and model:FindFirstChild("BreakableID")
    local entry = idVal and self._enemies[idVal.Value]
    if entry and entry.aggro then
        AggroTable.add(entry.aggro, key, amount)
        -- BEING ATTACKED ACQUIRES AGGRO (Jason: bunny fought imps from beyond the
        -- owner's perception range and "they don't care" — perception watched the
        -- PLAYER only). Damage is its own acquisition path: an unaware enemy that
        -- takes a hit wakes on the attacking pet's OWNER, regardless of how far
        -- away that player is standing. Perception stays the ambient path.
        if not entry.aggroPlayerName and typeof(key) == "Instance" and key.Parent then
            local owner = game:GetService("Players"):FindFirstChild(key.Parent.Name)
            -- ONRAMP + TERRITORIAL: only retaliate if the attacking pet's owner is at/above
            -- min_engage_level AND standing in this enemy's area.
            if owner and self:_engagesCombat(owner) and self:_inTerritory(entry, owner) then
                self:_setAggroOwner(entry, owner.Name)
                entry.meander = nil
                entry.home = nil -- re-home wherever this fight leaves it
            end
        end
    end
end

-- Load (once, cached) a real enemy art asset into a sanitized template: PrimaryPart
-- set, every part anchored + non-colliding (movement is PivotTo, not physics). The
-- template is cached UNSCALED and per-spawn scaling happens on the clone in _buildModel,
-- so two enemies sharing one asset at different model_scale values don't collide. Returns
-- nil on any failure so spawning falls back to the procedural block. Cache stores `false`
-- for known-bad ids so we don't re-yield on every spawn.
function EnemyService:_enemyTemplate(assetId, needsPrimaryPart)
    self._modelCache = self._modelCache or {}
    local cached = self._modelCache[assetId]
    if cached ~= nil then
        return cached or nil
    end

    local ok, container = pcall(function()
        return AssetFetch.load(assetId)
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

-- Build (once, cached) a MODEL from a separately-uploaded MESH + TEXTURE — the same combine the
-- gem drops use (DropService): CreateMeshPartAsync(meshId) + MeshPart.TextureID = texId. Avoids an
-- InsertService Model fetch (group-safe, cacheable) and keeps mesh/texture as independent assets.
-- Returns a Model whose PrimaryPart is the anchored MeshPart, or nil to fall back to a procedural block.
function EnemyService:_meshTemplate(meshId, textureId)
    self._meshCache = self._meshCache or {}
    local key = tostring(meshId) .. "|" .. tostring(textureId)
    local cached = self._meshCache[key]
    if cached ~= nil then
        return cached or nil
    end
    local ok, mesh = pcall(function()
        -- selene: allow(undefined_variable)
        local content = Content.fromUri(meshId) -- `Content` is a runtime global selene's std lacks
        return AssetService:CreateMeshPartAsync(content, {
            CollisionFidelity = Enum.CollisionFidelity.Box,
            RenderFidelity = Enum.RenderFidelity.Automatic,
        })
    end)
    local template
    if ok and mesh then
        if textureId then
            pcall(function()
                mesh.TextureID = textureId
            end)
        end
        mesh.Name = "Body"
        mesh.Anchored = true
        mesh.CanCollide = false
        local model = Instance.new("Model")
        mesh.Parent = model
        model.PrimaryPart = mesh
        model.Parent = ServerStorage
        template = model
    elseif self._logger then
        self._logger:Warn(
            "Enemy mesh build failed; using procedural fallback",
            { mesh = tostring(meshId), error = tostring(mesh) }
        )
    end
    self._meshCache[key] = template or false
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

    -- Name tag above the HP bar. The client (EnemyMotion) sets its text ("Name Lv N") and
    -- COLOUR by difficulty relative to the viewing player's level — so it's per-viewer.
    model:SetAttribute("DisplayName", def.display_name or enemyId)
    local nameBb = Instance.new("BillboardGui")
    nameBb.Name = "NameTag"
    nameBb.Size = UDim2.new(8, 0, 1.1, 0)
    nameBb.StudsOffset = Vector3.new(0, height / 2 + 3, 0)
    nameBb.AlwaysOnTop = true
    nameBb.Adornee = body
    nameBb.Parent = body
    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name = "Name"
    nameLbl.BackgroundTransparency = 1
    nameLbl.Size = UDim2.fromScale(1, 1)
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextScaled = true
    nameLbl.TextColor3 = Color3.fromRGB(245, 245, 245)
    nameLbl.TextStrokeTransparency = 0.35
    nameLbl.Text = def.display_name or enemyId
    nameLbl.Parent = nameBb

    -- Per-faction ambience: a small particle aura drifting off the body — embers for Lava
    -- (def.embers), sand-motes for Desert (def.dust). A cheap continuous ParticleEmitter modelled
    -- on the molten-tar-pit look in AreaFX. Server-created so every nearby player sees it
    -- (shared-world FX). Rate + size scale with model_scale, so a boss billows and a whelp wisps.
    if def.embers or def.dust or def.frost then
        self:_attachAura(body, def)
    end
end

-- Continuous rising particle aura for a faction enemy. `embers` = molten glow (Lava); `dust` =
-- pale sand-motes, no glow (Desert). Tuned small so it reads as ambience, not a bonfire/sandstorm.
local AURA_PALETTES = {
    embers = {
        light = 0.7, -- glowing
        colors = {
            { 0, Color3.fromRGB(255, 200, 90) }, -- bright spark
            { 0.6, Color3.fromRGB(235, 110, 40) }, -- ember orange
            { 1, Color3.fromRGB(120, 30, 20) }, -- cooling red
        },
    },
    dust = {
        light = 0.05, -- sand doesn't glow; just catches light
        colors = {
            { 0, Color3.fromRGB(225, 205, 160) }, -- pale sand
            { 0.6, Color3.fromRGB(200, 175, 125) }, -- ochre
            { 1, Color3.fromRGB(150, 130, 95) }, -- dusty brown
        },
    },
    frost = {
        light = 0.4, -- ice crystals catch a faint shimmer
        colors = {
            { 0, Color3.fromRGB(235, 250, 255) }, -- bright frost
            { 0.6, Color3.fromRGB(175, 220, 255) }, -- ice blue
            { 1, Color3.fromRGB(120, 170, 220) }, -- deep glacier blue
        },
    },
}
function EnemyService:_attachAura(body, def)
    if not body then
        return
    end
    local pal = AURA_PALETTES[(def.frost and "frost") or (def.dust and "dust") or "embers"]
    pcall(function()
        local scale = def.model_scale or 4
        local e = Instance.new("ParticleEmitter")
        e.Name = "FactionAura"
        local seq = {}
        for _, kp in ipairs(pal.colors) do
            seq[#seq + 1] = ColorSequenceKeypoint.new(kp[1], kp[2])
        end
        e.Color = ColorSequence.new(seq)
        e.LightEmission = pal.light
        e.Lifetime = NumberRange.new(0.8, 1.6)
        e.Rate = math.clamp(scale * 1.5, 5, 26) -- bigger enemy -> more motes
        e.Speed = NumberRange.new(1, 3)
        e.Acceleration = Vector3.new(0, 2, 0) -- rise
        e.SpreadAngle = Vector2.new(22, 22)
        e.EmissionDirection = Enum.NormalId.Top
        e.Rotation = NumberRange.new(0, 360)
        e.RotSpeed = NumberRange.new(-90, 90)
        local px = math.clamp(scale * 0.12, 0.3, 2) -- mote size grows with the enemy
        e.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, px),
            NumberSequenceKeypoint.new(1, 0),
        })
        e.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.8, 0.5),
            NumberSequenceKeypoint.new(1, 1),
        })
        e.Parent = body
    end)
end

-- Build the enemy model. Uses the configured `model_asset` art when present (cloned
-- from a cached template); otherwise a simple block dummy. PrimaryPart is the body so
-- pet formations surround its pivot, and movement is via PivotTo (parts are anchored).
function EnemyService:_buildModel(enemyId, def, position, targetId)
    local model, body
    -- `mesh_asset` (+ optional `texture_asset`) -> build via CreateMeshPartAsync (the gem combine);
    -- else `model_asset` -> InsertService/PlaceAssets clone; else the procedural block below.
    local template
    if def.mesh_asset then
        template = self:_meshTemplate(def.mesh_asset, def.texture_asset)
    elseif def.model_asset then
        template = self:_enemyTemplate(def.model_asset, def.needs_primary_part)
    end
    if template then
        model = template:Clone()
        body = model.PrimaryPart
        -- Scale the CLONE (not the shared cached template) so enemies that reuse the
        -- same art at different model_scale values each get their own size.
        if def.model_scale and def.model_scale ~= 1 then
            pcall(function()
                model:ScaleTo(def.model_scale)
            end)
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

-- Quietly retire an enemy that's been idle too long (engagement timer expired) — NO loot, no death
-- FX, it just leaves the field. Releases any pets still pointed at it and untracks it.
function EnemyService:_despawnEnemy(targetId)
    local entry = self._enemies[targetId]
    if not entry then
        return
    end
    self._enemies[targetId] = nil
    self:_releasePets(targetId)
    if entry.model then
        entry.model:Destroy()
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
                    combat:AwardLoot(player, entry.enemyId, model:GetAttribute("Level"))
                end)
                fireGameEvent(player, "enemy_defeated", { enemy = entry.enemyId })
                pcall(function() -- mission counter (Origin Story combat beats)
                    _G.RBXTemplateServices
                        :Get("StatsService")
                        :Increment(player, "enemies_defeated", 1)
                end)
                -- rare ENHANCEMENT drop at the kill site (identity revealed at pickup)
                local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if pp then
                    local locator = _G.RBXTemplateServices
                    local okSvc, drops = pcall(function()
                        return locator and locator:Get("DropService")
                    end)
                    if okSvc and drops and drops.TrySpawnEnhancementDrop then
                        pcall(function()
                            drops:TrySpawnEnhancementDrop(player, "enemy", pp.Position)
                        end)
                    end
                end
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
    if (pet:GetAttribute("ReviveGraceUntil") or 0) > os.time() then
        return -- fresh revive: not draftable until the grace expires (PetRevive)
    end
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
    -- pet folders are named after the owner (Workspace.PlayerPets.<name>)
    local owner = pet.Parent and Players:FindFirstChild(pet.Parent.Name)
    if owner then
        fireGameEvent(owner, "pet_down", { pet = pet.Name, reason = reason or "down" })
    end
    local cd = ActiveSquad.slotCooldownSeconds(reason or "down", self._squadConfig)
    pet:SetAttribute("CooldownUntil", os.time() + cd)
    local tid = pet:FindFirstChild("TargetID")
    if tid then
        tid.Value = 0 -- stop attacking
    end
    self:_clearEnduranceBar(pet) -- hidden pet shows no in-world bar; the HUD shows state
    -- #179: a forced DOWN matters — record the lockout against the pet's IDENTITY (persisted), so
    -- re-teaming can't revive it for free. A proactive RECALL is not a death, so it doesn't lock out.
    if (reason or "down") == "down" then
        pcall(function()
            self:_recordDownLockout(pet)
        end)
    end
    if self._logger then
        self._logger:Info("Pet left the fight", { pet = pet.Name, reason = reason or "down" })
    end
end

-- ===== #179 Down-lockout integration (pure logic in Shared/Game/PetLockout) =====

function EnemyService:_dataService()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, svc = pcall(function()
        return locator:Get("DataService")
    end)
    return ok and svc or nil
end

function EnemyService:_lockoutCfg()
    local sq = self._squadConfig or {}
    return {
        pet_lockout_seconds = (sq.down_lockout and sq.down_lockout.pet_lockout_seconds) or 300,
        slot_lock_seconds = (sq.slot_recovery and sq.slot_recovery.down_cooldown_seconds) or 60,
    }
end

-- Identity for the lockout: SPECIAL pets (huges/exclusives) lock by their UID; STACKED pets lock by
-- <id:variant> COUNT (no per-unit id). Tagged onto the model at spawn by PetHandler.
local function petLockEntry(pet)
    if pet:GetAttribute("LockoutSpecial") and pet:GetAttribute("LockoutUid") then
        return { kind = "special", uid = tostring(pet:GetAttribute("LockoutUid")) }
    end
    local key = pet:GetAttribute("LockoutKey")
    if not key or key == "" then
        local t = pet:GetAttribute("PetType")
        local v = pet:GetAttribute("Variant") or pet:GetAttribute("PetVariant")
        key = tostring(t) .. ":" .. tostring(v)
    end
    return { kind = "stack", stackKey = key }
end

-- The player who owns this pet folder + their profile data.
function EnemyService:_petOwnerData(pet)
    local folder = pet.Parent
    local player = folder and Players:FindFirstChild(folder.Name)
    local ds = player and self:_dataService()
    local data = ds and ds.GetData and ds:GetData(player)
    return player, data
end

-- Record a down into the player's persisted lockout state.
function EnemyService:_recordDownLockout(pet)
    local _, data = self:_petOwnerData(pet)
    if not data then
        return
    end
    local entry = petLockEntry(pet)
    local pn = pet:FindFirstChild("PositionNumber")
    entry.slot = "slot_" .. tostring((pn and pn.Value) or pet:GetAttribute("PositionNumber") or "?")
    local now = os.time()
    local state = PetLockout.prune(data.PetLockouts, now) -- housekeeping on write
    data.PetLockouts = PetLockout.recordDown(state, entry, now, self:_lockoutCfg())
end

-- Re-assert lockouts on the live squad each tick: a (re)spawned pet whose identity is still locked is
-- held DOWN with its REMAINING recovery — so going to Pets and re-teaming can't revive it for free.
function EnemyService:_enforceLockouts(now)
    local pp = Workspace:FindFirstChild("PlayerPets")
    if not pp then
        return
    end
    for _, folder in ipairs(pp:GetChildren()) do
        local player = Players:FindFirstChild(folder.Name)
        local ds = player and self:_dataService()
        local data = ds and ds.GetData and ds:GetData(player)
        local state = data and data.PetLockouts
        if state then
            for _, pet in ipairs(folder:GetChildren()) do
                if pet:IsA("Model") then
                    local entry = petLockEntry(pet)
                    -- SLOT lock (1 min): hold whatever pet occupies a slot whose pet just went down,
                    -- so a DIFFERENT pet (or a fresh stack sibling) can't fill it until the slot frees.
                    local pn = pet:FindFirstChild("PositionNumber")
                    local slotName = "slot_"
                        .. tostring((pn and pn.Value) or pet:GetAttribute("PositionNumber") or "?")
                    local slotUntil = (state.slots or {})[slotName] or 0
                    if slotUntil <= now then
                        slotUntil = 0
                    end
                    pet:SetAttribute("SlotLockUntil", slotUntil) -- UI: the SLOT bar (the 1-min timer)
                    -- IDENTITY lock: only the EXACT special (huge/exclusive) holds for the long pet
                    -- lockout. Stacks are fungible — they ride the slot timer + the availability pool
                    -- (deploy a sibling once the slot frees), so there's no per-unit 5-min hold here.
                    local idUntil = 0
                    if entry.kind == "special" then
                        local u = (state.pets or {})[entry.uid] or 0
                        if u > now then
                            idUntil = u
                        end
                    end
                    local holdUntil = math.max(idUntil, slotUntil)
                    if holdUntil > now then
                        if not pet:GetAttribute("CombatDowned") then
                            self:_holdDown(pet, holdUntil) -- a (re)spawned unit that's still locked
                        elseif (pet:GetAttribute("CooldownUntil") or 0) < holdUntil then
                            pet:SetAttribute("CooldownUntil", holdUntil) -- extend to the real lockout
                            pet:SetAttribute("DownedReason", "recovering")
                        end
                    end
                end
            end
            -- Replicate the pruned lockout pool to the client (the Pets window reads it for the
            -- ring-slot availability + red stack counts). Throttled to ~1s; cleared when empty.
            self:_replicateLockouts(player, state, now)
        end
    end
end

-- Push the (pruned) lockout pool to the player as a JSON attribute the client decodes. Throttled.
function EnemyService:_replicateLockouts(player, state, now)
    if not player then
        return
    end
    self._lockoutStampAt = self._lockoutStampAt or {}
    if (self._lockoutStampAt[player] or 0) > now then
        return
    end
    self._lockoutStampAt[player] = now + 1
    local pruned = PetLockout.prune(state, os.time())
    local hasAny = next(pruned.pets) or next(pruned.stacks) or next(pruned.slots)
    if not hasAny then
        if player:GetAttribute("PetLockouts") then
            player:SetAttribute("PetLockouts", nil)
        end
        return
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(pruned)
    end)
    if ok then
        player:SetAttribute("PetLockouts", encoded)
    end
end

-- Put a pet down WITHOUT resetting its recovery clock — keep the REMAINING recovery as CooldownUntil
-- so the HUD shows the true time left (not a fresh timer). Used only by the lockout enforcement.
function EnemyService:_holdDown(pet, untilEpoch)
    pet:SetAttribute("CombatDowned", true)
    pet:SetAttribute("DownedReason", "recovering")
    pet:SetAttribute("CooldownUntil", untilEpoch)
    local tid = pet:FindFirstChild("TargetID")
    if tid then
        tid.Value = 0
    end
    self:_clearEnduranceBar(pet)
end

-- Re-summon a recovered pet back onto the field (clears the downed state + heals it).
function EnemyService:_revivePet(pet)
    PetRevive.revive(pet)
    self:_clearEnduranceBar(pet)
end

-- One enemy hit on a pet (accumulate damage; down it if it crosses the ceiling).
function EnemyService:_hitPet(pet, def, now, eng, enemyLevel, petLevel)
    local power = self:_petPower(pet)
    local factor = self._combatConfig.pet_down_threshold_factor or 1
    local dmg = (def.attack and def.attack.damage) or 0
    -- Hit / crit roll. Hit chance from the level-diff Accuracy curve (a higher-level enemy lands
    -- more reliably on a lower pet, and vice versa) — same module the pets use. CombatRoll still
    -- owns the crit (chances from enemy_attack config).
    local enemyAtkRoll = eng.rolls and eng.rolls.enemy_attack
    local roll = CombatRoll.resolve({
        hit_chance = Accuracy.combatToHit(enemyLevel, petLevel, self._combatConfig.accuracy),
        crit_chance = enemyAtkRoll and enemyAtkRoll.crit_chance,
        crit_mult = enemyAtkRoll and enemyAtkRoll.crit_mult,
    }, math.random(), math.random())
    if roll.multiplier <= 0 then
        return -- missed
    end
    dmg = dmg * roll.multiplier
    -- Level scaling: a higher-level enemy hits harder; out-level it and it softens.
    dmg = dmg * LevelScale.factor(enemyLevel or 1, petLevel or 1, self._levelingConfig.scale)
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
    -- Ice buffer's team defense aura (penguin) — separate channel from a power's DefenseBuff
    -- above, so an aura + an activated shield STACK on the armor curve.
    if (pet:GetAttribute("TeamDefenseBuffUntil") or 0) > nowT then
        defense = defense + (pet:GetAttribute("TeamDefenseBuff") or 0)
    end
    dmg = CombatMath.mitigate(dmg, defense, self._combatConfig.armor_curve_k or 100)
    -- Combat-origin element: durability side. ice/desert take less, lava takes more — the mirror
    -- of the outgoing attack_mult (configs/combat_fx.lua origin.element_stats).
    dmg = dmg * self:_originTakenMult(pet)
    -- Absorption shield (Stone Skin etc.) soaks mitigated damage before any reaches
    -- endurance; it depletes as it absorbs.
    local shield = pet:GetAttribute("CombatShield") or 0
    if shield > 0 and dmg > 0 then
        local absorbed = math.min(shield, dmg)
        pet:SetAttribute("CombatShield", shield - absorbed)
        dmg = dmg - absorbed
        -- On-hit VFX is config-driven: if the absorbing power declares combat_vfx.on_hit = "dodge_pop"
        -- (e.g. Mirage Step), bump a tick so the client pops a floating "Dodge!" over the pet. A real
        -- shield has no on_hit, so it just soaks silently.
        if absorbed > 0 then
            local pid = pet:GetAttribute("CombatShieldPowerId")
            local def = pid and self._powersConfig.powers and self._powersConfig.powers[pid]
            local vfx = def and def.combat_vfx
            if vfx and vfx.on_hit == "dodge_pop" then
                pet:SetAttribute("DodgeTick", (pet:GetAttribute("DodgeTick") or 0) + 1)
            end
        end
        -- Mirage Veil (sandwalker signature): the veil heals a little each time it turns a blow
        -- aside (heal-on-evade) while MirageHealUntil is live — sustain that rewards being shielded.
        if absorbed > 0 and (pet:GetAttribute("MirageHealUntil") or 0) > nowT then
            local heal = pet:GetAttribute("MirageHealAmt") or 0
            local takenNow = pet:GetAttribute("CombatDamageTaken") or 0
            if heal > 0 and takenNow > 0 then
                pet:SetAttribute("CombatDamageTaken", math.max(0, takenNow - heal))
                pet:SetAttribute("HealFxUntil", os.time() + 2)
            end
        end
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

-- Incoming-damage multiplier from the pet's combat-origin element (CombatOrigin.statMod):
-- element from PetType (origin.pettype_element); lower = tankier. Default 1.
function EnemyService:_originTakenMult(pet)
    local cfg = self._originConfig or {}
    local petEl = cfg.pettype_element and cfg.pettype_element[pet:GetAttribute("PetType")]
    -- archetype nil: unify-to-player needs a server-published Archetype (not wired yet); with
    -- unify off this resolves to the pet's own element, which is the live behaviour today.
    local element = CombatOrigin.resolve(petEl, nil, cfg)
    return CombatOrigin.statMod(element, cfg).taken_mult
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

-- Idle LOITER (#217, Jason: enemies were "frozen statues" too): an unaware enemy
-- drifts around its HOME (where it stood when it last went idle) using the SAME
-- pure PetMeander state machine the idle pets use - server-side here, writing
-- entry.pos + MoveTarget so the client EnemyMotion lerp + gait render the stroll.
-- Aggro/chase takes over instantly (this only runs in the unaware branch), and
-- the meander state resets on aggro so a fight never teleports it back.
-- Config: combat.lua engagement.loiter (enabled/radius/speed/pause_min/pause_max).
function EnemyService:_loiter(entry, model, ePos, dt)
    local eng = self._combatConfig and self._combatConfig.engagement
    local cfg = eng and eng.loiter
    if not cfg or cfg.enabled == false then
        return
    end
    entry.home = entry.home or ePos
    entry.meander = entry.meander or PetMeander.newState(cfg, math.random)
    local ox, oz = PetMeander.step(entry.meander, dt or 0, cfg, math.random)
    local np = Vector3.new(entry.home.X + ox, ePos.Y, entry.home.Z + oz)
    local moveVec = Vector3.new(np.X - ePos.X, 0, np.Z - ePos.Z)
    entry.pos = np
    model:SetAttribute("MoveTarget", np)
    if moveVec.Magnitude > 0.02 then
        model:SetAttribute("MoveFace", np + moveVec.Unit * 4)
    end
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
    local perceptionRange = eng.perception_range or 70
    local leash = eng.leash_range or 90
    local def = self._enemiesConfig.enemies and self._enemiesConfig.enemies[entry.enemyId]
    -- Per-enemy attack range: RANGED foes (def.attack_range, e.g. 30+) hold at distance and fire,
    -- because the chase below stops at attack_range - attack_press. Melee/tank fall to the global
    -- default and close to bite range. This is what makes the "ranged" role read as ranged.
    local atk = (def and def.attack_range) or eng.attack_range or 11
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
            -- NO SQUAD, NO FIGHT (Jason's statue imps): enemies fight PETS, not
            -- players. A player with no live pet deployed is not a target — the
            -- pack keeps loitering around them instead of freezing mid-aggro on
            -- a fight that cannot happen. Resummon a pet and they engage.
            if player then
                local pf = Workspace:FindFirstChild("PlayerPets")
                local folder = pf and pf:FindFirstChild(player.Name)
                local live = false
                if folder then
                    for _, pet in ipairs(folder:GetChildren()) do
                        if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
                            live = true
                            break
                        end
                    end
                end
                if not live then
                    player = nil
                end
            end
            -- ONRAMP: a sub-threshold player is invisible to perception (enemy keeps loitering).
            -- TERRITORIAL: so is a player in a DIFFERENT area (across a wall) — no pulling through it.
            if
                player and (not self:_engagesCombat(player) or not self:_inTerritory(entry, player))
            then
                player = nil
            end
            if
                player
                and (d <= proxRange or EnemyAI.shouldNotice(d, perceptionRange, math.random()))
            then
                self:_setAggroOwner(entry, player.Name)
                entry.meander = nil
                entry.home = nil -- re-home wherever the fight leaves it
            end
        end
        if not entry.aggroPlayerName then
            self:_loiter(entry, model, ePos, dt)
            return -- still unaware: idle (loitering around home, not frozen)
        end
    end

    -- 2) Resolve the aggro'd player; drop aggro if gone or past the leash.
    local player = Players:FindFirstChild(entry.aggroPlayerName)
    local character = player and player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp or (hrp.Position - ePos).Magnitude > leash then
        self:_releasePets(targetId)
        self:_setAggroOwner(entry, nil)
        return
    end
    -- DRAFT RANGE (Jason: an enemy ~60 studs out kept re-conscripting his fresh
    -- revive the moment its grace expired): the leash keeps the enemy ANGRY, but
    -- it may only POINT THE SQUAD at itself while the player is inside the
    -- engagement radius. Farther out, the pets are released home — they re-engage
    -- the moment the player closes back in (or the enemy chases into range).
    if (hrp.Position - ePos).Magnitude > (eng.aggro_range or 45) then
        -- ...UNLESS something is actively hurting it (Jason's bunny-sniper
        -- exploit: assist-target a boss from beyond draft range and it could
        -- never bite back). A live attacker in the threat table keeps the whole
        -- combat tick running — the enemy bites whoever is hurting it.
        local attacker = AggroTable.top(entry.aggro, 0.5, function(k)
            return typeof(k) == "Instance" and k.Parent ~= nil
        end)
        if not attacker then
            self:_releasePets(targetId)
            return
        end
    end

    -- 3) Aggro: point the (non-downed) squad at this enemy + gather threat candidates.
    local petsFolder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not petsFolder then
        self:_releasePets(targetId)
        self:_setAggroOwner(entry, nil) -- nothing to fight: back to loitering
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
            -- (pets self-select their target in _assignPetTargets; the enemy no longer
            -- force-claims them — it just builds its aggro on the nearby squad here.)
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
        self:_setAggroOwner(entry, nil)
        return
    end
    entry.targetPet = targetPet -- published so co-attackers can spread off each other (below)

    -- 4) CHASE the aggro target until in attack range. A tank/melee target orbits inside
    -- attack_range so the enemy just holds + bites it; a ranged target kites near the
    -- player, so the enemy has to close the gap. A ROOTED enemy can't move.
    local targetPos = self:_petPosition(targetPet, pfs)
    local rooted = (model:GetAttribute("RootedUntil") or 0) > os.time()
    local moveSpeed = rooted and 0 or ((def and def.move_speed) or eng.default_move_speed or 12)
    -- Press inside attack_range so the enemy closes into bite range instead of stalling
    -- on its edge (where a kiting target floats just out of reach).
    local chaseStop = math.max(1, atk - (eng.attack_press or 3))
    -- RING SEPARATION: instead of every enemy chasing the EXACT pet point (and piling on top of
    -- each other), each fans out to its own slot on a ring around the target — same distance
    -- (so proximity / threat / damage are unchanged), just spread by angle. Gather the other
    -- enemies attacking THIS pet and let RingSeparate nudge us tangentially off them.
    local others = {}
    for _, e in pairs(self._enemies) do
        if e ~= entry and e.aggroPlayerName and e.targetPet == targetPet and e.pos then
            others[#others + 1] = { x = e.pos.X, z = e.pos.Z }
        end
    end
    local slot = RingSeparate.point(
        { x = ePos.X, z = ePos.Z },
        { x = targetPos.X, z = targetPos.Z },
        others,
        chaseStop,
        eng.surround_gap or 6
    )
    local chaseTo = Vector3.new(slot.x, targetPos.Y, slot.z)
    local np = EnemyAI.chaseStep(
        { x = ePos.X, y = ePos.Y, z = ePos.Z },
        { x = chaseTo.X, y = chaseTo.Y, z = chaseTo.Z },
        moveSpeed,
        dt or 0.15,
        0 -- the slot already sits at bite range, so close all the way onto it
    )
    if math.abs(np.x - ePos.X) > 1e-3 or math.abs(np.z - ePos.Z) > 1e-3 then
        local newPos = Vector3.new(np.x, np.y, np.z)
        -- face the TARGET it's biting (the pet), not its movement slot
        local faceTarget = Vector3.new(targetPos.X, np.y, targetPos.Z)
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

    -- Always face the current aggro target, even when standing still in bite range, so the
    -- enemy visibly turns to whoever it's attacking (the client lerps toward MoveFace). Faces the
    -- TARGET (the pet), not the ring slot it's standing on, so a fanned-out pack still looks inward.
    model:SetAttribute("MoveFace", Vector3.new(targetPos.X, ePos.Y, targetPos.Z))

    -- 5) ATTACK: bite the highest-aggro pet that is CURRENTLY within attack range — not
    -- only the chase target. The enemy may be pursuing an unreachable top-aggro pet (a
    -- ranged kiter), but anything in its face (the melee/tank orbiting it) still gets hit.
    local biteTarget = AggroTable.top(entry.aggro, 0, function(k)
        return valid[k] == true and (self:_petPosition(k, pfs) - ePos).Magnitude <= atk
    end)
    entry.nextAttack = entry.nextAttack or 0
    if biteTarget and now >= entry.nextAttack then
        local enemyLevel = model:GetAttribute("Level") or 1
        -- Pet defends at its owner's EFFECTIVE level (teaming seam), same value its own attacks use.
        local petLevel = player:GetAttribute("EffectiveLevel")
            or biteTarget:GetAttribute("Level")
            or (player:GetAttribute("Level") or 1)
        self:_hitPet(biteTarget, def, now, eng, enemyLevel, petLevel)
        entry.nextAttack = now + ((def and def.attack and def.attack.cadence) or 1.5)
        -- Broadcast the swing's VISUAL (damage is already applied above; the FX is just the swing,
        -- exactly like the pets' Combat_PetHit). Fired on EVERY attack so enemies attack the same
        -- way pets do: ranged -> a themed bolt enemy->pet, melee -> an impact at the pet. The client
        -- (EnemyMotion -> CombatHitFX) is the same path the pets use. To all clients = shared world.
        local isRanged = def and (def.role == "ranged" or def.bolt_kind ~= nil) or false
        pcall(function()
            Signals.Combat_EnemyHit:FireAllClients({
                enemy = model,
                target = biteTarget,
                ranged = isRanged,
                kind = def and def.bolt_kind,
                crit = biteTarget:GetAttribute("LastHitCrit") == true,
            })
        end)
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

-- Enemy regen pass (Jason: "enemies and pets are essentially supposed to be the exact
-- same mechanic" — but enemies never healed at all): once an enemy has gone
-- enemy_regen.delay_seconds without taking damage, it trickles HP back at
-- enemy_regen.partial_per_second (a THIRD of the pet rate). Damage detection is
-- self-contained: the pass watches each entry's HP for decreases instead of hooking
-- every damage path, so DoTs/AoEs/splash all reset the delay automatically.
function EnemyService:_enemyRegenPass(now, dt, eng)
    local cfg = eng.enemy_regen
    if not cfg then
        return
    end
    local delay = tonumber(cfg.delay_seconds) or 5
    local perSec = tonumber(cfg.partial_per_second) or 0.5
    for _, entry in pairs(self._enemies) do
        local model = entry.model
        if model and model.Parent then
            local hp = model:GetAttribute("HP") or 0
            local maxHp = model:GetAttribute("MaxHP") or hp
            if hp > 0 then
                if entry.lastSeenHp and hp < entry.lastSeenHp then
                    entry.lastDamagedAt = now
                end
                if hp < maxHp and now - (entry.lastDamagedAt or 0) >= delay then
                    hp = math.min(maxHp, hp + perSec * dt)
                    model:SetAttribute("HP", hp)
                end
                entry.lastSeenHp = hp
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

-- Admin testing: force a slot's pet DOWN with reason "down" so the full lockout (uid 5-min / slot
-- 1-min / Spirit Form) fires WITHOUT needing enemies on screen. Admin-gated (IsAdmin attribute).
function EnemyService:AdminKillPet(player, payload)
    if player:GetAttribute("IsAdmin") ~= true then
        return
    end
    local slot = tonumber(type(payload) == "table" and payload.slot or payload)
    if not slot then
        return
    end
    local pet = self:_findPlayerPetBySlot(player, slot)
    if pet and not pet:GetAttribute("CombatDowned") then
        self:_downPet(pet, os.clock(), self._combatConfig.engagement or {}, "down")
    end
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

-- A buffer pet's team aura (configs/pet_roles.lua support_auras, keyed by PetType — a
-- `SupportAura` model attribute can override later), or nil. The returned table carries
-- `.kind` (heal | defense | offense | yield) + that flavour's tuning knobs.
function EnemyService:_petAura(pet)
    local list = self:_petAuras(pet)
    return list and list[1] or nil
end

-- ALL of a pet's auras (creator pets carry the full buffer set — config may be a list).
function EnemyService:_petAuras(pet)
    local override = pet:GetAttribute("SupportAura")
    if type(override) == "string" and self._petRoles and self._petRoles.support_auras then
        local a = self._petRoles.support_auras[override]
        if a then
            return a.kind and { a } or a
        end
    end
    return SupportAura.aurasFor(pet:GetAttribute("PetType"), self._petRoles)
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

-- Does this pet provide a heal aura itself? Healers are excluded as aura-heal TARGETS so a
-- support pet can't passively mend itself (Jason: a self-healing Colorado was unkillable). The
-- healer is meant to be the vulnerable priority target you protect — out-of-combat _regenPass
-- still recovers it, and a player-cast heal power can deliberately top it up.
function EnemyService:_isHealer(pet)
    for _, aura in ipairs(self:_petAuras(pet) or {}) do
        if aura.kind == "heal" then
            return true
        end
    end
    return false
end

-- Heal aura (Grass / bunny): mend the most-hurt non-downed ally in the squad — reduce its
-- accumulated CombatDamageTaken. The squad healer keeps the tank up. Healers themselves are NOT
-- valid targets (no passive self-heal), so a lone support pet can still go down.
function EnemyService:_auraHeal(folder, heal, vmult)
    local factor = self._combatConfig.pet_down_threshold_factor or 1
    local target, worst
    for _, ally in ipairs(folder:GetChildren()) do
        if
            ally:IsA("Model")
            and not ally:GetAttribute("CombatDowned")
            and not self:_isHealer(ally)
        then
            local taken = ally:GetAttribute("CombatDamageTaken") or 0
            if taken > 0 and (not worst or taken > worst) then
                worst, target = taken, ally
            end
        end
    end
    if not target then
        return
    end
    -- Heal a FRACTION of the target's pool (keeps numbers proportional on the ~100 scale)
    -- — or a flat `amount` if configured instead.
    local pool = PetEndurance.maxEndurance(self:_petPower(target), factor)
    local healAmt = heal.fraction and (pool * heal.fraction) or (heal.amount or 0)
    healAmt = healAmt * (tonumber(vmult) or 1) -- variant-scaled (golden/rainbow mend more)
    local newTaken = math.max(0, (target:GetAttribute("CombatDamageTaken") or 0) - healAmt)
    target:SetAttribute("CombatDamageTaken", newTaken)
    if newTaken <= 0 then
        self:_clearEnduranceBar(target)
    else
        self:_updateEnduranceBar(target, newTaken, self:_petPower(target), factor)
    end
    -- Visual tell: blinking heal badge (HealFxUntil) + world heal puff, so an instant heal
    -- is visible even though it has no duration.
    local fxSec = (
        self._combatConfig.engagement and self._combatConfig.engagement.instant_fx_seconds
    ) or 3
    target:SetAttribute("HealFxUntil", os.time() + fxSec)
    self:_spawnHealVisual(target)
    -- Floating green heal number — shared world effect (Jason: team effect game).
    if healAmt >= 1 then
        Signals.Combat_Heal:FireAllClients({ target = target, amount = math.floor(healAmt + 0.5) })
    end
end

-- Defense aura (Ice / penguin): a short-lived TeamDefenseBuff on EVERY ally. Consumed in
-- _hitPet, added on the armor curve (separate from a power's DefenseBuff, so they stack).
function EnemyService:_auraDefense(folder, aura, count, weight)
    -- weight = variant-scaled buffer units (falls back to count for callers without it)
    local amount = (tonumber(aura.amount) or 0) * (weight or count or 1)
    local until_ = os.time() + (tonumber(aura.duration) or 3)
    for _, ally in ipairs(folder:GetChildren()) do
        if ally:IsA("Model") and not ally:GetAttribute("CombatDowned") then
            ally:SetAttribute("TeamDefenseBuff", amount)
            ally:SetAttribute("TeamDefenseBuffUntil", until_)
            ally:SetAttribute("TeamDefenseBuffStacks", count or 1) -- # contributing buffers (badge pile)
        end
    end
end

-- A team player-attribute buff (Lava offense -> PetTeamDamageBuff in _mine; Desert yield ->
-- CoinYieldBuff in BreakableSpawner). Short-lived + refreshed each interval, on a channel
-- separate from Powers so an aura stacks with an activated power buff.
function EnemyService:_auraPlayerBuff(folder, attr, aura, count, weight)
    local owner = Players:FindFirstChild(folder.Name)
    if not owner then
        return
    end
    -- Stored as a multiplier; each buffer contributes (mult - 1) x its VARIANT multiplier
    -- (weight = sum of variant units), so buffers stack additively and a rainbow counts
    -- 1.5x a basic. The consumer sums this with same-axis powers via BuffStack (axis cap).
    local frac = ((tonumber(aura.mult) or 1) - 1) * (weight or count or 1)
    owner:SetAttribute(attr, 1 + frac)
    owner:SetAttribute(attr .. "Until", os.time() + (tonumber(aura.duration) or 3))
    -- the PLAYER is the buffed entity — surface how many buffers contribute (Jason:
    -- "I have buffed three times... the player should 100% be stacked")
    owner:SetAttribute(attr .. "Stacks", count or 1)
end

-- Stamp a per-pet DISPLAY marker on every ally so the squad cards can show the support buff
-- icon (offense/yield ride the PLAYER attr, which the cards can't read per-pet). Display-only.
function EnemyService:_stampAuraFx(folder, fxAttr, aura, count)
    local until_ = os.time() + (tonumber(aura.duration) or 3)
    for _, ally in ipairs(folder:GetChildren()) do
        if ally:IsA("Model") and not ally:GetAttribute("CombatDowned") then
            ally:SetAttribute(fxAttr, until_)
            ally:SetAttribute(fxAttr .. "Stacks", count or 1) -- # contributing buffers (badge pile)
        end
    end
end

-- Buffer pets (configs/pet_roles support_auras) project a team aura every `interval`s while
-- deployed + alive. One flavour per zone: heal (Grass), defense (Ice), offense (Lava),
-- yield (Desert). The non-heal buffs ride short-lived "Team*" attributes consumed downstream.
function EnemyService:_supportPass(now)
    local playerPets = Workspace:FindFirstChild("PlayerPets")
    if not playerPets then
        return
    end
    -- Per-folder, per-KIND interval gate so the AGGREGATED aura pulses once per interval (not once
    -- per buffer). Keyed by player name -> { kind -> nextTime }.
    self._supportAt = self._supportAt or {}
    for _, folder in ipairs(playerPets:GetChildren()) do
        -- Count live buffers of each kind so multiple buffers of the same kind STACK additively
        -- (2 meerkats => 2x the coin-yield contribution, clamped by the axis cap downstream).
        -- count = # contributing buffers (badge piles); weight = variant-scaled units
        -- (basic 1.0 / golden 1.25 / rainbow 1.5 — the math multiplier downstream)
        local vmults = self._petRoles and self._petRoles.variant_effect_multipliers or {}
        local counts, weights, rep = {}, {}, {}
        for _, pet in ipairs(folder:GetChildren()) do
            if pet:IsA("Model") and pet.PrimaryPart and not pet:GetAttribute("CombatDowned") then
                local vmult = tonumber(vmults[pet:GetAttribute("PetVariant")]) or 1
                for _, aura in ipairs(self:_petAuras(pet) or {}) do
                    if aura.kind then
                        counts[aura.kind] = (counts[aura.kind] or 0) + 1
                        weights[aura.kind] = (weights[aura.kind] or 0) + vmult
                        rep[aura.kind] = rep[aura.kind] or aura
                    end
                end
            end
        end
        local gate = self._supportAt[folder.Name]
        if not gate then
            gate = {}
            self._supportAt[folder.Name] = gate
        end
        for kind, count in pairs(counts) do
            local aura = rep[kind]
            local weight = weights[kind] or count
            if not gate[kind] or now >= gate[kind] then
                gate[kind] = now + (aura.interval or 1.5)
                if kind == "heal" then
                    for _ = 1, count do -- N healers => N mends (variant scales each mend)
                        self:_auraHeal(folder, aura, weight / count)
                    end
                elseif kind == "defense" then
                    self:_auraDefense(folder, aura, count, weight)
                elseif kind == "offense" then
                    self:_auraPlayerBuff(folder, "PetTeamDamageBuff", aura, count, weight)
                    self:_stampAuraFx(folder, "OffenseFxUntil", aura, count)
                elseif kind == "yield" then
                    self:_auraPlayerBuff(folder, "CoinYieldBuff", aura, count, weight)
                    self:_stampAuraFx(folder, "YieldFxUntil", aura, count)
                elseif kind == "buff" then
                    -- GENERIC aura (Jason: "keep it configurable and flexible") — the
                    -- config declares the attribute and WHO it targets:
                    --   { kind = "buff", attr = "MoveSpeedBuff", mult = 1.2,
                    --     target = "player" | "pets" | "both", interval, duration }
                    -- player: multiplier+Stacks on the owner (bar badge shows xN);
                    -- pets:   multiplier stamped per ally (squad badge per pet).
                    -- NOTE: an attr is inert until something CONSUMES it (BuffStack
                    -- axis, EggService, movement...) — wiring the consumer is the only
                    -- per-buff code.
                    local target = aura.target or "player"
                    local until_ = os.time() + (tonumber(aura.duration) or 3)
                    if aura.attr and (target == "player" or target == "both") then
                        self:_auraPlayerBuff(folder, aura.attr, aura, count, weight)
                    end
                    if aura.attr and (target == "pets" or target == "both") then
                        for _, ally in ipairs(folder:GetChildren()) do
                            if ally:IsA("Model") and not ally:GetAttribute("CombatDowned") then
                                ally:SetAttribute(aura.attr, tonumber(aura.mult) or 1)
                                ally:SetAttribute(aura.attr .. "Until", until_)
                            end
                        end
                    end
                    -- providers always wear their single caster marker
                    for _, ally in ipairs(folder:GetChildren()) do
                        if ally:IsA("Model") and not ally:GetAttribute("CombatDowned") then
                            local provides = false
                            for _, a in ipairs(self:_petAuras(ally) or {}) do
                                if a.kind == "buff" and a.attr == aura.attr then
                                    provides = true
                                end
                            end
                            if provides then
                                ally:SetAttribute((aura.fx or aura.attr) .. "FxUntil", until_)
                                ally:SetAttribute((aura.fx or aura.attr) .. "FxUntilStacks", 1)
                            end
                        end
                    end
                elseif kind == "rage" then
                    -- RAGE (bear): an inherent power a pet uses on ITSELF — per-pet,
                    -- never aggregated. The RULES (enrage gate + variant-scaled
                    -- multiplier) live in ONE place — SupportAura.rageFraction — and
                    -- BattleSim consumes the same function, so live and simulated rage
                    -- cannot drift (Jason: "the same unified code path"). This branch
                    -- is only the live plumbing: read endurance, stamp attribute + FX.
                    -- The buff/FX expire via Until, so cooling off (regen above the
                    -- threshold) lets rage fade on its own. Consumer: PetFollowService
                    -- adds RageDamageBuff to the additive pet_damage axis.
                    local factor = self._combatConfig.pet_down_threshold_factor or 1
                    local until_ = os.time() + (tonumber(aura.duration) or 3)
                    for _, ally in ipairs(folder:GetChildren()) do
                        if ally:IsA("Model") and not ally:GetAttribute("CombatDowned") then
                            local frac = PetEndurance.healthFraction(
                                ally:GetAttribute("CombatDamageTaken") or 0,
                                self:_petPower(ally),
                                factor
                            )
                            local vmult = tonumber(vmults[ally:GetAttribute("PetVariant")]) or 1
                            local rageF =
                                SupportAura.rageFraction(self:_petAuras(ally), frac, vmult)
                            if rageF > 0 then
                                ally:SetAttribute("RageDamageBuff", 1 + rageF)
                                ally:SetAttribute("RageDamageBuffUntil", until_)
                                ally:SetAttribute("RageFxUntil", until_)
                                ally:SetAttribute("RageFxUntilStacks", 1)
                            end
                        end
                    end
                elseif kind == "luck" then
                    -- lucky-rabbit aura: hatch luck for the PLAYER (the buff already
                    -- targets the player). Display: stamp ONLY the providing bunnies —
                    -- stamping the whole squad implied the PETS were lucky (Jason:
                    -- "luck should be given to the player"). The player-side tells are
                    -- the green clover bar badge + the Active Buffs Luck row.
                    self:_auraPlayerBuff(folder, "HatchLuckBuff", aura, count, weight)
                    local until_ = os.time() + (tonumber(aura.duration) or 3)
                    for _, ally in ipairs(folder:GetChildren()) do
                        if ally:IsA("Model") and not ally:GetAttribute("CombatDowned") then
                            local allyHasLuck = false
                            for _, a in ipairs(self:_petAuras(ally) or {}) do
                                if a.kind == "luck" then
                                    allyHasLuck = true
                                end
                            end
                            if allyHasLuck then
                                ally:SetAttribute("LuckFxUntil", until_)
                                -- each bunny is ONE caster: a single clover marker, not
                                -- a pile (the STACK belongs on the buffed PLAYER)
                                ally:SetAttribute("LuckFxUntilStacks", 1)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Each non-downed pet picks its enemy target: the player's ASSIST target if set, else
-- the live enemy most aggro'd AT this pet (reciprocal — fight what's fighting you, which
-- naturally spreads the squad), else the nearest engaged enemy. With no enemies it leaves
-- the pet alone so AutoTarget mining continues.
function EnemyService:_assignPetTargets(eng)
    local playerPets = Workspace:FindFirstChild("PlayerPets")
    if not playerPets then
        return
    end
    local live = {}
    local any = false
    for tid, entry in pairs(self._enemies) do
        if entry.model and entry.model.Parent and (entry.model:GetAttribute("HP") or 0) > 0 then
            live[tid] = entry
            any = true
        end
    end
    if not any then
        return -- no enemies: don't touch targets (mining/AutoTarget owns them)
    end
    local pfs = self:_petFollowService()
    local aggroRange = eng.aggro_range or 45
    for _, folder in ipairs(playerPets:GetChildren()) do
        local player = Players:FindFirstChild(folder.Name)
        -- ONRAMP: a sub-threshold player's pets never auto-pick an enemy — they stay on mining /
        -- AutoTarget, so early levels are peaceful even with enemies loitering nearby.
        if not self:_engagesCombat(player) then
            continue
        end
        local assist = player and player:GetAttribute("CombatAssistTarget")
        for _, pet in ipairs(folder:GetChildren()) do
            local tid = pet:FindFirstChild("TargetID")
            local tt = pet:FindFirstChild("TargetType")
            if
                pet:IsA("Model")
                and pet.PrimaryPart
                and not pet:GetAttribute("CombatDowned")
                and tid
                and tt
            then
                local chosen
                if assist and assist ~= 0 and live[assist] then
                    chosen = assist -- player-directed (assist target always wins)
                else
                    -- per-pet target priority (TargetPriority): build the in-range candidates with
                    -- the data the modes need, then pick by the pet's mode (attr -> config default).
                    -- A KITING pet (ranged/support/control) holds position, so it can only auto-pick
                    -- enemies within its OWN attack_range — never one it can't reach. A chaser
                    -- (melee/tank) advances, so it considers the whole aggro range. (A player ASSIST
                    -- target bypasses this and will advance, handled above.)
                    local roles = self._petRoles
                    local roleId = pet:GetAttribute("PetRole")
                        or (roles and roles.by_type and roles.by_type[pet:GetAttribute("PetType")])
                        or (roles and roles.default)
                    local roleDef = roles and roles.roles and roles.roles[roleId]
                    local kites = roleDef
                        and (roleDef.kite or (tonumber(roleDef.standoff) or 0) > 0)
                    local reach = (kites and roleDef and tonumber(roleDef.attack_range))
                        or aggroRange
                    local petPos = self:_petPosition(pet, pfs)
                    local candidates = {}
                    for etid, entry in pairs(live) do
                        local d = (entry.pos - petPos).Magnitude
                        -- TERRITORIAL: pets only auto-pick foes in the player's own area (no
                        -- reaching across a wall into another biome's pack).
                        if d <= reach and self:_inTerritory(entry, player) then
                            local edef = self._enemiesConfig.enemies
                                and self._enemiesConfig.enemies[entry.enemyId]
                            candidates[#candidates + 1] = {
                                id = etid,
                                distance = d,
                                strength = (entry.model and entry.model:GetAttribute("Level")) or 1,
                                hp = (entry.model and entry.model:GetAttribute("HP")) or 0,
                                aggro = AggroTable.get(entry.aggro, pet),
                                teamDamage = (edef and edef.attack and edef.attack.damage) or 0,
                            }
                        end
                    end
                    local mode = pet:GetAttribute("TargetPriority")
                    if not TargetPriority.isMode(mode) then
                        mode = (eng.target_priority and eng.target_priority.default)
                            or TargetPriority.DEFAULT
                    end
                    chosen = TargetPriority.pick(candidates, mode)
                end
                if chosen then
                    if tt.Value ~= "Enemy" or tid.Value ~= chosen then
                        tt.Value = "Enemy"
                        local tw = pet:FindFirstChild("TargetWorld")
                        if tw then
                            tw.Value = ""
                        end
                        tid.Value = chosen
                    end
                elseif tt.Value == "Enemy" then
                    tid.Value = 0 -- enemy gone / out of range -> release to follow/mine
                end
            end
        end
    end
end

-- Enemy healers (enemies.lua auto_heal): restore HP to the most-hurt OTHER alive enemy
-- within range, on a cadence (mirrors the pet support role). Players can focus the healer
-- to flip the fight. Excludes self so a lone healer can still be brought down.
function EnemyService:_enemyHealPass(now)
    self._enemyHealAt = self._enemyHealAt or {}
    for tid, entry in pairs(self._enemies) do
        local model = entry.model
        if model and model.Parent and (model:GetAttribute("HP") or 0) > 0 then
            local def = self._enemiesConfig.enemies and self._enemiesConfig.enemies[entry.enemyId]
            local heal = def and def.auto_heal
            if
                heal
                and (heal.amount or 0) > 0
                and (not self._enemyHealAt[tid] or now >= self._enemyHealAt[tid])
            then
                self._enemyHealAt[tid] = now + (heal.interval or 2)
                local range = heal.range or 45
                local target, worstFrac
                for otid, oe in pairs(self._enemies) do
                    if otid ~= tid and oe.model and oe.model.Parent then
                        local hp = oe.model:GetAttribute("HP") or 0
                        local maxhp = oe.model:GetAttribute("MaxHP") or 1
                        if hp > 0 and hp < maxhp and (oe.pos - entry.pos).Magnitude <= range then
                            local frac = hp / maxhp
                            if not worstFrac or frac < worstFrac then
                                worstFrac, target = frac, oe.model
                            end
                        end
                    end
                end
                if target then
                    local maxhp = target:GetAttribute("MaxHP") or 1
                    local before = target:GetAttribute("HP") or 0
                    local after = math.min(maxhp, before + heal.amount)
                    target:SetAttribute("HP", after)
                    -- Same heal attribute pets carry (SquadHud reads HealFxUntil) — so the EnemyHud
                    -- lights a HEAL badge on the mended foe via the SHARED StatusBadges path. The
                    -- enemy speaks the pet status vocabulary; one renderer reads both.
                    target:SetAttribute("HealFxUntil", os.time() + 2)
                    self:_spawnHealVisual(target) -- works on any model with a PrimaryPart
                    -- Green heal number to ALL clients, so you SEE the enemy healer working
                    -- (the "kill the healer to flip the fight" tell).
                    local healed = math.floor(after - before + 0.5)
                    if healed >= 1 then
                        Signals.Combat_Heal:FireAllClients({ target = target, amount = healed })
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
    self:_enemyRegenPass(now, dt, eng)
    self:_supportPass(now)
    self:_enemyHealPass(now)
    self:_enforceLockouts(nowTime) -- #179: hold re-teamed/locked pets down for their recovery
    local idleDespawn = eng.despawn_idle_seconds or 0
    for targetId, entry in pairs(self._enemies) do
        local model = entry.model
        if model and model.Parent and (model:GetAttribute("HP") or 0) > 0 then
            -- Engagement timer: while it holds aggro it's IN a fight — refresh the clock so the
            -- idle-despawn below never fires mid-battle. When aggro drops (leashed / player fled /
            -- never engaged), the clock runs; past despawn_idle_seconds the enemy leaves the field.
            if entry.aggroPlayerName then
                entry.lastActiveAt = now
            elseif
                idleDespawn > 0
                and entry.everEngaged -- only retire enemies that ENGAGED then got abandoned;
                and (now - (entry.lastActiveAt or now)) > idleDespawn
            then
                -- never-engaged loiterers persist as ambiance (the combat-onramp preview for
                -- low-level players); the spawner's max_alive still caps how many can pile up.
                self:_despawnEnemy(targetId)
            end
            if self._enemies[targetId] then -- still alive (not just despawned)
                self:_engageEnemy(entry, targetId, now, eng, dt)
                self:_updateDebuffBadges(model, nowTime)
            end
        end
    end
    -- After enemies have updated their aggro this tick, let each pet self-select its
    -- enemy target (assist > most-aggro'd-at-it > nearest engaged).
    self:_assignPetTargets(eng)
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
-- opts (optional, for test spreads): { forward = studs, right = studs } offsets the spawn in the
-- player's local frame, on top of the base spawn distance.
function EnemyService:SpawnEnemy(player, enemyId, opts)
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
    local right = Vector3.new(flat.Z, 0, -flat.X) -- perpendicular on the ground plane
    local fwd = (opts and tonumber(opts.forward)) or 0
    local rt = (opts and tonumber(opts.right)) or 0
    local position = hrp.Position + flat * (dist + fwd) + right * rt + Vector3.new(0, 3, 0)
    if opts and typeof(opts.position) == "Vector3" then
        position = opts.position -- absolute placement (map spawners), not player-relative
    end

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
        lastActiveAt = os.clock(), -- engagement timer seed (idle-despawn clock; refreshed while aggro'd)
        homeArea = self:_areaAt(position), -- territorial: only engages players in this area
    }
    model:SetAttribute("MoveTarget", position)
    model:SetAttribute("MoveFace", Vector3.new(hrp.Position.X, position.Y, hrp.Position.Z))

    -- Effective level = base (config `level`, else the spawning player's level so a
    -- standard mob reads "even"/white) + the elite rank offset (lieutenant/boss read
    -- higher). Drives damage scaling + the difficulty colour label.
    local playerLevel = player:GetAttribute("Level") or 1
    local rankOff = (
        self._levelingConfig.rank_offset and self._levelingConfig.rank_offset[def.tier]
    ) or 0
    model:SetAttribute("Level", LevelScale.effectiveLevel(def.level or playerLevel, rankOff))

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

    -- Spawned enemies engage the triggering player immediately (skip the perception roll — the
    -- combat tick handles chase + threat targeting from here). Via the helper so the replicated
    -- AggroOwner attribute is stamped too (else the enemy chases + attacks but never shows on the
    -- client EnemyHud). ONRAMP: a sub-threshold trigger (a low-level player walking a spawner) gets
    -- a wave that LOITERS instead — visible in the world, but it won't aggress until they hit L5+.
    if self:_engagesCombat(player) and self:_inTerritory(self._enemies[targetId], player) then
        self:_setAggroOwner(self._enemies[targetId], player.Name)
    end
    if self._logger then
        self._logger:Info("Enemy spawned", { enemyId = enemyId, targetId = targetId, hp = def.hp })
    end
    if opts and typeof(opts.home) == "Vector3" then
        model:SetAttribute("SpawnHome", opts.home) -- loiter anchor (map spawners)
    end
    return { ok = true, targetId = targetId, enemyId = enemyId, hp = def.hp, model = model }
end

return EnemyService
