--[[
    Pet roles (archetypes) — Halo & Horns [PROTOTYPE].

    The City-of-Heroes-style squad card shows a small archetype chip on the left so you
    can read a pet's combat ROLE at a glance (tank / melee / ranged / support / control).

    Resolution order (SquadHud): the pet's `PetRole` attribute (per-pet override) ->
    `by_type[PetType]` -> `default`. Until real role art is uploaded, each role renders a
    coloured letter glyph; drop an `icon` asset id on a role to swap the glyph for art.

    Colours are {r, g, b} (0-255) so this stays plain data; the client builds the Color3.
]]

return {
    default = "melee",

    -- PetType -> role id. Extend as pets are designed; a pet can also override with a
    -- `PetRole` attribute on its model.
    by_type = {
        bear = "tank",
        doggy = "melee",
        dog = "melee",
        bunny = "support",
        cat = "ranged",
        bird = "ranged",
        colorado = "ranged",
    },

    -- Role definitions. glyph = the placeholder letter; icon = "" until art exists.
    roles = {
        tank = { label = "Tank", glyph = "T", color = { 70, 130, 195 }, icon = "" },
        melee = { label = "Melee", glyph = "M", color = { 205, 85, 70 }, icon = "" },
        ranged = { label = "Ranged", glyph = "R", color = { 120, 180, 85 }, icon = "" },
        support = { label = "Support", glyph = "S", color = { 150, 110, 215 }, icon = "" },
        control = { label = "Control", glyph = "C", color = { 90, 185, 205 }, icon = "" },
    },
}
