--[[
    SupportAura — pure resolver for a pet's team "buffer" aura (Halo & Horns).

    Every zone has ONE support pet whose presence boosts the rest of the squad — the
    City-of-Heroes "buffer". The aura is config-as-code: configs/pet_roles.lua carries a
    `support_auras` table keyed by PetType (a pet can also override with a `SupportAura`
    model attribute later). This module is the Roblox-free lookup; EnemyService:_supportPass
    applies whatever it returns on the aura's interval.

    Aura kinds (the zone flavours + self powers), all dev-tunable in pet_roles.lua:
      heal     — mend the most-hurt ally (Grass / bunny). { interval, fraction|amount }
      defense  — team damage reduction; writes TeamDefenseBuff on allies (Ice / penguin).
      offense  — team +damage on the owner; boosts mining AND combat (Lava / emberimp).
      yield    — team +coin payout on mining (Desert / meerkat). { interval, mult, duration }
      luck     — hatch luck for the PLAYER (Grass / bunny).
      rage     — SELF damage buff while hurt (bear). { enrage_below, mult, interval, duration }
      hold     — CONTROL: pin one enemy (no move/attack) for `duration`s; targets the player's focus
                 (assist → most-targeted-by-pets → nearest). { interval = recharge, duration } (experimental)
      empower  — SINGLE-TARGET damage buffer (the "carry amplifier"): instead of lifting the whole
                 team a little (offense), it stamps a per-pet damage buff on the squad's STRONGEST
                 ally — concentrate, don't spread. { interval, mult, duration, target = "highest_power" }

    SupportAura.forPet(petType, rolesConfig) -> aura table (with .kind) | nil
    SupportAura.isBuffer(petType, rolesConfig) -> boolean
    SupportAura.isEnraged(aura, healthFraction) -> boolean
    SupportAura.rageMultiplier(aura, healthFraction, variantMult) -> mult >= 1 | nil
    SupportAura.rageFraction(auras, healthFraction, variantMult) -> additive fraction >= 0
    SupportAura.rankTargets(candidates, rule) -> array of candidate keys, best-first
]]

local SupportAura = {}

function SupportAura.forPet(petType, rolesConfig)
    local list = SupportAura.aurasFor(petType, rolesConfig)
    return list and list[1] or nil
end

-- A pet's auras as a LIST. Config value may be a single aura table { kind = ... } or an
-- ARRAY of them (the colorado_creator SPECIES carries every buffer — Jason). Single
-- wraps to a one-list.
function SupportAura.aurasFor(petType, rolesConfig)
    if type(rolesConfig) ~= "table" or petType == nil then
        return nil
    end
    local auras = rolesConfig.support_auras
    if type(auras) ~= "table" then
        return nil
    end
    local entry = auras[petType]
    if type(entry) ~= "table" then
        return nil
    end
    if entry.kind ~= nil then
        return { entry }
    end
    if type(entry[1]) == "table" and entry[1].kind ~= nil then
        return entry
    end
    return nil
end

function SupportAura.isBuffer(petType, rolesConfig)
    return SupportAura.forPet(petType, rolesConfig) ~= nil
end

-- ── RAGE (kind = "rage") — the ONE implementation of the rage rules ──────────
-- Jason: "the same unified code path — if we change something in one place we
-- don't have to change it in multiple places." Both consumers route here:
--   live: EnemyService:_supportPass (stamps RageDamageBuff/RageFxUntil on the pet)
--   sim:  BattleSim (adds the fraction to each simulated swing while enraged)
-- Knobs on the aura entry: enrage_below = remaining-health fraction at or below
-- which the pet rages; mult = damage multiplier at basic — the FRACTION (mult-1)
-- scales by the pet's variant effect multiplier (golden/rainbow rage harder).

function SupportAura.isEnraged(aura, healthFraction)
    if type(aura) ~= "table" or aura.kind ~= "rage" then
        return false
    end
    local below = math.clamp(tonumber(aura.enrage_below) or 0.5, 0, 1)
    return (tonumber(healthFraction) or 1) <= below
end

-- The damage MULTIPLIER (>= 1) while raging, or nil when calm / not a rage aura.
function SupportAura.rageMultiplier(aura, healthFraction, variantMult)
    if not SupportAura.isEnraged(aura, healthFraction) then
        return nil
    end
    return 1 + ((tonumber(aura.mult) or 1) - 1) * (tonumber(variantMult) or 1)
end

-- Sum of rage FRACTIONS across a pet's aura list (rage lives on the additive
-- pet_damage axis, so multiple rage auras ADD like every other source there).
function SupportAura.rageFraction(auras, healthFraction, variantMult)
    local f = 0
    for _, aura in ipairs(auras or {}) do
        local m = SupportAura.rageMultiplier(aura, healthFraction, variantMult)
        if m then
            f += m - 1
        end
    end
    return f
end

-- ── SINGLE-TARGET selection (kind = "empower" and any future single-target aura) ──
-- Rank candidate allies for a single-target aura so the caller can lift the top-N. Pure +
-- deterministic (no randomness — ties break by insertion order, so the same squad picks the same
-- carry every tick and the buff doesn't flicker between equals).
--   candidates : array of { key = <opaque, e.g. the pet model>, power = number }
--   rule       : "highest_power" (default) | "lowest_power"
-- Returns a NEW array of the candidate KEYS, best-first.
function SupportAura.rankTargets(candidates, rule)
    local list = {}
    for i, c in ipairs(candidates or {}) do
        if type(c) == "table" then
            list[#list + 1] = { key = c.key, power = tonumber(c.power) or 0, order = i }
        end
    end
    local lowest = rule == "lowest_power"
    table.sort(list, function(a, b)
        if a.power ~= b.power then
            if lowest then
                return a.power < b.power
            end
            return a.power > b.power
        end
        return a.order < b.order -- stable tiebreak: earlier candidate wins
    end)
    local out = {}
    for i, c in ipairs(list) do
        out[i] = c.key
    end
    return out
end

return SupportAura
