--[[
    Daily login streak — Halo & Horns [PROTOTYPE] (Phase 7).

    A streak is a Claim with a time/cadence gate instead of a Condition. Day indices
    are passed to the pure DailyStreak resolver (no clock in the core). The calendar
    repeats every `cycle_length` days; missing more than `max_gap_days` resets it.
    The "Daily ❗" badge = 1 when a claim is available today.
]]

return {
    max_gap_days = 1,
    cycle_length = 7,
    calendar = {
        [1] = { currencies = { coins = 100 } },
        [2] = { currencies = { coins = 250 } },
        [3] = { currencies = { crystals = 5 } },
        [4] = { currencies = { coins = 500 } },
        [5] = { currencies = { gems = 2 } },
        [6] = { currencies = { crystals = 10 } },
        [7] = { pets = { { id = "bear", variant = "golden" } } },
    },
}
