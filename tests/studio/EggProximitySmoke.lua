--[[
    Client-coordinated Studio smoke test for egg proximity and hatching.

    Run in play mode through Studio MCP / command bar:

    return require(game:GetService("ReplicatedStorage").Tests.studio.EggProximitySmoke).runText()

    The server-side setup/assertion bridge is `StudioSmokeTestService`, exposed
    only while running in Studio.
]]

local EggProximitySmoke = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_TIMEOUT_SECONDS = 20
local REMOTE_NAME = "StudioSmokeTest"
local Locations = require(ReplicatedStorage.Shared.Locations)
local EggInteractionService = require(ReplicatedStorage.Shared.Services.EggInteractionService)

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

local function getPlayer(options)
    if options.player then
        return options.player
    end

    return Players.LocalPlayer
        or Players:GetPlayers()[1]
        or waitFor("a player", options.timeoutSeconds, function()
            return Players.LocalPlayer or Players:GetPlayers()[1]
        end)
end

local function invoke(remote, action, payload)
    local response = remote:InvokeServer(action, payload or {})
    if type(response) ~= "table" then
        error("Studio smoke bridge returned non-table response")
    end
    if response.ok ~= true then
        error(response.error or ("Studio smoke bridge action failed: " .. tostring(action)))
    end
    return response
end

local function getCurrentTarget(player)
    local gui = player:FindFirstChild("PlayerGui")
    local targetGui = gui and gui:FindFirstChild("EggCurrentTarget")
    local frame = targetGui and targetGui:FindFirstChild("PreviewFrame")
    local target = frame and frame:FindFirstChild("CurrentTarget")

    return target and target.Value or nil, frame
end

local function getHatchPanel(player)
    local gui = player:FindFirstChild("PlayerGui")
    local panelGui = gui and gui:FindFirstChild("EggHatchPanel")
    local panel = panelGui and panelGui:FindFirstChild("Panel")
    return panel
end

local function waitForTarget(player, expectedValue, timeoutSeconds)
    return waitFor("egg current target " .. tostring(expectedValue), timeoutSeconds, function()
        local currentTarget, frame = getCurrentTarget(player)
        if currentTarget == expectedValue then
            return {
                currentTarget = currentTarget,
                visible = frame and frame.Visible or false,
            }
        end
        return nil
    end)
end

local function waitForHatchPanel(player, expectedVisible, timeoutSeconds)
    return waitFor(
        "egg hatch panel visibility " .. tostring(expectedVisible),
        timeoutSeconds,
        function()
            local panel = getHatchPanel(player)
            if panel and panel.Visible == expectedVisible then
                return panel
            end
            if expectedVisible == false and not panel then
                return true
            end
            return nil
        end
    )
end

local function waitForHatchSelectedCount(player, expectedCount, timeoutSeconds)
    return waitFor(
        "persisted hatch selected count " .. tostring(expectedCount),
        timeoutSeconds,
        function()
            local settingsFolder = player:FindFirstChild("Settings")
            local autoFolder = settingsFolder and settingsFolder:FindFirstChild("AutoSystems")
            local hatchFolder = autoFolder and autoFolder:FindFirstChild("Hatch")
            local selected = hatchFolder and hatchFolder:FindFirstChild("SelectedCount")
            if selected and selected.Value == expectedCount then
                return selected.Value
            end
            return nil
        end
    )
end

local function waitForHatchActionMode(player, expectedMode, timeoutSeconds)
    return waitFor(
        "persisted hatch action mode " .. tostring(expectedMode),
        timeoutSeconds,
        function()
            local settingsFolder = player:FindFirstChild("Settings")
            local autoFolder = settingsFolder and settingsFolder:FindFirstChild("AutoSystems")
            local hatchFolder = autoFolder and autoFolder:FindFirstChild("Hatch")
            local actionMode = hatchFolder and hatchFolder:FindFirstChild("ActionMode")
            if actionMode and actionMode.Value == expectedMode then
                return actionMode.Value
            end
            return nil
        end
    )
end

local function readHatchActionMode(player)
    local settingsFolder = player:FindFirstChild("Settings")
    local autoFolder = settingsFolder and settingsFolder:FindFirstChild("AutoSystems")
    local hatchFolder = autoFolder and autoFolder:FindFirstChild("Hatch")
    local actionMode = hatchFolder and hatchFolder:FindFirstChild("ActionMode")
    return actionMode and actionMode.Value or "single"
end

