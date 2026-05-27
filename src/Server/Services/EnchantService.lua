--[[
    EnchantService

    Rolls and resolves pet enchants. Enchants live on unique pet inventory
    records and contribute to the shared modifier pipeline through the
    "enchants" stage.
]]

local EnchantService = {}
EnchantService.__index = EnchantService

function EnchantService.new()
    local self = setmetatable({}, EnchantService)
    self._logger = nil
    self._configLoader = nil
    self._dataService = nil
    self._inventoryService = nil
    self._modifierService = nil
    self._config = nil
    return self
end

function EnchantService:Init()
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    self._dataService = self._modules.DataService
    self._inventoryService = self._modules.InventoryService
    self._modifierService = self._modules.ModifierService
    self._config = self._configLoader:LoadConfig("enchants")

    if self:IsEnabled() and self._modifierService and self._modifierService.RegisterProvider then
        self._modifierService:RegisterProvider("enchants", function(context)
            return self:_getModifierContributions(context)
        end)
    end

    self._logger:Info("EnchantService initialized", {
        context = "EnchantService",
        enabled = self:IsEnabled(),
    })
end

function EnchantService:Start()
    local Signals = require(game:GetService("ReplicatedStorage").Shared.Network.Signals)
    Signals.EnchantPetRequest.OnServerEvent:Connect(function(player, payload)
        local result = self:RerollPetEnchant(player, payload)
        Signals.EnchantPetResult:FireClient(player, result)
    end)
end

function EnchantService:IsEnabled()
    return self._config and self._config.enabled ~= false
end

