local Disabled = false

-- Suppress verbose debug prints in this script unless explicitly enabled
local __RAW_PRINT = print
local __PRINT_ENABLED = false
local function print(...)
    if __PRINT_ENABLED then
        __RAW_PRINT(...)
    end
end
local Player = game.Players:FindFirstChild(script.Parent.Parent.Name)

-- Create Game folder if it doesn't exist
local gameFolder = game.Workspace:FindFirstChild("Game")
if not gameFolder then
    gameFolder = Instance.new("Folder")
    gameFolder.Name = "Game"
    gameFolder.Parent = game.Workspace
end

-- Create Breakables folder if it doesn't exist
local breakables = gameFolder:FindFirstChild("Breakables")
if not breakables then
    breakables = Instance.new("Folder")
    breakables.Name = "Breakables"
    breakables.Parent = gameFolder
end

-- DEBUG: follow setup prints are suppressed unless __PRINT_ENABLED=true above

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
