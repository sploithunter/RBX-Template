--[[
    EggService - Following working game pattern
    
    Simple egg purchase handling using RemoteFunction like the working game.
    Matches their EggHandler pattern exactly.
--]]

local EggService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Locations = require(ReplicatedStorage.Shared.Locations)
local petConfig = Locations.getConfig("pets")
local eggSystemConfig = Locations.getConfig("egg_system")
local EggWorldQuery = require(ReplicatedStorage.Shared.Services.EggWorldQuery)

-- Logger setup using singleton pattern
local Logger
local loggerSuccess, loggerResult = pcall(function()
    return require(Locations.Logger)
end)

if loggerSuccess and loggerResult then
    Logger = loggerResult -- Use singleton directly
else
    Logger = {
        Info = function(self, message, context)
            print("[INFO]", message, context)
        end,
        Warn = function(self, message, context)
            warn("[WARN]", message, context)
        end,
        Error = function(self, message, context)
            warn("[ERROR]", message, context)
        end,
        Debug = function(self, message, context)
            print("[DEBUG]", message, context)
        end,
    }
end

-- Player cooldowns
local playerCooldowns = {}
local playerHatchLocks = {}

-- RemoteFunction for egg purchases
local eggRemoteFunction = nil

-- Player current egg tracking (for persistence)
local playerCurrentEggs = {}

-- === HELPER FUNCTIONS ===

function EggService:IsOnCooldown(player)
    local playerId = player.UserId
    local lastPurchase = playerCooldowns[playerId] or 0
    local cooldownTime = eggSystemConfig.cooldowns.purchase_cooldown
    local currentTime = tick()

    if currentTime - lastPurchase < cooldownTime then
        return true, cooldownTime - (currentTime - lastPurchase)
    end

    playerCooldowns[playerId] = currentTime
    return false, 0
end

function EggService:GetHatchingConfig()
    return eggSystemConfig.hatching or {}
end

function EggService:GetMaxHatchCount()
    local hatching = self:GetHatchingConfig()
    return math.clamp(math.floor(tonumber(hatching.max_count) or 99), 1, 99)
end

function EggService:GetRequestedCountForPurchaseType(purchaseType)
    local hatching = self:GetHatchingConfig()
    local compat = hatching.compat_purchase_types or {}
    local defaultCount = tonumber(hatching.default_requested_count) or 1
    local configured = compat[tostring(purchaseType or "Single")]
    return tonumber(configured) or defaultCount
end

function EggService:NormalizeHatchRequest(rawEggType, purchaseType)
    local isBatchRequest = type(rawEggType) == "table"
    local request = {
        legacy = not isBatchRequest,
        purchaseType = purchaseType or "Single",
        requestedCount = self:GetRequestedCountForPurchaseType(purchaseType),
        options = {},
    }

    if isBatchRequest then
        local payload = rawEggType
        request.legacy = payload.legacy == true
        request.eggType = payload.eggType or payload.eggId or payload.EggType
        request.purchaseType = payload.purchaseType
            or payload.PurchaseType
            or purchaseType
            or "Batch"
        request.requestedCount = payload.requestedCount
            or payload.count
            or payload.Count
            or payload.quantity
            or self:GetRequestedCountForPurchaseType(request.purchaseType)
        request.options = type(payload.options) == "table" and payload.options or {}
        request.autoSessionId = payload.autoSessionId
    else
        request.eggType = rawEggType
    end

    request.eggType = tostring(request.eggType or "")
    request.requestedCount = math.floor(tonumber(request.requestedCount) or 1)
    request.requestedCount = math.clamp(request.requestedCount, 1, self:GetMaxHatchCount())
    return request
end

function EggService:FormatError(request, message, code, details)
    if request and request.legacy then
        return "Error", message
    end

    details = details or {}
    if request and request.autoSessionId ~= nil and details.autoSessionId == nil then
        details.autoSessionId = request.autoSessionId
    end

    return {
        ok = false,
        success = false,
        code = code or "error",
        message = message,
        details = details,
    }
end

function EggService:AcquireHatchLock(player)
    local playerId = player.UserId
    local currentTime = os.clock()
    local existing = playerHatchLocks[playerId]
    if existing and existing.expiresAt and existing.expiresAt > currentTime then
        return false, existing.expiresAt - currentTime
    end

    local hatching = self:GetHatchingConfig()
    local lockSeconds = tonumber(hatching.transaction_lock_seconds) or 0.35
    playerHatchLocks[playerId] = {
        expiresAt = currentTime + math.max(0.05, lockSeconds),
    }
    return true, 0
