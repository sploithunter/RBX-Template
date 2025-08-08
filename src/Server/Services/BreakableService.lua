--[[
    BreakableService - Handles targeting, damage, and breaking of crystals
]]

local BreakableService = {}
BreakableService.__index = BreakableService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local logger
local configLoader

-- Debounce map: player -> last attack tick
local lastAttack = {}

local function findBreakableById(id)
    local gameFolder = workspace:FindFirstChild("Game")
    if not gameFolder then return nil end
    local breakables = gameFolder:FindFirstChild("Breakables")
    if not breakables then return nil end
    for _, typeFolder in ipairs(breakables:GetChildren()) do
        for _, worldFolder in ipairs(typeFolder:GetChildren()) do
            local items = worldFolder:FindFirstChild("Items")
            if items then
                for _, model in ipairs(items:GetChildren()) do
                    local bId = model:FindFirstChild("BreakableID")
                    if bId and bId.Value == id then
                        return model
                    end
                end
            end
        end
    end
    return nil
end

function BreakableService:Init()
    logger = self._modules.Logger
    configLoader = self._modules.ConfigLoader

    local Signals = require(ReplicatedStorage.Shared.Network.Signals)
    Signals.Breakables_Attack.OnServerEvent:Connect(function(player, payload)
        local ok, err = pcall(function()
            self:_onAttack(player, payload)
        end)
        if not ok then
            logger:Warn("Breakables_Attack handler error", { error = tostring(err) })
        end
    end)

    logger:Info("BreakableService initialized")
end

function BreakableService:_onAttack(player, payload)
    if not player or not player:IsA("Player") then return end
    if type(payload) ~= "table" then return end
    local id = tonumber(payload.id)
    local dmg = tonumber(payload.damage) or 1

    -- basic rate limit
    local now = tick()
    if lastAttack[player] and now - lastAttack[player] < 0.05 then
        return
    end
    lastAttack[player] = now

    local target = findBreakableById(id)
    if not target or not target:GetAttribute("HP") then return end

    -- Reduce HP
    local hp = tonumber(target:GetAttribute("HP")) or 0
    local maxHp = tonumber(target:GetAttribute("MaxHP")) or hp
    hp = math.max(0, hp - dmg)
    target:SetAttribute("HP", hp)

    if hp <= 0 then
        -- Reward logic (simple placeholder; can expand later)
        -- Fire sounds/cleanup handled by spawner in MCP; here we just destroy
        target:Destroy()
    end
end

return BreakableService


