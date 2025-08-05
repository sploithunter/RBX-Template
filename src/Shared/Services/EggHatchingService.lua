-- EggHatchingService.lua
--
-- Scalable egg hatching animation system that handles 1-99+ eggs with dynamic grid layouts.
-- Uses image-based animations for optimal performance and consistent visual experience.
--
-- FEATURES:
-- - Dynamic grid positioning (1x1, 2x1, 2x2, 3x3, 4x4, 5x5, etc.)
-- - Multi-stage animations: shake -> flash -> reveal
-- - Performance optimized with image assets
-- - Scales to 99+ eggs with overflow handling
-- - Cinematic screen clearing: UI elements animate off-screen directionally
-- 
-- ANIMATION STAGES:
-- 1. SCREEN CLEAR: All UI elements animate off-screen in natural directions
-- 2. SHAKE: Egg wobbles back and forth on clean screen
-- 3. FLASH: Bright flash/explosion effect 
-- 4. REVEAL: Pet image appears with scale/fade effect
-- 5. SCREEN RESTORE: All UI elements animate back to original positions

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Locations = require(ReplicatedStorage.Shared.Locations)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local EggHatchingService = {}
EggHatchingService.__index = EggHatchingService

-- Persistent GUI that gets created once and reused
EggHatchingService._persistentGui = nil
EggHatchingService._persistentContainer = nil

-- ═══════════════════════════════════════════════════════════════════════════════════
-- CINEMATIC SCREEN MANAGEMENT SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════════

