--[[
    Summon-guardian config (#178) — the capstone "call a pet" powers.

    Gaia's Colossus (geomancer) and the Genie of the Dunes (sandwalker) summon a temporary GUARDIAN
    that stands with your squad for `duration`s, then despawns. To keep it firewall-safe (§16.5) the
    guardian doesn't deal player damage directly — it expresses its fantasy through squad buffs while
    it's on the field:
      • Colossus = a WALL + a FIST: big squad +Defense and x pet-damage while it stands (tank identity).
      • Djinn    = a FOUNT: revives every downed pet on arrival, full-heals, then a heal-over-time tick.

    Model: Jason is making real guardian models — drop their asset ids in `model_asset`. Until then the
    service clones a scaled-up squad pet as a placeholder (so the power is fully functional now).
]]

return {
    -- Real guardian models (Open Cloud Model asset ids). nil = clone a scaled+tinted squad pet.
    model_asset = {
        colossus = 95238379643484, -- moss-stone titan (tree + waterfall crown)
        djinn = 88120936939949, -- gold genie
    },

    colossus = {
        scale = 3.2, -- PLACEHOLDER only: enlarge the cloned pet (ignored when a real asset loads)
        height = 9, -- real asset: scale so the model stands this many studs tall
        tint = { 120, 132, 110 }, -- placeholder tint only (real model keeps its own textures)
        light = { 110, 200, 90 }, -- earth-green glow
        squad_defense = 220, -- +Defense on the squad while it stands (the WALL)
        squad_damage = 1.6, -- x pet damage while it stands (the FIST, via PetDamageBuff)
        offset = { x = 7, y = 0, z = 4 }, -- stands here relative to the player
    },
    djinn = {
        scale = 2.6,
        height = 5.5, -- real asset target height (studs)
        tint = { 245, 200, 90 },
        light = { 245, 185, 60 },
        heal_per_tick = 30, -- squad heal each tick while it floats (the HoT)
        tick_seconds = 1.5,
        hover = 5, -- floats this high off the ground
        offset = { x = -7, y = 0, z = 4 },
    },

    follow_lerp = 0.18, -- 0..1: how snappily the guardian trails the player each frame
}
