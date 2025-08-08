--[[
    GameStructureService - Creates Game Workspace Structure
    
    Creates the complete Workspace.Game structure that the pet system expects:
    - Game.Breakables (Crystals, Gold, Green, Summer, Clicks)
    - Game.Chaseables (Snowman, Hearts)
    
    Each world/type includes:
    - Items folder (for active breakables/chaseables)
    - CurrentItems NumberValue (tracking count)
    - Max NumberValue (maximum allowed)
    - Spawner parts (where items spawn)
--]]

local GameStructureService = {}

-- Define world types and their basic structure
local WORLD_TYPES = {
    "Spawn",      -- Starting area
    "World2",     -- Second area
    "World3",     -- Third area
    "Desert",     -- Desert world
    "Anime",      -- Anime world
    "Mine",       -- Mining world
    "Artic",      -- Arctic world
    "Ancient",    -- Ancient world
    "Magic",      -- Magic world
    "Galaxy",     -- Galaxy world
    "Steampunk",  -- Steampunk world
    "Carnival",   -- Carnival world
    "Swamp",      -- Swamp world
    "CorruptedCity", -- Corrupted City world
    "Blackhole",  -- Blackhole world
    "SpaceLand",  -- Space Land world
}

local EVENT_WORLDS = {
    "Christmas",
    "Christmas2", 
    "Valentine",
    "StPatrick",
    "Easter",
    "CincoDeMayo",
    "PowerMaxBunny",
    "VisitsEvent",
    "E100KEVENT",
    "Summer",
    "Careers",
    "Program"
}

-- Create basic world folder structure
local function createWorldFolder(parent, worldName, includeSpawners)
    includeSpawners = includeSpawners or false
    
    local worldFolder = Instance.new("Folder")
    worldFolder.Name = worldName
    worldFolder.Parent = parent
    
    -- Items folder for active objects
    local itemsFolder = Instance.new("Folder")
    itemsFolder.Name = "Items"
    itemsFolder.Parent = worldFolder
    
    -- Current count tracker
    local currentItems = Instance.new("NumberValue")
    currentItems.Name = "CurrentItems"
    currentItems.Value = 0
    currentItems.Parent = worldFolder
    
    -- Maximum allowed
    local maxItems = Instance.new("NumberValue")
    maxItems.Name = "Max"
    maxItems.Value = 50 -- Default max
    maxItems.Parent = worldFolder
    
    -- Create spawners if requested
    if includeSpawners then
        -- Primary spawner
        local spawner = Instance.new("Part")
        spawner.Name = "Spawner"
        spawner.Anchored = true
        spawner.CanCollide = false
        spawner.Transparency = 1
        spawner.Size = Vector3.new(1, 1, 1)
        spawner.Position = Vector3.new(math.random(-50, 50), 10, math.random(-50, 50))
        spawner.Parent = worldFolder
        
        -- Add attachment for spawner logic
        local attachment = Instance.new("Attachment")
        attachment.Name = "Attachment"
        attachment.Parent = spawner
        
        -- Some worlds have dark spawners too
        if worldName ~= "Spawn" and math.random() > 0.5 then
            local darkSpawner = Instance.new("Part")
            darkSpawner.Name = "DarkSpawner"
            darkSpawner.Anchored = true
            darkSpawner.CanCollide = false
            darkSpawner.Transparency = 1
            darkSpawner.Size = Vector3.new(1, 1, 1)
            darkSpawner.Position = Vector3.new(math.random(-50, 50), 10, math.random(-50, 50))
            darkSpawner.Parent = worldFolder
            
            local darkAttachment = Instance.new("Attachment")
            darkAttachment.Name = "Attachment"
            darkAttachment.Parent = darkSpawner
        end
    end
    
    return worldFolder
end

