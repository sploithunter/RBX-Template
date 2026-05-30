--[[
    PetFollowService — server authority for the pet work loop (issue #4 retry).

    Responsibilities (SERVER ONLY):
      - Make pets non-falling: ANCHOR each pet's parts. Anchored parts obey no
        gravity/physics, so a pet can never drift or fall off the map (the bug the
        legacy teleport-watchdog existed to patch). The client positions them
        kinematically via PivotTo (see PetFollowController).
      - Mining damage tick: read each pet's TargetID, apply damage to the breakable
        via CombatService:ResolvePetDamage + PetCombat (Contrib ledger).
      - Target leash: clear TargetID when the player walks beyond leash_distance so
        the pet returns to following (BreakableService re-assigns when near).

    Movement/visualisation is CLIENT-side (src/Client/Systems/PetFollowController.lua),
    which sets each pet's CFrame every RenderStepped for smooth, never-falling
    motion. Damage stays server-authoritative. Multiplayer position replication
    (other clients seeing a player's pets move) is a documented follow-up.

    Gated on configs/pet_follow.lua `service_owned`.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PetCombat = require(ReplicatedStorage.Shared.Game.PetCombat)

local PetFollowService = {}
PetFollowService.__index = PetFollowService

function PetFollowService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._config = self._configLoader:LoadConfig("pet_follow")
    self._nextHit = {} -- pet model -> os.clock() of next allowed mining hit
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
            self._logger:Info("PetFollowService inert (pet_follow.service_owned=false)")
        end
        return
    end
    _G.PetFollowServiceOwned = true -- legacy cloned scripts stand down
    if self._logger then
        self._logger:Info(
            "PetFollowService active — anchored pets, client-driven movement, server damage"
        )
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

-- Anchor every part so the pet can't fall/drift (the client moves it via PivotTo).
-- Strips any stale movement constraints from earlier builds. Once per pet.
function PetFollowService:_prepPet(pet)
    if pet:GetAttribute("PetFollowPrepped") then
        return
    end
    for _, name in ipairs({ "_FollowAlign", "_FollowAlignO", "align", "alignO" }) do
        local c = pet:FindFirstChild(name)
        if c then
            c:Destroy()
        end
    end
    for _, d in ipairs(pet:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
        end
    end
    pet:SetAttribute("PetFollowPrepped", true)
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

-- One mining hit on the pet's current target (server-authoritative damage).
function PetFollowService:_mine(player, pet, breakable)
    local now = os.clock()
    if self._nextHit[pet] and now < self._nextHit[pet] then
        return
    end
    local combat = self:_combatService()
    if not combat then
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
    local leash = self._config.attack.leash_distance

    for _, pet in ipairs(petsFolder:GetChildren()) do
        if pet:IsA("Model") and pet.PrimaryPart then
            self:_prepPet(pet)
            local targetId = pet:FindFirstChild("TargetID")
            if targetId and targetId.Value ~= 0 then
                local targetType = pet:FindFirstChild("TargetType")
                local targetWorld = pet:FindFirstChild("TargetWorld")
                local breakable = self:_findBreakable(
                    targetType and targetType.Value,
                    targetWorld and targetWorld.Value,
                    targetId.Value
                )
                if
                    not breakable
                    or (breakable:GetPivot().Position - hrp.Position).Magnitude > leash
                then
                    targetId.Value = 0 -- abandon gone/distant target -> follow
                else
                    self:_mine(player, pet, breakable)
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
