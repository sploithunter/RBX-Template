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
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local AssetFetch = require(ReplicatedStorage.Shared.Utils.AssetFetch)

local PetEndurance = require(ReplicatedStorage.Shared.Game.PetEndurance)
local MeshAssembly = require(ReplicatedStorage.Shared.Assets.MeshAssembly)
local EnemyAI = require(ReplicatedStorage.Shared.Game.EnemyAI)
local PetMeander = require(ReplicatedStorage.Shared.Game.PetMeander)
local RingSeparate = require(ReplicatedStorage.Shared.Game.RingSeparate)
local AggroTable = require(ReplicatedStorage.Shared.Game.AggroTable)
local Allegiance = require(ReplicatedStorage.Shared.Game.Allegiance)
local AggroLeash = require(ReplicatedStorage.Shared.Game.AggroLeash)
local PowerIcons = require(ReplicatedStorage.Configs:WaitForChild("power_icons")) -- world debuff disc
local Sounds = require(ReplicatedStorage.Configs:WaitForChild("sounds")) -- positional hold/freeze SFX
local CombatRoll = require(ReplicatedStorage.Shared.Game.CombatRoll)
local Accuracy = require(ReplicatedStorage.Shared.Game.Accuracy)
local LevelScale = require(ReplicatedStorage.Shared.Game.LevelScale)
local ActiveSquad = require(ReplicatedStorage.Shared.Game.ActiveSquad)
local CombatMath = require(ReplicatedStorage.Shared.Game.CombatMath)
local CombatOrigin = require(ReplicatedStorage.Shared.Game.CombatOrigin)
local TargetPriority = require(ReplicatedStorage.Shared.Game.TargetPriority)
local SupportAura = require(ReplicatedStorage.Shared.Game.SupportAura)
local PetPowerView = require(ReplicatedStorage.Shared.Game.PetPowerView) -- effective combat power (empower carry pick)
local DamageOverTime = require(ReplicatedStorage.Shared.Game.DamageOverTime) -- DoT burn ticks
local OnHitEffects = require(ReplicatedStorage.Shared.Game.OnHitEffects) -- slow/shred on-hit math
local OverheadBar = require(ReplicatedStorage.Shared.UI.OverheadBar) -- shared enemy HP / pet endurance bar
local PetLockout = require(ReplicatedStorage.Shared.Game.PetLockout)
local ZoneResolver = require(ReplicatedStorage.Shared.Game.ZoneResolver)
local EnemyLeash = require(ReplicatedStorage.Shared.Game.EnemyLeash)
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
    -- Movement leash regions resolved from the live map parts (configs/enemy_leash). Each region
    -- is a union of footprint shapes; an enemy spawned inside one is confined to it (hard wall).
    self._leashConfig = self._configLoader:LoadConfig("enemy_leash")
    self._leashRegions = self:_buildLeashRegions(self._leashConfig)
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
        -- Transient focus: stamp an expiry so the order lapses (pets resume auto-targeting) instead
        -- of locking forever. Re-clicking refreshes it. Cleared when id == 0.
        if id ~= 0 then
            local engCfg = (self._combatConfig and self._combatConfig.engagement) or {}
            player:SetAttribute("CombatAssistUntil", os.clock() + (engCfg.assist_seconds or 5))
        else
            player:SetAttribute("CombatAssistUntil", nil)
        end
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
        entry.stuckTime = 0 -- fresh engagement: reset the anti-hang no-progress timer
        entry.lastTargetDist = nil
    end
    local model = entry.model
    if model and model.Parent then
        model:SetAttribute("AggroOwner", name or "")
        if not name then
            self:_publishAggroTarget(model, nil) -- disengaged: drop the red-beam ref
        end
    end
end

-- Publish the exact pet/character this enemy is currently biting as a replicated ObjectValue
-- ("AggroTargetRef"), so the client TargetBeams overlay can draw a red beam enemy->victim. This
-- is the only client-readable handle on entry.targetPet (a server-side table field).
function EnemyService:_publishAggroTarget(model, target)
    if not (model and model.Parent) then
        return
    end
    local ref = model:FindFirstChild("AggroTargetRef")
    if not ref then
        if target == nil then
            return
        end
        ref = Instance.new("ObjectValue")
        ref.Name = "AggroTargetRef"
        ref.Parent = model
    end
    ref.Value = target
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

