--[[
    EggInteractionService - Simplified to work with CurrentTarget system
    
    Now only handles E key presses and egg purchasing.
    All proximity detection and UI positioning is handled by EggCurrentTargetService.
    Follows the working game's pattern exactly.
--]]

local EggInteractionService = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Dependencies
local Locations = require(ReplicatedStorage.Shared.Locations)
local petConfig = Locations.getConfig("pets")
local eggSystemConfig = Locations.getConfig("egg_system")
local EggWorldQuery = require(ReplicatedStorage.Shared.Services.EggWorldQuery)
local Signals = require(ReplicatedStorage.Shared.Network.Signals)

-- Local player reference
local player = Players.LocalPlayer

-- Current target service reference
local currentTargetService = nil
local hatchRequestInFlight = false
local autoHatchEnabled = false
local autoHatchSessionId = 0
local selectedHatchCount = 1
local hatchPanelGui = nil
local hatchPanel = nil
local hatchPanelFields = {}
local hatchPanelConnection = nil
local entitlementConnections = {}
local hatchSettingsOpen = false
local lastPersistedHatchCount = nil
local lastPersistedHatchModesKey = nil
local autoDeleteState = {
    enabled = false,
    rarities = {},
    pet_types = {},
    variants = {},
}
local hatchModeState = {
    goldenMode = false,
    chargedMode = false,
    fastHatch = false,
    skipHatch = false,
    silentHatch = false,
}
local lastStatusAt = 0

local MODE_STUB_KEYS = {
    goldenMode = "golden_mode",
    chargedMode = "charged_mode",
    fastHatch = "fast_hatch",
    skipHatch = "skip_hatch",
}

local MODE_ENTITLEMENT_ATTRIBUTES = {
    goldenMode = "GoldenHatchUnlocked",
    chargedMode = "ChargedHatchUnlocked",
    fastHatch = "FastHatchUnlocked",
    skipHatch = "SkipHatchUnlocked",
}

-- Logger setup using singleton pattern
local Logger
local loggerSuccess, loggerResult = pcall(function()
    return require(Locations.Logger)
end)

if loggerSuccess and loggerResult then
    Logger = loggerResult -- Use singleton directly
else
    Logger = {
        Info = function(_self, message, context)
            print("[INFO]", message, context)
        end,
        Warn = function(_self, message, context)
            warn("[WARN]", message, context)
        end,
        Error = function(_self, message, context)
            warn("[ERROR]", message, context)
        end,
        Debug = function(_self, message, context)
            print("[DEBUG]", message, context)
        end,
    }
end

local function getHatchingConfig()
    return eggSystemConfig.hatching or {}
end

local function getHatchPanelConfig()
    return eggSystemConfig.ui and eggSystemConfig.ui.hatch_panel or {}
end

local function getHatchPanelHelpConfig()
    return getHatchPanelConfig().help or {}
end

local function getModeConfigByOption(optionName)
    local modes = getHatchPanelConfig().modes or {}
    for key, cfg in pairs(modes) do
        if (cfg.option or key) == optionName then
            return cfg
        end
    end
    return nil
end

local function isModeOwned(optionName)
    if optionName == "silentHatch" then
        return true
    end

    local attributeName = MODE_ENTITLEMENT_ATTRIBUTES[optionName]
    if attributeName then
        local attributeValue = player:GetAttribute(attributeName)
        if attributeValue ~= nil then
            return attributeValue == true
        end
    end

    local stubKey = MODE_STUB_KEYS[optionName]
    local stub = stubKey and (getHatchingConfig().shop_stubs or {})[stubKey]
    if type(stub) == "table" then
        if stub.enabled == false then
            return false
        end
        return stub.owned_by_default == true
    end

    return true
end

local function getModeHelpText(optionName, cfg)
    cfg = cfg or getModeConfigByOption(optionName) or {}
    local owned = isModeOwned(optionName)
    if not owned then
        return cfg.locked_description or cfg.description
    end
    if hatchModeState[optionName] == true then
        return cfg.active_description or cfg.description
    end
    return cfg.available_description or cfg.description
end

local function getMaxHatchCount()
    local hatching = getHatchingConfig()
    return math.clamp(math.floor(tonumber(hatching.max_count) or 99), 1, 99)
end

local function getEffectiveMaxHatchCount()
    local hatching = getHatchingConfig()
    local stubs = hatching.shop_stubs or {}
    local maxStub = stubs.max_hatch_count or {}
    local configuredDefault = tonumber(maxStub.default_value)
        or tonumber(hatching.default_max_entitled_count)
        or getMaxHatchCount()
    local attributeMax = tonumber(player:GetAttribute("MaxEggHatchCount"))
    local effective = attributeMax or configuredDefault
    return math.clamp(math.floor(tonumber(effective) or 1), 1, getMaxHatchCount())
end

local function isAutoHatchOwned()
    local attributeValue = player:GetAttribute("AutoHatchUnlocked")
    if attributeValue ~= nil then
        return attributeValue == true
    end

    local autoStub = (getHatchingConfig().shop_stubs or {}).auto_hatch or {}
    if autoStub.enabled == false then
        return false
    end
    return autoStub.owned_by_default == true
end

local function clampSelectedCount(count)
    return math.clamp(math.floor(tonumber(count) or 1), 1, getEffectiveMaxHatchCount())
end

local function getDefaultSelectedHatchCount()
    local hatching = getHatchingConfig()
    local panel = getHatchPanelConfig()
    return clampSelectedCount(
        tonumber(panel.default_selected_count) or tonumber(hatching.default_requested_count) or 1
    )
end

local function getPersistedSelectedHatchCount()
    local settingsFolder = player:FindFirstChild("Settings")
    local autoFolder = settingsFolder and settingsFolder:FindFirstChild("AutoSystems")
    local hatchFolder = autoFolder and autoFolder:FindFirstChild("Hatch")
    local selectedValue = hatchFolder and hatchFolder:FindFirstChild("SelectedCount")
    if selectedValue and selectedValue:IsA("IntValue") then
        return clampSelectedCount(selectedValue.Value)
    end
    return nil
end

local function persistSelectedHatchCount(count)
    count = clampSelectedCount(count)
    if lastPersistedHatchCount == count then
        return
    end

    lastPersistedHatchCount = count
    Signals.HatchSettings_SetCount:FireServer({
        selectedCount = count,
    })
end

local function getPersistedHatchModes()
    local settingsFolder = player:FindFirstChild("Settings")
    local autoFolder = settingsFolder and settingsFolder:FindFirstChild("AutoSystems")
    local hatchFolder = autoFolder and autoFolder:FindFirstChild("Hatch")
    local modesFolder = hatchFolder and hatchFolder:FindFirstChild("Modes")
    if not modesFolder then
        return nil
    end

    local modes = {}
    local found = false
    for optionName in pairs(hatchModeState) do
        local value = modesFolder:FindFirstChild(optionName)
        if value and value:IsA("BoolValue") then
            modes[optionName] = value.Value == true
            found = true
        end
    end
    return found and modes or nil
