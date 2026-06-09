--[[
    game_events — the EVENT -> REACTIONS registry (config-as-code).

    Code fires a named gameplay event (GameEvents.fire("level_up", ctx)); THIS config decides what
    reacts. Each reaction kind is a key the client dispatcher (src/Client/Systems/GameEvents.lua)
    knows how to apply:

        sound = "<key in configs/sounds.lua>"   -- play that sound on its configured bus
        -- (planned) vfx = "<CombatFX/effect spec>", toast = "<text>", ...

    Add or extend a row to react to an event WITHOUT touching the firing code; remove a row to
    silence it. The only inherently-code part is detecting the event and calling fire().

    Event sources:
      level_up   — the player's claimed level increased        (client: LevelUpController)
    Planned (wire the source, then add a row here): death, hit, area_change, egg_hatch, purchase.
]]

return {
    level_up = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 255, 205, 70 } }, -- gold celebratory burst at the player
    },
}