-- Resolve configs/enemy_leash into { regionName -> { shapes } } by reading the live map parts.
-- box    -> the part's X/Z footprint (axis-aligned half-extents).
-- circle -> a disc at the part's position, radius = half its largest horizontal dimension.
-- A part that can't be found is skipped (logged), so a renamed map asset degrades gracefully.
function EnemyService:_buildLeashRegions(cfg)
    local regions = {}
    if not (cfg and cfg.regions) then
        return regions
    end
    local function resolvePart(path)
        local node = Workspace
        for segment in string.gmatch(path, "[^%.]+") do
            node = node and node:FindFirstChild(segment)
        end
        return node
    end
    for name, shapeDefs in pairs(cfg.regions) do
        local shapes = {}
        for _, def in ipairs(shapeDefs) do
            local part = resolvePart(def.part)
            if part and part:IsA("BasePart") then
                local p, s = part.Position, part.Size
                if def.shape == "circle" then
                    shapes[#shapes + 1] =
                        { kind = "circle", cx = p.X, cz = p.Z, r = math.max(s.X, s.Z) / 2 }
                else
                    shapes[#shapes + 1] =
                        { kind = "box", cx = p.X, cz = p.Z, halfX = s.X / 2, halfZ = s.Z / 2 }
                end
            elseif self._logger then
                self._logger:Warn("Leash part not found", { region = name, part = def.part })
            end
        end
        if #shapes > 0 then
            regions[name] = shapes
        end
    end
    return regions
end

-- The leash region (name) whose shape-union contains a spawn position, or nil if none. Stamped on
-- the enemy at spawn so the chase step can be clamped to the SAME pen it spawned in.
function EnemyService:_leashRegionAt(pos)
    if not pos then
        return nil
    end
    for name, shapes in pairs(self._leashRegions) do
        if EnemyLeash.inside(pos.X, pos.Z, shapes) then
            return name
        end
    end
    return nil
end

-- LEASH a chase step into the enemy's spawn region (a hard wall at the region boundary). The
-- region is a UNION of shapes (e.g. Grass mesh ∪ Spawn circle), so the enemy roams the whole pen
-- but can't leave it. Y untouched. An enemy with no resolved region is returned unchanged.
function EnemyService:_leashToHomeArea(entry, pos)
    local region = entry and entry.leashRegion
    local shapes = region and self._leashRegions[region]
    if not shapes then
        return pos
    end
    local inset = (self._leashConfig and self._leashConfig.inset) or 0
    local x, z = EnemyLeash.clamp(pos.X, pos.Z, shapes, inset)
    return Vector3.new(x, pos.Y, z)
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
    -- THE single combine path (shared with pets/gems/eggs): mesh + texture -> textured Model.
    local model, err = MeshAssembly.build(meshId, textureId, { partName = "Body" })
    local template
    if model then
        model.Parent = ServerStorage
        template = model
    elseif self._logger then
        self._logger:Warn(
            "Enemy mesh build failed; using procedural fallback",
            { mesh = tostring(meshId), error = tostring(err) }
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

    -- Enemy HP bar: the shared OverheadBar widget (same as the pet endurance bar, red fill).
    OverheadBar.create({
        adornee = body,
        name = "HealthBar",
        studsOffset = Vector3.new(0, height / 2 + 1.5, 0),
        fillColor = Color3.fromRGB(220, 70, 70), -- enemy = red
    })

    -- Name tag above the HP bar. The client (EnemyMotion) sets its text ("Name Lv N") and
    -- COLOUR by difficulty relative to the viewing player's level — so it's per-viewer.
    model:SetAttribute("DisplayName", def.display_name or enemyId)
    -- Role (tank/melee/ranged/support) so the client HUD can show the enemy's ARCHETYPE the same
    -- way pet cards do — uses the same role vocabulary as pets (pet_roles / power_icons role_symbol).
    model:SetAttribute("Role", def.role or "melee")
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
    self:_attachFillLight(model, body, def)
    self:_attachEnemyDecor(model, body, enemyId, def, targetId)
    return model
end

-- Internal FILL LIGHT (Jason): the dark biomes have almost no ambient, so a mesh's baked texture
-- reads gray/washed-out. A PointLight parented straight to the body (its centre is just inside the
-- mesh, so nothing visible) lifts the creature out of the murk. Range auto-scales to the model so a
-- whelp isn't over-lit and a boss isn't under-lit; shadows off (cheap on big waves). Config in
-- combat.lua engagement.fill_light; per-enemy `fill_light = false` disables, `= <number>` overrides
-- brightness.
function EnemyService:_attachFillLight(model, body, def)
    if not body or def.fill_light == false then
        return
    end
    local cfg = (self._combatConfig.engagement and self._combatConfig.engagement.fill_light) or {}
    if cfg.enabled == false then
        return
    end
    pcall(function()
        local maxExtent = 4
        local okE, sz = pcall(function()
            return model:GetExtentsSize()
        end)
        if okE and sz then
            maxExtent = math.max(sz.X, sz.Y, sz.Z)
        end
        local light = Instance.new("PointLight")
        light.Name = "FillLight"
        light.Brightness = (type(def.fill_light) == "number" and def.fill_light)
            or cfg.brightness
            or 1.75
        light.Range = math.clamp(maxExtent * (cfg.range_factor or 0.6), 6, 60)
        light.Color = Color3.new(1, 1, 1)
        light.Shadows = false -- keep it cheap on big waves
        light.Parent = body
    end)
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
                -- rare ENHANCEMENT drop at the DOWN site (identity revealed at pickup). Use entry.pos,
                -- NOT model.PrimaryPart.Position: the server never re-pivots the anchored enemy model
                -- (only the client interpolates it toward MoveTarget), so the model sits at its SPAWN
                -- CFrame server-side. entry.pos is the authoritative current position — the spot the
                -- enemy actually went down (Jason: drops were landing back at the spawn, not the kill).
                local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                local dropPos = entry.pos or (pp and pp.Position)
                if dropPos then
                    local locator = _G.RBXTemplateServices
                    local okSvc, drops = pcall(function()
                        return locator and locator:Get("DropService")
                    end)
                    if okSvc and drops and drops.TrySpawnEnhancementDrop then
                        pcall(function()
                            drops:TrySpawnEnhancementDrop(player, "enemy", dropPos)
                        end)
                        -- POTION drop (same odds as enhancements; independent roll)
                        if drops.TrySpawnPotionDrop then
                            pcall(function()
                                drops:TrySpawnPotionDrop(player, "enemy", dropPos)
                            end)
                        end
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
    -- ROBUST FALLBACK: pets are client-moved, so their server pivot sits at world ORIGIN (0,0,0)
    -- until a position report lands. NEVER gate combat off origin — that strands the squad 500+
    -- studs from every enemy (pets "do nothing" while a foe is on top of you). Pets cluster around
    -- their owner, so fall back to the OWNER's position: an adjacent enemy is then in range and the
    -- squad engages even if the report hiccups. Only with no owner do we use the (origin) pivot.
    local ownerName = pet.Parent and pet.Parent.Name
    local owner = ownerName and Players:FindFirstChild(ownerName)
    local char = owner and owner.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        return hrp.Position
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
    -- Pet endurance bar: the SAME shared OverheadBar widget as the enemy HP bar (green->red fill).
    if not pp:FindFirstChild("EnduranceBar") then
        OverheadBar.create({
            adornee = pp,
            name = "EnduranceBar",
            studsOffset = Vector3.new(0, 3.5, 0),
            bgColor = Color3.fromRGB(25, 25, 25),
            fillColor = Color3.fromRGB(70, 200, 90), -- pet = green (re-ramped by fraction below)
        })
    end
    local frac = PetEndurance.healthFraction(taken, power, factor)
    OverheadBar.setFraction(
        OverheadBar.fillOf(pp, "EnduranceBar"),
        frac,
        Color3.fromRGB(math.floor(215 * (1 - frac)) + 40, math.floor(195 * frac) + 30, 45)
    )
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
-- Rebuild the ground-snap exclude list once per tick: ignore dynamic gameplay objects (enemies,
-- ore, drops under Workspace.Game), pets, and player characters so a downcast hits only the map
-- floor. The authored biome floor lives outside Workspace.Game, so it is NOT filtered out.
function EnemyService:_refreshGroundExclude()
    local exclude = {}
    local game = Workspace:FindFirstChild("Game")
    if game then
        exclude[#exclude + 1] = game
    end
    local pets = Workspace:FindFirstChild("PlayerPets")
    if pets then
        exclude[#exclude + 1] = pets
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            exclude[#exclude + 1] = player.Character
        end
    end
    self._groundExclude = exclude
end

-- Raycast down to the floor at (x, z) and return the Y the enemy's pivot should sit at so the
-- body rests on the terrain (+ hoverHeight for flyers). Returns fallbackY if grounding is off or
-- the ray misses (e.g. over a void). self._groundExclude is rebuilt once per combat tick so a
-- single downcast ignores dynamic stuff (enemies/pets/characters/Game objects) and only hits the map.
function EnemyService:_groundedY(entry, x, z, fallbackY)
    local eng = self._combatConfig and self._combatConfig.engagement
    if eng and eng.ground_snap == false then
        return fallbackY
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = self._groundExclude or {}
    params.IgnoreWater = true
    -- Start well above the enemy's current/target Y so a creature stuck high in a cave still
    -- casts down to the floor below it; 1000 studs of reach covers any biome drop.
    local origin = Vector3.new(x, (fallbackY or 0) + 80, z)
    local hit = Workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
    if hit then
        return hit.Position.Y + (entry.halfHeight or 3) + (entry.hoverHeight or 0)
    end
    return fallbackY
end

function EnemyService:_loiter(entry, model, ePos, dt)
    local eng = self._combatConfig and self._combatConfig.engagement
    local cfg = eng and eng.loiter
    if not cfg or cfg.enabled == false then
        return
    end
    entry.home = entry.home or ePos
    entry.meander = entry.meander or PetMeander.newState(cfg, math.random)
    local ox, oz = PetMeander.step(entry.meander, dt or 0, cfg, math.random)
    local gx, gz = entry.home.X + ox, entry.home.Z + oz
    local gy = self:_groundedY(entry, gx, gz, ePos.Y)
    -- Ground dwellers don't WANDER up walls while loitering (flyers may, they fly): if the next
    -- meander step would mount a ledge, skip it and re-seed the wander to head a fresh direction.
    -- (Pursuit is different -- the chase path gets a jump-assist so they can climb OUT to a target.)
    local flyer = (entry.hoverHeight or 0) > 0
    if not flyer and (gy - ePos.Y) > (eng.ground_climb_max or 10) then
        entry.meander = PetMeander.newState(cfg, math.random)
        return
    end
    local np = Vector3.new(gx, gy, gz)
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

-- One alive enemy, per tick: PERCEIVE a player (distance x probability) to acquire aggro, CHASE the
-- aggro'd squad until in attack range, and bite the highest-THREAT pet in range (so a tank pet pulls
-- aggro). How long it stays angry as the squad flees is the LEASH (AggroLeash): pure decay — threat
-- bleeds faster the farther it chases (and once you leave its area), dropped hard only past give_up.
function EnemyService:_engageEnemy(entry, targetId, now, eng, dt)
    local model = entry.model
    -- Authoritative position lives in entry.pos (NOT the model pivot): the server
    -- never re-pivots the model after spawn, so its live CFrame is client-owned for
    -- smooth rendering (EnemyMotion). entry.pos drives all server-side combat math.
    local ePos = entry.pos or model:GetPivot().Position
    local perceptionRange = eng.perception_range or 70
    local def = entry.def
        or (self._enemiesConfig.enemies and self._enemiesConfig.enemies[entry.enemyId])
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
                        -- ALLEGIANCE GATE: only a HOSTILE live pet makes the player a target. A heaven
                        -- enemy ignores a heaven/neutral squad entirely (no aggro -> peaceful farming);
                        -- bring a hell pet and it perceives + engages. Hell enemies are hostile to all.
                        if
                            pet:IsA("Model")
                            and not pet:GetAttribute("CombatDowned")
                            and self:_enemyHostileToPet(entry, pet, player)
                        then
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

    -- 2) Resolve the aggro'd player + its live squad. Combat is fought against PETS, so ALL
    -- persistence is measured to the nearest live pet (not the player) — see AggroLeash. This is the
    -- fix for the old player-keyed leash/draft (45/90 studs): wrong reference frame, far too short.
    local player = Players:FindFirstChild(entry.aggroPlayerName)
    local petsFolder = player
        and Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not player or not petsFolder then
        self:_releasePets(targetId)
        self:_setAggroOwner(entry, nil) -- player/squad gone: back to loitering
        return
    end
    local aggroCfg = eng.aggro or {}

    -- Nearest live-pet distance drives the leash: locked-on while close, threat decays faster the
    -- farther the squad runs, hard drop past give_up_range (a teleport / world-hop takes the whole
    -- squad out of range at once -> instant give-up, so nothing chases you to another world).
    local nearestDist = math.huge
    for _, pet in ipairs(petsFolder:GetChildren()) do
        if pet:IsA("Model") and pet.PrimaryPart and not pet:GetAttribute("CombatDowned") then
            local d = (self:_petPosition(pet, pfs) - ePos).Magnitude
            if d < nearestDist then
                nearestDist = d
            end
        end
    end
    if nearestDist > (aggroCfg.give_up_range or 300) then
        self:_releasePets(targetId)
        self:_setAggroOwner(entry, nil)
        return
    end
    local inTerritory = self:_inTerritory(entry, player)

    -- 3) Aggro upkeep: DECAY the table (faster the farther the squad is, faster still once it has
    -- left the enemy's home area — AggroLeash.decayMult), then tick PASSIVE threat (× each pet's
    -- Threat stat, so a tank climbs fastest) + the proximity floor. `valid` = targetable attackers.
    AggroTable.decay(
        entry.aggro,
        dt or 0.15,
        (aggroCfg.decay_per_second or 4) * AggroLeash.decayMult(nearestDist, inTerritory, aggroCfg)
    )
    local valid = {}
    local proxRange = aggroCfg.proximity_range or 30
    local proxFloor = aggroCfg.proximity_floor or 6
    for _, pet in ipairs(petsFolder:GetChildren()) do
        if
            pet:IsA("Model")
            and pet.PrimaryPart
            and not pet:GetAttribute("CombatDowned")
            and self:_enemyHostileToPet(entry, pet, player) -- only attack pets it's hostile to
        then
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

    -- Target = the highest-aggro attacker still valid. Let go (AggroLeash.shouldDrop) only when the
    -- squad has teleported past give_up_range OR threat has bled below the disengage threshold (no
    -- valid target left). Within range the enemy keeps chasing as long as ANY threat remains, and the
    -- distance-scaled decay above is what eventually bleeds it to zero if you keep your distance —
    -- pure decay, no hard "locked on" zone.
    local targetPet = AggroTable.top(entry.aggro, aggroCfg.disengage_threshold or 0.5, function(k)
        return valid[k] == true
    end)
    if AggroLeash.shouldDrop(nearestDist, targetPet ~= nil, aggroCfg) then
        self:_releasePets(targetId)
        self:_setAggroOwner(entry, nil)
        return
    end
    entry.targetPet = targetPet -- published so co-attackers can spread off each other (below)
    self:_publishAggroTarget(model, targetPet) -- red-beam ref for the TargetBeams admin overlay

    -- 4) CHASE the aggro target until in attack range. A tank/melee target orbits inside
    -- attack_range so the enemy just holds + bites it; a ranged target kites near the
    -- player, so the enemy has to close the gap. A ROOTED enemy can't move.
    local targetPos = self:_petPosition(targetPet, pfs)
    -- CONTROL: HeldUntil = full mez (can't move OR attack — see the bite gate below); RootedUntil =
    -- snare (can't move, still bites). Either zeroes move speed. This is the controller's lockdown.
    local held = (model:GetAttribute("HeldUntil") or 0) > os.time()
    local rooted = held or (model:GetAttribute("RootedUntil") or 0) > os.time()
    local moveSpeed = rooted and 0 or ((def and def.move_speed) or eng.default_move_speed or 12)
    -- SLOW (graded control, Anvil pets): SlowUntil/SlowFactor reduce move speed without a full root,
    -- so a slowed pack still drifts toward the squad but stays parked in the AoE/plague. Stacks under
    -- a real root (which already zeroed speed above).
    if not rooted and (model:GetAttribute("SlowUntil") or 0) > os.time() then
        moveSpeed = OnHitEffects.slowSpeed(moveSpeed, model:GetAttribute("SlowFactor"))
    end
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
    local groundedY = self:_groundedY(entry, np.x, np.z, np.y)
    -- Vertical traversal while CHASING (the target is ahead, so an up-step is pursuit, not aimless
    -- wandering): steps DOWN and small step-ups (slopes / cave thresholds) are always fine. A bigger
    -- rise is a wall/lip -> JUMP-ASSIST up toward the target if the climb is modest (so they get OUT
    -- of the spawn cave and over ledges); only a genuinely tall wall blocks. Flyers ignore this and
    -- rise freely (they fly over). A pet that then drops below is just a step DOWN next tick, so an
    -- enemy that hopped onto a ledge self-recovers instead of getting marooned up there.
    local rise = groundedY - ePos.Y
    local flyer = (entry.hoverHeight or 0) > 0
    local wallAhead = false
    if not flyer and rise > (eng.ground_climb_max or 10) and rise > (eng.ground_jump_max or 28) then
        wallAhead = true
        groundedY = ePos.Y -- too tall to scale: hold at the base (still faces + attacks below)
    end
    if not wallAhead and (math.abs(np.x - ePos.X) > 1e-3 or math.abs(np.z - ePos.Z) > 1e-3) then
        local newPos = Vector3.new(np.x, groundedY, np.z)
        -- LEASH: an enemy can chase up to the edge of the area it spawned in, but no further — a
        -- hard wall at the area footprint. Stops desert foes from trailing the player across the
        -- whole map. Clamps the step's X/Z into the home-area box (config bounds == the area mesh's
        -- bounding box); enemies with no resolved home area (spawned off-grid) are left unclamped.
        newPos = self:_leashToHomeArea(entry, newPos)
        np.x, np.z = newPos.X, newPos.Z
        -- face the TARGET it's biting (the pet), not its movement slot
        local faceTarget = Vector3.new(targetPos.X, groundedY, targetPos.Z)
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

    -- ANTI-HANG (Jason: "one got away ... is this a hung state?"): a LEASHED enemy whose target sits
    -- beyond its leash boundary chases forever without ever closing — frozen at the wall, holding
    -- aggro, which latches the player InCombat and PAUSES farming (the stray-despawn skips aggro'd
    -- foes, so nothing clears it). If it can neither reach attack range nor close the gap for
    -- stuck_disengage_seconds, DESPAWN it outright — just disengaging sends it back to patrol where it
    -- flees and re-aggros into the same loop (Jason). A fresh patrol fills in shortly anyway.
    local distToTarget = (Vector3.new(targetPos.X, ePos.Y, targetPos.Z) - ePos).Magnitude
    local closing = (entry.lastTargetDist == nil) or (distToTarget < entry.lastTargetDist - 0.5)
    if distToTarget <= (atk + 1) or closing then
        entry.stuckTime = 0 -- in bite range or still closing the gap = making progress
    else
        entry.stuckTime = (entry.stuckTime or 0) + (dt or 0.15)
        if entry.stuckTime >= (eng.stuck_disengage_seconds or 8) then
            self:_despawnEnemy(targetId) -- can't reach it + would just re-loop: remove it (frees InCombat)
            return
        end
    end
    entry.lastTargetDist = distToTarget

    -- 5) ATTACK: bite the highest-aggro pet that is CURRENTLY within attack range — not
    -- only the chase target. The enemy may be pursuing an unreachable top-aggro pet (a
    -- ranged kiter), but anything in its face (the melee/tank orbiting it) still gets hit.
    local biteTarget = AggroTable.top(entry.aggro, 0, function(k)
        return valid[k] == true and (self:_petPosition(k, pfs) - ePos).Magnitude <= atk
    end)
    entry.nextAttack = entry.nextAttack or 0
    if biteTarget and not held and now >= entry.nextAttack then
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
--   rally — pets ignore combat + return to formation for a window; enemies (still aggro'd on
--           the pets) chase them home, dragging the fight back to the player
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
    elseif command == "rally" then
        -- Recall the squad to formation for a window (RallyUntil): pets break off and return to the
        -- player; _assignPetTargets suppresses re-targeting while the window holds, so they don't
        -- instantly re-engage and drift off again. The enemies follow on their own — their built-up
        -- threat is high and decays only slowly while the retreating squad stays close (AggroLeash),
        -- so they keep chasing the pets home with no special aggro commit needed.
        local engCfg = self._combatConfig.engagement or {}
        player:SetAttribute("RallyUntil", os.clock() + (engCfg.rally_seconds or 3.5))
        for _, pet in ipairs(petsFolder:GetChildren()) do
            if pet:IsA("Model") then
                local tid = pet:FindFirstChild("TargetID")
                if tid then
                    tid.Value = 0 -- drop the current target now -> return to follow this frame
                end
            end
        end
    end
    if self._logger then
        self._logger:Info("Tactical command", { player = player.Name, command = command })
    end
end

-- The old floating debuff billboard was a placeholder PILL (coloured box + text) — retired in favour
-- of the enemy HUD card badges (the canonical surface). The HOLD state, though, also wears a world
-- badge ABOVE the enemy so you can see at a glance which foe is pinned without reading the HUD — but
-- rendered as the proper ICON DISC (the same capacitor glyph the HUD uses), not a placeholder pill.
-- Server-created so every nearby player sees the pinned enemy.
local HELD_DISC = nil -- resolved once (PowerIcons.discFor); the ice "capacitor" hold glyph
function EnemyService:_updateHeldBadge(model, nowTime)
    local pp = model.PrimaryPart
    if not pp then
        return
    end
    local held = (model:GetAttribute("HeldUntil") or 0) > nowTime
    local bb = pp:FindFirstChild("HeldBadge")
    if held then
        if not bb then
            if HELD_DISC == nil then
                HELD_DISC = (PowerIcons.discFor and PowerIcons.discFor("ice", "capacitor")) or false
            end
            bb = Instance.new("BillboardGui")
            bb.Name = "HeldBadge"
            bb.Size = UDim2.fromOffset(36, 36)
            bb.StudsOffset = Vector3.new(0, 6.6, 0) -- just above the HP bar
            bb.AlwaysOnTop = true
            bb.Adornee = pp
            bb.Parent = pp
            local img = Instance.new("ImageLabel")
            img.Name = "Icon"
            img.BackgroundTransparency = 1
            img.Size = UDim2.fromScale(1, 1)
            img.Image = HELD_DISC or ""
            img.Parent = bb
        end
    elseif bb then
        bb:Destroy()
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
        if aura.kind == "heal" or aura.kind == "drain" then -- drain = Hell's life-drain heal
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

-- CONTROL aura (kind = "hold") — pin one enemy: it can't move OR attack for `duration`s (HeldUntil).
-- TARGETING mirrors how the PLAYER designates an enemy — INDIRECTLY through the squad (Jason): hold
-- the player's focus = CombatAssistTarget if set (clicking the enemy HUD), else the enemy the most
-- pets are currently attacking, else the nearest engaged enemy. So the controller pins what you're
-- already fighting, and you steer it the same way you steer the squad. Experimental (meerkat test).
function EnemyService:_auraHold(folder, aura)
    local player = Players:FindFirstChild(folder.Name)
    if not player then
        return
    end
    local now = os.time()

    local function liveEnemy(targetId)
        local entry = targetId and self._enemies[targetId]
        local model = entry and entry.model
        if model and model.Parent and (model:GetAttribute("HP") or 0) > 0 then
            return entry, model
        end
        return nil
    end

    -- 1) the player's explicit focus (assist target set by clicking the enemy HUD)
    local targetId = player:GetAttribute("CombatAssistTarget")
    local entry, model = liveEnemy(targetId ~= 0 and targetId or nil)

    -- 2) else the enemy the most of this player's pets are currently attacking (de-facto focus)
    if not model then
        local petsFolder = Workspace:FindFirstChild("PlayerPets")
            and Workspace.PlayerPets:FindFirstChild(player.Name)
        if petsFolder then
            local tally = {}
            for _, pet in ipairs(petsFolder:GetChildren()) do
                local tt = pet:FindFirstChild("TargetType")
                local tid = pet:FindFirstChild("TargetID")
                if tt and tt.Value == "Enemy" and tid and tid.Value ~= 0 then
                    tally[tid.Value] = (tally[tid.Value] or 0) + 1
                end
            end
            local bestId, bestN
            for id, n in pairs(tally) do
                if not bestN or n > bestN then
                    bestId, bestN = id, n
                end
            end
            entry, model = liveEnemy(bestId)
        end
    end

    -- 3) else the nearest enemy aggro'd on this player's squad
    if not model then
        local ref = entry and entry.pos
        if not ref then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            ref = hrp and hrp.Position
        end
        if ref then
            local bestD
            for _, e in pairs(self._enemies) do
                local m = e.model
                if
                    e.aggroPlayerName == player.Name
                    and m
                    and m.Parent
                    and (m:GetAttribute("HP") or 0) > 0
                then
                    local d = (e.pos - ref).Magnitude
                    if not bestD or d < bestD then
                        bestD, model = d, m
                    end
                end
            end
        end
    end

    if not model then
        return
    end
    -- don't re-stamp an already-held target (lets a repeat cast roll onto a fresh enemy instead)
    if (model:GetAttribute("HeldUntil") or 0) > now then
        return
    end
    model:SetAttribute("HeldUntil", now + (tonumber(aura.duration) or 10))

    -- FREEZE roar: positional ice-crystal sound at the moment the hold lands (server-created, so
    -- every nearby player hears the foe get frozen). Plays once per hold (guarded above).
    local pp = model.PrimaryPart
    local def = pp and Sounds.freeze_hold
    if pp and def and def.id then
        local s = Instance.new("Sound")
        s.SoundId = def.id
        s.Volume = tonumber(def.volume) or 0.5
        s.RollOffMode = Enum.RollOffMode.InverseTapered
        s.RollOffMaxDistance = 120
        s.Parent = pp
        s:Play()
        Debris:AddItem(s, 10)
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

