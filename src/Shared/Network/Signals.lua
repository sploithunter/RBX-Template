local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wally packages are placed in ReplicatedStorage.Packages by our Rojo project file
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Net = require(Packages:WaitForChild("Net"))

-- Central registry of RemoteEvents used by client/server
local Signals = {
    -- Economy core
    PurchaseItem = Net:RemoteEvent("PurchaseItem"), -- c->s
    SellItem = Net:RemoteEvent("SellItem"), -- c->s
    PurchaseResult = Net:RemoteEvent("PurchaseResult"), -- s->c (success/fail text)
    AdjustCurrency = Net:RemoteEvent("AdjustCurrency"), -- c->s
    ConvertCurrency = Net:RemoteEvent("ConvertCurrency"), -- c->s exchange configured currencies
    CurrencyUpdate = Net:RemoteEvent("CurrencyUpdate"), -- s->c
    PurchaseUpgrade = Net:RemoteEvent("PurchaseUpgrade"), -- c->s
    UpgradeResult = Net:RemoteEvent("UpgradeResult"), -- s->c

    -- Legacy-bridge replacements
    PurchaseSuccess = Net:RemoteEvent("PurchaseSuccess"), -- s->c UI toast
    SellSuccess = Net:RemoteEvent("SellSuccess"), -- s->c
    ShopItems = Net:RemoteEvent("ShopItems"), -- s->c
    PlayerDebugInfo = Net:RemoteEvent("PlayerDebugInfo"), -- s->c
    GiveItemSuccess = Net:RemoteEvent("GiveItemSuccess"), -- s->c
    EconomyError = Net:RemoteEvent("EconomyError"), -- s->c error message
    Admin_GetPlayerSnapshot = Net:RemoteEvent("Admin_GetPlayerSnapshot"), -- c->s admin player state request
    Admin_ForceSave = Net:RemoteEvent("Admin_ForceSave"), -- c->s admin force save
    Admin_GrantPet = Net:RemoteEvent("Admin_GrantPet"), -- c->s admin grant configured pet
    Admin_SetZoneLock = Net:RemoteEvent("Admin_SetZoneLock"), -- c->s admin lock/unlock configured zone
    Admin_SetHatchEntitlement = Net:RemoteEvent("Admin_SetHatchEntitlement"), -- c->s admin hatch unlock/testing stubs
    Admin_EventCommand = Net:RemoteEvent("Admin_EventCommand"), -- c->s admin global event command
    AdminToolResult = Net:RemoteEvent("AdminToolResult"), -- s->c admin action result

    -- Effects
    ActiveEffects = Net:RemoteEvent("ActiveEffects"), -- s->c unified list

    -- Monetization
    InitiatePurchase = Net:RemoteEvent("InitiatePurchase"), -- c->s
    GetOwnedPasses = Net:RemoteEvent("GetOwnedPasses"), -- c->s
    GetProductInfo = Net:RemoteEvent("GetProductInfo"), -- c->s
    PurchaseError = Net:RemoteEvent("PurchaseError"), -- s->c
    OwnedPasses = Net:RemoteEvent("OwnedPasses"), -- s->c
    ProductInfo = Net:RemoteEvent("ProductInfo"), -- s->c
    FirstPurchaseBonus = Net:RemoteEvent("FirstPurchaseBonus"), -- s->c

    -- Diagnostics
    RunDiagnostics = Net:RemoteEvent("RunDiagnostics"), -- c->s request & s->c reply

    -- Inventory Management
    DeleteInventoryItem = Net:RemoteEvent("DeleteInventoryItem"), -- c->s delete single item
    CleanupInventory = Net:RemoteEvent("CleanupInventory"), -- c->s admin cleanup
    FixItemCategories = Net:RemoteEvent("FixItemCategories"), -- c->s admin category migration
    CleanOrphanedBuckets = Net:RemoteEvent("CleanOrphanedBuckets"), -- c->s admin orphaned bucket cleanup
    InventoryUpdate = Net:RemoteEvent("InventoryUpdate"), -- s->c inventory changed
    ConsumeItem = Net:RemoteEvent("ConsumeItem"), -- c->s consume consumable
    TogglePetEquipped = Net:RemoteEvent("TogglePetEquipped"), -- c->s equip/unequip pet
    ToggleToolEquipped = Net:RemoteEvent("ToggleToolEquipped"), -- c->s equip/unequip tool
    EnchantPetRequest = Net:RemoteEvent("EnchantPetRequest"), -- c->s reroll/apply pet enchant
    EnchantPetResult = Net:RemoteEvent("EnchantPetResult"), -- s->c enchant action result
    EnchantStationOpened = Net:RemoteEvent("EnchantStationOpened"), -- s->c player activated map enchanter

    -- User Display Preferences
    SaveDisplayPreferences = Net:RemoteEvent("SaveDisplayPreferences"),
    ForceRegenerateAssets = Net:RemoteEvent("ForceRegenerateAssets"), -- c->s admin force asset regeneration

    -- Breakables
    Breakables_Attack = Net:RemoteEvent("Breakables_Attack"), -- c->s attack a crystal by BreakableID

    -- Zones / progression
    UnlockZoneRequest = Net:RemoteEvent("UnlockZoneRequest"), -- c->s
    ZoneUnlockResult = Net:RemoteEvent("ZoneUnlockResult"), -- s->c
    ZoneTravelResult = Net:RemoteEvent("ZoneTravelResult"), -- s->c

    -- Phase 3 stats-derived features
    PetIndexUpdated = Net:RemoteEvent("PetIndexUpdated"), -- s->c
    AchievementCompleted = Net:RemoteEvent("AchievementCompleted"), -- s->c
    LeaderboardUpdated = Net:RemoteEvent("LeaderboardUpdated"), -- s->c
    LeaderboardSnapshotRequest = Net:RemoteEvent("LeaderboardSnapshotRequest"), -- c->s

    -- Auto-target toggles
    -- Server validates and flips Player BoolValues (FreeTarget/PaidTarget).
    -- Client UI reflects state via AutoTarget_Status and Player value listeners.
    AutoTarget_ToggleFree = Net:RemoteEvent("AutoTarget_ToggleFree"), -- c->s request toggle free (low) targeting
    AutoTarget_TogglePaid = Net:RemoteEvent("AutoTarget_TogglePaid"), -- c->s request toggle paid (high) targeting
    AutoTarget_SetMode = Net:RemoteEvent("AutoTarget_SetMode"), -- c->s persist selected target mode
    AutoTarget_RequestAttack = Net:RemoteEvent("AutoTarget_RequestAttack"), -- c->s ask server to select/attack
    AutoDelete_SetFilters = Net:RemoteEvent("AutoDelete_SetFilters"), -- c->s persist hatch auto-delete filters
    AutoTarget_Status = Net:RemoteEvent("AutoTarget_Status"), -- s->c push current auto-target status
}

return Signals
