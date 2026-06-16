--[[
    EggStandPlacement — put the right egg on every AUTHORED egg-hatcher stand, resolved by world +
    area (no per-stand config, no fabricated stands).

    A stand is an authored map Model with a `UIanchor` part. This script walks every world folder
    under `Workspace.Maps`, and for each stand inside it:
        • realm = WorldContext.parseName(world folder).realm   (Home -> base, Heaven_1 -> heaven…)
        • egg   = EggStandResolver.eggFor(realm, stand.Name, pets.realm_area_eggs)   (name carries
                  the area: "BasicIce" -> ice, "Lava" -> lava)
    then clones the loaded egg model (ReplicatedStorage.Assets.Models.Eggs[eggId]) and centers it
    UPRIGHT on the stand's anchor (yaw only — never inherit the stand's pitch/roll, which is what
    put the old fabricated stand's egg on its side). Purely visual placement; the placed egg is
    tagged `EggStand` + stamped `EggId` so the existing hatch/preview path picks it up.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local petConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("pets"))
local WorldContext = require(ReplicatedStorage.Shared.Game.WorldContext)
local EggStandResolver = require(ReplicatedStorage.Shared.Game.EggStandResolver)

local matrix = petConfig.realm_area_eggs
if type(matrix) ~= "table" or next(matrix) == nil then
    return
end
local defaults = petConfig.egg_stand_defaults or {}
local SCALE = defaults.scale or 1
local OFFSET_Y = defaults.offset_y or 0

-- An egg-hatcher stand is an authored Model carrying a `UIanchor` part (the egg-centering anchor).
local function isStand(inst)
    return inst:IsA("Model") and inst:FindFirstChild("UIanchor") ~= nil
end

-- Upright placement CFrame: the anchor's POSITION with YAW only, so the egg always stands up
-- regardless of how the stand mesh is tilted. Falls back to the model pivot if there's no anchor.
local function uprightCFrame(stand)
    local pos, yaw
    local anchor = stand:FindFirstChild("UIanchor")
    if anchor and anchor:IsA("BasePart") then
        pos = anchor.Position
        local _, y = anchor.CFrame:ToEulerAnglesYXZ()
        yaw = y
    else
        local ok, pivot = pcall(function()
            return stand:GetPivot()
        end)
        if ok then
            pos = pivot.Position
            local _, y = pivot:ToEulerAnglesYXZ()
            yaw = y
        end
    end
    if not pos then
        return nil
    end
    return CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)
end

local function placeEgg(stand, eggTemplate, eggId)
    local existing = stand:FindFirstChild("PlacedEgg")
    if existing then
        existing:Destroy()
    end
    local cf = uprightCFrame(stand)
    if not cf then
        return
    end
    if OFFSET_Y ~= 0 then
        cf = cf * CFrame.new(0, OFFSET_Y, 0)
    end
    local egg = eggTemplate:Clone()
    egg.Name = "PlacedEgg"
    for _, p in ipairs(egg:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Anchored = true
            p.CanCollide = false
            p.CanQuery = false
        end
    end
    if egg:IsA("Model") then
        if not egg.PrimaryPart then
            egg.PrimaryPart = egg:FindFirstChildWhichIsA("BasePart")
        end
        if SCALE ~= 1 then
            pcall(function()
                egg:ScaleTo(SCALE)
            end)
        end
        if egg.PrimaryPart then
            egg:PivotTo(cf)
        end
    elseif egg:IsA("BasePart") then
        if SCALE ~= 1 then
            egg.Size = egg.Size * SCALE
        end
        egg.CFrame = cf
    end
    egg.Parent = stand
    -- Make it a real, hatchable target (same wiring as before): tag + EggId register it in
    -- EggWorldQuery; stamp the EGG (not the stand) so proximity preview + hatch anchor on it.
    egg:SetAttribute("EggId", tostring(eggId))
    if not CollectionService:HasTag(egg, "EggStand") then
        CollectionService:AddTag(egg, "EggStand")
    end
    return egg
end

local eggsFolder =
    ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Eggs", 30)
if not eggsFolder then
    return
end
local maps = Workspace:WaitForChild("Maps", 30)
if not maps then
    return
end

-- Discover authored stands per world and place their resolved egg.
for _, world in ipairs(maps:GetChildren()) do
    local parsed = WorldContext.parseName(world.Name)
    local realm = parsed and parsed.realm
    if realm and type(matrix[realm]) == "table" then
        for _, inst in ipairs(world:GetDescendants()) do
            if isStand(inst) then
                local eggId = EggStandResolver.eggFor(realm, inst.Name, matrix)
                if eggId then
                    task.spawn(function()
                        local template = eggsFolder:WaitForChild(tostring(eggId), 30)
                        if template then
                            placeEgg(inst, template, eggId)
                        end
                    end)
                end
            end
        end
    end
end
