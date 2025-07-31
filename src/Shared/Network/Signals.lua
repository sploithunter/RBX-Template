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

    -- Diagnostics
    RunDiagnostics    = Net:RemoteEvent("RunDiagnostics"),      -- c->s request & s->c reply
}

return Signals