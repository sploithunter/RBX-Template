--[[
    GameEvents (client) — one hook for every gameplay event; configs/game_events.lua decides the
    reactions.

    Game code DETECTS an event (a level changed, a death, a hit) and calls GameEvents.fire(name, ctx).
    This dispatcher looks up configs/game_events.lua[name] and applies each configured reaction by
    kind. Reaction handlers are registered here once (sound now; vfx/toast/callback can be added the
    same way). So "react to event X" is config; the only code is firing the event and the generic
    handler for each reaction kind.

      • Local fire:  require this module and call GameEvents.fire("level_up", { level = n })
      • Server fire: Signals.GameEvent:FireClient(player, name, ctx) -> bridged to fire() in start()
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)
local SoundGroups = require(ReplicatedStorage.Shared.Effects.SoundGroups)
local sounds = require(ReplicatedStorage.Configs:WaitForChild("sounds"))
local eventConfig = require(ReplicatedStorage.Configs:WaitForChild("game_events"))

local GameEvents = {}

-- reaction kind -> handler(spec, ctx). Add a new kind here and it's instantly usable from config.
local REACTIONS = {}

-- sound: spec is a key into configs/sounds.lua; play it one-shot on its configured bus.
REACTIONS.sound = function(soundKey)
    local def = soundKey and sounds[soundKey]
    if not (def and def.id) then
        return
    end
    local s = Instance.new("Sound")
    s.SoundId = def.id
    s.Volume = def.volume or 0.7
    s.PlaybackSpeed = def.playback_speed or 1
    SoundGroups.assign(s, def.bus or "ui")
    s.Parent = SoundService
    s:Play()
    s.Ended:Once(function()
        s:Destroy()
    end)
    task.delay(8, function() -- safety cleanup if Ended never fires (unapproved/failed asset)
        if s.Parent then
            s:Destroy()
        end
    end)
end

-- Fire a named event: apply every configured reaction. `ctx` is forwarded to handlers (future use).
function GameEvents.fire(name, ctx)
    local entry = eventConfig[name]
    if type(entry) ~= "table" then
        return -- no reactions configured for this event
    end
    for kind, spec in pairs(entry) do
        local handler = REACTIONS[kind]
        if handler then
            local ok, err = pcall(handler, spec, ctx)
            if not ok then
                warn(
                    ("GameEvents: reaction '%s' for '%s' failed: %s"):format(
                        kind,
                        name,
                        tostring(err)
                    )
                )
            end
        end
    end
end

-- Bridge server-origin events (death/hit/...) onto the same hook.
function GameEvents.start()
    if Signals.GameEvent then
        Signals.GameEvent.OnClientEvent:Connect(function(name, ctx)
            if type(name) == "string" then
                GameEvents.fire(name, ctx)
            end
        end)
    end
    return GameEvents
end

local _ = Players.LocalPlayer -- ensure client context
return GameEvents