local function waitForHatchMode(player, optionName, expectedEnabled, timeoutSeconds)
    return waitFor(
        "persisted hatch mode " .. tostring(optionName) .. "=" .. tostring(expectedEnabled),
        timeoutSeconds,
        function()
            local settingsFolder = player:FindFirstChild("Settings")
            local autoFolder = settingsFolder and settingsFolder:FindFirstChild("AutoSystems")
            local hatchFolder = autoFolder and autoFolder:FindFirstChild("Hatch")
            local modesFolder = hatchFolder and hatchFolder:FindFirstChild("Modes")
            local modeValue = modesFolder and modesFolder:FindFirstChild(optionName)
            if modeValue and modeValue.Value == expectedEnabled then
                return true
            end
            return nil
        end
    )
end

local function readHatchMode(player, optionName)
    local settingsFolder = player:FindFirstChild("Settings")
    local autoFolder = settingsFolder and settingsFolder:FindFirstChild("AutoSystems")
    local hatchFolder = autoFolder and autoFolder:FindFirstChild("Hatch")
    local modesFolder = hatchFolder and hatchFolder:FindFirstChild("Modes")
    local modeValue = modesFolder and modesFolder:FindFirstChild(optionName)
    return modeValue and modeValue.Value == true or false
end

local function getClippedDrawerChildren(drawer)
    local clipped = {}
    local drawerPosition = drawer.AbsolutePosition
    local drawerSize = drawer.AbsoluteSize

    for _, child in ipairs(drawer:GetDescendants()) do
        if child:IsA("GuiObject") and child.Visible == true then
            local relativeX = child.AbsolutePosition.X - drawerPosition.X
            local relativeY = child.AbsolutePosition.Y - drawerPosition.Y
            local right = relativeX + child.AbsoluteSize.X
            local bottom = relativeY + child.AbsoluteSize.Y
            if
                relativeX < -0.5
                or relativeY < -0.5
                or right > drawerSize.X + 0.5
                or bottom > drawerSize.Y + 0.5
            then
                table.insert(clipped, child.Name)
            end
        end
    end

    return clipped
end

