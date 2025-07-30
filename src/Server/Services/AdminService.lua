-- AdminService
-- Handles admin authorization and security
-- CRITICAL: This service must remain SERVER-SIDE ONLY to prevent client injection

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AdminService = {}
AdminService.__index = AdminService

function AdminService.new()
    local self = setmetatable({}, AdminService)
    self._logger = nil
    self._configLoader = nil
    self._adminConfig = nil
    
    return self
end

function AdminService:Init()
    -- Get dependencies
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    
    -- Load admin configuration
    local success, adminConfig = pcall(function()
        return self._configLoader:LoadConfig("admins")
    end)
    
    if success and adminConfig then
        self._adminConfig = adminConfig
        self._logger:Info("AdminService initialized", {
            authorizedUserCount = #adminConfig.authorizedUsers,
            securityEnabled = adminConfig.security.logAllAdminActions
        })
    else
        self._logger:Error("Failed to load admin configuration", {error = adminConfig})
        -- Fail safe - no admins authorized if config fails
        self._adminConfig = {
            authorizedUsers = {},
            permissions = {},
            security = { logAllAdminActions = true, requireStudioForSensitiveOps = true }
        }
    end
end

-- Check if a player is authorized as an admin
function AdminService:IsAuthorized(player)
    if not player or not self._adminConfig then
        return false
    end
    
    local userId = player.UserId
    
    -- Check if user is in authorized list
    for _, authorizedUserId in ipairs(self._adminConfig.authorizedUsers) do
        if userId == authorizedUserId then
            return true
        end
    end
    
    return false
end

-- Check if an admin has a specific permission
function AdminService:HasPermission(player, permission)
    if not self:IsAuthorized(player) then
        return false
    end
    
    if not self._adminConfig.permissions then
        return false
    end
    
    return self._adminConfig.permissions[permission] == true
end

-- Validate an admin action request
function AdminService:ValidateAdminAction(player, action, data, source)
    -- Source can be "client" or "server"
    source = source or "unknown"
    
    -- Log the admin action attempt
    if self._adminConfig.security.logAllAdminActions then
        self._logger:Info("🛡️ ADMIN ACTION ATTEMPT", {
            player = player.Name,
            userId = player.UserId,
            action = action,
            data = data,
            source = source,
            timestamp = os.time()
        })
    end
    
    -- Check if player is authorized
    if not self:IsAuthorized(player) then
        self._logger:Warn("🚨 UNAUTHORIZED ADMIN ACTION BLOCKED", {
            player = player.Name,
            userId = player.UserId,
            action = action,
            reason = "Not authorized as admin"
        })
        return false, "Not authorized"
    end
    
    -- Check specific permission
    if not self:HasPermission(player, action) then
        self._logger:Warn("🚨 ADMIN ACTION BLOCKED - INSUFFICIENT PERMISSION", {
            player = player.Name,
            userId = player.UserId,
            action = action,
            reason = "Missing permission: " .. tostring(action)
        })
        return false, "Insufficient permissions"
    end
    
    -- Check security restrictions
    if source == "client" and self._adminConfig.security.blockClientRequests then
        self._logger:Warn("🚨 CLIENT ADMIN REQUEST BLOCKED", {
            player = player.Name,
            userId = player.UserId,
            action = action,
            reason = "Client requests blocked by security policy"
        })
        return false, "Client requests not allowed"
    end
    
    -- Check Studio requirement for sensitive operations
    local sensitiveOps = {"resetData", "setCurrency"}
    if self._adminConfig.security.requireStudioForSensitiveOps then
        for _, sensitiveOp in ipairs(sensitiveOps) do
            if action == sensitiveOp and not RunService:IsStudio() then
                self._logger:Warn("🚨 SENSITIVE ADMIN ACTION BLOCKED - NOT IN STUDIO", {
                    player = player.Name,
                    userId = player.UserId,
                    action = action,
                    reason = "Sensitive operation requires Studio environment"
                })
                return false, "Sensitive operations require Studio"
            end
        end
    end
    
    -- Action is authorized
    self._logger:Info("✅ ADMIN ACTION AUTHORIZED", {
        player = player.Name,
        userId = player.UserId,
        action = action,
        source = source
    })
    
    return true, "Authorized"
end

-- Get admin status for a player
function AdminService:GetAdminStatus(player)
    return {
        isAuthorized = self:IsAuthorized(player),
        permissions = self._adminConfig.permissions,
        userId = player.UserId
    }
end

return AdminService