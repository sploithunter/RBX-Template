--[[
    SummonService (server, #178) — the capstone "call a pet" guardians.

    PowerService routes the `summon` family here. A guardian model joins your squad for the power's
    duration, expresses its fantasy through squad buffs (firewall-safe — no direct player damage),
    trails the player, then despawns. Two guardians today (configs/guardians.lua):
      • Colossus (Gaia's Colossus) — big squad +Defense and x pet-damage while it stands.
      • Djinn (Genie of the Dunes) — revives every downed pet + full-heals on arrival, then a HoT tick.

    Model is a scaled+tinted clone of a squad pet as a placeholder until Jason's real guardian models
    land (drop their Open Cloud asset ids in configs/guardians.lua `model_asset`).
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")

local SummonService = {}
SummonService.__index = SummonService

local function color3(t)
    t = t or {}
    return Color3.fromRGB(t[1] or 200, t[2] or 200, t[3] or 200)
end

-- A character's HumanoidRootPart sits ~2.7 studs above its feet; subtract this so a guardian's
-- BASE (not its center) lands at the player's foot level before applying the config `hover`.
local FOOT_DROP = 2.7

-- World CFrame for a guardian: trail toward the player at its offset, auto-grounded by half the
-- model height (+ config hover), facing the player but kept level (no pitch/roll).
local function targetCFrame(rec, hrpPos, fromPos, lerp)
    local o = rec.offset
    local y = hrpPos.Y + (rec.halfHeight - FOOT_DROP) + rec.hover
    local target = Vector3.new(hrpPos.X + (o.x or 6), y, hrpPos.Z + (o.z or 4))
    local nextPos = fromPos and fromPos:Lerp(target, lerp or 1) or target
    return CFrame.lookAt(nextPos, Vector3.new(hrpPos.X, nextPos.Y, hrpPos.Z))
end

function SummonService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._config = (self._configLoader and self._configLoader:LoadConfig("guardians"))
        or require(game:GetService("ReplicatedStorage").Configs:WaitForChild("guardians"))
    self._active = {} -- { model, owner=userId, gkind, expireAt, healEvery, lastHeal, healAmt }

    self._folder = Instance.new("Folder")
    self._folder.Name = "Guardians"
    self._folder.Parent = Workspace

    self._conn = RunService.Heartbeat:Connect(function()
        self:_step()
    end)
end

local function squadFolder(player)
    local pp = Workspace:FindFirstChild("PlayerPets")
    return pp and pp:FindFirstChild(player.Name)
end

-- Build the guardian model: the real asset if configured, else a scaled+tinted clone of a squad pet,
-- else a glowing blob. Sanitized so other systems don't treat it as a real squad pet.
function SummonService:_buildModel(player, gkind, gcfg)
    local model
    local usingPlaceholder = true -- real asset keeps its own textures; placeholder gets tinted
    local assetId = self._config.model_asset and self._config.model_asset[gkind]
    if assetId then
        local ok, loaded = pcall(function()
            return InsertService:LoadAsset(assetId)
        end)
        if ok and loaded then
            model = loaded:FindFirstChildWhichIsA("Model") or loaded
            if model.Parent == loaded then
                model.Parent = nil
            end
            usingPlaceholder = false
        end
    end
    if not model then
        local pets = squadFolder(player)
        local src = pets and pets:FindFirstChildWhichIsA("Model")
        if src then
            model = src:Clone()
        end
    end
    if not model then
        local p = Instance.new("Part")
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(6, 6, 6)
        local m = Instance.new("Model")
        p.Parent = m
        m.PrimaryPart = p
        model = m
    end
    -- sanitize: strip pet/breakable system markers + scripts so nothing else manages it
    for _, d in ipairs(model:GetDescendants()) do
        if
            d:IsA("BaseScript")
            or d.Name == "PositionNumber"
            or d.Name == "TargetID"
            or d.Name == "TargetType"
            or d.Name == "TargetWorld"
            or d.Name == "BreakableID"
        then
            pcall(function()
                d:Destroy()
            end)
        end
    end
    if not model.PrimaryPart then
        model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
    end
    -- scale: placeholder uses a flat multiplier; a real asset is scaled to a target stud height
    if usingPlaceholder then
        pcall(function()
            model:ScaleTo(gcfg.scale or 2.5)
        end)
    elseif gcfg.height then
        pcall(function()
            local ext = model:GetExtentsSize()
            if ext and ext.Y > 0.1 then
                model:ScaleTo(gcfg.height / ext.Y)
            end
        end)
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
            d.Massless = true
            if usingPlaceholder then -- real asset keeps its authored textures/colors
                d.Color = color3(gcfg.tint)
                d.Material = Enum.Material.SmoothPlastic
            end
        elseif d:IsA("Humanoid") then
            d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end
    end
    if model.PrimaryPart then
        local light = Instance.new("PointLight")
        light.Color = color3(gcfg.light)
        light.Range = math.clamp((gcfg.height or 12) * 0.8, 13, 42) -- scale the glow with the giant's size
        light.Brightness = 1.6 -- soft glow; high brightness washed the textures out
        light.Parent = model.PrimaryPart
    end
    model.Name = "Guardian_" .. gkind
    return model
end

-- Heal one pet by `amount` endurance (mirrors PowerService:_healPet; used by the Djinn HoT).
local function healPet(pet, amount)
    if not (pet and pet:IsA("Model")) or pet:GetAttribute("CombatDowned") then
        return
    end
    local taken = pet:GetAttribute("CombatDamageTaken") or 0
    if amount <= 0 or taken <= 0 then
        return
    end
    local healed = math.min(taken, amount)
    pet:SetAttribute("CombatDamageTaken", math.max(0, taken - amount))
    pet:SetAttribute("HealFxUntil", os.time() + 3)
    -- green "+N" float, like every other heal path (this was the one heal with no number)
    pcall(function()
        Signals.Combat_Heal:FireAllClients({ target = pet, amount = math.floor(healed + 0.5) })
    end)
end

-- Summon a guardian for `kind` (the effect_kind: guardian/duration/revive/magnitude). Called by
-- PowerService:_summonGuardian. Applies the immediate payoff + spawns the model + standing buffs.
function SummonService:Summon(player, kind, now, powerId)
    local gkind = kind.guardian
    local gcfg = gkind and self._config[gkind]
    if not gcfg then
        return
    end
    local dur = tonumber(kind.duration) or 20
    local pets = squadFolder(player)

    -- immediate payoff: revive + heal (Genie's never-wipe)
    if pets then
        if kind.revive then
            for _, pet in ipairs(pets:GetChildren()) do
                if pet:IsA("Model") and pet:GetAttribute("CombatDowned") then
                    pet:SetAttribute("CombatDowned", false)
                    pet:SetAttribute("CombatDamageTaken", 0)
                    pet:SetAttribute("CooldownUntil", 0)
                    pet:SetAttribute("DownedReason", "")
                end
            end
        end
        local burst = tonumber(kind.magnitude) or 0
        if burst > 0 then
            for _, pet in ipairs(pets:GetChildren()) do
                healPet(pet, burst)
            end
        end
        -- Colossus standing buffs: the WALL (squad +Defense) + the FIST (x pet-damage)
        if gkind == "colossus" then
            for _, pet in ipairs(pets:GetChildren()) do
                if pet:IsA("Model") then
                    pet:SetAttribute("DefenseBuff", gcfg.squad_defense or 200)
                    pet:SetAttribute("DefenseBuffUntil", now + dur)
                    pet:SetAttribute("DefenseBuffPowerId", powerId)
                end
            end
            player:SetAttribute("PetDamageBuff", gcfg.squad_damage or 1.5)
            player:SetAttribute("PetDamageBuffUntil", now + dur)
            player:SetAttribute("PetDamageBuffPowerId", powerId)
        end
    end

    local model = self:_buildModel(player, gkind, gcfg)
    model.Parent = self._folder

    local halfHeight = 2.5
    pcall(function()
        local ext = model:GetExtentsSize()
        if ext and ext.Y > 0 then
            halfHeight = ext.Y / 2
        end
    end)

    local rec = {
        model = model,
        owner = player.UserId,
        gkind = gkind,
        offset = gcfg.offset or { x = 6, y = 0, z = 4 },
        hover = gcfg.hover or 0,
        halfHeight = halfHeight,
        expireAt = os.clock() + dur,
        healEvery = gcfg.tick_seconds,
        healAmt = gcfg.heal_per_tick,
        lastHeal = os.clock(),
    }

    -- place it at the player's side immediately (don't slide in from the world origin)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp and model.PrimaryPart then
        pcall(function()
            model:PivotTo(targetCFrame(rec, hrp.Position, nil, 1))
        end)
    end

    self._active[#self._active + 1] = rec
    if self._logger and self._logger.Info then
        self._logger:Info(
            "Guardian summoned",
            { kind = gkind, player = player.Name, seconds = dur }
        )
    end
end

function SummonService:_despawn(rec)
    pcall(function()
        rec.model:Destroy()
    end)
end

function SummonService:_step()
    local now = os.clock()
    local lerp = self._config.follow_lerp or 0.18
    for i = #self._active, 1, -1 do
        local rec = self._active[i]
        if not rec or not rec.model or not rec.model.Parent or now >= rec.expireAt then
            if rec then
                self:_despawn(rec)
            end
            table.remove(self._active, i)
        else
            local plr = Players:GetPlayerByUserId(rec.owner)
            local hrp = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            local pp = rec.model.PrimaryPart
            if hrp and pp then
                -- PivotTo moves the whole (anchored, multi-part) model; auto-grounded + level
                pcall(function()
                    rec.model:PivotTo(targetCFrame(rec, hrp.Position, pp.Position, lerp))
                end)
            end
            -- Djinn heal-over-time tick
            if rec.healEvery and now - rec.lastHeal >= rec.healEvery then
                rec.lastHeal = now
                local pets = plr and squadFolder(plr)
                if pets then
                    for _, pet in ipairs(pets:GetChildren()) do
                        healPet(pet, rec.healAmt or 0)
                    end
                end
            end
        end
    end
end

return SummonService
