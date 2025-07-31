--[[
    EggCurrentTargetService - Following working game's CurrentTarget pattern
    
    Implements the VisibleHandler pattern from the working game:
    - Continuously scans for nearby eggs
    - Sets CurrentTarget.Value 
    - Positions UI at egg's world position
    - Calls setLastEgg server for persistence
--]]

local EggCurrentTargetService = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Dependencies
local Locations = require(ReplicatedStorage.Shared.Locations)
local eggSystemConfig = Locations.getConfig("egg_system")

-- Services
local eggPetPreviewService = nil

-- Get player and camera
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Configuration from config file
local MAX_MAGNITUDE = eggSystemConfig.proximity.max_distance
local UPDATE_INTERVAL = eggSystemConfig.performance.update_interval
local SERVER_UPDATE_THRESHOLD = eggSystemConfig.performance.server_update_threshold

-- Variables
local timecounter = 0
local counter = 0
local currentTargetUI = nil
local currentTarget = "None"
local heartbeatConnection = nil

-- Logger setup using singleton pattern
local Logger
local loggerSuccess, loggerResult = pcall(function()
    return require(Locations.Logger)
end)

if loggerSuccess and loggerResult then
    Logger = loggerResult -- Use singleton directly
else
    Logger = {
        Info = function(self, message, context) print("[INFO]", message, context) end,
        Warn = function(self, message, context) warn("[WARN]", message, context) end,
        Error = function(self, message, context) warn("[ERROR]", message, context) end,
        Debug = function(self, message, context) print("[DEBUG]", message, context) end,
    }
end

-- === HELPER FUNCTIONS ===

function EggCurrentTargetService:DetermineClosest(eggsAvailable)
    local currentClosest = nil
    local closestDistance = MAX_MAGNITUDE
    
    for i, eggName in pairs(eggsAvailable) do
        local egg = nil
        -- Search workspace for egg model
        for _, obj in pairs(workspace:GetChildren()) do
            if obj:IsA("Model") then
                local objEggType = obj:GetAttribute("EggType")
                local eggInfo = obj:FindFirstChild("EggType")
                if eggInfo then objEggType = eggInfo.Value end
                
                if objEggType == eggName then
                    egg = obj
                    break
                end
            end
        end
        
        if egg then
            -- Use the EggSpawnPoint as anchor (referenced in SpawnPoint ObjectValue)
            local spawnPointRef = egg:FindFirstChild("SpawnPoint")
            local anchor = spawnPointRef and spawnPointRef.Value
            
            -- Fallback to PrimaryPart or any Part if no SpawnPoint reference
            if not anchor then
                anchor = egg.PrimaryPart or egg:FindFirstChildOfClass("Part")
            end
            
            if anchor and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local mag = (anchor.Position - player.Character.HumanoidRootPart.Position).Magnitude
                if mag <= closestDistance then
                    currentClosest = egg
                    closestDistance = mag
                end
            end
        end
    end
    
    return currentClosest
end

function EggCurrentTargetService:CreateEggUI()
    if currentTargetUI then
        currentTargetUI:Destroy()
    end
    
    -- Create UI similar to working game's EggPreview
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggCurrentTarget"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = player.PlayerGui
    
    local frame = Instance.new("Frame")
    frame.Name = "PreviewFrame"
    frame.Size = UDim2.new(0, eggSystemConfig.ui.preview_size.width, 0, eggSystemConfig.ui.preview_size.height)
    frame.BackgroundColor3 = eggSystemConfig.ui.colors.background
    frame.BorderSizePixel = 0
    frame.Visible = false  -- Start hidden until an egg is in range
    frame.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, eggSystemConfig.ui.corner_radius)
    corner.Parent = frame
    
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = eggSystemConfig.ui.border_thickness
    stroke.Color = eggSystemConfig.ui.colors.border
    stroke.Parent = frame
    
    local eggNameLabel = Instance.new("TextLabel")
    eggNameLabel.Name = "EggName"
    eggNameLabel.Size = UDim2.new(1, -10, 0.6, 0)
    eggNameLabel.Position = UDim2.new(0, 5, 0, 5)
    eggNameLabel.BackgroundTransparency = 1
    eggNameLabel.Text = "Basic Egg"
    eggNameLabel.TextColor3 = eggSystemConfig.ui.colors.text_primary
    eggNameLabel.TextScaled = true
    eggNameLabel.Font = eggSystemConfig.ui.fonts.title
    eggNameLabel.Parent = frame
    
    local promptLabel = Instance.new("TextLabel")
    promptLabel.Name = "Prompt"
    promptLabel.Size = UDim2.new(1, -10, 0.4, 0)
    promptLabel.Position = UDim2.new(0, 5, 0.6, 0)
    promptLabel.BackgroundTransparency = 1
    promptLabel.Text = "Press " .. eggSystemConfig.proximity.interaction_key.Name .. " to open"
    promptLabel.TextColor3 = eggSystemConfig.ui.colors.text_secondary
    promptLabel.TextScaled = true
    promptLabel.Font = eggSystemConfig.ui.fonts.prompt
    promptLabel.Parent = frame
    
    -- Store CurrentTarget value
    local currentTargetValue = Instance.new("StringValue")
    currentTargetValue.Name = "CurrentTarget"
    currentTargetValue.Value = "None"
    currentTargetValue.Parent = frame
    
    currentTargetUI = screenGui
    return frame
