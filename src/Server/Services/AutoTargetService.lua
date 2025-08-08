--[[
    AutoTargetService - Manages automatic pet targeting modes (Free/Low and Paid/High)

    Behavior:
    - Adds BoolValues `FreeTarget` and `PaidTarget` to each Player
    - Clients request toggles via Net signals; server validates and updates flags
    - Broadcasts current status to the player (so client visuals are server-driven)

    Integration:
    - Client AutoTarget module listens to status, selects targets, and fires
      Breakables_Attack periodically. UI buttons show green/orange based on
      `FreeTarget` / `PaidTarget` changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoTargetService = {}
AutoTargetService.__index = AutoTargetService

local logger
local monetization
local productIdMapper

-- Config IDs expected in configs/monetization.lua via ProductIdMapper
local PAID_AUTOTARGET_PASS_ID = "auto_target_high" -- config key; maps to Roblox gamepass id

local function ensurePlayerFlags(player)
    local free = player:FindFirstChild("FreeTarget")
    if not free then
        free = Instance.new("BoolValue")
        free.Name = "FreeTarget"
        free.Value = false
        free.Parent = player
    end
    local paid = player:FindFirstChild("PaidTarget")
    if not paid then
        paid = Instance.new("BoolValue")
        paid.Name = "PaidTarget"
        paid.Value = false
        paid.Parent = player
    end
    return free, paid
end

function AutoTargetService:Init()
    logger = self._modules.Logger
    monetization = self._modules.MonetizationService
    productIdMapper = self._modules.ProductIdMapper

    local Signals = require(ReplicatedStorage.Shared.Network.Signals)

    Signals.AutoTarget_ToggleFree.OnServerEvent:Connect(function(player)
        self:_toggleFree(player)
    end)
    Signals.AutoTarget_TogglePaid.OnServerEvent:Connect(function(player)
        self:_togglePaid(player)
    end)

    Players.PlayerAdded:Connect(function(player)
        ensurePlayerFlags(player)
        -- Send initial status after short delay so client can bind listener
        task.delay(0.2, function()
            self:_sendStatus(player)
        end)
    end)
    for _, plr in ipairs(Players:GetPlayers()) do
        ensurePlayerFlags(plr)
        self:_sendStatus(plr)
    end

    logger:Info("AutoTargetService initialized")
end

function AutoTargetService:_sendStatus(player)
    local Signals = require(ReplicatedStorage.Shared.Network.Signals)
    local free, paid = ensurePlayerFlags(player)
    Signals.AutoTarget_Status:FireClient(player, {
        free = free.Value,
        paid = paid.Value,
    })
end

function AutoTargetService:_toggleFree(player)
    local free, paid = ensurePlayerFlags(player)
    if free.Value then
        free.Value = false
    else
        paid.Value = false
        free.Value = true
    end
    self:_sendStatus(player)
    if logger then logger:Info("AutoTarget Free toggled", {player = player.Name, state = free.Value}) end
end

function AutoTargetService:_togglePaid(player)
    local free, paid = ensurePlayerFlags(player)

    -- Validate gamepass ownership using MonetizationService's data if available
    local owns = false
    if monetization and monetization.PlayerOwnsPass and productIdMapper then
        owns = monetization:PlayerOwnsPass(player, PAID_AUTOTARGET_PASS_ID)
    end

    if owns then
        if paid.Value then
            paid.Value = false
        else
            free.Value = false
            paid.Value = true
        end
        self:_sendStatus(player)
        if logger then logger:Info("AutoTarget Paid toggled", {player = player.Name, state = paid.Value}) end
    else
        if logger then logger:Warn("AutoTarget Paid denied (no pass)", {player = player.Name}) end
        -- Optionally echo status to ensure UI stays consistent
        self:_sendStatus(player)
    end
end

return AutoTargetService


