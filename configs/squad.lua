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

    -- Slot recovery (the timer the PLAYER manages). When a pet leaves its active
    -- slot the SLOT recharges before it can be re-crewed — this paces throughput
    -- regardless of how deep a stack is, so 1000 pets can't be spammed forever.
    -- Distinct from the per-pet / stack-pool spirit-form recovery (you still can't
    -- re-summon a pet that was just downed; that lives in spirit_form/stack_pool).
    --   recall_cooldown_seconds — SHORT: you proactively pulled a Strained/Critical
    --       pet before it fell (rewards attention; still capped so recall isn't spam).
    --   down_cooldown_seconds   — LONG: the slot's pet was fully downed (the real cost).
    -- Both are balance knobs (everything is config-driven); tune against enemy DPS.
    slot_recovery = {
        recall_cooldown_seconds = 4,
        down_cooldown_seconds = 20,
    },
}