end

function EggCurrentTargetService:UpdateEggUI(egg, eggType)
    if not currentTargetUI then
        self:CreateEggUI()
    end
    
    local frame = currentTargetUI.PreviewFrame
    local currentTargetValue = frame.CurrentTarget
    
    if egg and eggType then
        -- Only update if target has changed
        if currentTarget ~= eggType then
            if eggSystemConfig.debug.log_proximity_changes then
                print("🎯 Now targeting egg:", eggType)
            end
            currentTarget = eggType
            currentTargetValue.Value = eggType
            
            -- Update UI content only when target changes
            frame.EggName.Text = eggType:gsub("_", " ") .. " Egg"
            frame.Visible = true
            
            -- Show pet preview for new egg
            if eggPetPreviewService then
                local anchor = self:GetEggAnchor(egg)
                if anchor then
                    eggPetPreviewService:ShowPetPreview(eggType, anchor)
                end
            end
        end
        
        -- Always update position (player might be moving around the egg)
        local anchor = self:GetEggAnchor(egg)
        
        if anchor then
            local screenPos = camera:WorldToScreenPoint(anchor.Position)
            frame.Position = UDim2.new(0, screenPos.X + eggSystemConfig.ui.position_offset.x, 0, screenPos.Y + eggSystemConfig.ui.position_offset.y)
            
            -- Update pet preview position
            if eggPetPreviewService then
                eggPetPreviewService:UpdatePreviewPosition(anchor)
            end
        end
    else
        -- No egg in range - only update if we had a target before
        if currentTarget ~= "None" then
            if eggSystemConfig.debug.log_proximity_changes then
                print("🚫 No longer targeting egg")
            end
            currentTarget = "None"
            currentTargetValue.Value = "None"
            frame.Visible = false
            
            -- Hide pet preview
            if eggPetPreviewService then
                eggPetPreviewService:HidePetPreview()
            end
        end
    end
end

function EggCurrentTargetService:CallSetLastEgg(eggType)
    -- Call server to set last egg (for persistence like working game)
    local success, result = pcall(function()
        local eggRemote = ReplicatedStorage:FindFirstChild("EggOpened")
        if eggRemote and eggRemote:FindFirstChild("setLastEgg") then
            return eggRemote.setLastEgg:InvokeServer(eggType)
        end
    end)
    
    if success then
        Logger:Debug("Set last egg on server", {eggType = eggType or "nil"})
    else
        Logger:Warn("Failed to set last egg on server", {error = tostring(result)})
    end
end

-- === MAIN UPDATE LOOP (following working game pattern) ===

