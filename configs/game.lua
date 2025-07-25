-- Game Configuration
-- Main game settings and parameters
return {
    GameMode = "Simulator", -- Options: Simulator, FPS, TowerDefense, Custom
    MaxPlayers = 20,
    EnableTrading = true,
    EnablePvP = false,
    RespawnTime = 5,
    
    -- Simulator specific settings
    SimulatorSettings = {
        BaseClickPower = 1,
        MaxRebirths = 100,
        RebirthMultiplier = 2,
        AutoClickers = {
            maxOwned = 10,
            basePrice = 100,
            priceMultiplier = 1.5
        }
    },
    
    -- FPS specific settings  
    FPSSettings = {
        RoundTime = 300,
        MaxKills = 30,
        WeaponRespawnTime = 10,
        TeamBalance = true
    },
    
    -- Tower Defense specific settings
    TowerDefenseSettings = {
        StartingLives = 20,
        StartingMoney = 500,
        WaveCount = 50,
        DifficultyMultiplier = 1.1
    },
    
    -- World settings
    WorldSettings = {
        Gravity = 196.2,
        WalkSpeed = 16,
        JumpPower = 50
    }
} 