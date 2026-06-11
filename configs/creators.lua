--[[
    Creators — the registry of TOP-TIER creators (Jason + invited collaborators) and
    the Meet-The-Creator mechanic.

    Each registered creator has their OWN creator-pet species. The species is theirs
    exclusively as the APEX (creator-class grants only ever go to the creator
    themselves — colorado is Jason's, period). Other players obtain the SPECIES
    (never the apex class) through Meet-The-Creator:

        The FIRST time you are in the same server as a registered creator — and only
        that once, ever — you receive their creator EGG in your eggs inventory. The
        egg hatches a creator-species pet at the configured variant odds.

    Persisted per player in data.MetCreators[creatorUserId] = os.time().
]]

return {
    creators = {
        -- userId (string keys: JSON-safe) -> identity
        ["3200870803"] = {
            name = "ColoradoPlays",
            pet = "colorado", -- the species their egg hatches
            egg_id = "colorado_egg", -- eggs-bucket item id
            egg_name = "Colorado Egg",
            -- variant odds on hatch (weights)
            variants = { basic = 85, golden = 12, rainbow = 3 },
        },
    },

    meet = {
        enabled = true,
        -- once per (player, creator) pair, forever
        check_delay = 8, -- seconds after a join before scanning (lets data load)
    },
}
