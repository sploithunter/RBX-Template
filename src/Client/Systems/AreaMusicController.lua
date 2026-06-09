--[[
    AreaMusicController — looping background music that follows the player's CURRENT area.

    One Sound, Looped, routed through the "music" SoundGroup bus (so the Settings "Music Volume"
    slider controls it). On spawn and whenever CurrentArea (or HomeArea as a fallback) changes, it
    resolves the area's track from configs/sounds.lua (`area_music` area->key, `music` key->{id,volume})
    and CROSSFADES: fade the current track down, swap the SoundId, fade the new one up. A token guards
    against rapid area changes so only the latest swap wins.

    Add tracks + remap areas entirely in configs/sounds.lua — no code change needed here.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundGroups = require(ReplicatedStorage.Shared.Effects.SoundGroups)
local sounds = require(ReplicatedStorage.Configs:WaitForChild("sounds"))

local AreaMusicController = {}

local FADE = 1.5 -- seconds for each half of the crossfade
local localPlayer = Players.LocalPlayer

function AreaMusicController.start()
    local music = sounds.music or {}
    local areaMap = sounds.area_music or {}

    local sound = Instance.new("Sound")
    sound.Name = "AreaMusic"
    sound.Looped = true
    sound.Volume = 0
    SoundGroups.assign(sound, "music")
    sound.Parent = SoundService

    local currentKey -- the track key currently playing
    local token = 0

    local function trackForArea(area)
        local key = areaMap[area] or areaMap.default
        return key, key and music[key]
    end

    local function apply()
        local area = localPlayer:GetAttribute("CurrentArea")
            or localPlayer:GetAttribute("HomeArea")
            or "Spawn"
        local key, def = trackForArea(area)
        if not def or not def.id or key == currentKey then
            return -- unknown area/track, or already playing the right one
        end
        currentKey = key

        token += 1
        local myToken = token
        local target = def.volume or 0.45

        local function swapIn()
            if myToken ~= token then
                return -- a newer area change superseded this one
            end
            sound.SoundId = def.id
            sound:Play()
            TweenService:Create(sound, TweenInfo.new(FADE), { Volume = target }):Play()
        end

        if sound.IsPlaying and sound.Volume > 0 then
            local fadeOut = TweenService:Create(sound, TweenInfo.new(FADE), { Volume = 0 })
            fadeOut.Completed:Once(swapIn)
            fadeOut:Play()
        else
            swapIn()
        end
    end

    apply()
    localPlayer:GetAttributeChangedSignal("CurrentArea"):Connect(apply)
    localPlayer:GetAttributeChangedSignal("HomeArea"):Connect(apply)
end

return AreaMusicController
