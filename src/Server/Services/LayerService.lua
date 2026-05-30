--[[
    LayerService — server owner of layer access (Feature 3, Halo & Horns).

    Server-authoritative ascend/descend: validates Soul magnitude + token cost
    from config (never trusting the client), deducts the token cost via
    DataService, and sets profile.CurrentLayer (lazy-init, persists). The actual
    teleport to the layer's Y-offset geometry is deferred until the stacked
    layers are authored in the world; this service owns the logical layer + cost.

    Cross-path "visit" portals (ignore Soul) are tied to authored visit portals
    and are NOT exposed as a client-settable flag here (that would bypass Soul
    gating); the pure LayerAccess supports it for when visit portals are authored.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LayerAccess = require(ReplicatedStorage.Shared.Game.LayerAccess)

local LayerService = {}
LayerService.__index = LayerService

function LayerService:Init()
    self._logger = self._modules and self._modules.Logger
    self._configLoader = self._modules and self._modules.ConfigLoader
    self._dataService = self._modules and self._modules.DataService
    self._layersConfig = self._configLoader:LoadConfig("layers")
end

function LayerService:GetCurrentLayer(player)
    local data = self._dataService:GetData(player)
    return (data and data.CurrentLayer) or "base"
end

function LayerService:_tokenBalances(player)
    return {
        light_tokens = self._dataService:GetCurrency(player, "light_tokens") or 0,
        shadow_tokens = self._dataService:GetCurrency(player, "shadow_tokens") or 0,
    }
end

function LayerService:AccessibleLayers(player)
    local data = self._dataService:GetData(player)
    if not data then
        return {}
    end
    return LayerAccess.accessibleLayers(
        data.Soul or 0,
        self:_tokenBalances(player),
        self._layersConfig
    )
end

-- Attempt to move the player to a layer. Server re-validates cost from config.
function LayerService:UseLayer(player, layerId)
    local data = self._dataService:GetData(player)
    if not data then
        return { ok = false, reason = "data_not_loaded" }
    end

    local soul = data.Soul or 0
    local currency = self._layersConfig.token_currency
        and self._layersConfig.token_currency[layerId]
    local balance = currency and (self._dataService:GetCurrency(player, currency) or 0) or 0

    local decision = LayerAccess.canAccess(soul, balance, layerId, self._layersConfig)
    if not decision.ok then
        return {
            ok = false,
            reason = decision.reason,
            cost = decision.cost,
            currency = decision.currency,
        }
    end

    -- Deduct the server-resolved cost (decision.cost from config, not the client).
    if decision.cost and decision.cost > 0 and decision.currency then
        self._dataService:RemoveCurrency(
            player,
            decision.currency,
            decision.cost,
            "layer_use_" .. layerId
        )
    end

    data.CurrentLayer = layerId
    self._dataService:RequestSave(player, "layer_use_" .. layerId, { critical = true })

    if self._logger then
        self._logger:Info("Layer changed", {
            player = player.Name,
            layer = layerId,
            cost = decision.cost,
            currency = decision.currency,
        })
    end

    return {
        ok = true,
        layer = layerId,
        cost = decision.cost,
        currency = decision.currency,
        soul = soul,
    }
end

return LayerService
