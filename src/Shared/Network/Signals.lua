local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wally packages are placed in ReplicatedStorage.Packages by our Rojo project file
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Net = require(Packages:WaitForChild("Net"))

-- Central registry of RemoteEvents used by client/server
local Signals = {
    -- Economy core
    PurchaseItem      = Net:RemoteEvent("PurchaseItem"),    -- c->s
    PurchaseResult    = Net:RemoteEvent("PurchaseResult"),   -- s->c (success/fail text)
    AdjustCurrency    = Net:RemoteEvent("AdjustCurrency"),   -- c->s
    CurrencyUpdate    = Net:RemoteEvent("CurrencyUpdate"),   -- s->c

    -- Legacy-bridge replacements
    PurchaseSuccess   = Net:RemoteEvent("PurchaseSuccess"),  -- s->c UI toast
    SellSuccess       = Net:RemoteEvent("SellSuccess"),      -- s->c
    ShopItems         = Net:RemoteEvent("ShopItems"),        -- s->c
    PlayerDebugInfo   = Net:RemoteEvent("PlayerDebugInfo"),  -- s->c
    GiveItemSuccess   = Net:RemoteEvent("GiveItemSuccess"),  -- s->c
    EconomyError      = Net:RemoteEvent("EconomyError"),     -- s->c error message

    -- Effects
    ActiveEffects     = Net:RemoteEvent("ActiveEffects"),    -- s->c unified list

    -- Monetization
    InitiatePurchase  = Net:RemoteEvent("InitiatePurchase"),   -- c->s
    GetOwnedPasses    = Net:RemoteEvent("GetOwnedPasses"),     -- c->s
    GetProductInfo    = Net:RemoteEvent("GetProductInfo"),     -- c->s
    PurchaseError     = Net:RemoteEvent("PurchaseError"),      -- s->c
    OwnedPasses       = Net:RemoteEvent("OwnedPasses"),        -- s->c
    ProductInfo       = Net:RemoteEvent("ProductInfo"),        -- s->c
    FirstPurchaseBonus = Net:RemoteEvent("FirstPurchaseBonus"), -- s->c

    -- Diagnostics
    RunDiagnostics    = Net:RemoteEvent("RunDiagnostics"),      -- c->s request & s->c reply
    
    -- Inventory Management
    DeleteInventoryItem = Net:RemoteEvent("DeleteInventoryItem"), -- c->s delete single item
    CleanupInventory   = Net:RemoteEvent("CleanupInventory"),    -- c->s admin cleanup
    FixItemCategories  = Net:RemoteEvent("FixItemCategories"),   -- c->s admin category migration
    CleanOrphanedBuckets = Net:RemoteEvent("CleanOrphanedBuckets"), -- c->s admin orphaned bucket cleanup
    InventoryUpdate    = Net:RemoteEvent("InventoryUpdate"),     -- s->c inventory changed
    ConsumeItem        = Net:RemoteEvent("ConsumeItem"),         -- c->s consume consumable
    TogglePetEquipped  = Net:RemoteEvent("TogglePetEquipped"),   -- c->s equip/unequip pet
    ToggleToolEquipped = Net:RemoteEvent("ToggleToolEquipped"),  -- c->s equip/unequip tool
    
    -- User Display Preferences
    SaveDisplayPreferences = Net:RemoteEvent("SaveDisplayPreferences"), -- c->s save user display preferences
}

return Signals