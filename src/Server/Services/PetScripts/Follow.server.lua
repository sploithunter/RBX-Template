local Disabled = false
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local hasUnanchored = false
local unanchorScheduled = false
local __RAW_PRINT = print
local PRINT_ENABLED = true -- temporarily enable verbose tracing
local function tprint(...)
    if PRINT_ENABLED then
        __RAW_PRINT("[FOLLOW TRACE]", ...)
    end
end

-- Toggleable stabilization knobs (for A/B testing root cause)
local ENABLE_MASSLESS = false -- massless now applied pre-parent in PetHandler
local ENABLE_ZERO_VELOCITY = true
local ENABLE_STABILIZE_LOOP = false
local STABILIZE_DURATION_SECS = 3.0
local ENABLE_DRIFT_CLAMP = false
local ENABLE_SPAWN_SNAP = false
local ENABLE_SPAWN_PARTICLES = false
local ENABLE_RANDOM_SPAWN = false
local RANDOM_SPAWN_RADIUS_MIN = 6
local RANDOM_SPAWN_RADIUS_MAX = 10
local RANDOM_SPAWN_HEIGHT = 2.5
local ENABLE_INVISIBLE_SPAWN = false
local SPAWN_FADE_IN_TIME = 0.25
local didInitialFade = false

-- Mass debugging (toggleable)
local DEBUG_MASS = false
local function debugAssemblyMass(model, tag, seconds)
    if not DEBUG_MASS then return end
    if not model or not model:IsA("Model") or not model.PrimaryPart then return end
    local start = os.clock()
    local function snapshot()
        local anchored, massless, partCount, totalMass = 0, 0, 0, 0
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                partCount += 1
                if d.Anchored then anchored += 1 end
                if d.Massless then massless += 1 end
                totalMass += d:GetMass()
            end
        end
        local assemblyMass = model.PrimaryPart.AssemblyMass
        local owner
        pcall(function()
            local o = model.PrimaryPart:GetNetworkOwner()
            owner = o and o.Name or "nil"
        end)
        print(string.format(
            "[MASS] %s parts=%d anchored=%d massless=%d totalMass=%.2f assemblyMass=%s owner=%s",
            tag or model:GetFullName(), partCount, anchored, massless, totalMass, tostring(assemblyMass), owner
        ))
    end
    local conn; conn = RunService.Heartbeat:Connect(function()
        snapshot()
        if os.clock() - start > (seconds or 1.5) then conn:Disconnect() end
    end)
end

-- Watchdog: if pet drifts too far from its target, snap it back safely
local AXIS_TELEPORT_THRESHOLD = 1000 -- per-axis threshold
local WATCHDOG_INTERVAL = 0.1

local function startTeleportWatchdog(tokenName: string, getTargetCFrame: () -> CFrame?)
    -- Destroy any existing token with same name
    local existing = script:FindFirstChild(tokenName)
    if existing then existing:Destroy() end
    local token = Instance.new("BindableEvent")
    token.Name = tokenName
    token.Parent = script
    task.spawn(function()
        while token.Parent and script.Parent do
            task.wait(WATCHDOG_INTERVAL)
            local model = script.Parent
            local primary = model and model.PrimaryPart
            if not primary then continue end
            local targetCF = nil
            pcall(function() targetCF = getTargetCFrame() end)
            if not targetCF then continue end
            local pos = primary.Position
            local tpos = targetCF.Position
            local dx = math.abs(pos.X - tpos.X)
            local dy = math.abs(pos.Y - tpos.Y)
            local dz = math.abs(pos.Z - tpos.Z)
            if dx > AXIS_TELEPORT_THRESHOLD or dy > AXIS_TELEPORT_THRESHOLD or dz > AXIS_TELEPORT_THRESHOLD then
                -- Teleport back to target and zero velocities
                pcall(function()
                    primary.AssemblyLinearVelocity = Vector3.new()
                    primary.AssemblyAngularVelocity = Vector3.new()
                    model:PivotTo(targetCF)
                end)
                if PRINT_ENABLED then
                    tprint("pet=", model.Name, "WATCHDOG-TELEPORT", string.format("dx=%.1f dy=%.1f dz=%.1f", dx, dy, dz))
                end
            end
        end
    end)
end

-- Apply unified align parameters for both follow and attack modes
local function applyAlignParams(alignPosition: AlignPosition, alignOrientation: AlignOrientation, assemblyMass: number)
    if alignPosition then
        alignPosition.MaxForce = math.huge
        alignPosition.Responsiveness = 200
        alignPosition.RigidityEnabled = false
    end
    if alignOrientation then
        -- Match Studio inspector: infinite torque and angular velocity for snappy reorientation
        alignOrientation.MaxTorque = math.huge
        alignOrientation.MaxAngularVelocity = math.huge
        alignOrientation.Responsiveness = 200
        alignOrientation.RigidityEnabled = false
        -- alignOrientation.MaxAngularVelocity left as default (infinite)
    end
