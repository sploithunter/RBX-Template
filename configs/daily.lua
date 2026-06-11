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
    -- Denominated in the LIVE economy (Jason: legacy 100-coins / 5-crystals predated
    -- the per-zone coin system and read as noise). Yardsticks: one small ore break
    -- pays ~20, Meadow unlock = 2000 crystals (~3 min of mining). Each day gifts a
    -- few minutes of progress; day 4 = exactly one Meadow unlock; day 7 stays the
    -- golden-bear streak payoff. Gems keep their shop sinks.
    calendar = {
        [1] = { currencies = { crystals = 500 } },
        [2] = { currencies = { crystals = 1000 } },
        [3] = { currencies = { gems = 2 } },
        [4] = { currencies = { crystals = 2000 } },
        [5] = { currencies = { gems = 5 } },
        [6] = { currencies = { crystals = 4000 } },
        [7] = { pets = { { id = "bear", variant = "golden" } } },
    },
}
