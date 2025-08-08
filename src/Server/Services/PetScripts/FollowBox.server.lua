local Disabled = false
local Player = game.Players:FindFirstChild(script.Parent.Parent.Name)
local breakables = game.Workspace:WaitForChild("Game"):WaitForChild("Breakables")

-- DEBUG: Check if FollowBox script is running
print("🔍 DEBUG FollowBox: Script started for control box", script.Parent.Name)
print("  - Player found:", Player ~= nil)
if Player then
    print("  - Player name:", Player.Name)
    print("  - Player character:", Player.Character ~= nil)
    if Player.Character then
        print("  - HumanoidRootPart:", Player.Character:FindFirstChild("HumanoidRootPart") ~= nil)
        if Player.Character:FindFirstChild("HumanoidRootPart") then
            print("  - attachmentFar exists:", Player.Character.HumanoidRootPart:FindFirstChild("attachmentFar") ~= nil)
        end
    end
end

local function scanForID(folder, id, TargetType, TargetWorld)
	local target = nil
	for i, v in pairs(folder:GetChildren()) do
		if v.Name == "BreakableID" and v.Value == id then
			target = v
			break
		elseif #v:GetChildren() ~= 0 then
			target = scanForID(v,id)
			if target ~= nil then
				break
			end
		end
	end
	if target then
		return target
	else
		return nil
	end
end

function GetPointOnCircle(CircleRadius, Degrees)
	return Vector3.new(math.cos(math.rad(Degrees)) * CircleRadius, 1, math.sin(math.rad(Degrees))* CircleRadius)
end

local followType = 0

if Player then
	local frontAttachment
	local centerAttachment = script.Parent.Center
	local alignP = script.Parent.AlignPosition
	local alignO = script.Parent.AlignOrientation
	local followeeNumber = tonumber(script.Parent.Name) - 1
	local originalPosition = Vector3.new(0,0,15)
	       if followeeNumber == 0 then
               print("🔍 DEBUG FollowBox: Setting up first pet (followeeNumber = 0)")
               print("  - attachmentFar position:", Player.Character.HumanoidRootPart.attachmentFar.WorldCFrame.Position)
               -- Use an attachment behind the player for the lead pet rather than in front
               local hrp = Player.Character.HumanoidRootPart
               -- Create or reuse a behind attachment once
               local behind = hrp:FindFirstChild("attachmentBehind")
               if not behind then
                   behind = Instance.new("Attachment")
                   behind.Name = "attachmentBehind"
                   behind.Parent = hrp
                   behind.Position = Vector3.new(0, 0, 12) -- behind player along +Z
               end
               Pos = behind.WorldCFrame.Position
               frontAttachment = behind
               alignP.Attachment0 = centerAttachment
               alignP.Attachment1 =  frontAttachment
               alignO.Attachment0 = centerAttachment
               alignO.Attachment1 =  frontAttachment
               print("  - AlignPosition connected: Center -> attachmentFar")
               print("  - AlignOrientation connected: Center -> attachmentFar")
                      else
               print("🔍 DEBUG FollowBox: Setting up pet", followeeNumber, "(following previous pet)")
               local frontAttachmentPart = workspace.PlayerPetControl:WaitForChild(Player.Name):WaitForChild(tostring(followeeNumber))
               print("  - Found front attachment part:", frontAttachmentPart ~= nil)
               if frontAttachmentPart then
                   print("  - Front attachment part name:", frontAttachmentPart.Name)
                   print("  - Has Back attachment:", frontAttachmentPart:FindFirstChild("Back") ~= nil)
               end
               -- Chain to the back of the previous pet's control box
               frontAttachment = frontAttachmentPart.Back
               alignP.Attachment0 = centerAttachment 
               alignP.Attachment1 = frontAttachment
               alignO.Attachment0 = centerAttachment
               alignO.Attachment1 =  frontAttachment
               print("  - AlignPosition connected: Center -> Back")
               print("  - AlignOrientation connected: Center -> Back")
           end
else
	-- Could not find Player in Follow
end
