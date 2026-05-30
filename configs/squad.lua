--[[
    Active squad hierarchy — Halo & Horns [PROTOTYPE] (Feature 9).

    Three tiers: Inventory (all owned) -> Equipped (followers) -> Active Squad
    (fighters). Swapping the active squad mid-combat has a cooldown; out of combat
    it is instant. Read by `src/Shared/Game/ActiveSquad.lua`.
]]

return {
    limits = {
        inventory = 1000,
        equipped = 10,
        active_squad = 5,
    },
    swap_cooldown_seconds = 5,
}