end

local function hatchModesKey(modes)
    local parts = {}
    for optionName in pairs(hatchModeState) do
        table.insert(parts, optionName .. "=" .. tostring(modes and modes[optionName] == true))
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function currentHatchModes()
    local modes = {}
    for optionName, enabled in pairs(hatchModeState) do
        modes[optionName] = enabled == true
    end
    return modes
end

local function persistHatchModes()
    local modes = currentHatchModes()
    local key = hatchModesKey(modes)
    if lastPersistedHatchModesKey == key then
        return
    end

    lastPersistedHatchModesKey = key
    Signals.HatchSettings_SetModes:FireServer({
        modes = modes,
    })
end

local function asSet(values)
    local result = {}
    if type(values) ~= "table" then
        return result
    end

    for key, value in pairs(values) do
        if type(key) == "number" then
            result[tostring(value)] = true
        elseif value == true then
            result[tostring(key)] = true
        end
    end
    return result
end

local function setToArray(set)
    local values = {}
    for key, enabled in pairs(set or {}) do
        if enabled == true then
            table.insert(values, key)
        end
    end
    table.sort(values)
    return values
end

local function titleCaseId(id)
    return tostring(id or ""):gsub("_", " "):gsub("(%l)(%w*)", function(a, b)
        return string.upper(a) .. b
    end)
end

local function getEggDisplayData(eggType)
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        return nil
    end

    local cost = (petConfig.getEggCost and petConfig.getEggCost(eggType)) or eggData.cost or 0
    return {
        name = eggData.name or titleCaseId(eggType),
        currency = eggData.currency or "coins",
        cost = math.max(0, tonumber(cost) or 0),
    }
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if value >= 1000000000 then
        return string.format("%.1fB", value / 1000000000)
    elseif value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    end
    return tostring(math.floor(value))
end

local function getCurrencyIcon(currency)
    if currency == "gems" then
        return "💎"
    elseif currency == "crystals" then
        return "🔮"
    end
    return "💰"
end

local function formatStopReason(stopReason)
    local labels = {
        currency = "out of currency",
        storage = "storage full",
        entitlement = "hatch limit",
        partial = "partial hatch",
        grant_failed = "grant issue",
        no_storage = "storage full",
    }
    return labels[stopReason] or tostring(stopReason or "")
end

local function isTerminalAutoStopReason(stopReason)
    return stopReason == "currency"
        or stopReason == "storage"
        or stopReason == "entitlement"
        or stopReason == "grant_failed"
        or stopReason == "partial"
end

local function formatAutoErrorStopReason(result)
    if type(result) ~= "table" then
        return nil
    end

    local labels = {
        insufficient_currency = "out of currency",
        no_storage = "storage full",
        too_far = "too far away",
        feature_locked = "locked feature",
        partial_not_allowed = "partial hatch unavailable",
        invalid_egg = "egg unavailable",
    }
    return labels[result.code]
end

local function getSelectedCostMultiplier()
    local hatching = getHatchingConfig()
    local shopStubs = hatching.shop_stubs or {}
    local golden = shopStubs.golden_mode or {}
    local charged = shopStubs.charged_mode or {}
    local multiplier = 1
    if hatchModeState.goldenMode == true then
        multiplier *= math.max(1, tonumber(golden.cost_multiplier) or 20)
    end
    if hatchModeState.chargedMode == true then
        multiplier *= math.max(1, tonumber(charged.cost_multiplier) or 5)
    end
    return multiplier
end

local function getFilterDisplayName(id)
    local petFamily = petConfig.pets and petConfig.pets[id]
    return (petConfig.rarities[id] and petConfig.rarities[id].name)
        or (petFamily and (petFamily.display_name or petFamily.name))
        or (petConfig.variants[id] and petConfig.variants[id].name)
        or titleCaseId(id)
end

function EggInteractionService:CreateButton(parent, name, text, size, position, color, callback)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = size
    button.Position = position
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextScaled = true
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    button.MouseButton1Click:Connect(function()
        if callback then
            callback()
        end
    end)

    return button
end

function EggInteractionService:SetPanelStatus(message, isError)
    if not hatchPanelFields.status then
        return
    end

    lastStatusAt = os.clock()
    hatchPanelFields.status.Text = tostring(message or "")
    hatchPanelFields.status.TextColor3 = isError and Color3.fromRGB(255, 150, 150)
        or Color3.fromRGB(170, 255, 210)
end

function EggInteractionService:SetHatchHelp(message)
    if not hatchPanelFields.helpText then
        return
    end

    local helpConfig = getHatchPanelHelpConfig()
    hatchPanelFields.helpText.Text = tostring(message or helpConfig.default or "")
end

function EggInteractionService:BindHelpText(instance, helpText)
    if not instance or not helpText or helpText == "" then
        return
    end

    instance:SetAttribute("HelpText", helpText)
    if instance.MouseEnter then
        instance.MouseEnter:Connect(function()
            self:SetHatchHelp(helpText)
        end)
    end
    if instance.MouseLeave then
        instance.MouseLeave:Connect(function()
            self:SetHatchHelp()
        end)
    end
    if instance.SelectionGained then
        instance.SelectionGained:Connect(function()
            self:SetHatchHelp(helpText)
        end)
    end
    if instance.SelectionLost then
        instance.SelectionLost:Connect(function()
            self:SetHatchHelp()
        end)
    end
end

function EggInteractionService:BindModeHelpText(instance, optionName, cfg)
    if not instance then
        return
    end

    instance:SetAttribute("HelpText", cfg.description or "")
    instance:SetAttribute("LockedHelpText", cfg.locked_description or "")
    instance:SetAttribute("ActiveHelpText", cfg.active_description or "")
    instance:SetAttribute("AvailableHelpText", cfg.available_description or "")
    if instance.MouseEnter then
        instance.MouseEnter:Connect(function()
            self:SetHatchHelp(getModeHelpText(optionName, cfg))
        end)
    end
    if instance.MouseLeave then
        instance.MouseLeave:Connect(function()
            self:SetHatchHelp()
        end)
    end
    if instance.SelectionGained then
        instance.SelectionGained:Connect(function()
            self:SetHatchHelp(getModeHelpText(optionName, cfg))
        end)
    end
    if instance.SelectionLost then
        instance.SelectionLost:Connect(function()
            self:SetHatchHelp()
        end)
    end
end

