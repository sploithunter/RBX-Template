--[[
    EnemyMotion — CLIENT-side smoothing of enemy movement (Feature 10).

    EnemyService moves each enemy server-side in ~update_interval steps (the server is
    authoritative — its pivot drives the mining-distance gate). Anchored parts moved on
    the server replicate at that coarse cadence with no interpolation, so the motion
    looks steppy. This system reads the server-published step target (the `MoveTarget`
    / `MoveFace` attributes) and lerps the *visible* model toward it every RenderStepped,
    overriding the steppy replicated CFrame. Client PivotTo on an anchored part is local
    only, so the server's authoritative position is untouched.

    Self-gates on pet_follow.service_owned (same as the rest of the combat layer).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyMotion = {}

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
    local rate = (combat.engagement and combat.engagement.render_lerp_rate) or 12

    -- model -> current render CFrame (weak so despawned enemies drop out).
    local render = setmetatable({}, { __mode = "k" })

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
                    local cur = render[model] or model:GetPivot()
                    local nextCf = cur:Lerp(goal, alpha)
                    render[model] = nextCf
                    model:PivotTo(nextCf)
                end
            end
        end
    end)
end

return EnemyMotion
