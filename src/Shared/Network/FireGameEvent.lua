--[[
    FireGameEvent — server-side one-liner for the GameEvents bus (docs/GAME_EVENTS.md).

    Usage (any server service):
        local fireGameEvent = require(ReplicatedStorage.Shared.Network.FireGameEvent)
        fireGameEvent(player, "quest_complete", { quest = questId })

    Sends Signals.GameEvent to that player's client, where GameEvents.start() dispatches the
    reactions declared in configs/game_events.lua (sound / vfx / ...). Firing an event with no
    config entry is a no-op, so sources can fire unconditionally and reactions stay config-only.
    pcall'd: a celebration must never break the gameplay mutation that triggered it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)

return function(player, name, ctx)
    pcall(function()
        Signals.GameEvent:FireClient(player, name, ctx)
    end)
end
