--[[
    CombatService — Feature 10 (Combat System, Hell-focused).

    Server owner of combat resolution. Composes the pure cores (Targeting,
    CombatMath, FocusMath via CombatSim) with the live services so combat is
    config-driven and bus-testable:

      Simulate(opts)               — deterministic full-fight resolution (read-only;
                                     auto-target + damage + encounter-end + loot +
                                     sundering + pet-down, no state mutation).
      AwardLoot(player, enemyId)   — resolve a defeated enemy's drop table and
                                     credit the player (biome currency + tokens).
      SunderPlayer(player, enemyId)— apply the enemy attack's Focus drain (-> FocusService).
      DownPetInCombat(player,uid,enemyId)
                                   — down a pet at the enemy's tier (-> SpiritFormService,
                                     which auto-returns it from the active squad). This is
                                     the real "combat down" trigger deferred from Phase 3.

    Live enemy spawning, auto-attack traversal, and player-invulnerability visuals
    are [studio]/authored-map work (enemy spawner markers in a Hell combat zone);
    see docs/wiki/CURRENT_STATUS.md. The resolution math + economy/Spirit-Form/Focus
    interconnections are owned + verified here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Targeting = require(ReplicatedStorage.Shared.Game.Targeting)
local CombatMath = require(ReplicatedStorage.Shared.Game.CombatMath)
local FocusMath = require(ReplicatedStorage.Shared.Game.FocusMath)
local CombatSim = require(ReplicatedStorage.Shared.Game.CombatSim)
local PetCombat = require(ReplicatedStorage.Shared.Game.PetCombat)
local XpReward = require(ReplicatedStorage.Shared.Game.XpReward)

local CombatService = {}
CombatService.__index = CombatService

function CombatService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._combatConfig = self._configLoader:LoadConfig("combat")
    self._enemiesConfig = self._configLoader:LoadConfig("enemies")
    self._focusConfig = self._configLoader:LoadConfig("focus")
    -- "Everything you do grants XP": defeating an enemy feeds the level bar (see AwardLoot).
    local okLvl, lvlCfg = pcall(function()
        return self._configLoader:LoadConfig("leveling")
    end)
    self._xpRewards = (okLvl and type(lvlCfg) == "table" and lvlCfg.xp_rewards) or {}
    self._deps = { Targeting = Targeting, CombatMath = CombatMath, FocusMath = FocusMath }
end

-- Runtime locators (these services may not be registered in every build).
function CombatService:_service(name)
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get(name)
    end)
    return ok and service or nil
end

function CombatService:_enemyDef(enemyId)
    return self._enemiesConfig.enemies[enemyId]
end

-- Expand a configured spawner into fight-ready enemy records (HP scaled by party
-- size), spread along +x so nearest-target selection is meaningful.
function CombatService:_expandSpawner(spawnerId, partySize)
    local spawner = self._combatConfig.spawners[spawnerId]
    if not spawner then
        return nil
    end
    local enemies = {}
    local x = 20
    for _, entry in ipairs(spawner.enemies) do
        local def = self:_enemyDef(entry.id)
        if def then
            for _ = 1, entry.count do
                table.insert(enemies, {
                    id = entry.id,
                    hp = CombatMath.groupScaledHp(def.hp, partySize or 1, self._combatConfig),
                    position = { x = x, y = 0, z = 0 },
                    attack = def.attack,
                    drop_table = def.drop_table,
                })
                x += 20
            end
        end
    end
    return enemies
end

-- Deterministic, read-only combat resolution. opts:
--   { spawner = "hell_1_lava", partySize?, petPowers = {..}, buff?, maxRounds?, focusStart? }
--   or { enemies = {..explicit records..}, petPowers = {..}, ... }
function CombatService:Simulate(opts)
    opts = opts or {}
    local partySize = opts.partySize or 1

    local enemies = opts.enemies
    if not enemies and opts.spawner then
        enemies = self:_expandSpawner(opts.spawner, partySize)
    end
    if not enemies then
        return { ok = false, reason = "no_enemies" }
    end

    local pets = {}
    for _, power in ipairs(opts.petPowers or {}) do
        table.insert(pets, { power = power })
    end
    if #pets == 0 then
        return { ok = false, reason = "no_pets" }
    end

    local scenario = {
        enemies = enemies,
        pets = pets,
        buff = opts.buff,
        maxRounds = opts.maxRounds,
        focusStart = opts.focusStart,
    }
    local report = CombatSim.run(
        scenario,
        self._deps,
        { combat = self._combatConfig, focus = self._focusConfig }
    )
    report.spawner = opts.spawner
    return report
