--[[
    tutorial — the new-player guided path (config-as-code, EVENT-DRIVEN).

    Each step COMPLETES off a named GameEvents bus event (docs/GAME_EVENTS.md) — the tutorial
    never polls game state and no gameplay service knows it exists. TutorialService taps every
    server-side fireGameEvent(player, name, ctx) call; when the current step's `complete_on`
    event arrives (count times), the player advances. Add/reorder/remove steps HERE only.

    Step shape:
      id          stable key (progress persists by index, id is for logs/UI)
      title/body  what the objective capsule shows
      target      where the client should point the player:
                    { kind = "egg" }                 — beacon over the nearest world egg
                    { kind = "ui", name = "<gui>" }  — pulse the named GuiObject (recursive find)
                    { kind = "none" }                — text only
      complete_on { event = "<bus event>", count = N (default 1) }

    `veteran_skip`: an existing save with claimed level >= this (or any pet hatched before the
    tutorial existed) silently completes the whole thing — only genuinely new players see it.
]]

return {
    veteran_skip = { min_claimed_level = 3 },

    steps = {
        {
            id = "hatch_first_egg",
            title = "Hatch your first pet",
            body = "Walk to the glowing egg and hatch it — pets do everything for you here.",
            target = { kind = "egg" },
            complete_on = { event = "egg_hatch" },
        },
        {
            id = "equip_pet",
            title = "Equip your pet",
            body = "Open the Pets menu and click your new pet to equip it — equipped pets follow you and mine. New players can equip 3!",
            target = { kind = "ui", name = "PetsButton" },
            complete_on = { event = "pet_equipped" },
        },
        {
            id = "farm_crystals",
            title = "Mine some crystals",
            body = "Pets mine nearby crystals when Farm Near is ON — if the glowing button says Off, click it! Click a crystal to BOOST it, scoop up the coins. Small crystals = fast but cheap; big = slow but rich!",
            target = { kind = "ui", name = "Farming" }, -- pulse the Farm button
            complete_on = { event = "coin_payout", count = 3 },
        },
        {
            id = "hatch_another",
            title = "Grow your team",
            body = "Spend those coins on another egg — more pets means faster mining.",
            target = { kind = "egg" },
            complete_on = { event = "egg_hatch" },
        },
        {
            id = "claim_level",
            title = "Level up",
            body = "Mining earns XP. When the ASCEND button appears below your name, press it to claim your level.",
            target = { kind = "ui", name = "LevelUpButton" },
            complete_on = { event = "level_claimed" },
        },
        {
            id = "pick_power",
            title = "Choose a power",
            body = "Leveling offers you powers. Hover one to read what it does, then pick and commit.",
            target = { kind = "none" },
            complete_on = { event = "power_selected" },
        },
        {
            id = "cast_power",
            title = "Use your power",
            body = "Your new power is on the hotbar at the bottom — press its number key (or tap it) to cast.",
            target = { kind = "none" },
            complete_on = { event = "power_cast" },
        },
    },
}
