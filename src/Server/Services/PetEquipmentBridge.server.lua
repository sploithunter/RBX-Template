--[[
    PetEquipmentBridge Server Script
    
    This server script bridges between our Equipped/pets folder system and the boolean-based
    system from the imported pet mechanics. It converts folder changes to the loadEquipped()
    calls expected by the imported system.
    
    Our System: Player/Equipped/pets/slot_X (StringValue with pet UID)
    Their System: Pet.Equipped.Value = true/false (BoolValue on each pet)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Silence verbose prints unless enabled
local __RAW_PRINT = print
local __PRINT_ENABLED = false
local function print(...)
    if __PRINT_ENABLED then
        __RAW_PRINT(...)
    end
end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- This will be populated when ImportedPetHandler initializes
local loadEquippedFunction = nil

-- Cache for tracking equipped pets per player
local equippedPets = {}
local playerConnections = {}
local loadDebounce = {}

-- Function to set the loadEquipped function from ImportedPetHandler
_G.SetPetLoadEquippedFunction = function(func)
    loadEquippedFunction = func
    print("✅ PetEquipmentBridge: LoadEquipped function registered")
end

local function getEquippedCount(player)
    local count = 0
    for _ in pairs(equippedPets[player] or {}) do
        count = count + 1
    end
    return count
end

local function updatePetBooleanStates(player)
    -- This function updates the boolean Equipped values on pets to match our folder system
    -- It acts as the bridge between the two systems
    
    local equippedFolder = player:FindFirstChild("Equipped")
    if not equippedFolder then return end
    
    local petsFolder = equippedFolder:FindFirstChild("pets")
    if not petsFolder then return end
    
    -- Build a set of currently equipped pet UIDs
    local equippedUids = {}
    for _, slotValue in ipairs(petsFolder:GetChildren()) do
        if slotValue:IsA("StringValue") and slotValue.Value ~= "" then
            equippedUids[slotValue.Value] = true
        end
    end
    
    -- Now update the boolean values on the actual pet data in Inventory/pets
    local inventoryFolder = player:FindFirstChild("Inventory")
    if not inventoryFolder then
        warn("PetEquipmentBridge: No Inventory folder found for", player.Name)
        return
    end
    
    local petsDataFolder = inventoryFolder:FindFirstChild("pets")
    if petsDataFolder then
        for _, petFolder in ipairs(petsDataFolder:GetChildren()) do
            if petFolder:IsA("Folder") then
                -- Find or create the Equipped BoolValue
                local equippedValue = petFolder:FindFirstChild("Equipped")
                if not equippedValue then
                    equippedValue = Instance.new("BoolValue")
                    equippedValue.Name = "Equipped"
                    equippedValue.Parent = petFolder
                end
                
                -- Set based on whether this pet's UID is in our equipped set
                local petUid = petFolder:GetAttribute("uid") or petFolder.Name
                equippedValue.Value = equippedUids[petUid] == true
                

            end
        end
    else
        warn("PetEquipmentBridge: No pets folder found in Inventory for", player.Name)
    end
end

local function triggerLoadEquipped(player)
    -- Debounce rapid changes
    if loadDebounce[player] then
        return
    end
    
    loadDebounce[player] = true
    
    task.spawn(function()
        task.wait(0.1) -- Small debounce
        loadDebounce[player] = nil
        
        print("🔄 PetEquipmentBridge: Triggering loadEquipped for", player.Name, "with", getEquippedCount(player), "pets")
        
        -- Call the imported loadEquipped function
        if loadEquippedFunction then
            -- The imported function expects pets to have Equipped.Value set
            -- We need to update pet data before calling
            updatePetBooleanStates(player)
            
            -- Now call the imported function
            local success, err = pcall(loadEquippedFunction, player)
            if not success then
                warn("❌ PetEquipmentBridge: Failed to call loadEquipped -", err)
            end
        else
            warn("⚠️ PetEquipmentBridge: No loadEquipped function set! Waiting for ImportedPetHandler...")
        end
    end)
end

local function setupSlotListener(player, slotValue)
    local connections = playerConnections[player]
    if not connections then return end
    
    -- Create a unique key for this connection
    local connectionKey = "slot_" .. slotValue.Name .. "_changed"
    
    -- Clean up old connection if it exists
    if connections[connectionKey] then
        connections[connectionKey]:Disconnect()
    end
    
    -- Listen for value changes on this slot
    connections[connectionKey] = slotValue:GetPropertyChangedSignal("Value"):Connect(function()
        print("🔄 PetEquipmentBridge: Slot value changed -", slotValue.Name, "=", slotValue.Value)
        
        -- Update equipped pets cache
        equippedPets[player] = equippedPets[player] or {}
        
        -- Clear all pets first (we'll rebuild from current slots)
        for uid in pairs(equippedPets[player]) do
            equippedPets[player][uid] = nil
        end
        
        -- Rebuild from all current slots
        local petsFolder = slotValue.Parent
        for _, slot in ipairs(petsFolder:GetChildren()) do
            if slot:IsA("StringValue") and slot.Value ~= "" then
                equippedPets[player][slot.Value] = true
            end
        end
        
        triggerLoadEquipped(player)
    end)
end

local function setupPetsFolder(player, petsFolder)
    print("📁 PetEquipmentBridge: Setting up pets folder listeners for", player.Name)
    
    local connections = playerConnections[player]
    if not connections then return end
    
    -- Initial scan of equipped pets
    equippedPets[player] = {}
    for _, slotValue in ipairs(petsFolder:GetChildren()) do
        if slotValue:IsA("StringValue") and slotValue.Value ~= "" then
            equippedPets[player][slotValue.Value] = true
        end
    end
    
    -- Trigger initial load
    triggerLoadEquipped(player)
    
    -- Listen for new slots being added
    connections.slotAdded = petsFolder.ChildAdded:Connect(function(child)
        if child:IsA("StringValue") then
            print("➕ PetEquipmentBridge: Slot added -", child.Name)
            setupSlotListener(player, child)
            
            -- If slot has a value, update and trigger
            if child.Value ~= "" then
                equippedPets[player][child.Value] = true
                triggerLoadEquipped(player)
            end
        end
    end)
    
    -- Listen for slots being removed
    connections.slotRemoved = petsFolder.ChildRemoved:Connect(function(child)
        if child:IsA("StringValue") then
            print("➖ PetEquipmentBridge: Slot removed -", child.Name)
            
            -- Clean up the connection for this slot
            local connectionKey = "slot_" .. child.Name .. "_changed"
            if connections[connectionKey] then
                connections[connectionKey]:Disconnect()
                connections[connectionKey] = nil
            end
            
            -- If slot had a value, update and trigger
            if child.Value ~= "" then
                equippedPets[player][child.Value] = nil
                triggerLoadEquipped(player)
            end
        end
    end)
    
    -- Set up listeners for existing slots
    for _, slotValue in ipairs(petsFolder:GetChildren()) do
        if slotValue:IsA("StringValue") then
            setupSlotListener(player, slotValue)
        end
    end
end

local function onCharacterAdded(player, character)
    print("👤 PetEquipmentBridge: Character added for", player.Name)
    
    -- Wait for equipped folder
    local equippedFolder = player:WaitForChild("Equipped", 10)
    if not equippedFolder then
        warn("❌ PetEquipmentBridge: No equipped folder found for", player.Name)
        return
    end
    
    -- Wait for pets folder
    local petsFolder = equippedFolder:FindFirstChild("pets")
    if not petsFolder then
        -- Wait for it to be created
        local connection
        connection = equippedFolder.ChildAdded:Connect(function(child)
            if child.Name == "pets" and child:IsA("Folder") then
                connection:Disconnect()
                setupPetsFolder(player, child)
            end
        end)
        
        -- Store this connection
        if playerConnections[player] then
            playerConnections[player].waitingForPets = connection
        end
    else
        setupPetsFolder(player, petsFolder)
    end
end

local function setupPlayer(player)
    print("🎮 PetEquipmentBridge: Setting up equipment bridge for", player.Name)
    
    -- Initialize connections storage
    playerConnections[player] = {}
    equippedPets[player] = {}
    
    -- Connect character events
    playerConnections[player].characterAdded = player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)
    
    -- If character already exists
    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end

local function cleanupPlayer(player)
    print("🧹 PetEquipmentBridge: Cleaning up", player.Name)
    
    -- Clean up all connections
    if playerConnections[player] then
        for key, connection in pairs(playerConnections[player]) do
            if typeof(connection) == "RBXScriptConnection" then
                connection:Disconnect()
            end
        end
        playerConnections[player] = nil
    end
    
    -- Clear equipped cache
    equippedPets[player] = nil
    loadDebounce[player] = nil
end

-- Initialize
print("🌉 PetEquipmentBridge: Initializing...")

-- Connect existing players
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

-- Connect future players
Players.PlayerAdded:Connect(setupPlayer)

-- Cleanup on player removal
Players.PlayerRemoving:Connect(cleanupPlayer)

print("✅ PetEquipmentBridge: Initialized and waiting for ImportedPetHandler...")