end

function EggService:ReleaseHatchLock(player, success)
    local playerId = player.UserId
    local hatching = self:GetHatchingConfig()
    local holdSeconds
    if success then
        holdSeconds = tonumber(eggSystemConfig.cooldowns.purchase_cooldown) or 0
    else
        holdSeconds = tonumber(hatching.failed_request_lock_seconds) or 0.2
    end

    if holdSeconds <= 0 then
        playerHatchLocks[playerId] = nil
        return
    end

    playerHatchLocks[playerId] = {
        expiresAt = os.clock() + holdSeconds,
    }
end

function EggService:HasEnoughCurrency(player, currency, cost)
    if self._dataService then
        return self._dataService:CanAfford(player, currency, cost),
            self._dataService:GetCurrency(player, currency)
    else
        -- Fallback to attributes if DataService not available
        local currentAmount = player:GetAttribute(currency) or 0
        return currentAmount >= cost, currentAmount
    end
end

function EggService:GetCurrencyBalance(player, currency)
    if self._dataService then
        return self._dataService:GetCurrency(player, currency)
    end
    return player:GetAttribute(currency) or 0
end

function EggService:DeductCurrency(player, currency, cost)
    if self._dataService then
        return self._dataService:RemoveCurrency(player, currency, cost, "egg_hatch")
    else
        -- Fallback to attributes if DataService not available
        local currentAmount = player:GetAttribute(currency) or 0
        if currentAmount >= cost then
            player:SetAttribute(currency, currentAmount - cost)
            return true
        end
        return false
    end
end

function EggService:AddCurrency(player, currency, amount, source)
    if amount <= 0 then
        return true
    end

    if self._dataService then
        return self._dataService:AddCurrency(player, currency, amount, source or "egg_hatch_refund")
    end

    local currentAmount = player:GetAttribute(currency) or 0
    player:SetAttribute(currency, currentAmount + amount)
    return true
end

function EggService:IsPlayerNearEgg(player, eggType)
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end

    local playerPosition = player.Character.HumanoidRootPart.Position

    local isNear =
        EggWorldQuery.IsNearEggType(eggType, playerPosition, eggSystemConfig.proximity.max_distance)
    return isNear == true
end

function EggService:ResolveHatchEntitlements(player)
    local hatching = self:GetHatchingConfig()
    local shopStubs = hatching.shop_stubs or {}
    local maxStub = shopStubs.max_hatch_count or {}
    local defaultMax = tonumber(maxStub.default_value)
        or tonumber(hatching.default_max_entitled_count)
        or self:GetMaxHatchCount()
    local attributeMax = tonumber(player:GetAttribute("MaxEggHatchCount"))
    local maxHatchCount = attributeMax or defaultMax
    local function resolveBooleanEntitlement(attributeName, stubConfig)
        local attributeValue = player:GetAttribute(attributeName)
        if attributeValue ~= nil then
            return attributeValue == true
        end
        return stubConfig and stubConfig.owned_by_default == true
    end

    return {
        maxHatchCount = math.clamp(math.floor(maxHatchCount), 1, self:GetMaxHatchCount()),
        autoHatch = resolveBooleanEntitlement("AutoHatchUnlocked", shopStubs.auto_hatch),
        fastHatch = resolveBooleanEntitlement("FastHatchUnlocked", shopStubs.fast_hatch),
        skipHatch = resolveBooleanEntitlement("SkipHatchUnlocked", shopStubs.skip_hatch),
        goldenMode = resolveBooleanEntitlement("GoldenHatchUnlocked", shopStubs.golden_mode),
        chargedMode = resolveBooleanEntitlement("ChargedHatchUnlocked", shopStubs.charged_mode),
    }
end

