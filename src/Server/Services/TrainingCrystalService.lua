--[[
    TrainingCrystalService (server, Studio-only) — a permanent practice node near spawn.

    Picks the large crystal nearest the world SpawnLocation and keeps its HP topped up, so it never
    breaks and your squad mines it forever — an always-available rig for testing farming/debuff/drop
    powers without hunting for a fresh node. Studio-gated: it never runs in a live server. If the
    chosen node ever vanishes (re-spawn pass), it re-picks on the next tick.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TrainingCrystalService = {}
TrainingCrystalService.__index = TrainingCrystalService

local REFILL_BELOW = 0.6 -- refill once HP drops under 60% of MaxHP (keeps it visibly mined)

local function spawnPos()
    local sl = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    return sl and sl.Position or Vector3.new(0, 0, 0)
end

-- Largest-HP crystal nearest the spawn (a real farm node, no EnemyId), or nil if none spawned yet.
local function pickCrystal()
    local game = Workspace:FindFirstChild("Game")
    local root = game and game:FindFirstChild("Breakables")
    if not root then
        return nil
    end
    local origin = spawnPos()
    local best, bestScore
    for _, d in ipairs(root:GetDescendants()) do
        if
            d:IsA("Model")
            and (d:GetAttribute("MaxHP") or 0) >= 300 -- a "large" node, lasts/reads well
            and not d:GetAttribute("EnemyId")
        then
            local bp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")
            if bp then
                local dist = (Vector3.new(bp.Position.X, 0, bp.Position.Z) - Vector3.new(
                    origin.X,
                    0,
                    origin.Z
                )).Magnitude
                if not bestScore or dist < bestScore then
                    bestScore, best = dist, d
                end
            end
        end
    end
    return best
end

function TrainingCrystalService:Init()
    self._logger = self._modules and self._modules.Logger
    if not RunService:IsStudio() then
        return -- dev-only rig
    end

    self._acc = 0
    self._loggedName = nil

    self._conn = RunService.Heartbeat:Connect(function(dt)
        self._acc += dt
        if self._acc < 0.5 then
            return -- cheap: check ~twice a second
        end
        self._acc = 0
        self:_tick()
    end)
end

-- Stateless each tick: the spawner respawns/replaces crystal instances, so we don't hold a node
-- reference (it would go stale and the marker would flap). Instead we re-resolve the nearest large
-- crystal every tick and keep THAT one marked + topped up — a permanent practice node always exists
-- near spawn even as the field refreshes around it.
function TrainingCrystalService:_tick()
    local node = pickCrystal()
    if not node then
        return -- field hasn't spawned yet
    end
    -- exactly ONE training node: clear the marker off any stale crystal (the nearest can shift as the
    -- field respawns; leaving old markers behind would litter half-mined nodes around spawn).
    local game = Workspace:FindFirstChild("Game")
    local root = game and game:FindFirstChild("Breakables")
    if root then
        for _, d in ipairs(root:GetDescendants()) do
            if d ~= node and d:IsA("Model") and d:GetAttribute("TrainingCrystal") then
                d:SetAttribute("TrainingCrystal", nil)
            end
        end
    end
    node:SetAttribute("TrainingCrystal", true)
    local maxHp = tonumber(node:GetAttribute("MaxHP")) or 0
    local hp = tonumber(node:GetAttribute("HP")) or 0
    if maxHp > 0 and hp < maxHp * REFILL_BELOW then
        node:SetAttribute("HP", maxHp)
    end
    if self._logger and self._logger.Info and self._loggedName ~= node.Name then
        self._loggedName = node.Name
        self._logger:Info("Training crystal active", { name = node.Name, maxHp = maxHp })
    end
end

return TrainingCrystalService
