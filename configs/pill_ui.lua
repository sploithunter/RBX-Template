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
    -- Hollow rounded-square RING (slot outline / availability).
    frames = {
        sapphire = id(70695072756337),
        emerald = id(76092963987648),
        ruby = id(81233579833062),
        citrine = id(74085455334565),
        neutral = id(97044269701632),
    },
    -- Solid rounded-square PANEL (filled slot / card background).
    panels = {
        sapphire = id(130004574852540),
        emerald = id(107824647721584),
        ruby = id(101100402725956),
        citrine = id(131811968137834),
        neutral = id(121583751476131),
    },

    -- Semantic shortcuts for the equipped ring-slot view (down-lockout availability).
    slot_available = id(97044269701632), -- neutral_pill_frame (white ring)
    slot_locked = id(81233579833062), -- ruby_pill_frame (red ring)
}
