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

local function baselines(data)
    if type(data.QuestBaselines) ~= "table" then
        data.QuestBaselines = {}
    end
    return data.QuestBaselines
end

-- since_start missions measure FORWARD progress (Jason: "hatch 100 MORE eggs, not
-- your current total"): evaluate against counter MINUS the baseline stamped when the
-- mission became active. Unstamped (locked / not yet reached) shows zero progress.
local function adjustedSnapshot(def, snapshot, base)
    local cond = def.condition
    if not (cond and cond.since_start and cond.counter) then
        return snapshot
    end
    local cur = (snapshot.counters and snapshot.counters[cond.counter]) or 0
    local counters = table.clone(snapshot.counters or {})
    counters[cond.counter] = math.max(0, cur - (base or cur))
    return { counters = counters, level = snapshot.level, currencies = snapshot.currencies }
end

function QuestService:List(player)
    local snapshot = self:_snapshot(player)
    local data = self._dataService:GetData(player)
    local ledger = claims(data)
    local bases = baselines(data)
    local out = {}
    for id, def in pairs(self._config.defs or {}) do
        local count = ledger[id] or 0
        table.insert(out, {
            id = id,
            def = def,
            order = tonumber(def.order) or math.huge,
            name = def.name,
            description = def.description,
            claimedCount = count,
            repeatable = def.repeatable == true,
        })
    end
    -- MISSION CHAIN (Jason): quests are an ordered chain — sort by `order`, and LOCK a
    -- mission until every lower-order non-repeatable one has been claimed. Locked
    -- missions stay listed (the panel shows what's coming) but can't be claimed and
    -- the tracker skips them.
    table.sort(out, function(a, b)
        return a.order < b.order
    end)
    local blocked = false
    for _, q in ipairs(out) do
        q.locked = blocked
        if not q.repeatable and q.claimedCount == 0 then
            blocked = true
        end
    end
    -- stamp the ACTIVE mission's baseline the first time it surfaces (since_start
    -- progress counts from here)
    for _, q in ipairs(out) do
        if not q.locked and q.claimedCount == 0 then
            local cond = q.def.condition
            if cond and cond.since_start and cond.counter and bases[q.id] == nil then
                bases[q.id] = (snapshot.counters and snapshot.counters[cond.counter]) or 0
                self._dataService:RequestSave(player, "quest_baseline")
            end
            break -- only the first unclaimed unlocked mission is active
        end
    end
    for _, q in ipairs(out) do
        local progress =
            Condition.progress(q.def.condition, adjustedSnapshot(q.def, snapshot, bases[q.id]))
        q.progress = progress
        q.claimable = not q.locked and ClaimLogic.canClaim(progress.met, q.claimedCount, q.def).ok
        q.def = nil -- not for the wire
    end
    return { ok = true, quests = out }
end

function QuestService:_isLocked(player, questId)
    local res = self:List(player)
    for _, q in ipairs((res and res.quests) or {}) do
        if q.id == questId then
            return q.locked == true
        end
    end
    return false
end

function QuestService:Claim(player, questId)
    local def = (self._config.defs or {})[questId]
    if not def then
        return { ok = false, reason = "unknown_quest" }
    end
    local snapshot = self:_snapshot(player)
    local data = self._dataService:GetData(player)
    local ledger = claims(data)
    local met =
        Condition.isMet(def.condition, adjustedSnapshot(def, snapshot, baselines(data)[questId]))
    local verdict = ClaimLogic.canClaim(met, ledger[questId] or 0, def)
    if not verdict.ok then
        return verdict
    end
    if self:_isLocked(player, questId) then
        return { ok = false, reason = "locked" } -- chain order is server-authoritative
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