function EggInteractionService:CreateHatchPanel()
    if hatchPanelGui then
        hatchPanelGui:Destroy()
    end

    local panelConfig = getHatchPanelConfig()
    if panelConfig.enabled == false then
        return
    end

    local width = tonumber(panelConfig.width) or 500
    local height = tonumber(panelConfig.height) or 176
    local settingsHeight = tonumber(panelConfig.settings_height) or 168

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggHatchPanel"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = player.PlayerGui

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.Size = UDim2.new(0, width, 0, height)
    frame.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
    frame.BackgroundTransparency = 0.04
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(0, 210, 220)
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -24, 0, 30)
    title.Position = UDim2.new(0, 12, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "Egg"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local cost = Instance.new("TextLabel")
    cost.Name = "Cost"
    cost.Size = UDim2.new(0.52, -12, 0, 24)
    cost.Position = UDim2.new(0, 12, 0, 44)
    cost.BackgroundTransparency = 1
    cost.Text = ""
    cost.TextColor3 = Color3.fromRGB(205, 214, 230)
    cost.TextScaled = true
    cost.Font = Enum.Font.Gotham
    cost.TextXAlignment = Enum.TextXAlignment.Left
    cost.Parent = frame

    local countLabel = Instance.new("TextLabel")
    countLabel.Name = "Count"
    countLabel.Size = UDim2.new(0, 104, 0, 36)
    countLabel.Position = UDim2.new(0.52, 4, 0, 38)
    countLabel.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
    countLabel.BorderSizePixel = 0
    countLabel.Text = "x1"
    countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    countLabel.TextScaled = true
    countLabel.Font = Enum.Font.GothamBold
    countLabel.Parent = frame

    local countCorner = Instance.new("UICorner")
    countCorner.CornerRadius = UDim.new(0, 8)
    countCorner.Parent = countLabel

    self:CreateButton(
        frame,
        "CountDown",
        "-",
        UDim2.new(0, 42, 0, 36),
        UDim2.new(0.52, 112, 0, 38),
        Color3.fromRGB(72, 82, 103),
        function()
            local step = tonumber(panelConfig.count_step) or 1
            self:SetSelectedHatchCount(selectedHatchCount - step)
        end
    )
    self:CreateButton(
        frame,
        "CountUp",
        "+",
        UDim2.new(0, 42, 0, 36),
        UDim2.new(0.52, 158, 0, 38),
        Color3.fromRGB(72, 82, 103),
        function()
            local step = tonumber(panelConfig.count_step) or 1
            self:SetSelectedHatchCount(selectedHatchCount + step)
        end
    )

    local buttonY = 84
    local buttons = panelConfig.buttons or {}
    local help = getHatchPanelHelpConfig()
    local hatchButton = self:CreateButton(
        frame,
        "Hatch",
        buttons.hatch or "Hatch",
        UDim2.new(0, 112, 0, 38),
        UDim2.new(0, 12, 0, buttonY),
        Color3.fromRGB(31, 138, 255),
        function()
            self:HatchSelectedCount("Button")
        end
    )
    local maxButton = self:CreateButton(
        frame,
        "Max",
        buttons.max or "Max",
        UDim2.new(0, 96, 0, 38),
        UDim2.new(0, 132, 0, buttonY),
        Color3.fromRGB(72, 82, 103),
        function()
            self:OnMaxHatchKeyPressed()
        end
    )
    local autoButton = self:CreateButton(
        frame,
        "Auto",
        buttons.auto or "Auto",
        UDim2.new(0, 96, 0, 38),
        UDim2.new(0, 236, 0, buttonY),
        Color3.fromRGB(39, 161, 92),
        function()
            self:ToggleAutoHatch()
        end
    )
    local settingsButton = self:CreateButton(
        frame,
        "Settings",
        buttons.settings or "Filters",
        UDim2.new(0, 132, 0, 38),
        UDim2.new(1, -144, 0, buttonY),
        Color3.fromRGB(115, 85, 210),
        function()
            hatchSettingsOpen = not hatchSettingsOpen
            self:UpdateHatchPanel()
        end
    )
    self:BindHelpText(countLabel, help.count)
    self:BindHelpText(hatchButton, help.hatch)
    self:BindHelpText(maxButton, help.max)
    self:BindHelpText(autoButton, help.auto)
    self:BindHelpText(settingsButton, help.settings)

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Size = UDim2.new(1, -24, 0, 26)
    status.Position = UDim2.new(0, 12, 0, 132)
    status.BackgroundTransparency = 1
    status.Text = ""
    status.TextColor3 = Color3.fromRGB(170, 255, 210)
    status.TextScaled = true
    status.Font = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame

    local settings = Instance.new("Frame")
    settings.Name = "SettingsDrawer"
    settings.Size = UDim2.new(1, -24, 0, settingsHeight)
    settings.Position = UDim2.new(0, 12, 0, height - 4)
    settings.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
    settings.BorderSizePixel = 0
    settings.Visible = false
    settings.Parent = frame

    local settingsCorner = Instance.new("UICorner")
    settingsCorner.CornerRadius = UDim.new(0, 8)
    settingsCorner.Parent = settings

    hatchPanelGui = screenGui
    hatchPanel = frame
    hatchPanelFields = {
        title = title,
        cost = cost,
        count = countLabel,
        status = status,
        hatchButton = hatchButton,
        maxButton = maxButton,
        autoButton = autoButton,
        settingsButton = settingsButton,
        settings = settings,
        filterButtons = {},
        modeButtons = {},
    }

    self:CreateAutoDeleteSettings(settings)
    self:CreateModeSettings(settings)
    self:CreateHatchHelpText(settings)
    self:ApplyPersistedHatchModes({ persist = false })
    self:SetSelectedHatchCount(
        getPersistedSelectedHatchCount() or getDefaultSelectedHatchCount(),
        { persist = false }
    )
end

function EggInteractionService:CreateAutoDeleteSettings(parent)
    local panelConfig = getHatchPanelConfig()
    local filterConfig = panelConfig.auto_delete or {}

    local header = Instance.new("TextLabel")
    header.Name = "Header"
    header.Size = UDim2.new(1, -16, 0, 24)
    header.Position = UDim2.new(0, 8, 0, 8)
    header.BackgroundTransparency = 1
    header.Text = "Auto-delete"
    header.TextColor3 = Color3.fromRGB(255, 255, 255)
    header.TextScaled = true
    header.Font = Enum.Font.GothamBold
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = parent
    self:BindHelpText(header, filterConfig.description)

    local enabledButton = self:CreateButton(
        parent,
        "AutoDeleteEnabled",
        "Off",
        UDim2.new(0, 82, 0, 30),
        UDim2.new(1, -92, 0, 6),
        Color3.fromRGB(80, 85, 98),
        function()
            autoDeleteState.enabled = not autoDeleteState.enabled
            self:SendAutoDeleteFilters()
        end
    )
    hatchPanelFields.filterButtons.enabled = enabledButton
    self:BindHelpText(enabledButton, filterConfig.enabled_description)

    local y = 44
    self:CreateFilterRow(
        parent,
        "Rarities",
        filterConfig.rarity_filters or {},
        "rarities",
        y,
        filterConfig.rarity_description
    )
    self:CreateFilterRow(
        parent,
        "Pets",
        filterConfig.pet_type_filters or {},
        "pet_types",
        y + 58,
        filterConfig.pet_type_description
    )
    self:CreateFilterRow(
        parent,
        "Variants",
        filterConfig.variant_filters or {},
        "variants",
        y + 116,
        filterConfig.variant_description
    )
end

function EggInteractionService:CreateModeSettings(parent)
    local panelConfig = getHatchPanelConfig()
    local modeConfig = panelConfig.modes or {}
    local y = 218

    local label = Instance.new("TextLabel")
    label.Name = "ModesLabel"
    label.Size = UDim2.new(0, 74, 0, 28)
    label.Position = UDim2.new(0, 8, 0, y)
    label.BackgroundTransparency = 1
    label.Text = "Modes"
    label.TextColor3 = Color3.fromRGB(205, 214, 230)
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent

    local orderedModes = { "golden", "charged", "fast", "skip", "silent" }
    for index, key in ipairs(orderedModes) do
        local cfg = modeConfig[key]
        if cfg then
            local optionName = cfg.option or key
            local buttonWidth = 70
            local buttonGap = 76
            local button = self:CreateButton(
                parent,
                "Mode_" .. optionName,
                cfg.label or titleCaseId(key),
                UDim2.new(0, buttonWidth, 0, 28),
                UDim2.new(0, 88 + (index - 1) * buttonGap, 0, y),
                Color3.fromRGB(80, 85, 98),
                function()
                    self:SetHatchModeState(optionName, hatchModeState[optionName] ~= true)
                end
            )
            hatchPanelFields.modeButtons[optionName] = button
            button:SetAttribute("ModeOption", optionName)
            button:SetAttribute("ModeLabel", cfg.label or titleCaseId(key))
            self:BindModeHelpText(button, optionName, cfg)
        end
    end

    local modeStatus = Instance.new("TextLabel")
    modeStatus.Name = "ModeStatus"
    modeStatus.Size = UDim2.new(1, -16, 0, 26)
    modeStatus.Position = UDim2.new(0, 8, 0, y + 34)
    modeStatus.BackgroundTransparency = 1
    modeStatus.Text = ""
    modeStatus.TextColor3 = Color3.fromRGB(180, 190, 210)
    modeStatus.TextScaled = true
    modeStatus.TextWrapped = true
    modeStatus.Font = Enum.Font.Gotham
    modeStatus.TextXAlignment = Enum.TextXAlignment.Left
    modeStatus.Parent = parent
    hatchPanelFields.modeStatus = modeStatus
end

function EggInteractionService:CreateFilterRow(
    parent,
    labelText,
    filterIds,
    bucketName,
    y,
    helpText
)
    local label = Instance.new("TextLabel")
    label.Name = bucketName .. "Label"
    label.Size = UDim2.new(0, 74, 0, 28)
    label.Position = UDim2.new(0, 8, 0, y)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(205, 214, 230)
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    self:BindHelpText(label, helpText)

    hatchPanelFields.filterButtons[bucketName] = hatchPanelFields.filterButtons[bucketName] or {}
    for index, id in ipairs(filterIds) do
        local x = 88 + ((index - 1) % 4) * 92
        local row = math.floor((index - 1) / 4)
        local button = self:CreateButton(
            parent,
            bucketName .. "_" .. id,
            getFilterDisplayName(id),
            UDim2.new(0, 84, 0, 28),
            UDim2.new(0, x, 0, y + row * 32),
            Color3.fromRGB(80, 85, 98),
            function()
                autoDeleteState[bucketName] = autoDeleteState[bucketName] or {}
                autoDeleteState[bucketName][id] = autoDeleteState[bucketName][id] ~= true
                self:SendAutoDeleteFilters()
            end
        )
        hatchPanelFields.filterButtons[bucketName][id] = button
        self:BindHelpText(button, helpText)
    end
end

function EggInteractionService:CreateHatchHelpText(parent)
    local panelConfig = getHatchPanelConfig()
    local helpConfig = panelConfig.help or {}
    local helpText = Instance.new("TextLabel")
    helpText.Name = "HelpText"
    helpText.Size = UDim2.new(1, -16, 0, 42)
    helpText.Position =
        UDim2.new(0, 8, 0, math.max(252, (tonumber(panelConfig.settings_height) or 304) - 50))
    helpText.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
    helpText.BackgroundTransparency = 0.12
    helpText.BorderSizePixel = 0
    helpText.Text = tostring(helpConfig.default or "")
    helpText.TextColor3 = Color3.fromRGB(205, 214, 230)
    helpText.TextScaled = true
    helpText.TextWrapped = true
    helpText.Font = Enum.Font.Gotham
    helpText.TextXAlignment = Enum.TextXAlignment.Left
    helpText.Parent = parent

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = helpText

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = helpText

    hatchPanelFields.helpText = helpText
end

function EggInteractionService:SendAutoDeleteFilters()
    Signals.AutoDelete_SetFilters:FireServer({
        enabled = autoDeleteState.enabled == true,
        rarities = setToArray(autoDeleteState.rarities),
        pet_types = setToArray(autoDeleteState.pet_types),
        variants = setToArray(autoDeleteState.variants),
    })
    self:RefreshAutoDeleteButtons()
    self:SetPanelStatus("Filters saved", false)
end

function EggInteractionService:ApplyAutoDeleteStatus(status)
    if type(status) ~= "table" then
        return
    end

    autoDeleteState.enabled = status.enabled == true
    autoDeleteState.rarities = asSet(status.rarities)
    autoDeleteState.pet_types = asSet(status.pet_types)
    autoDeleteState.variants = asSet(status.variants)
    self:RefreshAutoDeleteButtons()
end

function EggInteractionService:RefreshAutoDeleteButtons()
    if not hatchPanelFields.filterButtons then
        return
    end

    local enabledButton = hatchPanelFields.filterButtons.enabled
    if enabledButton then
        enabledButton.Text = autoDeleteState.enabled and "On" or "Off"
        enabledButton.BackgroundColor3 = autoDeleteState.enabled and Color3.fromRGB(39, 161, 92)
            or Color3.fromRGB(80, 85, 98)
    end

    for bucketName, buttons in pairs(hatchPanelFields.filterButtons) do
        if type(buttons) == "table" then
            for id, button in pairs(buttons) do
                local enabled = autoDeleteState[bucketName]
                    and autoDeleteState[bucketName][id] == true
                button.BackgroundColor3 = enabled and Color3.fromRGB(220, 82, 95)
                    or Color3.fromRGB(80, 85, 98)
            end
        end
    end
end

function EggInteractionService:RefreshModeButtons()
    if not hatchPanelFields.modeButtons then
        return
    end

    local activeModes = {}
    local lockedModes = {}
    for optionName, button in pairs(hatchPanelFields.modeButtons) do
        local owned = isModeOwned(optionName)
        local enabled = hatchModeState[optionName] == true
        local label = button:GetAttribute("ModeLabel") or titleCaseId(optionName)
        if not owned then
            if enabled then
                hatchModeState[optionName] = false
            end
            button.BackgroundColor3 = Color3.fromRGB(58, 62, 76)
            button.TextColor3 = Color3.fromRGB(150, 158, 176)
            button:SetAttribute("ModeOwned", false)
            button:SetAttribute("ModeState", "locked")
            table.insert(lockedModes, label)
        else
            button.BackgroundColor3 = enabled and Color3.fromRGB(244, 172, 54)
                or Color3.fromRGB(80, 85, 98)
            button.TextColor3 = Color3.fromRGB(255, 255, 255)
            button:SetAttribute("ModeOwned", true)
            button:SetAttribute("ModeState", enabled and "active" or "available")
            if enabled then
                table.insert(activeModes, label)
            end
        end
        button:SetAttribute("CurrentHelpText", getModeHelpText(optionName))
    end

    if hatchPanelFields.modeStatus then
        local parts = {}
        if #activeModes > 0 then
            table.insert(parts, "Active: " .. table.concat(activeModes, ", "))
        end
        if #lockedModes > 0 then
            table.insert(parts, "Locked: " .. table.concat(lockedModes, ", "))
        end
        hatchPanelFields.modeStatus.Text = #parts > 0 and table.concat(parts, "  |  ")
            or "Modes available"
    end
end

function EggInteractionService:ApplyPersistedHatchModes(options)
    options = options or {}
    local persistedModes = getPersistedHatchModes()
    if not persistedModes then
        return
    end

    for optionName in pairs(hatchModeState) do
        if persistedModes[optionName] ~= nil then
            hatchModeState[optionName] = persistedModes[optionName] == true
        end
    end

    if options.persist ~= false then
        persistHatchModes()
    else
        lastPersistedHatchModesKey = hatchModesKey(currentHatchModes())
    end
    self:RefreshModeButtons()
    self:UpdateHatchPanel()
end

function EggInteractionService:SetHatchModeState(optionName, enabled, options)
    options = options or {}
    if hatchModeState[optionName] == nil then
        return false
    end

    hatchModeState[optionName] = enabled == true and isModeOwned(optionName)
    if options.persist ~= false then
        persistHatchModes()
    end
    self:RefreshModeButtons()
    self:UpdateHatchPanel()
    return true
end

function EggInteractionService:BuildHatchOptions()
    return {
        goldenMode = hatchModeState.goldenMode == true,
        chargedMode = hatchModeState.chargedMode == true,
        fastHatch = hatchModeState.fastHatch == true,
        skipHatch = hatchModeState.skipHatch == true,
        silentHatch = hatchModeState.silentHatch == true,
    }
end

function EggInteractionService:ApplyResolvedHatchOptions(options)
    if type(options) ~= "table" then
        return
    end

    for optionName in pairs(hatchModeState) do
        if options[optionName] ~= nil then
            hatchModeState[optionName] = options[optionName] == true
        end
    end
    persistHatchModes()
    self:RefreshModeButtons()
    self:UpdateHatchPanel()
end

function EggInteractionService:HandleHatchError(result)
    local message = result.message or "Purchase failed"
    if result.code == "feature_locked" then
        local lockedMode = result.details and result.details.mode
        if lockedMode and hatchModeState[lockedMode] ~= nil then
            hatchModeState[lockedMode] = false
        elseif hatchModeState.goldenMode == true then
            hatchModeState.goldenMode = false
        end
        persistHatchModes()
        self:RefreshModeButtons()
        self:UpdateHatchPanel()
        message = message .. " Turn off the locked mode or unlock it first."
    end

    self:ShowErrorMessage(message)
    self:SetPanelStatus(message, true)
end

function EggInteractionService:SetSelectedHatchCount(count, options)
    options = options or {}
    selectedHatchCount = clampSelectedCount(count)
    if options.persist ~= false then
        persistSelectedHatchCount(selectedHatchCount)
    end
    self:UpdateHatchPanel()
end

function EggInteractionService:HatchSelectedCount(purchaseType)
    if not currentTargetService then
        return false
    end

    local currentTarget = currentTargetService:GetCurrentTarget()
    if currentTarget == "None" or not currentTarget then
        self:SetPanelStatus("Move near an egg", true)
        return false
    end

    return self:HandleEggPurchase(currentTarget, selectedHatchCount, purchaseType or "Selected")
end

function EggInteractionService:UpdateHatchPanel()
    if not hatchPanel then
        return
    end

    local panelConfig = getHatchPanelConfig()
    local currentTarget = currentTargetService and currentTargetService:GetCurrentTarget() or "None"
    local visible = currentTarget ~= nil and currentTarget ~= "None"
    hatchPanel.Visible = visible
    if not visible then
        return
    end

    local effectiveMaxCount = getEffectiveMaxHatchCount()
    if selectedHatchCount > effectiveMaxCount then
        selectedHatchCount = effectiveMaxCount
    end

    local width = tonumber(panelConfig.width) or 500
    local baseHeight = tonumber(panelConfig.height) or 176
    local settingsHeight = tonumber(panelConfig.settings_height) or 168
    local height = hatchSettingsOpen and (baseHeight + settingsHeight) or baseHeight
    local bottomOffset = tonumber(panelConfig.bottom_offset) or 126

    hatchPanel.Size = UDim2.new(0, width, 0, height)
    hatchPanel.Position = UDim2.new(0.5, -math.floor(width / 2), 1, -bottomOffset - height)
    if hatchPanelFields.settings then
        hatchPanelFields.settings.Visible = hatchSettingsOpen
    end

    local eggData = getEggDisplayData(currentTarget)
    if eggData then
        local totalCost = eggData.cost * getSelectedCostMultiplier() * selectedHatchCount
        hatchPanelFields.title.Text = eggData.name
        hatchPanelFields.cost.Text = string.format(
            "%s %s %s",
            getCurrencyIcon(eggData.currency),
            formatNumber(totalCost),
            titleCaseId(eggData.currency)
        )
    end

    hatchPanelFields.count.Text = "x" .. tostring(selectedHatchCount)
    local busy = hatchRequestInFlight == true
    local autoOwned = isAutoHatchOwned()
    hatchPanelFields.hatchButton.Active = not busy
    hatchPanelFields.maxButton.Active = not busy
    hatchPanelFields.autoButton.Active = not busy
    hatchPanelFields.hatchButton.AutoButtonColor = not busy
    hatchPanelFields.maxButton.AutoButtonColor = not busy
    hatchPanelFields.autoButton.AutoButtonColor = not busy
    hatchPanelFields.hatchButton.BackgroundColor3 = busy and Color3.fromRGB(70, 76, 90)
        or Color3.fromRGB(31, 138, 255)
    hatchPanelFields.maxButton.BackgroundColor3 = busy and Color3.fromRGB(70, 76, 90)
        or Color3.fromRGB(72, 82, 103)
    hatchPanelFields.autoButton.Text = autoHatchEnabled and "Stop" or "Auto"
    hatchPanelFields.autoButton.BackgroundColor3 = busy and Color3.fromRGB(70, 76, 90)
        or autoHatchEnabled and Color3.fromRGB(220, 82, 95)
        or autoOwned and Color3.fromRGB(39, 161, 92)
        or Color3.fromRGB(58, 62, 76)
    hatchPanelFields.autoButton.TextColor3 = autoOwned and Color3.fromRGB(255, 255, 255)
        or Color3.fromRGB(150, 158, 176)
    hatchPanel:SetAttribute("MaxHatchCount", getMaxHatchCount())
    hatchPanel:SetAttribute("MaxEntitledHatchCount", effectiveMaxCount)
    hatchPanel:SetAttribute("AutoHatchOwned", autoOwned)
    hatchPanelFields.count:SetAttribute("MaxEntitledHatchCount", effectiveMaxCount)
    hatchPanelFields.maxButton:SetAttribute("MaxEntitledHatchCount", effectiveMaxCount)
    hatchPanelFields.autoButton:SetAttribute("ModeOwned", autoOwned)
    hatchPanelFields.autoButton:SetAttribute("ModeState", autoOwned and "available" or "locked")

    if os.clock() - lastStatusAt > (tonumber(panelConfig.status_display_time) or 3) then
        hatchPanelFields.status.Text = ""
    end
    self:RefreshAutoDeleteButtons()
    self:RefreshModeButtons()
end

-- === E KEY INTERACTION ===

function EggInteractionService:OnEKeyPressed()
    -- Get current target from the targeting service
    if not currentTargetService then
        Logger:Warn("CurrentTargetService not available", { context = "EggInteractionService" })
        return
    end

    local currentTarget = currentTargetService:GetCurrentTarget()
    if currentTarget == "None" or not currentTarget then
        Logger:Debug("No egg currently targeted", { context = "EggInteractionService" })
        return
    end

    Logger:Info("E pressed - attempting hatch", {
        context = "EggInteractionService",
        eggType = currentTarget,
        requestedCount = selectedHatchCount,
    })
    self:HandleEggPurchase(currentTarget, selectedHatchCount, "Selected")
end

function EggInteractionService:OnMaxHatchKeyPressed()
    if not currentTargetService then
        Logger:Warn("CurrentTargetService not available", { context = "EggInteractionService" })
        return
    end

    local currentTarget = currentTargetService:GetCurrentTarget()
    if currentTarget == "None" or not currentTarget then
        return
    end

    local maxCount = getEffectiveMaxHatchCount()
    self:SetSelectedHatchCount(maxCount)
    self:HandleEggPurchase(currentTarget, maxCount, "Max")
end

function EggInteractionService:ToggleAutoHatch()
    if autoHatchEnabled then
        autoHatchEnabled = false
        autoHatchSessionId += 1
        self:SetPanelStatus("Auto hatch stopped", false)
        self:UpdateHatchPanel()
        return
    end

    if not isAutoHatchOwned() then
        self:SetPanelStatus("Auto hatch locked", true)
        self:ShowErrorMessage("Auto hatch locked")
        self:UpdateHatchPanel()
        return
    end

    if not currentTargetService then
        Logger:Warn("CurrentTargetService not available", { context = "EggInteractionService" })
        return
    end

    local currentTarget = currentTargetService:GetCurrentTarget()
    if currentTarget == "None" or not currentTarget then
        self:SetPanelStatus("Move near an egg", true)
        return
    end

    autoHatchEnabled = true
    autoHatchSessionId += 1
    local sessionId = autoHatchSessionId
    local hatching = getHatchingConfig()
    local waitSeconds = tonumber(hatching.auto_loop_delay)
        or tonumber(eggSystemConfig.cooldowns.purchase_cooldown)
        or 3
    self:SetPanelStatus("Auto hatch running", false)
    self:UpdateHatchPanel()

    task.spawn(function()
        while autoHatchEnabled and sessionId == autoHatchSessionId do
            local target = currentTargetService:GetCurrentTarget()
            if target == "None" or not target then
                autoHatchEnabled = false
                self:SetPanelStatus("Auto hatch stopped: too far away", true)
                break
            end

            local ok = self:HandleEggPurchase(target, selectedHatchCount, "Auto", sessionId)
            if not ok then
                if autoHatchEnabled and sessionId == autoHatchSessionId then
                    autoHatchEnabled = false
                    self:SetPanelStatus("Auto hatch stopped", true)
                end
                break
            end

            task.wait(waitSeconds)
        end
        self:UpdateHatchPanel()
    end)
end

-- === EGG PURCHASE HANDLING ===

function EggInteractionService:HandleEggPurchase(
    eggType,
    requestedCount,
    purchaseType,
    autoSessionId
)
    if hatchRequestInFlight then
        self:ShowErrorMessage("Please wait before hatching again")
        return false
    end

    requestedCount = requestedCount or 1
    purchaseType = purchaseType or "Single"
    Logger:Info("Requesting egg hatch", {
        context = "EggInteractionService",
        eggType = eggType,
        requestedCount = requestedCount,
        purchaseType = purchaseType,
    })

    -- Validate egg type
    local eggData = petConfig.egg_sources[eggType]
    if not eggData then
        Logger:Warn("Invalid egg type", { context = "EggInteractionService", eggType = eggType })
        self:ShowErrorMessage("Invalid egg type")
        return false
    end

    -- Client-side distance check (like working game)
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        Logger:Warn("No character or root part", { context = "EggInteractionService" })
        self:ShowErrorMessage("Character not ready")
        return false
    end

    -- Find egg in workspace
    local eggInWorkspace = self:FindEggByType(eggType)
    if not eggInWorkspace then
        Logger:Warn("Egg not found in workspace", { context = "EggInteractionService" })
        self:ShowErrorMessage("Egg not found")
        return false
    end

    local anchor = EggWorldQuery.GetAnchor(eggInWorkspace)

    if not anchor then
        Logger:Warn("No anchor found on egg", { context = "EggInteractionService" })
        self:ShowErrorMessage("Egg configuration error")
        return false
    end

    local distance = (player.Character.HumanoidRootPart.Position - anchor.Position).Magnitude
    if distance > eggSystemConfig.proximity.max_distance then
        Logger:Info("Too far from egg", { context = "EggInteractionService", distance = distance })
        self:ShowErrorMessage(eggSystemConfig.messages.too_far_away)
        return false
    end

    Logger:Debug(
        "Distance check passed",
        { context = "EggInteractionService", distance = distance }
    )

    -- Call server using RemoteFunction (like working game)
    local eggRemote = ReplicatedStorage:FindFirstChild("EggOpened")
    if not eggRemote then
        Logger:Error("EggOpened RemoteFunction not found", { context = "EggInteractionService" })
        self:ShowErrorMessage("Server not ready, please restart game")
        return false
    end

    hatchRequestInFlight = true
    self:UpdateHatchPanel()
    local success, result, message = pcall(function()
        return eggRemote:InvokeServer({
            eggType = eggType,
            requestedCount = requestedCount,
            purchaseType = purchaseType,
            options = self:BuildHatchOptions(),
            autoSessionId = autoSessionId,
        })
    end)
    hatchRequestInFlight = false
    self:UpdateHatchPanel()

    if autoSessionId ~= nil and autoSessionId ~= autoHatchSessionId then
        return false
    end

    if success then
        Logger:Info(
            "Server call successful",
            { context = "EggInteractionService", resultType = typeof(result) }
        )
        if type(result) == "table" and result.success then
            Logger:Info("Purchase successful", { context = "EggInteractionService" })
            self:ApplyResolvedHatchOptions(result.options)
            self:ShowHatchingResults(result)
            local status = "Hatched " .. tostring(result.hatchCount or 1)
            if result.stopReason then
                status ..= " - " .. formatStopReason(result.stopReason)
            end
            if autoSessionId ~= nil and isTerminalAutoStopReason(result.stopReason) then
                autoHatchEnabled = false
                autoHatchSessionId += 1
                status = "Auto hatch stopped: " .. formatStopReason(result.stopReason)
            end
            self:SetPanelStatus(status, false)
            return true
        elseif type(result) == "table" and result.success == false then
            Logger:Warn("Purchase failed", {
                context = "EggInteractionService",
                message = result.message or "Purchase failed",
                code = result.code,
            })
            self:HandleHatchError(result)
            if autoSessionId ~= nil and autoSessionId == autoHatchSessionId then
                local stopReason = formatAutoErrorStopReason(result)
                if stopReason then
                    autoHatchEnabled = false
                    autoHatchSessionId += 1
                    self:SetPanelStatus("Auto hatch stopped: " .. stopReason, true)
                end
            end
            return false
        elseif result == "Error" then
            Logger:Warn(
                "Purchase failed",
                { context = "EggInteractionService", message = message or "Unknown error" }
            )
            self:ShowErrorMessage(message or "Purchase failed")
            self:SetPanelStatus(message or "Purchase failed", true)
            return false
        elseif type(result) == "table" and result.Pet then
            -- Handle successful result without explicit success flag
            Logger:Info(
                "Purchase successful (legacy format)",
                { context = "EggInteractionService" }
            )
            self:ShowHatchingResults(result)
            self:SetPanelStatus("Hatched 1", false)
            return true
        else
            Logger:Warn(
                "Unexpected result format",
                { context = "EggInteractionService", resultType = typeof(result) }
            )
            self:ShowErrorMessage("Unexpected server response")
            self:SetPanelStatus("Unexpected server response", true)
            return false
        end
    else
        Logger:Error(
            "Server call failed",
            { context = "EggInteractionService", error = tostring(result) }
        )
        self:ShowErrorMessage("Connection error")
        self:SetPanelStatus("Connection error", true)
        return false
    end
end

function EggInteractionService:FindEggByType(eggType)
    return EggWorldQuery.FindEggByType(eggType)
end

-- === UI FEEDBACK ===

function EggInteractionService:ShowErrorMessage(errorMessage)
    self:SetPanelStatus(errorMessage, true)

    -- Create simple error notification
    local errorGui = Instance.new("ScreenGui")
    errorGui.Name = "EggError"
    errorGui.ResetOnSpawn = false
    errorGui.Parent = player.PlayerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 80)
    frame.Position = UDim2.new(0.5, -150, 0.8, -40)
    frame.BackgroundColor3 = Color3.fromRGB(220, 53, 69)
    frame.BorderSizePixel = 0
    frame.Parent = errorGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 1, -10)
    label.Position = UDim2.new(0, 10, 0, 5)
    label.BackgroundTransparency = 1
    label.Text = "❌ " .. errorMessage
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.Parent = frame

    -- Slide in animation
    frame.Position = UDim2.new(0.5, -150, 1, 0)
    local tween = TweenService:Create(
        frame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(0.5, -150, 0.8, -40),
        }
    )
    tween:Play()

    -- Auto-remove after configured time
    task.spawn(function()
        task.wait(eggSystemConfig.cooldowns.ui_error_display_time)
        errorGui:Destroy()
    end)
