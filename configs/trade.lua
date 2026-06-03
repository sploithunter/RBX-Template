--[[
    Trade — Halo & Horns [PROTOTYPE] (Feature 19).

    Pets are tradeable (unless locked); currencies are NOT; cosmetics are. Trades
    are server-authoritative, require both players to confirm, execute atomically
    (anti-duplication), and are written to a trade-history audit log. Pure rules:
    `src/Shared/Game/TradeLogic.lua`.
]]

return {
    tradeable = {
        pets = true,
        currencies = false,
        cosmetics = true,
    },
    -- Per-currency trade allowlist (Pet Realm): the four biome coins are soulbound;
    -- gems are the only tradeable currency. Anything not listed here is non-tradeable.
    tradeable_currencies = {
        gems = true,
    },
    max_offer_items = 10,
    -- Cap the in-memory audit log per player (full audit would be a DataStore).
    audit_log_limit = 100,
}
