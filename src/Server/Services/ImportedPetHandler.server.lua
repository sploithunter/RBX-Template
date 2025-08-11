--[[
    ImportedPetHandler Server Script
    
    This contains the pet spawning and following mechanics imported from the other game,
    modified to work with our equipment bridge system.
    
    The key modification is that instead of looking for Pet.Equipped.Value directly,
    it relies on the bridge to set those values before calling loadEquipped.
--]]

-- This legacy handler spawned placeholder neon-blue boxes with pet names.
-- We now use the real `PetHandler.server.lua`. Disable this script to avoid
-- duplicate/placeholder visuals.
-- fallback is disabled by default; keep callable for debug

local ENABLE_LEGACY_HANDLER = false
if not ENABLE_LEGACY_HANDLER then
    print("⏸️ ImportedPetHandler: Disabled (using native PetHandler)")
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")

-- Constants from the original system
local PET_CIRCLE_RADIUS = 8  -- Adjust based on your preference

-- Storage for pet models and connections
local playerPetModels = {}
local playerPetConnections = {}

-- Create workspace folders if they don't exist
if not workspace:FindFirstChild("PlayerPets") then
    local folder = Instance.new("Folder")
    folder.Name = "PlayerPets"
    folder.Parent = workspace
end

if not workspace:FindFirstChild("PlayerPetControl") then
    local folder = Instance.new("Folder")
    folder.Name = "PlayerPetControl"
    folder.Parent = workspace
end

-- Utility function to get point on circle
local function getPointOnCircle(radius, degrees)
    return Vector3.new(
        math.cos(math.rad(degrees)) * radius,
        1,
        math.sin(math.rad(degrees)) * radius
    )
end

-- Get equipped pets (those with Equipped.Value = true)
local function getEquippedPets(player)
    local equipped = {}
    

    
    -- Look for pets with Equipped.Value = true in Inventory/pets
    -- The bridge should have already set these values
    local inventoryFolder = player:FindFirstChild("Inventory")
    if not inventoryFolder then
        warn("ImportedPetHandler: No Inventory folder found for", player.Name)
        return equipped
    end
    
    local petsFolder = inventoryFolder:FindFirstChild("pets")
    if not petsFolder then
        warn("ImportedPetHandler: No pets folder found in Inventory for", player.Name)
        warn("ImportedPetHandler: Full path checked:", player:GetFullName() .. "/Inventory/pets")
        return equipped
    end
    
    for _, petFolder in ipairs(petsFolder:GetChildren()) do
        if petFolder:IsA("Folder") then
            local equippedValue = petFolder:FindFirstChild("Equipped")
            if equippedValue and equippedValue:IsA("BoolValue") and equippedValue.Value then
                local petData = {
                    folder = petFolder,
                    uid = petFolder:GetAttribute("uid") or petFolder.Name,
                    petId = petFolder:FindFirstChild("PetID") and petFolder.PetID.Value,
                    type = (petFolder:FindFirstChild("ItemId") and petFolder.ItemId.Value) or (petFolder:FindFirstChild("Type") and petFolder.Type.Value) or petFolder.Name,
                    variant = petFolder:FindFirstChild("Variant") and petFolder.Variant.Value,
                    name = petFolder.Name,
                }
                print("📦 ImportedPetHandler: equipped folder ->", petData.name, "type=", petData.type, "variant=", petData.variant)
                table.insert(equipped, petData)
            end
        end
    end
    
    return equipped
end

-- Clean up existing pet models and connections
local function cleanupPlayerPets(player)
    -- Clean up connections
    if playerPetConnections[player] then
        for _, connection in pairs(playerPetConnections[player]) do
            if typeof(connection) == "RBXScriptConnection" then
                connection:Disconnect()
            end
        end
        playerPetConnections[player] = nil
    end
    
    -- Clean up pet models
    local petsFolder = workspace.PlayerPets:FindFirstChild(player.Name)
    if petsFolder then
        petsFolder:ClearAllChildren()
    end
    
    -- Clean up control boxes
    local controlFolder = workspace.PlayerPetControl:FindFirstChild(player.Name)
    if controlFolder then
        controlFolder:ClearAllChildren()
    end
    
    -- Clear model storage
    playerPetModels[player] = nil
end

-- Create control box for pet movement
local function createControlBox(player, index)
    local controlFolder = workspace.PlayerPetControl:FindFirstChild(player.Name)
    if not controlFolder then
        controlFolder = Instance.new("Folder")
        controlFolder.Name = player.Name
        controlFolder.Parent = workspace.PlayerPetControl
    end
    
    local box = Instance.new("Part")
    box.Name = tostring(index)
    box.Size = Vector3.new(1, 1, 1)
    box.Transparency = 1
    box.CanCollide = false
    box.Anchored = true
    box.Parent = controlFolder
    
    -- Add attachment point for pet
    local attachment = Instance.new("Attachment")
    attachment.Name = "Pet"
    attachment.Parent = box
    
    return box
end

-- Load pet model (integrate with your pet configuration system)
local function loadPetModel(petData)
    -- This would integrate with your pet configuration system
    -- For now, create a placeholder that shows pet info
    local model = Instance.new("Model")
    model.Name = petData.name
    
    -- Create a simple part as placeholder
    -- Replace this with actual pet model loading from your configs
    local part = Instance.new("Part")
    part.Name = "Root"
    part.Size = Vector3.new(2, 2, 2)
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.CanCollide = false
    
    -- Add some visual distinction
    part.BrickColor = BrickColor.new("Bright blue")
    part.Material = Enum.Material.Neon
    part.Transparency = 0.3
    
    -- Add a billboard gui to show pet name
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 200, 0, 50)
    billboardGui.StudsOffset = Vector3.new(0, 3, 0)
    billboardGui.Parent = part
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = petData.name
    textLabel.TextScaled = true
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.Parent = billboardGui
    
    part.Parent = model
    model.PrimaryPart = part
    
    -- You would load the actual pet model from your configs here
    -- Example:
    -- local petConfig = require(ReplicatedStorage.Configs.pets)[petData.petId]
    -- local actualModel = ReplicatedStorage.PetModels[petConfig.modelName]:Clone()
    -- return actualModel
    
    return model
