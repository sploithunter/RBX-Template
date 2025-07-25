-- Currency Configuration
-- Define all available currencies in the game

return {
  {
    id = "coins",
    name = "Coins",
    description = "Primary currency earned through gameplay",
    maxAmount = 999999999,
    defaultAmount = 100,
    icon = "💰"
  },
  
  {
    id = "gems",
    name = "Gems", 
    description = "Premium currency purchased or earned through special rewards",
    maxAmount = 999999,
    defaultAmount = 0,
    icon = "💎"
  },
  
  {
    id = "crystals",
    name = "Crystals",
    description = "Rare currency found in dungeons and special events",
    maxAmount = 50000,
    defaultAmount = 0,
    icon = "🔮"
  }
} 