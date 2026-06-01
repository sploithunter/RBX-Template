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

    -- Role definitions. glyph = placeholder letter (until art exists via `icon`).
    -- attack_range = how far the pet can deal damage (server mining gate, studs).
    -- standoff = how far back it holds in the attack formation (client), studs. Keep
    -- standoff < attack_range so the pet can still hit from where it stands. Melee/tank
    -- crowd in close (standoff 0); ranged hangs back and snipes; support/control sit at
    -- mid range. This is the melee-closes / ranged-kites dynamic.
    -- threat_mult scales the aggro a role generates (passive threat × this), so a tank
    -- holds the enemy's attention and soaks for the squad while dps/ranged stay safer.
    roles = {
        tank = { label = "Tank", glyph = "T", color = { 70, 130, 195 }, icon = "", attack_range = 9, standoff = 0, threat_mult = 5 },
        melee = { label = "Melee", glyph = "M", color = { 205, 85, 70 }, icon = "", attack_range = 9, standoff = 0, threat_mult = 1 },
        -- kite = true: holds near the player and snipes instead of orbiting the enemy, so
        -- an enemy chasing it has to close the gap (the melee-closes / ranged-kites loop).
        ranged = { label = "Ranged", glyph = "R", color = { 120, 180, 85 }, icon = "", attack_range = 28, standoff = 17, kite = true },
        support = { label = "Support", glyph = "S", color = { 150, 110, 215 }, icon = "", attack_range = 16, standoff = 9 },
        control = { label = "Control", glyph = "C", color = { 90, 185, 205 }, icon = "", attack_range = 20, standoff = 12 },
    },
}
