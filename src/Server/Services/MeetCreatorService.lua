--[[
    MeetCreatorService — the Meet-The-Creator mechanic (configs/creators.lua).

    The first time a player shares a server with a registered creator — and only that
    once, EVER — they receive the creator's egg in their eggs inventory bucket. The
    egg hatches the creator's SPECIES (never the apex creator class — that is granted
    only to the creator themselves) at the configured variant odds.

    Both directions are covered: a player joining a server where a creator is
    present, and a creator joining a server full of players. Met-state persists in
    data.MetCreators[creatorUserId] = os.time().

    HatchEggItem (bus: egg_item.hatch) consumes one egg item and grants the pet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fireGameEvent = require(ReplicatedStorage.Shared.Network.FireGameEvent)

local MeetCreatorService = {}
MeetCreatorService.__index = MeetCreatorService

function MeetCreatorService.new()
    return setmetatable({}, MeetCreatorService)
end

function MeetCreatorService:Init()
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    local ok, cfg = pcall(function()
        return self._configLoader:LoadConfig("creators")
    end)
    self._config = (ok and cfg) or { creators = {}, meet = { enabled = false } }
end

function MeetCreatorService:_svc(name)
    local locator = _G.RBXTemplateServices
    local ok, svc = pcall(function()
        return locator and locator:Get(name)
    end)
    return ok and svc or nil
end

function MeetCreatorService:_creatorFor(userId)
    return (self._config.creators or {})[tostring(userId)]
end

-- Award `player` the meet-egg for `creatorUserId` if this is their first meeting.
function MeetCreatorService:_tryMeet(player, creatorUserId, creatorDef)
    if player.UserId == tonumber(creatorUserId) then
        return -- creators don't meet themselves
    end
    local dataService = self:_svc("DataService")
    if not (dataService and dataService:IsDataLoaded(player)) then
        return
    end
    local data = dataService:GetData(player)
    data.MetCreators = data.MetCreators or {}
    if data.MetCreators[tostring(creatorUserId)] then
        return -- once, ever
    end
    data.MetCreators[tostring(creatorUserId)] = os.time()

    local invSvc = self:_svc("InventoryService")
    local granted = invSvc
        and invSvc:AddItem(player, "eggs", {
            id = creatorDef.egg_id,
            name = creatorDef.egg_name or creatorDef.egg_id,
            source = "met_creator:" .. tostring(creatorUserId),
        })
    dataService:RequestSave(player, "met_creator", { critical = true })
    fireGameEvent(player, "met_creator", {
        creator = creatorDef.name,
        egg = creatorDef.egg_name or creatorDef.egg_id,
        granted = granted ~= nil,
    })
    self._logger:Info("Meet-The-Creator: first meeting", {
        player = player.Name,
        creator = creatorDef.name,
        egg = creatorDef.egg_id,
        granted = granted ~= nil,
    })
end

-- Scan: for `player`, check every registered creator present in this server.
function MeetCreatorService:_scanFor(player)
    for creatorId, def in pairs(self._config.creators or {}) do
        local creatorPlayer = Players:GetPlayerByUserId(tonumber(creatorId))
        if creatorPlayer and creatorPlayer ~= player then
            self:_tryMeet(player, creatorId, def)
        end
    end
end

function MeetCreatorService:Start()
    if not (self._config.meet and self._config.meet.enabled) then
        return
    end
    local delay = tonumber(self._config.meet.check_delay) or 8
    local function onJoin(joiner)
        task.delay(delay, function()
            if not joiner.Parent then
                return
            end
            -- the joiner might be meeting creators already here
            self:_scanFor(joiner)
            -- ...or the joiner IS a creator everyone else now meets
            if self:_creatorFor(joiner.UserId) then
                local def = self:_creatorFor(joiner.UserId)
                for _, other in ipairs(Players:GetPlayers()) do
                    if other ~= joiner then
                        self:_tryMeet(other, joiner.UserId, def)
                    end
                end
            end
        end)
    end
    Players.PlayerAdded:Connect(onJoin)
    for _, p in ipairs(Players:GetPlayers()) do
        onJoin(p)
    end
end

-- Hatch one held egg item: consume it, roll the variant, grant the SPECIES pet
-- (plain grant — never huge, never creator class).
function MeetCreatorService:HatchEggItem(player, eggItemId)
    -- find which creator this egg belongs to
    local def
    for _, c in pairs(self._config.creators or {}) do
        if c.egg_id == eggItemId then
            def = c
            break
        end
    end
    if not def then
        return { ok = false, reason = "unknown_egg" }
    end
    local invSvc = self:_svc("InventoryService")
    local rec = invSvc and invSvc:GetItem(player, "eggs", eggItemId)
    if not rec or (tonumber(rec.quantity) or 0) < 1 then
        return { ok = false, reason = "no_egg" }
    end
    -- roll variant by weight
    local total = 0
    for _, w in pairs(def.variants or { basic = 1 }) do
        total += w
    end
    local roll = math.random() * total
    local variant = "basic"
    for v, w in pairs(def.variants or { basic = 1 }) do
        roll -= w
        if roll <= 0 then
            variant = v
            break
        end
    end
    local grantSvc = self:_svc("PetGrantService")
    if not grantSvc then
        return { ok = false, reason = "service_unavailable" }
    end
    local result = grantSvc:GrantPet(player, {
        petType = def.pet,
        variant = variant,
        quantity = 1,
        source = "creator_egg:" .. eggItemId,
    })
    if not result or result.ok == false then
        return { ok = false, reason = "grant_failed" }
    end
    invSvc:RemoveItem(player, "eggs", eggItemId, 1)
    self._logger:Info("Creator egg hatched", {
        player = player.Name,
        egg = eggItemId,
        pet = def.pet,
        variant = variant,
    })
    return { ok = true, pet = def.pet, variant = variant }
end

return MeetCreatorService
