--[[
    PetFollowService — Feature: service-owned pet work loop (issue #4).

    Replaces the legacy cloned per-pet PetScripts/Follow + FollowBox scripts with a
    single server-owned, config-driven loop. Movement is computed by the pure
    `PetFormation` core; damage flows through `CombatService:ResolvePetDamage`
    (the modifier pipeline + PetCombat, built in Phase 4.d). No behavior lives in
    cloned per-model scripts.

    ROLLOUT FLAG: the entire loop only runs when `configs/pet_follow.lua`
    `service_owned == true`. While false the service is inert and the legacy
    cloned scripts drive movement exactly as before (flag-gated, reversible).

    Runtime contract preserved: pets remain Models under workspace.PlayerPets[name]
    with PositionNumber / TargetID / TargetType / TargetWorld / Power and the
    PetType/PetVariant attributes; TargetID is assigned externally (BreakableService
    / BreakableSpawner) and read here (==0 follow, ~=0 attack a breakable, HP +
    Contrib ledger).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PetFormation = require(ReplicatedStorage.Shared.Game.PetFormation)
local PetCombat = require(ReplicatedStorage.Shared.Game.PetCombat)

local PetFollowService = {}
PetFollowService.__index = PetFollowService

function PetFollowService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._config = self._configLoader:LoadConfig("pet_follow")
    self._nextHit = {} -- pet model -> os.clock() of next allowed mining hit
    self._started = 0 -- service start clock (for the float phase)
end

function PetFollowService:_combatService()
    local locator = _G.RBXTemplateServices
    if not locator then
        return nil
    end
    local ok, service = pcall(function()
        return locator:Get("CombatService")
    end)
    return ok and service or nil
end

function PetFollowService:Start()
    if not self._config.service_owned then
        if self._logger then
            self._logger:Info(
                "PetFollowService inert (pet_follow.service_owned=false); legacy scripts own movement"
            )
        end
        return
    end
    self._started = os.clock()
    -- Signal the legacy cloned scripts (Follow/FollowBox) to stand down — they
    -- read this flag at the top and no-op, so this service owns movement.
    _G.PetFollowServiceOwned = true
    if self._logger then
        self._logger:Info("PetFollowService active — owning the pet follow loop")
    end
    local accum = 0
    RunService.Heartbeat:Connect(function(dt)
        accum += dt
        if accum < self._config.update_interval then
            return
        end
        accum = 0
        pcall(function()
            self:_tick()
        end)
    end)
end

-- One position attachment + Align constraints per pet, created lazily and reused.
function PetFollowService:_ensureConstraints(pet)
    local primary = pet.PrimaryPart
    if not primary then
        return nil
    end
    local att = primary:FindFirstChild("attachmentPet")
    if not att then
        att = Instance.new("Attachment")
        att.Name = "attachmentPet"
        att.Parent = primary
    end
    local align = pet:FindFirstChild("_FollowAlign")
    if not align then
        align = Instance.new("AlignPosition")
        align.Name = "_FollowAlign"
        align.Mode = Enum.PositionAlignmentMode.OneAttachment
        align.Attachment0 = att
        align.RigidityEnabled = false
        align.MaxForce = self._config.align.follow_max_force
        align.Responsiveness = self._config.align.follow_responsiveness
        align.Parent = pet
    end
    local alignO = pet:FindFirstChild("_FollowAlignO")
    if not alignO then
        alignO = Instance.new("AlignOrientation")
        alignO.Name = "_FollowAlignO"
        alignO.Mode = Enum.OrientationAlignmentMode.OneAttachment
        alignO.Attachment0 = att
        alignO.RigidityEnabled = false
        alignO.Responsiveness = self._config.align.follow_responsiveness
        alignO.Parent = pet
    end
    if primary.Anchored then
        primary.Anchored = false
    end
    return align, alignO
end

-- Locate a breakable Model by id under its type/world folder (any nesting depth).
function PetFollowService:_findBreakable(targetType, world, id)
    local breakables = Workspace:FindFirstChild("Game")
        and Workspace.Game:FindFirstChild("Breakables")
    if not breakables then
        return nil
    end
    local typeFolder = breakables:FindFirstChild(targetType)
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

-- Apply one mining hit to the pet's current breakable target (position-independent,
-- mirrors the legacy doDamage but routed through the service-owned damage path).
function PetFollowService:_mine(player, pet)
    local targetId = pet:FindFirstChild("TargetID")
    if not targetId or targetId.Value == 0 then
        return
    end
    local now = os.clock()
    if self._nextHit[pet] and now < self._nextHit[pet] then
        return
    end
    local targetType = pet:FindFirstChild("TargetType")
    local targetWorld = pet:FindFirstChild("TargetWorld")
    local breakable = self:_findBreakable(
        targetType and targetType.Value,
        targetWorld and targetWorld.Value,
        targetId.Value
    )
    local combat = self:_combatService()
    if not breakable or not combat then
        return
    end
    local hp = breakable:GetAttribute("HP") or 0
    if hp <= 0 then
        return
    end
    local powerNV = pet:FindFirstChild("Power")
    local ctx = {
        power = tonumber(powerNV and powerNV.Value) or 1,
        petId = pet:GetAttribute("PetType"),
        variant = pet:GetAttribute("PetVariant"),
        breakableId = breakable:GetAttribute("BreakableId"),
        currency = breakable:GetAttribute("Currency"),
    }
    local dmg = combat:ResolvePetDamage(player, ctx)
    local applied = PetCombat.applyDamage(hp, dmg)
    breakable:SetAttribute("HP", applied.hp)

    local contrib = breakable:FindFirstChild("Contrib")
    if contrib then
        local key = tostring(player.UserId)
        local nv = contrib:FindFirstChild(key)
        if not nv then
            nv = Instance.new("NumberValue")
            nv.Name = key
            nv.Parent = contrib
        end
        nv.Value += applied.contributed
    end

    self._nextHit[pet] = now + combat:ResolvePetAttackInterval(player, ctx)
end

function PetFollowService:_tickPlayer(player)
    local character = player.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local petsFolder = Workspace:FindFirstChild("PlayerPets")
        and Workspace.PlayerPets:FindFirstChild(player.Name)
    if not hrp or not petsFolder then
        return
    end

    local pets = {}
    for _, child in ipairs(petsFolder:GetChildren()) do
        if child:IsA("Model") and child.PrimaryPart then
            table.insert(pets, child)
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
    local phase = os.clock() - self._started

    for slot, pet in ipairs(pets) do
        local posNV = pet:FindFirstChild("PositionNumber")
        local index = (posNV and posNV.Value > 0) and posNV.Value or slot
        local align, alignO = self:_ensureConstraints(pet)
        if align then
            local targetId = pet:FindFirstChild("TargetID")
            if targetId and targetId.Value ~= 0 then
                -- attack mode: sit near the breakable, and mine it
                local targetType = pet:FindFirstChild("TargetType")
                local targetWorld = pet:FindFirstChild("TargetWorld")
                local breakable = self:_findBreakable(
                    targetType and targetType.Value,
                    targetWorld and targetWorld.Value,
                    targetId.Value
                )
                if breakable then
                    local bpos = breakable:GetPivot().Position
                    align.Position = bpos + Vector3.new(0, self._config.attack.approach_distance, 0)
                end
                self:_mine(player, pet)
            else
                -- follow mode: hold the formation slot (with a gentle bob)
                local t = PetFormation.targetPosition(frame, index, count, self._config.formation)
                local bob = PetFormation.floatOffset(phase + index, self._config.float)
                align.Position = Vector3.new(t.x, t.y + bob, t.z)
                if alignO then
                    alignO.CFrame = CFrame.lookAt(
                        Vector3.new(t.x, t.y, t.z),
                        Vector3.new(t.x, t.y, t.z) + cf.LookVector
                    )
                end
            end
        end
    end
end

function PetFollowService:_tick()
    for _, player in ipairs(Players:GetPlayers()) do
        self:_tickPlayer(player)
    end
end

return PetFollowService
