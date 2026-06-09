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

    -- Default layout for a new player: which slots get powers / rosters / tacticals. Power slots
    -- are filled from the player's archetype pool in order (each archetype's bar shows its powers).
    defaults = {
        power_slots = { 1, 2, 3, 4, 5, 6 },
        roster_slots = { 7, 8, 9 },
        tactical_slots = { 10, 11, 12, 13 },
    },

    -- [PROTOTYPE] Explicit default bar OVERRIDE. When set, a fresh hotbar uses exactly this layout
    -- (archetype-independent) instead of the per-archetype fill above — handy for testing a specific
    -- kit so a restart reliably comes up with it. Set to nil to fall back to the `defaults` above
    -- (power slots fill from OWNED powers, so a fresh character's power slots stay empty until they
    -- pick — the real level-up flow). Each entry is { slot, type, target }.
    --
    -- NIL while we test the level-up system (powers come only from picks). To re-seed a fixed kit
    -- for VFX/signature testing, restore a table here, e.g. the old Pyromancer kit:
    --   { {slot=1,type="power",target="cataclysm"}, {slot=2,type="power",target="wildfire"},
    --     {slot=3,type="power",target="firestorm"}, {slot=4,type="power",target="mark_of_flame"},
    --     {slot=5,type="power",target="ember_ward"}, {slot=6,type="power",target="eruption"},
    --     {slot=7,type="roster",target="Roster 1"}, {slot=8,type="tactical",target="scatter"},
    --     {slot=9,type="tactical",target="focus_fire"}, {slot=10,type="tactical",target="regroup"} }
    default_binds = nil,
}
