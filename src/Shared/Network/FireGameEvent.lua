--[[
    FireGameEvent — server-side one-liner for the GameEvents bus (docs/GAME_EVENTS.md).

    Usage (any server service):
        local fireGameEvent = require(ReplicatedStorage.Shared.Network.FireGameEvent)
        fireGameEvent(player, "quest_complete", { quest = questId })

    Sends Signals.GameEvent to that player's client, where GameEvents.start() dispatches the
    reactions declared in configs/game_events.lua (sound / vfx / ...). Firing an event with no
    config entry is a no-op, so sources can fire unconditionally and reactions stay config-only.
    pcall'd: a celebration must never break the gameplay mutation that triggered it.

    SERVER TAP: fireGameEvent.tap(fn) registers a server-side observer of EVERY event —
    fn(player, name, ctx) runs (pcall'd) before the client send. This is how cross-cutting
    consumers (the tutorial) react to gameplay without any gameplay service knowing they exist.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local listeners = {}

local FireGameEvent = setmetatable({}, {
    __call = function(_, player, name, ctx)
        for _, fn in ipairs(listeners) do
            pcall(fn, player, name, ctx)
        end
        pcall(function()
            Signals.GameEvent:FireClient(player, name, ctx)
        end)
    end,
})

function FireGameEvent.tap(fn)
    table.insert(listeners, fn)
end

return FireGameEvent