function EggHatchingService:ClearScreen()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local animatedGUIs = {}
    
    print("🎬 Clearing screen for cinematic egg hatching...")
    
    -- Simple approach: Just fade out entire ScreenGuis (not individual elements)
    for _, gui in pairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name ~= "EggHatchingGui" and gui.Enabled then
            -- Store original enabled state
            table.insert(animatedGUIs, {
                gui = gui,
                originalEnabled = gui.Enabled
            })
            
            -- Simply disable the GUI (much safer than complex animations)
            gui.Enabled = false
        end
    end
    
    print("🎭 Disabled", #animatedGUIs, "ScreenGuis for cinematic mode")
    
    -- No wait needed since this is instant
    return animatedGUIs
end

function EggHatchingService:RestoreScreen(animatedElements)
    if not animatedElements or #animatedElements == 0 then
        print("⚠️ No animated elements to restore")
        return
    end
    
    print("🎬 Restoring screen UI elements...")
    
    -- Simply re-enable the GUIs
    for _, guiData in pairs(animatedElements) do
        local gui = guiData.gui
        
        -- Check if GUI still exists and restore its enabled state
        if gui and gui.Parent then
            gui.Enabled = guiData.originalEnabled
        end
    end
    
    print("✨ Screen restoration complete!")
    
    -- No wait needed since this is instant
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- DYNAMIC GRID LAYOUT SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════════

local GRID_LAYOUTS = {
    {columns = 1, rows = 1, minItems = 1, maxItems = 1, name = "1x1"},
    {columns = 2, rows = 1, minItems = 2, maxItems = 2, name = "2x1"},
    {columns = 2, rows = 2, minItems = 3, maxItems = 4, name = "2x2"},
    {columns = 3, rows = 2, minItems = 5, maxItems = 6, name = "3x2"},
    {columns = 3, rows = 3, minItems = 7, maxItems = 9, name = "3x3"},
    {columns = 4, rows = 3, minItems = 10, maxItems = 12, name = "4x3"},
    {columns = 4, rows = 4, minItems = 13, maxItems = 16, name = "4x4"},
    {columns = 5, rows = 4, minItems = 17, maxItems = 20, name = "5x4"},
    {columns = 5, rows = 5, minItems = 21, maxItems = 25, name = "5x5"},
    {columns = 6, rows = 5, minItems = 26, maxItems = 30, name = "6x5"},
    {columns = 6, rows = 6, minItems = 31, maxItems = 36, name = "6x6"},
    {columns = 7, rows = 6, minItems = 37, maxItems = 42, name = "7x6"},
    {columns = 7, rows = 7, minItems = 43, maxItems = 49, name = "7x7"},
    {columns = 8, rows = 7, minItems = 50, maxItems = 56, name = "8x7"},
    {columns = 8, rows = 8, minItems = 57, maxItems = 64, name = "8x8"},
    {columns = 9, rows = 8, minItems = 65, maxItems = 72, name = "9x8"},
    {columns = 9, rows = 9, minItems = 73, maxItems = 81, name = "9x9"},
    {columns = 10, rows = 9, minItems = 82, maxItems = 90, name = "10x9"},
    {columns = 10, rows = 10, minItems = 91, maxItems = 100, name = "10x10"},
}

-- Calculate optimal grid layout for given number of eggs
function EggHatchingService:CalculateGridLayout(eggCount, containerWidth, containerHeight)
    -- Find the best fitting grid layout
    local layout = nil
    for _, gridLayout in ipairs(GRID_LAYOUTS) do
        if eggCount >= gridLayout.minItems and eggCount <= gridLayout.maxItems then
            layout = gridLayout
            break
        end
    end
    
    -- Fallback to largest grid if we exceed maximum
    if not layout then
        layout = GRID_LAYOUTS[#GRID_LAYOUTS]
        warn("Egg count exceeds maximum grid size. Using largest available grid:", layout.name)
    end
    
    -- Calculate cell dimensions
    local padding = 20 -- Space between eggs
    local availableWidth = containerWidth - (padding * (layout.columns + 1))
    local availableHeight = containerHeight - (padding * (layout.rows + 1))
    
    local cellWidth = availableWidth / layout.columns
    local cellHeight = availableHeight / layout.rows
    
    -- Keep eggs square (use smaller dimension)
    local eggSize = math.min(cellWidth, cellHeight)
    
    -- Enforce minimum and maximum egg sizes for visibility
    local minEggSize = 100  -- Minimum 100 pixels
    local maxEggSize = 300  -- Maximum 300 pixels
    local originalEggSize = eggSize
    eggSize = math.max(minEggSize, math.min(maxEggSize, eggSize))
    
    print("🔢 SIZE CALCULATION TRACE:")
    print("  📊 Container:", containerWidth .. "x" .. containerHeight)
    print("  📐 Available space:", availableWidth .. "x" .. availableHeight) 
    print("  📏 Cell size:", cellWidth .. "x" .. cellHeight)
    print("  🥚 Original egg size:", originalEggSize)
    print("  ✅ Final egg size:", eggSize, "(min:", minEggSize, "max:", maxEggSize .. ")")
    
    -- Calculate starting position to center the grid
    local gridWidth = (eggSize * layout.columns) + (padding * (layout.columns - 1))
    local gridHeight = (eggSize * layout.rows) + (padding * (layout.rows - 1))
    local startX = (containerWidth - gridWidth) / 2
    local startY = (containerHeight - gridHeight) / 2
    
    return {
        layout = layout,
        eggSize = eggSize,
        startX = startX,
        startY = startY,
        padding = padding,
        totalWidth = gridWidth,
        totalHeight = gridHeight
    }
end

-- Generate positions for all eggs in the grid
function EggHatchingService:GenerateEggPositions(eggCount, gridInfo)
    local positions = {}
    local layout = gridInfo.layout
    
    for i = 1, math.min(eggCount, layout.maxItems) do
        -- Convert linear index to grid coordinates (0-based)
        local gridIndex = i - 1
        local col = gridIndex % layout.columns
        local row = math.floor(gridIndex / layout.columns)
        
        -- Calculate pixel position
        local x = gridInfo.startX + (col * (gridInfo.eggSize + gridInfo.padding))
        local y = gridInfo.startY + (row * (gridInfo.eggSize + gridInfo.padding))
        
        table.insert(positions, {
            x = x,
            y = y,
            size = gridInfo.eggSize,
            gridCol = col,
            gridRow = row,
            index = i
        })
    end
    
    return positions
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- ANIMATION SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════════

-- Animation states
local ANIMATION_STATE = {
    IDLE = "idle",
    SHAKE = "shake", 
    FLASH = "flash",
    REVEAL = "reveal",
    COMPLETE = "complete"
}

function EggHatchingService:CreateEggFrame(position, eggData)
    local frame = Instance.new("Frame")
    frame.Name = "EggFrame_" .. position.index
    frame.Size = UDim2.new(0, position.size, 0, position.size)
    frame.Position = UDim2.new(0, position.x, 0, position.y)
    frame.BackgroundTransparency = 1  -- Transparent
    frame.BorderSizePixel = 0
    
    print("🖼️ Creating egg frame at position:", position.x, position.y, "| Size:", position.size)
    print("📏 Frame UDim2 size:", frame.Size.X.Scale, frame.Size.X.Offset, frame.Size.Y.Scale, frame.Size.Y.Offset)
    print("📍 Frame UDim2 position:", frame.Position.X.Scale, frame.Position.X.Offset, frame.Position.Y.Scale, frame.Position.Y.Offset)
    
    -- Egg image - use the generated ViewportFrames from asset generation system
    local eggImage = nil
    
    if eggData.imageId == "generated_image" then
        -- Get the actual generated ViewportFrame (same as inventory/egg preview)
        eggImage = self:GetGeneratedEggViewport(eggData.eggType or "basic_egg")
        if eggImage then
            print("🖼️ Using generated ViewportFrame for:", eggData.eggType)
        else
            print("⚠️ No generated ViewportFrame found, using fallback")
        end
    end
    
    -- Fallback if no generated image available
    if not eggImage then
        eggImage = Instance.new("ImageLabel")
        eggImage.Image = eggData.imageId or "rbxasset://textures/face.png"
        print("🖼️ Using fallback ImageLabel:", eggImage.Image)
    end
    
    eggImage.Name = "EggImage"
    eggImage.Size = UDim2.new(1, 0, 1, 0)
    eggImage.Position = UDim2.new(0, 0, 0, 0)
    eggImage.BackgroundTransparency = 1
    eggImage.BorderSizePixel = 0
    print("🖼️ Created egg image element:", eggImage.ClassName)
    
    eggImage.Parent = frame
    
    -- Remove the timing-sensitive debug from here - will be done after parenting
    
    -- Flash effect (initially hidden)
    local flashEffect = Instance.new("Frame")
    flashEffect.Name = "FlashEffect"
    flashEffect.Size = UDim2.new(1.2, 0, 1.2, 0)
    flashEffect.Position = UDim2.new(-0.1, 0, -0.1, 0)
    flashEffect.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    flashEffect.BorderSizePixel = 0
    flashEffect.BackgroundTransparency = 1
    flashEffect.Parent = frame
    
    -- Pet reveal (initially hidden)
    local petReveal = Instance.new("ImageLabel")
    petReveal.Name = "PetReveal"
    petReveal.Size = UDim2.new(0.8, 0, 0.8, 0)
    petReveal.Position = UDim2.new(0.1, 0, 0.1, 0)
    petReveal.BackgroundTransparency = 1
    petReveal.BackgroundColor3 = Color3.fromRGB(255, 255, 255)  -- Set to white (will be transparent)
    petReveal.BorderSizePixel = 0
    petReveal.ImageTransparency = 1
    petReveal.Image = "" -- Will be set when revealing
    petReveal.Parent = frame
    
    -- Ensure the parent frame has a transparent background for the reveal
    frame.BackgroundTransparency = 1
    
    return frame, {
        egg = eggImage,
        flash = flashEffect,
        reveal = petReveal,
        state = ANIMATION_STATE.IDLE
    }
end

-- Shake animation (egg wobbles)
function EggHatchingService:AnimateShake(eggComponents, duration)
    duration = duration or 2.0
    local eggImage = eggComponents.egg
    
    -- DEBUG: Log detailed size information during shake
    print("🔍 SHAKE DEBUG START:")
    print("  📏 EggImage AbsoluteSize:", eggImage.AbsoluteSize.X .. "x" .. eggImage.AbsoluteSize.Y)
    print("  📏 EggImage Size UDim2:", eggImage.Size.X.Scale, eggImage.Size.X.Offset, eggImage.Size.Y.Scale, eggImage.Size.Y.Offset)
    print("  📍 EggImage AbsolutePosition:", eggImage.AbsolutePosition.X .. "," .. eggImage.AbsolutePosition.Y)
    print("  📍 EggImage Position UDim2:", eggImage.Position.X.Scale, eggImage.Position.X.Offset, eggImage.Position.Y.Scale, eggImage.Position.Y.Offset)
    print("  🏠 Parent AbsoluteSize:", eggImage.Parent.AbsoluteSize.X .. "x" .. eggImage.Parent.AbsoluteSize.Y)
    print("  🏠 Parent Size UDim2:", eggImage.Parent.Size.X.Scale, eggImage.Parent.Size.X.Offset, eggImage.Parent.Size.Y.Scale, eggImage.Parent.Size.Y.Offset)
    print("  🔍 EggImage ClassName:", eggImage.ClassName)
    
    eggComponents.state = ANIMATION_STATE.SHAKE
    
    -- Create wobble animation
    local shakeInfo = TweenInfo.new(
        0.1, -- Short duration for each shake
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.InOut,
        -1, -- Infinite repeats (until stopped)
        true -- Reverse
    )
    
    local leftShake = TweenService:Create(eggImage, shakeInfo, {
        Rotation = -5
    })
    
    local rightShake = TweenService:Create(eggImage, shakeInfo, {
        Rotation = 5
    })
    
    -- Start shaking
    leftShake:Play()
    
    -- EXTENDED DEBUG: Check size every 10 seconds during shake
    local startTime = tick()
    task.spawn(function()
        while tick() - startTime < duration do
            task.wait(10)
            local elapsed = tick() - startTime
            print("🔍 SHAKE SIZE CHECK @", math.floor(elapsed), "s:")
            print("  📏 Current AbsoluteSize:", eggImage.AbsoluteSize.X .. "x" .. eggImage.AbsoluteSize.Y)
            print("  📍 Current AbsolutePosition:", eggImage.AbsolutePosition.X .. "," .. eggImage.AbsolutePosition.Y)
            print("  🔄 Current Rotation:", eggImage.Rotation)
        end
    end)
    
    -- Stop after duration and proceed to flash
    task.wait(duration)
    leftShake:Cancel()
    rightShake:Cancel()
    
    -- Reset rotation
    eggImage.Rotation = 0
    
    return true
end

-- Flash animation (bright explosion effect)
function EggHatchingService:AnimateFlash(eggComponents, duration)
    duration = duration or 0.5
    local flashEffect = eggComponents.flash
    local eggImage = eggComponents.egg
    
    eggComponents.state = ANIMATION_STATE.FLASH
    
    -- Flash in
    local flashIn = TweenService:Create(flashEffect, TweenInfo.new(0.1), {
        BackgroundTransparency = 0
    })
    
    -- Flash out
    local flashOut = TweenService:Create(flashEffect, TweenInfo.new(0.4), {
        BackgroundTransparency = 1
    })
    
    -- Hide egg during flash
    local hideEgg = TweenService:Create(eggImage, TweenInfo.new(0.1), {
        ImageTransparency = 1
    })
    
    -- Execute flash sequence
    flashIn:Play()
    hideEgg:Play()
    
    task.wait(0.1)
    flashOut:Play()
    
    task.wait(0.4)
    
    return true
end

-- Reveal animation (pet appears with effects)
function EggHatchingService:AnimateReveal(eggComponents, petImageId, petData, duration)
    duration = duration or 1.0
    
    print("🎭 REVEAL DEBUG START:")
    print("  📊 petImageId:", petImageId)
    print("  📊 petData:", petData and "EXISTS" or "NIL")
    if petData then
        print("  📊 petData.petType:", petData.petType)
        print("  📊 petData.variant:", petData.variant)
    end
    print("  📊 duration:", duration)
    print("  📊 eggComponents.reveal exists:", eggComponents.reveal ~= nil)
    if eggComponents.reveal then
        print("  📊 eggComponents.reveal.ClassName:", eggComponents.reveal.ClassName)
        print("  📊 eggComponents.reveal.Name:", eggComponents.reveal.Name)
    end
    
    local petReveal = eggComponents.reveal
    
    eggComponents.state = ANIMATION_STATE.REVEAL
    
    -- Handle generated images vs regular asset IDs
    if petImageId == "generated_image" and petData then
        print("  🔄 Using generated image path")
        -- Try to get generated pet image
        local generatedImage = self:GetGeneratedPetImage(petData.petType, petData.variant)
        print("  📊 generatedImage found:", generatedImage ~= nil)
        if generatedImage then
            print("  📊 generatedImage.ClassName:", generatedImage.ClassName)
            print("  📊 generatedImage.Name:", generatedImage.Name)
            
            -- Store parent before destroying
            local parent = petReveal.Parent
            print("  📊 Parent before destroy:", parent and parent.Name or "NIL")
            
            -- Replace the ImageLabel with the generated ViewportFrame
            petReveal:Destroy()
            print("  ✅ Original petReveal destroyed")
            
            petReveal = generatedImage:Clone()
            petReveal.Name = "PetReveal"
            petReveal.BackgroundTransparency = 1  -- Ensure ViewportFrame is transparent
            petReveal.BackgroundColor3 = Color3.fromRGB(255, 255, 255)  -- Set to white (will be transparent)
            petReveal.Parent = parent
            eggComponents.reveal = petReveal
            print("  ✅ New petReveal created and parented with transparency")
            print("  📊 petReveal.ClassName:", petReveal.ClassName)
            print("  📊 petReveal.BackgroundTransparency:", petReveal.BackgroundTransparency)
            print("  📊 petReveal.BackgroundColor3:", tostring(petReveal.BackgroundColor3))
        else
            print("  ❌ Failed to get generated pet image!")
        end
    else
        print("  🔄 Using regular image path")
        -- Set regular image
        petReveal.Image = petImageId or "rbxasset://textures/face.png"
        print("  📊 Set Image to:", petReveal.Image)
    end
    
    print("  📊 Final petReveal.ClassName:", petReveal.ClassName)
    print("  📊 Final petReveal.Name:", petReveal.Name)
    print("  📊 Final petReveal.Parent:", petReveal.Parent and petReveal.Parent.Name or "NIL")
    
    -- Give ViewportFrame a moment to render before starting animation
    if petReveal.ClassName == "ViewportFrame" then
        task.wait(0.05)  -- Very short wait for render
    end
    
    -- Ensure transparency is set correctly regardless of element type
    petReveal.BackgroundTransparency = 1
    if petReveal.ClassName == "Frame" then
        print("  📊 Setting Frame BackgroundTransparency to 1")
    elseif petReveal.ClassName == "ViewportFrame" then
        print("  📊 Setting ViewportFrame BackgroundTransparency to 1")
    else
        print("  📊 Setting", petReveal.ClassName, "BackgroundTransparency to 1")
    end
    
    -- Scale and fade in effect
    petReveal.Size = UDim2.new(0.3, 0, 0.3, 0)
    petReveal.Position = UDim2.new(0.35, 0, 0.35, 0)
    print("  📊 Set initial Size:", tostring(petReveal.Size))
    print("  📊 Set initial Position:", tostring(petReveal.Position))
    
    -- Handle transparency for both ImageLabel and ViewportFrame
    local transparencyProperty = "ImageTransparency"
    if petReveal.ClassName == "ViewportFrame" then
        transparencyProperty = "BackgroundTransparency"
        petReveal.BackgroundTransparency = 1
        print("  📊 Using BackgroundTransparency for ViewportFrame")
    else
        petReveal.ImageTransparency = 1
        print("  📊 Using ImageTransparency for ImageLabel")
    end
    
    -- Ensure the reveal element itself has a clear background
    if petReveal.ClassName == "Frame" then
        petReveal.BackgroundTransparency = 1
        print("  📊 Set Frame BackgroundTransparency to 1")
    end
    
    local tweenProperties = {
        Size = UDim2.new(0.8, 0, 0.8, 0),
        Position = UDim2.new(0.1, 0, 0.1, 0)
    }
    -- REMOVED: Don't tween transparency - keep it transparent
    -- tweenProperties[transparencyProperty] = 0
    
    print("  📊 Tween target Size:", tostring(tweenProperties.Size))
    print("  📊 Tween target Position:", tostring(tweenProperties.Position))
    print("  📊 Tween target transparency: KEEPING TRANSPARENT (no tween)")
    
    local revealTween = TweenService:Create(petReveal, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), tweenProperties)
    
    print("  🎬 Starting reveal tween for", duration, "seconds...")
    revealTween:Play()
    
    task.wait(duration)
    
    print("  ✅ Reveal tween complete")
    eggComponents.state = ANIMATION_STATE.COMPLETE
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- CLEANUP UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════════════

function EggHatchingService:InitializePersistentGui()
    if self._persistentGui then
        return -- Already initialized
    end
    
    print("🏗️ Creating persistent egg hatching GUI...")
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggHatchingGui"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 100  -- Ensure it's on top
    screenGui.Enabled = false  -- Start disabled
    
    -- Full-screen transparent container for cinematic effect
    local container = Instance.new("Frame")
    container.Name = "HatchingContainer"
    container.Size = UDim2.new(1, 0, 1, 0)  -- Full screen
    container.Position = UDim2.new(0, 0, 0, 0)  -- Top-left corner
    container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)  -- Pure black background
    container.BackgroundTransparency = 0.8  -- Much more transparent so eggs are visible
    container.BorderSizePixel = 0
    container.Parent = screenGui
    
    screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    
    -- Store references
    self._persistentGui = screenGui
    self._persistentContainer = container
    
    print("✅ Persistent egg hatching GUI created and ready")
