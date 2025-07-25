--[[
    NetworkConfig - Configuration-driven network bridge setup
    
    Reads network.lua and automatically:
    - Creates all network bridges
    - Defines all packets with validation
    - Sets up rate limiting
    - Connects handlers
    
    Single source of truth for all networking!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NetworkBridge = require(script.Parent.Parent.Network.NetworkBridge)
local ConfigLoader = require(script.Parent.Parent.ConfigLoader)

local NetworkConfig = {}
local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

-- Store created bridges
local bridges = {}

-- Validation type checkers
local function validateType(value, expectedType)
    if expectedType == "any" then
        return true
    elseif expectedType == "string" then
        return type(value) == "string"
    elseif expectedType == "number" then
        return type(value) == "number"
    elseif expectedType == "boolean" then
        return type(value) == "boolean"
    elseif expectedType == "table" then
        return type(value) == "table"
    end
    return false
end

-- Create validator function from config
local function createValidator(validationConfig)
    return function(data)
        if not data and next(validationConfig) == nil then
            return true -- No validation required
        end
        
        if type(data) ~= "table" then
            return false
        end
        
        for field, expectedType in pairs(validationConfig) do
            if not validateType(data[field], expectedType) then
                return false
            end
        end
        
        return true
    end
end

-- Check if packet should be available on current side
local function shouldDefinePacket(direction)
    if direction == "client_to_server" then
        return true -- Both sides need to know about these
    elseif direction == "server_to_client" then
        return true -- Both sides need to know about these
    end
    return true -- Default: define on both sides
end

function NetworkConfig:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    
    if not self._configLoader then
        if self._logger then
            self._logger:Error("NetworkConfig: ConfigLoader dependency missing")
        end
        return
    end
    
    -- Load network configuration
    local networkConfig = self._configLoader:LoadConfig("network")
    if not networkConfig then
        if self._logger then
            self._logger:Error("Failed to load network configuration")
        end
        return
    end
    
    -- Create bridges and define packets
    for bridgeName, bridgeConfig in pairs(networkConfig.bridges) do
        local bridge = NetworkBridge:CreateBridge(bridgeName)
        bridges[bridgeName] = bridge
        
        if self._logger then
            self._logger:Debug("Created network bridge", {bridge = bridgeName, description = bridgeConfig.description})
        end
        
        -- Define packets for this bridge
        for packetName, packetConfig in pairs(bridgeConfig.packets) do
            if shouldDefinePacket(packetConfig.direction) then
                local validator = createValidator(packetConfig.validation or {})
                
                bridge:DefinePacket(packetName, {
                    rateLimit = packetConfig.rateLimit,
                    validator = validator
                })
                
                if self._logger then
                    self._logger:Debug("Defined packet", {
                        bridge = bridgeName,
                        packet = packetName,
                        rateLimit = packetConfig.rateLimit,
                        direction = packetConfig.direction
                    })
                end
            end
        end
    end
    
    if self._logger then
        self._logger:Info("NetworkConfig initialized", {
            bridgeCount = table.getn(bridges) or 0,
            isServer = IS_SERVER,
            isClient = IS_CLIENT
        })
    end
end

-- Get a bridge by name
function NetworkConfig:GetBridge(bridgeName)
    return bridges[bridgeName]
end

-- Get all bridges
function NetworkConfig:GetBridges()
    return bridges
end

-- Connect server-side handlers automatically
function NetworkConfig:ConnectServerHandlers(services)
    if not IS_SERVER then
        return
    end
    
    local networkConfig = ConfigLoader:LoadConfig("network")
    if not networkConfig then
        return
    end
    
    for bridgeName, bridgeConfig in pairs(networkConfig.bridges) do
        local bridge = bridges[bridgeName]
        if bridge then
            bridge:Connect(function(player, packetType, data)
                local packetConfig = bridgeConfig.packets[packetType]
                if packetConfig and packetConfig.handler then
                    -- Parse handler "ServiceName.MethodName"
                    local serviceName, methodName = string.match(packetConfig.handler, "^([^%.]+)%.(.+)$")
                    if serviceName and methodName then
                        local service = services[serviceName]
                        if service and service[methodName] then
                            service[methodName](service, player, data)
                        elseif self._logger then
                            self._logger:Warn("Handler not found", {
                                service = serviceName,
                                method = methodName,
                                packet = packetType
                            })
                        end
                    end
                end
            end)
        end
    end
end

return NetworkConfig 