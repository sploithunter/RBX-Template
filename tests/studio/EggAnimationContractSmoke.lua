--[[
    Studio smoke test for client hatch animation metadata and reveal badges.

    Run in play mode:

    return require(game:GetService("ReplicatedStorage").Tests.studio.EggAnimationContractSmoke).runText()
]]

local EggAnimationContractSmoke = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage.Shared.Locations)

local DEFAULT_TIMEOUT_SECONDS = 20

local function waitFor(description, timeoutSeconds, predicate)
    local deadline = os.clock() + (timeoutSeconds or DEFAULT_TIMEOUT_SECONDS)

    while os.clock() < deadline do
        local result = predicate()
        if result then
            return result
        end
        task.wait(0.1)
    end

    error("Timed out waiting for " .. description)
end

function EggAnimationContractSmoke.run(options)
    options = options or {}
    local timeoutSeconds = options.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
    local eggHatchingService = require(ReplicatedStorage.Shared.Services.EggHatchingService)
    local eggSystemConfig = Locations.getConfig("egg_system")
    local animationConfig = eggSystemConfig.hatching.animation
    local layoutConfig = animationConfig.layout

    eggHatchingService:TestCleanup()

    local animationResult = eggHatchingService:StartHatchingAnimation({
        {
            eggType = options.eggType or "basic_egg",
            imageId = "generated_image",
            petImageId = "generated_image",
            petType = "colorado",
            variant = "rainbow",
            rarityId = "exclusive",
            rarityName = "Exclusive",
            specialHatch = true,
            autoDeleted = false,
            animation = {
                useAuthoredEggVisual = true,
            },
            hatchOptions = {
                fastHatch = true,
                silentHatch = true,
            },
        },
        {
            eggType = options.eggType or "basic_egg",
            imageId = "generated_image",
            petImageId = "generated_image",
            petType = "bear",
            variant = "basic",
            rarityId = "common",
            rarityName = "Common",
            specialHatch = false,
            autoDeleted = true,
            autoDeleteReason = "rarity",
            animation = {
                useAuthoredEggVisual = true,
            },
            hatchOptions = {
                fastHatch = true,
                silentHatch = true,
            },
        },
    })

    local initial = waitFor("animation frames", timeoutSeconds, function()
        local state = eggHatchingService:GetActiveAnimationDebugState()
        if state.frameCount == 2 then
            return state
        end
        return nil
    end)

    local specialFrame = initial.frames[1]
    local autoDeletedFrame = initial.frames[2]
    assert(initial.layout.name == "2x1", "Animation layout name mismatch")
    assert(initial.layout.padding == layoutConfig.padding, "Animation layout padding mismatch")
    assert(
        initial.layout.eggSize >= layoutConfig.min_egg_size,
        "Animation egg size below configured min"
    )
    assert(initial.timing.fastHatch == true, "Fast hatch timing flag missing")
    assert(initial.timing.silentHatch == true, "Silent hatch timing flag missing")
    assert(
        math.abs(initial.timing.speedScale - animationConfig.fast_hatch_speed_scale) < 0.001,
        "Fast hatch speed scale did not match config"
    )
    assert(specialFrame.specialHatch == true, "Special hatch flag missing")
    assert(specialFrame.rarityId == "exclusive", "Special hatch rarity mismatch")
    assert(specialFrame.hasSpecialRevealStroke == true, "Special hatch stroke missing")
    assert(specialFrame.specialGlowPulseEnabled == true, "Special hatch glow pulse missing")
    assert(specialFrame.badges.SpecialBadge, "Special hatch badge missing")
    assert(specialFrame.badges.RarityBadge, "Special rarity badge missing")
    assert(specialFrame.badges.VariantBadge, "Special variant badge missing")
    assert(autoDeletedFrame.autoDeleted == true, "Auto-delete flag missing")
    assert(autoDeletedFrame.badges.AutoDeleteBadge, "Auto-delete badge missing")

    local revealed = waitFor("visible reveal badges", timeoutSeconds, function()
        local state = eggHatchingService:GetActiveAnimationDebugState()
        local first = state.frames[1]
        local second = state.frames[2]
        if
            first
            and second
            and first.badges.SpecialBadge
            and first.badges.SpecialBadge.visible == true
            and second.badges.AutoDeleteBadge
            and second.badges.AutoDeleteBadge.visible == true
        then
            return state
        end
        return nil
    end)

    eggHatchingService:TestCleanup()

    return {
        frameCount = initial.frameCount,
        specialBadge = specialFrame.badges.SpecialBadge.text,
        rarityBadge = specialFrame.badges.RarityBadge.text,
        variantBadge = specialFrame.badges.VariantBadge.text,
        autoDeleteBadge = autoDeletedFrame.badges.AutoDeleteBadge.text,
        revealedStatus = revealed.guiStatus,
        animationComplete = animationResult.isComplete == true,
    }
end

function EggAnimationContractSmoke.runText(options)
    local result = EggAnimationContractSmoke.run(options)
    return string.format(
        "EggAnimationContractSmoke passed: frames=%d special=%q rarity=%q variant=%q autoDelete=%q revealedStatus=%s",
        result.frameCount,
        result.specialBadge,
        result.rarityBadge,
        result.variantBadge,
        result.autoDeleteBadge,
        result.revealedStatus
    )
end

return EggAnimationContractSmoke