end

-- Diagnostics helpers to compare this pet model with others just before unanchoring
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
        attachments = 0,
        bodyMovers = 0,
        partsWithoutDirectWeldToPrimary = 0,
        maxOffset = 0,
        hasAttachmentPet = (primary and primary:FindFirstChild("attachmentPet") ~= nil) or false,
        assemblyMass = primary and primary.AssemblyMass or 0,
    }
    local primaryPos = primary and primary.Position or (model:GetPivot().Position)
    local function hasDirectWeldToPrimary(p)
        if not primary or p == primary then return true end
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
    stats.boundingSize = size
    stats.anchoredPrimary = primary and primary.Anchored or false
    stats.canCollidePrimary = primary and primary.CanCollide or false
    return stats
end

local function printDiag(tag, stats)
    if not stats or not stats.valid then return end
    if PRINT_ENABLED then __RAW_PRINT(string.format(
        "[FOLLOW DIAG] %s %s prim=%s parts=%d anchored=%d collide=%d welds=%d alignP=%d alignO=%d attach=%d body=%d noWeld=%d maxOff=%.2f mass=%.2f bbox=(%.1f,%.1f,%.1f) primAnch=%s",
        tag,
        tostring(stats.name),
        tostring(stats.primaryPart),
        stats.totalParts,
        stats.anchoredParts,
        stats.canCollideParts,
        stats.weldConstraints,
        stats.alignPositions,
        stats.alignOrientations,
        stats.attachments,
        stats.bodyMovers,
        stats.partsWithoutDirectWeldToPrimary,
        stats.maxOffset,
        stats.assemblyMass,
        stats.boundingSize.X, stats.boundingSize.Y, stats.boundingSize.Z,
        tostring(stats.anchoredPrimary)
    )) end
end

local function printComparisons(currentStats, others)
    for _, s in ipairs(others) do
        if PRINT_ENABLED then __RAW_PRINT(string.format(
            "[FOLLOW DIFF] %s vs %s | parts:%d/%d anchored:%d/%d collide:%d/%d welds:%d/%d noWeld:%d/%d maxOff:%.2f/%.2f mass:%.1f/%.1f",
            tostring(currentStats.name), tostring(s.name),
            currentStats.totalParts, s.totalParts,
            currentStats.anchoredParts, s.anchoredParts,
            currentStats.canCollideParts, s.canCollideParts,
            currentStats.weldConstraints, s.weldConstraints,
            currentStats.partsWithoutDirectWeldToPrimary, s.partsWithoutDirectWeldToPrimary,
            currentStats.maxOffset, s.maxOffset,
            currentStats.assemblyMass, s.assemblyMass
        )) end
    end
end

