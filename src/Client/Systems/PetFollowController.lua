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
local Gait = require(ReplicatedStorage.Shared.Game.Gait)
local AttackAnim = require(ReplicatedStorage.Shared.Game.AttackAnim)
local EnchantLightning = require(ReplicatedStorage.Shared.Effects.EnchantLightning)
local PetRoles = require(ReplicatedStorage.Configs:WaitForChild("pet_roles"))
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

-- A pet's combat role (matches SquadHud): PetRole attr -> by_type[PetType] -> default.
local function petRoleId(pet)
    return pet:GetAttribute("PetRole")
        or (PetRoles.by_type and PetRoles.by_type[pet:GetAttribute("PetType")])
        or PetRoles.default
end

-- Studs the pet holds back from its target in the attack formation (role.standoff).
local function roleStandoff(pet)
    local def = PetRoles.roles and PetRoles.roles[petRoleId(pet)]
    return (def and tonumber(def.standoff)) or 0
end

-- Kiters (role.kite) hold their player-formation slot and snipe rather than orbiting the
-- target, so a chasing enemy must close on them instead of drifting with the orbit.
local function roleKites(pet)
    local def = PetRoles.roles and PetRoles.roles[petRoleId(pet)]
    return def and def.kite == true
end

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
    local game = Workspace:FindFirstChild("Game")
    if not game then
        return nil
    end
    if targetType == "Enemy" then
        local enemies = game:FindFirstChild("Enemies")
        if not enemies then
            return nil
        end
        for _, desc in ipairs(enemies:GetDescendants()) do
            if desc.Name == "BreakableID" and desc:IsA("NumberValue") and desc.Value == id then
                return desc.Parent
            end
        end
        return nil
    end
    local breakables = game:FindFirstChild("Breakables")
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

    -- Procedural walk gait (shared with enemies — src/Shared/Game/Gait.lua). Resolved
    -- per PetType (gait_by_type override merged over the default), cached. baseCF holds
    -- each pet's CLEAN target pivot (no gait) so the lerp + position report never feed
    -- the bob/tilt back into themselves; gaitState carries the per-pet phase/amplitude.
    local defaultGait = config.gait or {}
    local gaitByType = config.gait_by_type or {}
    local gaitCache = {}
    local function resolveGait(petType)
        local key = petType or "_default"
        local cached = gaitCache[key]
        if cached then
            return cached
        end
        local g = Gait.resolve(defaultGait, gaitByType[petType])
        gaitCache[key] = g
        return g
    end
    local baseCF = setmetatable({}, { __mode = "k" }) -- pet model -> clean CFrame (no gait)
    local gaitState = setmetatable({}, { __mode = "k" }) -- pet model -> { phase, amp }
    local attackTimer = setmetatable({}, { __mode = "k" }) -- pet model -> { t } (attack-anim clock)

    -- Attack flourishes (layered like the gait): one per target type, resolved once.
    -- mining = breakables/ore (spin), combat = enemies (face for now). See AttackAnim.
    local animCfg = (config.attack and config.attack.anim) or {}
    local miningAnim = AttackAnim.resolve(animCfg.mining)
    local combatAnim = AttackAnim.resolve(animCfg.combat)

    -- Facing tuning: turn toward the heading when moving faster than this, else rest facing.
    local faceTurnRate = (config.movement and config.movement.face_turn_rate) or 12
    local faceMoveSpeed = (config.movement and config.movement.face_move_speed) or 2

    -- Ranged pets fire a cosmetic lightning bolt at their target on a cadence. Clone the
    -- config and rebuild target_offset as a Vector3 (stored as {x,y,z} so the config can
    -- be required headless, where Vector3 doesn't exist).
    local boltCfg = table.clone(config.ranged_bolt or {})
    local boltInterval = boltCfg.interval or 0.55
    local castLockSeconds = boltCfg.cast_lock_seconds or 0
    if type(boltCfg.target_offset) == "table" then
        local o = boltCfg.target_offset
        boltCfg.target_offset = Vector3.new(o[1] or 0, o[2] or 0, o[3] or 0)
    end
    local nextBolt = setmetatable({}, { __mode = "k" }) -- pet model -> next os.clock to fire
    -- Cast-lock: a ranged pet that just fired can't move until this clock — a melee enemy
    -- gets a window to close the gap (counterplay to kiting).
    local castLockUntil = setmetatable({}, { __mode = "k" })

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

        -- Downed pets are OUT of the fight: hide them (client-only LocalTransparencyModifier
        -- so we never touch base Transparency) + any billboards, and skip positioning them.
        -- They reappear when the player summons them (server clears CombatDowned).
        local pets = {}
        for _, m in ipairs(petsFolder:GetChildren()) do
            if m:IsA("Model") and m.PrimaryPart then
                local downed = m:GetAttribute("CombatDowned")
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("BasePart") then
                        d.LocalTransparencyModifier = downed and 1 or 0
                    elseif d:IsA("BillboardGui") then
                        d.Enabled = not downed
                    end
                end
                if not downed then
                    table.insert(pets, m)
                end
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
        local maxTravel = config.movement.max_travel_speed
        local playerSpeed = localPlayer:GetAttribute("PetMoveSpeed")

        -- Move a pet toward its goal at `baseRate` smoothing, scaled by its move-speed
        -- multiplier. Snap if catastrophically far (the player teleported). Otherwise
        -- smooth-lerp BUT cap the per-frame travel to max_travel_speed*mult so a pet
        -- flies over to a new target at a bounded speed instead of teleporting onto it
        -- (the exponential lerp alone covers any distance almost instantly). Orientation
        -- still uses the full lerp; only linear position is capped.
        local catchupDist = config.movement.catchup_distance

        -- Pick this frame's HEADING: face the way the pet is actually moving when it's
        -- travelling above face_move_speed (so it heads forward instead of sliding), else
        -- settle onto restDir (player-forward following / the target when attacking). The
        -- turn is eased so it never snaps. Returns a horizontal unit Vector3.
        local function facingFor(cur, curPos, newPos, restDir)
            local moveVec = Vector3.new(newPos.X - curPos.X, 0, newPos.Z - curPos.Z)
            local speed = moveVec.Magnitude / math.max(dt, 1e-3)
            local desired
            if speed > faceMoveSpeed and moveVec.Magnitude > 1e-4 then
                desired = moveVec.Unit
            elseif restDir and restDir.Magnitude > 1e-4 then
                desired = restDir.Unit
            end
            local curLook = Vector3.new(cur.LookVector.X, 0, cur.LookVector.Z)
            curLook = (curLook.Magnitude > 1e-4) and curLook.Unit or upFwd
            if not desired then
                return curLook
            end
            local turnAlpha = 1 - math.exp(-faceTurnRate * dt)
            local newLook = curLook:Lerp(desired, turnAlpha)
            return (newLook.Magnitude > 1e-4) and newLook.Unit or desired
        end

        -- Store the clean (gait-free, anim-free) pivot, then PivotTo with the walk gait AND
        -- any attack flourish layered on. Keeping baseCF clean means neither feeds back into
        -- the lerp or the position report. `anim` is a resolved AttackAnim (or nil to follow).
        local function applyMotion(model, cleanPivot, stepDist, anim)
            baseCF[model] = cleanPivot
            local st = gaitState[model]
            if not st then
                st = { phase = 0, amp = 0 }
                gaitState[model] = st
            end
            local gait = resolveGait(model:GetAttribute("PetType"))
            local bob, roll, yaw = Gait.advance(st, gait, stepDist, dt)

            -- Attack flourish (spin / pounce). Resets its clock when the pet stops attacking.
            local aYaw, aLunge, aBob = 0, 0, 0
            if anim and anim.enabled then
                local ts = attackTimer[model]
                if not ts then
                    ts = { t = 0 }
                    attackTimer[model] = ts
                end
                aYaw, aLunge, aBob = AttackAnim.advance(ts, anim, dt)
            else
                attackTimer[model] = nil
            end

            local pivot = cleanPivot
            if aLunge ~= 0 then
                pivot = cleanPivot * CFrame.new(0, 0, -aLunge) -- jab forward toward the faced target
            end
            model:PivotTo(CFrame.new(0, bob + aBob, 0) * pivot * CFrame.Angles(0, yaw + aYaw, roll))
        end

        -- Move a pet toward goalPos (Vector3), facing its heading while moving / restDir at
        -- rest, at baseRate smoothing scaled by move speed. `anim` (optional) layers a flourish.
        local function moveToward(model, goalPos, restDir, baseRate, anim)
            -- Cast-locked (just-fired ranged pet): hold position so it can't kite freely, but
            -- keep facing its target (restDir) so it still aims at its prey while "casting".
            if castLockUntil[model] and dt and os.clock() < castLockUntil[model] then
                local cur = baseCF[model] or model:GetPivot()
                local face = facingFor(cur, cur.Position, cur.Position, restDir)
                applyMotion(model, CFrame.lookAt(cur.Position, cur.Position + face), 0, anim)
                return
            end
            local mult = PetFormation.moveSpeedMultiplier(
                playerSpeed,
                model:GetAttribute("MoveSpeedMult"),
                speedCfg
            )
            local cur = baseCF[model] or model:GetPivot()
            local curPos = cur.Position
            if PetFormation.shouldSnap((curPos - goalPos).Magnitude, catchupDist) then
                local face = (restDir and restDir.Magnitude > 1e-4) and restDir.Unit or upFwd
                applyMotion(model, CFrame.lookAt(goalPos, goalPos + face), 0, anim) -- teleport
                return
            end
            local alpha = 1 - math.exp(-(baseRate * mult) * dt)
            local newPos = curPos:Lerp(goalPos, alpha)
            if maxTravel and maxTravel > 0 then
                local step = newPos - curPos
                local maxStep = maxTravel * mult * dt
                if step.Magnitude > maxStep then
                    newPos = curPos + step.Unit * maxStep
                end
            end
            local face = facingFor(cur, curPos, newPos, restDir)
            local cleanPivot = CFrame.lookAt(newPos, newPos + face)
            local stepDist =
                (Vector3.new(newPos.X, 0, newPos.Z) - Vector3.new(curPos.X, 0, curPos.Z)).Magnitude
            applyMotion(model, cleanPivot, stepDist, anim)
        end

        -- Full attack config (so every style's params reach attackOffset) with the player's
        -- saved/live PetAttackStyle override.
        local attackCfg = table.clone(config.attack)
        attackCfg.style = localPlayer:GetAttribute("PetAttackStyle") or config.attack.style

        local groups = {} -- id -> { center, pets = {} }   (melee/tank: orbit the target)
        local followers = {}
        local kiters = {} -- ranged: hold player formation + snipe the target
        local kiterFace = {} -- kiter pet -> its target model (so it faces what it snipes)
        for slot, pet in ipairs(pets) do
            local tid = pet:FindFirstChild("TargetID")
            local breakable = nil
            if tid and tid.Value ~= 0 then
                local tt = pet:FindFirstChild("TargetType")
                local tw = pet:FindFirstChild("TargetWorld")
                breakable = findBreakable(tt and tt.Value, tw and tw.Value, tid.Value)
            end
            local posNV = pet:FindFirstChild("PositionNumber")
            local index = (posNV and posNV.Value > 0) and posNV.Value or slot
            if breakable and roleKites(pet) then
                -- Ranged: stays in the player formation (so a chasing enemy must close on
                -- it) and fires from there — but faces the target it's sniping.
                table.insert(followers, { pet = pet, index = index })
                table.insert(kiters, { pet = pet, model = breakable })
                kiterFace[pet] = breakable
            elseif breakable then
                local g = groups[tid.Value]
                if not g then
                    g = {
                        center = breakable:GetPivot().Position,
                        model = breakable,
                        isEnemy = breakable:GetAttribute("IsEnemy") == true,
                        pets = {},
                    }
                    groups[tid.Value] = g
                end
                table.insert(g.pets, pet)
            else
                table.insert(followers, { pet = pet, index = index })
            end
        end

        -- A follower's rest facing: player-forward, unless it's a ranged kiter — then it
        -- faces the target it's firing on (computed per pet from its world position).
        local function followerRestDir(pet, targetPos)
            local kt = kiterFace[pet]
            if kt and kt.Parent and kt.PrimaryPart then
                local p = kt:GetPivot().Position
                local d = Vector3.new(p.X - targetPos.X, 0, p.Z - targetPos.Z)
                if d.Magnitude > 1e-3 then
                    return d.Unit
                end
            end
            return upFwd
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
                moveToward(model, target, followerRestDir(model, target), followRate)
            end
        else
            for _, f in ipairs(followers) do
                local t = PetFormation.targetPosition(frame, f.index, count, config.formation)
                local bob = PetFormation.floatOffset(phase + f.index, config.float)
                local target = Vector3.new(t.x, t.y + bob, t.z)
                moveToward(f.pet, target, followerRestDir(f.pet, target), followRate)
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
                -- Role standoff: ranged/support hold further out (push the slot radially
                -- away from the target) so melee crowds in and ranged kites at distance.
                local standoff = roleStandoff(pet)
                if standoff > 0 then
                    local horiz = Vector3.new(off.x, 0, off.z)
                    if horiz.Magnitude > 0.01 then
                        local pushed = horiz + horiz.Unit * standoff
                        off = { x = pushed.X, y = off.y, z = pushed.Z }
                    end
                end
                local target = g.center + Vector3.new(off.x, off.y, off.z)
                local toC = Vector3.new(g.center.X - target.X, 0, g.center.Z - target.Z)
                local dir = toC.Magnitude > 0.01 and toC.Unit or upFwd
                -- Mining (breakables) spins; combat (enemies) faces the target. The flourish
                -- layers on the facing — a spinning pet still orients to its prey underneath.
                local anim = g.isEnemy and combatAnim or miningAnim
                moveToward(pet, target, dir, attackRate, anim)
            end
        end

        -- Kiters (ranged): held in the player formation above; fire the enchanter
        -- lightning bolt at their target on cadence from wherever they're standing.
        if boltCfg.enabled ~= false then
            local nowC = os.clock()
            for _, k in ipairs(kiters) do
                if k.model and k.model.Parent then
                    if not nextBolt[k.pet] or nowC >= nextBolt[k.pet] then
                        nextBolt[k.pet] = nowC + boltInterval
                        if castLockSeconds > 0 then
                            castLockUntil[k.pet] = nowC + castLockSeconds
                        end
                        pcall(EnchantLightning.Play, k.pet, boltCfg, k.model)
                    end
                end
            end
        end

        -- Throttled: report this player's pet positions to the server (drives the mining gate;
        -- foundation for multiplayer pet visibility). Positions are post-move (this frame).
        reportAccum += dt
        if reportAccum >= reportInterval then
            reportAccum = 0
            local report = {}
            for _, m in ipairs(pets) do
                -- Report the clean base (no gait bob/tilt) so the server mining gate
                -- measures true position, not the cosmetic waddle offset.
                report[#report + 1] = { pet = m, cf = baseCF[m] or m:GetPivot() }
            end
            Signals.PetReportPositions:FireServer(report)
        end
    end)
end

return PetFollowController
