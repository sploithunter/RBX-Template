--[[
    TradeService — Feature 19 (Trade System), escrow model (Phase 10).

    Roblox has NO native in-experience trading/escrow API (the platform Trading
    System is for avatar catalog Limiteds + Robux between accounts; the old web
    Trade API was deprecated). So we implement the escrow PATTERN ourselves,
    server-authoritatively:

      Request -> Accept -> (each Add MOVES the pet into server escrow) ->
      both Confirm -> deliver each side's escrow to the other (all-or-nothing) ->
      Cancel / Decline / disconnect -> refund escrow to its owner.

    Escrow is the anti-duplication guarantee: an offered pet leaves the owner's
    inventory immediately, so it can't be sold, deleted, or offered in a second
    trade while pending. Live state is pushed to both clients via the TradeUpdate
    RemoteEvent. Pure rules (tradeable / both-confirm / audit record) live in the
    shared TradeLogic core.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TradeLogic = require(ReplicatedStorage.Shared.Game.TradeLogic)

local TradeService = {}
TradeService.__index = TradeService

local UPDATE_REMOTE = "TradeUpdate"
local PETS_BUCKET = "pets"

function TradeService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._config = self._configLoader:LoadConfig("trade")
    self._sessions = {} -- sessionId -> session
    self._playerSession = {} -- userId -> sessionId
    self._invites = {} -- targetUserId -> { from = userId }
    self._nextId = 0
    self._auditLog = {} -- append-only, capped

    -- Server -> client push channel (recreated to survive Studio hot-sync).
    local existing = ReplicatedStorage:FindFirstChild(UPDATE_REMOTE)
    if existing then
        existing:Destroy()
    end
    local remote = Instance.new("RemoteEvent")
    remote.Name = UPDATE_REMOTE
    remote.Parent = ReplicatedStorage
    self._remote = remote
end

function TradeService:Start()
    Players.PlayerRemoving:Connect(function(player)
        self:_onLeave(player)
    end)
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

-- Pure rule check (kept for the original Feature 19 bus command / tests).
function TradeService:CanAdd(category, item)
    return TradeLogic.canAddItem(category, item, self._config)
end

----------------------------------------------------------------------
-- Session helpers
----------------------------------------------------------------------

local function playerById(userId)
    return Players:GetPlayerByUserId(userId)
end

function TradeService:_sessionOf(userId)
    local id = self._playerSession[userId]
    return id and self._sessions[id]
end

-- Per-recipient view: your side + the partner's side (offers + confirm flags).
function TradeService:_view(session, forUserId)
    local otherId = (forUserId == session.a) and session.b or session.a
    local other = playerById(otherId)
    return {
        sessionId = session.id,
        you = {
            items = session.offers[forUserId].items,
            confirmed = session.offers[forUserId].confirmed,
        },
        them = {
            userId = otherId,
            name = other and other.Name or "Player",
            items = session.offers[otherId].items,
            confirmed = session.offers[otherId].confirmed,
        },
    }
end

function TradeService:_push(session, eventType)
    for _, userId in ipairs({ session.a, session.b }) do
        local plr = playerById(userId)
        if plr then
            self._remote:FireClient(plr, { type = eventType, state = self:_view(session, userId) })
        end
    end
end

function TradeService:_notify(player, payload)
    if player then
        self._remote:FireClient(player, payload)
    end
end

----------------------------------------------------------------------
-- Online-player list + invite handshake
----------------------------------------------------------------------

function TradeService:ListPlayers(player)
    local out = {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            table.insert(out, {
                userId = other.UserId,
                name = other.Name,
                busy = self._playerSession[other.UserId] ~= nil,
            })
        end
    end
    return { ok = true, players = out }
end

function TradeService:Request(player, targetUserId)
    if targetUserId == player.UserId then
        return { ok = false, reason = "cannot_trade_self" }
    end
    local target = playerById(targetUserId)
    if not target then
        return { ok = false, reason = "player_not_found" }
    end
    if self._playerSession[player.UserId] or self._playerSession[targetUserId] then
        return { ok = false, reason = "already_trading" }
    end
    self._invites[targetUserId] = { from = player.UserId }
    self:_notify(target, { type = "request", fromUserId = player.UserId, fromName = player.Name })
    return { ok = true, pending = true }
end

function TradeService:Respond(player, fromUserId, accept)
    local invite = self._invites[player.UserId]
    if not invite or invite.from ~= fromUserId then
        return { ok = false, reason = "no_invite" }
    end
    self._invites[player.UserId] = nil
    local requester = playerById(fromUserId)

    if not accept then
        self:_notify(requester, { type = "declined", byUserId = player.UserId })
        return { ok = true, accepted = false }
    end
    if not requester then
        return { ok = false, reason = "player_not_found" }
    end
    if self._playerSession[player.UserId] or self._playerSession[fromUserId] then
        return { ok = false, reason = "already_trading" }
    end
    return self:_open(requester, player)
end

function TradeService:_open(playerA, playerB)
    self._nextId += 1
    local id = self._nextId
    local session = {
        id = id,
        a = playerA.UserId,
        b = playerB.UserId,
        offers = {
            [playerA.UserId] = { items = {}, confirmed = false },
            [playerB.UserId] = { items = {}, confirmed = false },
        },
        escrow = {
            [playerA.UserId] = {}, -- uid -> normalized pet descriptor
            [playerB.UserId] = {},
        },
    }
    self._sessions[id] = session
    self._playerSession[playerA.UserId] = id
    self._playerSession[playerB.UserId] = id
    self:_push(session, "opened")
    return { ok = true, sessionId = id }
end

----------------------------------------------------------------------
-- Escrow add / remove
----------------------------------------------------------------------

local function descriptorFromRecord(uid, rec)
    return {
        uid = uid,
        id = rec.id,
        variant = rec.variant or "basic",
        element = rec.element,
        huge = rec.huge,
        locked = rec.locked,
    }
end

-- Detach a pet from everything that references it before it leaves the inventory,
-- so it doesn't linger as a "phantom" equipped pet (in the UI or in the world):
--   1. the Equipped.pets slot (normal pets), keyed by uid
--   2. the ephemeral equip_<...> folder (special/unique pets), matched by id+variant
--   3. roster references
-- _reloadEquipped() then forces a loadEquipped rebuild that despawns the orphan model.
function TradeService:_detachPet(player, uid, rec)
    local equipped = player:FindFirstChild("Equipped")
    local equipSlots = equipped and equipped:FindFirstChild("pets")
    if equipSlots then
        for _, slot in ipairs(equipSlots:GetChildren()) do
            if slot:IsA("StringValue") and slot.Value == uid then
                slot:Destroy()
            end
        end
    end

    -- Special pets equip via an equip_<id> folder in Inventory.pets that RemoveItem
    -- does not clean up; remove the one matching this pet so it won't respawn.
    local inventory = player:FindFirstChild("Inventory")
    local invPets = inventory and inventory:FindFirstChild("pets")
    if invPets and rec then
        for _, child in ipairs(invPets:GetChildren()) do
            if child:IsA("Folder") and string.sub(child.Name, 1, 6) == "equip_" then
                local itemId = child:FindFirstChild("ItemId")
                local variant = child:FindFirstChild("Variant")
                local matchesName = child.Name == ("equip_" .. tostring(uid))
                local matchesData = itemId
                    and itemId.Value == rec.id
                    and (not variant or variant.Value == (rec.variant or "basic"))
                if matchesName or matchesData then
                    child:Destroy()
                end
            end
        end
    end

    local rosters = self:_service("RosterService")
    if rosters and rosters.RemovePetReference then
        pcall(function()
            rosters:RemovePetReference(player, uid)
        end)
    end
end

-- Force a clean respawn of equipped pets (despawns orphaned follow models).
function TradeService:_reloadEquipped(player)
    if type(_G.RBXReloadEquippedPets) == "function" then
        pcall(function()
            _G.RBXReloadEquippedPets(player)
        end)
    end
end

-- Add a pet to the offer: validate, then MOVE it out of inventory into escrow.
function TradeService:Add(player, uid)
    local session = self:_sessionOf(player.UserId)
    if not session then
        return { ok = false, reason = "no_trade" }
    end
    local inventory = self:_service("InventoryService")
    if not inventory then
        return { ok = false, reason = "service_unavailable" }
    end
    local bucket = inventory:GetInventory(player, PETS_BUCKET)
    local rec = bucket and bucket.items and bucket.items[uid]
    if not rec then
        return { ok = false, reason = "pet_not_found" }
    end

    local verdict =
        TradeLogic.canAddItem("pets", { id = rec.id, locked = rec.locked }, self._config)
    if not verdict.ok then
        return verdict
    end

    local offer = session.offers[player.UserId]
    if #offer.items >= (self._config.max_offer_items or 10) then
        return { ok = false, reason = "offer_full" }
    end

    -- Escrow lock: unequip + drop references, then remove from inventory (anti-dup),
    -- then force an equipped-pets rebuild so the world model despawns (no phantom).
    self:_detachPet(player, uid, rec)
    inventory:RemoveItem(player, PETS_BUCKET, uid, 1)
    self:_reloadEquipped(player)
    local descriptor = descriptorFromRecord(uid, rec)
    session.escrow[player.UserId][uid] = descriptor
    table.insert(offer.items, descriptor)

    -- Any change invalidates both confirmations.
    session.offers[session.a].confirmed = false
    session.offers[session.b].confirmed = false
    self:_push(session, "updated")
    return { ok = true, count = #offer.items }
end

-- Pull a pet back out of the offer and return it to the owner's inventory.
function TradeService:Remove(player, uid)
    local session = self:_sessionOf(player.UserId)
    if not session then
        return { ok = false, reason = "no_trade" }
    end
    local descriptor = session.escrow[player.UserId][uid]
    if not descriptor then
        return { ok = false, reason = "not_offered" }
    end
    local inventory = self:_service("InventoryService")
    if inventory then
        inventory:AddItem(player, PETS_BUCKET, {
            id = descriptor.id,
            variant = descriptor.variant,
            element = descriptor.element,
            huge = descriptor.huge,
            quantity = 1,
        })
    end
    session.escrow[player.UserId][uid] = nil
    local offer = session.offers[player.UserId]
    for i = #offer.items, 1, -1 do
        if offer.items[i].uid == uid then
            table.remove(offer.items, i)
        end
    end
    session.offers[session.a].confirmed = false
    session.offers[session.b].confirmed = false
    self:_push(session, "updated")
    return { ok = true }
end

----------------------------------------------------------------------
-- Confirm / deliver / cancel / refund
----------------------------------------------------------------------

function TradeService:Confirm(player)
    local session = self:_sessionOf(player.UserId)
    if not session then
        return { ok = false, reason = "no_trade" }
    end
    session.offers[player.UserId].confirmed = true
    local offerA, offerB = session.offers[session.a], session.offers[session.b]
    if TradeLogic.canExecute(offerA, offerB).ok then
        return self:_deliver(session)
    end
    self:_push(session, "updated")
    return { ok = true, waiting = true }
end

local function giveAll(inventory, player, escrowForOwner)
    if not (inventory and player) then
        return
    end
    for _, descriptor in pairs(escrowForOwner) do
        inventory:AddItem(player, PETS_BUCKET, {
            id = descriptor.id,
            variant = descriptor.variant,
            element = descriptor.element,
            huge = descriptor.huge,
            quantity = 1,
        })
    end
end

-- Both confirmed: deliver A's escrow to B and B's escrow to A. All-or-nothing —
-- the items are already escrowed, so neither side can be left holding both/none.
function TradeService:_deliver(session)
    local inventory = self:_service("InventoryService")
    local pa, pb = playerById(session.a), playerById(session.b)
    giveAll(inventory, pb, session.escrow[session.a])
    giveAll(inventory, pa, session.escrow[session.b])

    local rec = TradeLogic.auditRecord(
        session.a,
        session.b,
        session.offers[session.a],
        session.offers[session.b],
        os.time()
    )
    self:_appendAudit(rec)
    self:_push(session, "completed")
    self:_close(session.id)
    if pa then
        self._dataService:RequestSave(pa, "trade_complete", { critical = true })
    end
    if pb then
        self._dataService:RequestSave(pb, "trade_complete", { critical = true })
    end
    return { ok = true, executed = true, audit = rec }
end

-- Return every escrowed pet to its owner (cancel / decline / disconnect).
function TradeService:_refund(session)
    local inventory = self:_service("InventoryService")
    for _, userId in ipairs({ session.a, session.b }) do
        giveAll(inventory, playerById(userId), session.escrow[userId])
        session.escrow[userId] = {}
    end
end

function TradeService:Cancel(player)
    local session = self:_sessionOf(player.UserId)
    if not session then
        return { ok = true }
    end
    self:_refund(session)
    self:_push(session, "cancelled")
    self:_close(session.id)
    return { ok = true }
end

function TradeService:_onLeave(player)
    -- Clear any invite addressed to or from the leaving player.
    self._invites[player.UserId] = nil
    for target, invite in pairs(self._invites) do
        if invite.from == player.UserId then
            self._invites[target] = nil
        end
    end
    local session = self:_sessionOf(player.UserId)
    if session then
        self:_refund(session) -- refunds the leaver too (their save flushes on remove)
        self:_push(session, "cancelled")
        self:_close(session.id)
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

-- The player's tradeable pets (for the offer picker). Pets already escrowed in an
-- active trade are gone from inventory, so they naturally don't appear here.
function TradeService:ListMyPets(player)
    local inventory = self:_service("InventoryService")
    if not inventory then
        return { ok = false, reason = "service_unavailable" }
    end
    local bucket = inventory:GetInventory(player, PETS_BUCKET)
    local out = {}
    for uid, rec in pairs((bucket and bucket.items) or {}) do
        table.insert(out, {
            uid = uid,
            id = rec.id,
            variant = rec.variant or "basic",
            element = rec.element,
            huge = rec.huge,
            locked = rec.locked,
        })
    end
    return { ok = true, pets = out }
end

function TradeService:GetState(player)
    local session = self:_sessionOf(player.UserId)
    if not session then
        return { ok = true, active = false }
    end
    return { ok = true, active = true, state = self:_view(session, player.UserId) }
end

----------------------------------------------------------------------
-- Audit log + test affordance
----------------------------------------------------------------------

function TradeService:_appendAudit(rec)
    table.insert(self._auditLog, rec)
    local limit = self._config.audit_log_limit or 100
    while #self._auditLog > limit do
        table.remove(self._auditLog, 1)
    end
end

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

-- Rules + execute-gate + audit-record logic without two live players.
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
