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
print("✅ PetHandler: Loaded and waiting for bridge registration")

-- Suppress verbose debug prints in this script unless explicitly enabled
local __RAW_PRINT = print
local __PRINT_ENABLED = false -- default silent; toggle for debugging
local function print(...)
    if __PRINT_ENABLED then
        __RAW_PRINT(...)
    end
end
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")

-- Prevent concurrent loadEquipped runs per-player (which can destroy freshly spawned models)
local activeLoads: {[Player]: boolean} = {}

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

-- TEMPORARY: Model override to help debug missing/vanishing pets
-- When enabled, certain pet IDs will be swapped to known-good models.
local TEMP_MODEL_OVERRIDE_ENABLED = false
local TEMP_MODEL_OVERRIDES = {
    dragon = "bunny", -- map dragon -> bunny
}

-- Diagnostics options for comparing suspect pets against a known good reference
local DIAGNOSTICS_ENABLED = false
local DIAG_REFERENCE_ID = "bunny"
local DIAG_REFERENCE_VARIANT = "basic"
local STABILITY_WATCH_ENABLED = false
local STABILITY_WATCH_DURATION_SEC = 2.0

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

-- Collect detailed model diagnostics for comparison
local function collectModelDiagnostics(model)
    if not model or not model:IsA("Model") then return { valid = false } end
    local primary = model.PrimaryPart
    local stats = {
        valid = true,
        name = model.Name,
        primaryPart = primary and primary.Name or nil,
        totalParts = 0,
        anchoredParts = 0,
        canCollideParts = 0,
        weldConstraints = 0,
        alignPositions = 0,
        alignOrientations = 0,
        bodyMovers = 0,
        attachments = 0,
        partsWithoutDirectWeldToPrimary = 0,
        extremeOffsets = {}, -- list of {part, distance}
        maxOffset = 0,
    }
    local primaryPos = primary and primary.Position or (model:GetPivot().Position)
    local function hasDirectWeldToPrimary(p)
        if not primary or not p or p == primary then return true end
        for _, d in ipairs(primary:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                if (d.Part0 == primary and d.Part1 == p) or (d.Part1 == primary and d.Part0 == p) then
                    return true
                end
            end
        end
        for _, d in ipairs(p:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                if (d.Part0 == primary and d.Part1 == p) or (d.Part1 == primary and d.Part0 == p) then
                    return true
                end
            end
        end
        return false
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            stats.totalParts += 1
            if d.Anchored then stats.anchoredParts += 1 end
            if d.CanCollide then stats.canCollideParts += 1 end
            if primaryPos then
                local dist = (d.Position - primaryPos).Magnitude
                if dist > stats.maxOffset then stats.maxOffset = dist end
                if dist > 150 then
                    table.insert(stats.extremeOffsets, { part = d:GetFullName(), distance = dist })
                end
            end
            if not hasDirectWeldToPrimary(d) then
                stats.partsWithoutDirectWeldToPrimary += 1
            end
        elseif d:IsA("WeldConstraint") then
            stats.weldConstraints += 1
        elseif d:IsA("AlignPosition") then
            stats.alignPositions += 1
        elseif d:IsA("AlignOrientation") then
            stats.alignOrientations += 1
        elseif d:IsA("Attachment") then
            stats.attachments += 1
        elseif d:IsA("BodyMover") or d:IsA("BodyGyro") or d:IsA("BodyPosition") or d:IsA("BodyVelocity") then
            stats.bodyMovers += 1
        end
    end
    local cf, size = model:GetBoundingBox()
    stats.boundingCenter = cf.Position
    stats.boundingSize = size
    return stats
end

local function printDiagnostics(tag, stats)
    if not stats or not stats.valid then
        print("🔎 DIAG", tag, "invalid model")
        return
    end
    print(string.format(
        "🔎 DIAG %s %s prim=%s parts=%d anchored=%d collide=%d welds=%d alignP=%d alignO=%d bodyMovers=%d attach=%d maxOffset=%.1f bbox=(%.1f,%.1f,%.1f)",
        tag,
        tostring(stats.name),
        tostring(stats.primaryPart),
        stats.totalParts,
        stats.anchoredParts,
        stats.canCollideParts,
        stats.weldConstraints,
        stats.alignPositions,
        stats.alignOrientations,
        stats.bodyMovers,
        stats.attachments,
        stats.maxOffset,
        stats.boundingSize.X, stats.boundingSize.Y, stats.boundingSize.Z
    ))
    if stats.partsWithoutDirectWeldToPrimary > 0 then
        print("   • partsWithoutDirectWeldToPrimary=", stats.partsWithoutDirectWeldToPrimary)
    end
    if #stats.extremeOffsets > 0 then
        print("   • extremeOffsets (top 5):")
        for i = 1, math.min(5, #stats.extremeOffsets) do
            local e = stats.extremeOffsets[i]
            print(string.format("     - %s dist=%.1f", e.part, e.distance))
        end
    end
end

local function compareDiagnostics(refStats, suspectStats)
    if not refStats or not refStats.valid or not suspectStats or not suspectStats.valid then return end
    print("🧪 DIAG COMPARE:")
    local function diff(label, a, b)
        if a ~= b then
            print(string.format("   %s: ref=%s vs suspect=%s", label, tostring(a), tostring(b)))
        end
    end
    diff("totalParts", refStats.totalParts, suspectStats.totalParts)
    diff("anchoredParts", refStats.anchoredParts, suspectStats.anchoredParts)
    diff("canCollideParts", refStats.canCollideParts, suspectStats.canCollideParts)
    diff("weldConstraints", refStats.weldConstraints, suspectStats.weldConstraints)
    diff("partsWithoutDirectWeldToPrimary", refStats.partsWithoutDirectWeldToPrimary, suspectStats.partsWithoutDirectWeldToPrimary)
    if math.abs(refStats.maxOffset - suspectStats.maxOffset) > 5 then
        print(string.format("   maxOffset: ref=%.1f vs suspect=%.1f", refStats.maxOffset, suspectStats.maxOffset))
    end
    local function sz(s) return string.format("(%.1f,%.1f,%.1f)", s.X, s.Y, s.Z) end
    if (refStats.boundingSize - suspectStats.boundingSize).Magnitude > 5 then
        print("   boundingSize:", sz(refStats.boundingSize), "vs", sz(suspectStats.boundingSize))
    end
end

-- Watch for weld/anchor/offset changes shortly after parenting to catch transient issues
local function watchModelStability(model, tag)
    if not STABILITY_WATCH_ENABLED or not model or not model.PrimaryPart then return end
    local startTime = os.clock()
    local last = {
        welds = 0,
        anchored = 0,
        collide = 0,
        maxOffset = 0,
    }
    local primary = model.PrimaryPart
    local function snapshot()
        local welds, anchored, collide = 0, 0, 0
        local primaryPos = primary.Position
        local maxOffset = 0
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("WeldConstraint") then welds += 1 end
            if d:IsA("BasePart") then
                if d.Anchored then anchored += 1 end
                if d.CanCollide then collide += 1 end
                local dist = (d.Position - primaryPos).Magnitude
                if dist > maxOffset then maxOffset = dist end
            end
        end
        return welds, anchored, collide, maxOffset
    end
    local function maybeLog()
        local w, a, c, m = snapshot()
        if w ~= last.welds or a ~= last.anchored or c ~= last.collide or math.abs(m - last.maxOffset) > 0.5 then
            print(string.format("🧷 DIAG STABILITY %s t=%.2f welds=%d anchored=%d collide=%d maxOffset=%.1f owner=%s",
                tag, os.clock() - startTime, w, a, c, m,
                tostring((pcall(function() return game:GetService('Players'):GetPlayerFromCharacter(primary:GetNetworkOwner()) end)) and primary:GetNetworkOwner() and primary:GetNetworkOwner().Name or "nil")))
            last.welds, last.anchored, last.collide, last.maxOffset = w, a, c, m
        end
    end
    -- Initial
    last.welds, last.anchored, last.collide, last.maxOffset = snapshot()
    print(string.format("🧷 DIAG STABILITY %s t=%.2f welds=%d anchored=%d collide=%d maxOffset=%.1f (start)", tag, 0, last.welds, last.anchored, last.collide, last.maxOffset))
    -- DescendantRemoving hook to catch weld deletions
    local remConn = model.DescendantRemoving:Connect(function(inst)
        if inst:IsA("WeldConstraint") then
            print("⚠️ DIAG", tag, "weld removed:", inst:GetFullName())
        end
    end)
    -- Sample loop
    task.spawn(function()
        while os.clock() - startTime < STABILITY_WATCH_DURATION_SEC and model.Parent do
            task.wait(0.1)
            maybeLog()
        end
        if remConn.Connected then remConn:Disconnect() end
        local w, a, c, m = snapshot()
        print(string.format("🧷 DIAG STABILITY %s t=%.2f welds=%d anchored=%d collide=%d maxOffset=%.1f (end)", tag, os.clock() - startTime, w, a, c, m))
    end)
end

-- Extract logical pet identifier and variant from an equipped pet folder
-- Prefers explicit `ItemId` and `Variant` values set by the bridge, and
-- falls back to parsing folders named like `equip_<id>:<variant>`.
local function extractIdAndVariantFromFolder(petFolder)
    local idValue = petFolder:FindFirstChild("ItemId")
    local variantValue = petFolder:FindFirstChild("Variant") or petFolder:FindFirstChild("variant")
    local petIdName = idValue and idValue.Value or nil
    local petVariantName = variantValue and variantValue.Value or nil

    if not petIdName or not petVariantName then
        local name = petFolder.Name
        local parsedId, parsedVariant = name:match("^equip_([^:]+):(.+)$")
        if parsedId then
            petIdName = petIdName or parsedId
            petVariantName = petVariantName or parsedVariant
        end
    end

    return petIdName, petVariantName
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
            -- Leave anchoring as-is until Follow binds constraints
            d.CanCollide = false
        end
    end
    -- Keep PrimaryPart anchored until Follow binds constraints
    primary.CanCollide = false
    return created
end

-- Set all BaseParts to Massless and zero out velocities (apply before parenting)
local function forceMasslessAndZeroVelocity(model)
    if not model or not model:IsA("Model") then return end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Massless = true
            d.AssemblyLinearVelocity = Vector3.new()
            d.AssemblyAngularVelocity = Vector3.new()
        end
    end
end

-- Remove any physics movers or stray constraints inside the asset model that can fight our Aligns
local function sanitizeModelConstraints(model)
    if not model or not model:IsA("Model") then return end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("AlignPosition") or d:IsA("AlignOrientation")
            or d:IsA("BodyMover") or d:IsA("BodyForce") or d:IsA("BodyGyro")
            or d:IsA("BodyPosition") or d:IsA("BodyVelocity")
            or d:IsA("LinearVelocity") or d:IsA("AngularVelocity")
            or (d:IsA("Constraint") and not d:IsA("WeldConstraint"))
        then
            d:Destroy()
        elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
            d:Destroy()
        elseif d:IsA("Weld") or d:IsA("Motor6D") then
            local p0 = d.Part0 or d.Part1
            local p1 = d.Part1 or d.Part0
            if typeof(p0) == "Instance" and typeof(p1) == "Instance" and p0:IsA("BasePart") and p1:IsA("BasePart") then
                local wc = Instance.new("WeldConstraint")
                wc.Part0 = p0
                wc.Part1 = p1
                wc.Parent = p0
            end
            d:Destroy()
        end
    end
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
    -- Cross-script/process lock using a BoolValue on the Player
    local inProgress = Player:FindFirstChild("__PetLoadInProgress")
    if inProgress and inProgress.Value then
        print("⏭️ PetHandler: loadEquipped already running for", Player.Name, "- skipping")
        return "Skipped"
    end
    if not inProgress then
        inProgress = Instance.new("BoolValue")
        inProgress.Name = "__PetLoadInProgress"
        inProgress.Value = false
        inProgress.Parent = Player
    end
    inProgress.Value = true
    -- Local guard as a fallback
    if activeLoads[Player] then
        print("⏭️ PetHandler: loadEquipped (local) already running for", Player.Name, "- skipping")
        inProgress.Value = false
        return "Skipped"
    end
    activeLoads[Player] = true
    local function cleanup()
        activeLoads[Player] = nil
        if inProgress then inProgress.Value = false end
    end
    local ok, result = pcall(function()
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
        -- Clear existing spawned pet models to avoid de-dup by PetID collisions across stack instances
        for _, model in pairs(petModelsLocation:GetChildren()) do
            if model:IsA("Model") then
                model:Destroy()
            end
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
    
    local function considerFolder(folder)
        if not folder or not folder:IsA("Folder") then return end
        local name = folder.Name or ""
        local equippedValue = folder:FindFirstChild("Equipped")
        -- Treat explicit Equipped=true OR ephemeral equip_<id> folders as equipped sources
        if (equippedValue and equippedValue:IsA("BoolValue") and equippedValue.Value)
            or (string.sub(name, 1, 6) == "equip_") then
            table.insert(CurrentlyEquipped, folder)
        else
            -- Do not destroy here; unique pets may be equipped via ephemeral equip_ folders.
            -- Cleanup of prior instances happens per-PetID before spawning below.
        end
    end

    for _, child in pairs(petsFolder:GetChildren()) do
        if child:IsA("Folder") then
            if child.Name == "Special" then
                for _, specialFolder in ipairs(child:GetChildren()) do
                    considerFolder(specialFolder)
                end
            else
                considerFolder(child)
            end
        end
    end
    
    -- Mirror legacy side-effect for UI/metrics
    local currentEquipValue = Player:FindFirstChild("CurrentEquip")
    if currentEquipValue then
        currentEquipValue.Value = #CurrentlyEquipped
    end
    print("🎯 PetHandler: Found", #CurrentlyEquipped, "equipped pets for", Player.Name)
    for _, pf in ipairs(CurrentlyEquipped) do
        local id = pf:FindFirstChild("ItemId") and pf.ItemId.Value or pf.Name
        local variant = pf:FindFirstChild("Variant") and pf.Variant.Value or "?"
        print("  • Equipped ->", pf.Name, "id=", id, "variant=", variant)
    end
    
    -- Create pets
    local Increment = 360 / math.max(#CurrentlyEquipped, 1)
    local skip = math.floor(36 / math.max(#CurrentlyEquipped, 1))
    if skip < 1 then skip = 1 end
    
    for i, petFolder in pairs(CurrentlyEquipped) do
        -- Create control box with ALL required components
        local components = createPetSetupComponents()
        local box = components.PetBox:Clone()
        box.Name = tostring(i)
        box.Anchored = true  -- Anchor during setup to prevent initial fall
        
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
        -- Defer network ownership until box is unanchored later in setup
        
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
        
        -- No per-PetID de-duplication here; we cleared the folder above to support multiple stack instances
        
        -- Load the REAL pet model from ReplicatedStorage.Assets
        -- Determine pet id and variant from explicit values or equip_ naming
        local petIdName, petVariantName = extractIdAndVariantFromFolder(petFolder)
        if not petIdName then
            -- Legacy fallback: try using the folder name directly (pre-mixed system)
            petIdName = petFolder.Name:match("^([^_]+)") or petFolder.Name
        end
        if not petVariantName then
            local petType = petFolder:FindFirstChild("Type")
            petVariantName = (petType and petType.Value) or "basic"
        end

        -- Apply temporary override if enabled
        local effectiveIdName = petIdName
        local effectiveVariantName = petVariantName
        if TEMP_MODEL_OVERRIDE_ENABLED and effectiveIdName and TEMP_MODEL_OVERRIDES[string.lower(effectiveIdName)] then
            local target = TEMP_MODEL_OVERRIDES[string.lower(effectiveIdName)]
            print("🧪 TEMP OVERRIDE: Swapping pet id", effectiveIdName, "->", target, "(variant:", effectiveVariantName, ")")
            effectiveIdName = target
        end

        print("🐾 PetHandler: Loading REAL pet model", effectiveIdName, "variant", effectiveVariantName, "(from folder:", petFolder.Name, ")")
        
        -- Get the pet model from ReplicatedStorage.Assets.Models.Pets
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        local PetModel = nil
        
        if assetsFolder then
            local modelsFolder = assetsFolder:FindFirstChild("Models")
            if modelsFolder then
                local petsFolder = modelsFolder:FindFirstChild("Pets")
                if petsFolder then
                    local petTypeFolder = petsFolder:FindFirstChild(effectiveIdName)
                    if petTypeFolder then
                        local petVariantModel = petTypeFolder:FindFirstChild(effectiveVariantName)
                        -- Fallback to basic variant if requested one doesn't exist on overridden type
                        if not petVariantModel then
                            petVariantModel = petTypeFolder:FindFirstChild("basic")
                        end
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
                            if DIAGNOSTICS_ENABLED then
                                printDiagnostics("PRE_SANITIZE", collectModelDiagnostics(PetModel))
                                -- If suspect (e.g., dragon), compare to reference (bunny/basic) for a baseline
                                if string.lower(effectiveIdName) ~= string.lower(DIAG_REFERENCE_ID) then
                                    local refType = modelsFolder and modelsFolder:FindFirstChild("Pets") and modelsFolder.Pets:FindFirstChild(DIAG_REFERENCE_ID)
                                    local refModel = refType and refType:FindFirstChild(DIAG_REFERENCE_VARIANT)
                                    if refModel then
                                        printDiagnostics("REF_"..DIAG_REFERENCE_ID, collectModelDiagnostics(refModel))
                                        compareDiagnostics(collectModelDiagnostics(refModel), collectModelDiagnostics(PetModel))
                                    end
                                end
                            end
                            do
                                local welds = 0
                                for _, d in ipairs(PetModel:GetDescendants()) do
                                    if d:IsA("WeldConstraint") then welds += 1 end
                                end
                                print("   • Clone welds:", welds)
                            end
                            print("✅ PetHandler: Successfully cloned REAL pet model", petIdName, petVariantName)
                        end
                    end
                end
            end
        end
        
        -- ERROR if model not found - don't hide this with fallbacks!
        if not PetModel then
            error("❌ PetHandler: CRITICAL ERROR - Could not find pet model for " .. tostring(petIdName) .. " variant " .. tostring(petVariantName) .. 
                  " at path ReplicatedStorage.Assets.Models.Pets." .. tostring(petIdName) .. "." .. tostring(petVariantName))
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

        -- Validate required parts and add missing ones if necessary
        if not PetModel.PrimaryPart then
            error("❌ PetHandler: Pet model has no PrimaryPart after setup: " .. tostring(PetModel.Name))
        end
        -- Ensure attachmentPet exists on PrimaryPart for follow constraints
        if not PetModel.PrimaryPart:FindFirstChild("attachmentPet") then
            local ap = Instance.new("Attachment")
            ap.Name = "attachmentPet"
            ap.Parent = PetModel.PrimaryPart
        end
        -- Remove any non-weld constraints left and purge collision/anchored on all parts
        for _, bp in ipairs(PetModel:GetDescendants()) do
            if bp:IsA("BasePart") then
                -- Do not unanchor individual parts here; Follow will manage after attachments
                bp.CanCollide = false
            elseif bp:IsA("Constraint") and not bp:IsA("WeldConstraint") then
                bp:Destroy()
            end
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
        
        -- Rely on AssetPreloadService to deliver welded, cleaned models.
        -- Do minimal safety: make massless and zero velocities BEFORE parenting so physics won't explode
        forceMasslessAndZeroVelocity(PetModel)
        
        -- Pet model already has all components from AssetPreloadService
        print("🔨 PetHandler: Setting up pet system for", petIdName)
        
        -- Apply stats from asset model if present
        do
            local powerAttr = PetModel:GetAttribute("Power")
            local powerNV = PetModel:FindFirstChild("Power")
            if powerAttr and (not powerNV) then
                powerNV = Instance.new("NumberValue")
                powerNV.Name = "Power"
                powerNV.Value = powerAttr
                powerNV.Parent = PetModel
            end
        end

        -- Replace the placeholder Follow script with the real one
        local placeholderFollow = PetModel:FindFirstChild("Follow")
        if placeholderFollow then
            placeholderFollow:Destroy()
        end
        
        local followScript = game.ServerScriptService.Server.Services.PetScripts.Follow:Clone()
        followScript.Parent = PetModel
        -- Match legacy: enable Follow prior to parenting
        followScript.Disabled = false
        
        -- Add FollowBox script to control box
        local followBoxScript = game.ServerScriptService.Server.Services.PetScripts.FollowBox:Clone()
        followBoxScript.Parent = box
        
        -- Do not add alignment here; the Follow script manages AlignPosition/AlignOrientation
        
        -- Set pet properties (ensure compatibility values exist)
        PetModel.PositionNumber.Value = i
        PetModel.AttackPos.Value = "Pos" .. tostring((i * skip) % 36)
        PetModel.Pos.Value = GetPointOnCircle(PET_CIRCLE_RADIUS, Increment * i)
        do
            local petIdNv = PetModel:FindFirstChild("PetID")
            if not petIdNv then
                petIdNv = Instance.new("NumberValue")
                petIdNv.Name = "PetID"
                petIdNv.Parent = PetModel
            end
            petIdNv.Value = petId.Value
        end
        
        -- Position model by PrimaryPart to the box position (legacy behavior)
        if PetModel.PrimaryPart then
            PetModel.PrimaryPart.Position = box.Position
            logModelGeometry("POST_SET_POSITION_PREPARENT", PetModel)
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
        
        -- NOW parent everything to workspace (AFTER everything is built)
        PetModel.Parent = petModelsLocation
        box.Parent = petLocation
        -- Match legacy: set pet model network owner immediately after parenting
        if PetModel.PrimaryPart then
            pcall(function()
                -- Keep anchored until Follow unanchors; prevents initial clump
                PetModel.PrimaryPart.Anchored = true
                PetModel.PrimaryPart:SetNetworkOwner(Player)
            end)
        end
        -- Trigger refresh like legacy
        if PetModel:FindFirstChild("Refresh") and PetModel.Refresh:IsA("BoolValue") then
            PetModel.Refresh.Value = true
        end
        
        -- Immediate spawn position log (full geometry after parent). Physics settles next frame; sample again shortly.
        logModelGeometry("POST_PARENT", PetModel)
        if DIAGNOSTICS_ENABLED then
            printDiagnostics("POST_PARENT", collectModelDiagnostics(PetModel))
            watchModelStability(PetModel, string.format("%s:%s", tostring(effectiveIdName), tostring(effectiveVariantName)))
        end
        do
            local capturedModel = PetModel
            task.defer(function()
                task.wait()
                if capturedModel and capturedModel.Parent then
                    logModelGeometry("POST_PARENT_AFTER_STEP", capturedModel)
                    if DIAGNOSTICS_ENABLED then
                        printDiagnostics("POST_PARENT_AFTER_STEP", collectModelDiagnostics(capturedModel))
                    end
                end
            end)
        end

        -- Legacy: box unanchored & network owner set; pet model anchoring handled by Follow
        box.Anchored = false
        -- Set network owner for the control box only; PetModel owner will be set by Follow after constraints bind
        box:SetNetworkOwner(Player)
        
        -- Do not toggle Refresh here; it causes duplicate setFollowType runs and dueling constraints
        
        -- Finally enable Follow after everything is live and networked
        local followScript = PetModel:FindFirstChild("Follow")
        if followScript then
            followScript.Disabled = false
        end

        -- Watch for unexpected deletion to debug fast-despawn
        PetModel.AncestryChanged:Connect(function(_, newParent)
            if newParent == nil then
                print("⚠️ PetHandler: Pet model removed from workspace:", PetModel.Name, "PetID=", PetModel:FindFirstChild("PetID") and PetModel.PetID.Value)
            end
        end)
        
        print("✅ PetHandler: Created REAL pet", i, "for", Player.Name, "at", PetModel.PrimaryPart and PetModel.PrimaryPart.Position or "unknown position")
    end
    
        print("🎉 PetHandler: loadEquipped completed for", Player.Name)
        return "Success"
    end)
    cleanup()
    if ok then
        return result
    else
        warn("PetHandler: loadEquipped error for", Player and Player.Name, result)
        return "Error"
    end
end

-- Register with the bridge (wait for it to be available)
local function registerWithBridge()
    if _G.SetPetLoadEquippedFunction then
        _G.SetPetLoadEquippedFunction(loadEquipped)
        print("✅ PetHandler: Registered with PetEquipmentBridge (native handler)")
    else
        task.wait(0.1)
        registerWithBridge()
    end
end
registerWithBridge()

-- Handle player joining
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- Create player folders (spawning is triggered by PetEquipmentBridge)
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