local function setMasslessAndZeroVel(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            if ENABLE_MASSLESS then
                d.Massless = true
            end
            if ENABLE_ZERO_VELOCITY then
                d.AssemblyLinearVelocity = Vector3.new()
                d.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end
end

local function attachPartWatchers(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d:GetPropertyChangedSignal("Transparency"):Connect(function()
                tprint("pet=", script.Parent.Name, "PART TransparencyChanged", d:GetFullName(), d.Transparency)
            end)
            d:GetPropertyChangedSignal("Size"):Connect(function()
                tprint("pet=", script.Parent.Name, "PART SizeChanged", d:GetFullName(), tostring(d.Size))
            end)
            d.Destroying:Connect(function()
                tprint("pet=", script.Parent.Name, "PART Destroying", d:GetFullName())
            end)
            d.AncestryChanged:Connect(function(_, newParent)
                if newParent == nil then
                    tprint("pet=", script.Parent.Name, "PART RemovedFromWorkspace", d:GetFullName())
                end
            end)
        end
    end
end

local function setModelTransparencyInstant(model, alpha)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Transparency = alpha
        elseif d:IsA("Decal") or d:IsA("Texture") then
            d.Transparency = alpha
        end
    end
end

local function fadeModelToVisible(model, duration)
    duration = duration or 0.25
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            TweenService:Create(d, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
        elseif d:IsA("Decal") or d:IsA("Texture") then
            TweenService:Create(d, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
        end
    end
end

-- Wait for script to be properly parented to a pet model
if not script.Parent or script.Parent.Name == "PetScripts" then
    script.Parent.Changed:Wait() -- Wait until we're reparented
end

-- Ensure we have the required components
local TargetID = script.Parent:WaitForChild("TargetID")
local TargetType = script.Parent:WaitForChild("TargetType") 
local TargetWorld = script.Parent:WaitForChild("TargetWorld")

-- Get the player from the pet's location in workspace
local Player = game.Players:FindFirstChild(script.Parent.Parent.Name)
local breakables = game.Workspace:WaitForChild("Game"):WaitForChild("Breakables")


-- Legacy startup delay to mirror original behavior
task.wait(2)

local CrystalList = {}
for i, v in pairs(game.Workspace:WaitForChild("Game"):WaitForChild("Breakables"):WaitForChild("Crystals"):GetChildren()) do
	if v:IsA("Folder") then
		table.insert(CrystalList,v.Name)
	end
end

local GoldList = {}
for i, v in pairs(game.Workspace:WaitForChild("Game"):WaitForChild("Breakables"):WaitForChild("Gold"):GetChildren()) do
	if v:IsA("Folder") then
		table.insert(GoldList,v.Name)
	end
end

local GreenList = {}
for i, v in pairs(game.Workspace:WaitForChild("Game"):WaitForChild("Breakables"):WaitForChild("Green"):GetChildren()) do
	if v:IsA("Folder") then
		table.insert(GreenList,v.Name)
	end
end

local SnowList = {}
for i, v in pairs(game.Workspace:WaitForChild("Game"):WaitForChild("Chaseables"):WaitForChild("Snowman"):GetChildren()) do
	if v:IsA("Folder") then

		table.insert(SnowList,v.Name)
	end
end

local HeartList = {}
for i, v in pairs(game.Workspace:WaitForChild("Game"):WaitForChild("Chaseables"):WaitForChild("Hearts"):GetChildren()) do
	if v:IsA("Folder") then
		table.insert(HeartList,v.Name)
	end
end




local function scanForID(folder, id, TargetType, TargetWorld)
	local world = Player.CurrentWorld.Value

	local farmType = TargetType
	local target = nil
	
	if farmType == "Green" then
		local typeFolder = workspace.Game:WaitForChild("Breakables"):FindFirstChild(farmType)
		local worldFolder
		if typeFolder then
			worldFolder = typeFolder:FindFirstChild(world)
		end
		if worldFolder then
			for i, v in pairs(worldFolder:WaitForChild("Items"):GetChildren()) do
				local bID = v:FindFirstChild("BreakableID")

				if bID and bID.Value == id then
					--print("found id: "..tostring(v.Value))
					target = bID
					return target
				end
			end

		else
			--		print("didn't find worldfolder for "..world.." in "..typeFolder)
		end
		--	print("Could not find target")
		return nil

	end

	if farmType == "Gold" then
		local typeFolder = workspace.Game:WaitForChild("Breakables"):FindFirstChild(farmType)
		local worldFolder
		if typeFolder then
			worldFolder = typeFolder:FindFirstChild(world)
		end
		if worldFolder then
			for i, v in pairs(worldFolder:WaitForChild("Items"):GetChildren()) do
				local bID = v:FindFirstChild("BreakableID")

				if bID and bID.Value == id then
					--print("found id: "..tostring(v.Value))
					target = bID
					return target
				end
			end

		else
		--		print("didn't find worldfolder for "..world.." in "..typeFolder)
		end
		--	print("Could not find target")
		return nil

	end

	if farmType == "Crystals" then
		local typeFolder = workspace.Game:WaitForChild("Breakables"):FindFirstChild(farmType)
		local worldFolder
		if typeFolder then
			worldFolder = typeFolder:FindFirstChild(world)

		end
		if worldFolder then
			for x, spawners in pairs(worldFolder:GetChildren()) do
				for i, crystals in pairs(spawners:GetChildren()) do
					for j, v in pairs(crystals:GetChildren()) do
						if v.Name == "BreakableID" and v.Value == id then
							--print("found id: "..tostring(v.Value))
							target = v
							return target
						end
					end

				end

			end

		else
			--	print("didn't find worldfolder for "..world.." in "..typeFolder)
		end
--		print("Could not find target")
		return nil

	end



end


function GetPointOnCircle(CircleRadius, Degrees)
	return Vector3.new(math.cos(math.rad(Degrees)) * CircleRadius, 1, math.sin(math.rad(Degrees))* CircleRadius)
end

function GetBoundingBox(model, orientation)
	if typeof(model) == "Instance" then
		model = model:GetDescendants()
	end
	if not orientation then
		orientation = CFrame.new()
	end
	local abs = math.abs
	local inf = math.huge

	local minx, miny, minz = inf, inf, inf
	local maxx, maxy, maxz = -inf, -inf, -inf

	for _, obj in pairs(model) do
		if obj:IsA("BasePart") then
			local cf = obj.CFrame
			cf = orientation:toObjectSpace(cf)
			local size = obj.Size
			local sx, sy, sz = size.X, size.Y, size.Z

			local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = cf:components()

			local wsx = 0.5 * (abs(R00) * sx + abs(R01) * sy + abs(R02) * sz)
			local wsy = 0.5 * (abs(R10) * sx + abs(R11) * sy + abs(R12) * sz)
			local wsz = 0.5 * (abs(R20) * sx + abs(R21) * sy + abs(R22) * sz)

			if minx > x - wsx then
				minx = x - wsx
			end
			if miny > y - wsy then
				miny = y - wsy
			end
			if minz > z - wsz then
				minz = z - wsz
			end

			if maxx < x + wsx then
				maxx = x + wsx
			end
			if maxy < y + wsy then
				maxy = y + wsy
			end
			if maxz < z + wsz then
				maxz = z + wsz
			end
		end
	end

	local omin, omax = Vector3.new(minx, miny, minz), Vector3.new(maxx, maxy, maxz)
	local omiddle = (omax+omin)/2
	local wCf = orientation - orientation.p + orientation:pointToWorldSpace(omiddle)
	local size = (omax-omin)
	return wCf, size
end


local function setFollowType(followType)
    -- normalize followType to numeric: 0 = BodyMover, 1 = Align
    if typeof(followType) == "string" then
        local ft = string.lower(followType)
        followType = (ft == "align") and 1 or 0
    elseif typeof(followType) ~= "number" then
        followType = 0
    end
	
	local modelBox, modelSize = GetBoundingBox(script.Parent)
	modelSize = script.Parent.PetSize.Value
	local PosNum = script.Parent.PositionNumber.Value
	local PosNumString = tostring(PosNum)
    local playerBox = workspace.PlayerPetControl:WaitForChild(Player.Name):WaitForChild(1)
    local box = workspace.PlayerPetControl:WaitForChild(Player.Name):WaitForChild(PosNumString)
    if PRINT_ENABLED then
        local playerBox = workspace.PlayerPetControl:FindFirstChild(Player.Name)
        local boxPath = box and box:GetFullName() or "<nil>"
        __RAW_PRINT(string.format("[FOLLOW] pet=%s PosNum=%s box=%s",
            script.Parent:GetFullName(), PosNumString, boxPath))
    end
    -- Build movers/constraints per mode
        while(script.Parent.PositionNumber.Value == 0 ) do
			-- Short poll while number is being set
			task.wait(0.05)
		end
		local attachmentBox
		local attachmentPet

		attachmentBox = box.Pet

		attachmentBox.Position = Vector3.new(0,0,0) + Vector3.new(0,modelSize.Y/4,0)
		attachmentBox.Visible = false
		--print("Position "..PosNumString.." for pet "..script.Parent.Name.." is "..tostring(modelSize.Y))

        -- No special initial placement in legacy; keep current position

        -- If requested, spawn fully invisible and fade in after follow binds
		if ENABLE_INVISIBLE_SPAWN and not didInitialFade then
			setModelTransparencyInstant(script.Parent, 1)
			didInitialFade = true
		end

        if script.Parent.PrimaryPart:FindFirstChild("attachmentPet") then
			script.Parent.PrimaryPart:FindFirstChild("attachmentPet"):Destroy() 
		end
        
        -- Respect legacy followType: when 1 use Align, else use BodyMovers
        if followType == 1 then
        attachmentPet = Instance.new("Attachment")
		attachmentPet.Visible = false
		attachmentPet.Name = "attachmentPet"
		attachmentPet.Parent = script.Parent.PrimaryPart
        -- Do not force any yaw offset; use model's native forward axis
        -- attachmentPet.CFrame = CFrame.new()
        if PRINT_ENABLED then
            __RAW_PRINT(string.format("[FOLLOW] pet=%s attachmentPet=%s boxPet=%s",
                script.Parent:GetFullName(),
                attachmentPet:GetFullName(),
                (box and box:FindFirstChild("Pet") and box.Pet:GetFullName()) or "<nil>"))
        end


		
			

		
        local alignPosition
		if script.Parent:FindFirstChild("align") then
			script.Parent:FindFirstChild("align"):Destroy()
		end
        alignPosition = Instance.new("AlignPosition")
		alignPosition.Name = "align"
		alignPosition.Parent = script.Parent
		
			
		

        -- Unified parameters
        applyAlignParams(alignPosition, nil, script.Parent.PrimaryPart.AssemblyMass)
		alignPosition.Attachment0 = script.Parent.PrimaryPart.attachmentPet
		alignPosition.Attachment1 = attachmentBox
		alignPosition.ApplyAtCenterOfMass = false


        local alignOrientation 
		if script.Parent:FindFirstChild("alignO") then
			script.Parent:FindFirstChild("alignO"):Destroy()
		end
		
        alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "alignO"
		alignOrientation.Parent = script.Parent


        alignOrientation.Attachment0 = script.Parent.PrimaryPart.attachmentPet
        alignOrientation.Attachment1 = attachmentBox
        applyAlignParams(nil, alignOrientation, script.Parent.PrimaryPart.AssemblyMass)
        if PRINT_ENABLED then
            __RAW_PRINT(string.format("[FOLLOW] pet=%s alignP(A0=%s,A1=%s) alignO(A0=%s,A1=%s)",
                script.Parent:GetFullName(),
                script.Parent.PrimaryPart.attachmentPet:GetFullName(), attachmentBox:GetFullName(),
                script.Parent.PrimaryPart.attachmentPet:GetFullName(), attachmentBox:GetFullName()))
        end
        -- Zero velocities at mode switch to prevent spikes
        pcall(function()
            script.Parent.PrimaryPart.AssemblyLinearVelocity = Vector3.new()
            script.Parent.PrimaryPart.AssemblyAngularVelocity = Vector3.new()
        end)
        -- Mass debug right after binding/unanchor
        debugAssemblyMass(script.Parent, "FollowBind", 1.5)
        -- Start watchdog tethered to current follow box attachment
        startTeleportWatchdog("_FollowWatchdog", function()
            return attachmentBox and attachmentBox.WorldCFrame or nil
        end)
        -- Values set by applyAlignParams

        -- Optional spin effect disabled when invis spawn is enabled
        if not ENABLE_INVISIBLE_SPAWN then
            local primary = script.Parent.PrimaryPart
            if primary then
                alignOrientation.Enabled = false
                primary.AssemblyAngularVelocity = Vector3.new(0, 10, 0)
                task.delay(0.25, function()
                    primary.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    alignOrientation.Enabled = true
                end)
            end
        end

        if ENABLE_SPAWN_PARTICLES then
			local primary = script.Parent.PrimaryPart
			if primary then
				local p = Instance.new("ParticleEmitter")
				p.Name = "SpawnBurst"
				p.Lifetime = NumberRange.new(0.15, 0.35)
				p.Rate = 0
				p.Speed = NumberRange.new(1, 3)
				p.SpreadAngle = Vector2.new(360, 360)
				p.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.5),
					NumberSequenceKeypoint.new(1, 0)
				})
				p.LightEmission = 0.7
				p.Parent = primary
				p:Emit(25)
				task.delay(1, function()
					if p then p.Enabled = false; p:Destroy() end
				end)
			end
		end
        else
            -- BODY MOVER MODE: remove Align instances and ensure BG/BP exist
            local existingAlign = script.Parent:FindFirstChild("align")
            if existingAlign then existingAlign:Destroy() end
            local existingAlignO = script.Parent:FindFirstChild("alignO")
            if existingAlignO then existingAlignO:Destroy() end
            local pp = script.Parent.PrimaryPart
            if pp then
                if not pp:FindFirstChild("BodyGyro") then
                    local BG = game:GetService("ServerScriptService"):WaitForChild("PetHandler"):WaitForChild("PetSetup"):WaitForChild("BodyGyro"):Clone()
                    BG.Parent = pp
                    pcall(function() BG.MaxTorque = Vector3.new(1e9, 1e9, 1e9) end)
                else
                    pcall(function() pp.BodyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9) end)
                end
                if not pp:FindFirstChild("BodyPosition") then
                    local BP = game:GetService("ServerScriptService"):WaitForChild("PetHandler"):WaitForChild("PetSetup"):WaitForChild("BodyPosition"):Clone()
                    BP.Parent = pp
                    pcall(function() BP.MaxForce = Vector3.new(1e9, 1e9, 1e9) end)
                else
                    pcall(function() pp.BodyPosition.MaxForce = Vector3.new(1e9, 1e9, 1e9) end)
                end
            end
        end

    -- Immediate unanchor after movers exist (legacy timing)
    if not hasUnanchored then
        -- Pre-unanchor diagnostics across all current pets for this player
        do
            local folder = workspace:FindFirstChild("PlayerPets")
            folder = folder and folder:FindFirstChild(Player.Name)
            if folder then
                local currentStats = collectModelDiagnostics(script.Parent)
                local others = {}
                for _, child in ipairs(folder:GetChildren()) do
                    if child:IsA("Model") and child ~= script.Parent then
                        local st = collectModelDiagnostics(child)
                        table.insert(others, st)
                    end
                end
                printDiag("PRE-UNANCHOR THIS", currentStats)
                for _, st in ipairs(others) do printDiag("PRE-UNANCHOR OTHER", st) end
                printComparisons(currentStats, others)
                setMasslessAndZeroVel(script.Parent)
                attachPartWatchers(script.Parent)
            end
        end
        local primary = script.Parent.PrimaryPart
        if primary then
            local before = primary.Anchored
            primary.Anchored = false
            local owner
            pcall(function()
                primary:SetNetworkOwner(Player)
                owner = primary:GetNetworkOwner()
            end)
            hasUnanchored = true
            if PRINT_ENABLED then tprint("pet=", script.Parent.Name, "unanchor-now", "beforeAnchored=", before, "afterAnchored=", primary.Anchored, "owner=", owner and owner.Name or "nil") end
            if ENABLE_INVISIBLE_SPAWN then
                fadeModelToVisible(script.Parent, SPAWN_FADE_IN_TIME)
            end
            -- Stabilization window: reassert ownership/anchoring, optional drift clamp
            if ENABLE_STABILIZE_LOOP then
                task.spawn(function()
                    local startT = os.clock()
                    while os.clock() - startT < STABILIZE_DURATION_SECS and script.Parent and primary.Parent do
                        if primary.Anchored then primary.Anchored = false end
                        pcall(function() primary:SetNetworkOwner(Player) end)
                        if ENABLE_DRIFT_CLAMP then
                            local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                local dist = (primary.Position - hrp.Position).Magnitude
                                if dist > 150 then
                                    local targetCF = CFrame.new(hrp.Position + Vector3.new(0, 3, -5))
                                    script.Parent:PivotTo(targetCF)
                                    if PRINT_ENABLED then tprint("pet=", script.Parent.Name, "CLAMP-REPOSITION", string.format("dist=%.1f", dist), "->", tostring(targetCF.Position)) end
                                end
                            end
                        end
                        task.wait(0.05)
                    end
                end)
            end
            -- sample a few frames later
            task.defer(function()
                task.wait(0.05)
                local o
                pcall(function() o = primary:GetNetworkOwner() end)
                if PRINT_ENABLED then tprint("pet=", script.Parent.Name, "t+0.05s", "anchored=", primary.Anchored, "owner=", o and o.Name or "nil", "pos=", tostring(primary.Position)) end
            end)
            task.defer(function()
                task.wait(0.2)
                local o
                pcall(function() o = primary:GetNetworkOwner() end)
                if PRINT_ENABLED then tprint("pet=", script.Parent.Name, "t+0.2s", "anchored=", primary.Anchored, "owner=", o and o.Name or "nil", "pos=", tostring(primary.Position)) end
            end)
            task.defer(function()
                task.wait(1)
                local o
                pcall(function() o = primary:GetNetworkOwner() end)
                if PRINT_ENABLED then tprint("pet=", script.Parent.Name, "t+1.0s", "anchored=", primary.Anchored, "owner=", o and o.Name or "nil", "pos=", tostring(primary.Position)) end
            end)
            -- monitor Anchored flips
            primary:GetPropertyChangedSignal("Anchored"):Connect(function()
                if PRINT_ENABLED then tprint("pet=", script.Parent.Name, "AnchoredChanged", primary.Anchored) end
            end)
        end
    end

	-- Align-only mode: remove legacy branch
