--[[
    AudioPrefs (client) — persist + restore the audio sliders (Jason: "lowering the volume
    in settings is temporary").

    The Settings panel only mutated a local table that re-defaulted to 1.0 every boot.
    Persistence rides the command bus: `settings.set` stores the audio table in the profile
    (data.Settings.ClientPrefs), `settings.get` returns it. start() loads + APPLIES at boot,
    so saved volumes are live before the Settings panel is ever opened; the panel seeds its
    sliders from loaded() and calls save() on change (debounced — slider drags fire a lot).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundGroups = require(ReplicatedStorage.Shared.Effects.SoundGroups)

local AudioPrefs = {}
local loadedAudio = nil -- last known persisted table (nil until the bus answers)
local saveQueued = false

local function callBus(name, args)
    local remote = ReplicatedStorage:WaitForChild("GameAPICommand", 15)
    if not remote then
        return nil
    end
    local ok, envelope = pcall(function()
        return remote:InvokeServer(name, args or {})
    end)
    if not ok or type(envelope) ~= "table" then
        return nil
    end
    return envelope.result or envelope.data or envelope
end

-- Same bus math the Settings panel uses (master folds into every bus).
function AudioPrefs.apply(audio)
    if type(audio) ~= "table" then
        return
    end
    local master = tonumber(audio.masterVolume) or 1
    SoundGroups.setVolume("effects", (tonumber(audio.effectsVolume) or 1) * master)
    SoundGroups.setVolume("music", (tonumber(audio.musicVolume) or 1) * master)
    SoundGroups.setVolume("ui", (audio.uiSoundsEnabled ~= false and 1 or 0) * master)
end

-- The persisted audio table, or nil if none saved / not loaded yet.
function AudioPrefs.loaded()
    return loadedAudio
end

-- Debounced persist (1s): the LAST values win; slider drags collapse to one save.
function AudioPrefs.save(audio)
    loadedAudio = audio
    if saveQueued then
        return
    end
    saveQueued = true
    task.delay(1, function()
        saveQueued = false
        callBus("settings.set", { audio = loadedAudio })
    end)
end

function AudioPrefs.start()
    task.spawn(function()
        local res = callBus("settings.get")
        local audio = type(res) == "table" and type(res.audio) == "table" and res.audio
        if audio then
            loadedAudio = audio
            AudioPrefs.apply(audio)
        end
    end)
end

return AudioPrefs
