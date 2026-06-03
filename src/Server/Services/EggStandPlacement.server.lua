--[[
    EggStandPlacement — spawn an egg model centered inside a named map stand.

    Map "Egg hatcher" stands are decorative placeholders. configs/pets.lua `egg_stand_placements`
    maps a stand's NAME -> an egg_sources id; this script clones the loaded egg model
    (ReplicatedStorage.Assets.Models.Eggs[eggId], produced by AssetPreloadService) and centers it
    at the stand's `UIanchor` (or the model's pivot). No per-instance attributes or tags needed —
    just name the stand + egg in config. Purely visual placement (hatch wiring is separate).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local petConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("pets"))
local placements = petConfig.egg_stand_placements
if type(placements) ~= "table" or next(placements) == nil then
    return
end

-- First map instance matching `name` (Model or BasePart). nil if none.
local function findByName(name)
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == name and (d:IsA("Model") or d:IsA("BasePart")) then
            return d
        end
    end
    return nil
end

-- The CFrame to center the egg on: the stand's UIanchor part if present, else its pivot.
local function standCFrame(stand)
    local anchor = stand:FindFirstChild("UIanchor")
    if anchor and anchor:IsA("BasePart") then
        return anchor.CFrame
    end
    if stand:IsA("Model") then
        local ok, pivot = pcall(function()
            return stand:GetPivot()
        end)
        if ok then
            return pivot
        end
    elseif stand:IsA("BasePart") then
        return stand.CFrame
    end
    return nil
end

local function placeEgg(stand, eggTemplate, scale, offsetY)
    local existing = stand:FindFirstChild("PlacedEgg")
    if existing then
        existing:Destroy()
    end
    local cf = standCFrame(stand)
    if not cf then
        return
    end
    if offsetY and offsetY ~= 0 then
        cf = cf * CFrame.new(0, offsetY, 0)
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
        if scale and scale ~= 1 then
            pcall(function()
                egg:ScaleTo(scale)
            end)
        end
        if egg.PrimaryPart then
            egg:PivotTo(cf)
        end
    elseif egg:IsA("BasePart") then
        if scale and scale ~= 1 then
            egg.Size = egg.Size * scale
        end
        egg.CFrame = cf
    end
    egg.Parent = stand
end

local eggsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Eggs", 30)
if not eggsFolder then
    return
end

for standName, value in pairs(placements) do
    -- value is either an egg id string, or { egg, scale, offset_y } for tuning.
    local eggId, scale, offsetY
    if type(value) == "table" then
        eggId, scale, offsetY = value.egg, value.scale, value.offset_y
    else
        eggId = value
    end
    task.spawn(function()
        local template = eggsFolder:WaitForChild(tostring(eggId), 30)
        local stand = findByName(standName)
        if template and stand then
            placeEgg(stand, template, scale, offsetY)
        end
    end)
end
