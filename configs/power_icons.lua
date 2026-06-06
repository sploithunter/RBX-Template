--[[
    Power / status icons — Halo & Horns [PROTOTYPE].

    Roblox Image asset ids for the hotbar slots, pet status badges, and squad action
    buttons. Imported as Images (correct for ImageLabel). Aura art = squad/AoE,
    target art = single-target. Add ids here as they're made; UI falls back to text
    labels for anything without an icon.

    SCALE: many imported icons carry a transparent margin/border baked into the
    image. Containers clip their icon, so a scale > 1 zooms the art to crop that
    border away. `default_scale` applies to every icon; `scales` overrides per asset
    id when one piece of art needs more/less zoom. Tune live, then record here.
]]

local function id(n)
    return "rbxassetid://" .. n
end

local M = {
    -- Hotbar slot icon per power id (falls back to the slot's text label if absent).
    powers = {
        stone_skin = id(120424299023186), -- shield, single target
        bulwark = id(73499491406959), -- shield aura (squad damage-reduction)
        ice_armor = id(73499491406959),
        dune_shield = id(73499491406959),
        ember_ward = id(73499491406959),
        dodge = id(120424299023186),
        mountains_strength = id(102528688168498), -- damage buff aura
    },

    -- Pet status-badge icons (keys match SquadHud PET_EFFECTS). Use the new icon set so the
    -- buff badges match the hotbar/squad badges (the old flat assets read "wrong" next to them).
    status = {
        defense = id(99602330844217), -- DEF (Bulwark) -> ice armor disc (blue armor_chest)
        shield = id(121311806877255), -- SH (absorption pool) -> white shield disc
        damage = id(111373865269609), -- DMG (damage buff) -> green chevrons_up disc
    },

    -- Squad-HUD action buttons.
    actions = {
        heal = id(109752593245713), -- heal aura
        buff = id(102528688168498), -- damage buff aura
    },

    -- Spare art ready for single-target / assist-target variants when those land.
    spare = {
        heal_target = id(124914444699157),
        damage_target = id(91449088100042),
        shield_target = id(120424299023186),
    },

    -- Ring FRAMES (the 5 grayscale rings, uploaded white; tinted per element via ImageColor3).
    -- The SHAPE conveys TARGETING; the COLOR (tint) conveys element of origin. Layer a bright
    -- disc behind a dark ring + a white symbol to build an archetype/power badge in code, so we
    -- never have to upload a colored ring per element.
    -- NB: ids below are the IMAGE content ids (resolved from the uploaded Decals via the
    -- Decal.Texture each wraps). The Decal ids themselves do NOT render in ImageLabel.Image.
    rings = {
        target_in = id(73447619254562), -- single target (incoming pip)   [decal 116214377637854]
        target_out = id(96971740848796), -- single friendly / ally target [decal 120073694232878]
        aoe = id(128177741420839), -- enemy area-of-effect                [decal 115953506041881]
        target_aoe = id(130533151036887), -- friendly / team AoE          [decal 78886679306044]
        aura = id(121697559002218), -- plain ring (archetype / no dir)     [decal 76032353374470]
    },

    -- Map a power's targeting kind onto a ring SHAPE (above). UI: rings[targetingRing[kind]].
    targeting_ring = {
        single = "target_in",
        ally = "target_out",
        enemy_aoe = "aoe",
        team_aoe = "target_aoe",
        self = "aura",
        none = "aura",
    },

    -- Rock-paper-scissors element tints, RECOVERED from the hand-colored reference rings
    -- (colored = white_grayscale x ImageColor3, so the bright sample IS the multiplier). `bright`
    -- tints the disc/element; `dark` (= bright x ~0.36) tints the ring frame. Element by COLOR,
    -- archetype by the white SYMBOL shape. neutral = archetype with no/mixed element.
    elements = {
        earth = { bright = { 91, 255, 81 }, dark = { 33, 92, 29 } }, -- green (grass)
        fire = { bright = { 255, 82, 89 }, dark = { 92, 30, 32 } }, -- red (lava)
        desert = { bright = { 255, 209, 79 }, dark = { 92, 75, 28 } }, -- yellow (sand)
        ice = { bright = { 81, 136, 255 }, dark = { 29, 49, 92 } }, -- blue (frost)
        neutral = { bright = { 220, 220, 225 }, dark = { 70, 70, 78 } }, -- mixed / archetype-only
    },

    -- Canonical combat element (grass/lava/ice/desert, from CombatOrigin / combat_fx) -> the
    -- badge element key above. The badge vocabulary is earth/fire; combat uses grass/lava.
    element_alias = {
        grass = "earth",
        lava = "fire",
        desert = "desert",
        ice = "ice",
        earth = "earth",
        fire = "fire",
    },

    -- Archetype/role id (pet_roles / PetPowerView.roleInfo .id) -> the white SYMBOL to stamp on
    -- the element disc. (melee = the IMPACT fist; control = the hand.)
    role_symbol = {
        tank = "armor_chest",
        melee = "fist_impact",
        ranged = "arrow_right",
        support = "star_sparkle",
        control = "hand_stop",
    },

    -- Power badges. A power's disc COLOUR = its element (signature `element`, else the archetype
    -- theme); SYMBOL + RING (targeting) come from these maps. `power_effect_badge` keys off the
    -- power's `effect` (configs/powers.lua); signatures use `power_glyph_symbol` + the target map.
    -- target values are targeting_ring keys (resolved to a ring shape via M.ringFor).
    power_effect_badge = {
        shield = { symbol = "shield", target = "self" }, -- absorb shields (dune_shield/ember_ward)
        armor = { symbol = "armor_chest", target = "self" }, -- hardening armor (stone_skin/ice_armor) -> tank armor icon
        team_shield = { symbol = "armor_chest", target = "self" }, -- Bulwark squad defense
        dodge = { symbol = "eye_hidden", target = "self" }, -- evasion (mirage_step)
        damage_buff = { symbol = "chevrons_up", target = "self" }, -- Mountain's Strength
        root = { symbol = "hand_stop", target = "enemy_aoe" }, -- frost_bind
        aoe_slow = { symbol = "chevrons_down", target = "enemy_aoe" }, -- blizzard
        aoe_blind = { symbol = "eye_hidden", target = "enemy_aoe" }, -- sandstorm
        damage_over_time = { symbol = "contagion", target = "single" }, -- mark_of_flame
        aoe_damage = { symbol = "fist_impact", target = "enemy_aoe" }, -- eruption
    },
    power_glyph_symbol = {
        debuff = "contagion",
        burst = "star_sparkle",
        buff = "chevrons_up",
    },
    power_signature_ring = {
        single = "single",
        single_spread = "single",
        targeted_aoe = "enemy_aoe",
        team_aoe = "team_aoe",
        friendly = "ally",
    },

    -- Pre-baked colored disc-icons: discs[element][symbol] = Image id. The element is the disc
    -- COLOR (the pet's origin); the symbol is the archetype/power glyph baked onto it. Jason's
    -- recolor script renders these per element; uploaded as Decals, ids here are the resolved
    -- IMAGE content ids (see scripts/icon_ids.discs.json). The aura ring (rings.aura) tinted
    -- elements[elem].dark frames it -> the universal two-layer badge (src/Client/UI/PetBadge).
    discs = {
        earth = {
            armor_chest = id(117196376134677),
            fist_impact = id(107483427967238),
            arrow_right = id(89629994898328),
            star_sparkle = id(70922319936021),
            hand_stop = id(100801154207594),
            shield = id(113193953850265),
            chevrons_up = id(111373865269609),
            chevrons_down = id(116956260236978),
            eye_hidden = id(124548851657627),
            contagion = id(110049191538903),
        },
        fire = {
            armor_chest = id(80412131835560),
            fist_impact = id(111009476265182),
            arrow_right = id(102767415664686),
            star_sparkle = id(112938645728666),
            hand_stop = id(129326094066674),
            shield = id(87662561870844),
            chevrons_up = id(96245333568134),
            chevrons_down = id(77890006849747),
            eye_hidden = id(77250885695722),
            contagion = id(76135092340255),
        },
        desert = {
            armor_chest = id(138256777477472),
            fist_impact = id(92759715093176),
            arrow_right = id(95570155438599),
            star_sparkle = id(115581368440623),
            hand_stop = id(134819309651243),
            shield = id(126464933309161),
            chevrons_up = id(102312434316877),
            chevrons_down = id(91176982083127),
            eye_hidden = id(133420622860824),
            contagion = id(136303427822334),
        },
        ice = {
            armor_chest = id(99602330844217),
            fist_impact = id(138777877678894),
            arrow_right = id(110668229230948),
            star_sparkle = id(117884715579847),
            hand_stop = id(86991673939412),
            shield = id(127714891076758),
            chevrons_up = id(101680625896085),
            chevrons_down = id(94391806359767),
            eye_hidden = id(95538251553983),
            contagion = id(127344507940994),
        },
    },

    -- Zoom applied inside the (clipping) container to crop a transparent border.
    -- 1 = fit exactly; >1 = zoom in. Per-asset overrides win over default_scale.
    default_scale = 1.25,
    scales = {
        -- e.g. [id(73499491406959)] = 1.4,
        -- (Full-bleed disc icons are auto-registered at a slight inset below, after M is built.)
        [id(121311806877255)] = 0.9, -- white shield disc (status fallback; not in M.discs loop)
    },
}

-- Zoom factor for a given image string ("" / nil -> 1, i.e. no icon present).
function M.scaleFor(image)
    if not image or image == "" then
        return 1
    end
    return M.scales[image] or M.default_scale
end

-- Raw RGB triple {r,g,b} for an element badge layer. shade = "bright" (disc) | "dark" (ring).
-- Pure (no Color3) so headless specs can read it; UI wraps it via M.elementColor3.
function M.elementRGB(element, shade)
    local e = M.elements[element] or M.elements.neutral
    return e[shade] or e.bright
end

-- Color3 for an element badge layer (client UI only — touches the Color3 global).
function M.elementColor3(element, shade)
    local t = M.elementRGB(element, shade)
    return Color3.fromRGB(t[1], t[2], t[3])
end

-- Ring image (rbxassetid string) for a TARGETING kind; falls back to the plain archetype ring.
function M.ringFor(targetingKind)
    local shape = M.targeting_ring[targetingKind or "none"] or "aura"
    return M.rings[shape] or M.rings.aura
end

-- Normalize any element token (canonical grass/lava or badge earth/fire) to a badge key.
function M.elementKey(element)
    return M.element_alias[element or ""] or "neutral"
end

-- White symbol id for a role/archetype id ("" if none).
function M.symbolForRole(role)
    return M.role_symbol[role or ""]
end

-- Disc Image (rbxassetid string) for an element + symbol; nil if that combo wasn't uploaded.
function M.discFor(element, symbol)
    local e = M.discs[M.elementKey(element)]
    return e and symbol and e[symbol] or nil
end

-- Auto-register every colored disc at a slight inset: they're full-bleed (no transparent border
-- to crop), so the 1.25 border-zoom would overflow a clipping frame (status badges) and cut their
-- edges. Any scaleFor() consumer gets ~0.92 for a disc unless explicitly overridden above.
for _, byElement in pairs(M.discs) do
    for _, image in pairs(byElement) do
        if M.scales[image] == nil then
            M.scales[image] = 0.92
        end
    end
end

return M
