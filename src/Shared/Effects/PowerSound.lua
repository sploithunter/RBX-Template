--[[
    PowerSound — plays a power's element SFX from the configs/power_fx.lua `sounds` registry.

        PowerSound.play(phase, element, position) -> the entry played (or nil if none/gap)

    Resolves `sounds[phase][element]` (phase = "cast" | "impact"), picks a random variant, and plays
    it as a 3D positional Sound at `position` (auto-cleaned after the clip + a small tail). GAPS ARE
    SILENT: an element/phase with no entry simply plays nothing (returns nil) — so missing sounds are
    a no-op, not an error. Shared by the FX-probe and the real cast-FX path so there's one sound path.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local FX = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("power_fx"))

local PowerSound = {}

function PowerSound.entryFor(phase, element)
    local byPhase = FX.sounds and FX.sounds[phase]
    local list = byPhase and byPhase[element]
    if not list or #list == 0 then
        return nil
    end
    return list[math.random(1, #list)]
end

function PowerSound.play(phase, element, position)
    local entry = PowerSound.entryFor(phase, element)
    if not entry or not entry.id then
        return nil
    end
    local part = Instance.new("Part")
    part.Name = "PowerSoundAnchor"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.Transparency = 1
    part.Size = Vector3.new(1, 1, 1)
    part.CFrame = CFrame.new(position or Vector3.new())
    part.Parent = Workspace

    local sound = Instance.new("Sound")
    sound.SoundId = entry.id
    sound.RollOffMaxDistance = 140
    sound.RollOffMinDistance = 8
    sound.Parent = part
    sound:Play()

    -- Live the clip's length (the manifest baseline) + a small tail, then clean up.
    Debris:AddItem(part, (tonumber(entry.seconds) or 3) + 0.75)
    return entry
end

return PowerSound