end

function EggHatchingService:CleanupExistingHatchingGUIs()
    -- Remove any old/duplicate GUIs, but not our persistent one
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local cleanedCount = 0
    
    for _, gui in pairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name == "EggHatchingGui" and gui ~= self._persistentGui then
            gui:Destroy()
            cleanedCount = cleanedCount + 1
        end
    end
    
    if cleanedCount > 0 then
        print("🧹 Cleaned up", cleanedCount, "duplicate hatching GUIs")
    end
end

function EggHatchingService:ClearEggFrames()
    if not self._persistentContainer then
        return
    end
    
    -- Remove all existing egg frames from the container
    local removedCount = 0
    for _, child in pairs(self._persistentContainer:GetChildren()) do
        if child.Name:match("EggFrame_") then
            child:Destroy()
            removedCount = removedCount + 1
        end
    end
    
    if removedCount > 0 then
        print("🧹 Cleared", removedCount, "egg frames from persistent container")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- MAIN HATCHING INTERFACE
-- ═══════════════════════════════════════════════════════════════════════════════════

function EggHatchingService:StartHatchingAnimation(eggsData)
    local eggCount = #eggsData
    
    -- PHASE 0: Initialize persistent GUI if needed
    self:InitializePersistentGui()
    self:CleanupExistingHatchingGUIs()
    
    -- PHASE 1: Clear the screen cinematically
    print("🎬 Phase 1: Clearing screen for cinematic experience...")
    local animatedElements = self:ClearScreen()
    
    -- PHASE 2: Clear any existing egg frames and prepare container
    self:ClearEggFrames()
    local container = self._persistentContainer
    
    -- Enable the persistent GUI
    self._persistentGui.Enabled = true
    
    -- Calculate grid layout using proper screen dimensions
    local screenSize = workspace.CurrentCamera.ViewportSize
    local containerSize = Vector2.new(screenSize.X, screenSize.Y)
    
    local gridInfo = self:CalculateGridLayout(eggCount, containerSize.X, containerSize.Y)
    local positions = self:GenerateEggPositions(eggCount, gridInfo)
    
    print("🥚 Phase 2: Starting hatching animation for", eggCount, "eggs using", gridInfo.layout.name, "grid")
    print("📐 Container size:", containerSize.X, "x", containerSize.Y)
    print("🥚 Calculated egg size:", gridInfo.eggSize, "pixels")
    print("📍 First egg position:", positions[1] and (positions[1].x .. ", " .. positions[1].y) or "none")
    
    -- Create egg frames
    local eggFrames = {}
    local eggComponents = {}
    
    for i = 1, math.min(eggCount, #positions) do
        local eggData = eggsData[i]
        local position = positions[i]
        
        local frame, components = self:CreateEggFrame(position, eggData)
        frame.Parent = container
        
        -- Debug after parenting
        task.wait() -- Let positioning take effect
        print("📐 ACTUAL SIZES (after parenting):")
        print("  📦 Frame AbsoluteSize:", frame.AbsoluteSize.X .. "x" .. frame.AbsoluteSize.Y)
        print("  📦 Frame AbsolutePosition:", frame.AbsolutePosition.X .. ", " .. frame.AbsolutePosition.Y)
        print("  🏠 Container AbsoluteSize:", container.AbsoluteSize.X .. "x" .. container.AbsoluteSize.Y)
        print("  🏠 Container AbsolutePosition:", container.AbsolutePosition.X .. ", " .. container.AbsolutePosition.Y)
        
        table.insert(eggFrames, frame)
        table.insert(eggComponents, components)
    end
    
    -- PHASE 3: Execute animations in sequence with staggered timing
    local cleanupResult = {
        frames = eggFrames,
        components = eggComponents,
        gridInfo = gridInfo,
        container = container,
        animatedElements = animatedElements,
        isComplete = false
    }
    
    task.spawn(function()
        self:ExecuteHatchingSequence(eggComponents, eggsData)
        
        -- PHASE 4: After animations complete, wait a moment then restore screen
        task.wait(1) -- Let player enjoy the result
        print("🎬 Phase 4: Restoring screen...")
        self:RestoreScreen(animatedElements)
        
        -- PHASE 5: Auto cleanup after a short delay - just disable the GUI
        task.wait(1) -- Brief pause to see the restoration
        print("🧹 Auto-cleanup: Disabling hatching GUI...")
        self._persistentGui.Enabled = false
        self:ClearEggFrames() -- Clean up egg frames for next use
        print("✅ Auto-cleanup complete - GUI ready for reuse")
        cleanupResult.isComplete = true
    end)
    
    return cleanupResult
end

function EggHatchingService:ExecuteHatchingSequence(eggComponents, eggsData)
    local eggCount = #eggComponents
    
    -- PHASE 1: All eggs shake simultaneously
    print("🔄 Phase 1: Shaking", eggCount, "eggs")
    local shakeCoroutines = {}
    
    for i, components in ipairs(eggComponents) do
        local co = coroutine.create(function()
            self:AnimateShake(components, 2.0)
        end)
        coroutine.resume(co)
        table.insert(shakeCoroutines, co)
    end
    
    -- Wait for all shaking to complete
    task.wait(2.0)
    
    -- PHASE 2: Staggered flash and reveal
    print("💥 Phase 2: Flash and reveal sequence")
    
    for i, components in ipairs(eggComponents) do
        local eggData = eggsData[i]
        
        -- Small delay between each egg (creates wave effect)
        if i > 1 then
            task.wait(0.2)
        end
        
        task.spawn(function()
            -- Flash
            self:AnimateFlash(components, 0.5)
            -- Reveal (pass the full eggData for pet info)
            self:AnimateReveal(components, eggData.petImageId, eggData, 1.0)
            

        end)
    end
    
    -- Wait for all reveals to complete
    task.wait(1.5)
    
    print("✅ Hatching animation sequence complete!")
end



-- ═══════════════════════════════════════════════════════════════════════════════════
-- DEBUG/TESTING FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════════════

-- DEBUG: Create a viewer to inspect egg ViewportFrames
function EggHatchingService:CreateEggViewportDebugger()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    if not player then return end
    
    -- Create debug GUI
    local debugGui = Instance.new("ScreenGui")
    debugGui.Name = "EggViewportDebugger"
    debugGui.ResetOnSpawn = false
    debugGui.Parent = player:WaitForChild("PlayerGui")
    
    -- Main frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "DebugFrame"
    mainFrame.Size = UDim2.new(0, 800, 0, 600)
    mainFrame.Position = UDim2.new(0.5, -400, 0.5, -300)
    mainFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    mainFrame.BorderSizePixel = 2
    mainFrame.BorderColor3 = Color3.fromRGB(255, 255, 255)
    mainFrame.Parent = debugGui
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    title.Text = "EGG VIEWPORT DEBUGGER"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame
    
    -- Egg display area
    local eggContainer = Instance.new("Frame")
    eggContainer.Name = "EggContainer"
    eggContainer.Size = UDim2.new(0.6, 0, 1, -100)
    eggContainer.Position = UDim2.new(0, 10, 0, 50)
    eggContainer.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    eggContainer.BorderSizePixel = 1
    eggContainer.BorderColor3 = Color3.fromRGB(200, 200, 200)
    eggContainer.Parent = mainFrame
    
    -- Info panel
    local infoPanel = Instance.new("Frame")
    infoPanel.Name = "InfoPanel"
    infoPanel.Size = UDim2.new(0.35, -20, 1, -100)
    infoPanel.Position = UDim2.new(0.65, 0, 0, 50)
    infoPanel.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    infoPanel.BorderSizePixel = 1
    infoPanel.BorderColor3 = Color3.fromRGB(200, 200, 200)
    infoPanel.Parent = mainFrame
    
    -- Info text
    local infoText = Instance.new("TextLabel")
    infoText.Name = "InfoText"
    infoText.Size = UDim2.new(1, -10, 1, -10)
    infoText.Position = UDim2.new(0, 5, 0, 5)
    infoText.BackgroundTransparency = 1
    infoText.Text = "Loading egg viewport..."
    infoText.TextColor3 = Color3.fromRGB(255, 255, 255)
    infoText.TextSize = 14
    infoText.TextWrapped = true
    infoText.TextXAlignment = Enum.TextXAlignment.Left
    infoText.TextYAlignment = Enum.TextYAlignment.Top
    infoText.Font = Enum.Font.SourceSans
    infoText.Parent = infoPanel
    
    -- Close button
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 100, 0, 30)
    closeButton.Position = UDim2.new(1, -110, 1, -40)
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    closeButton.Text = "CLOSE"
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextScaled = true
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Parent = mainFrame
    
    closeButton.Activated:Connect(function()
        debugGui:Destroy()
    end)
    
    -- Load and display egg viewports
    task.spawn(function()
        local eggTypes = {"basic_egg", "golden_egg"} -- Add more as needed
        local yOffset = 10
        
        for i, eggType in ipairs(eggTypes) do
            local eggViewport = self:GetGeneratedEggViewport(eggType)
            
            if eggViewport then
                -- Create container for this egg
                local eggFrame = Instance.new("Frame")
                eggFrame.Name = eggType .. "_Frame"
                eggFrame.Size = UDim2.new(1, -20, 0, 200)
                eggFrame.Position = UDim2.new(0, 10, 0, yOffset)
                eggFrame.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
                eggFrame.BorderSizePixel = 1
                eggFrame.BorderColor3 = Color3.fromRGB(255, 255, 255)
                eggFrame.Parent = eggContainer
                
                -- Label
                local label = Instance.new("TextLabel")
                label.Name = "Label"
                label.Size = UDim2.new(1, 0, 0, 30)
                label.Position = UDim2.new(0, 0, 0, 0)
                label.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                label.Text = eggType
                label.TextColor3 = Color3.fromRGB(255, 255, 255)
                label.TextScaled = true
                label.Font = Enum.Font.GothamBold
                label.Parent = eggFrame
                
                -- Display the viewport at different sizes for comparison
                local sizes = {
                    {name = "Small", size = UDim2.new(0, 50, 0, 50)},
                    {name = "Medium", size = UDim2.new(0, 100, 0, 100)},
                    {name = "Large", size = UDim2.new(0, 150, 0, 150)}
                }
                
                for j, sizeData in ipairs(sizes) do
                    local clonedViewport = eggViewport:Clone()
                    clonedViewport.Name = eggType .. "_" .. sizeData.name
                    clonedViewport.Size = sizeData.size
                    clonedViewport.Position = UDim2.new(0, 10 + (j-1) * 160, 0, 35)
                    clonedViewport.Parent = eggFrame
                    
                    -- Size label
                    local sizeLabel = Instance.new("TextLabel")
                    sizeLabel.Size = UDim2.new(0, 150, 0, 20)
                    sizeLabel.Position = UDim2.new(0, 10 + (j-1) * 160, 0, 190)
                    sizeLabel.BackgroundTransparency = 1
                    sizeLabel.Text = sizeData.name .. " (" .. sizeData.size.X.Offset .. "x" .. sizeData.size.Y.Offset .. ")"
                    sizeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                    sizeLabel.TextSize = 12
                    sizeLabel.Font = Enum.Font.SourceSans
                    sizeLabel.Parent = eggFrame
                end
                
                yOffset = yOffset + 220
                
                -- Update info text
                local infoLines = {
                    "EGG TYPE: " .. eggType,
                    "VIEWPORT FOUND: YES",
                    "ORIGINAL SIZE: " .. eggViewport.Size.X.Scale .. "," .. eggViewport.Size.X.Offset .. " | " .. eggViewport.Size.Y.Scale .. "," .. eggViewport.Size.Y.Offset,
                    "",
                    "Compare the different sizes above.",
                    "The egg should be clearly visible.",
                    "If it's tiny in all sizes, the",
                    "camera config needs adjustment.",
                    "",
                    "Check configs/pets.lua:",
                    "- egg_sources['" .. eggType .. "'].camera",
                    "- default_egg_camera settings",
                    "",
                    "Adjust distance, angle_x, angle_y",
                    "to make the egg fill the viewport."
                }
                infoText.Text = table.concat(infoLines, "\n")
                
            else
                -- Show error info
                infoText.Text = "ERROR: No viewport found for " .. eggType .. "\n\nCheck if AssetPreloadService\ngenerated the egg images.\n\nPath should be:\nAssets.Images.Eggs." .. eggType
            end
        end
    end)
    
    print("🔍 Egg Viewport Debugger created! Check your screen.")
    return debugGui
