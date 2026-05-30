--[[
    PetPower — single source of truth for a pet's CONFIGURED BASE power.

    Both the server (PetHandler team-power / mining) and the client (inventory
    display) call this, so the number shown and the number that fights can never
    diverge again. Huge-aware: a huge pet uses `huge_base_power` (e.g. bear 100)
    instead of its variant `power` (bear 10).

    Eternal team-scaling (power = % of the top-N non-eternal baseline) is layered
    on TOP of this, server-side, where team context exists — see PetHandler
    resolveEffectivePetPower. This module is purely the per-pet base.

    No Roblox APIs (pure); headless-tested.

      configuredBasePower(petConfigData, isHuge)            -> number
      withLevel(base, level, progressionConfig)             -> integer
      basePowerForLevel(petConfigData, isHuge, level, prog) -> integer (compose)
]]

local PetPower = {}

-- petConfigData is the table returned by configs/pets.lua getPet(petType, variant)
-- (it carries `power` and, when configured, `huge_base_power`).
function PetPower.configuredBasePower(petConfigData, isHuge)
    if not petConfigData then
        return 1
    end
    if isHuge then
        local hugeBase = tonumber(petConfigData.huge_base_power)
        if hugeBase then
            return hugeBase
        end
    end
    return tonumber(petConfigData.power) or 1
end

-- Apply the shared level-progression multiplier (configs/pet_progression.lua).
function PetPower.withLevel(base, level, progressionConfig)
    local multiplier = 1
    if progressionConfig and progressionConfig.enabled ~= false then
        local scaling = progressionConfig.power_scaling or {}
        local perLevel = tonumber(scaling.percent_per_level) or 0
        local maxBonus = tonumber(scaling.max_bonus_percent) or 0
        local lvl = math.max(1, math.floor(tonumber(level) or 1))
        multiplier = 1 + math.min(maxBonus, math.max(0, (lvl - 1) * perLevel))
    end
    return math.max(1, math.floor((tonumber(base) or 1) * multiplier))
end

function PetPower.basePowerForLevel(petConfigData, isHuge, level, progressionConfig)
    return PetPower.withLevel(
        PetPower.configuredBasePower(petConfigData, isHuge),
        level,
        progressionConfig
    )
end

return PetPower
