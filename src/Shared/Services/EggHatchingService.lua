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
-- 
-- ANIMATION STAGES:
-- 1. SHAKE: Egg wobbles back and forth
-- 2. FLASH: Bright flash/explosion effect 
-- 3. REVEAL: Pet image appears with scale/fade effect

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Locations = require(ReplicatedStorage.Shared.Locations)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local EggHatchingService = {}
EggHatchingService.__index = EggHatchingService

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
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    
    -- Egg image (support both regular images and generated ViewportFrames)
    local eggImage
    if eggData.imageId == "generated_image" then
        -- Try to get generated egg image from assets
        eggImage = self:GetGeneratedEggImage(eggData.eggType or "basic_egg")
        if not eggImage then
            -- Fallback to regular ImageLabel
            eggImage = Instance.new("ImageLabel")
            eggImage.Image = "rbxasset://textures/face.png"
        end
    else
        -- Regular ImageLabel with asset ID
        eggImage = Instance.new("ImageLabel")
        eggImage.Image = eggData.imageId or "rbxasset://textures/face.png"
    end
    
    eggImage.Name = "EggImage"
    eggImage.Size = UDim2.new(1, 0, 1, 0)
    eggImage.Position = UDim2.new(0, 0, 0, 0)
    eggImage.BackgroundTransparency = 1
    eggImage.BorderSizePixel = 0
    eggImage.Parent = frame
    
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
    petReveal.BorderSizePixel = 0
    petReveal.ImageTransparency = 1
    petReveal.Image = "" -- Will be set when revealing
    petReveal.Parent = frame
    
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
    local petReveal = eggComponents.reveal
    
    eggComponents.state = ANIMATION_STATE.REVEAL
    
    -- Handle generated images vs regular asset IDs
    if petImageId == "generated_image" and petData then
        -- Try to get generated pet image
        local generatedImage = self:GetGeneratedPetImage(petData.petType, petData.variant)
        if generatedImage then
            -- Replace the ImageLabel with the generated ViewportFrame
            petReveal:Destroy()
            petReveal = generatedImage:Clone()
            petReveal.Name = "PetReveal"
            petReveal.Parent = eggComponents.reveal.Parent
            eggComponents.reveal = petReveal
        end
    else
        -- Set regular image
        petReveal.Image = petImageId or "rbxasset://textures/face.png"
    end
    
    -- Scale and fade in effect
    petReveal.Size = UDim2.new(0.3, 0, 0.3, 0)
    petReveal.Position = UDim2.new(0.35, 0, 0.35, 0)
    
    -- Handle transparency for both ImageLabel and ViewportFrame
    local transparencyProperty = "ImageTransparency"
    if petReveal.ClassName == "ViewportFrame" then
        transparencyProperty = "BackgroundTransparency"
        petReveal.BackgroundTransparency = 1
    else
        petReveal.ImageTransparency = 1
    end
    
    local tweenProperties = {
        Size = UDim2.new(0.8, 0, 0.8, 0),
        Position = UDim2.new(0.1, 0, 0.1, 0)
    }
    tweenProperties[transparencyProperty] = 0
    
    local revealTween = TweenService:Create(petReveal, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), tweenProperties)
    
    revealTween:Play()
    
    task.wait(duration)
    
    eggComponents.state = ANIMATION_STATE.COMPLETE
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- MAIN HATCHING INTERFACE
-- ═══════════════════════════════════════════════════════════════════════════════════

function EggHatchingService:StartHatchingAnimation(eggsData, containerGui)
    local eggCount = #eggsData
    local container = containerGui or self:CreateDefaultContainer()
    
    -- Wait for the GUI to be properly sized
    task.wait()  -- Give a frame for the GUI to be parented and sized
    
    -- Calculate grid layout using proper screen dimensions
    local containerSize = container.AbsoluteSize
    if containerSize.X == 0 or containerSize.Y == 0 then
        -- Fallback to reasonable screen dimensions
        local screenSize = workspace.CurrentCamera.ViewportSize
        containerSize = Vector2.new(screenSize.X * 0.8, screenSize.Y * 0.8)
        print("⚠️ Using fallback container size:", containerSize)
    end
    
    local gridInfo = self:CalculateGridLayout(eggCount, containerSize.X, containerSize.Y)
    local positions = self:GenerateEggPositions(eggCount, gridInfo)
    
    print("🥚 Starting hatching animation for", eggCount, "eggs using", gridInfo.layout.name, "grid")
    
    -- Create egg frames
    local eggFrames = {}
    local eggComponents = {}
    
    for i = 1, math.min(eggCount, #positions) do
        local eggData = eggsData[i]
        local position = positions[i]
        
        local frame, components = self:CreateEggFrame(position, eggData)
        frame.Parent = container
        
        table.insert(eggFrames, frame)
        table.insert(eggComponents, components)
    end
    
    -- Execute animations in sequence with staggered timing
    task.spawn(function()
        self:ExecuteHatchingSequence(eggComponents, eggsData)
    end)
    
    return {
        frames = eggFrames,
        components = eggComponents,
        gridInfo = gridInfo,
        container = container,
        cleanup = function()
            print("🧹 Cleaning up hatching animation GUI...")
            -- Destroy all egg frames first
            for _, frame in ipairs(eggFrames) do
                if frame and frame.Parent then
                    frame:Destroy()
                end
            end
            -- Destroy the main container (ScreenGui)
            if container and container.Parent then
                container:Destroy()
                print("✅ Hatching animation GUI destroyed")
            end
        end
    }
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

function EggHatchingService:CreateDefaultContainer()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggHatchingGui"
    screenGui.ResetOnSpawn = false
    
    local container = Instance.new("Frame")
    container.Name = "HatchingContainer"
    container.Size = UDim2.new(0.6, 0, 0.6, 0)  -- Smaller, more centered
    container.Position = UDim2.new(0.2, 0, 0.2, 0)  -- Centered
    container.BackgroundColor3 = Color3.fromRGB(20, 20, 30)  -- Dark blue background
    container.BackgroundTransparency = 0.1  -- More visible
    container.BorderSizePixel = 0
    container.Parent = screenGui
    
    -- Add rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 20)
    corner.Parent = container
    
    -- Add a subtle glow effect
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(100, 150, 255)
    stroke.Thickness = 3
    stroke.Transparency = 0.5
    stroke.Parent = container
    
    screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    
    return container
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

function EggHatchingService:GetGeneratedEggImage(eggType)
    local success, image = pcall(function()
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        if assetsFolder then
            local imagesFolder = assetsFolder:FindFirstChild("Images")
            if imagesFolder then
                local eggsFolder = imagesFolder:FindFirstChild("Eggs")
                if eggsFolder then
                    local eggImage = eggsFolder:FindFirstChild(eggType)
                    if eggImage then
                        return eggImage:Clone() -- Clone the generated ViewportFrame
                    end
                end
            end
        end
        return nil
    end)
    
    return success and image or nil
end

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

return EggHatchingService