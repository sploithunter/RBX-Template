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
    -- Jason's real guardian models go here (Open Cloud Model asset ids). nil = use the placeholder.
    model_asset = {
        colossus = nil,
        djinn = nil,
    },

    colossus = {
        scale = 3.2, -- placeholder: how much to enlarge the cloned pet
        tint = { 120, 132, 110 }, -- stone grey-green
        light = { 110, 200, 90 }, -- earth-green glow
        squad_defense = 220, -- +Defense on the squad while it stands (the WALL)
        squad_damage = 1.6, -- x pet damage while it stands (the FIST, via PetDamageBuff)
        offset = { x = 7, y = 0, z = 4 }, -- stands here relative to the player
    },
    djinn = {
        scale = 2.6,
        tint = { 245, 200, 90 }, -- gold
        light = { 245, 185, 60 },
        heal_per_tick = 30, -- squad heal each tick while it floats (the HoT)
        tick_seconds = 1.5,
        hover = 5, -- floats this high off the ground
        offset = { x = -7, y = 0, z = 4 },
    },

    follow_lerp = 0.18, -- 0..1: how snappily the guardian trails the player each frame
}
