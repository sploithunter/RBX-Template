--[[
    ServerClockService - Server-authoritative timing system
    
    Based on Roblox best practices for server-authoritative systems.
    Provides synchronized timing between server and all clients.
    
    Features:
    - Server-authoritative time source
    - Client synchronization with latency compensation
    - Consistent time references for all game systems
    - Player clock tracking for persistent effects
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ServerClockService = {}
ServerClockService.__index = ServerClockService

-- Server clock state
local serverStartTime = nil
local playerClocks = {} -- Track individual player clocks

function ServerClockService:Init()
    self._logger = self._modules.Logger
    
    if not self._logger then
        error("ServerClockService: Logger dependency missing")
    end
    
    -- Initialize server clock
    if RunService:IsServer() then
        serverStartTime = os.time()
        self._logger:Info("Server clock initialized", {
            serverStartTime = serverStartTime,
            osTime = os.time()
        })
        
        -- Clean up player clocks when players leave
        Players.PlayerRemoving:Connect(function(player)
            self:_cleanupPlayerClock(player)
        end)
    end
end

-- Get authoritative server time (always use this for game logic)
function ServerClockService:GetServerTime()
    if RunService:IsServer() then
        return os.time()
    else
        error("GetServerTime() should only be called on server")
    end
end

-- Get server time as a precise float for high-resolution timing
function ServerClockService:GetServerTimePrecise()
    if RunService:IsServer() then
        -- Use tick() for sub-second precision, but offset by server start
        return serverStartTime + (tick() - serverStartTime)
    else
        error("GetServerTimePrecise() should only be called on server")
    end
end

-- Initialize player clock when they join
function ServerClockService:InitializePlayerClock(player)
    local userId = player.UserId
    local currentTime = self:GetServerTime()
    
    playerClocks[userId] = {
        joinTime = currentTime,
        lastUpdateTime = currentTime,
        totalPlayTime = 0,
        sessionStartTime = currentTime
    }
    
    self._logger:Info("Player clock initialized", {
        player = player.Name,
        joinTime = currentTime
    })
end

-- Update player clock (call periodically to track play time)
function ServerClockService:UpdatePlayerClock(player)
    local userId = player.UserId
    local playerClock = playerClocks[userId]
    
    if not playerClock then
        self:InitializePlayerClock(player)
        return
    end
    
    local currentTime = self:GetServerTime()
    local timeDelta = currentTime - playerClock.lastUpdateTime
    
    playerClock.totalPlayTime = playerClock.totalPlayTime + timeDelta
    playerClock.lastUpdateTime = currentTime
    
    return playerClock
end

-- Get player's current session time
function ServerClockService:GetPlayerSessionTime(player)
    local userId = player.UserId
    local playerClock = playerClocks[userId]
    
    if not playerClock then
        return 0
    end
    
    return self:GetServerTime() - playerClock.sessionStartTime
end

-- Get player's total play time
function ServerClockService:GetPlayerTotalPlayTime(player)
    local userId = player.UserId
    local playerClock = playerClocks[userId]
    
    if not playerClock then
        return 0
    end
    
    -- Update clock before returning
    self:UpdatePlayerClock(player)
    return playerClock.totalPlayTime
end

-- Calculate time remaining for an effect (server-authoritative)
function ServerClockService:CalculateTimeRemaining(expiresAt)
    if expiresAt == -1 then
        return -1 -- Permanent effect
    end
    
    local currentTime = self:GetServerTime()
    return math.max(0, expiresAt - currentTime)
end

-- Create an expiration timestamp for a duration from now
function ServerClockService:CreateExpirationTime(duration)
    if duration == -1 then
        return -1 -- Permanent
    end
    
    return self:GetServerTime() + duration
end

-- Check if a timestamp has expired
function ServerClockService:HasExpired(expiresAt)
    if expiresAt == -1 then
        return false -- Permanent effects never expire
    end
    
    return self:GetServerTime() >= expiresAt
end

-- Get server uptime (useful for intervals and performance metrics)
function ServerClockService:GetServerUptime()
    if not serverStartTime then
        return 0
    end
    
    return os.time() - serverStartTime
end

-- Format time for display (helper function)
function ServerClockService:FormatTimeRemaining(timeRemaining)
    if timeRemaining == -1 then
        return "Permanent"
    elseif timeRemaining <= 0 then
        return "Expired" 
    elseif timeRemaining < 60 then
        return string.format("%ds", math.ceil(timeRemaining))
    elseif timeRemaining < 3600 then
        return string.format("%dm %ds", math.floor(timeRemaining / 60), math.ceil(timeRemaining % 60))
    else
        return string.format("%dh %dm", math.floor(timeRemaining / 3600), math.floor((timeRemaining % 3600) / 60))
    end
end

-- Private helper to cleanup player data
function ServerClockService:_cleanupPlayerClock(player)
    local userId = player.UserId
    if playerClocks[userId] then
        self._logger:Debug("Player clock cleaned up", {
            player = player.Name,
            totalPlayTime = playerClocks[userId].totalPlayTime
        })
        playerClocks[userId] = nil
    end
end

-- Debug method to get all player clocks (for testing)
function ServerClockService:GetAllPlayerClocks()
    return playerClocks
end

return ServerClockService 