--[[
    PetHandler Server Script
    
    This is a direct adaptation of the original PetHandler from the other game,
    converted to work with Rojo and our equipment bridge system.
    
    Key changes:
    - Uses our Inventory/pets structure instead of Player.Pets
    - Creates all objects programmatically instead of relying on PetSetup folder
    - Integrates with our PetEquipmentBridge for equipped status
    - Loads REAL pet models from ReplicatedStorage.Assets (not placeholders!)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")

-- Create event for asset loading completion
if not _G.AssetsLoadedEvent then
    _G.AssetsLoadedEvent = Instance.new("BindableEvent")
end
_G.AssetsLoadingComplete = false

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

-- Create global pet float values
local globalPetFloat = game.ServerScriptService:FindFirstChild("globalPetFloat")
if not globalPetFloat then
    globalPetFloat = Instance.new("NumberValue")
    globalPetFloat.Name = "globalPetFloat"
    globalPetFloat.Value = 333
    globalPetFloat.Parent = game.ServerScriptService
end

local globalPetAttackFloat = game.ServerScriptService:FindFirstChild("globalPetAttackFloat")
if not globalPetAttackFloat then
    globalPetAttackFloat = Instance.new("NumberValue")
    globalPetAttackFloat.Name = "globalPetAttackFloat"
    globalPetAttackFloat.Value = 0
    globalPetAttackFloat.Parent = game.ServerScriptService
end

-- Constants
local PET_CIRCLE_RADIUS = 8
local FOLLOW_SPACING = 4 -- studs between control boxes in a chain

-- Utility functions from original
function GetPointOnCircle(CircleRadius, Degrees)
    return Vector3.new(math.cos(math.rad(Degrees)) * CircleRadius, 1, math.sin(math.rad(Degrees)) * CircleRadius)
end

function GetFolderFromPetID(Player, PetID)
    local inventoryFolder = Player:FindFirstChild("Inventory")
    if not inventoryFolder then return nil end
    
    local petsFolder = inventoryFolder:FindFirstChild("pets")
    if not petsFolder then return nil end
    
    for _, petFolder in pairs(petsFolder:GetChildren()) do
        if petFolder:IsA("Folder") then
            local petIdValue = petFolder:FindFirstChild("PetID")
            if petIdValue and petIdValue.Value == PetID then
                return petFolder
            end
        end
    end
    return nil
end

-- Case-insensitive part finder
local function findByNameCI(root, target)
    target = string.lower(target)
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") and string.lower(d.Name) == target then
            return d
        end
    end
    return nil
end

-- Geometry logger for troubleshooting model offsets across lifecycle
local function logModelGeometry(stage, model)
    if not model or not model:IsA("Model") then return end
    local cf, size = model:GetBoundingBox()
    print("🧭 PET GEOM", stage, model.Name, "parent=", model.Parent and model.Parent:GetFullName() or "nil",
        "center=("..string.format("%.2f,%.2f,%.2f", cf.Position.X, cf.Position.Y, cf.Position.Z)..")",
        "size=("..string.format("%.2f,%.2f,%.2f", size.X, size.Y, size.Z)..")")
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            print(string.format("   • %s pos=(%.2f,%.2f,%.2f) anchored=%s",
                d:GetFullName(), d.Position.X, d.Position.Y, d.Position.Z, tostring(d.Anchored)))
        end
    end
end

-- Ensure all BaseParts are welded to the model's PrimaryPart
local function ensureWeldsToPrimary(model)
    if not model or not model:IsA("Model") or not model.PrimaryPart then return 0 end
    local primary = model.PrimaryPart
    local created = 0
    local function hasDirectWeld(a, b)
        for _, d in ipairs(primary:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                local p0, p1 = d.Part0, d.Part1
                if (p0 == primary and p1 == b) or (p1 == primary and p0 == b) then
                    return true
                end
            end
        end
        -- Also check on the other part in case welds were parented there
        for _, d in ipairs(b:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                local p0, p1 = d.Part0, d.Part1
                if (p0 == primary and p1 == b) or (p1 == primary and p0 == b) then
                    return true
                end
            end
        end
        return false
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d ~= primary then
            if not hasDirectWeld(primary, d) then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = primary
                weld.Part1 = d
                weld.Parent = primary
                created += 1
            end
            d.Anchored = false
            d.CanCollide = false
        end
    end
    primary.Anchored = false
    primary.CanCollide = false
    return created
end

-- Debug loop removed now that falling has been ruled out

-- Create control box components (pet models now come complete from AssetPreloadService)
function createPetSetupComponents()
    local components = {}
    
    -- PetBox (control part)
    components.PetBox = Instance.new("Part")
    components.PetBox.Name = "PetBox"
    components.PetBox.Size = Vector3.new(1, 1, 1)
    components.PetBox.Material = Enum.Material.Neon
    components.PetBox.BrickColor = BrickColor.new("Really blue")
    components.PetBox.Anchored = true
    components.PetBox.CanCollide = false
    components.PetBox.Transparency = 1 -- Make invisible
    
    -- CRITICAL: Add Pet attachment for AlignPosition to work
    local petAttachment = Instance.new("Attachment")
    petAttachment.Name = "Pet"
    petAttachment.Parent = components.PetBox
    
    return components
end

-- Scripts are now handled directly in the pet setup process

-- Main loadEquipped function (adapted from original)
function loadEquipped(Player)
    print("🔄 PetHandler: Loading equipped pets for", Player.Name)
    
    -- Wait for assets to finish loading if they haven't already
    if not _G.AssetsLoadingComplete then
        print("⏳ PetHandler: Waiting for asset loading to complete...")
        _G.AssetsLoadedEvent.Event:Wait()
        print("✅ PetHandler: Assets loaded, proceeding with pet spawn")
    end
    
    -- Create player folders if they don't exist
    local petLocation = workspace.PlayerPetControl:FindFirstChild(Player.Name)
    if not petLocation then
        petLocation = Instance.new("Folder")
        petLocation.Name = Player.Name
        petLocation.Parent = workspace.PlayerPetControl
    end
    
    local petModelsLocation = workspace.PlayerPets:FindFirstChild(Player.Name)
    if not petModelsLocation then
        petModelsLocation = Instance.new("Folder")
        petModelsLocation.Name = Player.Name
        petModelsLocation.Parent = workspace.PlayerPets
    end
    
    -- Clear existing boxes
    for _, box in pairs(petLocation:GetChildren()) do
        box:Destroy()
    end
    
    -- Get equipped pets (those with Equipped.Value = true)
    local CurrentlyEquipped = {}
    local inventoryFolder = Player:FindFirstChild("Inventory")
    if not inventoryFolder then
        warn("PetHandler: No Inventory folder found for", Player.Name)
        return "Error"
    end
    
    local petsFolder = inventoryFolder:FindFirstChild("pets")
    if not petsFolder then
        warn("PetHandler: No pets folder found in Inventory for", Player.Name)
        return "Error"
    end
    
    for _, petFolder in pairs(petsFolder:GetChildren()) do
        if petFolder:IsA("Folder") then
            local equippedValue = petFolder:FindFirstChild("Equipped")
            if equippedValue and equippedValue:IsA("BoolValue") and equippedValue.Value then
                table.insert(CurrentlyEquipped, petFolder)
            else
                -- Destroy unequipped pet models
                for _, part in pairs(petModelsLocation:GetChildren()) do
                    local petIdValue = part:FindFirstChild("PetID")
                    if petIdValue then
                        local petId = petFolder:FindFirstChild("PetID")
                        if petId and petIdValue.Value == petId.Value then
                            part:Destroy()
                        end
                    end
                end
            end
        end
    end
    
    print("🎯 PetHandler: Found", #CurrentlyEquipped, "equipped pets for", Player.Name)
    
    -- Create pets
    local Increment = 360 / math.max(#CurrentlyEquipped, 1)
    local skip = math.floor(36 / math.max(#CurrentlyEquipped, 1))
    if skip < 1 then skip = 1 end
    
    for i, petFolder in pairs(CurrentlyEquipped) do
        -- Create control box with ALL required components
        local components = createPetSetupComponents()
        local box = components.PetBox:Clone()
        box.Name = tostring(i)
        box.Anchored = false  -- Unanchor the control box so we can set network ownership
        
        -- Add Center attachment to the control box
        local centerAttachment = Instance.new("Attachment")
        centerAttachment.Name = "Center"
        centerAttachment.Parent = box
        
        -- Add AlignPosition to the control box
        local alignPosition = Instance.new("AlignPosition")
        alignPosition.Name = "AlignPosition"
        alignPosition.Parent = box
        
        -- Add AlignOrientation to the control box
        local alignOrientation = Instance.new("AlignOrientation")
        alignOrientation.Name = "AlignOrientation"
        alignOrientation.Parent = box
        
        -- Add Back attachment to the control box (for chaining)
        local backAttachment = Instance.new("Attachment")
        backAttachment.Name = "Back"
        -- Positive Z is behind the character (Roblox forward is -Z),
        -- so place subsequent pets further behind the previous box
        backAttachment.Position = Vector3.new(0, 0, FOLLOW_SPACING)
        backAttachment.Parent = box
        
        box.Parent = petLocation
        box:SetNetworkOwner(Player)
        
        -- DEBUG: Check if control box has required components
        print("🔍 DEBUG PetHandler: Control box", box.Name, "for pet", i)
        print("  - Box has Center attachment:", box:FindFirstChild("Center") ~= nil)
        print("  - Box has AlignPosition:", box:FindFirstChild("AlignPosition") ~= nil)
        print("  - Box has AlignOrientation:", box:FindFirstChild("AlignOrientation") ~= nil)
        print("  - Box has FollowBox script:", box:FindFirstChild("FollowBox") ~= nil)
        print("  - Box has Pet attachment:", box:FindFirstChild("Pet") ~= nil)
        print("  - Box has Back attachment:", box:FindFirstChild("Back") ~= nil)
        
        -- Ensure compatibility folder that Follow script clones from exists at
        -- ServerScriptService.PetHandler.PetSetup (matches original game's path)
        local sss = game.ServerScriptService
        local petHandlerFolder = sss:FindFirstChild("PetHandler")
        if not petHandlerFolder then
            petHandlerFolder = Instance.new("Folder")
            petHandlerFolder.Name = "PetHandler"
            petHandlerFolder.Parent = sss
        end
        local petSetup = petHandlerFolder:FindFirstChild("PetSetup")
        if not petSetup then
            petSetup = Instance.new("Folder")
            petSetup.Name = "PetSetup"
            petSetup.Parent = petHandlerFolder
        end
        -- Only the physics movers are required in this template; values live on the pet model
        if not petSetup:FindFirstChild("BodyGyro") then
            local bodyGyro = Instance.new("BodyGyro")
            bodyGyro.Name = "BodyGyro"
            bodyGyro.Parent = petSetup
        end
        if not petSetup:FindFirstChild("BodyPosition") then
            local bodyPosition = Instance.new("BodyPosition")
            bodyPosition.Name = "BodyPosition"
            bodyPosition.Parent = petSetup
        end
        
        -- Pet system will be built AFTER the pet model is created
        
        -- Ensure our pet folder has the numeric PetID that the original game expects
        local petId = petFolder:FindFirstChild("PetID")
        if not petId then
            -- Create the missing PetID NumberValue
            petId = Instance.new("NumberValue")
            petId.Name = "PetID"
            -- Generate unique numeric ID from UUID hash
            local uuid = petFolder.Name
            local hash = 0
            for i = 1, #uuid do
                hash = (hash * 31 + string.byte(uuid, i)) % 2147483647
            end
            petId.Value = hash
            petId.Parent = petFolder
            print("✅ PetHandler: Created missing PetID", hash, "for", petFolder.Name)
        end
        
        -- Remove existing pet model if it exists
        if petId then
            for _, part in pairs(petModelsLocation:GetChildren()) do
                local existingPetId = part:FindFirstChild("PetID")
                if existingPetId and existingPetId.Value == petId.Value then
                    part:Destroy()
                end
            end
        end
        
        -- Load the REAL pet model from ReplicatedStorage.Assets
        -- Extract base pet name from folder name (remove UID suffix)
        local fullPetName = petFolder.Name
        local basePetName = fullPetName:match("^([^_]+)") or fullPetName -- Get everything before first underscore
        local petType = petFolder:FindFirstChild("Type")
        local petTypeValue = petType and petType.Value or "basic"
        
        print("🐾 PetHandler: Loading REAL pet model", basePetName, "variant", petTypeValue, "(from folder:", fullPetName, ")")
        
        -- Get the pet model from ReplicatedStorage.Assets.Models.Pets
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        local PetModel = nil
        
        if assetsFolder then
            local modelsFolder = assetsFolder:FindFirstChild("Models")
            if modelsFolder then
                local petsFolder = modelsFolder:FindFirstChild("Pets")
                if petsFolder then
                    local petTypeFolder = petsFolder:FindFirstChild(basePetName)
                    if petTypeFolder then
                        local petVariantModel = petTypeFolder:FindFirstChild(petTypeValue)
                        if petVariantModel then
                            -- Log geometry straight from ReplicatedStorage before we touch it
                            logModelGeometry("PRE_CLONE_RS", petVariantModel)
                            -- Count existing welds
                            do
                                local welds = 0
                                for _, d in ipairs(petVariantModel:GetDescendants()) do
                                    if d:IsA("WeldConstraint") then welds += 1 end
                                end
                                print("   • RS welds:", welds)
                            end
                            PetModel = petVariantModel:Clone()
                            -- Log geometry immediately after clone, before any changes
                            logModelGeometry("POST_CLONE_PREPARENT", PetModel)
                            do
                                local welds = 0
                                for _, d in ipairs(PetModel:GetDescendants()) do
                                    if d:IsA("WeldConstraint") then welds += 1 end
                                end
                                print("   • Clone welds:", welds)
                            end
                            print("✅ PetHandler: Successfully cloned REAL pet model", basePetName, petTypeValue)
                        end
                    end
                end
            end
        end
        
        -- ERROR if model not found - don't hide this with fallbacks!
        if not PetModel then
            error("❌ PetHandler: CRITICAL ERROR - Could not find pet model for " .. basePetName .. " variant " .. petTypeValue .. 
                  " at path ReplicatedStorage.Assets.Models.Pets." .. basePetName .. "." .. petTypeValue)
        end
        
        -- Ensure the model has a sensible PrimaryPart (prefer Face/Head)
        if not PetModel.PrimaryPart then
            local candidate
            for _, child in pairs(PetModel:GetDescendants()) do
                if child:IsA("BasePart") then
                    local n = string.lower(child.Name)
                    if string.find(n, "face") or string.find(n, "head") then
                        candidate = child
                        break
                    end
                    candidate = candidate or child
                end
            end
            PetModel.PrimaryPart = candidate
        end

        -- DEBUG: print part sample positions before any runtime weld changes
        do
            local function partByName(n)
                for _, d in ipairs(PetModel:GetDescendants()) do
                    if d:IsA("BasePart") and string.lower(d.Name) == string.lower(n) then
                        return d
                    end
                end
            end
            local face = partByName("Face")
            local base = partByName("Base")
            local outline = partByName("Outline")
            local function fmt(p)
                if not p then return "nil" end
                return string.format("(%.2f,%.2f,%.2f)", p.Position.X, p.Position.Y, p.Position.Z)
            end
            print("🧪 PET PRE-CLONE POS SAMPLE", PetModel.Name, "primary=", PetModel.PrimaryPart and PetModel.PrimaryPart.Name or "nil", "face=", fmt(face), "base=", fmt(base), "outline=", fmt(outline))
        end
        
        -- Ensure welds exist and physics properties are correct
        local createdWelds = ensureWeldsToPrimary(PetModel)
        print("🔗 PetHandler: Physics prepared for", basePetName, "(welds created:", createdWelds, ")")
        
        -- Pet model already has all components from AssetPreloadService
        print("🔨 PetHandler: Setting up pet system for", basePetName)
        
        -- Replace the placeholder Follow script with the real one
        local placeholderFollow = PetModel:FindFirstChild("Follow")
        if placeholderFollow then
            placeholderFollow:Destroy()
        end
        
        local followScript = game.ServerScriptService.Server.Services.PetScripts.Follow:Clone()
        followScript.Parent = PetModel
        
        -- Add FollowBox script to control box
        local followBoxScript = game.ServerScriptService.Server.Services.PetScripts.FollowBox:Clone()
        followBoxScript.Parent = box
        
        -- Connect pet model to control box via AlignPosition (strong settings)
        if PetModel.PrimaryPart and PetModel.PrimaryPart:FindFirstChild("attachmentPet") then
            local petAlignPosition = Instance.new("AlignPosition")
            petAlignPosition.Name = "PetAlignPosition"
            petAlignPosition.MaxForce = 1e12
            petAlignPosition.Responsiveness = 75
            petAlignPosition.RigidityEnabled = true
            petAlignPosition.Attachment0 = PetModel.PrimaryPart.attachmentPet
            petAlignPosition.Attachment1 = box.Pet
            petAlignPosition.Parent = PetModel.PrimaryPart
        end
        
        -- Set pet properties (values already exist from AssetPreloadService)
        PetModel.PositionNumber.Value = i
        PetModel.AttackPos.Value = "Pos" .. tostring((i * skip) % 36)
        PetModel.Pos.Value = GetPointOnCircle(PET_CIRCLE_RADIUS, Increment * i)
        PetModel.PetID.Value = petId.Value
        
        -- Position whole model (not just PrimaryPart) before parenting
        if PetModel.PrimaryPart then
            local targetPos
            if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                targetPos = Player.Character.HumanoidRootPart.Position + Vector3.new(0, 5, 0)
            else
                targetPos = box.Position
            end
            PetModel:PivotTo(CFrame.new(targetPos))
            logModelGeometry("POST_PIVOT_PREPARENT", PetModel)
        end
        
        print("✅ PetHandler: Pet system set up for", basePetName)
        
        -- DEBUG: Check if pet model has required components
        print("🔍 DEBUG PetHandler: Pet model", PetModel.Name)
        print("  - Pet has PrimaryPart:", PetModel.PrimaryPart ~= nil)
        print("  - Pet has PetSetup:", PetModel:FindFirstChild("PetSetup") ~= nil)
        print("  - Pet has Follow script:", PetModel:FindFirstChild("Follow") ~= nil)
        if PetModel.PrimaryPart then
            print("  - PrimaryPart anchored:", PetModel.PrimaryPart.Anchored)
            print("  - PrimaryPart can collide:", PetModel.PrimaryPart.CanCollide)
        end
        
        -- Set timer value if it exists
        local timerValue = petFolder:FindFirstChild("Timer")
        if timerValue then
            PetModel.Timer.Value = timerValue.Value
        end
        
        -- Enable the Follow script
        local followScript = PetModel:FindFirstChild("Follow")
        if followScript then
            followScript.Disabled = false
        end
        
        -- NOW parent everything to workspace (AFTER everything is built)
        PetModel.Parent = petModelsLocation
        box.Parent = petLocation
        
        -- Immediate spawn position log (full geometry after parent). Physics settles next frame; sample again shortly.
        logModelGeometry("POST_PARENT", PetModel)
        do
            local capturedModel = PetModel
            task.defer(function()
                task.wait()
                if capturedModel and capturedModel.Parent then
                    logModelGeometry("POST_PARENT_AFTER_STEP", capturedModel)
                end
            end)
        end

        -- Set network ownership (must be in workspace first)
        if PetModel.PrimaryPart then
            PetModel.PrimaryPart:SetNetworkOwner(Player)
        end
        box:SetNetworkOwner(Player)
        
        PetModel.Refresh.Value = true
        
        print("✅ PetHandler: Created REAL pet", i, "for", Player.Name, "at", PetModel.PrimaryPart and PetModel.PrimaryPart.Position or "unknown position")
    end
    
    print("🎉 PetHandler: loadEquipped completed for", Player.Name)
    return "Success"
end

-- Register with the bridge (wait for it to be available)
local function registerWithBridge()
    if _G.SetPetLoadEquippedFunction then
        _G.SetPetLoadEquippedFunction(loadEquipped)
        print("✅ PetHandler: Registered with PetEquipmentBridge")
    else
        task.wait(0.1)
        registerWithBridge()
    end
end
registerWithBridge()

-- Handle player joining
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- Create player folders
        local petFolder = workspace.PlayerPets:FindFirstChild(player.Name)
        if not petFolder then
            petFolder = Instance.new("Folder")
            petFolder.Name = player.Name
            petFolder.Parent = workspace.PlayerPets
        end
        
        local controlFolder = workspace.PlayerPetControl:FindFirstChild(player.Name)
        if not controlFolder then
            controlFolder = Instance.new("Folder")
            controlFolder.Name = player.Name
            controlFolder.Parent = workspace.PlayerPetControl
        end
        
        -- Load equipped pets after a brief delay
        task.wait(2)
        loadEquipped(player)
    end)
end)

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
    local petFolder = workspace.PlayerPets:FindFirstChild(player.Name)
    if petFolder then
        petFolder:Destroy()
    end
    
    local controlFolder = workspace.PlayerPetControl:FindFirstChild(player.Name)
    if controlFolder then
        controlFolder:Destroy()
    end
end)

-- Create position values for pet movement (EXACT COPY from original)
for i = 36, 0, -1 do
    local inst = Instance.new("Vector3Value")
    inst.Name = "Pos" .. tostring(i)
    inst.Parent = script.Parent
end

for i = 36, 0, -1 do
    local inst = Instance.new("Vector3Value")
    inst.Name = "Attach" .. tostring(i)
    local Increment = 360 / 36
    inst.Value = GetPointOnCircle(PET_CIRCLE_RADIUS, (Increment * i))
    inst.Parent = script.Parent
end

-- Global pet float animation (adapted from original)
local maxFloat = 0.75
local floatInc = 0.035
local sw = false
local fl = 0

task.spawn(function()
    while true do
        task.wait(0.05)
        if not sw then
            fl = fl + floatInc
            if fl >= maxFloat then
                sw = true
            end
        else
            fl = fl - floatInc
            if fl <= -maxFloat then
                sw = false
            end
        end
        globalPetFloat.Value = fl
    end
end)

-- Global pet attack float animation
local maxFloatA = 0.25
local floatIncA = 0.25
local swA = false
local flA = 0

task.spawn(function()
    while true do
        task.wait(0.05)
        if not swA then
            flA = flA + floatIncA
            if flA >= maxFloatA then
                swA = true
            end
        else
            flA = flA - floatIncA
            if flA <= -maxFloatA then
                swA = false
            end
        end
        globalPetAttackFloat.Value = flA
    end
end)

-- EXACT COPY: Position rotation system from original
local loop = 0
local posShift = Instance.new("NumberValue")
posShift.Name = "posShift"
posShift.Parent = game.Workspace

coroutine.resume(coroutine.create(function()
    while true do
        task.wait(0.05)
        if loop == 360 then
            loop = 0
        end
        loop = loop + 2
        local Increment = 360 / 36
        for i = 36, 0, -1 do
            local name = "Pos" .. tostring(i)
            local posValue = script.Parent:FindFirstChild(name)
            if posValue then
                posValue.Value = GetPointOnCircle(PET_CIRCLE_RADIUS, (Increment * i) + loop)
            end
        end
    end
end))

coroutine.resume(coroutine.create(function()
    local looper = 1
    while task.wait(.2) do
        looper = looper + 1
        if looper > 36 then
            looper = 1
        end
        posShift.Value = looper
    end
end))

print("🎮 PetHandler: Server script initialized with REAL pet model loading!")