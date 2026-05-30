--[[
    TradeService — Feature 19 (Trade System).

    Server-authoritative trading: session-scoped offers, both-player confirm gate,
    atomic (anti-duplication) execution, and a queryable trade-history audit log.
    Pure rules live in the shared TradeLogic core; this service owns sessions, the
    inventory swap, and the audit ledger.

    The two-player invite/confirm handshake + UI are [studio]; the rules, the
    atomic-swap contract, and the audit log are bus-testable solo via trade.canAdd
    and the test-only trade.simulate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TradeLogic = require(ReplicatedStorage.Shared.Game.TradeLogic)

local TradeService = {}
TradeService.__index = TradeService

function TradeService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._config = self._configLoader:LoadConfig("trade")
    self._sessions = {} -- sessionId -> { a, b, offers = { [userId] = { items, confirmed } } }
    self._playerSession = {} -- userId -> sessionId
    self._nextId = 0
    self._auditLog = {} -- append-only, capped at config.audit_log_limit
end

function TradeService:_service(name)
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get(name)
    end)
    return ok and service or nil
end

-- Rule check for a single item, exposed to the UI/bus (trade.canAdd).
function TradeService:CanAdd(category, item)
    return TradeLogic.canAddItem(category, item, self._config)
end

function TradeService:_offerOf(session, userId)
    session.offers[userId] = session.offers[userId] or { items = {}, confirmed = false }
    return session.offers[userId]
end

-- Open a trade session between two players (server side of the invite-accept).
function TradeService:Open(playerA, playerB)
    if self._playerSession[playerA.UserId] or self._playerSession[playerB.UserId] then
        return { ok = false, reason = "already_trading" }
    end
    self._nextId += 1
    local id = self._nextId
    self._sessions[id] = {
        a = playerA.UserId,
        b = playerB.UserId,
        offers = {},
    }
    self._playerSession[playerA.UserId] = id
    self._playerSession[playerB.UserId] = id
    return { ok = true, sessionId = id }
end

function TradeService:Add(player, category, item)
    local id = self._playerSession[player.UserId]
    local session = id and self._sessions[id]
    if not session then
        return { ok = false, reason = "no_trade" }
    end
    local verdict = TradeLogic.canAddItem(category, item, self._config)
    if not verdict.ok then
        return verdict
    end
    local offer = self:_offerOf(session, player.UserId)
    if #offer.items >= (self._config.max_offer_items or 10) then
        return { ok = false, reason = "offer_full" }
    end
    -- Adding/removing items invalidates any prior confirmation (both must re-confirm).
    session.offers[session.a] = session.offers[session.a] or { items = {}, confirmed = false }
    session.offers[session.b] = session.offers[session.b] or { items = {}, confirmed = false }
    session.offers[session.a].confirmed = false
    session.offers[session.b].confirmed = false
    table.insert(
        offer.items,
        { category = category, id = item.id, uid = item.uid, locked = item.locked }
    )
    return { ok = true, count = #offer.items }
end

function TradeService:Confirm(player)
    local id = self._playerSession[player.UserId]
    local session = id and self._sessions[id]
    if not session then
        return { ok = false, reason = "no_trade" }
    end
    self:_offerOf(session, player.UserId).confirmed = true
    local offerA = session.offers[session.a]
    local offerB = session.offers[session.b]
    if TradeLogic.canExecute(offerA, offerB).ok then
        return self:_execute(id)
    end
    return { ok = true, waiting = true }
end

-- Atomic swap: move every offered pet from its owner to the other player. We snapshot
-- and validate ownership first; if anything is missing we abort BEFORE mutating, so the
-- trade is all-or-nothing (anti-duplication: no item ends up in both or neither).
function TradeService:_execute(sessionId)
    local session = self._sessions[sessionId]
    if not session then
        return { ok = false, reason = "no_trade" }
    end
    local inventory = self:_service("InventoryService")
    local players = game:GetService("Players")
    local pa = players:GetPlayerByUserId(session.a)
    local pb = players:GetPlayerByUserId(session.b)
    local offerA = session.offers[session.a] or { items = {} }
    local offerB = session.offers[session.b] or { items = {} }

    if inventory and pa and pb then
        local moves = {}
        local function plan(fromPlayer, toPlayer, items)
            for _, it in ipairs(items) do
                if it.category == "pets" and it.uid then
                    local bucket = inventory:GetInventory(fromPlayer, "pets")
                    local rec = bucket and bucket.items and bucket.items[it.uid]
                    if not rec then
                        return false -- ownership lost -> abort whole trade
                    end
                    table.insert(
                        moves,
                        { from = fromPlayer, to = toPlayer, uid = it.uid, rec = rec }
                    )
                end
            end
            return true
        end
        if not (plan(pa, pb, offerA.items) and plan(pb, pa, offerB.items)) then
            return { ok = false, reason = "ownership_changed" }
        end
        -- All validated -> apply. (Single-frame server execution; no yield between
        -- remove/add, so there is no partial-completion window.)
        for _, m in ipairs(moves) do
            inventory:RemoveItem(m.from, "pets", m.uid, 1)
            inventory:AddItem(m.to, "pets", m.rec)
        end
    end

    local rec = TradeLogic.auditRecord(session.a, session.b, offerA, offerB, os.time())
    self:_appendAudit(rec)
    self:_close(sessionId)
    return { ok = true, executed = true, audit = rec }
end

function TradeService:_appendAudit(rec)
    table.insert(self._auditLog, rec)
    local limit = self._config.audit_log_limit or 100
    while #self._auditLog > limit do
        table.remove(self._auditLog, 1)
    end
end

function TradeService:_close(sessionId)
    local session = self._sessions[sessionId]
    if not session then
        return
    end
    self._playerSession[session.a] = nil
    self._playerSession[session.b] = nil
    self._sessions[sessionId] = nil
end

function TradeService:Cancel(player)
    local id = self._playerSession[player.UserId]
    if id then
        self:_close(id)
    end
    return { ok = true }
end

-- Queryable trade-history audit log (for support/audit). Optionally filtered to a userId.
function TradeService:GetAuditLog(userId)
    if not userId then
        return { ok = true, records = self._auditLog }
    end
    local out = {}
    for _, rec in ipairs(self._auditLog) do
        if rec.a == userId or rec.b == userId then
            table.insert(out, rec)
        end
    end
    return { ok = true, records = out }
end

-- Test/UI affordance: run the rule + execute-gate + audit-record logic over a
-- described trade without two live players. Mirrors PartyService:Simulate.
function TradeService:Simulate(opts)
    opts = opts or {}
    local offerA = opts.offerA or { items = {}, confirmed = false }
    local offerB = opts.offerB or { items = {}, confirmed = false }
    local adds = {}
    for _, it in ipairs(opts.adds or {}) do
        adds[#adds + 1] = TradeLogic.canAddItem(it.category, it, self._config)
    end
    local exec = TradeLogic.canExecute(offerA, offerB)
    local audit = nil
    if exec.ok then
        audit = TradeLogic.auditRecord(
            opts.a or "A",
            opts.b or "B",
            offerA,
            offerB,
            opts.timestamp or 0
        )
    end
    return { ok = true, adds = adds, canExecute = exec, audit = audit }
end

return TradeService
