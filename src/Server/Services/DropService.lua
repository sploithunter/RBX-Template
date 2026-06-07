--[[
    DropService (server, #167 + #177) — physical GEM pickups + Magnet collection.

    When a crystal breaks, BreakableSpawner hands the resolved COIN award to SpawnCoinDrop instead of
    crediting it instantly. The award SPLITS into one or more GEMS (payout by count — a fat node
    bursts a fistful) that pop out and rest on the ground; a single Heartbeat loop collects them when
    the owner walks within `collect_radius` (+ the Magnet power's MagnetBuff bonus), flying them in
    once close. Coins are never lost: a gem auto-collects to its owner on despawn-timeout or when the
    per-server cap is exceeded. XP / pet-xp / realm cuts stay instant in BreakableSpawner.

    Each gem is a MODEL: a MeshPart (one of 3 shared form meshes + the biome-colour texture) with a
    PointLight inside for glow (configs/gems.lua). Gem colour = biome currency; gem FORM = the chunk
    it carries (single/pile/bag). Templates are built once (async) and cloned per drop; a tinted ball
    is the fallback if a mesh fails to build, so drops never break. All numbers in configs/drops.lua
    + configs/gems.lua.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local AssetService = game:GetService("AssetService")

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
    self._gems = (self._configLoader and self._configLoader:LoadConfig("gems"))
        or require(ReplicatedStorage.Configs:WaitForChild("gems"))

    self._active = {} -- live drop records
    self._pool = {} -- recycled gem models, keyed "color|form" (or "ball")
    self._templates = {} -- built gem model templates, keyed "color|form"

    if not self._config.enabled then
        return -- inert: BreakableSpawner credits instantly when SpawnCoinDrop returns false
    end

    self._folder = Instance.new("Folder")
    self._folder.Name = "CoinDrops"
    self._folder.Parent = Workspace
    self._templateHolder = Instance.new("Folder")
    self._templateHolder.Name = "_GemTemplates"
    self._templateHolder.Parent = self._folder

    -- pre-build the gem templates off the hot path (CreateMeshPartAsync yields)
    task.spawn(function()
        for color in pairs(self._gems.textures or {}) do
            for form in pairs(self._gems.meshes or {}) do
                self:_ensureTemplate(color, form)
            end
        end
    end)

    self._conn = RunService.Heartbeat:Connect(function()
        self:_step()
    end)
end

function DropService:IsEnabled()
    return self._config and self._config.enabled == true
end

-- Target widest-side studs for a gem of this form (per-form so piles/bags read bigger than singles).
function DropService:_sizeFor(form)
    local s = self._gems.size
    if type(s) == "table" then
        return s[form] or self._gems.default_size or 1.5
    end
    return s or self._gems.default_size or 1.5
end

-- ---- gem template construction -----------------------------------------

-- Build (once) and cache the gem MODEL template for a colour+form: a MeshPart (mesh + texture,
-- scaled, glassy) wrapped in a Model, with a PointLight inside for glow. Yields on first build.
function DropService:_ensureTemplate(color, form)
    local key = color .. "|" .. form
    if self._templates[key] then
        return self._templates[key]
    end
    local meshId = self._gems.meshes and self._gems.meshes[form]
    local texId = self._gems.textures
        and self._gems.textures[color]
        and self._gems.textures[color][form]
    if not (meshId and texId) then
        return nil
    end
    local ok, mesh = pcall(function()
        -- selene: allow(undefined_variable)
        local content = Content.fromUri(meshId) -- `Content` is a runtime global selene's std lacks
        return AssetService:CreateMeshPartAsync(content, {
            CollisionFidelity = Enum.CollisionFidelity.Box,
            RenderFidelity = Enum.RenderFidelity.Automatic,
        })
    end)
    if not ok or not mesh then
        if self._logger and self._logger.Warn then
            self._logger:Warn("Gem mesh build failed", { key = key, error = tostring(mesh) })
        end
        return nil -- caller falls back to a tinted ball
    end
    mesh.TextureID = texId
    mesh.Anchored = true
    mesh.CanCollide = false
    mesh.CanQuery = false
    mesh.CanTouch = false
    mesh.Massless = true
    mesh.Material = Enum.Material.Glass
    mesh.Name = "Gem"
    -- scale so the widest side ≈ the per-form target studs
    local widest = math.max(mesh.Size.X, mesh.Size.Y, mesh.Size.Z)
    if widest > 0 then
        mesh.Size = mesh.Size * (self:_sizeFor(form) / widest)
    end
    local light = Instance.new("PointLight")
    light.Color = color3((self._gems.light_color and self._gems.light_color[color]) or {})
    light.Range = self._gems.light_range or 9
    light.Brightness = self._gems.light_brightness or 2.5
    light.Parent = mesh
    local model = Instance.new("Model")
    model.Name = "GemDrop"
    mesh.Parent = model
    model.PrimaryPart = mesh
    model.Parent = self._templateHolder
    self._templates[key] = model
    return model
end

-- Acquire a gem (or ball) instance for colour+form: pool hit, else clone the template, else a ball.
-- Returns the Model and its movable PrimaryPart.
function DropService:_acquireGem(color, form)
    local key = color .. "|" .. form
    local pooled = self._pool[key] and table.remove(self._pool[key])
    if pooled then
        pooled.Parent = self._folder
        return pooled, pooled.PrimaryPart
    end
    local template = self._templates[key]
    if template then
        local clone = template:Clone()
        clone.Parent = self._folder
        return clone, clone.PrimaryPart
    end
    -- fallback: a tinted ball wrapped in a Model (template not built yet / mesh failed)
    local ball = Instance.new("Part")
    ball.Shape = Enum.PartType.Ball
    ball.Material = Enum.Material.Neon
    ball.Color = color3((self._gems.light_color and self._gems.light_color[color]) or {})
    local bs = self:_sizeFor(form)
    ball.Size = Vector3.new(bs, bs, bs)
    ball.Anchored = true
    ball.CanCollide = false
    ball.CanQuery = false
    ball.CanTouch = false
    ball.Massless = true
    ball.Name = "Gem"
    local light = Instance.new("PointLight")
    light.Color = ball.Color
    light.Range = self._gems.light_range or 9
    light.Brightness = self._gems.light_brightness or 2.5
    light.Parent = ball
    local model = Instance.new("Model")
    model.Name = "GemDrop"
    ball.Parent = model
    model.PrimaryPart = ball
    model.Parent = self._folder
    return model, ball
end

function DropService:_recycle(rec)
    local model = rec.model
    if not model then
        return
    end
    model.Parent = nil
    local key = rec.poolKey or "ball"
    self._pool[key] = self._pool[key] or {}
    if #self._pool[key] < 40 then
        self._pool[key][#self._pool[key] + 1] = model
    else
        model:Destroy()
    end
end

-- ---- payout split ------------------------------------------------------

function DropService:_colorFor(currency)
    local map = self._gems.currency_color or {}
    return map[tostring(currency)] or self._gems.default_color or "emerald"
end

function DropService:_formFor(amount)
    for _, tier in ipairs(self._gems.form_tiers or {}) do
        if amount >= (tier.min or 0) then
            return tier.form
        end
    end
    return "single"
end

-- Split a coin award into gem chunks (payout by COUNT): one extra gem per `split_step`, clamped to
-- `max_gems`; the award is divided across them (first gem keeps the remainder so the sum is exact).
function DropService:_split(amount)
    local step = self._gems.split_step or 250
    local maxGems = self._gems.max_gems or 6
    local count = math.clamp(1 + math.floor(amount / math.max(1, step)), 1, maxGems)
    local per = math.floor(amount / count)
    local rem = amount - per * count
    local chunks = {}
    for i = 1, count do
        local a = per + (i == 1 and rem or 0)
        if a > 0 then
            chunks[#chunks + 1] = a
        end
    end
    if #chunks == 0 then
        chunks[1] = amount
    end
    return chunks
end

-- ---- spawn -------------------------------------------------------------

-- Floor height under (x, z); ignores drops/pets/characters so gems rest on the terrain.
function DropService:_groundY(x, z, fromY, fallbackY)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = { self._folder }
    local pp = Workspace:FindFirstChild("PlayerPets")
    if pp then
        exclude[#exclude + 1] = pp
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then
            exclude[#exclude + 1] = plr.Character
        end
    end
    params.FilterDescendantsInstances = exclude
    local result = Workspace:Raycast(Vector3.new(x, fromY + 8, z), Vector3.new(0, -200, 0), params)
    return result and result.Position.Y or fallbackY
end

-- Spawn gem pickups for a coin award. Returns true if drops were created (caller must NOT credit),
-- false to credit instantly (disabled / too small / no position). Never throws.
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

    local color = self:_colorFor(currencyType)
    local chunks = self:_split(amount)
    local pop = self._config.pop_up or 7
    local out = self._config.pop_out or 5

    for i, chunkAmount in ipairs(chunks) do
        -- cap: auto-collect the oldest live drop so the world never floods
        if #self._active >= (self._config.max_active or 90) then
            self:_collect(self._active[1], true)
        end
        local form = self:_formFor(chunkAmount)
        local model, part = self:_acquireGem(color, form)
        local ang = ((#self._active + i) % 12) * (math.pi / 6)
        local hx = position.X + math.cos(ang) * out
        local hz = position.Z + math.sin(ang) * out
        local groundY = self:_groundY(hx, hz, position.Y, position.Y - 1)
        local radius = part.Size.Y * 0.5
        local rest = Vector3.new(hx, groundY + radius, hz)
        local apex = position
            + Vector3.new(math.cos(ang) * out * 0.5, pop, math.sin(ang) * out * 0.5)
        part.CFrame = CFrame.new(apex)

        local rec = {
            model = model,
            part = part,
            poolKey = color .. "|" .. form,
            owner = player.UserId,
            currency = tostring(currencyType or "coins"),
            amount = math.floor(chunkAmount),
            spawnAt = os.clock(),
            settling = true,
        }
        self._active[#self._active + 1] = rec

        local TweenService = game:GetService("TweenService")
        TweenService:Create(
            part,
            TweenInfo.new(
                self._config.pop_time or 0.35,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ),
            { CFrame = CFrame.new(rest) }
        ):Play()
        task.delay(self._config.pop_time or 0.35, function()
            rec.settling = false
        end)
    end
    return true
end

-- ---- collect loop ------------------------------------------------------

local function ownerRoot(userId)
    local plr = Players:GetPlayerByUserId(userId)
    if not plr then
        return nil, nil
    end
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    return plr, hrp and hrp.Position
end

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
    for i, r in ipairs(self._active) do
        if r == rec then
            table.remove(self._active, i)
            break
        end
    end
    self:_recycle(rec)
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

    for i = #self._active, 1, -1 do
        local rec = self._active[i]
        if not rec or rec._done or not rec.part or not rec.part.Parent then
            if rec and not rec._done then
                self:_collect(rec, true)
            end
        elseif now - rec.spawnAt >= despawn then
            self:_collect(rec, true)
        else
            local plr, rootPos = ownerRoot(rec.owner)
            if not plr then
                self:_collect(rec, true)
            elseif rootPos and not rec.settling then
                local bonus = 0
                if (plr:GetAttribute("MagnetBuffUntil") or 0) > nowT then
                    bonus = tonumber(plr:GetAttribute("MagnetBuff")) or 0
                end
                local dist = (rec.part.Position - rootPos).Magnitude
                if dist <= pullR then
                    self:_collect(rec)
                elseif dist <= (baseR + bonus) then
                    local dir = (rootPos - rec.part.Position)
                    local stepLen = math.min(pullSpeed / 60, dir.Magnitude)
                    rec.part.CFrame = rec.part.CFrame * CFrame.Angles(0, spin, 0)
                        + dir.Unit * stepLen
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