function EggService:ResolveHatchOptions(player, request, entitlements)
    local options = request.options or {}
    local hatching = self:GetHatchingConfig()
    local shopStubs = hatching.shop_stubs or {}
    local goldenStub = shopStubs.golden_mode or {}
    local chargedStub = shopStubs.charged_mode or {}

    if
        (request.purchaseType == "Auto" or request.autoSessionId ~= nil)
        and entitlements.autoHatch ~= true
    then
        return nil,
            "Auto hatch is locked",
            "feature_locked",
            {
                mode = "autoHatch",
            }
    end

    local resolved = {
        goldenMode = false,
        chargedMode = false,
        fastHatch = options.fastHatch == true and entitlements.fastHatch == true,
        skipHatch = options.skipHatch == true and entitlements.skipHatch == true,
        silentHatch = options.silentHatch == true,
        costMultiplier = 1,
    }

    if options.goldenMode == true then
        if entitlements.goldenMode ~= true then
            return nil,
                "Golden hatch mode is locked",
                "feature_locked",
                {
                    mode = "goldenMode",
                }
        end
        resolved.goldenMode = true
        resolved.costMultiplier *= math.max(1, tonumber(goldenStub.cost_multiplier) or 20)
    end

    if options.chargedMode == true then
        if entitlements.chargedMode ~= true then
            return nil,
                "Charged hatch mode is locked",
                "feature_locked",
                {
                    mode = "chargedMode",
                }
        end
        resolved.chargedMode = true
        resolved.costMultiplier *= math.max(1, tonumber(chargedStub.cost_multiplier) or 5)
    end

    return resolved
end

function EggService:BuildPlayerHatchData(player, eggType, eggData, hatchOptions)
    local playerData = {
        level = player:GetAttribute("Level") or 1,
        petsHatched = player:GetAttribute("PetsHatched") or 0,
        hasLuckGamepass = false,
        hasGoldenGamepass = false,
        hasRainbowGamepass = false,
        isVIP = false,
    }

    if self._eventService then
        playerData.luckBoost = self._eventService:GetModifier("egg_luck", 0)
    end

    if self._modifierService and self._modifierService.Resolve then
        local baseLuckBoost = tonumber(playerData.luckBoost) or 0
        local hatchLuck = self._modifierService:Resolve(baseLuckBoost, {
            player = player,
            kind = "hatch_luck",
            eggType = eggType,
            currency = eggData.currency,
            source = "EggService",
        })
        local secretLuck = self._modifierService:Resolve(0, {
            player = player,
            kind = "secret_hatch_luck",
            eggType = eggType,
            currency = eggData.currency,
            source = "EggService",
        })
        playerData.luckBoost = tonumber(hatchLuck) or baseLuckBoost
        playerData.secretLuckBoost = tonumber(secretLuck) or 0
    end

    hatchOptions = type(hatchOptions) == "table" and hatchOptions or {}
    if hatchOptions.chargedMode == true then
        local hatching = self:GetHatchingConfig()
        local chargedStub = hatching.shop_stubs and hatching.shop_stubs.charged_mode or {}
        playerData.luckBoost = (tonumber(playerData.luckBoost) or 0)
            + (tonumber(chargedStub.luck_bonus) or 0)
        playerData.secretLuckBoost = (tonumber(playerData.secretLuckBoost) or 0)
            + (tonumber(chargedStub.secret_luck_bonus) or 0)
    end

    return playerData
end

function EggService:SetTestHatchOverride(player, forcedPet, forcedVariant)
    petConfig.test_mode = petConfig.test_mode or {}
    if forcedPet or forcedVariant then
        petConfig.test_mode.enabled = true
        petConfig.test_mode.force_pet = forcedPet
        petConfig.test_mode.force_variant = forcedVariant or "basic"
        petConfig.test_mode._force_source_user_id = player and player.UserId or nil
        return
    end

    if
        player
        and petConfig.test_mode._force_source_user_id ~= nil
        and petConfig.test_mode._force_source_user_id ~= player.UserId
    then
        return
    end

    petConfig.test_mode.force_pet = nil
    petConfig.test_mode.force_variant = nil
    petConfig.test_mode._force_source_user_id = nil
    if
        not petConfig.test_mode.super_luck
        and not petConfig.test_mode.pet_weight_overrides
        and not petConfig.test_mode.rarity_overrides
    then
        petConfig.test_mode.enabled = false
    end
end

function EggService:ApplyTestOverrides(player)
    local attrForcePet = player:GetAttribute("ForcePet")
    local attrForceVariant = player:GetAttribute("ForceVariant")
    if attrForcePet or attrForceVariant then
        self:SetTestHatchOverride(player, attrForcePet, attrForceVariant)
        Logger:Info("Hatch override active", {
            player = player.Name,
            force_pet = attrForcePet,
            force_variant = attrForceVariant,
        })
        return
    end

    if not (petConfig.test_mode and petConfig.test_mode.enabled) then
        Logger:Debug("No hatch override attributes set", { player = player.Name })
    end
