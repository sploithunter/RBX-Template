--[[
    Logger - Centralized logging system for debugging and monitoring
    
    Features:
    - Multiple log levels (Debug, Info, Warn, Error)
    - Structured logging with context
    - Performance tracking
    - Remote logging capability
    
    Usage:
    local Logger = require(ReplicatedStorage.Shared.Utils.Logger)
    Logger:Info("Player joined", {playerId = player.UserId})
    Logger:Error("Failed to load data", {error = err, playerId = player.UserId})
]]

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Logger = {}
Logger.__index = Logger

-- Log levels
local LogLevel = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

local LogLevelNames = {
    [LogLevel.DEBUG] = "DEBUG",
    [LogLevel.INFO] = "INFO",
    [LogLevel.WARN] = "WARN",
    [LogLevel.ERROR] = "ERROR"
}

-- Default configuration
local Config = {
    MinLogLevel = LogLevel.INFO, -- Always use INFO level now that systems are stable
    EnableRemoteLogging = false,
    MaxLogHistory = 100
}

-- Internal state
local LogHistory = {}
local StartTime = tick()

-- Color codes for output
local Colors = {
    [LogLevel.DEBUG] = "\27[36m", -- Cyan
    [LogLevel.INFO] = "\27[32m",  -- Green
    [LogLevel.WARN] = "\27[33m",  -- Yellow
    [LogLevel.ERROR] = "\27[31m"  -- Red
}
local ColorReset = "\27[0m"

function Logger:Init()
    -- Initialize logger
    self:Info("Logger initialized", {
        minLogLevel = LogLevelNames[Config.MinLogLevel],
        isStudio = RunService:IsStudio(),
        isServer = RunService:IsServer()
    })
end

function Logger:SetLogLevel(level)
    Config.MinLogLevel = level
    self:Info("Log level changed", {newLevel = LogLevelNames[level]})
end

function Logger:_log(level, message, context)
    if level < Config.MinLogLevel then
        return
    end
    
    local timestamp = tick() - StartTime
    local levelName = LogLevelNames[level]
    local contextStr = ""
    
    if context and type(context) == "table" then
        contextStr = " " .. HttpService:JSONEncode(context)
    end
    
    local logEntry = {
        timestamp = timestamp,
        level = level,
        levelName = levelName,
        message = message,
        context = context
    }
    
    -- Add to history
    table.insert(LogHistory, logEntry)
    if #LogHistory > Config.MaxLogHistory then
        table.remove(LogHistory, 1)
    end
    
    -- Format output
    local output = string.format(
        "%s[%.3f] [%s] %s%s%s",
        Colors[level] or "",
        timestamp,
        levelName,
        message,
        contextStr,
        ColorReset
    )
    
    if level >= LogLevel.ERROR then
        warn(output)
    else
        print(output)
    end
    
    -- Remote logging (if enabled)
    if Config.EnableRemoteLogging and RunService:IsServer() then
        self:_sendRemoteLog(logEntry)
    end
end

function Logger:Debug(message, context)
    self:_log(LogLevel.DEBUG, message, context)
end

function Logger:Info(message, context)
    self:_log(LogLevel.INFO, message, context)
end

function Logger:Warn(message, context)
    self:_log(LogLevel.WARN, message, context)
end

function Logger:Error(message, context)
    self:_log(LogLevel.ERROR, message, context)
end

function Logger:Performance(name, func, ...)
    local startTime = tick()
    local results = {func(...)}
    local endTime = tick()
    local duration = endTime - startTime
    
    self:Debug("Performance measurement", {
        operation = name,
        duration = duration,
        durationMs = duration * 1000
    })
    
    return unpack(results)
end

function Logger:StartTimer(name)
    return {
        name = name,
        startTime = tick()
    }
end

function Logger:EndTimer(timer)
    local duration = tick() - timer.startTime
    self:Debug("Timer completed", {
        name = timer.name,
        duration = duration,
        durationMs = duration * 1000
    })
    return duration
end

function Logger:GetHistory()
    return LogHistory
end

function Logger:ClearHistory()
    LogHistory = {}
    self:Info("Log history cleared")
end

function Logger:_sendRemoteLog(logEntry)
    -- TODO: Implement remote logging to external service
    -- This could send logs to Discord webhooks, external APIs, etc.
end

-- Global error handler
local function globalErrorHandler(message, trace)
    Logger:Error("Uncaught error", {
        message = message,
        trace = trace,
        timestamp = tick()
    })
end

-- Set up global error handling
if not _G.__LOGGER_ERROR_HANDLER_SET then
    _G.__LOGGER_ERROR_HANDLER_SET = true
    local LogService = game:GetService("LogService")
    if LogService then
        LogService.MessageOut:Connect(function(message, messageType)
            if messageType == Enum.MessageType.MessageError then
                globalErrorHandler(message)
            end
        end)
    end
end

return Logger 