--[[
    Power / status icons — Halo & Horns [PROTOTYPE].

    Roblox Image asset ids for the hotbar slots, pet status badges, and squad action
    buttons. Imported as Images (correct for ImageLabel). Aura art = squad/AoE,
    target art = single-target. Add ids here as they're made; UI falls back to text
    labels for anything without an icon.
]]

local function id(n)
    return "rbxassetid://" .. n
end

return {
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
}