end

function EggInteractionService:ShowHatchingResults(result)
    if type(result) == "table" and result.options and result.options.skipHatch == true then
        return
    end

    -- Reduce console noise: keep egg-related logs through Logger only
    local activeLogger = self._modules and self._modules.Logger
    if activeLogger and activeLogger.Info then
        activeLogger:Info("Hatched pet", {
            pet = result.Pet,
            variant = result.Type,
            power = result.Power,
            hatchCount = result.hatchCount or 1,
        })
    end

    -- Use the full egg hatching animation system instead of simple notification
    local success, hatchingService = pcall(function()
        return require(ReplicatedStorage.Shared.Services.EggHatchingService)
    end)

    if success and hatchingService then
        -- Prepare egg data for animation. Batch responses carry one entry per egg;
        -- legacy single-hatch responses still flow through the same path.
        local eggsData = {}
        local resultEntries = type(result.results) == "table" and result.results or { result }
        for _, entry in ipairs(resultEntries) do
            local eggType = entry.EggType or result.EggType or "basic_egg"
            table.insert(eggsData, {
                petType = entry.Pet or entry.pet,
                variant = entry.Type or entry.variant,
                power = entry.Power or entry.power,
                eggType = eggType,
                imageId = self:GetEggImageId(eggType),
                petImageId = self:GetPetImageId(
                    entry.Pet or entry.pet,
                    entry.Type or entry.variant
                ),
                animation = result.animation,
                hatchOptions = result.options,
                rarityId = entry.RarityId or entry.rarityId,
                rarityName = entry.RarityName or entry.rarityName,
                specialHatch = entry.SpecialHatch == true or entry.specialHatch == true,
                autoDeleted = entry.AutoDeleted or entry.autoDeleted,
                autoDeleteReason = entry.AutoDeleteReason or entry.autoDeleteReason,
            })
        end

        -- Start the hatching animation (uses persistent reusable GUI)
        if activeLogger and activeLogger.Info then
            activeLogger:Info(
                "Starting egg hatching animation",
                { pet = result.Pet, variant = result.Type, hatchCount = #eggsData }
            )
        end
        hatchingService:StartHatchingAnimation(eggsData)
        if activeLogger and activeLogger.Info then
            activeLogger:Info("Hatching animation started (persistent GUI)")
        end
    else
        -- Fallback to simple notification if animation service fails
        warn("Failed to load EggHatchingService, falling back to simple notification")
        self:ShowSimpleHatchingNotification(result)
    end
end

-- Fallback simple notification (moved from original function)
function EggInteractionService:ShowSimpleHatchingNotification(result)
    local successGui = Instance.new("ScreenGui")
    successGui.Name = "HatchingSuccess"
    successGui.ResetOnSpawn = false
    successGui.Parent = player.PlayerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 120)
    frame.Position = UDim2.new(0.5, -200, 0.5, -60)
    frame.BackgroundColor3 = Color3.fromRGB(34, 139, 34)
    frame.BorderSizePixel = 0
    frame.Parent = successGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0.5, 0)
    title.Position = UDim2.new(0, 10, 0, 5)
    title.BackgroundTransparency = 1
    title.Text = "🎉 EGG HATCHED!"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = frame

    local details = Instance.new("TextLabel")
    details.Size = UDim2.new(1, -20, 0.5, 0)
    details.Position = UDim2.new(0, 10, 0.5, 0)
    details.BackgroundTransparency = 1
    details.Text = result.Type .. " " .. result.Pet .. " (Power: " .. result.Power .. ")"
    details.TextColor3 = Color3.fromRGB(255, 255, 255)
    details.TextScaled = true
    details.Font = Enum.Font.Gotham
    details.Parent = frame

    -- Auto-remove after configured time
    task.spawn(function()
        task.wait(eggSystemConfig.cooldowns.success_notification_time)
        successGui:Destroy()
    end)
