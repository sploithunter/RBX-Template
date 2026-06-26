--[[
    FocusService — Feature 12 (Player Character / Spirit Presence).

    The player is an ethereal, INVULNERABLE supporter — there is NO health stat.
    The only player resource is Focus, spent on support powers and disrupted by
    enemy "Sundering" attacks; it regenerates over time. Focus is persisted on
    profile.Focus (lazy-initialized to focus_max — no schema migration). The pure
    FocusMath core does the arithmetic; this service owns the profile state and
    the runtime invulnerability hook.

    The Focus economy lives here. PowerService:Cast now CHARGES a power's focus_cost via
    FocusService:Cast at the commit point (an empty pool refuses the cast with not_enough_focus);
    cooldown lives with the Power system. `Cast(player, cost)` is the spend/affordability gate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FocusMath = require(ReplicatedStorage.Shared.Game.FocusMath)

local FocusService = {}
FocusService.__index = FocusService

function FocusService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._config = self._configLoader:LoadConfig("focus")
    self._invulnConns = {}
end

-- Make the player's character ethereal/invulnerable: no effective damage, no
-- death. Realizes "Player has 0 HP and cannot be damaged" (Feature 12) without a
-- health stat by pinning health and disabling the Dead state.
function FocusService:_makeInvulnerable(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = character:WaitForChild("Humanoid", 5)
    end
    if not humanoid then
        return
    end
    humanoid.MaxHealth = math.huge
    humanoid.Health = math.huge
    pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    end)
    humanoid.HealthChanged:Connect(function()
        if humanoid.Health < humanoid.MaxHealth then
            humanoid.Health = humanoid.MaxHealth
        end
    end)
end

function FocusService:Start()
    local function hookPlayer(player)
        if player.Character then
            self:_makeInvulnerable(player.Character)
        end
        player.CharacterAdded:Connect(function(character)
            self:_makeInvulnerable(character)
        end)
    end
    for _, player in ipairs(Players:GetPlayers()) do
        hookPlayer(player)
    end
    Players.PlayerAdded:Connect(hookPlayer)

    -- FOCUS REGEN LOOP: refill every player's Focus once a second (regen_per_second, clamped to
    -- focus_max). RegenTick existed but NOTHING drove it — harmless while casting was free (Focus sat
    -- at max forever), but now that PowerService:Cast charges focus_cost, a missing regen loop drained
    -- the pool to 0 and it never refilled, silently blocking EVERY cast. Skip players already at max so
    -- we don't spam non-critical saves.
    task.spawn(function()
        while true do
            task.wait(1)
            for _, player in ipairs(Players:GetPlayers()) do
                local st = self:Get(player)
                if st and st.ok then
                    if (st.focus or 0) < (st.max or 0) then
                        self:RegenTick(player, 1)
                    end
                    self:_push(player) -- keep the HUD bar fresh (regen rise / join / sunder)
                end
            end
        end
    end)
end

local function focusOf(self, data)
    if type(data.Focus) ~= "number" then
        data.Focus = self._config.focus_max
    end
    return data.Focus
end

function FocusService:Get(player)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    return { ok = true, focus = focusOf(self, data), max = self._config.focus_max }
end

-- Replicate the live pool to the client via `Focus` / `FocusMax` player attributes so the HUD bar
-- (PlayerBar) can read + animate it the same way it reads Level/XP. Pure UI mirror — no save.
function FocusService:_push(player)
    local data = self._dataService and self._dataService:GetData(player)
    if not data then
        return
    end
    player:SetAttribute("Focus", focusOf(self, data))
    player:SetAttribute("FocusMax", self._config.focus_max)
end

-- Spend Focus to cast a power. Rejects (no spend) if the pool can't cover it.
function FocusService:Cast(player, cost)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    local result = FocusMath.cast(focusOf(self, data), cost)
    if not result.ok then
        return { ok = false, reason = result.reason, focus = result.focus }
    end
    data.Focus = result.focus
    self._dataService:RequestSave(player, "focus_cast", { critical = false })
    self:_push(player) -- HUD drops the instant you spend
    return { ok = true, focus = result.focus, spent = cost }
end

-- A Sundering enemy attack drains Focus (never below 0).
function FocusService:Sunder(player, amount)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    local before = focusOf(self, data)
    data.Focus = FocusMath.sunder(before, amount, self._config)
    self._dataService:RequestSave(player, "focus_sunder", { critical = false })
    return { ok = true, focus = data.Focus, drained = before - data.Focus }
end

-- Regenerate Focus over `elapsed` seconds (clamped to focus_max).
function FocusService:RegenTick(player, elapsed)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end
    data.Focus = FocusMath.regen(focusOf(self, data), elapsed, self._config)
    self._dataService:RequestSave(player, "focus_regen", { critical = false })
    return { ok = true, focus = data.Focus }
end

return FocusService