function EnchantService:_chooseWeighted(entries)
    if type(entries) ~= "table" then
        return nil
    end

    local totalWeight = 0
    for _, entry in ipairs(entries) do
        totalWeight += math.max(0, tonumber(entry.weight) or 0)
    end
    if totalWeight <= 0 then
        return nil
    end

    local roll = math.random() * totalWeight
    local cursor = 0
    for _, entry in ipairs(entries) do
        cursor += math.max(0, tonumber(entry.weight) or 0)
        if roll <= cursor then
            return entry
        end
    end

    return entries[#entries]
end

function EnchantService:_getRollProfileForRarity(rarityId)
    local profileId = self._config.rarity_profiles and self._config.rarity_profiles[rarityId]
    if type(profileId) ~= "string" then
        return nil, nil
    end
    local profile = self._config.roll_profiles and self._config.roll_profiles[profileId]
    if type(profile) ~= "table" then
        return nil, profileId
    end
    return profile, profileId
end

function EnchantService:_rollStrength(strengthConfig)
    strengthConfig = type(strengthConfig) == "table" and strengthConfig or {}
    local low = math.floor(tonumber(strengthConfig.low) or 1)
    local high = math.floor(tonumber(strengthConfig.high) or low)
    local scale = math.max(1, math.floor(tonumber(strengthConfig.scale) or 1))
    if high < low then
        high = low
    end

    local strength = low
    while strength < high and math.random(1, scale) == scale do
        strength += 1
    end
    return strength
end

function EnchantService:_buildEnchant(entry, profileId)
    if type(entry) ~= "table" then
        return nil
    end

    local enchantId = entry.effect
    local enchantConfig = self._config.effects and self._config.effects[enchantId]
    if type(enchantConfig) ~= "table" then
        return nil
    end

    return {
        id = enchantId,
        display_name = enchantConfig.display_name or enchantId,
        strength = self:_rollStrength(entry.strength),
        roll_profile = profileId,
        rolled_at = tick(),
    }
end

function EnchantService:RollEnchant(rarityId, excludedEffects)
    if not self:IsEnabled() then
        return nil, "disabled"
    end

    local profile, profileId = self:_getRollProfileForRarity(rarityId)
    if not profile then
        return nil, "missing_roll_profile"
    end

    local entries = profile.chances or {}
    if type(excludedEffects) == "table" and profile.prevent_duplicate_effects ~= false then
        local filtered = {}
        for _, entry in ipairs(entries) do
            if not excludedEffects[entry.effect] then
                table.insert(filtered, entry)
            end
        end
        if #filtered > 0 then
            entries = filtered
        end
    end

    local entry = self:_chooseWeighted(entries)
    if not entry then
        return nil, "empty_roll_profile"
    end

    local enchant = self:_buildEnchant(entry, profileId)
    if not enchant then
        return nil, "invalid_enchant_entry"
    end

    return enchant
end

function EnchantService:RollInitialEnchantments(player, petData, petConfig, source)
    if not self:IsEnabled() or type(petData) ~= "table" then
        return petData
    end

    local hatchRolls = self._config.hatch_rolls or {}
    if hatchRolls.enabled ~= true then
        return petData
    end

    local rarityId = petData.rarity_id or (petConfig and petConfig.rarity_id)
    local maxEnchantments = math.max(0, math.floor(tonumber(petData.max_enchantments) or 0))
    local unlockedSlots = math.max(
        0,
        math.floor(tonumber(petData.unlocked_enchant_slots) or maxEnchantments)
    )
    if maxEnchantments <= 0 then
        return petData
    end
    if hatchRolls.require_unlocked_slot ~= false and unlockedSlots <= 0 then
        return petData
    end

    local profile = self:_getRollProfileForRarity(rarityId)
    if not profile then
        return petData
    end

    local existing = type(petData.enchantments) == "table" and #petData.enchantments or 0
    local availableSlots = math.max(
        0,
        math.min(maxEnchantments, unlockedSlots > 0 and unlockedSlots or maxEnchantments) - existing
    )
    local minRolls = math.max(0, math.floor(tonumber(profile.min_rolls) or 0))
    local maxRolls = math.max(minRolls, math.floor(tonumber(profile.max_rolls) or minRolls))
    local targetRolls = math.random(minRolls, maxRolls)
    local rolls = math.min(availableSlots, targetRolls)
    if rolls <= 0 then
        return petData
    end

    local chance = math.clamp(tonumber(profile.initial_roll_chance) or 0, 0, 1)
    petData.enchantments = petData.enchantments or {}
    local excludedEffects = {}
    for _, existingEnchant in ipairs(petData.enchantments) do
        if type(existingEnchant) == "table" and type(existingEnchant.id) == "string" then
            excludedEffects[existingEnchant.id] = true
        end
    end
    local added = 0
    for _ = 1, rolls do
        if math.random() <= chance then
            local enchant = self:RollEnchant(rarityId, excludedEffects)
            if enchant then
                enchant.source = source or petData.grant_source or "pet_grant"
                table.insert(petData.enchantments, enchant)
                excludedEffects[enchant.id] = true
                added += 1
            end
        end
    end

    if added > 0 and self._logger then
        self._logger:Info("Initial pet enchants rolled", {
            context = "EnchantService",
            player = player and player.Name or nil,
            pet = petData.id,
            variant = petData.variant,
            rarity = rarityId,
            added = added,
        })
    end

    return petData
end

function EnchantService:_getPetRecord(player, petUid)
    local data = self._dataService and self._dataService:GetData(player)
    local items = data and data.Inventory and data.Inventory.pets and data.Inventory.pets.items
    local petData = items and items[petUid]
    if type(petData) ~= "table" or petData._kind ~= "special" then
        return nil, "pet_not_unique"
    end
    return petData, nil
end

function EnchantService:_chargeRerollCost(player)
    local reroll = self._config.reroll or {}
    local cost = reroll.cost or {}
    local amount = math.max(0, math.floor(tonumber(cost.amount) or 0))
    local currency = cost.currency
    if amount <= 0 then
        return true
    end
    if type(currency) ~= "string" or currency == "" then
        return false, "invalid_reroll_cost"
    end
    if not self._dataService:CanAfford(player, currency, amount) then
        return false, "insufficient_currency", {
            currency = currency,
            cost = amount,
        }
    end
    self._dataService:RemoveCurrency(player, currency, amount, "pet_enchant_reroll")
    return true, nil, {
        currency = currency,
        cost = amount,
    }
end

function EnchantService:RerollPetEnchant(player, payload)
    if not self:IsEnabled() then
        return {
            ok = false,
            reason = "enchants_disabled",
        }
    end

    local reroll = self._config.reroll or {}
    if reroll.enabled ~= true then
        return {
            ok = false,
            reason = "reroll_disabled",
        }
    end

    payload = type(payload) == "table" and payload or {}
    local petUid = tostring(payload.petUid or payload.uid or "")
    local slot = math.max(
        1,
        math.floor(tonumber(payload.slot) or tonumber(reroll.default_slot) or 1)
    )
    local petData, petError = self:_getPetRecord(player, petUid)
    if not petData then
        return {
            ok = false,
            reason = petError,
            petUid = petUid,
        }
    end

    local maxEnchantments = math.max(0, math.floor(tonumber(petData.max_enchantments) or 0))
    local unlockedSlots = math.max(
        0,
        math.floor(tonumber(petData.unlocked_enchant_slots) or maxEnchantments)
    )
    if maxEnchantments <= 0 or slot > unlockedSlots then
        return {
            ok = false,
            reason = "slot_locked",
            petUid = petUid,
            slot = slot,
            unlockedSlots = unlockedSlots,
            maxEnchantments = maxEnchantments,
        }
    end

    petData.enchantments = type(petData.enchantments) == "table" and petData.enchantments or {}
    local excluded = {}
    for index, existingEnchant in ipairs(petData.enchantments) do
        if index ~= slot and type(existingEnchant) == "table" then
            excluded[existingEnchant.id] = true
        end
    end

    local rarityId = petData.rarity_id
    local enchant, rollError = self:RollEnchant(rarityId, excluded)
    if not enchant then
        return {
            ok = false,
            reason = rollError,
            petUid = petUid,
            slot = slot,
        }
    end

    local paid, payReason, costInfo = self:_chargeRerollCost(player)
    if not paid then
        return {
            ok = false,
            reason = payReason,
            petUid = petUid,
            currency = costInfo and costInfo.currency,
            cost = costInfo and costInfo.cost,
        }
    end

    enchant.source = payload.source or "manual_reroll"
    petData.enchantments[slot] = enchant

    if self._inventoryService and self._inventoryService._updateBucketFolders then
        self._inventoryService:_updateBucketFolders(player, "pets")
    end
    self._dataService:RequestSave(player, "pet_enchant_reroll", { critical = true })

    return {
        ok = true,
        petUid = petUid,
        slot = slot,
        enchant = enchant,
        currency = costInfo and costInfo.currency,
        cost = costInfo and costInfo.cost,
    }
end

function EnchantService:_matchesModifierContext(modifier, context)
    if type(modifier) ~= "table" or type(context) ~= "table" then
        return false
    end
    if modifier.kind ~= nil and modifier.kind ~= context.kind then
        return false
    end
    if modifier.currency ~= nil and modifier.currency ~= context.currency then
        return false
    end
    return true
end

function EnchantService:_getEquippedUniquePets(player)
    local data = self._dataService and self._dataService:GetData(player)
    local equipped = data and data.Equipped and data.Equipped.pets
    local items = data and data.Inventory and data.Inventory.pets and data.Inventory.pets.items
    if type(equipped) ~= "table" or type(items) ~= "table" then
        return {}
    end

    local pets = {}
    for _, uid in pairs(equipped) do
        if type(uid) == "string" and not string.match(uid, "^stack|") then
            local petData = items[uid]
            if type(petData) == "table" and petData._kind == "special" then
                table.insert(pets, {
                    uid = uid,
                    data = petData,
                })
            end
        end
    end
    return pets
end

function EnchantService:_getModifierContributions(context)
    if type(context) ~= "table" or not context.player then
        return {}
    end

    local contributions = {}
    for _, pet in ipairs(self:_getEquippedUniquePets(context.player)) do
        for _, enchant in ipairs(pet.data.enchantments or {}) do
            local enchantConfig = self._config.effects and self._config.effects[enchant.id]
            local modifier = enchantConfig and enchantConfig.modifier
            if self:_matchesModifierContext(modifier, context) then
                local strength = tonumber(enchant.strength or enchant.value) or 0
                local value = strength * (tonumber(modifier.amount_per_strength) or 0)
                local combine = modifier.combine or "add"
                local amount = value
                if combine == "multiply" then
                    amount = 1 + value
                end
                table.insert(contributions, {
                    id = tostring(pet.uid) .. ":" .. tostring(enchant.id),
                    label = enchant.display_name or enchantConfig.display_name or enchant.id,
                    amount = amount,
                    combine = combine,
                })
            end
        end
    end

    return contributions
end

return EnchantService