end

function EggService:IsSpecialPetOutcome(hatchResult)
    if hatchResult.huge == true then
        return true
    end
    if self._inventoryService and self._inventoryService._isSpecialPet then
        return self._inventoryService:_isSpecialPet(hatchResult.pet, hatchResult.variant)
    end

    local petData = hatchResult.petData
        or (petConfig.getPet and petConfig.getPet(hatchResult.pet, hatchResult.variant))
    local rarityId = petData and petData.rarity_id
    return rarityId == "mythic"
        or rarityId == "secret"
        or rarityId == "exclusive"
        or rarityId == "huge"
end

function EggService:IsSpecialRevealOutcome(hatchResult)
    local hatching = self:GetHatchingConfig()
    local animation = hatching.animation or {}
    if animation.special_reveal_enabled == false then
        return false
    end
    if hatchResult.huge == true then
        return true
    end

    local petData = hatchResult.petData
        or (petConfig.getPet and petConfig.getPet(hatchResult.pet, hatchResult.variant))
    local rarityId = petData and petData.rarity_id
    local specialRarities = animation.special_rarities or {}
    return type(rarityId) == "string" and specialRarities[rarityId] == true
end

function EggService:ResolveStorageLimitedOutcomes(player, outcomes)
    if not self._inventoryService then
        return outcomes, nil
    end

    local bucket = self._inventoryService:GetInventory(player, "pets")
    if not bucket then
        return outcomes, nil
    end

    local totalSlots = tonumber(bucket.total_slots) or 0
    local usedSlots = tonumber(bucket.used_slots) or 0
    local availableSlots = math.max(0, totalSlots - usedSlots)
    local usedNewSlots = 0
    local simulatedStacks = {}
    local accepted = {}

    for _, outcome in ipairs(outcomes) do
        local requiresSlot = false
        if not outcome.autoDeleted then
            if self:IsSpecialPetOutcome(outcome.hatchResult) then
                requiresSlot = true
            else
                local stackKey = string.format(
                    "%s:%s",
                    tostring(outcome.hatchResult.pet),
                    tostring(outcome.hatchResult.variant or "basic")
                )
                local hasExistingStack = bucket.items and bucket.items[stackKey] ~= nil
                if not hasExistingStack and not simulatedStacks[stackKey] then
                    requiresSlot = true
                    simulatedStacks[stackKey] = true
                end
            end
        end

        if requiresSlot and usedNewSlots >= availableSlots then
            return accepted, "storage"
        end

        if requiresSlot then
            usedNewSlots += 1
        end
        table.insert(accepted, outcome)
    end

    return accepted, nil
end

function EggService:GetEggAnimationPayload(eggType, eggData)
    local payload = {
        eggType = eggType,
        eggId = eggType,
        displayName = eggData and eggData.name or eggType,
        useAuthoredEggVisual = true,
    }

    local eggInstance = EggWorldQuery.FindEggByType(eggType)
    if eggInstance then
        payload.worldPath = eggInstance:GetFullName()
        payload.modelName = eggInstance.Name
        local anchor = EggWorldQuery.GetAnchor(eggInstance)
        if anchor then
            payload.anchorName = anchor.Name
        end
    end

    return payload
end

-- === MAIN HANDLER (following working game pattern) ===