-- A pet's EFFECTIVE combat power — the ⚔ number on the card — resolved through the SAME
-- PetPowerView the inventory/squad cards and the damage path use (so "the carry" == the pet showing
-- the highest ⚔). It applies role combat_mult (tank ×0.6), element + variant + per-pet aptitude on
-- top of the realized base. Falls back to the raw base if PetPowerView is unavailable. (Live zone/
-- realm resonance isn't folded in — that's a small situational factor vs the archetype combat_mult.)
function EnemyService:_petCombatPower(pet)
    local base = self:_petPower(pet)
    if not (PetPowerView and PetPowerView.profile) then
        return base
    end
    local ok, profile = pcall(function()
        return PetPowerView.profile({
            base = base,
            petType = pet:GetAttribute("PetType"),
            variant = pet:GetAttribute("PetVariant"),
            role = pet:GetAttribute("PetRole"),
        })
    end)
    return (ok and profile and tonumber(profile.combatEffective)) or base
end

-- EMPOWER (single-target damage buffer — the "carry amplifier", pet_roles support_auras kind
-- "empower"): instead of lifting the whole team like the offense aura, concentrate the damage buff
-- on the squad's STRONGEST ally. Picks the top-`count` allies by power (SupportAura.rankTargets — so
-- N empower buffers lift the top N carries) and stamps the per-PET EmpowerDamageBuff. That attribute
-- rides the SAME additive pet_damage axis as RAGE + the player buffs (PetFollowService reads it
-- per-pet), so it adds under the cap and boosts BOTH the carry's mining and combat.
function EnemyService:_auraEmpower(folder, aura, count)
    local candidates = {}
    for _, ally in ipairs(folder:GetChildren()) do
        if ally:IsA("Model") and ally.PrimaryPart and not ally:GetAttribute("CombatDowned") then
            -- Rank by EFFECTIVE combat power (the ⚔ number), NOT raw base: a huge tank has the
            -- biggest base but its ×0.6 combat_mult makes a blaster the real carry. Empower must
            -- lift the actual damage dealer, so resolve combatEffective through PetPowerView.
            candidates[#candidates + 1] = { key = ally, power = self:_petCombatPower(ally) }
        end
    end
    local ranked = SupportAura.rankTargets(candidates, aura.target or "highest_power")
    local mult = tonumber(aura.mult) or 1
    local until_ = os.time() + (tonumber(aura.duration) or 3)
    local lift = math.min(math.max(1, math.floor(tonumber(count) or 1)), #ranked)
    for i = 1, lift do
        local ally = ranked[i]
        ally:SetAttribute("EmpowerDamageBuff", mult)
        ally:SetAttribute("EmpowerDamageBuffUntil", until_)
        ally:SetAttribute("EmpowerFxUntil", until_) -- squad-card badge (steady while buffed)
        ally:SetAttribute("EmpowerFxUntilStacks", 1)
    end
end

-- SCOPED team buff (Jason: "aura targeting drives the application scope, not just the ring"). A
-- combat buff (offense/haste) applies to a pet SET chosen by its `targeting`:
--   "aura" (default)  -> TEAM: player-wide attribute, FX on every ally (the original behavior).
--   "single"          -> the top-1 carry (by combat power) gets a PER-PET buff.
--   "targeted_aoe"    -> the top-K carries (aura.max_targets, default 3) get the per-pet buff.
-- The ring already follows targeting via PetTargeting.auraScope (so the card reads single/aoe/team);
-- this makes the MECHANIC match. teamAttr = the player multiplier; petAttr = the per-pet multiplier
-- the consumer also reads (PetFollowService: additive for damage, bounded-mult for haste).
function EnemyService:_auraScopedBuff(folder, teamAttr, petAttr, fxAttr, aura, count, weight)
    local scope = (type(aura.targeting) == "string" and aura.targeting) or "aura"
    if scope ~= "single" and scope ~= "targeted_aoe" then
        self:_auraPlayerBuff(folder, teamAttr, aura, count, weight)
        self:_stampAuraFx(folder, fxAttr, aura, count)
        return
    end
    local candidates = {}
    for _, ally in ipairs(folder:GetChildren()) do
        if ally:IsA("Model") and ally.PrimaryPart and not ally:GetAttribute("CombatDowned") then
            candidates[#candidates + 1] = { key = ally, power = self:_petCombatPower(ally) }
        end
    end
    local ranked = SupportAura.rankTargets(candidates, aura.target or "highest_power")
    local k = (scope == "single") and 1 or math.max(1, math.floor(tonumber(aura.max_targets) or 3))
    k = math.min(k, #ranked)
    -- per-pet multiplier = same variant-scaled fraction the team path uses
    local mult = 1 + ((tonumber(aura.mult) or 1) - 1) * (tonumber(weight) or tonumber(count) or 1)
    local until_ = os.time() + (tonumber(aura.duration) or 3)
    for i = 1, k do
        local ally = ranked[i]
        ally:SetAttribute(petAttr, mult)
        ally:SetAttribute(petAttr .. "Until", until_)
        ally:SetAttribute(fxAttr, until_) -- squad-card badge on the buffed carry(ies) only
        ally:SetAttribute(fxAttr .. "Stacks", 1)
    end
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
                if kind == "heal" or kind == "drain" then
                    -- "drain" = Hell's life-drain heal (give→take flavor): mechanically a team mend,
                    -- so it routes through the same _auraHeal path as Heaven's heal.
                    for _ = 1, count do -- N healers => N mends (variant scales each mend)
                        self:_auraHeal(folder, aura, weight / count)
                    end
                elseif kind == "hold" then
                    for _ = 1, count do -- N controllers => N enemies pinned (each picks a fresh one)
                        self:_auraHold(folder, aura)
                    end
                elseif kind == "defense" then
                    self:_auraDefense(folder, aura, count, weight)
                elseif kind == "offense" then
                    -- War-Cry: team damage, OR single/targeted_aoe via aura.targeting (per-pet).
                    self:_auraScopedBuff(
                        folder,
                        "PetTeamDamageBuff",
                        "PetDamageBuffSelf",
                        "OffenseFxUntil",
                        aura,
                        count,
                        weight
                    )
                elseif kind == "haste" then
                    -- Haste: team ATTACK-SPEED, OR single/targeted_aoe via aura.targeting. Consumed in
                    -- PetFollowService (shortens the attack interval, bounded).
                    self:_auraScopedBuff(
                        folder,
                        "PetHasteBuff",
                        "PetHasteBuffSelf",
                        "HasteFxUntil",
                        aura,
                        count,
                        weight
                    )
                elseif kind == "empower" then
                    -- SINGLE-TARGET damage buffer (carry amplifier): N empower buffers lift the
                    -- top-N strongest allies, not the whole team.
                    self:_auraEmpower(folder, aura, count)
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
        -- RALLY: during the window the pets ignore combat and return to formation (clear targets);
        -- enemies keep their aggro and chase the returning pets, pulling the fight back to the player.
        if player and (player:GetAttribute("RallyUntil") or 0) > os.clock() then
            for _, pet in ipairs(folder:GetChildren()) do
                if pet:IsA("Model") then
                    local tid = pet:FindFirstChild("TargetID")
                    if tid then
                        tid.Value = 0
                    end
                end
            end
            continue
        end
        local assist = player and player:GetAttribute("CombatAssistTarget")
        -- TRANSIENT focus: a directed assist target lapses after assist_seconds so the squad is never
        -- stranded on an unreachable/stale focus — it reverts to normal auto-targeting (re-click to
        -- refresh). This is what stops "focus a far enemy -> pets do nothing forever".
        if assist and assist ~= 0 then
            local until_ = player:GetAttribute("CombatAssistUntil")
            if until_ and os.clock() >= until_ then
                player:SetAttribute("CombatAssistTarget", 0)
                player:SetAttribute("CombatAssistUntil", nil)
                assist = 0
            end
        end
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
                    -- Acquisition range: an explicit role engage_range wins (a blaster acquires from
                    -- well beyond its attack_range, then advances to standoff to fire). Otherwise a
                    -- kiter is capped at its attack_range (snipe-in-place roles stay back) and a
                    -- chaser uses the squad aggro range.
                    local reach = (roleDef and tonumber(roleDef.engage_range))
                        or (kites and roleDef and tonumber(roleDef.attack_range))
                        or aggroRange
                    local petPos = self:_petPosition(pet, pfs)
                    local candidates = {}
                    for etid, entry in pairs(live) do
                        -- A kiting pet shoots, so it picks targets by HORIZONTAL distance — it can
                        -- engage a flyer perched above (the vertical gap shouldn't hide it). A chaser
                        -- uses true 3D distance (it has to physically reach + the jump-assist climbs).
                        local d
                        if kites then
                            local dx, dz = entry.pos.X - petPos.X, entry.pos.Z - petPos.Z
                            d = math.sqrt(dx * dx + dz * dz)
                        else
                            d = (entry.pos - petPos).Magnitude
                        end
                        -- TERRITORIAL: pets only auto-pick foes in the player's own area (no
                        -- reaching across a wall into another biome's pack). ALLEGIANCE GATE: a pet
                        -- only auto-targets an enemy it's hostile to (heaven/neutral pets ignore heaven
                        -- enemies -> peaceful farming in heaven; hell pets engage everything).
                        if
                            d <= reach
                            and self:_inTerritory(entry, player)
                            and self:_petHostileToEnemy(pet, entry, player)
                        then
                            local edef = entry.def
                                or (
                                    self._enemiesConfig.enemies
                                    and self._enemiesConfig.enemies[entry.enemyId]
                                )
                            candidates[#candidates + 1] = {
                                id = etid,
                                distance = d,
                                strength = (entry.model and entry.model:GetAttribute("Level")) or 1,
                                hp = (entry.model and entry.model:GetAttribute("HP")) or 0,
                                aggro = AggroTable.get(entry.aggro, pet),
                                teamDamage = (edef and edef.attack and edef.attack.damage) or 0,
                                -- flyers hover (hover_height); a grounded chaser can't reach them.
                                flyer = (edef and (edef.hover_height or 0) > 0) or false,
                            }
                        end
                    end
                    -- REACHABILITY (chasers only): a melee/tank pet can't hit a hovering flyer, so
                    -- it would stand there as a punching bag. If ANY ground-reachable enemy is in
                    -- range, drop the flyers from its candidate set so it engages something it can
                    -- actually hit; only fall back to a flyer when that's the sole option. Kiters
                    -- shoot upward (horizontal distance above), so they keep flyers.
                    if not kites then
                        local hasGround = false
                        for _, cand in ipairs(candidates) do
                            if not cand.flyer then
                                hasGround = true
                                break
                            end
                        end
                        if hasGround then
                            local ground = {}
                            for _, cand in ipairs(candidates) do
                                if not cand.flyer then
                                    ground[#ground + 1] = cand
                                end
                            end
                            candidates = ground
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
                elseif tt.Value == "Enemy" or (player and player:GetAttribute("InCombat")) then
                    -- Release this pet's target to 0 (follow formation) when EITHER its enemy is gone
                    -- / out of range, OR the player is in combat and this pet isn't engaged (a buffer
                    -- hanging back, or a melee with no enemy in range) -> COMBAT STANCE: stop mining
                    -- and hold formation. Auto-farm assignment is paused too, so it stays put until
                    -- the fight ends (InCombat clears -> farming resumes).
                    if tid.Value ~= 0 then
                        tid.Value = 0
                    end
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
            local def = entry.def
                or (self._enemiesConfig.enemies and self._enemiesConfig.enemies[entry.enemyId])
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

-- AURA-damage pass: a pet with attack_targeting = "aura" deals a damage FIELD around ITSELF — every
-- pet_aura.interval it hits every enemy within `radius` for `fraction` of its effective combat power,
-- no target needed (the "get close and everything burns" bruiser). Interval-gated per pet (a steady
-- cadence, not every combat tick); a fire-ring follows the pet (Power_AreaFx, sized to radius).
-- Damage credits the owner's Contrib so aura kills count. Opt-in: only aura pets run this.
function EnemyService:_auraDamagePass(now)
    local cfg = (self._combatConfig and self._combatConfig.pet_aura) or {}
    local radius = tonumber(cfg.radius) or 12
    local fraction = tonumber(cfg.fraction) or 0.5
    local interval = math.max(0.1, tonumber(cfg.interval) or 1)
    local playerPets = Workspace:FindFirstChild("PlayerPets")
    if not playerPets then
        return
    end
    self._auraAt = self._auraAt or setmetatable({}, { __mode = "k" }) -- [pet]=next tick; weak so dead pets GC
    local pfs = self:_petFollowService()
    for _, folder in ipairs(playerPets:GetChildren()) do
        local owner = Players:FindFirstChild(folder.Name)
        local ownerKey = owner and tostring(owner.UserId)
        for _, pet in ipairs(folder:GetChildren()) do
            if
                pet:IsA("Model")
                and not pet:GetAttribute("CombatDowned")
                and pet:GetAttribute("AttackTargeting") == "aura"
            then
                local nextAt = self._auraAt[pet]
                if not nextAt or now >= nextAt then
                    self._auraAt[pet] = now + interval
                    local pos = self:_petPosition(pet, pfs)
                    local dmg = math.floor(self:_petCombatPower(pet) * fraction + 0.5)
                    if pos and dmg > 0 then
                        for _, entry in pairs(self._enemies) do
                            local model = entry.model
                            if model and model.Parent and (model:GetAttribute("HP") or 0) > 0 then
                                local ep = model.PrimaryPart
                                    or model:FindFirstChildWhichIsA("BasePart")
                                if ep and (ep.Position - pos).Magnitude <= radius then
                                    local hp = tonumber(model:GetAttribute("HP")) or 0
                                    local newHp = math.max(0, hp - dmg)
                                    local dealt = hp - newHp
                                    model:SetAttribute("HP", newHp)
                                    local contrib = dealt > 0
                                        and ownerKey
                                        and model:FindFirstChild("Contrib")
                                    if contrib then
                                        local nv = contrib:FindFirstChild(ownerKey)
                                        if not nv then
                                            nv = Instance.new("NumberValue")
                                            nv.Name = ownerKey
                                            nv.Parent = contrib
                                        end
                                        nv.Value += dealt
                                    end
                                    -- BONFIRE (aura + DoT): if the aura pet carries an attack_dot, its
                                    -- field also LEAVES A BURN on each enemy it ticks — a persistent
                                    -- burning zone. Composes the aura geometry with the DoT axis; the
                                    -- _dotPass + EnemyBurnFx render it like any other burn.
                                    local dotFrac = tonumber(pet:GetAttribute("DotFraction")) or 0
                                    local dotDur = tonumber(pet:GetAttribute("DotDuration")) or 0
                                    if dotFrac > 0 and dotDur > 0 then
                                        local perTick = DamageOverTime.perTick(dmg, dotFrac)
                                        if perTick > 0 then
                                            local tick = math.max(
                                                0.1,
                                                tonumber(pet:GetAttribute("DotTick")) or 1
                                            )
                                            model:SetAttribute(
                                                "DotPerTick",
                                                math.max(
                                                    tonumber(model:GetAttribute("DotPerTick")) or 0,
                                                    perTick
                                                )
                                            )
                                            model:SetAttribute("DotInterval", tick)
                                            model:SetAttribute("DotNextTick", now + tick)
                                            model:SetAttribute("DotExpireAt", now + dotDur)
                                            model:SetAttribute("DotDuration", dotDur)
                                            model:SetAttribute(
                                                "DotSourceUserId",
                                                owner and owner.UserId or 0
                                            )
                                            model:SetAttribute(
                                                "BurnFxUntil",
                                                os.time() + math.ceil(dotDur)
                                            )
                                        end
                                    end
                                    -- VISUALIZE: a floating number on each enemy the field ticks, so
                                    -- the aura reads (splash = number-only, no per-target bolt). Without
                                    -- this the aura is silent and looks like it's "not hitting".
                                    if dealt > 0 and owner then
                                        Signals.Combat_PetHit:FireClient(owner, {
                                            pet = pet,
                                            target = model,
                                            crit = false,
                                            amount = dealt,
                                            miss = false,
                                            splash = true,
                                        })
                                    end
                                end
                            end
                        end
                        if owner then -- the field VFX: centred on the pet, sized to the aura, themed
                            -- to the pet's ELEMENT (grass bear -> Bloom nova, lava -> fire ring) so
                            -- it doesn't always read as fire. pettype_element returns the AreaFX
                            -- theme key (grass/lava/ice/desert); nil -> client default.
                            local petEl = self._originConfig.pettype_element
                                and self._originConfig.pettype_element[pet:GetAttribute("PetType")]
                            Signals.Power_AreaFx:FireClient(
                                owner,
                                { center = pos, variant = "self", radius = radius, element = petEl }
                            )
                        end
                    end
                end
            end
        end
    end
end

-- CONTAGION pass: a burning enemy marked by a contagion pet SPREADS its burn to the NEAREST
-- un-burning enemy within spread_radius, every spread_interval, chaining up to max_spread hops (each
-- hop carries one fewer + a fresh copy of the burn window). Sequential, not an instant splash —
-- that's what makes it a distinct targeting type. A node spreads ONCE then stops; the new node
-- carries the chain. Needs an active DoT (the burn) to spread — set by the contagion stamp in _mine.
function EnemyService:_contagionPass(now)
    local cc = (self._combatConfig and self._combatConfig.pet_contagion) or {}
    for _, entry in pairs(self._enemies) do
        local src = entry.model
        if src and src.Parent and (src:GetAttribute("HP") or 0) > 0 then
            local spreadAt = tonumber(src:GetAttribute("ContagionSpreadAt")) or 0
            local left = tonumber(src:GetAttribute("ContagionLeft")) or 0
            local perTick = tonumber(src:GetAttribute("DotPerTick")) or 0
            -- Per-BURN spread tuning carried on the enemy (originating pet's attack_dot.spread),
            -- falling back to the global pet_contagion defaults. Lets one contagion pet creep tight
            -- and slow while another wildfires wide and fast — and each hop carries the same tuning.
            local spreadRadius = (tonumber(src:GetAttribute("ContagionRadius")) or 0) > 0
                    and tonumber(src:GetAttribute("ContagionRadius"))
                or (tonumber(cc.spread_radius) or 8)
            local spreadInterval = math.max(
                0.2,
                (tonumber(src:GetAttribute("ContagionInterval")) or 0) > 0
                        and tonumber(src:GetAttribute("ContagionInterval"))
                    or (tonumber(cc.spread_interval) or 1.5)
            )
            if
                spreadAt > 0
                and left > 0
                and perTick > 0
                and now >= spreadAt
                and not DamageOverTime.isExpired(src:GetAttribute("DotExpireAt") or 0, now)
            then
                local sp = src.PrimaryPart or src:FindFirstChildWhichIsA("BasePart")
                local best, bestD
                if sp then
                    for _, e2 in pairs(self._enemies) do
                        local m2 = e2.model
                        if
                            m2
                            and m2 ~= src
                            and m2.Parent
                            and (m2:GetAttribute("HP") or 0) > 0
                            and (tonumber(m2:GetAttribute("DotPerTick")) or 0) <= 0 -- not already burning
                        then
                            local p2 = m2.PrimaryPart or m2:FindFirstChildWhichIsA("BasePart")
                            if p2 then
                                local d = (p2.Position - sp.Position).Magnitude
                                if d <= spreadRadius and (not bestD or d < bestD) then
                                    best, bestD = m2, d
                                end
                            end
                        end
                    end
                end
                if best then
                    local interval = tonumber(src:GetAttribute("DotInterval")) or 1
                    local duration = tonumber(src:GetAttribute("DotDuration")) or 0
                    best:SetAttribute("DotPerTick", perTick) -- copy the burn (fresh window)
                    best:SetAttribute("DotInterval", interval)
                    best:SetAttribute("DotNextTick", now + interval)
                    best:SetAttribute("DotExpireAt", now + duration)
                    best:SetAttribute("DotDuration", duration)
                    best:SetAttribute("DotSourceUserId", src:GetAttribute("DotSourceUserId"))
                    best:SetAttribute("BurnFxUntil", os.time() + math.ceil(duration))
                    local nextLeft = left - 1
                    best:SetAttribute("ContagionLeft", nextLeft)
                    best:SetAttribute(
                        "ContagionSpreadAt",
                        nextLeft > 0 and (now + spreadInterval) or 0
                    )
                    -- carry the per-burn spread tuning to the next node so the chain stays consistent
                    best:SetAttribute("ContagionRadius", spreadRadius)
                    best:SetAttribute("ContagionInterval", spreadInterval)
                    best:SetAttribute(
                        "ContagionMax",
                        tonumber(src:GetAttribute("ContagionMax")) or nextLeft
                    )
                    src:SetAttribute("ContagionLeft", 0) -- this node did its one hop; it's done
                    src:SetAttribute("ContagionSpreadAt", 0)
                else
                    src:SetAttribute("ContagionSpreadAt", now + spreadInterval) -- none in range; retry
                end
            end
        end
    end
end

-- DoT pass: tick any burn (DamageOverTime) a pet attack stamped on an enemy. perTick is stored on
-- the enemy (DotPerTick); apply the whole ticks due this step, credit the source player's Contrib so
-- burn kills count toward rewards, and burn out at expiry. The HP drain is the visible tell (the
-- enemy's overhead bar updates off the HP attribute). Pure tick math lives in DamageOverTime.
function EnemyService:_dotPass(now)
    for _, entry in pairs(self._enemies) do
        local model = entry.model
        if model and model.Parent and (model:GetAttribute("HP") or 0) > 0 then
            local perTick = tonumber(model:GetAttribute("DotPerTick")) or 0
            if perTick > 0 then
                if DamageOverTime.isExpired(model:GetAttribute("DotExpireAt") or 0, now) then
                    model:SetAttribute("DotPerTick", 0) -- burned out
                else
                    local count, nextAt = DamageOverTime.ticksDue(
                        model:GetAttribute("DotNextTick") or 0,
                        model:GetAttribute("DotInterval") or 1,
                        model:GetAttribute("DotExpireAt") or 0,
                        now
                    )
                    if count > 0 then
                        model:SetAttribute("DotNextTick", nextAt)
                        local hp = tonumber(model:GetAttribute("HP")) or 0
                        local newHp = math.max(0, hp - perTick * count)
                        local dealt = hp - newHp
                        model:SetAttribute("HP", newHp)
                        local uid = model:GetAttribute("DotSourceUserId")
                        local contrib = dealt > 0 and model:FindFirstChild("Contrib")
                        if uid and contrib then
                            local key = tostring(uid)
                            local nv = contrib:FindFirstChild(key)
                            if not nv then
                                nv = Instance.new("NumberValue")
                                nv.Name = key
                                nv.Parent = contrib
                            end
                            nv.Value += dealt
                        end
                        -- VISUALIZE the burn tick: float the number on the enemy so the DoT/contagion
                        -- damage READS (the fire shows it's burning; this shows how much). The DoT pass
                        -- has no source-pet ref, so use any of the owner's deployed pets purely as the
                        -- Combat_PetHit ref; splash = true -> number-only (no bolt), so the ref's
                        -- identity doesn't matter. Skipped if the owner/pets are gone.
                        if dealt > 0 and uid then
                            local owner = Players:GetPlayerByUserId(uid)
                            local folder = owner
                                and Workspace:FindFirstChild("PlayerPets")
                                and Workspace.PlayerPets:FindFirstChild(owner.Name)
                            local refPet = folder and folder:FindFirstChildWhichIsA("Model")
                            if refPet then
                                Signals.Combat_PetHit:FireClient(owner, {
                                    pet = refPet,
                                    target = model,
                                    crit = false,
                                    amount = dealt,
                                    miss = false,
                                    splash = true,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ROAMING PATROL BANDS (combat.lua enemy_patrol; flag-gated). One band per realm BaddieSpawner<Area>
-- part: a pack that walks a procedural route. The route is a moving `home` anchor — the existing idle
-- LOITER drifts each unaware member around it, so moving the anchor through waypoints (with dwell) IS
-- the patrol. Aggro/return ride the existing perception + leash. Slice 1: placeholder model, spawns
-- only while a player is in the realm; per-area heaven-pet factions are the content pass.

-- Procedural route from VALID crystal locations (Jason: "all waypoints should be valid crystal
-- locations — a crystal could be spawned there"). A live crystal IS a valid, grounded, in-biome
-- spot, so we sample the route from real crystal positions near the anchor instead of raw circle
-- points (which landed on mountainsides and sent the band climbing).
--
-- AREA BOUNDARY (Jason: "they should be bounded by the area-ID crystals"): a band patrols ONLY its
-- own zone's crystals. Crystals are foldered by areaId under Workspace.Game.Breakables.Crystals.<areaId>
-- (e.g. Hell_1_Lava), so we scan that ONE folder — never the whole map — so a Lava band can't wander
-- onto Ice/Desert ore. No areaId folder yet (ore not spawned) = hold; _updateBand re-rolls once it
-- fills. Prefer stops within `radius` of the cave; if none are that close (cave sits at the zone's
-- edge), fall back to the NEAREST in-area crystals so the route stays inside the zone either way.
function EnemyService:_patrolWaypoints(center, radius, count, areaId)
    local want = math.max(1, math.floor(count or 3))
    local reach = tonumber(radius) or 100 -- preferred crystal stops within this many studs of the cave
    local game = Workspace:FindFirstChild("Game")
    local breakables = game and game:FindFirstChild("Breakables")
    local crystals = breakables and breakables:FindFirstChild("Crystals")
    local areaFolder = (areaId and crystals) and crystals:FindFirstChild(areaId) or nil
    local within, all = {}, {}
    if areaFolder then
        for _, inst in ipairs(areaFolder:GetDescendants()) do
            if inst:IsA("Model") and inst:GetAttribute("MiningLevel") ~= nil then
                local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
                if pp then
                    local dx, dz = pp.Position.X - center.X, pp.Position.Z - center.Z
                    local d2 = dx * dx + dz * dz
                    all[#all + 1] = { pos = pp.Position, d2 = d2 }
                    if d2 <= (reach * reach) then
                        within[#within + 1] = pp.Position
                    end
                end
            end
        end
    end
    local pts = {}
    if #within > 0 then
        -- shuffle the in-range crystals, take `want` (varied route each sortie)
        for i = #within, 2, -1 do
            local j = math.random(1, i)
            within[i], within[j] = within[j], within[i]
        end
        for i = 1, math.min(want, #within) do
            pts[#pts + 1] = within[i]
        end
    elseif #all > 0 then
        -- none within reach but the zone has crystals: take the nearest in-area ones (stays bounded)
        table.sort(all, function(a, b)
            return a.d2 < b.d2
        end)
        for i = 1, math.min(want, #all) do
            pts[#pts + 1] = all[i].pos
        end
    end
    if #pts == 0 then
        pts[1] = center -- no in-area crystals yet: hold at the cave; route re-rolls once they spawn
    end
    return pts
end

-- A cave's NORMALIZED origin: the BaddieSpawner<Origin> suffix, mapped through patrol_origin_alias so
-- the player-facing cave name resolves to the element id used by crystal folders + factions. The grass
-- cave is authored as "BaddieSpawnerEarth" (player-facing) but its ore folders + faction use "Grass"
-- (the frozen element id), so alias { Earth = "Grass" } bridges them without renaming anything.
function EnemyService:_caveOrigin(part)
    local suffix = part.Name:gsub("^BaddieSpawner", "")
    if suffix == "" then
        return nil
    end
    local cfg = self._combatConfig and self._combatConfig.enemy_patrol
    local alias = cfg and cfg.patrol_origin_alias
    if type(alias) == "table" and alias[suffix] then
        return alias[suffix]
    end
    return suffix
end

-- A band's ALLEGIANCE: the realm's OWN side. Heaven realms spawn HEAVEN enemies, hell realms spawn
-- HELL enemies (Jason: "in heaven we should only spawn heaven enemies; in hell, only hell"). The
-- heaven/hell ASYMMETRY comes from the aggression rule layered on top (heaven enemies only attack hell
-- pets, hell enemies attack all), NOT from which side spawns — "heaven attacks hell" is the targeting
-- direction. Returns nil outside the two realm families (home never patrols). Stamped on each member.
function EnemyService:_caveAllegiance(part)
    local parent = part.Parent
    local folderName = parent and parent.Name
    if type(folderName) ~= "string" then
        return nil
    end
    local lower = folderName:lower()
    if lower:match("^heaven") then
        return "heaven" -- heaven realm fields heaven enemies
    elseif lower:match("^hell") then
        return "hell" -- hell realm fields hell enemies
    end
    return nil
end

-- The realm a player currently stands in ("heaven"/"hell"/"neutral"), derived from CurrentLayer so it
-- matches _caveAllegiance (folder-name based) rather than relying on a separately-set attribute.
function EnemyService:_currentRealm(player)
    local layer = player and player:GetAttribute("CurrentLayer")
    if type(layer) == "string" then
        if layer:match("^heaven") then
            return "heaven"
        elseif layer:match("^hell") then
            return "hell"
        end
    end
    return "neutral"
end

-- A pet species' side ("heaven"/"hell"/"neutral") from its pets.lua `realm`. Cached by PetType.
function EnemyService:_petRealmOf(petType)
    if type(petType) ~= "string" then
        return "neutral"
    end
    self._petsConfig = self._petsConfig or self._configLoader:LoadConfig("pets")
    self._petRealmCache = self._petRealmCache or {}
    local cached = self._petRealmCache[petType]
    if cached ~= nil then
        return cached
    end
    local def = self._petsConfig and self._petsConfig.pets and self._petsConfig.pets[petType]
    local realm = Allegiance.normalize(def and def.realm)
    self._petRealmCache[petType] = realm
    return realm
end

-- The allegiance targeting gate (Jason's farming-vs-combat asymmetry): heaven attacks only hell, hell
-- attacks all, neutral takes the current realm's side; off-realm (homeworld) everyone attacks all.
-- Enemy side = entry.allegiance (set for realm pet-invaders, nil/neutral elsewhere); pet side = species.
function EnemyService:_enemyHostileToPet(entry, pet, player)
    return Allegiance.hostile(
        entry.allegiance,
        self:_petRealmOf(pet:GetAttribute("PetType")),
        self:_currentRealm(player)
    )
end

function EnemyService:_petHostileToEnemy(pet, entry, player)
    return Allegiance.hostile(
        self:_petRealmOf(pet:GetAttribute("PetType")),
        entry.allegiance,
        self:_currentRealm(player)
    )
end

-- The crystal folder id for a cave's zone. Realm caves are BaddieSpawner<Origin> parts living in the
-- realm map folder (Maps/Hell_1), and their ore is foldered as <RealmFolder>_<Origin> (Hell_1_Lava),
-- so the areaId composes from the parent folder name + the normalized origin. Mirrors the suffix
-- routing BaddieSpawnerService uses for waves, so waves and patrol stops share one zone identity.
function EnemyService:_caveAreaId(part)
    local parent = part.Parent
    local folderName = parent and parent.Name
    if not folderName or folderName == "" then
        return nil
    end
    local origin = self:_caveOrigin(part)
    if not origin then
        return nil
    end
    return folderName .. "_" .. origin
end

-- The signature enemy a cave fields, keyed off its normalized origin, so a band's model reads as its
-- home zone (Jason: lava_imp = Lava, frost_fox = Ice, sand_jackal = Desert, rabid_dog = Grass)
-- instead of one generic placeholder you can't place. Falls back to placeholder_enemy if unmapped.
function EnemyService:_patrolEnemyId(cfg, part)
    local map = cfg.patrol_enemy_by_origin
    if type(map) == "table" then
        local origin = self:_caveOrigin(part)
        if origin and map[origin] then
            return map[origin]
        end
    end
    return cfg.placeholder_enemy or "lava_imp"
end

-- Pets of a given realm ("heaven"/"hell"), sorted weakest->strongest by base_power, each entry
-- { id, def, power }. The patrol fields these as INVADERS (Jason: "the pets from heaven attack hell
-- and the pets from hell attack heaven — we just use the same models"). Cached per realm; only pets
-- with a basic mesh are eligible (so the model actually renders).
function EnemyService:_realmPetRoster(realm)
    if not realm then
        return {}
    end
    self._petsConfig = self._petsConfig or self._configLoader:LoadConfig("pets")
    self._petRosterCache = self._petRosterCache or {}
    if self._petRosterCache[realm] then
        return self._petRosterCache[realm]
    end
    local list = {}
    local pets = (self._petsConfig and self._petsConfig.pets) or {}
    for id, def in pairs(pets) do
        if type(def) == "table" and def.realm == realm then
            local variant = def.variants and def.variants.basic
            if variant and variant.mesh_asset then
                list[#list + 1] = { id = id, def = def, power = tonumber(def.base_power) or 0 }
            end
        end
    end
    table.sort(list, function(a, b)
        return a.power < b.power
    end)
    self._petRosterCache[realm] = list
    return list
end

-- Synthesize an ENEMY def from a PET def — same model (mesh+texture+scale), HP from base_health and
-- attack from base_power, so an opposing-realm pet can wear the enemy attack script unchanged. The
-- pet is NOT acquirable; this is purely a model+stat wrapper (Jason: "exactly the same, just attached
-- to the attack script"). Balance knobs (hp mult, cadence, move speed) live in combat.lua enemy_patrol.
function EnemyService:_petEnemyDef(petId, petDef)
    local cfg = (self._combatConfig and self._combatConfig.enemy_patrol) or {}
    local variant = (petDef.variants and petDef.variants.basic) or {}
    local scale = (petDef.asset_transform and tonumber(petDef.asset_transform.scale)) or 1.6
    local hpMult = tonumber(cfg.pet_enemy_hp_mult) or 10
    local hp = math.max(1, math.floor((tonumber(petDef.base_health) or 100) * hpMult))
    local dmg = math.max(1, math.floor(tonumber(petDef.base_power) or 10))
    local tierByRarity = {
        common = "trash_mob",
        uncommon = "trash_mob",
        rare = "trash_mob",
        epic = "lieutenant",
        legendary = "lieutenant",
        mythic = "boss",
        secret = "boss",
        exclusive = "boss",
    }
    -- SUPPORT INVADERS (Jason): a support pet doesn't melee — it either helps its team or stays
    -- neutral. Easiest correct mapping: damage 0 (no attack), and if its aura is HEAL give it the
    -- enemy-side auto_heal so it mends its band (the one support kind with an existing enemy hook).
    -- Other auras (defense/offense/yield/luck/hold) have no enemy mechanic yet, so those are simply
    -- neutral non-combatants.
    local roles = self._petRoles or {}
    local isSupport = (roles.roles and roles.roles[petId]) == "support"
    local aura = roles.support_auras and roles.support_auras[petId]
    local attack = { damage = dmg, cadence = tonumber(cfg.pet_enemy_cadence) or 1.5, sundering = 0 }
    local autoHeal
    if isSupport then
        attack.damage = 0 -- support invaders don't attack
        if type(aura) == "table" and (aura.kind == "heal" or aura.kind == "drain") then
            local amount = tonumber(aura.amount)
                or math.max(1, math.floor(hp * (tonumber(aura.fraction) or 0.08)))
            autoHeal = { interval = tonumber(aura.interval) or 2.0, amount = amount, range = 45 }
        end
    end
    return {
        role = isSupport and "support" or "melee",
        hp = hp,
        display_name = petDef.display_name or petId,
        tier = tierByRarity[petDef.rarity] or "trash_mob",
        move_speed = tonumber(cfg.pet_enemy_move_speed) or 15,
        armor = 0,
        mesh_asset = variant.mesh_asset,
        texture_asset = variant.texture_asset,
        model_scale = scale,
        attack = attack,
        auto_heal = autoHeal, -- heal-support invaders mend their team; nil otherwise
        drop_table = {}, -- invaders aren't farmed for currency (tuning pass can add realm drops)
        _petInvader = petId,
    }
end

-- Roll a varied band for a sortie. Returns (specs, label, scary) — each spec is
-- { id = <enemyId>, def = <synthesized pet-invader def or nil> }. Two modes:
--   PET INVADERS (use_pet_invaders): the band IS opposing-realm PET models wearing the attack script
--   (pets whose realm == this cave's allegiance). One rare SCARY slot = the strongest opposing pet.
--   ELEMENT PACKS (default): weighted comp from patrol_bands_by_origin (the home-style wave tables).
function EnemyService:_pickPatrolBand(cfg, part)
    local origin = self:_caveOrigin(part)
    local allegiance = self:_caveAllegiance(part)

    -- PET INVADERS — opposing-realm pet models as the band.
    if cfg.use_pet_invaders and allegiance then
        local roster = self:_realmPetRoster(allegiance) -- weak -> strong
        if #roster > 0 then
            local size = math.min(
                math.max(1, math.floor(cfg.band_size or 4)),
                math.max(1, math.floor(tonumber(cfg.max_band_units) or 8))
            )
            local specs = {}
            local scary = math.random() < (tonumber(cfg.pet_invader_scary_chance) or 0.18)
            if scary then
                local boss = roster[#roster] -- strongest opposing pet anchors the scary band
                specs[#specs + 1] =
                    { id = "petinv_" .. boss.id, def = self:_petEnemyDef(boss.id, boss.def) }
            end
            while #specs < size do
                local pick = roster[math.random(1, #roster)]
                specs[#specs + 1] =
                    { id = "petinv_" .. pick.id, def = self:_petEnemyDef(pick.id, pick.def) }
            end
            return specs, scary and "scary invaders" or "invaders", scary
        end
        -- no opposing-realm pets eligible -> fall through to element packs
    end

    -- ELEMENT PACKS — prefer the allegiance x element matrix (themed-content seam), else the
    -- realm-neutral element-only pools.
    local pool
    local byAlleg = cfg.patrol_bands_by_allegiance
    if type(byAlleg) == "table" and allegiance and type(byAlleg[allegiance]) == "table" then
        pool = origin and byAlleg[allegiance][origin] or nil
    end
    if not pool then
        local pools = cfg.patrol_bands_by_origin
        pool = (type(pools) == "table" and origin) and pools[origin] or nil
    end
    local units, label, scary
    if type(pool) == "table" and #pool > 0 then
        local total = 0
        for _, comp in ipairs(pool) do
            total += tonumber(comp.weight) or 0
        end
        local chosen = pool[#pool]
        if total > 0 then
            local roll = math.random() * total
            for _, comp in ipairs(pool) do
                roll -= tonumber(comp.weight) or 0
                if roll <= 0 then
                    chosen = comp
                    break
                end
            end
        end
        units, label, scary = chosen.units, chosen.label, chosen.scary == true
    else
        units = {
            {
                enemy = self:_patrolEnemyId(cfg, part),
                count = math.max(1, math.floor(cfg.band_size or 4)),
            },
        }
    end
    -- clamp total head count so a mis-edited pool can't field a horde; emit { id } specs
    local cap = math.max(1, math.floor(tonumber(cfg.max_band_units) or 8))
    local specs = {}
    for _, u in ipairs(units) do
        for _ = 1, math.max(1, math.floor(tonumber(u.count) or 1)) do
            if #specs >= cap then
                break
            end
            specs[#specs + 1] = { id = u.enemy }
        end
    end
    return specs, label, scary
end

-- How many crystals have spawned into a zone's ore folder. The patrol gates group spawning on this
-- (Jason: "make sure the crystals respond into the environment prior to spawning any baddies") — no
-- ore yet means no patrol route and no baddies, so bands follow the world in rather than precede it.
function EnemyService:_zoneCrystalCount(areaId)
    if not areaId then
        return 0
    end
    local game = Workspace:FindFirstChild("Game")
    local breakables = game and game:FindFirstChild("Breakables")
    local crystals = breakables and breakables:FindFirstChild("Crystals")
    local folder = crystals and crystals:FindFirstChild(areaId)
    if not folder then
        return 0
    end
    local n = 0
    for _, inst in ipairs(folder:GetDescendants()) do
        if inst:IsA("Model") and inst:GetAttribute("MiningLevel") ~= nil then
            n += 1
        end
    end
    return n
end

-- Despawn any enemy tagged to this cave that the band is no longer tracking (a stray whose handle we
-- lost). Called before fielding a fresh group so "only one group" holds even if tracking drifted.
-- Never touches an enemy that is mid-fight (aggro'd).
function EnemyService:_despawnOrphanBandMembers(part, band)
    local tracked = {}
    for _, id in ipairs(band.members) do
        tracked[id] = true
    end
    for id, e in pairs(self._enemies) do
        if e.patrolBand == part and not tracked[id] and not e.aggroPlayerName then
            self:_despawnEnemy(id)
        end
    end
end

function EnemyService:_updateBand(part, player, cfg, now, dt)
    self._bands = self._bands or {}
    local band = self._bands[part]
    if not band then
        local areaId = self:_caveAreaId(part) -- scope crystal stops to THIS zone's ore only
        band = {
            cave = part.Position, -- home base (the spawner part): sorties start AND end here
            anchor = part.Position,
            areaId = areaId,
            stops = self:_patrolWaypoints(part.Position, cfg.patrol_radius, cfg.waypoints, areaId),
            stopIdx = 1, -- which outbound crystal stop we're heading to
            returning = false, -- true = heading back to the cave
            dwellUntil = 0,
            members = {},
        }
        self._bands[part] = band
    end

    -- self-heal: if no crystal stops were found yet (only the cave fallback), re-roll until real
    -- crystal stops exist so the next sortie has valid ground to patrol.
    if #band.stops <= 1 and not band.returning then
        band.stops =
            self:_patrolWaypoints(part.Position, cfg.patrol_radius, cfg.waypoints, band.areaId)
        band.stopIdx = 1
    end

    -- prune dead/despawned members from tracking
    local alive = {}
    for _, id in ipairs(band.members) do
        local e = self._enemies[id]
        if e and e.model and e.model.Parent and (e.model:GetAttribute("HP") or 0) > 0 then
            alive[#alive + 1] = id
        end
    end
    band.members = alive

    -- ONE GROUP AT A TIME (Jason: "despawn a group prior to spawning another so there's only one
    -- group"). We do NOT trickle-refill losses — that read as a second group spawning from the cave
    -- mid-fight. A fresh FULL group is fielded only once the previous one is entirely gone, after a
    -- respawn beat, and only after the zone's crystals have populated (baddies follow ore, never
    -- precede it). The composition is rolled fresh each sortie (varied mix; one rare scary pack).
    -- Spawned NEUTRAL so they patrol until they perceive a player.
    if #band.members == 0 then
        if (band.respawnAt or 0) == 0 then
            local lo = tonumber(cfg.group_respawn_min) or 6
            local hi = tonumber(cfg.group_respawn_max) or 14
            band.respawnAt = now + lo + math.random() * math.max(0, hi - lo)
        end
        if now >= band.respawnAt and self:_zoneCrystalCount(band.areaId) > 0 then
            self:_despawnOrphanBandMembers(part, band) -- defensive: clear any untracked stragglers
            -- reset to the cave for a clean sortie, then field the whole group at once
            band.anchor = band.cave
            band.returning = false
            band.stops =
                self:_patrolWaypoints(part.Position, cfg.patrol_radius, cfg.waypoints, band.areaId)
            band.stopIdx = 1
            local roster, label, scary = self:_pickPatrolBand(cfg, part) -- varied comp for this sortie
            -- allegiance = the INVADING side (heaven realm -> hell troops, hell realm -> heaven troops)
            local allegiance = self:_caveAllegiance(part)
            band.label, band.scary, band.allegiance = label, scary, allegiance
            local scatter = tonumber(cfg.member_scatter) or 10
            for _, spec in ipairs(roster) do
                local sx = band.anchor.X + (math.random() * 2 - 1) * scatter
                local sz = band.anchor.Z + (math.random() * 2 - 1) * scatter
                local res = self:SpawnEnemy(player, spec.id, {
                    position = Vector3.new(sx, band.anchor.Y + 3, sz),
                    def = spec.def, -- synthesized pet-invader def (nil for normal element packs)
                })
                if res and res.ok and res.targetId then
                    local e = self._enemies[res.targetId]
                    if e then
                        self:_setAggroOwner(e, nil) -- start unaware: patrol, don't beeline the cave
                        e.patrolBand = part
                        e.home = band.anchor
                        e.spawnedAt = now
                        e.allegiance = allegiance -- which side this invader fights for (themed content keys off this)
                        if e.model and allegiance then
                            e.model:SetAttribute("PatrolAllegiance", allegiance)
                        end
                        band.members[#band.members + 1] = res.targetId
                    end
                end
            end
            band.respawnAt = 0 -- group fielded; clock re-arms when this group is wiped
        end
    end

    -- CAVE SORTIE: walk the anchor cave -> crystal stops -> back to the cave -> rest -> repeat (with
    -- fresh stops each sortie). The cave is the bookend; "only one patrol at a time" per area = this
    -- single band cycling out and back, never a second concurrent route.
    if now >= (band.dwellUntil or 0) then
        local target = band.returning and band.cave or (band.stops[band.stopIdx] or band.cave)
        local to = Vector3.new(target.X - band.anchor.X, 0, target.Z - band.anchor.Z)
        local distXZ = to.Magnitude
        if distXZ <= (cfg.arrive_dist or 6) then
            if band.returning then
                -- home at the cave: rest, then plan a fresh sortie
                local lo = tonumber(cfg.cave_rest_min) or 5
                local hi = tonumber(cfg.cave_rest_max) or 10
                band.dwellUntil = now + lo + math.random() * math.max(0, hi - lo)
                band.stops = self:_patrolWaypoints(
                    part.Position,
                    cfg.patrol_radius,
                    cfg.waypoints,
                    band.areaId
                )
                band.stopIdx = 1
                band.returning = false
            else
                -- reached a crystal stop: pause, then next stop (or turn back after the last)
                local lo = tonumber(cfg.dwell_min) or 2
                local hi = tonumber(cfg.dwell_max) or 5
                band.dwellUntil = now + lo + math.random() * math.max(0, hi - lo)
                band.stopIdx += 1
                if band.stopIdx > #band.stops then
                    band.returning = true -- patrolled the stops; head home to the cave
                end
            end
        else
            local step = math.min(distXZ, (cfg.anchor_speed or 8) * (dt or 0.15))
            local dir = to.Unit
            band.anchor = band.anchor + Vector3.new(dir.X * step, 0, dir.Z * step)
        end
    end

    -- the moving anchor IS each idle member's loiter home, so the band strolls the route together;
    -- aggro'd members keep chasing (their home updates for when they disengage and return)
    for _, id in ipairs(band.members) do
        local e = self._enemies[id]
        if e and not e.aggroPlayerName then
            e.home = band.anchor
        end
    end
end

function EnemyService:_patrolTick(now, dt)
    local cfg = self._combatConfig and self._combatConfig.enemy_patrol
    if not cfg or cfg.enabled ~= true then
        return
    end

    -- GLOBAL STRAY SWEEP (Jason's safety net): retire any patrol enemy whose cave is gone (map
    -- reload / band torn down) or that has outlived member_max_age while not in a fight — even if its
    -- band isn't ticking this frame (its realm emptied of players). Catches strays no live band would
    -- prune. Runs before the per-band update so an aged member frees its band to field the next group.
    local maxAge = tonumber(cfg.member_max_age) or 240
    for id, e in pairs(self._enemies) do
        if e.patrolBand ~= nil and not e.aggroPlayerName then
            local cave = e.patrolBand
            local orphaned = not (typeof(cave) == "Instance" and cave.Parent ~= nil)
            local aged = maxAge > 0 and (now - (e.spawnedAt or now)) > maxAge
            if orphaned or aged then
                self:_despawnEnemy(id)
            end
        end
    end

    local maps = Workspace:FindFirstChild("Maps")
    if not maps then
        return
    end
    -- realm folders that currently hold a player (one representative player per folder = the
    -- SpawnEnemy anchor; spawn-on-presence avoids the no-player spawn + bounds enemy count)
    local activeFolders = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local layer = player:GetAttribute("CurrentLayer")
        if type(layer) == "string" and layer ~= "" and layer ~= "base" then
            local isRealm = layer:match("^heaven_") or layer:match("^hell_")
            if (not cfg.realm_layers_only) or isRealm then
                local folderName = layer:sub(1, 1):upper() .. layer:sub(2) -- hell_1 -> Hell_1
                local folder = maps:FindFirstChild(folderName)
                if folder and player.Character then
                    activeFolders[folder] = activeFolders[folder] or player
                end
            end
        end
    end
    for folder, player in pairs(activeFolders) do
        for _, part in ipairs(folder:GetChildren()) do
            if part:IsA("BasePart") and part.Name:match("^BaddieSpawner") then
                self:_updateBand(part, player, cfg, now, dt)
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
    self:_dotPass(now) -- tick any burns (DoT) stamped on enemies by pet attacks
    self:_contagionPass(now) -- spread contagion burns to the nearest un-burning enemy (the plague)
    self:_auraDamagePass(now) -- AURA pets damage enemies in a radius around themselves
    self:_enemyHealPass(now)
    self:_enforceLockouts(nowTime) -- #179: hold re-teamed/locked pets down for their recovery
    self:_refreshGroundExclude() -- rebuild the ground-snap raycast filter once for the whole tick
    self:_patrolTick(now, dt) -- roaming hell-realm patrol bands (flag-gated); updates member home anchors
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
                self:_updateHeldBadge(model, nowTime) -- world icon disc above a pinned (held) enemy
            end
        end
    end
    -- COMBAT STANCE: mark each player whose squad has >=1 enemy aggroed on it as InCombat, so
    -- auto-farm pauses (AutoTargetService) and non-engaged pets hold formation instead of mining
    -- (below). Computed AFTER the enemy loop so aggroPlayerName is current; cleared the moment no
    -- enemy is angry at them, so farming auto-resumes.
    if eng.pause_farm_in_combat ~= false then
        local fighting = {}
        for _, entry in pairs(self._enemies) do
            if entry.aggroPlayerName then
                fighting[entry.aggroPlayerName] = true
            end
        end
        for _, pl in ipairs(Players:GetPlayers()) do
            pl:SetAttribute("InCombat", fighting[pl.Name] == true)
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
    -- opts.def lets a caller field a SYNTHESIZED def (e.g. a pet-model invader, see _petEnemyDef)
    -- instead of an enemies.lua entry — the rest of the spawn path is identical (mesh/scale/hp/attack).
    local def = (opts and type(opts.def) == "table" and opts.def)
        or (self._enemiesConfig.enemies and self._enemiesConfig.enemies[enemyId])
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
    -- Half the (scaled) body height: ground-snap sits the pivot this far above the floor so the
    -- model rests ON the terrain. hoverHeight lifts flyers (def.hover_height) above that.
    local halfHeight = 3
    do
        local okE, ext = pcall(function()
            return model:GetExtentsSize()
        end)
        if okE and ext then
            halfHeight = math.max(ext.Y * 0.5, 0.5)
        end
    end
    self._enemies[targetId] = {
        model = model,
        enemyId = enemyId,
        def = def, -- the resolved def (config OR a synthesized pet-invader def); combat reads this
        pos = position,
        aggro = AggroTable.new(),
        lastActiveAt = os.clock(), -- engagement timer seed (idle-despawn clock; refreshed while aggro'd)
        homeArea = self:_areaAt(position), -- territorial: only engages players in this area
        leashRegion = self:_leashRegionAt(position), -- movement pen (hard wall at its boundary)
        halfHeight = halfHeight, -- ground-snap pivot offset
        hoverHeight = tonumber(def.hover_height) or 0, -- flyers float this far above the ground
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
        OverheadBar.setFraction(
            OverheadBar.fillOf(model.PrimaryPart, "HealthBar"),
            hp / math.max(maxHp, 1)
        )
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
