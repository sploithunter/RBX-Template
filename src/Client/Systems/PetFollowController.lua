--[[
    PetFollowController — CLIENT-side pet movement visualisation (issue #4).

    Smoothly positions the LOCAL player's pets every RenderStepped (full framerate
    -> no jerking). The server (PetFollowService) keeps damage + target authority
    and hands network ownership of each pet to this client, so PivotTo here moves
    pets smoothly and replicates to everyone. This is pure visualisation — no
    damage logic lives here.

    Follow: pets hold a config formation behind the player.
    Attack:  pets SURROUND the target in an animated ring (orbit / static_ring /
             lunge). Switch live with localPlayer:SetAttribute("PetAttackStyle", ...)
             for experimentation.

    Movement math is the shared pure core src/Shared/Game/PetFormation.lua.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PetFormation = require(ReplicatedStorage.Shared.Game.PetFormation)

local PetFollowController = {}

local localPlayer = Players.LocalPlayer

local function findBreakable(targetType, world, id)
    local breakables = Workspace:FindFirstChild("Game")
        and Workspace.Game:FindFirstChild("Breakables")
    if not breakables then
        return nil
    end
    local typeFolder = targetType and breakables:FindFirstChild(targetType)
    local scope = typeFolder and (typeFolder:FindFirstChild(world) or typeFolder)
    if not scope then
        return nil
    end
    for _, desc in ipairs(scope:GetDescendants()) do
        if desc.Name == "BreakableID" and desc:IsA("NumberValue") and desc.Value == id then
            return desc.Parent
        end
    end
    return nil
end

function PetFollowController.start()
    local config = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("pet_follow"))
    if not config.service_owned then
        return -- server still owns movement; controller stays idle
    end
    local startClock = os.clock()

    RunService.RenderStepped:Connect(function()
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local petsFolder = Workspace:FindFirstChild("PlayerPets")
            and Workspace.PlayerPets:FindFirstChild(localPlayer.Name)
        if not hrp or not petsFolder then
            return
        end

        local pets = {}
        for _, m in ipairs(petsFolder:GetChildren()) do
            if m:IsA("Model") and m.PrimaryPart then
                table.insert(pets, m)
            end
        end
        local count = #pets
        if count == 0 then
            return
        end

        local cf = hrp.CFrame
        local frame = {
            position = { x = cf.Position.X, y = cf.Position.Y, z = cf.Position.Z },
            look = { x = cf.LookVector.X, y = cf.LookVector.Y, z = cf.LookVector.Z },
            right = { x = cf.RightVector.X, y = cf.RightVector.Y, z = cf.RightVector.Z },
        }
        local phase = os.clock() - startClock
        local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
        local upFwd = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)

        local a = config.attack
        local style = localPlayer:GetAttribute("PetAttackStyle") or a.style
        local attackCfg = {
            style = style,
            ring_radius = a.ring_radius,
            ring_height = a.ring_height,
            orbit_speed = a.orbit_speed,
            lunge_distance = a.lunge_distance,
            lunge_speed = a.lunge_speed,
        }

        -- Split into attack groups (by target) and followers.
        local groups = {} -- id -> { center, pets = {} }
        local followers = {}
        for slot, pet in ipairs(pets) do
            local tid = pet:FindFirstChild("TargetID")
            local breakable = nil
            if tid and tid.Value ~= 0 then
                local tt = pet:FindFirstChild("TargetType")
                local tw = pet:FindFirstChild("TargetWorld")
                breakable = findBreakable(tt and tt.Value, tw and tw.Value, tid.Value)
            end
            if breakable then
                local g = groups[tid.Value]
                if not g then
                    g = { center = breakable:GetPivot().Position, pets = {} }
                    groups[tid.Value] = g
                end
                table.insert(g.pets, pet)
            else
                local posNV = pet:FindFirstChild("PositionNumber")
                local index = (posNV and posNV.Value > 0) and posNV.Value or slot
                table.insert(followers, { pet = pet, index = index })
            end
        end

        -- Followers: hold the formation slot behind the player.
        for _, f in ipairs(followers) do
            local t = PetFormation.targetPosition(frame, f.index, count, config.formation)
            local bob = PetFormation.floatOffset(phase + f.index, config.float)
            local target = Vector3.new(t.x, t.y + bob, t.z)
            local goal = CFrame.lookAt(target, target + upFwd)
            f.pet:PivotTo(f.pet:GetPivot():Lerp(goal, config.movement.follow_lerp))
        end

        -- Attackers: surround the target in an animated ring, facing the center.
        for _, g in pairs(groups) do
            local gcount = #g.pets
            for gi, pet in ipairs(g.pets) do
                local off = PetFormation.attackOffset(gi, gcount, phase, attackCfg)
                local target = g.center + Vector3.new(off.x, off.y, off.z)
                local toC = Vector3.new(g.center.X - target.X, 0, g.center.Z - target.Z)
                local dir = toC.Magnitude > 0.01 and toC.Unit or upFwd
                local goal = CFrame.lookAt(target, target + dir)
                pet:PivotTo(pet:GetPivot():Lerp(goal, config.movement.attack_lerp))
            end
        end
    end)
end

return PetFollowController
