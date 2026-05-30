--[[
    Hotbar / Command Bar — Halo & Horns [PROTOTYPE] (Feature 16).

    A 20-slot hotbar (1-9, 0, Shift+1-9, Shift+0). Each slot holds one bind:
    { type, target } where type is power / roster / pet / tactical. New players get
    archetype defaults; bindings persist (profile.Hotbar). Pure rules:
    `src/Shared/Game/HotbarLogic.lua`.
]]

return {
    slot_count = 20,
    bind_types = { "power", "roster", "pet", "tactical" },
    tactical_commands = { "scatter", "focus_fire", "regroup", "retreat" },

    -- Default layout for a new player: which slots get powers / rosters / tacticals.
    defaults = {
        power_slots = { 1, 2, 3, 4 },
        roster_slots = { 5, 6, 7 },
        tactical_slots = { 8, 9, 10 },
    },
}
