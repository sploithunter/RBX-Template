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
local Players = game:GetService("Players")

local fireGameEvent = require(ReplicatedStorage.Shared.Network.FireGameEvent)
local Enhancements = require(ReplicatedStorage.Shared.Game.Enhancements)
local PowerSelection = require(ReplicatedStorage.Shared.Game.PowerSelection)
local ArchetypeLogic = require(ReplicatedStorage.Shared.Game.ArchetypeLogic)
local AmplifiedBurst = require(ReplicatedStorage.Shared.Game.AmplifiedBurst)
local PowerRegistry = require(ReplicatedStorage.Shared.Game.PowerRegistry)
local PowerStats = require(ReplicatedStorage.Shared.Game.PowerStats)
local Accuracy = require(ReplicatedStorage.Shared.Game.Accuracy)
local CombatRoll = require(ReplicatedStorage.Shared.Game.CombatRoll)
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

-- Archetype → CombatFX element (the per-element colour/look). Mirrors combat_fx.lua archetype_element.
-- Drives the cast/impact VFX so a power reads as its origin (pyro=lava, cryo=ice, …). Generic/white
-- powers have no archetype → they keep the neutral placeholder burst.
local ARCHETYPE_ELEMENT = {
    geomancer = "grass",
    pyromancer = "lava",
    cryomancer = "ice",
    sandwalker = "desert",
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
    self._combatConfig = self._configLoader:LoadConfig("combat") -- accuracy curve for P4 to-hit
    self._enhConfig = self._configLoader:LoadConfig("enhancements") -- slotted-enhancement boosts

    self._cooldowns = setmetatable({}, { __mode = "k" }) -- player -> { powerId -> expiry (os.time) }

    -- Re-stamp PASSIVE (always-on) buffs whenever a player joins / respawns, since their buff
    -- attributes don't survive a rejoin. (In-session picks re-stamp via Select.)
    Players.PlayerAdded:Connect(function(plr)
        self:_watchPlayer(plr)
    end)
    for _, plr in ipairs(Players:GetPlayers()) do
        self:_watchPlayer(plr)
    end
end

-- Families whose `passive = true` powers apply permanently by OWNERSHIP. Each maps to its single
-- axis attribute (sole-occupant — no overwrite). Shared-axis families (coin_yield/luck) wait for
-- additive BuffStack (#169).
local PASSIVE_ATTR = {
    magnet = "MagnetBuff",
    move_speed = "MoveSpeedBuff",
    recharge = "RechargeBuff",
    xp = "XpBuff",
}
local PASSIVE_UNTIL = 4102444800 -- year 2100 — "always on" (same sentinel as the toggle buffs)

function PowerService:_watchPlayer(plr)
    plr.CharacterAdded:Connect(function()
        self:_reapplyPassivesSoon(plr)
    end)
    self:_reapplyPassivesSoon(plr)
end

-- Wait (briefly) for the profile to load, then re-stamp the player's owned passive buffs.
function PowerService:_reapplyPassivesSoon(plr)
    task.spawn(function()
        local deadline = os.clock() + 8
        while os.clock() < deadline do
            if self._dataService and self._dataService:GetData(plr) then
                break
            end
            task.wait(0.25)
        end
        if plr.Parent then
            self:_applyOwnedPassives(plr)
        end
    end)
end

-- Clear every managed passive axis, then re-apply the ones the player currently OWNS (permanent,
-- no timer). Idempotent: call after pick / respec / grant / spawn. Respec (owned empty) clears all.
function PowerService:_applyOwnedPassives(player)
    for _, attr in pairs(PASSIVE_ATTR) do
        player:SetAttribute(attr, nil)
        player:SetAttribute(attr .. "Until", 0)
        player:SetAttribute(attr .. "Toggle", nil)
        player:SetAttribute(attr .. "PowerId", nil)
    end
    local data = self._dataService and self._dataService:GetData(player)
    if not data or type(data.Powers) ~= "table" then
        return
    end
    local kinds = self._powersConfig.effect_kinds or {}
    for _, powerId in ipairs(data.Powers) do
        local def = self._powersConfig.powers[powerId]
        local kind = def and def.effect and kinds[def.effect]
        local attr = kind and kind.passive and PASSIVE_ATTR[kind.family]
        if attr then
            -- POTENCY enhancements scale a passive's magnitude (this stamp IS the
            -- passive's "cast", so the slot fold happens here — Swift runs faster)
            local enhAxes = Enhancements.aggregate(
                self._enhConfig,
                type(data.Slots) == "table" and data.Slots[tostring(powerId)] or {},
                tonumber(player:GetAttribute("Level")) or 1
            )
            -- a passive's magnitude takes BOTH axes: potency (magnitude) and — for
            -- radius-magnitude passives like Magnet — range (radius). Additive, per
            -- the stacking model. (Range on Magnet did nothing before this.)
            local boost = (enhAxes.magnitude or 0) + (enhAxes.radius or 0)
            player:SetAttribute(attr, kind.magnitude * (1 + boost))
            player:SetAttribute(attr .. "Until", PASSIVE_UNTIL)
            player:SetAttribute(attr .. "Toggle", true) -- permanent: HUDs show no countdown
            player:SetAttribute(attr .. "PowerId", powerId)
        end
    end
end

-- Public re-stamp (called after respec / admin grant from other services).
function PowerService:ReapplyPassives(player)
    self:_applyOwnedPassives(player)
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

-- All alive farm nodes (crystals/ore) — Models under Game.Breakables/<type>/<world> with HP > 0.
-- These are NOT enemies (no EnemyId); a target-strength debuff (vulnerable) speeds mining the same
-- way it speeds combat. #174: farming powers reach crystals through the pets, just like enemies.
local function breakablesAlive()
    local game = Workspace:FindFirstChild("Game")
    local root = game and game:FindFirstChild("Breakables")
    local out = {}
    if root then
        for _, desc in ipairs(root:GetDescendants()) do
            if
                desc:IsA("Model")
                and (desc:GetAttribute("HP") or 0) > 0
                and not desc:GetAttribute("EnemyId")
            then
                out[#out + 1] = desc
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

-- The single ENEMY the squad is actually fighting — for single-target powers (Wildfire's seed,
-- single-target DoT/debuff). Position-independent: resolves a targetId to a model via the enemy's
-- `BreakableID` child (the same id pets store in TargetID and the player stores in CombatAssistTarget).
-- Priority: the player's assist target (their directed pick) → else the enemy the MOST pets are
-- attacking. nil if the squad isn't engaged with any enemy.
function PowerService:_engagedEnemy(player)
    local function modelForId(id)
        if not id or id == 0 then
            return nil
        end
        for _, e in ipairs(enemiesAlive()) do
            local bid = e:FindFirstChild("BreakableID")
            if bid and bid.Value == id then
                return e
            end
        end
        return nil
    end

    -- 1) player-directed assist target always wins (the one they selected)
    local assisted = modelForId(player:GetAttribute("CombatAssistTarget"))
    if assisted then
        return assisted
    end

    -- 2) else the enemy the most pets are currently attacking
    local pets = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not pets then
        return nil
    end
    local counts = {}
    for _, pet in ipairs(pets:GetChildren()) do
        if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
            local tid = pet:FindFirstChild("TargetID")
            local tt = pet:FindFirstChild("TargetType")
            if tid and tid.Value ~= 0 and tt and tostring(tt.Value) == "Enemy" then
                counts[tid.Value] = (counts[tid.Value] or 0) + 1
            end
        end
    end
    local bestId, bestN
    for id, n in pairs(counts) do
        if not bestN or n > bestN then
            bestId, bestN = id, n
        end
    end
    return modelForId(bestId)
end

-- Crystals the squad is engaged with (#174). Mirrors _hasEngagedEnemy's primary signal: a pet whose
-- TargetID is set and TargetType is NOT "Enemy" is mining that exact node. We resolve those ids to
-- crystal Models by their `BreakableID` child — position-INDEPENDENT, because pets are moved on the
-- client (RenderStepped), so their server-side PrimaryPart.Position is unreliable for a proximity
-- check. Returns exactly the crystals the squad's pets are mining (so the debuff lands on them).
function PowerService:_engagedBreakables(player)
    local pets = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not pets then
        return {}
    end
    -- collect the target ids of every pet currently mining a node (non-enemy target)
    local wanted = {}
    local anyMining = false
    for _, pet in ipairs(pets:GetChildren()) do
        if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
            local tid = pet:FindFirstChild("TargetID")
            local ttype = pet:FindFirstChild("TargetType")
            if tid and tid.Value ~= 0 and ttype and tostring(ttype.Value) ~= "Enemy" then
                wanted[tid.Value] = true
                anyMining = true
            end
        end
    end
    if not anyMining then
        return {}
    end
    -- resolve those ids to the alive crystal Models (BreakableID child, or BreakableId attribute)
    local out = {}
    for _, c in ipairs(breakablesAlive()) do
        local idChild = c:FindFirstChild("BreakableID")
        local cid = (idChild and idChild.Value)
            or c:GetAttribute("BreakableId")
            or c:GetAttribute("BreakableID")
        if cid and wanted[cid] then
            out[#out + 1] = c
        end
    end
    return out
end

-- True when a farm-targeting power may fire: the squad is mining crystals (#174). Cheap wrapper.
function PowerService:_hasEngagedFarmTarget(player)
    return #self:_engagedBreakables(player) > 0
end

-- Apply a cast power's SUPPORT effect (no direct damage — see configs/powers.lua). `powerId` is
-- stamped onto each buff it applies (CombatShieldPowerId / DefenseBuffPowerId / PetDamageBuffPowerId)
-- so every UI surface resolves the SAME icon for it via PetBadge.forPower (no generic fallbacks).
-- Which of the player's pets a buff applies to. Squad-wide by default; a power whose def carries
-- target="single_pet" applies to ONE pet — the player's selected squad card (CombatBuffTarget = a
-- PositionNumber), falling back to the first non-downed pet when nothing is selected (quick test).
function PowerService:_targetPets(player, powerId)
    local folder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not folder then
        return {}
    end
    local live = {}
    for _, pet in ipairs(folder:GetChildren()) do
        if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") then
            live[#live + 1] = pet
        end
    end
    local def = self._powersConfig.powers and self._powersConfig.powers[powerId]
    if not (def and def.target == "single_pet") then
        return live -- squad-wide
    end
    local sel = player:GetAttribute("CombatBuffTarget")
    if sel and sel ~= 0 then
        for _, pet in ipairs(live) do
            local pn = pet:FindFirstChild("PositionNumber")
            if pn and pn.Value == sel then
                return { pet }
            end
        end
    end
    return live[1] and { live[1] } or {} -- fallback: first non-downed pet
end

-- A player-wide AXIS buff (coin_yield / mining / luck / move_speed / recharge / xp). Stored as a
-- FRACTION (+0.5 = +50%) + a timer + the power id (for the badge). Consumers sum it via BuffStack
-- alongside any aura on the same axis (additive, never compounding — docs Part E).
function PowerService:_setAxisBuff(player, attr, frac, now, dur, powerId)
    player:SetAttribute(attr, frac)
    player:SetAttribute(attr .. "Until", now + (dur or 0))
    player:SetAttribute(attr .. "PowerId", powerId)
end

-- #180: a TOGGLE buff (Hasten / Super Speed) — cast to turn ON (permanent, no countdown), cast again
-- to turn OFF. The `*Toggle` flag marks it permanent so HUDs show no timer; `*Until` is set far in the
-- future so the same `Until > now` consumers keep applying it without any other change.
local TOGGLE_PERMANENT_UNTIL = 4102444800 -- year 2100 — effectively "on until toggled off"
function PowerService:_toggleAxisBuff(player, attr, frac, powerId)
    if player:GetAttribute(attr .. "Toggle") == true then
        player:SetAttribute(attr, nil)
        player:SetAttribute(attr .. "Until", 0)
        player:SetAttribute(attr .. "Toggle", nil)
        player:SetAttribute(attr .. "PowerId", nil)
    else
        player:SetAttribute(attr, frac)
        player:SetAttribute(attr .. "Until", TOGGLE_PERMANENT_UNTIL)
        player:SetAttribute(attr .. "Toggle", true)
        player:SetAttribute(attr .. "PowerId", powerId)
    end
end

-- Teleport the player's character to `pos` (a Vector3) or, if nil, the world spawn (World Travel /
-- recall fallback). A small lift keeps them above the floor.
function PowerService:_teleportPlayer(player, pos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end
    local target = pos
    if typeof(target) ~= "Vector3" then
        local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
        target = spawn and spawn.Position
    end
    if typeof(target) == "Vector3" then
        hrp.CFrame = CFrame.new(target + Vector3.new(0, 4, 0))
    end
end

-- Heal one pet by `amount` endurance (shared by heal / fortify / heal_blind / summon families).
function PowerService:_healPet(player, pet, amount, now)
    if not (pet and pet:IsA("Model")) or pet:GetAttribute("CombatDowned") then
        return
    end
    amount = tonumber(amount) or 0
    local taken = pet:GetAttribute("CombatDamageTaken") or 0
    if amount <= 0 or taken <= 0 then
        return
    end
    local healed = math.min(taken, amount)
    pet:SetAttribute("CombatDamageTaken", math.max(0, taken - amount))
    pet:SetAttribute("HealFxUntil", now + 3)
    if healed >= 1 then
        Signals.Combat_Heal:FireClient(player, { target = pet, amount = math.floor(healed + 0.5) })
    end
end

-- Heal-over-time: heal the WHOLE squad `perTick` every `tickSeconds` for `totalSeconds`. Re-resolves
-- the squad each tick so it heals whoever is alive (Living Mountain's standing aura, Oasis's tail).
function PowerService:_healOverTime(player, perTick, tickSeconds, totalSeconds)
    perTick = tonumber(perTick) or 0
    tickSeconds = tonumber(tickSeconds) or 2
    totalSeconds = tonumber(totalSeconds) or 0
    if perTick <= 0 or totalSeconds <= 0 then
        return
    end
    task.spawn(function()
        local elapsed = 0
        while elapsed < totalSeconds do
            task.wait(tickSeconds)
            elapsed += tickSeconds
            if not player.Parent then
                return
            end
            local pets = Workspace:FindFirstChild("PlayerPets")
                and Workspace.PlayerPets:FindFirstChild(player.Name)
            if pets then
                local nowT = os.time()
                for _, pet in ipairs(pets:GetChildren()) do
                    if pet:IsA("Model") then
                        self:_healPet(player, pet, perTick, nowT)
                    end
                end
            end
        end
    end)
end

-- Ramp a vulnerability mark UPWARD from `fromMag` to `toMag` over `totalSeconds` (Inferno Brand:
-- the longer it burns, the deeper it bites). Re-stamps only enemies still carrying THIS brand.
function PowerService:_rampVulnerable(player, fromMag, toMag, totalSeconds, powerId)
    fromMag = tonumber(fromMag) or 1
    toMag = tonumber(toMag) or fromMag
    totalSeconds = tonumber(totalSeconds) or 0
    if toMag <= fromMag or totalSeconds <= 0 then
        return
    end
    task.spawn(function()
        local elapsed = 0
        while elapsed < totalSeconds do
            task.wait(1)
            elapsed += 1
            if not player.Parent then
                return
            end
            local m = fromMag + (toMag - fromMag) * math.min(1, elapsed / totalSeconds)
            local nowT = os.time()
            for _, enemy in ipairs(enemiesAlive()) do
                if
                    enemy:GetAttribute("DebuffPowerId") == powerId
                    and (enemy:GetAttribute("VulnerableUntil") or 0) > nowT
                then
                    enemy:SetAttribute("VulnerableMult", m)
                end
            end
        end
    end)
end

-- Summon-guardian capstones (Gaia's Colossus / Genie of the Dunes) — delegate to SummonService,
-- which spawns the guardian model, applies its standing squad buffs / revive+heal, trails the
-- player and despawns. Resolved at runtime so PowerService doesn't hard-depend on it.
function PowerService:_summonGuardian(player, kind, now, powerId)
    local summon = self._moduleLoader and self._moduleLoader:Get("SummonService")
    if summon and summon.Summon then
        summon:Summon(player, kind, now, powerId)
    end
end

-- Damage-over-time: the power itself chips `perTick` HP off enemies every `interval` for
-- `totalSeconds` — independent of pet damage. Reduces the enemy's HP directly; EnemyService's
-- HP-changed watcher handles death + loot when it crosses 0, and we credit this player's Contrib
-- ledger so a DoT kill still pays out (same ledger PetFollowService:_mine writes).
--
-- Damage is a FLOAT and is deliberately NOT floored: a "minor" DoT (per_tick < 1) chips enemies
-- down a fraction of an HP per tick instead of rounding to zero. HP is a Roblox number attribute
-- (a double), so fractional HP is fine and the watcher still fires at <= 0.
--
-- aoe=true ticks every alive enemy (an AoE burn field); aoe=false ticks the single primary target
-- (a targeted brand). Re-resolves the target set each tick, so it burns whoever is alive now.
-- P5: the per-tick crit chance, source-agnostic — the power's own critBase PLUS the live
-- player CritBuff (Critical Strike) PLUS pet CritAura (a crit-buffer pet). The same channels the
-- pet-attack crit sums (PetFollowService), so a DoT crits whenever the squad's crit is up. Read
-- fresh each tick so a buff that expires mid-burn stops boosting. 0 by default ⇒ no crit ⇒ ×1.
function PowerService:_dotCritChance(player, critBase, now)
    local add = tonumber(critBase) or 0
    if (player:GetAttribute("CritBuffUntil") or 0) > now then
        add = add + (player:GetAttribute("CritBuff") or 0)
    end
    if (player:GetAttribute("CritAuraUntil") or 0) > now then
        add = add + (player:GetAttribute("CritAura") or 0)
    end
    return math.clamp(add, 0, 0.9)
end

function PowerService:_damageOverTime(
    player,
    perTick,
    interval,
    totalSeconds,
    aoe,
    powerId,
    critBase
)
    perTick = tonumber(perTick) or 0
    interval = math.max(0.1, tonumber(interval) or 1)
    totalSeconds = tonumber(totalSeconds) or 0
    if perTick <= 0 or totalSeconds <= 0 then
        return
    end
    local critMult = (
        self._combatConfig
        and self._combatConfig.rolls
        and self._combatConfig.rolls.pet_attack
        and self._combatConfig.rolls.pet_attack.crit_mult
    ) or 2.0
    task.spawn(function()
        local elapsed = 0
        while elapsed < totalSeconds do
            task.wait(interval)
            elapsed += interval
            if not player.Parent then
                return
            end
            local targets
            if aoe then
                targets = enemiesAlive()
            else
                -- single-target DoT burns the ENEMY THE SQUAD IS FIGHTING (assist target / most-
                -- targeted), not an arbitrary first-in-list. Falls back to any alive enemy.
                local primary = self:_engagedEnemy(player) or enemiesAlive()[1]
                targets = primary and { primary } or {}
            end
            local now = os.time()
            local critChance = self:_dotCritChance(player, critBase, now)
            for _, enemy in ipairs(targets) do
                self:_dotHit(
                    player,
                    enemy,
                    perTick,
                    critChance,
                    critMult,
                    now,
                    powerId,
                    math.ceil(interval) + 1
                )
            end
        end
    end)
end

-- Apply ONE DoT tick to a single enemy: per-tick crit roll (×1 / ×crit_mult), FLOAT damage (minor
-- DoT <1 still chips), Contrib credit, crit tell, and keep the debuff badge lit. Shared by the
-- generic DoT loop and the wildfire burn so damage application stays identical.
function PowerService:_dotHit(player, enemy, perTick, critChance, critMult, now, powerId, badgeSecs)
    if not (enemy and enemy.Parent) then
        return
    end
    local hp = enemy:GetAttribute("HP") or 0
    if hp <= 0 then
        return
    end
    local roll = CombatRoll.resolve(
        { hit_chance = 1, crit_chance = critChance, crit_mult = critMult },
        0,
        math.random()
    )
    local tick = perTick * roll.multiplier
    -- SPARK procs (slotted on this power): chance per hit to surge it for +bonus of its
    -- damage. The first proc enhancement — establishes the mechanics (Jason); rare
    -- specialty drops later ride the same Enhancements.procs path.
    local data = self._dataService and self._dataService:GetData(player)
    local slots = data and type(data.Slots) == "table" and data.Slots[tostring(powerId)]
    if slots then
        for _, proc in
            ipairs(
                Enhancements.procs(
                    self._enhConfig,
                    slots,
                    tonumber(player:GetAttribute("Level")) or 1
                )
            )
        do
            if proc.trigger == "hit" and math.random() < proc.chance then
                tick = tick * (1 + proc.bonus)
                enemy:SetAttribute("CritFxUntil", now + 1) -- surge tell (own VFX later)
            end
        end
    end
    local newHp = math.max(0, hp - tick) -- EnemyService HP-watcher -> death + loot
    enemy:SetAttribute("HP", newHp)
    self:_creditDot(enemy, player, hp - newHp)
    if roll.crit then
        enemy:SetAttribute("CritFxUntil", now + 1) -- crit tell (client, P6)
    end
    enemy:SetAttribute("DebuffPowerId", powerId)
    enemy:SetAttribute("DebuffUntil", now + (badgeSecs or 2))
end

-- Record DoT damage in the enemy's Contrib ledger (a NumberValue per UserId under the model) so the
-- kill credits this player for loot — the same ledger pet damage writes to in PetFollowService:_mine.
function PowerService:_creditDot(enemy, player, amount)
    if amount <= 0 then
        return
    end
    local contrib = enemy:FindFirstChild("Contrib")
    if not contrib then
        return
    end
    local key = tostring(player.UserId)
    local nv = contrib:FindFirstChild(key)
    if not nv then
        nv = Instance.new("NumberValue")
        nv.Name = key
        nv.Parent = contrib
    end
    nv.Value = nv.Value + amount
end

function PowerService:_applyEffect(player, kind, now, powerId)
    local family = kind.family
    local mag = kind.magnitude or 0
    local dur = kind.duration or 0
    -- A `dot` block layers damage-over-time on top of whatever the family does (a vulnerable MARK
    -- that also burns, an ice HOLD that chips). Generic — any power opts in via config. aoe=true
    -- hits every alive enemy; aoe=false the single primary target. Fires alongside the family below.
    -- EXCEPTION: burn_spread (Wildfire) owns its own burn INSIDE _burnSpread, gated to the enemies
    -- actually on fire (contagion) rather than every enemy — so the damage follows the visible spread.
    if kind.dot and family ~= "burn_spread" then
        self:_damageOverTime(
            player,
            kind.dot.per_tick,
            kind.dot.interval or 1,
            kind.dot.duration or dur,
            kind.dot.aoe,
            powerId,
            kind._critBase -- P5: power's own crit chance (+ live CritBuff/CritAura per tick)
        )
    end
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
        -- Oasis: a heal-over-time tail follows the big upfront pulse (`hot`/tick for `hot_seconds`).
        if tonumber(kind.hot) then
            self:_healOverTime(player, kind.hot, kind.hot_tick or 2, kind.hot_seconds or dur)
        end
    elseif family == "buff" then
        player:SetAttribute("PetDamageBuff", mag)
        player:SetAttribute("PetDamageBuffUntil", now + dur)
        player:SetAttribute("PetDamageBuffPowerId", powerId)
    elseif family == "absorb" then
        -- shield: add an absorption pool the pet soaks damage with before endurance. With a
        -- duration it ALSO times out (no permanent armor): stamp CombatShieldUntil + schedule a
        -- clear; a re-cast pushes the stamp later so an older timer won't drop a fresh shield.
        -- Squad-wide unless the power is single_pet (-> the selected pet only).
        local evadeHeal = tonumber(kind.evade_heal)
        for _, pet in ipairs(self:_targetPets(player, powerId)) do
            -- Tag the power BEFORE CombatShield. The client resolves the LOOK (bubble vs dodge) from
            -- CombatShieldPowerId's combat_vfx config and reacts to the CombatShield change — so the
            -- id must already be present, else the look resolves wrong for a frame. (The on-hit
            -- "Dodge!" is also config-driven from combat_vfx.on_hit, read server-side in EnemyService.)
            pet:SetAttribute("CombatShieldPowerId", powerId)
            pet:SetAttribute("CombatShield", (pet:GetAttribute("CombatShield") or 0) + mag)
            if dur and dur > 0 then
                pet:SetAttribute("CombatShieldUntil", now + dur)
                -- Mirage Veil: while the veil is up, each blow it turns aside also heals the pet a
                -- little (heal-on-evade). EnemyService reads MirageHeal* in its shield-absorb path.
                if evadeHeal then
                    pet:SetAttribute("MirageHealAmt", evadeHeal)
                    pet:SetAttribute("MirageHealUntil", now + dur)
                end
                task.delay(dur, function()
                    if pet.Parent and (pet:GetAttribute("CombatShieldUntil") or 0) <= os.time() then
                        pet:SetAttribute("CombatShield", 0)
                        pet:SetAttribute("CombatShieldUntil", 0)
                    end
                end)
            end
        end
    elseif family == "defense_buff" then
        -- armor: temporary +Defense (damage reduction on the armor curve). Squad-wide (Bulwark)
        -- unless the power is single_pet (-> the selected pet only).
        for _, pet in ipairs(self:_targetPets(player, powerId)) do
            pet:SetAttribute("DefenseBuff", mag)
            pet:SetAttribute("DefenseBuffUntil", now + dur)
            pet:SetAttribute("DefenseBuffPowerId", powerId)
        end
    elseif family == "coin_yield" then
        self:_setAxisBuff(player, "CoinYieldPower", mag, now, dur, powerId)
    elseif family == "crit" then
        self:_setAxisBuff(player, "CritBuff", mag, now, dur, powerId) -- +crit chance on pet hits (Critical Strike)
    elseif family == "luck" then
        self:_setAxisBuff(player, "LuckBuff", mag, now, dur, powerId)
    elseif family == "move_speed" then
        if kind.toggle then -- Super Speed: permanent toggle
            self:_toggleAxisBuff(player, "MoveSpeedBuff", mag, powerId)
        else
            self:_setAxisBuff(player, "MoveSpeedBuff", mag, now, dur, powerId)
        end
    elseif family == "recharge" then
        if kind.toggle then -- Hasten: permanent toggle
            self:_toggleAxisBuff(player, "RechargeBuff", mag, powerId)
        else
            self:_setAxisBuff(player, "RechargeBuff", mag, now, dur, powerId)
        end
    elseif family == "xp" then
        self:_setAxisBuff(player, "XpBuff", mag, now, dur, powerId)
    elseif family == "revive" then
        -- Revive: instantly bring a DOWNED pet back, ignoring its recharge cooldown (the tactical
        -- "summon before the clock" power, EnemyService:_revivePet's clears). Prefers the selected
        -- squad pet (CombatBuffTarget), else the first downed pet.
        local pets = Workspace:FindFirstChild("PlayerPets")
            and Workspace.PlayerPets:FindFirstChild(player.Name)
        if pets then
            local sel = player:GetAttribute("CombatBuffTarget")
            local target, firstDowned
            for _, pet in ipairs(pets:GetChildren()) do
                if pet:IsA("Model") and pet:GetAttribute("CombatDowned") then
                    firstDowned = firstDowned or pet
                    local pn = pet:FindFirstChild("PositionNumber")
                    if sel and sel ~= 0 and pn and pn.Value == sel then
                        target = pet
                    end
                end
            end
            target = target or firstDowned
            if target then
                target:SetAttribute("CombatDowned", false)
                target:SetAttribute("CombatDamageTaken", 0)
                target:SetAttribute("CooldownUntil", 0)
                target:SetAttribute("DownedReason", "")
                fireGameEvent(player, "pet_revive", { pet = target.Name })
            end
        end
    elseif family == "recall" then
        -- Recall: teleport to the player's saved spot (RecallPoint, stamped on each hatch), else
        -- the world spawn — the AFK-farmer "get back to where I was" QoL.
        self:_teleportPlayer(player, player:GetAttribute("RecallPoint"))
    elseif family == "world_travel" then
        self:_teleportPlayer(player, nil) -- to the world hub (spawn)
    elseif family == "magnet" then
        -- #167: widen the drop auto-collect radius by `magnitude` studs for `duration`s. DropService's
        -- collect loop reads MagnetBuff while MagnetBuffUntil is live (a flat studs bonus, not an axis).
        player:SetAttribute("MagnetBuff", mag)
        player:SetAttribute("MagnetBuffUntil", now + dur)
        player:SetAttribute("MagnetBuffPowerId", powerId)
    elseif family == "root" then
        for _, enemy in ipairs(enemiesAlive()) do
            if self:_accuracyHit(player, enemy, kind) then -- P4: a hold can be resisted (per target)
                enemy:SetAttribute("RootedUntil", now + dur)
                -- stamp WHICH power debuffed it, so the client can show the matching badge above it
                -- (alongside the aura) instead of leaving you to decode the particle colour.
                enemy:SetAttribute("DebuffPowerId", powerId)
                enemy:SetAttribute("DebuffUntil", now + dur)
            end
        end
    elseif family == "vulnerable" then
        -- Shatter: x`frozen_bonus` again on FROZEN (rooted) targets — the freeze->shatter payoff.
        local frozenBonus = tonumber(kind.frozen_bonus)
        for _, enemy in ipairs(enemiesAlive()) do
            if self:_accuracyHit(player, enemy, kind) then -- P4: the mark can miss (per target)
                local m = mag
                if frozenBonus and (enemy:GetAttribute("RootedUntil") or 0) > now then
                    m = mag * frozenBonus
                end
                enemy:SetAttribute("VulnerableMult", m)
                enemy:SetAttribute("VulnerableUntil", now + dur)
                enemy:SetAttribute("DebuffPowerId", powerId)
                enemy:SetAttribute("DebuffUntil", now + dur)
            end
        end
        -- Inferno Brand: ramp the mark upward over its lifetime (1.9 -> ramp_to).
        if tonumber(kind.ramp_to) then
            self:_rampVulnerable(player, mag, kind.ramp_to, dur, powerId)
        end
        -- #174: a target-strength debuff also applies to FARMING. Mark the crystals the squad is
        -- mining so pets shred them x`mag` faster (PetFollowService:_mine reads VulnerableMult on
        -- any breakable). Only families flagged farm_targeted reach crystals (root/disarm don't).
        local farmTargeted = self._powersConfig.farm_targeted_families
            and self._powersConfig.farm_targeted_families[family]
        if farmTargeted then
            for _, crystal in ipairs(self:_engagedBreakables(player)) do
                crystal:SetAttribute("VulnerableMult", mag)
                crystal:SetAttribute("VulnerableUntil", now + dur)
                crystal:SetAttribute("DebuffPowerId", powerId)
                crystal:SetAttribute("DebuffUntil", now + dur)
            end
        end
    elseif family == "root_guard" then
        -- Seismic Hold (geomancer signature): ROOT every engaged enemy AND harden the squad. A tank
        -- lockdown — control that also reinforces the shield identity. `magnitude` = the +Defense.
        for _, enemy in ipairs(enemiesAlive()) do
            enemy:SetAttribute("RootedUntil", now + dur)
            enemy:SetAttribute("DebuffPowerId", powerId)
            enemy:SetAttribute("DebuffUntil", now + dur)
        end
        for _, pet in ipairs(self:_targetPets(player, powerId)) do
            pet:SetAttribute("DefenseBuff", mag)
            pet:SetAttribute("DefenseBuffUntil", now + dur)
            pet:SetAttribute("DefenseBuffPowerId", powerId)
        end
    elseif family == "fortify" then
        -- Living Mountain (geomancer signature): big squad +Defense + a heal-over-time. `magnitude`=
        -- +Defense, `heal`=hp per pulse, `hot_tick`=seconds between pulses across the duration.
        local healAmt = tonumber(kind.heal) or 0
        for _, pet in ipairs(self:_targetPets(player, powerId)) do
            pet:SetAttribute("DefenseBuff", mag)
            pet:SetAttribute("DefenseBuffUntil", now + dur)
            pet:SetAttribute("DefenseBuffPowerId", powerId)
            self:_healPet(player, pet, healAmt, now) -- upfront pulse
        end
        if tonumber(kind.hot_tick) then
            self:_healOverTime(player, healAmt, kind.hot_tick, dur)
        end
    elseif family == "heal_blind" then
        -- Simoom (sandwalker signature): heal the squad AND blind/soften enemies caught in the storm
        -- (heal identity + a touch of control). `magnitude`=heal, `vuln`=enemy vulnerability mult.
        for _, pet in ipairs(self:_targetPets(player, powerId)) do
            self:_healPet(player, pet, mag, now)
        end
        local vuln = tonumber(kind.vuln) or 1
        for _, enemy in ipairs(enemiesAlive()) do
            enemy:SetAttribute("VulnerableMult", vuln)
            enemy:SetAttribute("VulnerableUntil", now + dur)
            enemy:SetAttribute("DebuffPowerId", powerId)
            enemy:SetAttribute("DebuffUntil", now + dur)
        end
    elseif family == "summon" then
        -- Gaia's Colossus / Genie of the Dunes (capstones): call a temporary guardian pet. Built in
        -- a follow-up slice (SummonService); for now this is a graceful no-op so the cast still spends
        -- cooldown + plays the cast VFX without erroring.
        self:_summonGuardian(player, kind, now, powerId)
    elseif family == "amplified_burst" then
        self:_amplifiedBurst(player, kind, now)
    elseif family == "burn_spread" then
        self:_burnSpread(player, kind, now, powerId)
    elseif family == "team_cleave" then
        -- Firestorm: for `duration`s every pet swing also splashes x`magnitude` to other enemies
        -- within `cleave_radius` (applied in PetFollowService:_mine). Fire a nova so it reads as on.
        player:SetAttribute("TeamCleaveUntil", now + dur)
        player:SetAttribute("TeamCleaveFrac", mag)
        player:SetAttribute("TeamCleaveRadius", tonumber(kind.cleave_radius) or 8)
        local center = self:_squadCenter(player)
        if center then
            Signals.Power_AreaFx:FireClient(
                player,
                { element = "lava", variant = "self", center = center, pit = false, hits = {} }
            )
        end
    end
end

-- Squad centroid (living pets), else the player's HRP. nil if neither is available.
function PowerService:_squadCenter(player)
    local pets = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    local sx, sy, sz, n = 0, 0, 0, 0
    if pets then
        for _, pet in ipairs(pets:GetChildren()) do
            if pet:IsA("Model") and not pet:GetAttribute("CombatDowned") and pet.PrimaryPart then
                local p = pet.PrimaryPart.Position
                sx, sy, sz, n = sx + p.X, sy + p.Y, sz + p.Z, n + 1
            end
        end
    end
    if n > 0 then
        return Vector3.new(sx / n, sy / n, sz / n)
    end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

-- Wildfire: mark the squad's engaged enemy with a burn (vulnerability), which then CONTAGIONS to
-- nearby enemies every `spread_interval`s for `duration`s. The debuff aura is shown by the client's
-- CombatAuraController (it reacts to VulnerableUntil), so this only needs to set the attributes.
function PowerService:_burnSpread(player, kind, now, powerId)
    local mag = tonumber(kind.magnitude) or 1.5
    local dur = tonumber(kind.duration) or 8
    local spreadR = tonumber(kind.spread_radius) or 14
    local perTick = (kind.dot and tonumber(kind.dot.per_tick)) or 0
    local critBase = kind._critBase
    local critMult = (
        self._combatConfig
        and self._combatConfig.rolls
        and self._combatConfig.rolls.pet_attack
        and self._combatConfig.rolls.pet_attack.crit_mult
    ) or 2.0
    -- tick cadence: the burn damage interval (falls back to spread_interval). Spread happens on the
    -- same beat — an enemy on fire ignites its unlit neighbours each tick.
    local interval = math.max(
        0.5,
        (kind.dot and tonumber(kind.dot.interval)) or tonumber(kind.spread_interval) or 1
    )
    local element = "lava" -- Wildfire = pyromancer; the only burn_spread power today

    local function partOfEnemy(e)
        return e.PrimaryPart or e:FindFirstChildWhichIsA("BasePart")
    end
    local function isBurning(e, t)
        return (e:GetAttribute("BurnUntil") or 0) > t
    end
    -- Catch an enemy on fire: vulnerability mark (pets hit harder) + the burn flag (BurnUntil) that
    -- gates damage AND drives the client fire visual + the debuff badge. Lasts `dur` from ignition.
    local function ignite(enemy, untilT)
        enemy:SetAttribute("VulnerableMult", mag)
        enemy:SetAttribute("VulnerableUntil", untilT)
        enemy:SetAttribute("BurnUntil", untilT)
        enemy:SetAttribute("BurnElement", element)
        enemy:SetAttribute("DebuffPowerId", powerId)
        enemy:SetAttribute("DebuffUntil", untilT)
    end

    -- SEED on the enemy the squad is actually fighting (single-target start), not the enemy nearest
    -- the squad centroid — Wildfire is a single-target contagion, not an AoE. Falls back to the
    -- centroid-nearest only if no engaged target can be resolved.
    local seed = self:_engagedEnemy(player)
    if not seed then
        local center = self:_squadCenter(player)
        local bestD
        for _, e in ipairs(enemiesAlive()) do
            local pp = partOfEnemy(e)
            if pp and center then
                local d = (pp.Position - center).Magnitude
                if not bestD or d < bestD then
                    bestD, seed = d, e
                end
            end
        end
    end
    if not seed then
        return
    end
    ignite(seed, now + dur)

    -- One loop drives BOTH damage and contagion. Each tick: burn every enemy currently on fire, then
    -- spread to unlit neighbours within spreadR. Spreading only happens during the first `dur` window;
    -- damage keeps going until each enemy's own burn expires (a late-caught enemy still burns its full
    -- time). No re-ignition of a still-burning enemy ⇒ the wave passes through the pack and dies out.
    local total = dur * 2 -- covers an enemy lit right at the end of the spread window
    local ticks = math.ceil(total / interval)
    for i = 1, ticks do
        task.delay(i * interval, function()
            if not player.Parent then
                return
            end
            local t = os.time()
            local live = enemiesAlive()
            local burning = {}
            for _, e in ipairs(live) do
                if isBurning(e, t) then
                    burning[#burning + 1] = e
                end
            end
            -- damage everything on fire
            if perTick > 0 then
                local critChance = self:_dotCritChance(player, critBase, t)
                for _, e in ipairs(burning) do
                    self:_dotHit(
                        player,
                        e,
                        perTick,
                        critChance,
                        critMult,
                        t,
                        powerId,
                        math.ceil(interval) + 1
                    )
                end
            end
            -- spread the fire (only while still within the ignition window)
            if (i * interval) <= dur then
                for _, m in ipairs(burning) do
                    local mp = partOfEnemy(m)
                    if mp then
                        for _, u in ipairs(live) do
                            if not isBurning(u, t) then
                                local up = partOfEnemy(u)
                                if up and (up.Position - mp.Position).Magnitude <= spreadR then
                                    ignite(u, t + dur)
                                end
                            end
                        end
                    end
                end
            end
        end)
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
-- Build the `kind` table the effect router consumes from the raw effect_kind, with the SCALABLE
-- axes (magnitude / duration / DoT per-tick + interval) replaced by the resolved EFFECTIVE values.
-- A shallow clone so the shared config table is never mutated; all exotic fields (ramp_to, radius,
-- spread_radius, guardian…) carry through untouched. With no scaling configured, effective == base,
-- so the result is identical to the raw effect_kind (behaviour-neutral until P3 supplies a curve).
function PowerService:_effectiveKind(rawKind, effective)
    local out = {}
    for k, v in pairs(rawKind) do
        out[k] = v
    end
    out.magnitude = effective.magnitude
    out.duration = effective.duration
    if rawKind.dot then
        out.dot = {
            per_tick = effective.damage,
            interval = effective.tick,
            aoe = rawKind.dot.aoe,
        }
    end
    return out
end

-- P4 accuracy: does this hostile application LAND on `enemy`? Rolls accuracyBase × the level-diff
-- to-hit curve (the same Accuracy core pet/enemy attacks use); a boss (Level reads +rank_offset) is
-- harder to hit. On a miss, stamps a transient MissFxUntil for the client tell and returns false so
-- the caller skips this enemy. Crystals never call this (no Level → mining exemption preserved).
function PowerService:_accuracyHit(player, enemy, kind)
    local accBase = tonumber(kind._accuracyBase) or 1
    local casterLevel = tonumber(kind._casterLevel) or 1
    local enemyLevel = tonumber(enemy:GetAttribute("Level")) or casterLevel
    local accCfg = self._combatConfig and self._combatConfig.accuracy
    local chance = math.clamp(accBase * Accuracy.toHit(casterLevel, enemyLevel, accCfg), 0, 1)
    local res = CombatRoll.resolve({ hit_chance = chance }, math.random())
    if not res.hit then
        enemy:SetAttribute("MissFxUntil", os.time() + 2) -- client surfaces the "Miss" tell (P6)
        return false
    end
    return true
end

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

    local rawKind = (
        self._powersConfig.effect_kinds and self._powersConfig.effect_kinds[def.effect]
    ) or { family = "heal", magnitude = 0, duration = 0 }

    -- Route the cast through the unified record (PowerRegistry) → resolved effective stats
    -- (PowerStats). The effect router then consumes RESOLVED values, so P3 scaling / P4 accuracy
    -- slot in here with no further router changes. Today scaling is absent ⇒ effective == base ⇒
    -- `kind` is identical to the raw effect_kind.
    local kind = rawKind
    local record = PowerRegistry.record(tostring(powerId), self._powersConfig)
    -- Slotted ENHANCEMENTS on the cast power -> per-axis bonus fractions (additive within an
    -- axis; single > dual). Feeds resolveEffective + the cooldown stamp below.
    local data = self._dataService and self._dataService:GetData(player)
    local enhAxes = Enhancements.aggregate(
        self._enhConfig,
        (data and type(data.Slots) == "table" and data.Slots[tostring(powerId)]) or {},
        tonumber(player:GetAttribute("Level")) or 1 -- CoH scaling: +2 stronger, -3 dead
    )
    if record then
        local casterLevel = tonumber(player:GetAttribute("Level")) or 1
        local effective = PowerStats.resolveEffective(record, {
            casterLevel = casterLevel,
            scaling = self._powersConfig.scaling, -- nil today ⇒ identity; P3 fills it
            enhancements = enhAxes,
        })
        kind = self:_effectiveKind(rawKind, effective)
        -- carry the accuracy inputs so the per-enemy to-hit roll (P4) can resolve in _applyEffect
        kind._accuracyBase = record.accuracyBase
        kind._casterLevel = casterLevel
        kind._critBase = record.critBase -- P5: per-power crit chance for DoT ticks
    end

    -- Target gate: an offensive power reaches the enemy THROUGH the pets, so it can't fire unless
    -- the squad is engaged with one (the pet is fighting something). Friendly powers (heal/buff/
    -- shield) target your own pets and skip the gate. Refused casts don't spend the cooldown.
    local enemyTargeted = self._powersConfig.enemy_targeted_families
        and self._powersConfig.enemy_targeted_families[kind.family]
    if enemyTargeted and not self:_hasEngagedEnemy(player) then
        -- #174: a farm-targeted debuff (vulnerable) may also fire when the squad is mining crystals,
        -- not just fighting enemies — the pet still has a target, it's just a node.
        local farmTargeted = self._powersConfig.farm_targeted_families
            and self._powersConfig.farm_targeted_families[kind.family]
        if not (farmTargeted and self:_hasEngagedFarmTarget(player)) then
            return { ok = false, reason = "no_target" }
        end
    end

    self:_applyEffect(player, kind, now, tostring(powerId))
    -- Cast VFX. amplified_burst / team_cleave fire their own bespoke area FX inside _applyEffect.
    -- Archetype powers play a caster cast-tell (small `cast_emit` body emission for single-target,
    -- the `cast_burst` ring for AoE powers) and, if hostile, a targeted strike on each engaged enemy
    -- (= registry `eruption`) — same AreaFX the FX-probe previews, element-coloured. Generic/white
    -- powers keep the neutral placeholder ball.
    -- Cast VFX. amplified_burst / team_cleave fire their own bespoke area FX inside _applyEffect.
    -- Everything else resolves per-FAMILY (powers.lua family_fx) → a registry primitive: a `source`
    -- effect on the caster + a `target` effect on each engaged enemy (hostile families). The client
    -- renders via PowerFXRender (element-coloured), with floating "(effect TBD)"/"(sound TBD)" where a
    -- mapping or sound is missing. This is what makes a shield read as a shield, a buff as a buff, etc.
    local family = kind.family
    if family ~= "amplified_burst" and family ~= "team_cleave" then
        local element = (def.archetype and ARCHETYPE_ELEMENT[def.archetype]) or "neutral"
        local generic = def.archetype == nil
        local fx = self._powersConfig.family_fx and self._powersConfig.family_fx[family]
        -- Caster cast-tell resolution (priority order):
        --   1. per-power override (def.fx.source) — hand-authored look for a specific power
        --   2. generic/white powers ⇒ "tbd" placeholder (no element-themed visual yet)
        --   3. friendly family source (heal_nova / aura / shield_bubble) — those read by family, not AoE
        --   4. hostile default by AoE-ness: AoE powers get the `cast_burst` RING (reads as AoE);
        --      single-target ones get the small `cast_emit` body emission ("emits from the player").
        local isAoe = def.target == "targeted_aoe" or def.target == "team_aoe"
        local sourcePrim = (def.fx and def.fx.source)
            or (generic and "tbd")
            or (fx and fx.source)
            or (isAoe and "cast_burst")
            or "cast_emit"
        Signals.Power_AreaFx:FireClient(
            player,
            { primId = sourcePrim, element = element, kind = "source" }
        )
        if not generic and self._powersConfig.enemy_targeted_families[family] then
            local targetPrim = (def.fx and def.fx.target) or (fx and fx.target) or "eruption"
            -- AoE powers land the impact on EVERY enemy; single-target ones land ONLY on the enemy
            -- the squad is fighting (so it doesn't read as an AoE). For Wildfire the seed burns there
            -- and the spread shows via the per-enemy fire as it catches.
            local impactFoes
            if isAoe then
                impactFoes = enemiesAlive()
            else
                local foe = self:_engagedEnemy(player)
                impactFoes = foe and { foe } or {}
            end
            for _, foe in ipairs(impactFoes) do
                if foe.PrimaryPart or foe:FindFirstChildWhichIsA("BasePart") then
                    Signals.Power_AreaFx:FireClient(
                        player,
                        { primId = targetPrim, element = element, kind = "target", target = foe }
                    )
                end
            end
        end
    end

    local cd = tonumber(def.cooldown_seconds) or 0
    -- Slotted RECHARGE enhancements shorten THIS power's cooldown: cd / (1 + Σ values).
    if (enhAxes.recharge or 0) > 0 then
        cd = cd / (1 + enhAxes.recharge)
    end
    -- Hasten (recharge axis): the player's recharge buff shortens every power's cooldown by its
    -- fraction (clamped so a cooldown never hits zero).
    if (player:GetAttribute("RechargeBuffUntil") or 0) > now then
        local r = math.clamp(player:GetAttribute("RechargeBuff") or 0, 0, 0.9)
        cd = cd * (1 - r)
    end
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
    fireGameEvent(player, "power_cast", { power = powerId }) -- bus source (tutorial etc.)
    pcall(function() -- mission counter (quest chain "Cast 5 powers")
        _G.RBXTemplateServices:Get("StatsService"):Increment(player, "powers_cast", 1)
    end)
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

-- Pure pre-check: COULD this power be selected AT `level` right now (no mutation)? Used by the
-- atomic levelup.commit to validate the pick BEFORE claiming the level, so claim+select are
-- all-or-nothing. Returns (ok, reason).
function PowerService:CanSelectAtLevel(player, powerId, level)
    local data = self._dataService:GetData(player)
    if not data then
        return false, "data_not_loaded"
    end
    local available = ArchetypeLogic.availablePowers(data.Archetype, self._archetypesConfig)
    local decision = PowerSelection.canSelect(
        powerId,
        available,
        powersList(data),
        math.max(1, math.floor(tonumber(level) or 1)),
        self._powersConfig.selection_levels
    )
    return decision.ok == true, decision.reason
end

function PowerService:Select(player, powerId, levelOverride)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    -- NOTE: no early no_archetype gate — NATURAL/generic powers are pickable BEFORE the L5 origin
    -- choice. availablePowers(nil) returns just the generic pool, so canSelect accepts generic and
    -- still rejects origin powers (not_in_archetype_pool) until an origin is chosen.
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
    -- Every picked power comes with one FREE inherent slot (flagged so it doesn't draw from the
    -- granted pool — see AugmentationService.allocatedCount). Level grants add the rest, up to 6.
    if type(data.Slots) ~= "table" then
        data.Slots = {}
    end
    if data.Slots[powerId] == nil then
        data.Slots[powerId] = { { inherent = true } }
    end
    self._dataService:RequestSave(player, "power_select", { critical = true })
    self:_applyOwnedPassives(player) -- a passive pick (Magnet/Swift/Hasten/XP) turns on immediately
    -- AUTO-BIND castable picks: a new ACTIVE power lands in the first empty hotbar
    -- slot (Jason: "I would have expected it to go into 1") — passives stay off the
    -- bar (they're always-on; the 10 slots are for casts). Players can still rebind.
    pcall(function()
        local kind = self._powersConfig.effect_kinds[self._powersConfig.powers[powerId].effect]
        local isPassive = kind and (kind.passive == true or kind.toggle == true)
        if not isPassive then
            local locator = _G.RBXTemplateServices
            local hotbar = locator and locator:Get("HotbarService")
            if hotbar and hotbar.GetState and hotbar.Rebind then
                local state = hotbar:GetState(player)
                local binds = (state and state.hotbar) or {}
                local slotCount = (state and state.slot_count) or 10
                local alreadyBound = false
                for _, bind in pairs(binds) do
                    if type(bind) == "table" and bind.target == powerId then
                        alreadyBound = true
                    end
                end
                if not alreadyBound then
                    for i = 1, slotCount do
                        if binds[tostring(i)] == nil then
                            hotbar:Rebind(player, i, { type = "power", target = powerId })
                            break
                        end
                    end
                end
            end
        end
    end)
    -- The hotbar's assign palette is owned-powers; re-push it so the fresh pick shows up in the
    -- Edit picker immediately (it was only pushed on join/rebind, so new picks were missing
    -- until rejoin).
    pcall(function()
        local locator = _G.RBXTemplateServices
        local hotbar = locator and locator:Get("HotbarService")
        if hotbar and hotbar._pushState then
            hotbar:_pushState(player)
        end
    end)
    fireGameEvent(player, "power_selected", { power = powerId }) -- bus source (tutorial etc.)
    return { ok = true, powers = selected }
end

return PowerService