end

-- Helper functions to get image IDs for animations
function EggInteractionService:GetEggImageId(eggType)
    -- Try to get egg image from generated assets
    local success, imageId = pcall(function()
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        if assetsFolder then
            local imagesFolder = assetsFolder:FindFirstChild("Images")
            if imagesFolder then
                local eggsFolder = imagesFolder:FindFirstChild("Eggs")
                if eggsFolder then
                    local eggImage = eggsFolder:FindFirstChild(eggType)
                    if eggImage then
                        return "generated_image" -- Special flag for cloned ViewportFrame
                    end
                end
            end
        end
        return "rbxasset://textures/face.png" -- Fallback
    end)

    return success and imageId or "rbxasset://textures/face.png"
end

function EggInteractionService:GetPetImageId(petType, variant)
    -- Try to get pet image from generated assets
    local success, imageId = pcall(function()
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
                            return "generated_image" -- Special flag for cloned ViewportFrame
                        end
                    end
                end
            end
        end
        return "rbxasset://textures/face.png" -- Fallback
    end)

    return success and imageId or "rbxasset://textures/face.png"
end

-- === INITIALIZATION ===

function EggInteractionService:Initialize()
    Logger:Info("Initializing with CurrentTarget system", { context = "EggInteractionService" })

    -- Get reference to CurrentTargetService
    local success, currentTargetServiceOrError = pcall(function()
        return require(ReplicatedStorage.Shared.Services.EggCurrentTargetService)
    end)

    if success then
        currentTargetService = currentTargetServiceOrError
        Logger:Info("Got CurrentTargetService reference", { context = "EggInteractionService" })
    else
        Logger:Error(
            "Failed to get CurrentTargetService",
            { error = tostring(currentTargetServiceOrError) }
        )
        return
    end

    self:CreateHatchPanel()

    for _, attributeName in ipairs({
        "MaxEggHatchCount",
        "AutoHatchUnlocked",
        "GoldenHatchUnlocked",
        "ChargedHatchUnlocked",
        "FastHatchUnlocked",
        "SkipHatchUnlocked",
    }) do
        table.insert(
            entitlementConnections,
            player:GetAttributeChangedSignal(attributeName):Connect(function()
                self:SetSelectedHatchCount(selectedHatchCount, { persist = false })
                self:RefreshModeButtons()
                self:UpdateHatchPanel()
            end)
        )
    end

    Signals.AutoTarget_Status.OnClientEvent:Connect(function(status)
        if type(status) == "table" then
            self:ApplyAutoDeleteStatus(status.auto_delete)
        end
    end)

    local updateAccumulator = 0
    hatchPanelConnection = RunService.Heartbeat:Connect(function(step)
        updateAccumulator += step
        if updateAccumulator >= 0.12 then
            updateAccumulator = 0
            self:UpdateHatchPanel()
        end
    end)

    -- Set up E key listening (only when not typing)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard then
            if UserInputService:GetFocusedTextBox() ~= nil then
                return
            end

            if input.KeyCode == eggSystemConfig.proximity.interaction_key then
                self:OnEKeyPressed()
            elseif input.KeyCode == eggSystemConfig.proximity.hatch_max_key then
                self:OnMaxHatchKeyPressed()
            elseif input.KeyCode == eggSystemConfig.proximity.auto_hatch_key then
                self:ToggleAutoHatch()
            end
        end
    end)

    Logger:Info("Initialized with E key listening", { context = "EggInteractionService" })