end

function EggHatchingService:TestCleanup()
    -- Force cleanup any existing GUIs for testing
    self:CleanupExistingHatchingGUIs()
    if self._persistentGui then
        self._persistentGui.Enabled = false
        self:ClearEggFrames()
    end
    print("🧪 Test cleanup completed")
end

function EggHatchingService:CheckForLeakedGUIs()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local totalCount = 0
    local persistentCount = 0
    
    for _, gui in pairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name == "EggHatchingGui" then
            totalCount = totalCount + 1
            if gui == self._persistentGui then
                persistentCount = persistentCount + 1
            end
        end
    end
    
    local leakedCount = totalCount - persistentCount
    
    if leakedCount > 0 then
        print("⚠️ Found", leakedCount, "leaked EggHatchingGui instances (should only have 1 persistent)")
    else
        print("✅ Only persistent GUI found - no leaks detected")
    end
    
    print("📊 GUI Status: Total =", totalCount, "| Persistent =", persistentCount, "| Leaks =", leakedCount)
    
    return leakedCount
end

function EggHatchingService:GetPersistentGuiStatus()
    if not self._persistentGui then
        print("❌ No persistent GUI created yet")
        return "not_created"
    elseif self._persistentGui.Enabled then
        print("🟢 Persistent GUI is ENABLED")
        return "enabled"
    else
        print("🔴 Persistent GUI is DISABLED")
        return "disabled"
    end
