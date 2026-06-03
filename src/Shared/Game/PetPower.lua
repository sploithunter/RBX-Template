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

-- === Mining/Combat power profile (Pet Realm "two numbers on the card") ===
-- Splits a pet's resolved base power (the huge/level-aware number above, i.e. its Power value)
-- into the two INTRINSIC card numbers (⛏ mining / ⚔ combat) and their live EFFECTIVE values.
-- One function for both the inventory display and the damage path (via PetPowerView), so the
-- shown number can never drift from the dealt number. Adding a future multiplier = add a key to
-- `context`; display + damage update together.
--
--   input = {
--     base,           -- resolved base power (Power value: dev base × huge × pet level)
--     baseScale?,     -- global lever (config base_scale; default 1)
--     elementMult?,   -- intrinsic element flat attack (combat_fx element_stats; default 1)
--     variantMult?,   -- intrinsic golden/rainbow bump (pet_power.variant_mult; default 1)
--     miningMult?,    -- intrinsic mining aptitude (role/pet; default 1)
--     combatMult?,    -- intrinsic combat aptitude (role/pet; default 1)
--     context = { lvl = m, boost = m, ... }  -- contextual multipliers (player), all default 1
--   }
local function num(v, default)
    return tonumber(v) or default
end

function PetPower.resolveProfile(input)
    input = input or {}
    local base = num(input.base, 0) * num(input.baseScale, 1)
    local intrinsicCommon = base * num(input.elementMult, 1) * num(input.variantMult, 1)
    local miningBase = intrinsicCommon * num(input.miningMult, 1)
    local combatBase = intrinsicCommon * num(input.combatMult, 1)

    local contextMult = 1
    if type(input.context) == "table" then
        for _, v in pairs(input.context) do
            contextMult = contextMult * num(v, 1)
        end
    end

    return {
        base = base,
        intrinsicCommon = intrinsicCommon,
        miningBase = miningBase,
        combatBase = combatBase,
        contextMult = contextMult,
        miningEffective = miningBase * contextMult,
        combatEffective = combatBase * contextMult,
    }
end

-- Round a power number for DISPLAY only (damage keeps its own floor in PetCombat).
function PetPower.roundForDisplay(n, mode)
    n = num(n, 0)
    if mode == "floor" then
        return math.floor(n)
    elseif mode == "ceil" then
        return math.ceil(n)
    end
    return math.floor(n + 0.5)
end

return PetPower
