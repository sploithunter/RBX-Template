local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wally packages are placed in ReplicatedStorage.Packages by our Rojo project file
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Net = require(Packages:WaitForChild("Net"))

local Signals = {
    PurchaseItem   = Net:RemoteEvent("PurchaseItem"),   -- RemoteEvent instance
    PurchaseResult = Net:RemoteEvent("PurchaseResult"), -- RemoteEvent instance
    AdjustCurrency = Net:RemoteEvent("AdjustCurrency"), -- RemoteEvent instance
    CurrencyUpdate = Net:RemoteEvent("CurrencyUpdate"),  -- server -> client currency sync
}

return Signals