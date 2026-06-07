--[[
    Gem drop assets + mapping (#177) — Halo & Horns.

    Mined coins drop as physical GEMS (DropService). Per Jason, the 4 colors share the SAME 3 form
    meshes (single / pile / bag) and differ only by texture — so this is 3 meshes + 12 textures, not
    12 meshes. Color is chosen by the biome currency; gem FORM steps up with the chunk a gem carries
    (single = small, pile = medium, bag = big). A large award SPLITS into several gems (payout by
    count), so a fat node bursts a fistful of gems instead of one. All ids are real, uploaded assets.
]]

return {
    -- 3 shared form meshes (colors reuse these; geometry is identical across colors).
    meshes = {
        single = "rbxassetid://120847768657487",
        pile = "rbxassetid://118620301664836",
        bag = "rbxassetid://140667375594889",
    },

    -- 12 textures keyed [color][form].
    textures = {
        sapphire = {
            single = "rbxassetid://92087344212010",
            pile = "rbxassetid://140074573067134",
            bag = "rbxassetid://111577083207352",
        },
        emerald = {
            single = "rbxassetid://89849279170806",
            pile = "rbxassetid://110721051431892",
            bag = "rbxassetid://91612068059535",
        },
        ruby = {
            single = "rbxassetid://106984872505048",
            pile = "rbxassetid://89319434061596",
            bag = "rbxassetid://80309644035251",
        },
        citrine = {
            single = "rbxassetid://88555005076540",
            pile = "rbxassetid://130117829099103",
            bag = "rbxassetid://115145476379087",
        },
    },

    -- Internal PointLight tint per color (the glow inside each gem).
    light_color = {
        sapphire = { 60, 140, 255 },
        emerald = { 80, 230, 90 },
        ruby = { 235, 45, 95 },
        citrine = { 245, 185, 45 },
    },

    -- Biome currency -> gem color (ice=sapphire, grass/earth=emerald, lava=ruby, desert=citrine).
    currency_color = {
        ice_coins = "sapphire",
        grass_coins = "emerald",
        earth_coins = "emerald",
        meadow_coins = "emerald",
        lava_coins = "ruby",
        desert_coins = "citrine",
        beach_coins = "citrine",
        coins = "emerald",
    },
    default_color = "emerald",

    -- Form chosen by the amount a single gem carries (descending min).
    form_tiers = {
        { min = 500, form = "bag" },
        { min = 100, form = "pile" },
        { min = 0, form = "single" },
    },

    -- Payout-by-count split: one extra gem per `split_step` of award, clamped to `max_gems`.
    split_step = 250,
    max_gems = 6,

    -- Visual: scale each gem so its widest side is ~`size[form]` studs (a pile/bag is a whole
    -- cluster, so it needs to be bigger than a single to read at the same gem scale). PointLight
    -- range/brightness for the internal glow.
    size = {
        single = 1.25, -- a touch smaller than the pile/bag (Jason: shrink the single, not grow the rest)
        pile = 3.0, -- ~2x a single (Jason: piles looked small at the shared size)
        bag = 4.0, -- the jackpot form — chunkiest
    },
    default_size = 1.5,
    light_range = 9,
    light_brightness = 2.5,
}
