--[[
    BaddieSpawnerService — proximity-triggered enemy waves at map-authored spawner parts.

    Jason placed parts named BaddieSpawner* (Lava + Desert) in the map: walk within
    `radius` studs and a wave spawns at the part (picked from the weighted `waves`
    table in configs/enemies.lua `spawners`), then THAT spawner cools down for
    `cooldown` seconds. Gives players a taste of combat before choosing a direction
    on the Heaven/Hell tree. Enemies use the normal EnemyService chase/aggro/loot
    path, credited to the triggering player. No bosses by design.

    Spawner parts are found by NAME PREFIX anywhere under Workspace at Start (re-scan
    on a slow timer so newly synced map edits are picked up without a restart).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BaddieSpawnerService = {}
BaddieSpawnerService.__index = BaddieSpawnerService

function BaddieSpawnerService.new()
    return setmetatable({}, BaddieSpawnerService)
end

function BaddieSpawnerService:Init()
    local loader = self._moduleLoader
    self._logger = loader:Get("Logger")
    local configLoader = loader:Get("ConfigLoader")
    local ok, cfg = pcall(function()
        return configLoader:LoadConfig("enemies")
    end)
    self._config = (ok and cfg and cfg.spawners) or nil
    self._spawners = {} -- part -> { cooldownUntil }
end

function BaddieSpawnerService:_enemyService()
    local locator = _G.RBXTemplateServices
    local ok, svc = pcall(function()
        return locator and locator:Get("EnemyService")
    end)
    return ok and svc or nil
end

function BaddieSpawnerService:_scan()
    local prefix = self._config.part_prefix or "BaddieSpawner"
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("BasePart") and inst.Name:sub(1, #prefix) == prefix then
            if not self._spawners[inst] then
                self._spawners[inst] = { cooldownUntil = 0, alive = {} }
                self._logger:Info("Baddie spawner armed", { part = inst.Name })
            end
        end
    end
end

function BaddieSpawnerService:_pickWave(rng)
    local waves = self._config.waves or {}
    local total = 0
    for _, w in ipairs(waves) do
        total += (tonumber(w.weight) or 0)
    end
    if total <= 0 then
        return nil
    end
    local roll = rng:NextNumber() * total
    for _, w in ipairs(waves) do
        roll -= (tonumber(w.weight) or 0)
        if roll <= 0 then
            return w
        end
    end
    return waves[#waves]
end

function BaddieSpawnerService:_trigger(part, player, rng)
    local wave = self:_pickWave(rng)
    if not wave then
        return
    end
    local enemySvc = self:_enemyService()
    if not enemySvc then
        return
    end
    local scatter = tonumber(self._config.scatter) or 8
    local state = self._spawners[part]
    local cap = tonumber(self._config.max_alive) or 6
    for _, unit in ipairs(wave.units or {}) do
        for _ = 1, (tonumber(unit.count) or 1) do
            if #state.alive >= cap then
                break -- never bury the player / stockpile for the next one
            end
            local offset = Vector3.new(
                (rng:NextNumber() * 2 - 1) * scatter,
                3,
                (rng:NextNumber() * 2 - 1) * scatter
            )
            pcall(function()
                local r = enemySvc:SpawnEnemy(player, unit.enemy, {
                    position = part.Position + offset,
                    home = part.Position, -- loiter anchor
                })
                if r and r.ok and r.model then
                    table.insert(state.alive, r.model)
                end
            end)
        end
    end
    self._logger:Info("Baddie wave spawned", {
        spawner = part.Name,
        player = player.Name,
        units = #(wave.units or {}),
    })
end

function BaddieSpawnerService:Start()
    if not self._config then
        self._logger:Warn("BaddieSpawnerService: no spawners config; idle")
        return
    end
    local radius = tonumber(self._config.radius) or 50
    local cd = self._config.cooldown
    local cdMin = (type(cd) == "table" and tonumber(cd.min)) or tonumber(cd) or 60
    local cdMax = (type(cd) == "table" and tonumber(cd.max)) or cdMin
    local cap = tonumber(self._config.max_alive) or 6
    local rng = Random.new()
    task.spawn(function()
        local rescanAt = 0
        while true do
            local now = os.clock()
            if now >= rescanAt then
                self:_scan()
                rescanAt = now + 15 -- pick up newly synced map parts
            end
            for part, state in pairs(self._spawners) do
                -- prune dead/cleaned baddies from the spawner's alive list
                for i = #state.alive, 1, -1 do
                    local m = state.alive[i]
                    if not m.Parent then
                        table.remove(state.alive, i)
                    end
                end
                if not part.Parent then
                    self._spawners[part] = nil
                elseif now >= state.cooldownUntil and #state.alive < cap then
                    for _, player in ipairs(Players:GetPlayers()) do
                        local hrp = player.Character
                            and player.Character:FindFirstChild("HumanoidRootPart")
                        if hrp and (hrp.Position - part.Position).Magnitude <= radius then
                            state.cooldownUntil = now + rng:NextNumber(cdMin, cdMax)
                            self:_trigger(part, player, rng)
                            break
                        end
                    end
                end
            end
            task.wait(0.5)
        end
    end)
end

return BaddieSpawnerService