end

function EggHatchingService:TestVisibility()
    -- Test the GUI visibility with a simple test egg
    self:InitializePersistentGui()
    
    print("🧪 Testing egg visibility...")
    
    -- Enable GUI
    self._persistentGui.Enabled = true
    
    -- Create a test egg frame right in the center
    local screenSize = workspace.CurrentCamera.ViewportSize
    local testFrame = Instance.new("Frame")
    testFrame.Name = "TestEggFrame"
    testFrame.Size = UDim2.new(0, 200, 0, 200)  -- Fixed 200x200 size
    testFrame.Position = UDim2.new(0.5, -100, 0.5, -100)  -- Centered
    testFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 0)  -- Bright yellow
    testFrame.BackgroundTransparency = 0.3
    testFrame.BorderSizePixel = 5
    testFrame.BorderColor3 = Color3.fromRGB(255, 0, 255)  -- Magenta border
    testFrame.Parent = self._persistentContainer
    
    -- Add test text
    local testLabel = Instance.new("TextLabel")
    testLabel.Text = "TEST EGG\nVISIBLE?"
    testLabel.Size = UDim2.new(1, 0, 1, 0)
    testLabel.BackgroundTransparency = 1
    testLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
    testLabel.TextScaled = true
    testLabel.Font = Enum.Font.GothamBold
    testLabel.Parent = testFrame
    
    print("✨ Test egg created - should be bright yellow square in center of screen")
    print("💡 Screen size:", screenSize.X .. "x" .. screenSize.Y)
    print("🎯 Test frame at:", testFrame.AbsolutePosition.X, testFrame.AbsolutePosition.Y)
    
    -- Auto-cleanup after 5 seconds
    task.spawn(function()
        task.wait(5)
        testFrame:Destroy()
        self._persistentGui.Enabled = false
        print("🧹 Test visibility cleanup complete")
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════════════

-- Example usage:
-- local eggsData = {
--     {imageId = "rbxassetid://123", petImageId = "rbxassetid://456"},
--     {imageId = "rbxassetid://789", petImageId = "rbxassetid://012"},
-- }
-- EggHatchingService:StartHatchingAnimation(eggsData)

-- ═══════════════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS FOR GENERATED IMAGES
-- ═══════════════════════════════════════════════════════════════════════════════════

function EggHatchingService:GetGeneratedEggViewport(eggType)
    local success, viewport = pcall(function()
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        if assetsFolder then
            local imagesFolder = assetsFolder:FindFirstChild("Images")
            if imagesFolder then
                local eggsFolder = imagesFolder:FindFirstChild("Eggs")
                if eggsFolder then
                    local eggViewport = eggsFolder:FindFirstChild(eggType)
                    if eggViewport and eggViewport:IsA("ViewportFrame") then
                        -- Clone the ViewportFrame (same as inventory/egg preview)
                        return eggViewport:Clone()
                    end
                end
            end
        end
        return nil
    end)
    
    return success and viewport or nil
end

-- Note: Bear debug function removed - no longer needed

function EggHatchingService:GetGeneratedPetImage(petType, variant)
    local success, image = pcall(function()
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        if assetsFolder then
            local imagesFolder = assetsFolder:FindFirstChild("Images")
            if imagesFolder then
                local petsFolder = imagesFolder:FindFirstChild("Pets")
                if petsFolder then
                    local petTypeFolder = petsFolder:FindFirstChild(petType)
                    if petTypeFolder then
                        local petImage = petTypeFolder:FindFirstChild(variant)
                        if petImage then
                            return petImage:Clone() -- Clone the generated ViewportFrame
                        end
                    end
                end
            end
        end
        return nil
    end)
    
    return success and image or nil
end

-- Auto-initialize the persistent GUI when the service is required
-- QUICK ACCESS: Debug egg viewports
function EggHatchingService:DebugEggViewports()
    return self:CreateEggViewportDebugger()
end

task.spawn(function()
    task.wait(1) -- Wait a moment for PlayerGui to be ready
    local service = EggHatchingService
    if Players.LocalPlayer then
        service:InitializePersistentGui()
    end
end)

return EggHatchingService