end

-- Initialize pet follow behavior
local function initializePetFollow(player, petModel, controlBox, positionOffset)
    local connection
    
    connection = RunService.Heartbeat:Connect(function()
        if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            return
        end
        
        if not petModel.Parent or not petModel.PrimaryPart then
            connection:Disconnect()
            return
        end
        
        if not controlBox.Parent then
            connection:Disconnect()
            return
        end
        
        -- Update control box position
        local targetPosition = player.Character.HumanoidRootPart.Position + positionOffset
        controlBox.Position = targetPosition
        
        -- Smooth pet movement towards control box
        local currentCFrame = petModel.PrimaryPart.CFrame
        local targetCFrame = CFrame.new(controlBox.Position) * CFrame.Angles(0, math.rad(180), 0)
        
        -- Lerp for smooth movement
        petModel.PrimaryPart.CFrame = currentCFrame:Lerp(targetCFrame, 0.1)
    end)
    
    -- Store connection for cleanup
    playerPetConnections[player] = playerPetConnections[player] or {}
    table.insert(playerPetConnections[player], connection)
    
    return connection
end

-- Spawn a single pet
local function spawnPet(player, petData, index, angleIncrement)
    print("🐕 ImportedPetHandler: Spawning pet", petData.name, "for", player.Name)
    
    -- Create control box for pet movement
    local controlBox = createControlBox(player, index)
    
    -- Load pet model
    local petModel = loadPetModel(petData)
    if not petModel then
        warn("ImportedPetHandler: Failed to load pet model", petData.name)
        return
    end
    
    -- Set up pet properties
    petModel:SetAttribute("PetUID", petData.uid)
    petModel:SetAttribute("OwnerUserId", player.UserId)
    petModel:SetAttribute("PositionNumber", index)
    
    -- Calculate position offset
    local angle = angleIncrement * index
    local offset = getPointOnCircle(PET_CIRCLE_RADIUS, angle)
    
    -- Parent pet model
    local playerPetsFolder = workspace.PlayerPets:FindFirstChild(player.Name)
    if not playerPetsFolder then
        playerPetsFolder = Instance.new("Folder")
        playerPetsFolder.Name = player.Name
        playerPetsFolder.Parent = workspace.PlayerPets
    end
    
    petModel.Parent = playerPetsFolder
    
    -- Set network owner for smooth movement
    if petModel.PrimaryPart then
        petModel.PrimaryPart:SetNetworkOwner(player)
    end
    
    -- Initialize follow behavior
    initializePetFollow(player, petModel, controlBox, offset)
    
    -- Store reference
    playerPetModels[player] = playerPetModels[player] or {}
    playerPetModels[player][petData.uid] = petModel
end

-- Update equipped stats
local function updateEquippedStats(player, equippedPets)
    -- Update any stats or values that depend on equipped pets
    local currentEquipValue = player:FindFirstChild("CurrentEquip")
    if currentEquipValue then
        currentEquipValue.Value = #equippedPets
    end
    
    -- You can add more stat updates here based on your needs
end

-- Main function called by the bridge
local function loadEquipped(player)
    print("🔄 ImportedPetHandler: Loading equipped pets for", player.Name)
    local inv = player:FindFirstChild("Inventory")
    if inv and inv:FindFirstChild("pets") then
        local list = {}
        for _, c in ipairs(inv.pets:GetChildren()) do
            if c:IsA("Folder") then
                table.insert(list, c.Name .. "(eq=" .. tostring(c:FindFirstChild("Equipped") and c.Equipped.Value) .. ")")
            end
        end
        print("📦 ImportedPetHandler: Inventory/pets:", table.concat(list, ", "))
    else
        print("⚠️ ImportedPetHandler: No Inventory/pets found")
    end
    
    local char = player.Character
    if not char then
        warn("ImportedPetHandler: No character found for", player.Name)
        return
    end
    
    -- Clean up existing pet models
    cleanupPlayerPets(player)
    
    -- Get currently equipped pets
    local currentlyEquipped = getEquippedPets(player)
    
    print("ImportedPetHandler: Found", #currentlyEquipped, "equipped pets")
    
    -- Create control boxes and spawn pets
    local increment = 360 / math.max(#currentlyEquipped, 1)
    
    for i, petData in ipairs(currentlyEquipped) do
        spawnPet(player, petData, i, increment)
    end
    
    -- Update any UI or stats that depend on equipped pets
    updateEquippedStats(player, currentlyEquipped)
    
    return "Success"
end

-- Register the loadEquipped function with the bridge
if _G.SetPetLoadEquippedFunction then
    _G.SetPetLoadEquippedFunction(loadEquipped)
else
    -- Wait a bit and try again
    task.wait(1)
    if _G.SetPetLoadEquippedFunction then
        _G.SetPetLoadEquippedFunction(loadEquipped)
    else
        warn("ImportedPetHandler: Could not register with PetEquipmentBridge!")
    end
end

-- Clean up when players leave
Players.PlayerRemoving:Connect(function(player)
    cleanupPlayerPets(player)
end)

print("✅ ImportedPetHandler: Initialized and registered with bridge")