function EggCurrentTargetService:UpdateTargeting(step)
    timecounter = timecounter + step
    
    if timecounter >= UPDATE_INTERVAL then
        timecounter = timecounter - UPDATE_INTERVAL
        
        if not player.Character or not player.Character:FindFirstChild("Humanoid") then
            return
        end
        
        if player.Character.Humanoid.Health == 0 then
            return
        end
        
        local eggsAvailable = {}
        
        -- Find all eggs in range (scan workspace like working game)
        for _, obj in pairs(workspace:GetChildren()) do
            if obj:IsA("Model") then
                local objEggType = obj:GetAttribute("EggType")
                local eggInfo = obj:FindFirstChild("EggType")
                if eggInfo then objEggType = eggInfo.Value end
                
                if objEggType and player.Character:FindFirstChild("HumanoidRootPart") then
                    -- Use the EggSpawnPoint as anchor (referenced in SpawnPoint ObjectValue)
                    local spawnPointRef = obj:FindFirstChild("SpawnPoint")
                    local anchor = spawnPointRef and spawnPointRef.Value
                    
                    if anchor then
                        local mag = (anchor.Position - player.Character.HumanoidRootPart.Position).Magnitude
                        if mag <= MAX_MAGNITUDE then
                            eggsAvailable[#eggsAvailable + 1] = objEggType
                        end
                    else
                        -- Fallback to PrimaryPart or any Part
                        anchor = obj.PrimaryPart or obj:FindFirstChildOfClass("Part")
                        if anchor then
                            local mag = (anchor.Position - player.Character.HumanoidRootPart.Position).Magnitude
                            if mag <= MAX_MAGNITUDE then
                                eggsAvailable[#eggsAvailable + 1] = objEggType
                            end
                        end
                    end
                end
            end
        end
        
        counter = counter + 1
        
        if #eggsAvailable == 1 then
            -- Single egg in range
            local eggType = eggsAvailable[1]
            local egg = self:FindEggByType(eggType)
            self:UpdateEggUI(egg, eggType)
            
            -- Call setLastEgg periodically (like working game)
            if counter > SERVER_UPDATE_THRESHOLD then
                counter = 0
                self:CallSetLastEgg(eggType)
            end
            
        elseif #eggsAvailable > 1 then
            -- Multiple eggs - find closest
            local egg = self:DetermineClosest(eggsAvailable)
            if egg then
                local eggType = egg:GetAttribute("EggType")
                local eggInfo = egg:FindFirstChild("EggType")
                if eggInfo then eggType = eggInfo.Value end
                
                self:UpdateEggUI(egg, eggType)
                
                if counter > SERVER_UPDATE_THRESHOLD then
                    counter = 0
                    self:CallSetLastEgg(eggType)
                end
            end
            
        elseif #eggsAvailable == 0 then
            -- No eggs in range
            self:UpdateEggUI(nil, nil)
            
            if counter > 100 then -- Less frequent server calls when no eggs
                counter = 0
                self:CallSetLastEgg(nil)
            end
        end
    end
end

function EggCurrentTargetService:FindEggByType(eggType)
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") then
            local objEggType = obj:GetAttribute("EggType")
            local eggInfo = obj:FindFirstChild("EggType")
            if eggInfo then objEggType = eggInfo.Value end
            
            if objEggType == eggType then
                return obj
            end
        end
    end
    return nil
end

-- Helper function to get egg anchor position
function EggCurrentTargetService:GetEggAnchor(egg)
    if not egg then return nil end
    
    -- Use the EggSpawnPoint as anchor (referenced in SpawnPoint ObjectValue)
    local spawnPointRef = egg:FindFirstChild("SpawnPoint")
    local anchor = spawnPointRef and spawnPointRef.Value
    
    -- Fallback to PrimaryPart or any Part if no SpawnPoint reference
    if not anchor then
        anchor = egg.PrimaryPart or egg:FindFirstChildOfClass("Part")
    end
    
    return anchor
end

function EggCurrentTargetService:GetCurrentTarget()
    return currentTarget
end

-- === INITIALIZATION ===

function EggCurrentTargetService:Initialize()
    Logger:Info("EggCurrentTargetService initializing...", {})
    
    -- Load pet preview service
    local success, petPreviewService = pcall(function()
        return require(ReplicatedStorage.Shared.Services.EggPetPreviewService)
    end)
    
    if success then
        eggPetPreviewService = petPreviewService
        eggPetPreviewService:Initialize()
        Logger:Info("Pet preview service loaded successfully", {})
    else
        Logger:Warn("Failed to load pet preview service", {error = tostring(petPreviewService)})
    end
    
    -- Start the targeting update loop (like working game's VisibleHandler)
    heartbeatConnection = RunService.Heartbeat:Connect(function(step)
        self:UpdateTargeting(step)
    end)
    
    Logger:Info("EggCurrentTargetService initialized - targeting system active", {})
end

function EggCurrentTargetService:Destroy()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end
    
    if currentTargetUI then
        currentTargetUI:Destroy()
        currentTargetUI = nil
    end
    
    if eggPetPreviewService then
        eggPetPreviewService:Destroy()
        eggPetPreviewService = nil
    end
    
    Logger:Info("EggCurrentTargetService destroyed", {})
end

return EggCurrentTargetService