end


local function setAttack()

	-- Do not remove legacy BodyMovers; disable them instead to avoid interference
	local pp = script.Parent and script.Parent.PrimaryPart
	if pp then
		local bg = pp:FindFirstChild("BodyGyro")
		if bg and bg:IsA("BodyGyro") then
			bg.MaxTorque = Vector3.new(0, 0, 0)
			pcall(function()
				bg.P = 0
				bg.D = 0
			end)
		end
		local bp = pp:FindFirstChild("BodyPosition")
		if bp and bp:IsA("BodyPosition") then
			bp.MaxForce = Vector3.new(0, 0, 0)
			pcall(function()
				bp.P = 0
				bp.D = 0
			end)
		end
	end

    local modelBox, modelSize = GetBoundingBox(script.Parent)
    modelSize = script.Parent.PetSize.Value
    -- Determine star point count dynamically and choose a distributed slot index
    local targetID = scanForID(breakables,TargetID.Value, TargetType.Value, TargetWorld.Value)
    if targetID == nil then
        return setFollowType()
	end
	local target = targetID.Parent
    local star = target:WaitForChild("Star")
    local pointCount = star:GetAttribute("PointCount") or 108
    -- Use pet's PositionNumber and PetID (or Player.UserId fallback) to spread selection
    local petIdVal = script.Parent:FindFirstChild("PetID")
    local seed = (script.Parent.PositionNumber.Value) + (petIdVal and petIdVal.Value or tonumber(Player.UserId))
    local baseIdx = (seed % pointCount) + 1
    local chosenIdx = baseIdx
    -- Try a few offsets using a coprime step to avoid clustering
    local step = 7
    for tries = 0, 10 do
        local idx = 1 + ((baseIdx + tries * step) % pointCount)
        local candidate = star:FindFirstChild("StarBox"..tostring(idx))
        if candidate then
            chosenIdx = idx
            break
        end
    end
    local box = star:WaitForChild("StarBox"..tostring(chosenIdx))
	
	-- Always use Align method for attack positioning
		while(script.Parent.PositionNumber.Value == 0 ) do
			-- Short poll while number is being set
			task.wait(0.05)
		end
		local attachmentBox
		local attachmentPet

        attachmentBox = box.Pet
        if PRINT_ENABLED then
            __RAW_PRINT(string.format("[FOLLOW] pet=%s attachBox=%s",
                script.Parent:GetFullName(), attachmentBox and attachmentBox:GetFullName() or "<nil>"))
        end
        -- Snap to target before enabling constraints to avoid large corrections
        pcall(function()
            local targetCF = attachmentBox.WorldCFrame
            if targetCF then script.Parent:PivotTo(targetCF) end
        end)

		attachmentBox.Position = Vector3.new(0,0,0) + Vector3.new(0,modelSize.Y/4,0)
		attachmentBox.Visible = false
		--print("Position "..PosNumString.." for pet "..script.Parent.Name.." is "..tostring(modelSize.Y))

		if not script.Parent.PrimaryPart:FindFirstChild("attachmentPet") then
			attachmentPet = Instance.new("Attachment")
			attachmentPet.Visible = false
			attachmentPet.Name = "attachmentPet"
			attachmentPet.Parent = script.Parent.PrimaryPart


        else
            attachmentPet = script.Parent.PrimaryPart.attachmentPet

		end
		local alignPosition
		if not script.Parent:FindFirstChild("align") then
			alignPosition = Instance.new("AlignPosition")
			alignPosition.Name = "align"
			alignPosition.Parent = script.Parent
		else
			alignPosition = script.Parent:FindFirstChild("align")
		end
		
        alignPosition.MaxForce = 1e12
        alignPosition.RigidityEnabled = true
		alignPosition.Attachment0 = script.Parent.PrimaryPart.attachmentPet
		alignPosition.Attachment1 = attachmentBox
        alignPosition.Responsiveness = 75
		alignPosition.ApplyAtCenterOfMass = false
		

		local alignOrientation 
		if not script.Parent:FindFirstChild("alignO") then
			alignOrientation = Instance.new("AlignOrientation")
			alignOrientation.Name = "alignO"
			alignOrientation.Parent = script.Parent
		else
			alignOrientation =script.Parent:FindFirstChild("alignO")
		end

		alignOrientation.Attachment0 = script.Parent.PrimaryPart.attachmentPet
		alignOrientation.Attachment1 = attachmentBox
        alignOrientation.MaxTorque = 10000 * script.Parent.PrimaryPart.AssemblyMass
        alignOrientation.Responsiveness = 75
        alignOrientation.RigidityEnabled = true
		



    -- Immediate unanchor/network owner now that inspection window is over
    if not hasUnanchored then
        local primary = script.Parent.PrimaryPart
        if primary then
            local before = primary.Anchored
            primary.Anchored = false
            local owner
            pcall(function()
                primary:SetNetworkOwner(Player)
                owner = primary:GetNetworkOwner()
            end)
            hasUnanchored = true
            if PRINT_ENABLED then tprint("pet=", script.Parent.Name, "unanchor-attack", "beforeAnchored=", before, "afterAnchored=", primary.Anchored, "owner=", owner and owner.Name or "nil") end
        end
    end

	-- Align-only mode; legacy branch removed
