local Disabled = false

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


local function setFollowType()

	while script.Parent.PrimaryPart:FindFirstChild("BodyGyro") do
		script.Parent.PrimaryPart.BodyGyro:Destroy()
	end
	while script.Parent.PrimaryPart:FindFirstChild("BodyPosition") do
		script.Parent.PrimaryPart.BodyPosition:Destroy()
	end
	
	local modelBox, modelSize = GetBoundingBox(script.Parent)
	modelSize = script.Parent.PetSize.Value
	local PosNum = script.Parent.PositionNumber.Value
	local PosNumString = tostring(PosNum)
    local playerBox = workspace.PlayerPetControl:WaitForChild(Player.Name):WaitForChild(1)
    local box = workspace.PlayerPetControl:WaitForChild(Player.Name):WaitForChild(PosNumString)
    -- Always use Align-based method
		while(script.Parent.PositionNumber.Value == 0 ) do
		--	print("waiting for position to be set")
			task.wait(1)
		end
		local attachmentBox
		local attachmentPet

		attachmentBox = box.Pet

		attachmentBox.Position = Vector3.new(0,0,0) + Vector3.new(0,modelSize.Y/4,0)
		attachmentBox.Visible = false
		--print("Position "..PosNumString.." for pet "..script.Parent.Name.." is "..tostring(modelSize.Y))

		if script.Parent.PrimaryPart:FindFirstChild("attachmentPet") then
			script.Parent.PrimaryPart:FindFirstChild("attachmentPet"):Destroy() 
		end
		
		attachmentPet = Instance.new("Attachment")
		attachmentPet.Visible = false
		attachmentPet.Name = "attachmentPet"
		attachmentPet.Parent = script.Parent.PrimaryPart


		
			

		
		local alignPosition
		if script.Parent:FindFirstChild("align") then
			script.Parent:FindFirstChild("align"):Destroy()
		end
        alignPosition = Instance.new("AlignPosition")
		alignPosition.Name = "align"
		alignPosition.Parent = script.Parent
		
			
		

        alignPosition.MaxForce = 1e12
        alignPosition.RigidityEnabled = true
		alignPosition.Attachment0 = script.Parent.PrimaryPart.attachmentPet
		alignPosition.Attachment1 = attachmentBox
        alignPosition.Responsiveness = 75
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
        alignOrientation.MaxTorque = 10000 * script.Parent.PrimaryPart.AssemblyMass
        alignOrientation.Responsiveness = 75
        alignOrientation.RigidityEnabled = true




	-- Align-only mode: remove legacy branch
end


local function setAttack()

	while script.Parent.PrimaryPart:FindFirstChild("BodyGyro") do
		script.Parent.PrimaryPart.BodyGyro:Destroy()
	end
	while script.Parent.PrimaryPart:FindFirstChild("BodyPosition") do
		script.Parent.PrimaryPart.BodyPosition:Destroy()
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
		--	print("waiting for position to be set")
			task.wait(1)
		end
		local attachmentBox
		local attachmentPet

        attachmentBox = box.Pet

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
		



	-- Align-only mode; legacy branch removed
end


if Player then
    local data = Player:WaitForChild("Data")
    setFollowType()

    Player:WaitForChild("Data"):WaitForChild("FollowType"):GetPropertyChangedSignal("Value"):Connect(function()
        if TargetID.Value == 0 then
            setFollowType()
        end
    end)
	
	
	script.Parent.Refresh:GetPropertyChangedSignal("Value"):Connect(function()
		if script.Parent.Refresh.Value == true then
			script.Parent.Refresh.Value = false
			setFollowType()
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
				local Pos = script.Parent.Pos.Value
				local BG = script.Parent.PrimaryPart.BodyGyro
				local BP = script.Parent.PrimaryPart.BodyPosition
				local d = Player.Character.HumanoidRootPart.Position.Y - script.Parent.PrimaryPart.Position.Y
				BP.Position = (Player.Character.HumanoidRootPart.Position + Pos) - Vector3.new(0,Player.Character.HumanoidRootPart.Size.Y/1,0) + Vector3.new(0,script.Parent.PrimaryPart.Size.Y/2,0) + Vector3.new(0,game.ServerScriptService.globalPetFloat.Value-0,0)
				--print("Setting Position")
				if Player.Data.isWalking.Value == false then
					BG.CFrame = CFrame.new(script.Parent.PrimaryPart.Position, Player.Character.HumanoidRootPart.Position - Vector3.new(0, d, 0))
				else
					BG.CFrame = Player.Character.HumanoidRootPart.CFrame
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