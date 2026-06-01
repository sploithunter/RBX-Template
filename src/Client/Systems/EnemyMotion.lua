--[[
    EnemyMotion — CLIENT-side smoothing + procedural walk gait for enemies (Feature 10).

    EnemyService moves each enemy server-side in ~update_interval steps (the server is
    authoritative — entry.pos / the MoveTarget attribute drives the mining gate). It no
    longer pivots the model, so the client fully owns the visible CFrame:

      1) SMOOTHING — lerp the model toward the server's MoveTarget every RenderStepped,
         so chasing reads smooth despite the coarse server tick.
      2) GAIT — these enemies are rig-less single-mesh models, so there's no skeletal
         animation. Instead we layer a procedural motion on the smoothed base CFrame,
         driven by distance travelled (so it scales with speed and rests when still).

    The gait is per-enemy: combat.engagement.gait is the default and each enemy in
    configs/enemies.lua can override any field via its own `gait = {...}`, so different
    pets move differently. `style` picks the motion SHAPE (see STYLES below).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyMotion = {}

local TWO_PI = math.pi * 2

-- Each style maps the gait phase p (0..2π, advances with distance) to normalised
-- (bob, roll, yaw) in [-1,1]; the resolved gait scales bob by bob_height and roll/yaw
-- by tilt_degrees. bob = world-up bounce; roll = bank about facing; yaw = heading wiggle.
local STYLES = {
    -- bob 2x/stride (down at p=0), bank 1x/stride: down->L->up->down->R->up.
    waddle = function(p)
        return -math.cos(2 * p), math.sin(p), 0
    end,
    -- stiff vertical stomp, no tilt.
    march = function(p)
        return -math.cos(2 * p), 0, 0
    end,
    -- one big bounce per stride, no tilt.
    hop = function(p)
        return -math.cos(p), 0, 0
    end,
    -- no bob; heading wiggles left/right like a snake.
    slither = function(p)
        return 0, 0, math.sin(p)
    end,
}

local function enemiesFolder()
    local game = Workspace:FindFirstChild("Game")
    return game and game:FindFirstChild("Enemies")
end

function EnemyMotion.start()
    local petCfg = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("pet_follow"))
    if not petCfg.service_owned then
        return -- legacy path owns movement; this layer is inert
    end
    local combat = require(ReplicatedStorage.Configs:WaitForChild("combat"))
    local enemiesCfg = require(ReplicatedStorage.Configs:WaitForChild("enemies"))
    local eng = combat.engagement or {}
    local rate = eng.render_lerp_rate or 12
    local defaultGait = eng.gait or {}

    -- Resolve (once per enemyId) the merged gait: per-enemy override fields win over the
    -- default. Cached so we don't rebuild the table every frame.
    local gaitCache = {}
    local function resolveGait(enemyId)
        local cached = gaitCache[enemyId]
        if cached then
            return cached
        end
        local override = enemiesCfg.enemies and enemiesCfg.enemies[enemyId] and enemiesCfg.enemies[enemyId].gait
        local g = {
            enabled = defaultGait.enabled ~= false,
            style = defaultGait.style or "waddle",
            bobHeight = defaultGait.bob_height or 0.6,
            tiltRad = math.rad(defaultGait.tilt_degrees or 12),
            stride = defaultGait.stride_length or 5,
            refSpeed = defaultGait.ref_speed or 8,
            easeRate = defaultGait.ease_rate or 8,
        }
        if type(override) == "table" then
            if override.enabled ~= nil then
                g.enabled = override.enabled
            end
            g.style = override.style or g.style
            g.bobHeight = override.bob_height or g.bobHeight
            g.tiltRad = override.tilt_degrees and math.rad(override.tilt_degrees) or g.tiltRad
            g.stride = override.stride_length or g.stride
            g.refSpeed = override.ref_speed or g.refSpeed
            g.easeRate = override.ease_rate or g.easeRate
        end
        g.fn = STYLES[g.style] or STYLES.waddle
        gaitCache[enemyId] = g
        return g
    end

    -- model -> { base = CFrame (no gait), phase, amp }. Weak keys so enemies drop out.
    local state = setmetatable({}, { __mode = "k" })

    RunService.RenderStepped:Connect(function(dt)
        local folder = enemiesFolder()
        if not folder then
            return
        end
        local alpha = 1 - math.exp(-rate * dt)
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model.PrimaryPart then
                local target = model:GetAttribute("MoveTarget")
                if target then
                    local face = model:GetAttribute("MoveFace")
                    local goal
                    if face and (face - target).Magnitude > 1e-3 then
                        goal = CFrame.lookAt(target, face)
                    else
                        goal = CFrame.new(target)
                    end

                    local st = state[model]
                    if not st then
                        st = { base = model:GetPivot(), phase = 0, amp = 0 }
                        state[model] = st
                    end

                    -- 1) Smoothed base position (no gait — kept clean for next lerp).
                    local base = st.base:Lerp(goal, alpha)
                    local stepDist = (Vector3.new(base.X, 0, base.Z) - Vector3.new(st.base.X, 0, st.base.Z)).Magnitude
                    st.base = base

                    local gait = resolveGait(model:GetAttribute("EnemyId"))
                    if gait.enabled then
                        -- 2) Advance the gait by distance walked; ease amplitude with speed.
                        st.phase = (st.phase + (stepDist / gait.stride) * TWO_PI) % TWO_PI
                        local speed = stepDist / math.max(dt, 1e-3)
                        local targetAmp = math.clamp(speed / gait.refSpeed, 0, 1)
                        st.amp = st.amp + (targetAmp - st.amp) * (1 - math.exp(-gait.easeRate * dt))

                        local bobN, rollN, yawN = gait.fn(st.phase)
                        local bob = gait.bobHeight * st.amp * bobN
                        local roll = gait.tiltRad * st.amp * rollN
                        local yaw = gait.tiltRad * st.amp * yawN
                        model:PivotTo(CFrame.new(0, bob, 0) * base * CFrame.Angles(0, yaw, roll))
                    else
                        model:PivotTo(base)
                    end
                end
            end
        end
    end)
end

return EnemyMotion
