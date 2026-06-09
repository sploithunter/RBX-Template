--[[
    QuestService — Phase 7 (the condition-gated reward gate).

    Quests are reward bundles gated behind a pure Condition over a snapshot of the
    player's stat counters / level / currencies. Claim-once unless `repeatable`.
    The claim ledger (profile.QuestClaims: defId -> count) is the anti-replay store.
    Grants flow through RewardService. The "Quest" badge = Pending().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Condition = require(ReplicatedStorage.Shared.Game.Condition)
local ClaimLogic = require(ReplicatedStorage.Shared.Game.ClaimLogic)
local fireGameEvent = require(ReplicatedStorage.Shared.Network.FireGameEvent)

local QuestService = {}
QuestService.__index = QuestService

function QuestService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._config = self._configLoader:LoadConfig("quests")
end

function QuestService:_service(name)
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get(name)
    end)
    return ok and service or nil
end

-- Build the Condition snapshot from the live player state.
function QuestService:_snapshot(player)
    local stats = self:_service("StatsService")
    local progression = self:_service("PlayerProgressionService")
    local counters = (stats and stats:GetAll(player)) or {}
    local level = (progression and progression:GetLevel(player)) or 1
    local currencies = {}
    local data = self._dataService and self._dataService:GetData(player)
    if data and type(data.Currencies) == "table" then
        for k, v in pairs(data.Currencies) do
            currencies[k] = v
        end
    end
    return { counters = counters, level = level, currencies = currencies }
end

local function claims(data)
    if type(data.QuestClaims) ~= "table" then
        data.QuestClaims = {}
    end
    return data.QuestClaims
end

function QuestService:List(player)
    local snapshot = self:_snapshot(player)
    local data = self._dataService:GetData(player)
    local ledger = claims(data)
    local out = {}
    for id, def in pairs(self._config.defs or {}) do
        local progress = Condition.progress(def.condition, snapshot)
        local count = ledger[id] or 0
        local claimable = ClaimLogic.canClaim(progress.met, count, def).ok
        table.insert(out, {
            id = id,
            name = def.name,
            description = def.description,
            progress = progress,
            claimedCount = count,
            claimable = claimable,
            repeatable = def.repeatable == true,
        })
    end
    return { ok = true, quests = out }
end

function QuestService:Claim(player, questId)
    local def = (self._config.defs or {})[questId]
    if not def then
        return { ok = false, reason = "unknown_quest" }
    end
    local snapshot = self:_snapshot(player)
    local data = self._dataService:GetData(player)
    local ledger = claims(data)
    local met = Condition.isMet(def.condition, snapshot)
    local verdict = ClaimLogic.canClaim(met, ledger[questId] or 0, def)
    if not verdict.ok then
        return verdict
    end

    local rewards = self:_service("RewardService")
    local granted
    if rewards then
        granted = rewards:Grant(player, def.reward, "quest:" .. questId)
    end
    ledger[questId] = (ledger[questId] or 0) + 1
    self._dataService:RequestSave(player, "quest_claim", { critical = true })
    fireGameEvent(player, "quest_complete", { quest = questId }) -- config-driven fanfare
    return { ok = true, quest = questId, reward = granted and granted.granted }
end

function QuestService:Pending(player)
    local n = 0
    for _, q in ipairs(self:List(player).quests) do
        if q.claimable then
            n += 1
        end
    end
    return n
end

return QuestService
