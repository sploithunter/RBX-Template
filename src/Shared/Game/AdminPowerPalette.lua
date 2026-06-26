--[[
    AdminPowerPalette — PURE grouping of every power into the admin power-bar layout.

    The admin power bar (admin-only test surface) shows ONE origin at a time via tabs, and within an
    origin splits powers into two controls:
      • CASTABLE  — an active cast (sandstorm, cataclysm, …) → a cast button (fires the real Cast path,
                    focus + cooldown respected).
      • ALWAYS-ON — a passive/toggle (Hasten, Swift, XP Surge, Magnet, Rage) → an on/off toggle. These
                    apply by OWNERSHIP, not by casting (PowerService:_applyOwnedPassives), so the bar
                    toggles a transient stamp instead of "casting" them.

    Classification mirrors the SERVER's own always-on rule (PowerService ~line 1616): a power is
    always-on iff its effect_kind is `passive` or `toggle`. Origin = the power's `archetype`, or
    "generic" for the shared farming/luck/utility pool (def.generic or no archetype) — that's the tab
    Hasten lives on.

    Pure + Roblox-free (reads only the powers config table) so it unit-tests headless and the bar's
    contents are deterministic.

    Run: mise run test-headless
]]

local AdminPowerPalette = {}

local GENERIC = "generic"

-- A power is ALWAYS-ON (toggle control, not a cast button) iff its effect_kind is passive or toggle —
-- the exact rule the server uses to stamp owned passives.
local function isAlwaysOn(powersConfig, def)
    local kinds = powersConfig and powersConfig.effect_kinds
    local kind = kinds and def and def.effect and kinds[def.effect]
    return kind ~= nil and (kind.passive == true or kind.toggle == true)
end

-- The origin (tab) a power belongs to: its archetype, else GENERIC for the shared pool.
function AdminPowerPalette.originOf(def)
    if not def or def.generic == true or def.archetype == nil then
        return GENERIC
    end
    return def.archetype
end

AdminPowerPalette.GENERIC = GENERIC

-- Group every power into { groups = { [origin] = { castable = {id,…}, always_on = {id,…} } },
-- order = { origin,… } }. Lists are sorted (stable bar). `originOrder` (optional) pins the leading
-- tab order (e.g. the archetype order); any origins not listed follow alphabetically, GENERIC last.
function AdminPowerPalette.group(powersConfig, originOrder)
    local groups = {}
    for powerId, def in pairs((powersConfig and powersConfig.powers) or {}) do
        local origin = AdminPowerPalette.originOf(def)
        local g = groups[origin]
        if not g then
            g = { castable = {}, always_on = {} }
            groups[origin] = g
        end
        local bucket = isAlwaysOn(powersConfig, def) and g.always_on or g.castable
        bucket[#bucket + 1] = powerId
    end
    for _, g in pairs(groups) do
        table.sort(g.castable)
        table.sort(g.always_on)
    end

    -- Tab order: pinned origins first (in the given order, if they have powers), then any remaining
    -- non-generic origins alphabetically, then GENERIC last (the catch-all utility tab).
    local order, seen = {}, {}
    for _, origin in ipairs(originOrder or {}) do
        if groups[origin] and not seen[origin] then
            order[#order + 1] = origin
            seen[origin] = true
        end
    end
    local rest = {}
    for origin in pairs(groups) do
        if not seen[origin] and origin ~= GENERIC then
            rest[#rest + 1] = origin
        end
    end
    table.sort(rest)
    for _, origin in ipairs(rest) do
        order[#order + 1] = origin
    end
    if groups[GENERIC] then
        order[#order + 1] = GENERIC
    end

    return { groups = groups, order = order }
end

return AdminPowerPalette