function EggProximitySmoke.run(options)
    options = options or {}

    local eggType = options.eggType or "basic_egg"
    local timeoutSeconds = options.timeoutSeconds or DEFAULT_TIMEOUT_SECONDS
    local assertUi = options.assertUi ~= false
    local player = getPlayer(options)
    local remote = waitFor(REMOTE_NAME .. " RemoteFunction", timeoutSeconds, function()
        local instance = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
        if instance and instance:IsA("RemoteFunction") then
            return instance
        end
        return nil
    end)

    local started = false
    local success, result = pcall(function()
        local begin = invoke(remote, "BeginEggProximity", {
            eggType = eggType,
            setupAutoHatchUnlocked = false,
            setupGoldenModeUnlocked = false,
            setupChargedModeUnlocked = false,
            setupFastHatchUnlocked = false,
            setupSkipHatchUnlocked = false,
            setupMaxHatchCount = 5,
            setupAutoDeleteFilters = {
                enabled = false,
                rarities = { "common" },
                pet_types = { "bear" },
                variants = { "golden" },
            },
        })
        started = true

        invoke(remote, "MoveEggProximity", { placement = "far" })
        task.wait(0.35)

        if assertUi then
            waitForTarget(player, "None", timeoutSeconds)
            waitForHatchPanel(player, false, timeoutSeconds)
        end

        local far = invoke(remote, "HatchEggProximity")
        assert(far.result == "Error", "Far hatch should be rejected")
        assert(
            tostring(far.message):find("Too far", 1, true),
            "Far hatch rejected for wrong reason"
        )
        assert(far.afterCurrency == far.beforeCurrency, "Far hatch changed currency")
        assert(far.afterPetCount == far.beforePetCount, "Far hatch changed pet count")

        task.wait((far.cooldown or 0) + 0.25)

        invoke(remote, "MoveEggProximity", { placement = "near" })
        task.wait(0.35)

        if assertUi then
            local targetState = waitForTarget(player, eggType, timeoutSeconds)
            assert(targetState.visible == true, "Egg target UI was not visible near the egg")
            local hatchPanel = waitForHatchPanel(player, true, timeoutSeconds)
            assert(hatchPanel:FindFirstChild("Hatch"), "Hatch panel missing Hatch button")
            assert(hatchPanel:FindFirstChild("Max"), "Hatch panel missing Max button")
            assert(hatchPanel:FindFirstChild("Auto"), "Hatch panel missing Auto button")
            assert(hatchPanel:FindFirstChild("Count"), "Hatch panel missing count display")
            assert(
                hatchPanel:GetAttribute("InlineControlsVisible") == false,
                "Hatch panel inline controls should be hidden by default"
            )
            assert(
                hatchPanel:GetAttribute("HatchActionMode") == readHatchActionMode(player),
                "Hatch panel did not expose the persisted hatch action mode"
            )
            assert(
                hatchPanel:GetAttribute("MaxEntitledHatchCount") == 5,
                "Hatch panel did not expose effective max hatch entitlement"
            )
            assert(
                hatchPanel.Count:GetAttribute("MaxEntitledHatchCount") == 5,
                "Hatch count label did not expose effective max hatch entitlement"
            )
            assert(
                hatchPanel.Max:GetAttribute("MaxEntitledHatchCount") == 5,
                "Max button did not expose effective max hatch entitlement"
            )
            assert(
                hatchPanel.Auto:GetAttribute("ModeState") == "locked",
                "Auto button did not expose locked state"
            )
            assert(
                hatchPanel.Auto:GetAttribute("ModeOwned") == false,
                "Auto button did not expose ownership state"
            )
            local desktopLayout =
                EggInteractionService:ComputeHatchPanelLayout(Vector2.new(1280, 720), false)
            assert(
                desktopLayout.scale == 1,
                "Desktop hatch panel layout should render at full scale"
            )
            local mobileLayout =
                EggInteractionService:ComputeHatchPanelLayout(Vector2.new(360, 640), true)
            assert(mobileLayout.scale < 1, "Mobile hatch panel layout did not scale down")
            assert(mobileLayout.fitsWidth == true, "Mobile hatch panel layout overflowed width")
            assert(mobileLayout.fitsHeight == true, "Mobile hatch panel layout overflowed height")
            local settings = hatchPanel:FindFirstChild("SettingsDrawer")
            assert(settings, "Hatch panel missing settings drawer")
            local eggSystemConfig = Locations.getConfig("egg_system")
            local panelConfig = eggSystemConfig.ui.hatch_panel
            hatchPanel.Size =
                UDim2.new(0, panelConfig.width, 0, panelConfig.height + panelConfig.settings_height)
            settings.Visible = true
            local openDrawer = waitFor("expanded hatch settings drawer", timeoutSeconds, function()
                if settings.Visible == true and settings.AbsoluteSize.Y > 0 then
                    return settings
                end
                return nil
            end)
            assert(
                openDrawer.AbsoluteSize.X > 0 and openDrawer.AbsoluteSize.Y > 0,
                "Hatch settings drawer did not report rendered dimensions"
            )
            local clippedChildren = getClippedDrawerChildren(openDrawer)
            assert(
                #clippedChildren == 0,
                "Hatch settings drawer clipped children: " .. table.concat(clippedChildren, ", ")
            )
            local helpText = settings:FindFirstChild("HelpText")
            assert(helpText, "Hatch panel missing config-driven help text")
            local protectedLabel = settings:FindFirstChild("ProtectedAutoDeleteRarities")
            assert(protectedLabel, "Hatch panel missing protected auto-delete rarity list")
            local protectedRarities =
                tostring(protectedLabel:GetAttribute("ProtectedRarities") or "")
            assert(
                protectedRarities:find("exclusive", 1, true),
                "Protected auto-delete list did not include exclusive rarity id"
            )
            assert(
                protectedRarities:find("huge", 1, true),
                "Protected auto-delete list did not include huge rarity id"
            )
            assert(
                tostring(protectedLabel.Text):find("Protected:", 1, true),
                "Protected auto-delete list did not explain protected tiers"
            )
            assert(
                settings:FindFirstChild("pet_types_bear"),
                "Hatch panel missing pet-family auto-delete filter"
            )
            local autoDeleteState = waitFor(
                "replicated auto-delete filters",
                timeoutSeconds,
                function()
                    local state = EggInteractionService:GetHatchPanelDebugState().autoDelete
                    if
                        state
                        and state.enabled == false
                        and state.rarities
                        and state.rarities.common == true
                        and state.pet_types
                        and state.pet_types.bear == true
                        and state.variants
                        and state.variants.golden == true
                    then
                        return state
                    end
                    return nil
                end
            )
            assert(autoDeleteState.enabled == false, "Replicated auto-delete state changed enabled")
            assert(
                settings.AutoDeleteEnabled.Text == "Off",
                "Hatch panel did not read replicated auto-delete enabled state"
            )
            assert(
                settings.AutoDeleteEnabled:GetAttribute("SelectedFilterCount") == 3,
                "Hatch panel did not summarize selected auto-delete filters"
            )
            assert(
                settings.Header:GetAttribute("SelectedRarityFilterCount") == 1,
                "Hatch panel auto-delete summary did not count rarity filters"
            )
            assert(
                tostring(settings.Header.Text):find("3 filters", 1, true),
                "Hatch panel auto-delete header did not summarize saved filters"
            )
            assert(
                settings:FindFirstChild("Mode_goldenMode"),
                "Hatch panel missing Golden mode toggle"
            )
            assert(
                settings.Mode_goldenMode:GetAttribute("HelpText"),
                "Golden mode toggle missing help text"
            )
            assert(
                settings.Mode_goldenMode:GetAttribute("ModeState") == "locked",
                "Golden mode toggle did not expose locked state"
            )
            assert(
                settings.Mode_goldenMode:GetAttribute("LockedHelpText"),
                "Golden mode toggle missing locked help text"
            )
            assert(
                settings.Mode_goldenMode:GetAttribute("CostMultiplier") == 20,
                "Golden mode toggle did not expose configured cost multiplier"
            )
            assert(
                tostring(settings.Mode_goldenMode:GetAttribute("CurrentHelpText")):find(
                    "20x",
                    1,
                    true
                ),
                "Golden mode help did not explain configured cost multiplier"
            )
            assert(
                settings:FindFirstChild("Mode_chargedMode"),
                "Hatch panel missing Charged mode toggle"
            )
            assert(
                settings.Mode_chargedMode:GetAttribute("CostMultiplier") == 5,
                "Charged mode toggle did not expose configured cost multiplier"
            )
            assert(
                settings.Mode_chargedMode:GetAttribute("LuckBonus") == 1,
                "Charged mode toggle did not expose configured hatch luck"
            )
            assert(
                settings.Mode_chargedMode:GetAttribute("SecretLuckBonus") == 0.25,
                "Charged mode toggle did not expose configured secret luck"
            )
            assert(
                settings:FindFirstChild("Mode_skipHatch"),
                "Hatch panel missing Skip mode toggle"
            )
            assert(
                settings:FindFirstChild("Mode_showHatch"),
                "Hatch panel missing Show mode toggle"
            )
            local modeStatus = settings:FindFirstChild("ModeStatus")
            assert(modeStatus, "Hatch panel missing mode status text")
            assert(
                tostring(modeStatus.Text):find("Locked:", 1, true),
                "Hatch panel mode status did not explain locked modes"
            )
            assert(
                tostring(modeStatus.Text):find("20x", 1, true),
                "Hatch panel mode status did not include configured mode details"
            )

            assert(hatchPanel.Count:IsA("TextBox"), "Hatch count control should be editable")
            EggInteractionService:SubmitHatchCountInput("4")
            waitForHatchSelectedCount(player, 4, timeoutSeconds)
            assert(hatchPanel.Count.Text == "x4", "Hatch count input did not show submitted count")
            local costDetail = hatchPanel:FindFirstChild("CostDetail")
            assert(costDetail, "Hatch panel missing cost detail label")
            assert(
                hatchPanel:GetAttribute("HatchCurrency") == begin.currency,
                "Hatch panel did not expose hatch currency"
            )
            assert(
                hatchPanel:GetAttribute("BaseCostEach") == begin.cost,
                "Hatch panel did not expose base egg cost"
            )
            assert(
                hatchPanel:GetAttribute("CostMultiplier") == 1,
                "Hatch panel default cost multiplier should be one"
            )
            assert(
                hatchPanel:GetAttribute("EstimatedCostEach") == begin.cost,
                "Hatch panel estimated per-egg cost mismatch"
            )
            assert(
                hatchPanel:GetAttribute("EstimatedTotalCost") == begin.cost * 4,
                "Hatch panel estimated total cost mismatch"
            )
            assert(
                tostring(costDetail.Text):find("each", 1, true),
                "Hatch panel cost detail did not explain per-egg cost"
            )
            local debugState = EggInteractionService:GetHatchPanelDebugState()
            assert(
                debugState.selectedHatchCount == 4,
                "Hatch interaction service did not keep selected count"
            )
            assert(
                debugState.persistedSelectedHatchCount == 4,
                "Hatch interaction service did not read persisted selected count"
            )

            EggInteractionService:SetSelectedHatchCount(1)
            waitForHatchSelectedCount(player, 1, timeoutSeconds)

            local originalActionMode = readHatchActionMode(player)
            EggInteractionService:SetHatchActionMode("max")
            waitForHatchActionMode(player, "max", timeoutSeconds)
            waitFor("max hatch cost display", timeoutSeconds, function()
                return hatchPanel:GetAttribute("EstimatedDisplayCount") == 5
            end)
            debugState = EggInteractionService:GetHatchPanelDebugState()
            assert(
                debugState.hatchActionMode == "max",
                "Hatch interaction service did not keep hatch action mode"
            )
            assert(
                hatchPanel:GetAttribute("EstimatedTotalCost") == begin.cost * 5,
                "Max hatch compact panel did not estimate the effective max hatch count"
            )
            assert(
                debugState.persistedHatchActionMode == "max",
                "Hatch interaction service did not read persisted hatch action mode"
            )
            EggInteractionService:SetHatchActionMode(originalActionMode)
            waitForHatchActionMode(player, originalActionMode, timeoutSeconds)

            local originalSilentHatch = readHatchMode(player, "silentHatch")
            local targetSilentHatch = not originalSilentHatch
            EggInteractionService:SetHatchModeState("silentHatch", targetSilentHatch)
            waitForHatchMode(player, "silentHatch", targetSilentHatch, timeoutSeconds)
            debugState = EggInteractionService:GetHatchPanelDebugState()
            assert(
                debugState.hatchModes and debugState.hatchModes.silentHatch == targetSilentHatch,
                "Hatch interaction service did not keep silent hatch mode"
            )
            assert(
                debugState.persistedHatchModes
                    and debugState.persistedHatchModes.silentHatch == targetSilentHatch,
                "Hatch interaction service did not read persisted silent hatch mode"
            )
            EggInteractionService:SetHatchModeState("silentHatch", originalSilentHatch)
            waitForHatchMode(player, "silentHatch", originalSilentHatch, timeoutSeconds)

            local originalShowHatch = readHatchMode(player, "showHatch")
            local targetShowHatch = not originalShowHatch
            EggInteractionService:SetHatchModeState("showHatch", targetShowHatch)
            waitForHatchMode(player, "showHatch", targetShowHatch, timeoutSeconds)
            debugState = EggInteractionService:GetHatchPanelDebugState()
            assert(
                debugState.hatchModes and debugState.hatchModes.showHatch == targetShowHatch,
                "Hatch interaction service did not keep show hatch mode"
            )
            assert(
                debugState.persistedHatchModes
                    and debugState.persistedHatchModes.showHatch == targetShowHatch,
                "Hatch interaction service did not read persisted show hatch mode"
            )
            EggInteractionService:SetHatchModeState("showHatch", originalShowHatch)
            waitForHatchMode(player, "showHatch", originalShowHatch, timeoutSeconds)
            settings.Visible = false
        end

        local near = invoke(remote, "HatchEggProximity")
        assert(type(near.result) == "table" and near.result.success == true, tostring(near.message))
        local expectedTotalCost = tonumber(near.result.TotalCost)
            or ((tonumber(near.cost) or 0) * (tonumber(near.result.hatchCount) or 1))
        local actualSpent = near.beforeCurrency - near.afterCurrency
        assert(
            actualSpent > 0 and actualSpent <= expectedTotalCost,
            string.format(
                "Near hatch currency delta was outside expected range: before=%s after=%s spent=%s expectedCost=%s",
                tostring(near.beforeCurrency),
                tostring(near.afterCurrency),
                tostring(actualSpent),
                tostring(expectedTotalCost)
            )
        )
        assert(near.afterPetCount == near.beforePetCount + 1, "Near hatch did not add one pet")

        invoke(remote, "MoveEggProximity", { placement = "far" })
        task.wait(0.35)

        if assertUi then
            waitForTarget(player, "None", timeoutSeconds)
            waitForHatchPanel(player, false, timeoutSeconds)
        end

        return {
            player = player.Name,
            eggType = begin.eggType,
            currency = begin.currency,
            cost = begin.cost,
            originalCurrency = begin.originalCurrency,
            originalPetCount = begin.originalPetCount,
            hatchedPet = near.result.Pet,
            hatchedVariant = near.result.Type,
        }
    end)

    local restoreResponse
    if started then
        restoreResponse = remote:InvokeServer("RestoreEggProximity", {})
    end

    if not success then
        error(result)
    end

    result.restored = type(restoreResponse) == "table" and restoreResponse.restored == true
    return result
end

function EggProximitySmoke.runText(options)
    local result = EggProximitySmoke.run(options)
    return string.format(
        "EggProximitySmoke passed: player=%s egg=%s cost=%d %s hatched=%s/%s restored=%s",
        result.player,
        result.eggType,
        result.cost,
        result.currency,
        tostring(result.hatchedPet),
        tostring(result.hatchedVariant),
        tostring(result.restored)
    )
end

return EggProximitySmoke