end

function EggInteractionService:GetHatchPanelDebugState()
    return {
        autoHatchEnabled = autoHatchEnabled == true,
        autoHatchSessionId = autoHatchSessionId,
        autoHatchOwned = isAutoHatchOwned(),
        selectedHatchCount = selectedHatchCount,
        persistedSelectedHatchCount = getPersistedSelectedHatchCount(),
        hatchModes = currentHatchModes(),
        persistedHatchModes = getPersistedHatchModes(),
        maxHatchCount = getMaxHatchCount(),
        maxEntitledHatchCount = getEffectiveMaxHatchCount(),
        statusText = hatchPanelFields.status and hatchPanelFields.status.Text or "",
        helpText = hatchPanelFields.helpText and hatchPanelFields.helpText.Text or "",
        modeStatus = hatchPanelFields.modeStatus and hatchPanelFields.modeStatus.Text or "",
        settingsOpen = hatchSettingsOpen == true,
    }
end

function EggInteractionService:Destroy()
    if hatchPanelConnection then
        hatchPanelConnection:Disconnect()
        hatchPanelConnection = nil
    end
    for _, connection in ipairs(entitlementConnections) do
        connection:Disconnect()
    end
    entitlementConnections = {}
    if hatchPanelGui then
        hatchPanelGui:Destroy()
        hatchPanelGui = nil
        hatchPanel = nil
        hatchPanelFields = {}
    end
end

return EggInteractionService