-- Create the main Game structure
function GameStructureService:CreateGameStructure()
    print("🏗️ GameStructureService: Creating Game structure...")
    
    -- Create main Game folder
    local gameFolder = workspace:FindFirstChild("Game")
    if gameFolder then
        print("🔄 GameStructureService: Game folder already exists, recreating...")
        gameFolder:Destroy()
    end
    
    gameFolder = Instance.new("Folder")
    gameFolder.Name = "Game"
    gameFolder.Parent = workspace
    
    -- === BREAKABLES STRUCTURE ===
    local breakablesFolder = Instance.new("Folder")
    breakablesFolder.Name = "Breakables"
    breakablesFolder.Parent = gameFolder
    
    -- Crystals section
    local crystalsFolder = Instance.new("Folder")
    crystalsFolder.Name = "Crystals"
    crystalsFolder.Parent = breakablesFolder
    
    -- Create crystal worlds
    for _, worldName in ipairs(WORLD_TYPES) do
        if worldName ~= "Steampunk" and worldName ~= "Carnival" then -- These are gold-only in original
            createWorldFolder(crystalsFolder, worldName, true)
        end
    end
    
    -- Add some event crystal worlds
    for _, eventName in ipairs({"Careers", "Program", "Anime", "E100KEVENT"}) do
        createWorldFolder(crystalsFolder, eventName, true)
    end
    
    -- Gold section
    local goldFolder = Instance.new("Folder")
    goldFolder.Name = "Gold"
    goldFolder.Parent = breakablesFolder
    
    -- Create gold worlds (fewer than crystals)
    for _, worldName in ipairs({"World3", "Ancient", "Magic", "Galaxy", "Steampunk", "Carnival", "Swamp", "CorruptedCity", "Blackhole", "SpaceLand"}) do
        local goldWorld = createWorldFolder(goldFolder, worldName, true)
        
        -- Gold spawners have special naming
        local spawner = goldWorld:FindFirstChild("Spawner")
        if spawner then
            spawner.Name = "GoldSpawner"
        end
        
        -- Some gold worlds get max increased
        local maxItems = goldWorld:FindFirstChild("Max")
        if maxItems then
            maxItems.Value = 25 -- Gold is rarer
        end
    end
    
    -- Add gold event worlds
    for _, eventName in ipairs({"PowerMaxBunny", "Easter", "CincoDeMayo", "VisitsEvent"}) do
        createWorldFolder(goldFolder, eventName, false) -- Events don't always have spawners
    end
    
    -- Green section
    local greenFolder = Instance.new("Folder")
    greenFolder.Name = "Green"
    greenFolder.Parent = breakablesFolder
    
    -- Create green worlds (basic ones)
    for _, worldName in ipairs({"Spawn", "World2", "World3", "StPatrick"}) do
        createWorldFolder(greenFolder, worldName, worldName == "Spawn") -- Only spawn gets spawners
    end
    
    -- Summer section
    local summerFolder = Instance.new("Folder")
    summerFolder.Name = "Summer"
    summerFolder.Parent = breakablesFolder
    
    for _, worldName in ipairs({"Spawn", "World2", "World3", "StPatrick"}) do
        createWorldFolder(summerFolder, worldName, worldName == "World3") -- Only World3 gets spawners
    end
    
    -- Clicks section (simple)
    local clicksFolder = Instance.new("Folder")
    clicksFolder.Name = "Clicks"
    clicksFolder.Parent = breakablesFolder
    
    createWorldFolder(clicksFolder, "Spawn", true)
    
    -- === CHASEABLES STRUCTURE ===
    local chaseablesFolder = Instance.new("Folder")
    chaseablesFolder.Name = "Chaseables"
    chaseablesFolder.Parent = gameFolder
    
    -- Snowman section
    local snowmanFolder = Instance.new("Folder")
    snowmanFolder.Name = "Snowman"
    snowmanFolder.Parent = chaseablesFolder
    
    for _, eventName in ipairs({"Christmas", "Christmas2"}) do
        createWorldFolder(snowmanFolder, eventName, false)
    end
    
    -- Hearts section
    local heartsFolder = Instance.new("Folder")
    heartsFolder.Name = "Hearts"
    heartsFolder.Parent = chaseablesFolder
    
    createWorldFolder(heartsFolder, "Valentine", false)
    
    print("✅ GameStructureService: Game structure created successfully!")
    print("📁 Created Breakables: Crystals (" .. #crystalsFolder:GetChildren() .. " worlds), Gold (" .. #goldFolder:GetChildren() .. " worlds), Green (" .. #greenFolder:GetChildren() .. " worlds), Summer (" .. #summerFolder:GetChildren() .. " worlds), Clicks (1 world)")
    print("📁 Created Chaseables: Snowman (" .. #snowmanFolder:GetChildren() .. " worlds), Hearts (" .. #heartsFolder:GetChildren() .. " worlds)")
    
    return gameFolder
end

-- Initialize on server start
function GameStructureService:Initialize()
    print("🚀 GameStructureService: Initializing...")
    
    -- Wait a moment for workspace to be ready
    task.wait(1)
    
    -- Create the structure
    self:CreateGameStructure()
    
    print("✅ GameStructureService: Initialized!")
end

-- Auto-initialize only if no prebuilt structure exists (avoid overwriting Studio-placed spawners)
if not workspace:FindFirstChild("Game") then
    GameStructureService:Initialize()
end

return GameStructureService