--[[
    PetProgressionService

    Config-driven progression math for unique pets. Stack pets stay compact and
    do not receive per-copy XP/level state until a future promotion flow makes
    one copy unique.
]]

local PetProgressionService = {}
PetProgressionService.__index = PetProgressionService

function PetProgressionService.new()
    local self = setmetatable({}, PetProgressionService)
    self._logger = nil
    self._configLoader = nil
    self._dataService = nil
    self._inventoryService = nil
    self._modifierService = nil
    self._config = nil
    self._petsConfig = nil
    return self
end

function PetProgressionService:Init()
    self._logger = self._modules.Logger
    self._configLoader = self._modules.ConfigLoader
    self._dataService = self._modules.DataService
    self._inventoryService = self._modules.InventoryService
    self._modifierService = self._modules.ModifierService
    self._config = self._configLoader:LoadConfig("pet_progression")
    self._petsConfig = self._configLoader:LoadConfig("pets")

    self._logger:Info("PetProgressionService initialized", {
        context = "PetProgressionService",
        enabled = self:IsEnabled(),
    })
end

function PetProgressionService:IsEnabled()
    return self._config and self._config.enabled ~= false
end

function PetProgressionService:GetMaxLevel(rarityId)
    if not self:IsEnabled() then
        return 1
    end

    local byRarity = self._config.max_level_by_rarity or {}
    return math.max(
        1,
        math.floor(tonumber(byRarity[rarityId]) or self._config.default_max_level or 1)
    )
end

function PetProgressionService:GetXpRequiredForLevel(level)
    level = math.max(1, math.floor(tonumber(level) or 1))
    local curve = self._config.xp_curve or {}
    local base = tonumber(curve.base) or 100

    if curve.type == "linear" then
        local increment = tonumber(curve.increment) or 0
        return math.max(1, math.floor(base + (increment * (level - 1))))
    end

    local growth = tonumber(curve.growth) or 1
    return math.max(1, math.floor(base * (growth ^ (level - 1))))
end

function PetProgressionService:GetPowerMultiplier(level)
    if not self:IsEnabled() then
        return 1
    end

    level = math.max(1, math.floor(tonumber(level) or 1))
    local scaling = self._config.power_scaling or {}
    local perLevel = tonumber(scaling.percent_per_level) or 0
    local maxBonus = tonumber(scaling.max_bonus_percent) or 0
    local bonus = math.min(maxBonus, math.max(0, (level - 1) * perLevel))
    return 1 + bonus
end

function PetProgressionService:GetPowerForLevel(basePower, level)
    basePower = tonumber(basePower) or 0
    if basePower <= 0 then
        return 0
    end
    return math.max(1, math.floor(basePower * self:GetPowerMultiplier(level)))
end

function PetProgressionService:GetUnlockedEnchantSlots(rarityId, level, maxEnchantments)
    maxEnchantments = math.max(0, math.floor(tonumber(maxEnchantments) or 0))
    if maxEnchantments <= 0 or not self:IsEnabled() then
        return 0
    end

    level = math.max(1, math.floor(tonumber(level) or 1))
    local slotConfig = self._config.enchant_slots or {}
    local unlocked = math.floor(tonumber(slotConfig.default_unlocked_slots) or 0)

    local unlocksByRarity = slotConfig.unlocks_by_rarity or {}
    for _, unlock in ipairs(unlocksByRarity[rarityId] or {}) do
        if level >= (tonumber(unlock.level) or math.huge) then
            unlocked = math.max(unlocked, math.floor(tonumber(unlock.slots) or 0))
        end
    end

    if unlocked <= 0 and maxEnchantments > 0 then
        unlocked = 1
    end
    return math.clamp(unlocked, 0, maxEnchantments)
end

function PetProgressionService:ApplyProgression(petData, petConfig)
    if type(petData) ~= "table" then
        return petData
    end
    if not self:IsEnabled() then
        return petData
    end

    local rarityId = petData.rarity_id
        or petData.rarity_override
        or (petConfig and petConfig.rarity_id)
    local maxLevel = self:GetMaxLevel(rarityId)
    local level = math.clamp(math.floor(tonumber(petData.level) or 1), 1, maxLevel)
    local exp = math.max(0, math.floor(tonumber(petData.exp) or 0))

    petData.level = level
    petData.exp = exp
    petData.max_level = maxLevel
    petData.xp_to_next_level = level < maxLevel and self:GetXpRequiredForLevel(level) or 0

    local maxEnchantments = math.max(0, math.floor(tonumber(petData.max_enchantments) or 0))
    local unlockedSlots = self:GetUnlockedEnchantSlots(rarityId, level, maxEnchantments)
    if maxEnchantments > 0 then
        petData.enchantable = true
        petData.unlocked_enchant_slots = unlockedSlots
        petData.enchantments = petData.enchantments or {}
    end

    return petData
end