function EggService:HandleEggPurchase(player, eggType, purchaseType)
    local request = self:NormalizeHatchRequest(eggType, purchaseType)
    Logger:Info("Egg purchase request", {
        player = player.Name,
        eggType = request.eggType,
        purchaseType = request.purchaseType,
        requestedCount = request.requestedCount,
    })

    local lockAcquired, lockRemaining = self:AcquireHatchLock(player)
    if not lockAcquired then
        Logger:Debug("Player hatch transaction locked", {
            player = player.Name,
            remainingTime = lockRemaining,
        })
        return self:FormatError(request, "Please wait before hatching again", "hatch_locked", {
            remainingTime = lockRemaining,
        })
    end

    -- Validate egg type
    local eggData = petConfig.egg_sources[request.eggType]
    if not eggData then
        Logger:Warn("Invalid egg type", { player = player.Name, eggType = request.eggType })
        self:ReleaseHatchLock(player, false)
        return self:FormatError(request, "Invalid egg type", "invalid_egg")
    end
    local eggCost = (petConfig.getEggCost and petConfig.getEggCost(request.eggType)) or eggData.cost
    eggCost = math.max(0, tonumber(eggCost) or 0)

    -- Check distance (server-side validation)
    if not self:IsPlayerNearEgg(player, request.eggType) then
        Logger:Warn("Player too far from egg", { player = player.Name, eggType = request.eggType })
        self:ReleaseHatchLock(player, false)
        return self:FormatError(request, "Too far away", "too_far")
    end

    local entitlements = self:ResolveHatchEntitlements(player)
    local hatchOptions, optionMessage, optionCode, optionDetails =
        self:ResolveHatchOptions(player, request, entitlements)
    if not hatchOptions then
        self:ReleaseHatchLock(player, false)
        return self:FormatError(
            request,
            optionMessage or "Hatch mode locked",
            optionCode or "feature_locked",
            optionDetails
        )
    end
    eggCost = math.floor((eggCost * (hatchOptions.costMultiplier or 1)) + 0.5)

    local hatching = self:GetHatchingConfig()
    local allowPartial = hatching.allow_partial ~= false
    local entitledCount = math.min(request.requestedCount, entitlements.maxHatchCount)
    local currentAmount = self:GetCurrencyBalance(player, eggData.currency)
    local affordableCount = entitledCount
    if eggCost > 0 then
        affordableCount = math.floor(currentAmount / eggCost)
    end

    local preliminaryCount = math.min(entitledCount, affordableCount)

    Logger:Info("🪙 EGG PURCHASE - Currency check", {
        player = player.Name,
        eggType = request.eggType,
        currency = eggData.currency,
        costEach = eggCost,
        current = currentAmount,
        requestedCount = request.requestedCount,
        entitledCount = entitledCount,
        affordableCount = affordableCount,
        dataServiceAvailable = self._dataService ~= nil,
    })

    if preliminaryCount <= 0 then
        Logger:Warn("🚫 INSUFFICIENT CURRENCY", {
            player = player.Name,
            currency = eggData.currency,
            required = eggCost,
            current = currentAmount,
        })
        self:ReleaseHatchLock(player, false)
        return self:FormatError(
            request,
            "Insufficient " .. eggData.currency,
            "insufficient_currency",
            {
                current = currentAmount,
                costEach = eggCost,
            }
        )
    end

    if preliminaryCount < request.requestedCount and not allowPartial then
        self:ReleaseHatchLock(player, false)
        return self:FormatError(request, "Cannot hatch requested amount", "partial_not_allowed", {
            requestedCount = request.requestedCount,
            availableCount = preliminaryCount,
        })
    end

    local playerData = self:BuildPlayerHatchData(player, request.eggType, eggData, hatchOptions)
    playerData.hatchOptions = hatchOptions
    self:ApplyTestOverrides(player)

    local outcomes = {}
    for _ = 1, preliminaryCount do
        local hatchResult = petConfig.simulateHatch(request.eggType, playerData)
        if not hatchResult then
            Logger:Error("Hatching failed", { player = player.Name, eggType = request.eggType })
            self:ReleaseHatchLock(player, false)
            return self:FormatError(request, "Hatching failed", "hatch_failed")
        end

        local autoDeleted = false
        local autoDeleteReason = nil
        if self._autoTargetService and self._autoTargetService.ShouldAutoDeleteHatch then
            autoDeleted, autoDeleteReason =
                self._autoTargetService:ShouldAutoDeleteHatch(player, hatchResult)
        end

        table.insert(outcomes, {
            hatchResult = hatchResult,
            autoDeleted = autoDeleted,
            autoDeleteReason = autoDeleteReason,
        })
    end

    local storageLimitedOutcomes, storageStop = self:ResolveStorageLimitedOutcomes(player, outcomes)
    if #storageLimitedOutcomes <= 0 then
        self:ReleaseHatchLock(player, false)
        return self:FormatError(request, "No pet storage available", "no_storage")
    end
    if #storageLimitedOutcomes < #outcomes and not allowPartial then
        self:ReleaseHatchLock(player, false)
        return self:FormatError(request, "No pet storage available", "no_storage")
    end
    outcomes = storageLimitedOutcomes

    local totalCost = eggCost * #outcomes
    local deductSuccess = self:DeductCurrency(player, eggData.currency, totalCost)
    if not deductSuccess then
        Logger:Error("Failed to deduct currency", { player = player.Name })
        self:ReleaseHatchLock(player, false)
        return self:FormatError(request, "Transaction failed", "deduct_failed")
    end

    local resultEntries = {}
    local processedCount = 0
    local grantFailed = nil
    local specialRevealCount = 0
    for _, outcome in ipairs(outcomes) do
        local hatchResult = outcome.hatchResult
        local grantResult = nil

        if outcome.autoDeleted then
            Logger:Info("Hatched pet auto-deleted by player filter", {
                player = player.Name,
                pet = hatchResult.pet,
                variant = hatchResult.variant,
                reason = outcome.autoDeleteReason,
            })
        elseif self._petGrantService then
            grantResult = self._petGrantService:GrantPet(player, {
                petType = hatchResult.pet,
                variant = hatchResult.variant,
                source = "egg_hatch",
            })
            if grantResult.ok then
                Logger:Info("Pet granted from egg hatch", {
                    player = player.Name,
                    uid = grantResult.uid,
                    pet = hatchResult.pet,
                    variant = hatchResult.variant,
                })
            else
                grantFailed = grantResult.error or "Failed to grant pet"
                Logger:Error("Failed to grant hatched pet", {
                    player = player.Name,
                    pet = hatchResult.pet,
                    variant = hatchResult.variant,
                    error = grantFailed,
                })
                break
            end
        else
            Logger:Warn("PetGrantService not available - pet not saved to inventory", {
                player = player.Name,
                pet = hatchResult.pet,
            })
        end

        processedCount += 1
        local rarityId = hatchResult.petData and hatchResult.petData.rarity_id or nil
        local rarityName = hatchResult.petData
                and hatchResult.petData.rarity
                and hatchResult.petData.rarity.name
            or rarityId
        local specialHatch = self:IsSpecialRevealOutcome(hatchResult)
        if specialHatch then
            specialRevealCount += 1
        end
        table.insert(resultEntries, {
            Pet = hatchResult.pet,
            PetNum = hatchResult.pet,
            Type = hatchResult.variant,
            Power = hatchResult.petData and hatchResult.petData.power or 0,
            RarityId = rarityId,
            RarityName = rarityName,
            SpecialHatch = specialHatch,
            FinalGoldenChance = hatchResult.finalGoldenChance,
            FinalRainbowChance = hatchResult.finalRainbowChance,
            LuckMultiplier = hatchResult.luckMultiplier,
            EggType = request.eggType,
            Cost = eggCost,
            AutoDeleted = outcome.autoDeleted,
            AutoDeleteReason = outcome.autoDeleteReason,
            uid = grantResult and grantResult.uid or nil,
            pet = hatchResult.pet,
            variant = hatchResult.variant,
            power = hatchResult.petData and hatchResult.petData.power or 0,
            rarityId = rarityId,
            rarityName = rarityName,
            specialHatch = specialHatch,
            finalGoldenChance = hatchResult.finalGoldenChance,
            finalRainbowChance = hatchResult.finalRainbowChance,
            luckMultiplier = hatchResult.luckMultiplier,
            autoDeleted = outcome.autoDeleted,
            autoDeleteReason = outcome.autoDeleteReason,
        })
    end

    if processedCount < #outcomes then
        local refund = (#outcomes - processedCount) * eggCost
        self:AddCurrency(player, eggData.currency, refund, "egg_hatch_partial_refund")
    end

    if processedCount <= 0 then
        self:AddCurrency(player, eggData.currency, totalCost, "egg_hatch_refund")
        self:ReleaseHatchLock(player, false)
        return self:FormatError(request, grantFailed or "Failed to grant pet", "grant_failed")
    end

    if self._statsService then
        pcall(function()
            self._statsService:Increment(player, "eggs_hatched", processedCount)
        end)
    end

    local stopReason = nil
    if processedCount < request.requestedCount then
        if storageStop then
            stopReason = storageStop
        elseif affordableCount < entitledCount then
            stopReason = "currency"
        elseif entitledCount < request.requestedCount then
            stopReason = "entitlement"
        elseif grantFailed then
            stopReason = "grant_failed"
        else
            stopReason = "partial"
        end
    end

    local first = resultEntries[1]
    local animationPayload = self:GetEggAnimationPayload(request.eggType, eggData)
    animationPayload.specialReveal = specialRevealCount > 0
    animationPayload.specialRevealCount = specialRevealCount

    local response = {
        ok = true,
        success = true,
        Pet = first.Pet,
        PetNum = first.PetNum,
        Type = first.Type,
        Power = first.Power,
        EggType = request.eggType,
        Cost = eggCost,
        TotalCost = eggCost * processedCount,
        Currency = eggData.currency,
        AutoDeleted = first.AutoDeleted,
        AutoDeleteReason = first.AutoDeleteReason,
        requestedCount = request.requestedCount,
        hatchCount = processedCount,
        results = resultEntries,
        stopReason = stopReason,
        entitlements = entitlements,
        options = hatchOptions,
        autoSessionId = request.autoSessionId,
        animation = animationPayload,
    }

    Logger:Info("Egg hatch transaction complete", {
        player = player.Name,
        eggType = request.eggType,
        requestedCount = request.requestedCount,
        hatchCount = processedCount,
        stopReason = stopReason,
        totalCost = response.TotalCost,
    })

    self:ReleaseHatchLock(player, true)
    return response
end

-- === CURRENT EGG TRACKING (for persistence) ===

function EggService:SetLastEgg(player, eggType)
    local playerId = player.UserId
    playerCurrentEggs[playerId] = eggType

    Logger:Debug("Set last egg for player", {
        player = player.Name,
        eggType = eggType or "nil",
    })

    -- TODO: Save to player data for persistence across sessions
    -- This would integrate with your DataService to save the current egg

    return true
end

function EggService:GetLastEgg(player)
    local playerId = player.UserId
    return playerCurrentEggs[playerId]
end

-- === INITIALIZATION ===

function EggService:Initialize(moduleLoader)
    Logger:Info("EggService initializing...")

    -- Get services from the module loader
    if moduleLoader then
        self._inventoryService = moduleLoader:Get("InventoryService")
        self._dataService = moduleLoader:Get("DataService")
        self._eventService = moduleLoader:Get("EventService")
        self._statsService = moduleLoader:Get("StatsService")
        self._petGrantService = moduleLoader:Get("PetGrantService")
        self._modifierService = moduleLoader:Get("ModifierService")
        self._autoTargetService = moduleLoader:Get("AutoTargetService")

        if self._inventoryService then
            Logger:Info("EggService: InventoryService connection established")
        else
            Logger:Warn("EggService: InventoryService not available in module loader")
        end

        if self._dataService then
            Logger:Info("EggService: DataService connection established")
        else
            Logger:Warn("EggService: DataService not available in module loader")
        end

        if self._eventService then
            Logger:Info("EggService: EventService connection established")
        else
            Logger:Warn("EggService: EventService not available in module loader")
        end

        if self._statsService then
            Logger:Info("EggService: StatsService connection established")
        else
            Logger:Warn("EggService: StatsService not available in module loader")
        end

        if self._petGrantService then
            Logger:Info("EggService: PetGrantService connection established")
        else
            Logger:Warn("EggService: PetGrantService not available in module loader")
        end

        if self._modifierService then
            Logger:Info("EggService: ModifierService connection established")
        else
            Logger:Warn("EggService: ModifierService not available in module loader")
        end

        if self._autoTargetService then
            Logger:Info("EggService: AutoTargetService connection established")
        else
            Logger:Warn("EggService: AutoTargetService not available in module loader")
        end
    else
        Logger:Warn("EggService: No module loader provided")
    end

    -- Create RemoteFunction (like working game)
    eggRemoteFunction = Instance.new("RemoteFunction")
    eggRemoteFunction.Name = "EggOpened"
    eggRemoteFunction.Parent = ReplicatedStorage

    -- Create setLastEgg RemoteFunction (like working game)
    local setLastEggRemote = Instance.new("RemoteFunction")
    setLastEggRemote.Name = "setLastEgg"
    setLastEggRemote.Parent = eggRemoteFunction

    -- Set up the handlers
    eggRemoteFunction.OnServerInvoke = function(player, eggType, purchaseType)
        return self:HandleEggPurchase(player, eggType, purchaseType)
    end

    setLastEggRemote.OnServerInvoke = function(player, eggType)
        return self:SetLastEgg(player, eggType)
    end

    -- Clean up when players leave
    Players.PlayerRemoving:Connect(function(player)
        playerCooldowns[player.UserId] = nil
        playerHatchLocks[player.UserId] = nil
        playerCurrentEggs[player.UserId] = nil
    end)

    Logger:Info("EggService initialized with RemoteFunction and setLastEgg tracking")
end

return EggService
