-- Currency Configuration
-- Define all available currencies in the game

return {
    {
        id = "coins",
        name = "Coins",
        description = "Primary currency earned through gameplay",
        maxAmount = 999999999,
        defaultAmount = 100,
        icon = "💰",
    },

    {
        id = "gems",
        name = "Gems",
        description = "Premium currency purchased or earned through special rewards",
        maxAmount = 999999,
        defaultAmount = 0,
        icon = "💎",
    },

    {
        id = "crystals",
        name = "Crystals",
        description = "Rare currency found in dungeons and special events",
        maxAmount = 50000,
        defaultAmount = 0,
        icon = "🔮",
    },

    -- Halo & Horns themed currencies (Feature 4). Per-biome coins + Heaven/Hell
    -- tokens. All non-tradeable (see configs/biomes.lua + configs/layers.lua).
    {
        id = "grass_coins",
        name = "Grass Coins",
        description = "Grass (earth) biome currency",
        maxAmount = 999999999,
        defaultAmount = 100,
        icon = "🌿",
        tradeable = false,
    }, -- 100 starter grant: funds the first EarthEgg hatch before mining
    {
        id = "ice_coins",
        name = "Ice Coins",
        description = "Ice biome currency",
        maxAmount = 999999999,
        defaultAmount = 0,
        icon = "🧊",
        tradeable = false,
    },
    {
        id = "lava_coins",
        name = "Lava Coins",
        description = "Lava biome currency",
        maxAmount = 999999999,
        defaultAmount = 0,
        icon = "🌋",
        tradeable = false,
    },
    {
        id = "desert_coins",
        name = "Desert Coins",
        description = "Desert biome currency",
        maxAmount = 999999999,
        defaultAmount = 0,
        icon = "🏜️",
        tradeable = false,
    },
    {
        id = "beach_coins",
        name = "Beach Coins",
        description = "Beach biome currency",
        maxAmount = 999999999,
        defaultAmount = 0,
        icon = "🏖️",
        tradeable = false,
    },
    {
        id = "light_tokens",
        name = "Light Tokens",
        description = "Heaven layer token (Halo)",
        maxAmount = 999999,
        defaultAmount = 0,
        icon = "😇",
        tradeable = false,
    },
    {
        id = "shadow_tokens",
        name = "Shadow Tokens",
        description = "Hell layer token (Horns)",
        maxAmount = 999999,
        defaultAmount = 0,
        icon = "😈",
        tradeable = false,
    },
}
