--[[
    LayerAccess (pure) — Feature 3.

    Decides whether a player may enter a layer, given their Soul and their balance
    of the layer's token currency. Heaven layers need soul >= requires_soul
    (positive); Hell layers need soul <= requires_soul (negative). A cross-path
    "visit" portal ignores the Soul requirement (token cost still applies). This
    module never deducts — it only judges; the service deducts on success.

    Pure: standard Lua only; unit-tested via `mise run test-headless`.
]]

local LayerAccess = {}

LayerAccess.Reason = {
    UnknownLayer = "unknown_layer",
    SoulTooLow = "soul_too_low",
    SoulWrongDirection = "soul_wrong_direction",
    InsufficientTokens = "insufficient_tokens",
}

-- canAccess(soul, tokenBalance, layerId, config, opts) -> { ok, reason?, cost, currency }
function LayerAccess.canAccess(soul, tokenBalance, layerId, config, opts)
    opts = opts or {}
    local access = config.access and config.access[layerId]
    if not access then
        return { ok = false, reason = LayerAccess.Reason.UnknownLayer }
    end
    local currency = config.token_currency and config.token_currency[layerId]
    local cost = access.token_cost or 0

    if not opts.crossPathVisit and access.requires_soul ~= nil then
        local req = access.requires_soul
        if req > 0 and soul < req then
            return {
                ok = false,
                reason = LayerAccess.Reason.SoulTooLow,
                cost = cost,
                currency = currency,
            }
        elseif req < 0 and soul > req then
            return {
                ok = false,
                reason = LayerAccess.Reason.SoulWrongDirection,
                cost = cost,
                currency = currency,
            }
        end
    end

    if (tokenBalance or 0) < cost then
        return {
            ok = false,
            reason = LayerAccess.Reason.InsufficientTokens,
            cost = cost,
            currency = currency,
        }
    end

    return { ok = true, cost = cost, currency = currency }
end

-- accessibleLayers(soul, tokenBalances, config) -> sorted array of accessible layer ids.
-- tokenBalances is a map of currency id -> amount.
function LayerAccess.accessibleLayers(soul, tokenBalances, config)
    tokenBalances = tokenBalances or {}
    local out = {}
    for layerId in pairs(config.access or {}) do
        local currency = config.token_currency and config.token_currency[layerId]
        local balance = (currency and tokenBalances[currency]) or 0
        if LayerAccess.canAccess(soul, balance, layerId, config).ok then
            table.insert(out, layerId)
        end
    end
    table.sort(out)
    return out
end

return LayerAccess
