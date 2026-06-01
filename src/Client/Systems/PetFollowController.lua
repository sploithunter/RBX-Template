--[[
    PetFollowController — CLIENT-side pet movement visualisation (issue #4 retry).

    Positions the local player's pets every RenderStepped (full framerate -> smooth,
    no jerk). Pets are ANCHORED by the server (PetFollowService), so they can never
    fall/drift — this controller just sets their CFrame kinematically each frame,
    lerping toward a moving target (momentum feel; frame-rate independent).

    Follow:  pets hold a config formation behind the player.
    Attack:  pets SURROUND the target in an animated ring (orbit/static_ring/lunge).
             Switch live with localPlayer:SetAttribute("PetAttackStyle", "lunge").

    Damage + target assignment are server-side; this is pure visualisation. Other
    clients seeing a player's pets move (position replication) is a documented
    follow-up; this drives the LOCAL player's view.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PetFormation = require(ReplicatedStorage.Shared.Game.PetFormation)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local PetFollowController = {}

local localPlayer = Players.LocalPlayer

-- Per-pet footprint (studs) for size-aware formations — the model's larger XZ extent, so huge
-- pets read bigger. Measured ONCE and stamped on the pet (an attribute persists for the model's
-- life), then QUANTIZED to 0.1 studs. Both matter: pet idle animations make GetExtentsSize
-- breathe by a hair, so two identical pets read minutely different + fluctuating extents — left
-- raw, that made the size-sort flip them frame to frame (the "swapping" bug). Quantizing collapses
-- identical pets to the exact same value so the stable tiebreak (equip slot) wins; stamping keeps
-- it from ever being recomputed.
local function petFootprint(pet, config)
    local stored = pet:GetAttribute("PetFootprint")
    if stored then
        return stored
    end
    local f
    local ok, ext = pcall(function()
        return pet:GetExtentsSize()
    end)
    if ok and ext then
        f = math.max(ext.X, ext.Z)
    end
    if not f or f <= 0 then
        f = (config.formation.size and config.formation.size.default_footprint) or 4
    end
    f = math.floor(f * 10 + 0.5) / 10 -- quantize to 0.1 stud
    pet:SetAttribute("PetFootprint", f)
    return f
end

-- Stable per-pet ordering key (the equip slot). Distinct + stable per equipped pet, so sorts
-- that tie on size (identical pets) stay deterministic instead of swapping frame to frame.
local function petSlot(pet)
    local n = pet:FindFirstChild("PositionNumber")
    return (n and n.Value) or 0
end

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
        return -- legacy scripts own movement; controller idle
    end
    local startClock = os.clock()
    local reportAccum = 0
    local reportInterval = (config.replication and config.replication.interval) or 0.1

    -- OTHER players' pets, server-relayed (the server never relays our own — those stay local).
    local remoteTargets = setmetatable({}, { __mode = "k" }) -- pet model -> latest relayed CFrame
    Signals.PetPositionsRelay.OnClientEvent:Connect(function(list)
        if type(list) ~= "table" then
            return
        end
        for _, e in ipairs(list) do
            if type(e) == "table" and typeof(e.pet) == "Instance" and typeof(e.cf) == "CFrame" then
                remoteTargets[e.pet] = e.cf
            end
        end
    end)

    RunService.RenderStepped:Connect(function(dt)
        -- Smooth OTHER players' pets toward their relayed transforms (always, even if we have no
        -- pets of our own). Our own pets are handled below, purely locally.
        local remoteAlpha = 1 - math.exp(-(config.movement.remote_lerp_rate or 14) * dt)
        for pet, targetCf in pairs(remoteTargets) do
            if pet.Parent and pet:IsA("Model") and pet.PrimaryPart then
                pet:PivotTo(pet:GetPivot():Lerp(targetCf, remoteAlpha))
            else
                remoteTargets[pet] = nil
            end
        end

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

        -- Frame-rate-independent smoothing (momentum feel), scaled per pet by move speed:
        -- the player's PetMoveSpeed stat times the pet's optional MoveSpeedMult. Higher = the
        -- pet catches its slot / repositions faster.
        local followRate = config.movement.follow_lerp_rate or 10
        local attackRate = config.movement.attack_lerp_rate or 16
        local speedCfg = config.movement.speed
        local playerSpeed = localPlayer:GetAttribute("PetMoveSpeed")
        local function alphaFor(baseRate, pet)
            local mult = PetFormation.moveSpeedMultiplier(
                playerSpeed,
                pet:GetAttribute("MoveSpeedMult"),
                speedCfg
            )
            return 1 - math.exp(-(baseRate * mult) * dt)
        end

        -- Move a pet toward its goal, snapping if it's catastrophically far (the player
        -- teleported) instead of crawling across the map; otherwise smooth-lerp.
        local catchupDist = config.movement.catchup_distance
        local function moveToward(model, goal, alpha)
            local cur = model:GetPivot()
            if PetFormation.shouldSnap((cur.Position - goal.Position).Magnitude, catchupDist) then
                model:PivotTo(goal)
            else
                model:PivotTo(cur:Lerp(goal, alpha))
            end
        end

        -- Full attack config (so every style's params reach attackOffset) with the player's
        -- saved/live PetAttackStyle override.
        local attackCfg = table.clone(config.attack)
        attackCfg.style = localPlayer:GetAttribute("PetAttackStyle") or config.attack.style

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
        -- Mode comes from the player's saved setting (PetFormationMode attribute, stage 3) or the
        -- config default. The size-aware modes sort by footprint + scale spacing via resolve();
        -- anything else falls back to the legacy index-based path.
        local mode = localPlayer:GetAttribute("PetFormationMode") or config.formation.default_mode
        local sizeAware = mode == "conga" or mode == "risers" or mode == "arc"

        if sizeAware and #followers > 0 then
            -- Stable input order by equip slot so equal-size pets keep a deterministic order.
            table.sort(followers, function(lhs, rhs)
                return lhs.index < rhs.index
            end)
            local input = {}
            for _, f in ipairs(followers) do
                input[#input + 1] = { model = f.pet, footprint = petFootprint(f.pet, config) }
            end
            local fm = table.clone(config.formation)
            fm.mode = mode
            local placed = PetFormation.resolve(input, fm)
            for slot, e in ipairs(placed) do
                local model = e.pet.model
                local t = PetFormation.toWorld(frame, e.offset)
                local bob = PetFormation.floatOffset(phase + slot, config.float)
                local target = Vector3.new(t.x, t.y + bob, t.z)
                local goal = CFrame.lookAt(target, target + upFwd)
                moveToward(model, goal, alphaFor(followRate, model))
            end
        else
            for _, f in ipairs(followers) do
                local t = PetFormation.targetPosition(frame, f.index, count, config.formation)
                local bob = PetFormation.floatOffset(phase + f.index, config.float)
                local target = Vector3.new(t.x, t.y + bob, t.z)
                local goal = CFrame.lookAt(target, target + upFwd)
                moveToward(f.pet, goal, alphaFor(followRate, f.pet))
            end
        end

        -- Attackers: arrange around the target per the attack style, facing the center.
        for _, g in pairs(groups) do
            -- smallest -> first slot, so huge pets take the outer slots (spiral arm / line ends).
            -- Tiebreak by equip slot so identical pets keep a fixed order (no frame-to-frame swap).
            table.sort(g.pets, function(p1, p2)
                local f1, f2 = petFootprint(p1, config), petFootprint(p2, config)
                if f1 ~= f2 then
                    return f1 < f2
                end
                return petSlot(p1) < petSlot(p2)
            end)
            local gcount = #g.pets
            for gi, pet in ipairs(g.pets) do
                local off = PetFormation.attackOffset(gi, gcount, phase, attackCfg)
                local target = g.center + Vector3.new(off.x, off.y, off.z)
                local toC = Vector3.new(g.center.X - target.X, 0, g.center.Z - target.Z)
                local dir = toC.Magnitude > 0.01 and toC.Unit or upFwd
                local goal = CFrame.lookAt(target, target + dir)
                moveToward(pet, goal, alphaFor(attackRate, pet))
            end
        end

        -- Throttled: report this player's pet positions to the server (drives the mining gate;
        -- foundation for multiplayer pet visibility). Positions are post-move (this frame).
        reportAccum += dt
        if reportAccum >= reportInterval then
            reportAccum = 0
            local report = {}
            for _, m in ipairs(pets) do
                report[#report + 1] = { pet = m, cf = m:GetPivot() }
            end
            Signals.PetReportPositions:FireServer(report)
        end
    end)
end

return PetFollowController