end

-- Credit a defeated enemy's deterministic drops to the player (Feature 10:
-- "loot includes biome currency + Shadow Tokens in Hell").
function CombatService:AwardLoot(player, enemyId)
    local def = self:_enemyDef(enemyId)
    if not def then
        return { ok = false, reason = "unknown_enemy" }
    end
    local loot = CombatMath.resolveLoot(def.drop_table)
    local lootTotal = 0
    for currency, amount in pairs(loot) do
        self._dataService:AddCurrency(player, currency, amount, "combat_loot")
        lootTotal += tonumber(amount) or 0
    end
    -- Combat grants XP too: scale off the enemy's loot total so tougher drops = more XP.
    -- AddExperience publishes the XP attribute -> the HUD level bar ticks live.
    local xp = XpReward.fromValue(lootTotal, self._xpRewards and self._xpRewards.combat)
    if xp > 0 then
        local progression = self:_service("PlayerProgressionService")
        if progression and progression.AddExperience then
            progression:AddExperience(player, xp)
        end
    end
    return { ok = true, loot = loot, xp = xp }
end

-- Apply this enemy attack's Sundering Focus drain to the player (Feature 12).
function CombatService:SunderPlayer(player, enemyId)
    local def = self:_enemyDef(enemyId)
    if not def then
        return { ok = false, reason = "unknown_enemy" }
    end
    local amount = CombatMath.sunderAmount(def.attack)
    local focusService = self:_service("FocusService")
    if not focusService then
        return { ok = false, reason = "service_unavailable" }
    end
    local result = focusService:Sunder(player, amount)
    result.amount = amount
    return result
end

-- The real "combat down" trigger (deferred from Phase 3): an enemy downs a pet,
-- which enters Spirit Form at the enemy's content tier and auto-returns from the
-- active squad (Features 7 + 9).
function CombatService:DownPetInCombat(player, uid, enemyId)
    local def = self:_enemyDef(enemyId)
    if not def then
        return { ok = false, reason = "unknown_enemy" }
    end
    local spirit = self:_service("SpiritFormService")
    if not spirit then
        return { ok = false, reason = "service_unavailable" }
    end
    local result = spirit:Down(player, uid, def.tier or "trash_mob")
    result.tier = def.tier
    return result
end

-- ── Pet work / mining damage (issue #4) ───────────────────────────────────
-- Single, service-owned source of truth for pet damage + cadence, replacing the
-- formula that used to live inline in the cloned PetScripts/Follow script. Pet
-- power flows through the ModifierService pipeline (pet_damage / pet_efficiency
-- stages), then the deterministic PetCombat rules are applied.

-- ctx: { power, petId, variant, breakableId, currency }
function CombatService:ResolvePetDamage(player, ctx)
    ctx = ctx or {}
    local power = ctx.power or 1
    local resolved = power
    local modifier = self:_service("ModifierService")
    if modifier and modifier.Resolve then
        local ok, value = pcall(function()
            return modifier:Resolve(power, {
                player = player,
                kind = "pet_damage",
                petId = ctx.petId,
                variant = ctx.variant,
                breakableId = ctx.breakableId,
                currency = ctx.currency,
                source = "PetWork",
            })
        end)
        if ok then
            resolved = tonumber(value) or power
        end
    end
    return PetCombat.damagePerHit(resolved)
end

-- Seconds to wait between this pet's hits, from the pet_efficiency pipeline.
function CombatService:ResolvePetAttackInterval(player, ctx)
    ctx = ctx or {}
    local efficiency = 1
    local modifier = self:_service("ModifierService")
    if modifier and modifier.Resolve then
        local ok, value = pcall(function()
            return modifier:Resolve(1, {
                player = player,
                kind = "pet_efficiency",
                petId = ctx.petId,
                variant = ctx.variant,
                source = "PetWork",
            })
        end)
        if ok then
            efficiency = tonumber(value) or 1
        end
    end
    return PetCombat.attackInterval(efficiency)
end

return CombatService
