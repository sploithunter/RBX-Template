-- Centralized sound catalog
-- Sounds are preloaded into ReplicatedStorage.Assets.Sounds by AssetPreloadService

return {
    -- Named sounds
    egg_hatch_pop = {
        id = "rbxassetid://98548849463653",
        volume = 0.8,
        playback_speed = 1.0,
    },

    egg_roll_snare = {
        id = "rbxassetid://79256976981602",
        volume = 0.6,
        playback_speed = 1.0,
    },

    enchant_thunder = {
        id = "rbxassetid://71266985896124",
        volume = 0.9,
        playback_speed = 0.85,
    },

    -- Add more named sounds here as needed

    -- Short celebratory stinger (non-looping) — level-up / ascend. Uploaded via scripts/upload_audio.js.
    celebratory_jingle = {
        id = "rbxassetid://129756458235378",
        volume = 0.7,
        playback_speed = 1.0,
        bus = "ui", -- SoundGroup bus (effects | music | ui); the volume slider controlling it
    },

    -- EVENT -> sound key. Code detects the event (the only inherently-code part); WHICH sound plays
    -- (and on which bus, from the sound's `bus` field) is config. Add a row to give a new event a
    -- stinger without touching code; remove a row to silence it.
    event_sounds = {
        level_up = "celebratory_jingle",
    },

    -- LOOPING AREA MUSIC. AreaMusicController plays the track for the player's CURRENT area, looped,
    -- on the "music" SoundGroup bus (so the Music volume slider controls it), crossfading on area
    -- change. New uploads play once Roblox moderation approves them.
    music = {
        awe = { id = "rbxassetid://122469397847650", volume = 0.45 }, -- LoopingAweMusic
        viking_drum = { id = "rbxassetid://133214678271304", volume = 0.45 }, -- VikingDrumLooping
        epic_drum = { id = "rbxassetid://75441224405966", volume = 0.45 }, -- DrumEpicLooping
    },

    -- Which looping track plays in each AREA (edit freely — falls back to `default`). Only 3 tracks
    -- so far, so some areas share; add more tracks + remap for fully distinct per-area music.
    area_music = {
        default = "awe",
        Spawn = "awe", -- calm hub
        Grass = "awe", -- gentle starter biome
        Desert = "viking_drum", -- arid march
        Ice = "viking_drum", -- harsh cold
        Lava = "epic_drum", -- intense endgame
    },
}
