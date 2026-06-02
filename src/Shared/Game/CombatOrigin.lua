--[[
    CombatOrigin (pure) — resolve a unit's effective COMBAT ELEMENT for VFX / animation / stats.

    Canonical combat elements are the four biomes: grass / lava / ice / desert. (The heaven/hell
    hatch element — neutral/light/shadow, see PetElement — is a SEPARATE alignment axis and is NOT
    a combat element.) Player archetypes map onto the same four via their theme, with the
    geomancer's "earth" reconciled to grass:
        geomancer -> grass   pyromancer -> lava   cryomancer -> ice   sandwalker -> desert

    Hybrid + configurable (the design decision): by default each pet fights as its OWN biome
    origin (collection variety); with config.unify_to_player the whole squad fights as the
    PLAYER's archetype element (build identity). Pure + Roblox-free; config-driven.
]]

local CombatOrigin = {}

-- The canonical combat elements. (cfg.elements may override this list.)
CombatOrigin.ELEMENTS = { "grass", "lava", "ice", "desert" }

local function elementSet(cfg)
    local list = (cfg and cfg.elements) or CombatOrigin.ELEMENTS
    local set = {}
    for _, e in ipairs(list) do
        set[e] = true
    end
    return set
end

-- Map a player archetype to its canonical combat element (config.archetype_element).
function CombatOrigin.archetypeElement(archetype, cfg)
    local map = cfg and cfg.archetype_element
    if archetype and map then
        return map[archetype]
    end
    return nil
end

-- Resolve the effective combat element for a pet given the owning player.
--   petElement      — the pet's own biome origin (grass/lava/ice/desert)
--   playerArchetype — the owner's archetype id (geomancer/...), for the unify path
--   cfg             — combat_fx.origin { unify_to_player, default_element, archetype_element, elements }
-- Returns a valid canonical element, always (falls back to default_element, then "grass").
function CombatOrigin.resolve(petElement, playerArchetype, cfg)
    cfg = cfg or {}
    local set = elementSet(cfg)
    local default = cfg.default_element or "grass"

    -- Unify path: the whole squad fights as the player's archetype element.
    if cfg.unify_to_player then
        local pe = CombatOrigin.archetypeElement(playerArchetype, cfg)
        if pe and set[pe] then
            return pe
        end
    end

    -- Default: the pet's own biome origin (if it's a valid canonical element).
    if petElement and set[petElement] then
        return petElement
    end

    return set[default] and default or CombatOrigin.ELEMENTS[1]
end

return CombatOrigin
