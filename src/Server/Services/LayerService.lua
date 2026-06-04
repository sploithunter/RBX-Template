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
local RealmTokens = require(ReplicatedStorage.Shared.Game.RealmTokens)

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

-- Player level for the World-S3 requires_level gate: the published EffectiveLevel
-- (combat level the curves read; teaming will sync it), falling back to Level.
function LayerService:_playerLevel(player)
    if not player then
        return 0
    end
    local lvl = player:GetAttribute("EffectiveLevel") or player:GetAttribute("Level")
    return tonumber(lvl) or 0
end

function LayerService:AccessibleLayers(player)
    local data = self._dataService:GetData(player)
    if not data then
        return {}
    end
    return LayerAccess.accessibleLayers(
        data.Soul or 0,
        self:_tokenBalances(player),
        self._layersConfig,
        self:_playerLevel(player)
    )
end

-- Income/reward scaling for the player's current layer (layers.multipliers; 1.0 at base).
-- The reward for descending: deeper realm = bigger income (+ bigger token cut, which is a
-- fraction of that income).
function LayerService:GetRewardMultiplier(player)
    local layer = self:GetCurrentLayer(player)
    local m = self._layersConfig.multipliers and self._layersConfig.multipliers[layer]
    return tonumber(m) or 1
end

-- Depth-scaled hatch luck for the player's current layer (0 at base). Consumed by
-- HatchEntitlementService via the published RealmHatchLuckBonus attribute.
function LayerService:GetHatchLuckBonus(player)
    return RealmTokens.hatchLuck(self:GetCurrentLayer(player), self._layersConfig)
end

-- ===== Token-earning loop (World S3 / RealmTokens) =====
-- Tokens are earned only while the player is in a realm layer (heaven -> light_tokens,
-- hell -> shadow_tokens). These are no-ops at base, so callers can fire them unconditionally.

function LayerService:_depositGrant(player, grant, reason)
    if not grant or not player or not self._dataService then
        return nil
    end
    self._dataService:AddCurrency(player, grant.currency, grant.amount, reason)
    return grant
end

-- A cut of biome-coin income becomes the realm token (call from the mining/combat payout).
function LayerService:GrantIncomeCut(player, incomeAmount)
    local layer = self:GetCurrentLayer(player)
    local grant = RealmTokens.fromIncome(incomeAmount, layer, self._layersConfig)
    return self:_depositGrant(player, grant, "realm_income_cut")
end

-- Flat token grant for a conquest event, keyed to the player's current realm.
function LayerService:GrantConquestTokens(player)
    local layer = self:GetCurrentLayer(player)
    local grant = RealmTokens.flat("conquest", layer, self._layersConfig)
    return self:_depositGrant(player, grant, "realm_conquest_tokens")
end

-- Flat token grant for hatching an egg in a realm.
function LayerService:GrantHatchTokens(player)
    local layer = self:GetCurrentLayer(player)
    local grant = RealmTokens.flat("hatch", layer, self._layersConfig)
    return self:_depositGrant(player, grant, "realm_hatch_tokens")
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

    local decision = LayerAccess.canAccess(soul, balance, layerId, self._layersConfig, {
        playerLevel = self:_playerLevel(player),
        fromLayer = data.CurrentLayer or "base", -- applies the charge_on traversal sink
    })
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
    -- Publish the depth-scaled hatch luck so HatchEntitlementService picks it up (S3.4).
    player:SetAttribute("RealmHatchLuckBonus", self:GetHatchLuckBonus(player))
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
