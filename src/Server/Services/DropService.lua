--[[
    DropService (server, #167) — physical coin pickups + Magnet collection.

    When a crystal breaks, BreakableSpawner hands the resolved COIN award to SpawnCoinDrop instead of
    crediting it instantly (when configs/drops.lua.enabled). A pooled coin part pops out of the node;
    a single Heartbeat loop collects it when the owner walks within `collect_radius` (+ the Magnet
    power's MagnetBuff bonus), flying it in once close. Coins are never lost: a drop auto-collects to
    its owner on despawn-timeout or when the per-server cap is exceeded. XP / pet-xp / realm cuts are
    NOT handled here — they stay instant in BreakableSpawner; only the coin currency rides the drop.

    Pure-ish boundary: all gameplay numbers live in configs/drops.lua. EconomyService is resolved at
    runtime (same pattern as BreakableSpawner) so crediting goes through the one currency path.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local DropService = {}
DropService.__index = DropService

local function color3(t)
    return Color3.fromRGB(t[1] or 240, t[2] or 200, t[3] or 70)
end

function DropService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._config = (self._configLoader and self._configLoader:LoadConfig("drops"))
        or require(ReplicatedStorage.Configs:WaitForChild("drops"))

    self._active = {} -- list of live drop records: { part, owner (userId), currency, amount, spawnAt, pulling }
    self._pool = {} -- recycled parts

    if not self._config.enabled then
        return -- inert: BreakableSpawner credits instantly when SpawnCoinDrop returns false
    end

    self._folder = Instance.new("Folder")
    self._folder.Name = "CoinDrops"
    self._folder.Parent = Workspace

    self._conn = RunService.Heartbeat:Connect(function()
        self:_step()
    end)
end

-- Is the drops system live? BreakableSpawner checks this before handing coins over.
function DropService:IsEnabled()
    return self._config and self._config.enabled == true
end

-- Borrow a coin part from the pool (or make one).
function DropService:_acquirePart()
    local part = table.remove(self._pool)
    if not part then
        part = Instance.new("Part")
        part.Shape = Enum.PartType.Ball
        part.Material = Enum.Material.Neon
        part.Color = color3(self._config.part_color or {})
        part.Size = Vector3.new(
            self._config.part_size or 1.3,
            self._config.part_size or 1.3,
            self._config.part_size or 1.3
        )
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Massless = true
        part.Name = "CoinDrop"
        local light = Instance.new("PointLight")
        light.Range = 6
        light.Brightness = 1.5
        light.Color = color3(self._config.part_color or {})
        light.Parent = part
    end
    part.Transparency = 0
    part.Parent = self._folder
    return part
end

function DropService:_recycle(part)
    part.Parent = nil
    if #self._pool < 200 then
        self._pool[#self._pool + 1] = part
    else
        part:Destroy()
    end
end

-- Spawn a coin pickup carrying `amount` of `currencyType` for `player`, popping out of `position`.
-- Returns true if a drop was created (caller must NOT credit), false if the caller should credit
-- instantly (drops disabled, amount too small, or no position). Never throws.
function DropService:SpawnCoinDrop(player, currencyType, amount, position)
    amount = tonumber(amount) or 0
    if not self:IsEnabled() then
        return false
    end
    if not (player and position and amount >= (self._config.min_coins_for_drop or 1)) then
        return false
    end
    if typeof(position) ~= "Vector3" then
        return false
    end

    -- cap: auto-collect the oldest live drop so the world never floods
    if #self._active >= (self._config.max_active or 90) then
        self:_collect(self._active[1], true)
    end

    local part = self:_acquirePart()
    -- pop arc: settle from an up+out hop to a resting spot near the node
    local ang = (#self._active % 12) * (math.pi / 6)
    local out = self._config.pop_out or 5
    local rest = position + Vector3.new(math.cos(ang) * out, 1.5, math.sin(ang) * out)
    local apex = position
        + Vector3.new(
            math.cos(ang) * out * 0.5,
            self._config.pop_up or 7,
            math.sin(ang) * out * 0.5
        )
    part.CFrame = CFrame.new(apex)

    local rec = {
        part = part,
        owner = player.UserId,
        currency = tostring(currencyType or "coins"),
        amount = math.floor(amount),
        spawnAt = os.clock(),
        rest = rest,
        settling = true,
    }
    self._active[#self._active + 1] = rec

    -- settle tween (cheap: just lerp via a short task; the Heartbeat loop ignores it until settled)
    local TweenService = game:GetService("TweenService")
    local tw = TweenService:Create(
        part,
        TweenInfo.new(
            self._config.pop_time or 0.35,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ),
        { CFrame = CFrame.new(rest) }
    )
    tw:Play()
    task.delay(self._config.pop_time or 0.35, function()
        rec.settling = false
    end)
    return true
end

-- Resolve the owner's root position (nil if offline / no character).
local function ownerRoot(userId)
    local plr = Players:GetPlayerByUserId(userId)
    if not plr then
        return nil, nil
    end
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    return plr, hrp and hrp.Position
end

-- Credit (or drop) a record and recycle its part. `force` = auto-collect (cap/despawn) — credits
-- to the owner if online, else just removes the part (offline players can't be credited here).
function DropService:_collect(rec, _force)
    if not rec or rec._done then
        return
    end
    rec._done = true
    local plr = Players:GetPlayerByUserId(rec.owner)
    if plr and rec.amount > 0 then
        local economy = self._moduleLoader and self._moduleLoader:Get("EconomyService")
        if economy and economy.AddCurrency then
            pcall(function()
                economy:AddCurrency(plr, rec.currency, rec.amount, "drop_collect")
            end)
        end
    end
    -- remove from active list
    for i, r in ipairs(self._active) do
        if r == rec then
            table.remove(self._active, i)
            break
        end
    end
    self:_recycle(rec.part)
end

function DropService:_step()
    local now = os.clock()
    local cfg = self._config
    local baseR = cfg.collect_radius or 11
    local pullR = cfg.magnet_pull_radius or 6
    local pullSpeed = cfg.magnet_pull_speed or 60
    local despawn = cfg.despawn_seconds or 30
    local spin = math.rad(cfg.part_spin or 90) * (1 / 60)
    local nowT = os.time()

    -- iterate backwards so collect() removals are safe
    for i = #self._active, 1, -1 do
        local rec = self._active[i]
        if not rec or rec._done then
            -- skip
        elseif now - rec.spawnAt >= despawn then
            self:_collect(rec, true) -- never lose coins
        else
            local plr, rootPos = ownerRoot(rec.owner)
            if not plr then
                -- owner left: drop the part (no offline credit)
                self:_collect(rec, true)
            elseif rootPos and not rec.settling then
                -- Magnet bonus: the power's MagnetBuff (studs) added while live
                local bonus = 0
                if (plr:GetAttribute("MagnetBuffUntil") or 0) > nowT then
                    bonus = tonumber(plr:GetAttribute("MagnetBuff")) or 0
                end
                local dist = (rec.part.Position - rootPos).Magnitude
                if dist <= pullR then
                    self:_collect(rec) -- close enough → pocket it
                elseif dist <= (baseR + bonus) then
                    -- fly toward the player (vacuum)
                    local dir = (rootPos - rec.part.Position)
                    local step = math.min(pullSpeed / 60, dir.Magnitude)
                    rec.part.CFrame = rec.part.CFrame * CFrame.Angles(0, spin, 0) + dir.Unit * step
                else
                    rec.part.CFrame = rec.part.CFrame * CFrame.Angles(0, spin, 0)
                end
            elseif not rec.settling then
                rec.part.CFrame = rec.part.CFrame * CFrame.Angles(0, spin, 0)
            end
        end
    end
end

return DropService