end


if Player then
    local data = Player:WaitForChild("Data")
    local followType = data:WaitForChild("FollowType").Value
    setFollowType(followType)

    Player:WaitForChild("Data"):WaitForChild("FollowType"):GetPropertyChangedSignal("Value"):Connect(function()
        if TargetID.Value == 0 then
            setFollowType(followType)
        end
    end)
	
	
	script.Parent.Refresh:GetPropertyChangedSignal("Value"):Connect(function()
		if script.Parent.Refresh.Value == true then
			script.Parent.Refresh.Value = false
            setFollowType(followType)
		end
	end)
	
    script.Parent.TargetID:GetPropertyChangedSignal("Value"):Connect(function()
		if TargetID.Value ~= 0 then
		--	print("Set Attack")
            setAttack(1)
            -- Always (re)start damage loop when acquiring a target
            local existing = script:FindFirstChild("_DamageLoopConn")
            if existing then existing:Destroy() end
            local function doDamage()
                local TargetIDValue = TargetID.Value
                if TargetIDValue == 0 then return end
            local targetIdObj = scanForID(breakables, TargetIDValue, TargetType.Value, TargetWorld.Value)
            local breakable = targetIdObj and targetIdObj.Parent
                if not breakable then return end
                -- Apply small periodic damage per pet
                local hp = breakable:GetAttribute("HP") or 0
                if hp <= 0 then return end
                -- Use pet Power directly as damage per tick (default 1)
                local powerNV = script.Parent:FindFirstChild("Power")
                local power = tonumber(powerNV and powerNV.Value) or 1
                local dmg = math.max(1, math.floor(power))
                local newHp = math.max(0, hp - dmg)
                breakable:SetAttribute("HP", newHp)
                -- Record contribution on the crystal if folder exists
                local contrib = breakable:FindFirstChild("Contrib")
                if contrib then
                    local key = tostring(Player.UserId)
                    local nv = contrib:FindFirstChild(key)
                    if not nv then
                        nv = Instance.new("NumberValue")
                        nv.Name = key
                        nv.Value = 0
                        nv.Parent = contrib
                    end
                    nv.Value += (hp - newHp)
                end
            end
            local conn = Instance.new("BindableEvent")
            conn.Name = "_DamageLoopConn"
            conn.Parent = script
            task.spawn(function()
                while conn.Parent and script.Parent and TargetID.Value ~= 0 do
                    task.wait(1)
                    doDamage()
                end
                if conn.Parent then conn:Destroy() end
            end)
            -- Switch watchdog to attack target while attacking
            startTeleportWatchdog("_AttackWatchdog", function()
                return breakable and breakable:FindFirstChild("Star") and breakable.Star:FindFirstChild("StarBox1") and breakable.Star.StarBox1.Pet.WorldCFrame or nil
            end)
		else
		--	print("Quit Attack")
            local existing = script:FindFirstChild("_DamageLoopConn")
            if existing then existing:Destroy() end
			followType = data:WaitForChild("FollowType").Value
			setFollowType(followType)
		end
		
		--[[
		if TargetID.Value ~= 0 then
			followType = 0
			setFollowType(0)
		else
			followType = data:WaitForChild("FollowType").Value
			setFollowType(followType)
		end
		]]--
		
	end)
	--print("Found Player in Follow")
	while task.wait(0.05) do
		
		if TargetID.Value == 0 and Player.Character.Health ~= 0 and followType == 0 then
			--	print("Follow typ is "..tostring(followType))
		--	print("not attacking")
			if not Disabled then
				-- Legacy BodyMover path is disabled when using Align constraints; guard to avoid nil errors
				local BG = script.Parent.PrimaryPart:FindFirstChild("BodyGyro")
				local BP = script.Parent.PrimaryPart:FindFirstChild("BodyPosition")
				if BG and BP then
					local Pos = script.Parent.Pos.Value
					local d = Player.Character.HumanoidRootPart.Position.Y - script.Parent.PrimaryPart.Position.Y
					BP.Position = (Player.Character.HumanoidRootPart.Position + Pos) - Vector3.new(0,Player.Character.HumanoidRootPart.Size.Y/1,0) + Vector3.new(0,script.Parent.PrimaryPart.Size.Y/2,0) + Vector3.new(0,game.ServerScriptService.globalPetFloat.Value-0,0)
					if Player.Data.isWalking.Value == false then
						BG.CFrame = CFrame.new(script.Parent.PrimaryPart.Position, Player.Character.HumanoidRootPart.Position - Vector3.new(0, d, 0))
					else
						BG.CFrame = Player.Character.HumanoidRootPart.CFrame
					end
				end
			else
				script.Parent:Destroy()
				break
			end
		elseif TargetID.Value == 0 and Player.Character.Health ~= 0 and followType == 1 then
			--local PosNum = script.Parent.PositionNumber.Value
			--local PosNumString = tostring(PosNum)
			--local box = workspace.PlayerPetControl:FindFirstChild(Player.Name):FindFirstChild(PosNumString)
			--if not box then continue end
			--local Pos = script.Parent.Pos.Value
			--local BG = script.Parent.PrimaryPart.BodyGyro
			--local BP = script.Parent.PrimaryPart.BodyPosition
			--BP.Position = box.Position + Vector3.new(0,script.Parent.PrimaryPart.Size.Y/2,0) 
		--	print(tostring(BP.Position))
			--BG.CFrame = box.CFrame
			
			
				
		elseif TargetID.Value ~= 0 and Player.Character.Health ~= 0 then --and followType == 0 then
			--scan 
			local targetID = scanForID(breakables,TargetID.Value, TargetType.Value, TargetWorld.Value)
			
			if targetID ~= nil then
				local target = targetID.Parent
				--print("Found Target for "..TargetType.Value)
				if not Disabled then
					--local Pos = script.Parent.Pos.Value
					
				--	print("attacking")
					--[[
				
					local Pos = game.ServerScriptService:FindFirstChild(script.Parent.AttackPos.Value).Value
					local BG = script.Parent.PrimaryPart.BodyGyro
					local BP = script.Parent.PrimaryPart.BodyPosition
					local d = target.PrimaryPart.Position.Y - script.Parent.PrimaryPart.Position.Y
					BP.Position = (target.PrimaryPart.Position + Pos) - Vector3.new(0,target.PrimaryPart.Size.Y/2,0) + Vector3.new(0,script.Parent.PrimaryPart.Size.Y/1,0) + Vector3.new(0,game.ServerScriptService.globalPetAttackFloat.Value+1,0)
					if Player.Data.isWalking.Value == false then
						BG.CFrame = CFrame.new(script.Parent.PrimaryPart.Position, target.PrimaryPart.Position - Vector3.new(0, d, 0))
					else
						BG.CFrame = target.PrimaryPart.CFrame
					end
					
					]]--
					
					
					
				else
					script.Parent:Destroy()
					break
				end
			else
				TargetID.Value = 0
			--	print("Setting targetID to 0 with followtype of "..followType)
			end 
			
		else
			-- print("Set disabled") -- Suppressed spam
			Disabled = false
		end
	end
else
	--print("Could not find Player in Follow")
end