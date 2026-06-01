--[[
    Power / status icons — Halo & Horns [PROTOTYPE].

    Roblox Image asset ids for the hotbar slots, pet status badges, and squad action
    buttons. Imported as Images (correct for ImageLabel). Aura art = squad/AoE,
    target art = single-target. Add ids here as they're made; UI falls back to text
    labels for anything without an icon.

    SCALE: many imported icons carry a transparent margin/border baked into the
    image. Containers clip their icon, so a scale > 1 zooms the art to crop that
    border away. `default_scale` applies to every icon; `scales` overrides per asset
    id when one piece of art needs more/less zoom. Tune live, then record here.
]]

local function id(n)
    return "rbxassetid://" .. n
end

local M = {
    -- Hotbar slot icon per power id (falls back to the slot's text label if absent).
    powers = {
        stone_skin = id(120424299023186), -- shield, single target
        bulwark = id(73499491406959), -- shield aura (squad damage-reduction)
        ice_armor = id(73499491406959),
        dune_shield = id(73499491406959),
        ember_ward = id(73499491406959),
        dodge = id(120424299023186),
        mountains_strength = id(102528688168498), -- damage buff aura
    },

    -- Pet status-badge icons (keys match SquadHud PET_EFFECTS).
    status = {
        defense = id(73499491406959), -- DEF (Bulwark) -> shield
        shield = id(73499491406959), -- SH (absorption pool) -> shield
        damage = id(102528688168498), -- DMG (damage buff) -> damage buff
    },

    -- Squad-HUD action buttons.
    actions = {
        heal = id(109752593245713), -- heal aura
        buff = id(102528688168498), -- damage buff aura
    },

    -- Spare art ready for single-target / assist-target variants when those land.
    spare = {
        heal_target = id(124914444699157),
        damage_target = id(91449088100042),
        shield_target = id(120424299023186),
    },

    -- Zoom applied inside the (clipping) container to crop a transparent border.
    -- 1 = fit exactly; >1 = zoom in. Per-asset overrides win over default_scale.
    default_scale = 1.25,
    scales = {
        -- e.g. [id(73499491406959)] = 1.4,
    },
}

-- Zoom factor for a given image string ("" / nil -> 1, i.e. no icon present).
function M.scaleFor(image)
    if not image or image == "" then
        return 1
    end
    return M.scales[image] or M.default_scale
end

return M