function PetProgressionService:AddPetExperience(player, petUid, amount, reason)
    if not self:IsEnabled() then
        return false, "pet_progression_disabled"
    end
    if not player or type(petUid) ~= "string" then
        return false, "invalid_pet"
    end

    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return false, "invalid_amount"
    end

    local data = self._dataService:GetData(player)
    local petsBucket = data and data.Inventory and data.Inventory.pets
    local petData = petsBucket and petsBucket.items and petsBucket.items[petUid]
    if type(petData) ~= "table" or petData._kind ~= "special" then
        return false, "pet_not_unique"
    end

    local petConfig = self._petsConfig.getPet
        and self._petsConfig.getPet(petData.id, petData.variant or "basic")
    if not petConfig then
        return false, "unknown_pet_config"
    end

    local rarityId = petData.rarity_id or petConfig.rarity_id
    local maxLevel = self:GetMaxLevel(rarityId)
    local level = math.clamp(math.floor(tonumber(petData.level) or 1), 1, maxLevel)
    local exp = math.max(0, math.floor(tonumber(petData.exp) or 0)) + amount

    while level < maxLevel do
        local required = self:GetXpRequiredForLevel(level)
        if exp < required then
            break
        end
        exp -= required
        level += 1
    end
    if level >= maxLevel then
        exp = 0
    end

    petData.level = level
    petData.exp = exp
    self:ApplyProgression(petData, petConfig)

    if self._inventoryService and self._inventoryService.RebuildPetProjections then
        self._inventoryService:RebuildPetProjections(player)
    elseif self._inventoryService and self._inventoryService._updateBucketFolders then
        self._inventoryService:_updateBucketFolders(player, "pets")
    end
    self._dataService:RequestSave(player, "pet_progression_" .. tostring(reason or "xp"), {
        critical = true,
    })

    self._logger:Info("Pet XP applied", {
        context = "PetProgressionService",
        player = player.Name,
        petUid = petUid,
        amount = amount,
        level = petData.level,
        exp = petData.exp,
        unlockedEnchantSlots = petData.unlocked_enchant_slots,
    })

    return true,
        {
            level = petData.level,
            exp = petData.exp,
            maxLevel = petData.max_level,
            unlockedEnchantSlots = petData.unlocked_enchant_slots or 0,
            maxEnchantments = petData.max_enchantments or 0,
        }
end

function PetProgressionService:_getBreakableDestroyBaseXp(context)
    local sources = self._config.xp_sources or {}
    local destroy = sources.breakable_destroy or {}
    if destroy.enabled ~= true then
        return 0
    end

    context = type(context) == "table" and context or {}
    local byBreakable = destroy.xp_by_breakable or {}
    local breakableId = context.breakableId or context.crystalName
    local xp = breakableId and byBreakable[breakableId] or nil
    if xp == nil then
        local byWorld = destroy.xp_by_world or destroy.xp_by_area or {}
        xp = context.world and byWorld[context.world] or nil
    end
    if xp == nil then
        xp = destroy.default_xp
    end
    return math.max(0, math.floor(tonumber(xp) or 0))
end

function PetProgressionService:_resolveXpAmount(player, baseXp, context)
    baseXp = math.max(0, math.floor(tonumber(baseXp) or 0))
    if baseXp <= 0 then
        return 0
    end
    if not self._modifierService or not self._modifierService.Resolve then
        return baseXp
    end

    local modifierContext = type(context) == "table" and table.clone(context) or {}
    modifierContext.player = player
    modifierContext.kind = "pet_xp"
    modifierContext.source = modifierContext.source or "PetProgressionService"

    local resolved = self._modifierService:Resolve(baseXp, modifierContext)
    return math.max(0, math.floor(tonumber(resolved) or baseXp))
end

function PetProgressionService:GetEquippedUniquePetUids(player)
    local data = self._dataService:GetData(player)
    local equipped = data and data.Equipped and data.Equipped.pets
    local items = data and data.Inventory and data.Inventory.pets and data.Inventory.pets.items
    if type(equipped) ~= "table" or type(items) ~= "table" then
        return {}
    end

    local uids = {}
    for _, uid in pairs(equipped) do
        if type(uid) == "string" and not string.match(uid, "^stack|") then
            local petData = items[uid]
            if type(petData) == "table" and petData._kind == "special" then
                table.insert(uids, uid)
            end
        end
    end
    return uids
end

function PetProgressionService:AwardBreakableDestroyed(player, context)
    if not self:IsEnabled() or not player then
        return {
            ok = false,
            reason = "pet_progression_disabled",
        }
    end

    local baseXp = self:_getBreakableDestroyBaseXp(context)
    local xp = self:_resolveXpAmount(player, baseXp, context)
    if xp <= 0 then
        return {
            ok = true,
            xp = 0,
            awarded = 0,
        }
    end

    local awarded = 0
    local results = {}
    for _, uid in ipairs(self:GetEquippedUniquePetUids(player)) do
        local ok, result = self:AddPetExperience(player, uid, xp, "breakable_destroy")
        if ok then
            awarded += 1
            results[uid] = result
        end
    end

    return {
        ok = true,
        xp = xp,
        baseXp = baseXp,
        awarded = awarded,
        results = results,
    }
end

return PetProgressionService
