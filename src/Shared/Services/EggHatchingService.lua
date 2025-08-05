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

-- ═══════════════════════════════════════════════════════════════════════════════════
-- CINEMATIC SCREEN MANAGEMENT SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════════

function EggHatchingService:ClearScreen()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local screenSize = workspace.CurrentCamera.ViewportSize
    local animatedElements = {}
    
    print("🎬 Clearing screen for cinematic egg hatching...")
    
    -- Find all visible GUI elements to animate out
    for _, gui in pairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name ~= "EggHatchingGui" and gui.Enabled then
            for _, element in pairs(gui:GetDescendants()) do
                if element:IsA("GuiObject") and element.Visible and element.Parent and element.AbsoluteSize.X > 0 then
                    -- Store original properties
                    local originalPos = element.Position
                    local originalSize = element.Size
                    local originalTransparency = element.BackgroundTransparency
                    
                    -- Calculate exit direction based on current position
                    local centerX = element.AbsolutePosition.X + element.AbsoluteSize.X / 2
                    local centerY = element.AbsolutePosition.Y + element.AbsoluteSize.Y / 2
                    local screenCenterX = screenSize.X / 2
                    local screenCenterY = screenSize.Y / 2
                    
                    -- Determine exit direction (which edge/corner to animate towards)
                    local exitPos
                    if centerX < screenCenterX * 0.33 and centerY < screenCenterY * 0.33 then
                        -- Top-left corner
                        exitPos = UDim2.new(0, -element.AbsoluteSize.X - 100, 0, -element.AbsoluteSize.Y - 100)
                    elseif centerX > screenCenterX * 1.66 and centerY < screenCenterY * 0.33 then
                        -- Top-right corner  
                        exitPos = UDim2.new(0, screenSize.X + 100, 0, -element.AbsoluteSize.Y - 100)
                    elseif centerX < screenCenterX * 0.33 and centerY > screenCenterY * 1.66 then
                        -- Bottom-left corner
                        exitPos = UDim2.new(0, -element.AbsoluteSize.X - 100, 0, screenSize.Y + 100)
                    elseif centerX > screenCenterX * 1.66 and centerY > screenCenterY * 1.66 then
                        -- Bottom-right corner
                        exitPos = UDim2.new(0, screenSize.X + 100, 0, screenSize.Y + 100)
                    elseif centerY < screenCenterY * 0.5 then
                        -- Top edge
                        exitPos = UDim2.new(originalPos.X.Scale, originalPos.X.Offset, 0, -element.AbsoluteSize.Y - 100)
                    elseif centerY > screenCenterY * 1.5 then
                        -- Bottom edge
                        exitPos = UDim2.new(originalPos.X.Scale, originalPos.X.Offset, 0, screenSize.Y + 100)
                    elseif centerX < screenCenterX * 0.5 then
                        -- Left edge
                        exitPos = UDim2.new(0, -element.AbsoluteSize.X - 100, originalPos.Y.Scale, originalPos.Y.Offset)
                    else
                        -- Right edge
                        exitPos = UDim2.new(0, screenSize.X + 100, originalPos.Y.Scale, originalPos.Y.Offset)
                    end
                    
                    -- Store element data for restoration
                    table.insert(animatedElements, {
                        element = element,
                        originalPos = originalPos,
                        originalSize = originalSize,
                        originalTransparency = originalTransparency,
                        gui = gui
                    })
                    
                    -- Create exit animation
                    local exitTween = TweenService:Create(element, 
                        TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.In),
                        {
                            Position = exitPos,
                            Size = UDim2.new(originalSize.X.Scale * 0.3, originalSize.X.Offset * 0.3, 
                                           originalSize.Y.Scale * 0.3, originalSize.Y.Offset * 0.3)
                        }
                    )
                    exitTween:Play()
                    
                    -- Also fade out if it has background
                    if element.BackgroundTransparency < 1 then
                        local fadeTween = TweenService:Create(element,
                            TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                            { BackgroundTransparency = 1 }
                        )
                        fadeTween:Play()
                    end
                end
            end
        end
    end
    
    print("🎭 Animated", #animatedElements, "UI elements off-screen")
    
    -- Wait for animations to complete
    task.wait(1.0)
    
    return animatedElements
end

function EggHatchingService:RestoreScreen(animatedElements)
    if not animatedElements or #animatedElements == 0 then
        print("⚠️ No animated elements to restore")
        return
    end
    
    print("🎬 Restoring screen UI elements...")
    
    -- Animate all elements back to their original positions
    for _, elementData in pairs(animatedElements) do
        local element = elementData.element
        
        -- Check if element still exists
        if element and element.Parent then
            -- Create return animation
            local returnTween = TweenService:Create(element,
                TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                {
                    Position = elementData.originalPos,
                    Size = elementData.originalSize
                }
            )
            returnTween:Play()
            
            -- Restore transparency
            if elementData.originalTransparency < 1 then
                local fadeInTween = TweenService:Create(element,
                    TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { BackgroundTransparency = elementData.originalTransparency }
                )
                fadeInTween:Play()
            end
        end
    end
    
    print("✨ Screen restoration complete!")
    
    -- Wait for restoration to complete
    task.wait(1.0)
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
    
    -- PHASE 1: Clear the screen cinematically
    print("🎬 Phase 1: Clearing screen for cinematic experience...")
    local animatedElements = self:ClearScreen()
    
    -- PHASE 2: Set up the animation container
    local container = containerGui or self:CreateCinematicContainer()
    
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
    
    print("🥚 Phase 2: Starting hatching animation for", eggCount, "eggs using", gridInfo.layout.name, "grid")
    
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
    
    -- PHASE 3: Execute animations in sequence with staggered timing
    task.spawn(function()
        self:ExecuteHatchingSequence(eggComponents, eggsData)
        
        -- PHASE 4: After animations complete, wait a moment then restore screen
        task.wait(2) -- Let player enjoy the result
        print("🎬 Phase 4: Restoring screen...")
        self:RestoreScreen(animatedElements)
    end)
    
    return {
        frames = eggFrames,
        components = eggComponents,
        gridInfo = gridInfo,
        container = container,
        animatedElements = animatedElements,
        cleanup = function()
            print("🧹 Cleaning up hatching animation GUI...")
            -- Restore screen first if not already done
            if animatedElements and #animatedElements > 0 then
                task.spawn(function()
                    self:RestoreScreen(animatedElements)
                end)
            end
            
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

function EggHatchingService:CreateCinematicContainer()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggHatchingGui"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 100  -- Ensure it's on top
    
    -- Full-screen transparent container for cinematic effect
    local container = Instance.new("Frame")
    container.Name = "HatchingContainer"
    container.Size = UDim2.new(1, 0, 1, 0)  -- Full screen
    container.Position = UDim2.new(0, 0, 0, 0)  -- Top-left corner
    container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)  -- Pure black background
    container.BackgroundTransparency = 0.2  -- Slight tint for cinematic feel
    container.BorderSizePixel = 0
    container.Parent = screenGui
    
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