--[[
    Pill UI assets — rounded "pill" frames (hollow rings) + solid panels, 5 colors.

    Jason's art (assets/ui/pill_*), uploaded via Open Cloud (scripts/pill_ids.json = Decal ids;
    resolved to the IMAGE content ids below — Decal ids don't render in ImageLabel). Re-resolve in
    Studio if re-uploaded: InsertService:LoadAsset(decalId):FindFirstChildWhichIsA("Decal").Texture.

    Primary use: the equipped ring-slot view in the Pets window (#179 down-lockout) — a slot is a
    `frame` (hollow ring): NEUTRAL (white) = available, RUBY (red) = locked/recovering; a filled slot
    sits on a `panel`. Colors also map to gem elements (sapphire=ice, emerald=grass/earth, ruby=lava,
    citrine=desert, neutral=generic) for reuse elsewhere.
]]

local function id(n)
    return "rbxassetid://" .. n
end

return {
    -- Hollow rounded-square RING (slot outline / availability) — TRANSPARENT-center re-upload.
    frames = {
        sapphire = id(95326067795013),
        emerald = id(129188138559157),
        ruby = id(90032311308057),
        citrine = id(119068520051744),
        neutral = id(85243706065340),
    },
    -- Solid rounded-square PANEL (filled slot / card background).
    panels = {
        sapphire = id(78579315573909),
        emerald = id(92870488851209),
        ruby = id(92148276403953),
        citrine = id(95983900646063),
        neutral = id(89609871330555),
    },

    -- Semantic shortcuts for the equipped ring-slot view (down-lockout availability).
    slot_available = id(85243706065340), -- neutral_pill_frame (white ring)
    slot_locked = id(90032311308057), -- ruby_pill_frame (red ring)
}
