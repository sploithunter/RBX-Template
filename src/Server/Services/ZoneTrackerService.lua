--[[
    ZoneTrackerService — server-authoritative "which area is each player standing in".

    Replaces the fragile touch-part area detection with config-bounds resolution: a few times a
    second it tests every player's HiddenRootPart position against the authored area boxes in
    configs/areas.lua (via the pure ZoneResolver) and writes the result to ONE SSOT player
    attribute, `CurrentArea`. Consumers read that attribute (and listen to its change signal):
      - AutoTargetService scopes farming to the current area's footprint;
      - area music (future) swaps on CurrentArea change;
      - per-zone breakable activation (future) can gate spawning on the active area.

    Robust to falls/teleports (no Touched dependency), cheap (a handful of box tests/player),
    and sticky (hysteresis margin) so standing on a shared edge doesn't flicker. Pure math lives
    in ZoneResolver; this service only does the polling + attribute write.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZoneResolver = require(ReplicatedStorage.Shared.Game.ZoneResolver)

local ZoneTrackerService = {}
ZoneTrackerService.__index = ZoneTrackerService

local CURRENT_AREA_ATTR = "CurrentArea"

function ZoneTrackerService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader

    local areasConfig = self._configLoader and self._configLoader:LoadConfig("areas") or {}
    self._bounds = ZoneResolver.boundsFromAreas(areasConfig)

    local cfg = (self._configLoader and self._configLoader:LoadConfig("zone_tracker")) or {}
    self._pollInterval = tonumber(cfg.poll_interval) or 0.25
    self._verticalBand = tonumber(cfg.vertical_band) or 80
    self._boundaryMargin = tonumber(cfg.boundary_margin) or 6
    self._defaultArea = cfg.default_area or "Spawn"

    if self._logger then
        self._logger:Info("ZoneTrackerService initialized", {
            areas = #self._bounds,
            pollInterval = self._pollInterval,
        })
    end
end

-- Public getter — the SSOT for "where is this player".
function ZoneTrackerService:GetCurrentArea(player)
    if not player then
        return nil
    end
    return player:GetAttribute(CURRENT_AREA_ATTR)
end

local function rootPosition(player)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return nil
    end
    local p = hrp.Position
    return { x = p.X, y = p.Y, z = p.Z }
end

function ZoneTrackerService:_resolveFor(player)
    local pos = rootPosition(player)
    if not pos then
        return -- character not spawned yet; leave the last known area in place
    end

    local current = player:GetAttribute(CURRENT_AREA_ATTR)
    local resolved = ZoneResolver.resolveSticky(pos, self._bounds, current, {
        verticalBand = self._verticalBand,
        margin = self._boundaryMargin,
        default = self._defaultArea,
    })

    if resolved ~= current then
        player:SetAttribute(CURRENT_AREA_ATTR, resolved)
        if self._logger then
            self._logger:Info("Area changed", {
                player = player.Name,
                from = current or "(none)",
                to = resolved,
            })
        end
    end
end

function ZoneTrackerService:Start()
    if #self._bounds == 0 then
        if self._logger then
            self._logger:Warn(
                "ZoneTrackerService: no area bounds in configs/areas.lua; CurrentArea will stay at default"
            )
        end
    end

    -- Seed CurrentArea immediately on spawn so farming/music have a value before the first poll.
    local function onCharacter(player)
        player.CharacterAdded:Connect(function()
            task.wait(0.5) -- let the HRP settle at the spawn location
            self:_resolveFor(player)
        end)
        if player.Character then
            self:_resolveFor(player)
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        onCharacter(player)
    end
    Players.PlayerAdded:Connect(onCharacter)

    -- Throttled poll loop.
    local accumulator = 0
    RunService.Heartbeat:Connect(function(dt)
        accumulator += dt
        if accumulator < self._pollInterval then
            return
        end
        accumulator = 0
        for _, player in ipairs(Players:GetPlayers()) do
            self:_resolveFor(player)
        end
    end)
end

return ZoneTrackerService
