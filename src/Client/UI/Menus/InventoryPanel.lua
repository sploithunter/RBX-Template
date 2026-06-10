--[[
    InventoryPanel - Professional Pet Simulator Style Inventory
    
    Features:
    - Grid layout with item cards
    - Search functionality
    - Category filtering
    - Professional visual design with gradients and shadows
    - Hover effects and animations
    - Item rarity indicators
    - Responsive design
    
    Usage:
    local InventoryPanel = require(script.InventoryPanel)
    local inventory = InventoryPanel.new()
    MenuManager:RegisterPanel("Inventory", inventory)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

-- #179 down-lockout: pill ring assets (white = available, red = locked) for the equipped view.
local PILL_UI = require(ReplicatedStorage.Configs:WaitForChild("pill_ui"))

local function lockoutFormatTime(sec)
    sec = math.max(0, math.ceil(sec))
    if sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
    end
    return sec .. "s"
end

-- Silence verbose raw debug prints (right-click / card-size / context-menu chatter that
-- fired on every interaction). Real logging goes through self.logger (gated by the
-- "InventoryPanel" level in configs/logging.lua); warn()/error() still surface. Toggle for
-- local debugging.
local __RAW_PRINT = print
local __PRINT_ENABLED = false
local function print(...)
    if __PRINT_ENABLED then
        __RAW_PRINT(...)
    end
end

-- Get shared modules
local Locations = require(ReplicatedStorage.Shared.Locations)
local ConfigLoader = require(ReplicatedStorage.Shared.ConfigLoader)
-- Single source of truth for configured base power (huge-aware), shared with the
-- server so the displayed power matches the power that mines/fights.
local PetPower = require(ReplicatedStorage.Shared.Game.PetPower)
local PetBadge = require(script.Parent.Parent.PetBadge)
-- Two-number card display (⛏ mining / ⚔ combat) — assembles the PetPower profile from config.
local petPowerViewOk, PetPowerView = pcall(function()
    return require(ReplicatedStorage.Shared.Game.PetPowerView)
end)
if not petPowerViewOk then
    PetPowerView = nil
end
-- Universal archetype badge (element disc + tinted ring). Optional: falls back to the text chip.
local petBadgeOk, PetBadge = pcall(function()
    return require(script.Parent.Parent.PetBadge)
end)
if not petBadgeOk then
    PetBadge = nil
end
-- Icon registry + support-aura config, for the "this pet provides X" badge on the card.
local powerIconsOk, POWER_ICONS = pcall(function()
    return require(ReplicatedStorage.Configs:WaitForChild("power_icons"))
end)
if not powerIconsOk then
    POWER_ICONS = nil
end
local petRolesOk, PET_ROLES = pcall(function()
    return require(ReplicatedStorage.Configs:WaitForChild("pet_roles"))
end)
if not petRolesOk then
    PET_ROLES = nil
end
-- Support-aura kind -> { biome element for the disc colour, human label }.
local SUPPORT_META = {
    heal = { element = "earth", label = "Heal" },
    defense = { element = "ice", label = "Defense" },
    offense = { element = "fire", label = "Offense" },
    yield = { element = "desert", label = "Coin Yield" },
    luck = { element = "earth", label = "Luck" }, -- bunny's lucky-rabbit aura (Grass)
}
local petVisualsOk, PetVariantVisuals = pcall(function()
    return require(ReplicatedStorage.Shared.Services.PetVariantVisuals)
end)

local function getAssetTransform(petData)
    if type(petData and petData.asset_transform) ~= "table" then
        return {}
    end

    local transform = petData.asset_transform
    local orientation = type(transform.orientation) == "table" and transform.orientation or {}
    return {
        scale = tonumber(transform.scale) or 1,
        hugeScale = tonumber(transform.huge_scale or transform.hugeScale) or 1,
        orientation = {
            x = tonumber(orientation.x) or 0,
            y = tonumber(orientation.y) or 0,
            z = tonumber(orientation.z) or 0,
        },
    }
end

local function applyUnbakedAssetTransform(model, transform)
    if not model or not model:IsA("Model") or type(transform) ~= "table" then
        return
    end

    if model:GetAttribute("AssetScale") ~= nil then
        return
    end

    if transform.scale and transform.scale > 0 and math.abs(transform.scale - 1) > 0.001 then
        pcall(function()
            model:ScaleTo(transform.scale)
        end)
    end

    local orientation = transform.orientation or {}
    local orientationCF = CFrame.Angles(
        math.rad(orientation.x or 0),
        math.rad(orientation.y or 0),
        math.rad(orientation.z or 0)
    )
    if orientationCF ~= CFrame.identity then
        pcall(function()
            model:PivotTo(orientationCF)
        end)
    end
end

local function getCameraDirection(cameraConfig)
    local angleY = math.rad(tonumber(cameraConfig and cameraConfig.angle_y) or 0)
    local angleX = math.rad(tonumber(cameraConfig and cameraConfig.angle_x) or 180)
    return Vector3.new(
        math.sin(angleY) * math.cos(angleX),
        math.sin(angleX),
        math.cos(angleY) * math.cos(angleX)
    )
end

-- Load Logger with wrapper
local LoggerWrapper
local loggerSuccess, loggerResult = pcall(function()
    return require(Locations.Logger)
end)

if loggerSuccess and loggerResult then
    LoggerWrapper = {
        new = function(name)
            return {
                info = function(self, ...)
                    loggerResult:Info("[" .. name .. "] " .. tostring((...)), { context = name })
                end,
                warn = function(self, ...)
                    loggerResult:Warn("[" .. name .. "] " .. tostring((...)), { context = name })
                end,
                error = function(self, ...)
                    loggerResult:Error("[" .. name .. "] " .. tostring((...)), { context = name })
                end,
                debug = function(self, ...)
                    loggerResult:Debug("[" .. name .. "] " .. tostring((...)), { context = name })
                end,
            }
        end,
    }
else
    LoggerWrapper = {
        new = function(name)
            return {
                info = function(self, ...)
                    print("[" .. name .. "] INFO:", ...)
                end,
                warn = function(self, ...)
                    warn("[" .. name .. "] WARN:", ...)
                end,
                error = function(self, ...)
                    warn("[" .. name .. "] ERROR:", ...)
                end,
                debug = function(self, ...)
                    print("[" .. name .. "] DEBUG:", ...)
                end,
            }
        end,
    }
end

-- Load UI config
local uiConfig
local configSuccess, configResult = pcall(function()
    return Locations.getConfig("ui")
end)

if configSuccess and configResult then
    uiConfig = configResult
else
    -- Enhanced fallback config
    uiConfig = {
        active_theme = "dark",
        themes = {
            dark = {
                primary = {
                    background = Color3.fromRGB(25, 25, 30),
                    surface = Color3.fromRGB(35, 35, 45),
                    accent = Color3.fromRGB(52, 152, 219),
                },
                text = {
                    primary = Color3.fromRGB(255, 255, 255),
                    secondary = Color3.fromRGB(200, 200, 210),
                },
            },
        },
        helpers = {
            get_theme = function(config)
                return config.themes.dark
            end,
        },
        defaults = {
            panel = {
                header = {
                    close_button = {
                        icon = "89257673063270",
                        size = { width = 30, height = 30 },
                        offset = { x = 10, y = -10 },
                        background_color = Color3.fromRGB(220, 60, 60),
                        hover_color = Color3.fromRGB(180, 40, 40),
                        corner_radius = 8,
                    },
                },
            },
        },
    }
end

local InventoryPanel = {}
InventoryPanel.__index = InventoryPanel

function InventoryPanel.new()
    local self = setmetatable({}, InventoryPanel)

    self.logger = LoggerWrapper.new("InventoryPanel")

    -- Load inventory configuration
    local success, result = pcall(function()
        return ConfigLoader:LoadConfig("inventory")
    end)

    if success then
        self.inventoryConfig = result
        self.logger:info("📁 INVENTORY CONFIG LOADED", {
            hasDisplayCategories = self.inventoryConfig.display_categories ~= nil,
            categoryCount = self.inventoryConfig.display_categories
                    and #self.inventoryConfig.display_categories
                or 0,
            hasCategorySettings = self.inventoryConfig.category_settings ~= nil,
        })
    else
        self.logger:error("❌ FAILED TO LOAD INVENTORY CONFIG", { error = result })
        self.inventoryConfig = nil
    end

    -- Configurable card sizing (with safe defaults)
    self.cardSize = Vector2.new(45, 45)
    self.cardPadding = Vector2.new(8, 8)

    -- Prefer UI.lua settings if present (hot-reload in Studio for live tuning)
    pcall(function()
        if game:GetService("RunService"):IsStudio() then
            ConfigLoader:ReloadConfig("ui")
        end
    end)
    local okUI, uiConfig = pcall(function()
        return ConfigLoader:LoadConfig("ui")
    end)
    local uiAppliedSize = false
    local uiAppliedPadding = false
    if
        okUI
        and uiConfig
        and uiConfig.panel_configs
        and uiConfig.panel_configs.inventory_panel
        and uiConfig.panel_configs.inventory_panel.grid
    then
        local invGrid = uiConfig.panel_configs.inventory_panel.grid
        if invGrid.card_size and typeof(invGrid.card_size) == "Vector2" then
            self.cardSize = invGrid.card_size
            uiAppliedSize = true
        end
        if invGrid.card_padding and typeof(invGrid.card_padding) == "Vector2" then
            self.cardPadding = invGrid.card_padding
            uiAppliedPadding = true
        end
    end

    -- Fallback to inventory.lua overrides
    local invUi = self.inventoryConfig and self.inventoryConfig.ui
    if invUi and typeof(invUi) == "table" then
        if (not uiAppliedSize) and invUi.card_size and typeof(invUi.card_size) == "Vector2" then
            self.cardSize = invUi.card_size
        end
        if
            not uiAppliedPadding
            and invUi.card_padding
            and typeof(invUi.card_padding) == "Vector2"
        then
            self.cardPadding = invUi.card_padding
        end
    end

    -- Load context menu configuration
    local contextSuccess, contextResult = pcall(function()
        return ConfigLoader:LoadConfig("context_menus")
    end)

    if contextSuccess then
        self.contextMenuConfig = contextResult
        self.logger:info("🖱️ CONTEXT MENU CONFIG LOADED", {
            hasItemTypes = self.contextMenuConfig.item_types ~= nil,
            itemTypeCount = self.contextMenuConfig.item_types
                    and #self.contextMenuConfig.item_types
                or 0,
        })
    else
        self.logger:error("❌ FAILED TO LOAD CONTEXT MENU CONFIG", { error = contextResult })
        self.contextMenuConfig = nil
    end

    -- Panel state
    self.isVisible = false
    self.frame = nil
    self.searchBox = nil
    self.itemsGrid = nil
    self.itemFrames = {}
    self.selectedCategory = "All"
    self.searchTerm = ""

    -- Initialize with empty data - will be populated from real inventory
    self.inventoryData = {}

    -- Get reference to player for inventory access
    self.player = Players.LocalPlayer

    -- Initialize networking
    self.signals = nil
    self:_initializeNetworking()

    return self
end

function InventoryPanel:Show(parent)
    if self.isVisible then
        return
    end

    self:_createUI(parent)
    self:_loadRealInventoryData() -- Load real data first
    self:_updateItemsDisplay() -- Update items display with real data
    self:_refreshCategoryTabs() -- Update category tabs with real counts (after data is loaded)
    self:_setupEquippedFolderListeners() -- Listen for equipped changes
    self:SetupRealTimeUpdates() -- Listen for inventory changes

    self.isVisible = true
    -- #179: tick the availability rings / red counts while the window is open (timers count down).
    task.spawn(function()
        while self.isVisible do
            pcall(function()
                self:_refreshLockoutVisuals()
            end)
            task.wait(0.5)
        end
    end)
    self.logger:info("Professional inventory panel shown")
end

-- Decode the lockout pool replicated by EnemyService (a JSON player attribute), or nil.
function InventoryPanel:_decodeLockouts()
    local raw = self.player and self.player:GetAttribute("PetLockouts")
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    return ok and type(decoded) == "table" and decoded or nil
end

-- Paint a pill RING on an equipped card: white = available, red = locked/recovering (+ timer).
-- The availability ring is a BORDER (transparent center), not a filled overlay — so the PET stays
-- visible inside it. White stroke = available, red = locked/recovering; a small timer chip sits at
-- the BOTTOM (never over the pet's face). (Earlier this drew a filled pill on top of the card, which
-- covered the pet with a solid block — a pure layering bug.)
function InventoryPanel:_applyAvailabilityRing(frame, lockUntil, now)
    local ring = frame:FindFirstChild("AvailRing")
    local timer = frame:FindFirstChild("AvailTimer")
    if not ring then
        -- Jason's pill_frame art is a hollow ring (transparent center). Sit it BEHIND the card (low
        -- ZIndex) and slightly oversized, so only the ring's border frames the card from behind — the
        -- pet/card content draws on top and is never clipped or covered by the ring.
        ring = Instance.new("ImageLabel")
        ring.Name = "AvailRing"
        ring.BackgroundTransparency = 1
        ring.AnchorPoint = Vector2.new(0.5, 0.5)
        ring.Position = UDim2.fromScale(0.5, 0.5)
        ring.Size = UDim2.fromScale(1.2, 1.2)
        ring.ScaleType = Enum.ScaleType.Stretch
        ring.ZIndex = 0
        ring.Parent = frame
        timer = Instance.new("TextLabel")
        timer.Name = "AvailTimer"
        timer.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
        timer.BackgroundTransparency = 0.15
        timer.AnchorPoint = Vector2.new(0.5, 1)
        timer.Position = UDim2.fromScale(0.5, 0.97) -- bottom edge, clear of the pet
        timer.Size = UDim2.fromOffset(46, 18)
        timer.Font = Enum.Font.GothamBlack
        timer.TextSize = 12
        timer.TextColor3 = Color3.fromRGB(255, 255, 255)
        timer.ZIndex = 122
        local tc = Instance.new("UICorner")
        tc.CornerRadius = UDim.new(0, 6)
        tc.Parent = timer
        timer.Parent = frame
    end
    local locked = lockUntil ~= nil
    ring.Visible = true
    ring.Image = locked and PILL_UI.slot_locked or PILL_UI.slot_available -- ruby ring / neutral ring
    timer.Visible = locked
    timer.Text = locked and lockoutFormatTime(lockUntil - now) or ""
end

-- Draw a blank ring for every UNLOCKED-but-empty equip slot, so the row always shows how many slots
-- you have (filled cards + blank rings = total slots). Count comes from the replicated PetEquipSlots.
function InventoryPanel:_renderEmptySlotRings(filledCount)
    local total = tonumber(self.player and self.player:GetAttribute("PetEquipSlots")) or 0
    if total <= filledCount then
        return
    end
    for i = filledCount + 1, total do
        -- The open slot IS the neutral pill_frame (hollow ring) over a faint dark canvas, so it
        -- reads as an empty version of a filled slot.
        local ring = Instance.new("ImageLabel")
        ring.Name = "EmptySlotRing"
        ring.Size = UDim2.new(0, self.cardSize.X, 0, self.cardSize.Y)
        ring.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
        ring.BackgroundTransparency = 0.35 -- faint canvas inside the hole
        ring.BorderSizePixel = 0
        ring.Image = PILL_UI.slot_available -- neutral (white) ring = an open, available slot
        ring.ImageTransparency = 0.25
        ring.ScaleType = Enum.ScaleType.Stretch
        ring.LayoutOrder = i
        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 10)
        rc.Parent = ring
        ring.Parent = self.equippedGrid
    end
end

-- Hide any ring/timer on a card (an inventory pet that's fully available stays clean).
function InventoryPanel:_clearAvailabilityRing(frame)
    local ring = frame:FindFirstChild("AvailRing")
    local timer = frame:FindFirstChild("AvailTimer")
    if ring then
        ring.Visible = false
    end
    if timer then
        timer.Visible = false
    end
end

-- Read the LIVE deployed pet models (same source the squad HUD reads) so an EQUIPPED card reflects
-- whether its pet can actually be SUMMONED right now. _enforceLockouts stamps SlotLockUntil (the
-- 1-min slot hold) and CooldownUntil (down / 5-min identity) on every live pet — so a re-equipped pet
-- sitting in a still-recovering slot carries SlotLockUntil > now and its card stays RED until it's
-- summonable, instead of going white the moment it's re-slotted.
function InventoryPanel:_deployedLocks(now)
    local byUid, byKey = {}, {}
    local pp = Workspace:FindFirstChild("PlayerPets")
    local folder = pp and self.player and pp:FindFirstChild(self.player.Name)
    if not folder then
        return byUid, byKey
    end
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") then
            local until_ = math.max(
                tonumber(m:GetAttribute("SlotLockUntil")) or 0,
                tonumber(m:GetAttribute("CooldownUntil")) or 0
            )
            if until_ > now then
                local uid = m:GetAttribute("LockoutUid")
                local key = m:GetAttribute("LockoutKey")
                if uid then
                    byUid[uid] = math.max(byUid[uid] or 0, until_)
                end
                if key then
                    byKey[key] = byKey[key] or {}
                    table.insert(byKey[key], until_)
                end
            end
        end
    end
    for _, list in pairs(byKey) do
        table.sort(list, function(a, b)
            return a > b
        end)
    end
    return byUid, byKey
end

-- Repaint every card's lockout overlay from the decoded pool. Equipped cards get the ring; an
-- inventory STACK whose available count is reduced shows its count in RED.
function InventoryPanel:_refreshLockoutVisuals()
    local frames = self.itemFrames
    if type(frames) ~= "table" then
        return
    end
    local map = self:_decodeLockouts()
    local now = os.time()
    -- active recovering count per stack key (consumed greedily by equipped ghosts of that key)
    local stackActive = {}
    if map and type(map.stacks) == "table" then
        for key, list in pairs(map.stacks) do
            local active = {}
            if type(list) == "table" then
                for _, t in ipairs(list) do
                    if t > now then
                        active[#active + 1] = t
                    end
                end
            end
            table.sort(active, function(a, b)
                return a > b
            end)
            if #active > 0 then
                stackActive[key] = active
            end
        end
    end
    local depUid, depKey = self:_deployedLocks(now)
    local depKeyUsed = {}
    local stackUsed = {}
    for _, frame in ipairs(frames) do
        if frame and frame.Parent then
            local kind = frame:GetAttribute("LockKind")
            local lid = frame:GetAttribute("LockId")
            local equipped = frame:GetAttribute("LockEquipped") == true
            local lockUntil
            local recovering = 0
            if kind == "special" and lid and map and type(map.pets) == "table" then
                local u = map.pets[lid]
                if type(u) == "number" and u > now then
                    lockUntil = u
                end
            elseif kind == "stack" and lid then
                local active = stackActive[lid]
                recovering = active and #active or 0
                if equipped and active then
                    local used = stackUsed[lid] or 0
                    if used < #active then
                        lockUntil = active[used + 1]
                        stackUsed[lid] = used + 1
                    end
                end
            end
            if equipped and kind then
                -- An equipped pet's REAL state is on its live model (slot + identity holds). Prefer
                -- that over the replicated pool so a re-equipped pet stays red until summonable; fall
                -- back to the pool value if the model isn't found.
                local depUntil
                if kind == "special" and lid then
                    depUntil = depUid[lid]
                elseif kind == "stack" and lid and depKey[lid] then
                    local used = depKeyUsed[lid] or 0
                    if used < #depKey[lid] then
                        depUntil = depKey[lid][used + 1]
                        depKeyUsed[lid] = used + 1
                    end
                end
                lockUntil = depUntil or lockUntil
                -- equipped slot: always ring it (white = available, red = recovering + timer)
                self:_applyAvailabilityRing(frame, lockUntil, now)
            elseif kind == "special" then
                -- inventory HUGE: a unique pet on its 5-min uid lockout is NOT deployable even though
                -- the slot is free — show the red ring + timer so you don't try to re-deploy it; an
                -- available huge stays clean.
                if lockUntil then
                    self:_applyAvailabilityRing(frame, lockUntil, now)
                else
                    self:_clearAvailabilityRing(frame)
                end
            elseif kind == "stack" then
                -- inventory stack: red the count label when some are recovering (reduced availability)
                local countLbl = frame:FindFirstChild("QtyLabel")
                if countLbl and countLbl:IsA("TextLabel") then
                    countLbl.TextColor3 = recovering > 0 and Color3.fromRGB(235, 70, 70)
                        or Color3.fromRGB(255, 255, 255)
                end
            end
        end
    end
end

function InventoryPanel:Hide()
    if not self.isVisible then
        return
    end

    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end

    self.itemFrames = {}
    self.isVisible = false
    self.logger:info("Inventory panel hidden")
end

function InventoryPanel:_createUI(parent)
    local theme = uiConfig.helpers.get_theme(uiConfig)

    -- Create image-based panel using BaseUI system (like Settings panel)
    local BaseUI = require(script.Parent.Parent.BaseUI)
    local baseUI = BaseUI.new()

    -- Create professional image-based inventory panel
    local panelResult = baseUI:CreateImagePanel("inventory_panel", {
        size = UDim2.new(0.8, 0, 0.85, 0),
        position = UDim2.new(0.5, 0, 0.5, 0),
        anchor_point = Vector2.new(0.5, 0.5),
    }, parent)

    self.frame = panelResult.panel
    self.frame.Name = "InventoryPanel"
    self.frame.Size = UDim2.new(0.8, 0, 0.85, 0)
    self.frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    self.frame.AnchorPoint = Vector2.new(0.5, 0.5)

    -- Store references
    self.header = panelResult.header
    self.content = panelResult.content
    self.baseUI = baseUI

    -- Add close button to header if it exists (same as Settings panel)
    if self.header then
        -- Get close button config from global defaults with safety checks
        local config = nil
        if
            uiConfig
            and uiConfig.defaults
            and uiConfig.defaults.panel
            and uiConfig.defaults.panel.header
            and uiConfig.defaults.panel.header.close_button
        then
            config = uiConfig.defaults.panel.header.close_button
        else
            -- Fallback configuration if config not found
            config = {
                icon = "89257673063270",
                size = { width = 30, height = 30 },
                offset = { x = 10, y = -10 },
                background_color = Color3.fromRGB(220, 60, 60),
                hover_color = Color3.fromRGB(180, 40, 40),
                corner_radius = 8,
            }
            self.logger:warn("Close button config not found, using fallback")
        end

        -- Trade lives INSIDE the inventory now (tray consolidation): header button, left of close.
        do
            local tradeBtn = Instance.new("TextButton")
            tradeBtn.Name = "TradeButton"
            tradeBtn.Size = UDim2.new(0, 86, 0, config.size.height)
            -- dock INSIDE the header, 8px left of the close X (which anchors top-right and
            -- hangs outside by config.offset). Without the (1,0) anchor this pill drifted
            -- OVER the close button — Jason: "what is this weird trade button".
            tradeBtn.AnchorPoint = Vector2.new(1, 0)
            tradeBtn.Position =
                UDim2.new(1, (config.offset.x or 10) - (config.size.width or 36) - 8, 0, 6)
            tradeBtn.BackgroundColor3 = Color3.fromRGB(70, 140, 90)
            tradeBtn.Text = "🤝 Trade"
            tradeBtn.TextColor3 = Color3.fromRGB(240, 255, 245)
            tradeBtn.TextScaled = true
            tradeBtn.Font = Enum.Font.GothamBold
            tradeBtn.ZIndex = 250
            local tc = Instance.new("UICorner")
            tc.CornerRadius = UDim.new(0, config.corner_radius or 8)
            tc.Parent = tradeBtn
            tradeBtn.Parent = self.header
            tradeBtn.Activated:Connect(function()
                local mm = _G.MenuManager
                if mm and mm.OpenPanel then
                    self:Hide()
                    mm:OpenPanel("Trade", "slide_in_right")
                end
            end)
        end

        local closeButton = Instance.new("ImageButton")
        closeButton.Name = "CloseButton"
        closeButton.Size = UDim2.new(0, config.size.width, 0, config.size.height)

        -- Position in top-right-corner with offset (extends outside bounds)
        closeButton.Position = UDim2.new(1, config.offset.x, 0, config.offset.y)
        closeButton.AnchorPoint = Vector2.new(1, 0) -- Anchor to top-right

        closeButton.BackgroundColor3 = config.background_color
        closeButton.BorderSizePixel = 0
        closeButton.Image = "rbxassetid://" .. config.icon
        closeButton.ScaleType = Enum.ScaleType.Fit
        closeButton.ZIndex = 117
        closeButton.Parent = self.header

        local closeCorner = Instance.new("UICorner")
        closeCorner.CornerRadius = UDim.new(0, config.corner_radius)
        closeCorner.Parent = closeButton

        -- Add hover effect
        closeButton.MouseEnter:Connect(function()
            closeButton.BackgroundColor3 = config.hover_color
        end)

        closeButton.MouseLeave:Connect(function()
            closeButton.BackgroundColor3 = config.background_color
        end)

        -- Connect close functionality
        closeButton.MouseButton1Click:Connect(function()
            self:Hide()
        end)
    end

    -- Category tabs
    self:_createCategoryTabs()

    -- Search section
    self:_createSearchSection()

    -- Items grid
    self:_createItemsGrid()

    -- Add entrance animation
    self:_animateEntrance()
end

function InventoryPanel:_createCategoryTabs()
    local theme = uiConfig.helpers.get_theme(uiConfig)

    -- Category container
    local categoryContainer = Instance.new("Frame")
    categoryContainer.Name = "CategoryContainer"
    categoryContainer.Size = UDim2.new(0.95, 0, 0.08, 0) -- 95% width, 8% height (scales with screen)
    categoryContainer.Position = UDim2.new(0.025, 0, 0.02, 0) -- 2.5% from left, 2% from top (scales with screen)
    categoryContainer.BackgroundTransparency = 1
    categoryContainer.ZIndex = 101
    categoryContainer.Parent = self.content

    -- Layout
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 10)
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = categoryContainer

    -- Get categories from configuration
    local categories = self:_getConfiguredCategories()

    for i, category in ipairs(categories) do
        self:_createCategoryTab(category, categoryContainer, i)
    end
end

function InventoryPanel:_refreshCategoryTabs()
    -- Find the category container and update the counts
    local categoryContainer = self.content and self.content:FindFirstChild("CategoryContainer")
        or self.frame:FindFirstChild("CategoryContainer")
    if not categoryContainer then
        return
    end

    -- Get configured categories with updated counts
    local categories = self:_getConfiguredCategories()

    -- Update each category tab's count display
    for _, category in ipairs(categories) do
        local tab = categoryContainer:FindFirstChild(category.name .. "Tab")
        if tab then
            local content = tab:FindFirstChild("Frame") -- Content frame name might be different
            if not content then
                -- Try to find by class
                for _, child in pairs(tab:GetChildren()) do
                    if child:IsA("Frame") and child.BackgroundTransparency == 1 then
                        content = child
                        break
                    end
                end
            end

            if content then
                -- Find the count label (it's positioned at Y=20)
                for _, child in pairs(content:GetChildren()) do
                    if child:IsA("TextLabel") and child.Position.Y.Offset == 20 then
                        child.Text = category.count .. " items"
                        break
                    end
                end
            end
        end
    end

    self.logger:info("🔄 CONFIGURED CATEGORY TABS REFRESHED", {
        categoriesUpdated = #categories,
    })
end

function InventoryPanel:_createCategoryTab(category, parent, layoutOrder)
    local isSelected = (category.name == self.selectedCategory)

    -- Tab button
    local tab = Instance.new("TextButton")
    tab.Name = category.name .. "Tab"
    tab.Size = UDim2.new(0, 120, 1, 0)
    tab.BackgroundColor3 = isSelected and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(40, 40, 50)
    tab.BorderSizePixel = 0
    tab.Text = ""
    tab.LayoutOrder = layoutOrder
    tab.ZIndex = 102
    tab.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = tab

    -- Tab content
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -10, 1, -10)
    content.Position = UDim2.new(0, 5, 0, 5)
    content.BackgroundTransparency = 1
    content.ZIndex = 103
    content.Parent = tab

    -- Icon
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 20, 0, 20)
    icon.Position = UDim2.new(0, 0, 0, 2)
    icon.BackgroundTransparency = 1
    icon.Text = category.icon
    icon.TextScaled = true
    icon.Font = Enum.Font.GothamBold
    icon.ZIndex = 104
    icon.Parent = content

    -- Name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -25, 0, 18)
    nameLabel.Position = UDim2.new(0, 25, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = category.name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.ZIndex = 104
    nameLabel.Parent = content

    -- Count
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(1, -25, 0, 15)
    countLabel.Position = UDim2.new(0, 25, 0, 20)
    countLabel.BackgroundTransparency = 1
    countLabel.Text = category.count .. " items"
    countLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    countLabel.TextScaled = true
    countLabel.Font = Enum.Font.Gotham
    countLabel.TextXAlignment = Enum.TextXAlignment.Left
    countLabel.ZIndex = 104
    countLabel.Parent = content

    -- Click handling
    tab.Activated:Connect(function()
        self:_selectCategory(category.name)
    end)

    if not isSelected then
        self:_addButtonHoverEffect(tab, Color3.fromRGB(40, 40, 50))
    end
end

function InventoryPanel:_createSearchSection()
    local theme = uiConfig.helpers.get_theme(uiConfig)

    -- Search container
    local searchContainer = Instance.new("Frame")
    searchContainer.Name = "SearchContainer"
    searchContainer.Size = UDim2.new(0.95, 0, 0.08, 0) -- 95% width, 8% height (scales with screen)
    searchContainer.Position = UDim2.new(0.025, 0, 0.11, 0) -- 2.5% from left, 11% from top (scales with screen)
    searchContainer.BackgroundTransparency = 1
    searchContainer.ZIndex = 101
    searchContainer.Parent = self.content

    -- Search box background
    local searchBG = Instance.new("Frame")
    searchBG.Size = UDim2.new(0, 300, 1, -10)
    searchBG.Position = UDim2.new(0, 0, 0, 5)
    searchBG.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    searchBG.BorderSizePixel = 0
    searchBG.ZIndex = 102
    searchBG.Parent = searchContainer

    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 10)
    searchCorner.Parent = searchBG

    -- Search icon
    local searchIcon = Instance.new("TextLabel")
    searchIcon.Size = UDim2.new(0, 30, 0, 30)
    searchIcon.Position = UDim2.new(0, 10, 0.5, -15)
    searchIcon.BackgroundTransparency = 1
    searchIcon.Text = "🔍"
    searchIcon.TextScaled = true
    searchIcon.Font = Enum.Font.GothamBold
    searchIcon.ZIndex = 104
    searchIcon.Parent = searchBG

    -- Search text box
    self.searchBox = Instance.new("TextBox")
    self.searchBox.Name = "SearchBox"
    self.searchBox.Size = UDim2.new(1, -50, 1, -10)
    self.searchBox.Position = UDim2.new(0, 45, 0, 5)
    self.searchBox.BackgroundTransparency = 1
    self.searchBox.Text = ""
    self.searchBox.PlaceholderText = "Search items..."
    self.searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    self.searchBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
    self.searchBox.TextScaled = true
    self.searchBox.Font = Enum.Font.Gotham
    self.searchBox.TextXAlignment = Enum.TextXAlignment.Left
    self.searchBox.ClearTextOnFocus = false
    self.searchBox.ZIndex = 103
    self.searchBox.Parent = searchBG

    -- Search functionality
    self.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        self.searchTerm = self.searchBox.Text:lower()
        self:_updateItemsDisplay()
    end)
end

function InventoryPanel:_createItemsGrid()
    local theme = uiConfig.helpers.get_theme(uiConfig)

    -- Items scroll frame
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ItemsScroll"
    scrollFrame.Size = UDim2.new(0.95, 0, 0.75, 0) -- 95% width, 75% height (accounts for later start position)
    scrollFrame.Position = UDim2.new(0.025, 0, 0.21, 0) -- 2.5% from left, 21% from top (after search box)
    scrollFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 8
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(52, 152, 219)
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.ZIndex = 101
    scrollFrame.Parent = self.content

    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 15)
    scrollCorner.Parent = scrollFrame

    -- Vertical list layout for sections
    local listLayout = Instance.new("UIListLayout")
    listLayout.FillDirection = Enum.FillDirection.Vertical
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 10)
    listLayout.Parent = scrollFrame

    -- Padding
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 15)
    padding.PaddingBottom = UDim.new(0, 15)
    padding.PaddingLeft = UDim.new(0, 15)
    padding.PaddingRight = UDim.new(0, 15)
    padding.Parent = scrollFrame

    -- Equipped section
    local eqLabel = Instance.new("TextLabel")
    eqLabel.Name = "EquippedLabel"
    eqLabel.Size = UDim2.new(1, -20, 0, 20)
    eqLabel.BackgroundTransparency = 1
    eqLabel.Text = "Equipped"
    eqLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    eqLabel.Font = Enum.Font.GothamBold
    eqLabel.TextScaled = true
    eqLabel.LayoutOrder = 1
    eqLabel.Parent = scrollFrame

    local eqGridContainer = Instance.new("Frame")
    eqGridContainer.Name = "EquippedContainer"
    eqGridContainer.Size = UDim2.new(1, -20, 0, 0)
    eqGridContainer.BackgroundTransparency = 1
    eqGridContainer.LayoutOrder = 2
    eqGridContainer.Parent = scrollFrame

    local eqGrid = Instance.new("UIGridLayout")
    eqGrid.CellSize = UDim2.new(0, self.cardSize.X, 0, self.cardSize.Y)
    print("card size in eqgrid", self.cardSize)
    eqGrid.CellPadding = UDim2.new(0, self.cardPadding.X, 0, self.cardPadding.Y)
    eqGrid.SortOrder = Enum.SortOrder.LayoutOrder
    eqGrid.Parent = eqGridContainer

    -- Unequipped section
    local invLabel = Instance.new("TextLabel")
    invLabel.Name = "InventoryLabel"
    invLabel.Size = UDim2.new(1, -20, 0, 20)
    invLabel.BackgroundTransparency = 1
    invLabel.Text = "Inventory"
    invLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    invLabel.Font = Enum.Font.GothamBold
    invLabel.TextScaled = true
    invLabel.LayoutOrder = 3
    invLabel.Parent = scrollFrame

    local invGridContainer = Instance.new("Frame")
    invGridContainer.Name = "InventoryContainer"
    invGridContainer.Size = UDim2.new(1, -20, 0, 0)
    invGridContainer.BackgroundTransparency = 1
    invGridContainer.LayoutOrder = 4
    invGridContainer.Parent = scrollFrame

    local invGrid = Instance.new("UIGridLayout")
    invGrid.CellSize = UDim2.new(0, self.cardSize.X, 0, self.cardSize.Y)
    print("card size in grid", self.cardSize)
    invGrid.CellPadding = UDim2.new(0, self.cardPadding.X, 0, self.cardPadding.Y)
    invGrid.SortOrder = Enum.SortOrder.LayoutOrder
    invGrid.Parent = invGridContainer

    local function updateSectionHeights()
        -- Expand containers to fit all grid rows
        local eqH = eqGrid.AbsoluteContentSize.Y
        local invH = invGrid.AbsoluteContentSize.Y
        eqGridContainer.Size = UDim2.new(1, -20, 0, eqH)
        invGridContainer.Size = UDim2.new(1, -20, 0, invH)

        -- Recompute scroll canvas
        local total = eqH + invH + eqLabel.AbsoluteSize.Y + invLabel.AbsoluteSize.Y + 60
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, math.max(0, total))
    end

    local function recomputeCanvas()
        updateSectionHeights()
    end

    eqGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSectionHeights)
    invGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSectionHeights)
    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(recomputeCanvas)

    -- Initial sizing
    task.defer(updateSectionHeights)

    -- Store references
    self.equippedGrid = eqGridContainer
    self.inventoryGrid = invGridContainer
    self.itemsGrid = invGridContainer -- backward compat for any code referencing itemsGrid
end

function InventoryPanel:_generateSampleData()
    local rarityColors = {
        Common = Color3.fromRGB(150, 150, 150),
        Uncommon = Color3.fromRGB(30, 255, 0),
        Rare = Color3.fromRGB(0, 112, 255),
        Epic = Color3.fromRGB(163, 53, 238),
        Legendary = Color3.fromRGB(255, 128, 0),
        Mythical = Color3.fromRGB(255, 0, 0),
    }

    local items = {}
    local petIcons =
        { "🐶", "🐱", "🐼", "🦊", "🐯", "🐸", "🐷", "🐨", "🐵", "🦁" }
    local rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical" }

    -- Generate random pets
    for i = 1, 60 do
        local rarity = rarities[math.random(1, #rarities)]
        table.insert(items, {
            id = "pet_" .. i,
            name = "Pet " .. i,
            icon = petIcons[math.random(1, #petIcons)],
            rarity = rarity,
            color = rarityColors[rarity],
            category = "Pets",
            count = 1,
            power = math.random(100, 999),
        })
    end

    return items
end

-- 🔧 CONFIGURATION-DRIVEN CATEGORIES
function InventoryPanel:_getConfiguredCategories()
    local categories = {}

    if not self.inventoryConfig or not self.inventoryConfig.display_categories then
        self.logger:warn("No inventory config found, using fallback categories")
        return self:_getFallbackCategories()
    end

    -- Get category counts by folder mapping
    local folderCounts = self:_calculateFolderCounts()

    -- Process each configured category
    for _, categoryConfig in ipairs(self.inventoryConfig.display_categories) do
        local totalCount = 0

        -- Sum counts for all folders in this category
        for _, folderName in ipairs(categoryConfig.folders) do
            totalCount = totalCount + (folderCounts[folderName] or 0)
        end

        -- Check if category should be visible
        local shouldShow = categoryConfig.always_visible or totalCount > 0
        local hideEmptyCategories = self.inventoryConfig.category_settings
            and self.inventoryConfig.category_settings.hide_empty_categories
        if not hideEmptyCategories then
            shouldShow = true -- Show all categories if hiding is disabled
        end

        -- TEMPORARY: Force show all categories for debugging
        shouldShow = true

        self.logger:info("🔍 CATEGORY VISIBILITY", {
            categoryName = categoryConfig.name,
            totalCount = totalCount,
            always_visible = categoryConfig.always_visible,
            shouldShow = shouldShow,
            folders = categoryConfig.folders,
        })

        if shouldShow then
            local categoryData = {
                name = categoryConfig.name,
                icon = categoryConfig.icon,
                description = categoryConfig.description,
                folders = categoryConfig.folders,
                count = totalCount,
                order = categoryConfig.display_order,
            }

            table.insert(categories, categoryData)
        end
    end

    -- Sort by display_order
    table.sort(categories, function(a, b)
        return a.order < b.order
    end)

    -- Create category summary for logging
    local categorySummary = {}
    for _, cat in ipairs(categories) do
        table.insert(categorySummary, cat.name .. " (" .. cat.count .. " items)")
    end

    self.logger:info("📁 CONFIGURED CATEGORIES", {
        count = #categories,
        categoryNames = categorySummary,
        fullCategories = categories,
    })

    return categories
end

function InventoryPanel:_getFallbackCategories()
    -- Fallback categories if config fails to load
    local categoryCounts = self:_calculateCategoryCounts()
    return {
        {
            name = "All",
            icon = "📦",
            count = categoryCounts.total,
            folders = { "pets", "consumables", "tools", "eggs" },
        },
        { name = "Pets", icon = "🐾", count = categoryCounts.pets, folders = { "pets" } },
        { name = "Items", icon = "⚡", count = categoryCounts.items, folders = { "consumables" } },
        { name = "Eggs", icon = "🥚", count = categoryCounts.eggs, folders = { "eggs" } },
        { name = "Tools", icon = "🔧", count = categoryCounts.tools, folders = { "tools" } },
    }
end

function InventoryPanel:_calculateFolderCounts()
    local folderCounts = {}
    local settings = self.inventoryConfig and self.inventoryConfig.category_settings or {}
    local countStacksAsSingle = settings.count_stacks_as_single ~= false -- default true

    for _, item in ipairs(self.inventoryData) do
        local folderName = item.folder_source or "unknown"
        local increment = 1
        if item.category == "Pets" and not countStacksAsSingle then
            increment = item.count or 1
        end
        folderCounts[folderName] = (folderCounts[folderName] or 0) + increment
    end

    -- Equipped stack pets sit at quantity 0 (the equipped one is taken out of the
    -- available stack), so they're not in inventoryData — but they DO render as
    -- equipped "ghost" cards. Count them so the tab total matches the visible cards.
    -- Mirror the exact ghost-render condition (stack slot with a backing stack entry).
    local equippedFolder = self.player and self.player:FindFirstChild("Equipped")
    local equippedPets = equippedFolder and equippedFolder:FindFirstChild("pets")
    if equippedPets and self._stackDataByKey then
        for _, slot in ipairs(equippedPets:GetChildren()) do
            if slot:IsA("StringValue") and typeof(slot.Value) == "string" then
                local parts = string.split(slot.Value, "|")
                if #parts >= 2 and parts[1] == "stack" and self._stackDataByKey[parts[2]] then
                    folderCounts["pets"] = (folderCounts["pets"] or 0) + 1
                end
            end
        end
    end

    self.logger:info("📊 FOLDER COUNTS DEBUG", folderCounts)
    return folderCounts
end

-- 📊 CATEGORY COUNTING (Legacy - now used for fallback)
function InventoryPanel:_calculateCategoryCounts()
    local counts = {
        total = 0,
        pets = 0,
        items = 0, -- Consumables/potions
        eggs = 0,
        tools = 0,
    }

    -- Count from real inventory data
    for _, item in ipairs(self.inventoryData) do
        counts.total = counts.total + 1

        -- Categorize based on item category
        if item.category == "Pets" then
            counts.pets = counts.pets + 1
        elseif item.category == "Items" or item.category == "Consumables" then
            counts.items = counts.items + 1
        elseif item.category == "Eggs" then
            counts.eggs = counts.eggs + 1
        elseif item.category == "Tools" then
            counts.tools = counts.tools + 1
        end
    end

    self.logger:info("📊 CATEGORY COUNTS", {
        total = counts.total,
        pets = counts.pets,
        items = counts.items,
        eggs = counts.eggs,
        tools = counts.tools,
    })

    return counts
end

-- 🔄 REAL DATA LOADING
function InventoryPanel:_loadRealInventoryData()
    self.inventoryData = {}
    -- Rebuild the stack-display cache from scratch each load so traded/removed stacks
    -- don't linger as stale ghost cards (or stale counts).
    self._stackDataByKey = {}

    -- Try to find inventory folder in player
    local inventoryFolder = self.player:FindFirstChild("Inventory")
    if not inventoryFolder then
        self.logger:warn("No inventory folder found for player")
        -- Fallback to sample data for testing
        self.inventoryData = self:_generateSampleData()
        return
    end

    local inventoryChildren = {}
    for _, child in pairs(inventoryFolder:GetChildren()) do
        table.insert(inventoryChildren, child.Name)
    end

    self.logger:info("🔍 INVENTORY DEBUG - Found inventory folder", {
        children = inventoryChildren,
    })

    -- Load pets from pets folder
    local petsFolder = inventoryFolder:FindFirstChild("pets")
    if petsFolder then
        local petsChildren = {}
        for _, child in pairs(petsFolder:GetChildren()) do
            table.insert(petsChildren, child.Name)
        end

        self.logger:info("🐾 PETS DEBUG - Found pets folder", {
            childCount = #petsFolder:GetChildren(),
            children = petsChildren,
        })

        self:_loadPetsFromFolder(petsFolder)
    else
        self.logger:warn("🚫 PETS DEBUG - No pets folder found")
    end

    -- Load enhancements from the enhancements bucket (E7)
    local enhFolder = inventoryFolder:FindFirstChild("enhancements")
    if enhFolder then
        self:_loadEnhancementsFromFolder(enhFolder)
    end

    -- Load consumables from consumables folder
    local consumablesFolder = inventoryFolder:FindFirstChild("consumables")
    if consumablesFolder then
        self:_loadConsumablesFromFolder(consumablesFolder)
    else
        self.logger:info("📦 CONSUMABLES DEBUG - No consumables folder found")
    end

    -- Load tools from tools folder
    local toolsFolder = inventoryFolder:FindFirstChild("tools")
    if toolsFolder then
        self:_loadToolsFromFolder(toolsFolder)
    else
        self.logger:info("🔧 TOOLS DEBUG - No tools folder found")
    end

    -- Load eggs from eggs folder
    local eggsFolder = inventoryFolder:FindFirstChild("eggs")
    if eggsFolder then
        self:_loadEggsFromFolder(eggsFolder)
    else
        self.logger:info("🥚 EGGS DEBUG - No eggs folder found")
    end

    self.logger:info("✅ INVENTORY DEBUG - Loaded real inventory data", {
        totalItems = #self.inventoryData,
        hasInventoryFolder = inventoryFolder ~= nil,
        hasPetsFolder = petsFolder ~= nil,
        sampleItems = self.inventoryData[1] and {
            name = self.inventoryData[1].name,
            folder_source = self.inventoryData[1].folder_source,
            category = self.inventoryData[1].category,
        } or "no items",
    })
end

function InventoryPanel:_loadPetsFromFolder(petsFolder)
    -- Mixed storage support: prefer Stacks/Special structure if present
    local stacksFolder = petsFolder:FindFirstChild("Stacks")
    local specialFolder = petsFolder:FindFirstChild("Special")
    if stacksFolder or specialFolder then
        return self:_loadPetsFromMixedFolders(stacksFolder, specialFolder)
    end
    -- Get rarity colors for display
    local rarityColors = {
        basic = Color3.fromRGB(150, 150, 150), -- Gray
        golden = Color3.fromRGB(255, 215, 0), -- Gold
        rainbow = Color3.fromRGB(255, 0, 255), -- Magenta
    }

    -- Get pet emoji mapping
    local petIcons = {
        bear = "🐻",
        bunny = "🐰",
        doggy = "🐶",
        kitty = "🐱",
        dragon = "🐉",
    }
    local petConfigModule = ReplicatedStorage:FindFirstChild("Configs")
        and ReplicatedStorage.Configs:FindFirstChild("pets")
    local petConfig = nil
    if petConfigModule then
        local ok, mod = pcall(function()
            return require(petConfigModule)
        end)
        if ok then
            petConfig = mod
        end
    end

    -- Iterate through all pet folders
    for _, petFolder in pairs(petsFolder:GetChildren()) do
        if petFolder:IsA("Folder") and petFolder.Name ~= "Info" then
            -- Extract pet data from folder structure
            local petData = self:_extractPetDataFromFolder(petFolder)
            if petData then
                -- Convert to inventory display format
                local displayData = {
                    id = petFolder.Name, -- UID
                    name = petData.id:gsub("^%l", string.upper), -- Capitalize pet name
                    icon = petIcons[petData.id] or "🐾", -- Emoji fallback
                    rarity = petData.variant:gsub("^%l", string.upper), -- Capitalize variant
                    color = rarityColors[petData.variant] or rarityColors.basic,
                    category = "Pets",
                    count = 1, -- Pets don't stack
                    power = petConfig and petConfig.getPet and petConfig.getPet(
                        petData.id,
                        petData.variant
                    ) and petConfig.getPet(petData.id, petData.variant).power or 0,
                    level = petData.level or 1,
                    uid = petFolder.Name, -- Store UID for future operations
                    folder_source = "pets", -- Track which folder this came from

                    -- 3D Model data for viewport display
                    petType = petData.id, -- Pet type for model loading
                    variant = petData.variant, -- Variant for model loading
                    use3DModel = true, -- Flag to use 3D model instead of emoji
                }

                table.insert(self.inventoryData, displayData)
                self.logger:info("🐾 LOADED PET", {
                    name = displayData.name,
                    folder_source = displayData.folder_source,
                    category = displayData.category,
                    petType = displayData.petType,
                })
            end
        end
    end
end

-- Mixed storage loader (Stacks + Special)
function InventoryPanel:_loadPetsFromMixedFolders(stacksFolder, specialFolder)
    local rarityColors = {
        basic = Color3.fromRGB(150, 150, 150),
        golden = Color3.fromRGB(255, 215, 0),
        rainbow = Color3.fromRGB(255, 0, 255),
        common = Color3.fromRGB(150, 150, 150),
        uncommon = Color3.fromRGB(0, 255, 0),
        rare = Color3.fromRGB(0, 100, 255),
        epic = Color3.fromRGB(128, 0, 128),
        legendary = Color3.fromRGB(255, 215, 0),
        mythic = Color3.fromRGB(255, 0, 255),
        secret = Color3.fromRGB(255, 140, 0),
        exclusive = Color3.fromRGB(0, 255, 255),
        huge = Color3.fromRGB(255, 90, 210),
    }

    local petIcons = {
        bear = "🐻",
        bunny = "🐰",
        doggy = "🐶",
        kitty = "🐱",
        dragon = "🐉",
        colorado = "👤",
    }

    -- Load pet config for power lookup
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local petConfigModule = ReplicatedStorage:FindFirstChild("Configs")
        and ReplicatedStorage.Configs:FindFirstChild("pets")
    local petConfig = nil
    if petConfigModule then
        local ok, mod = pcall(function()
            return require(petConfigModule)
        end)
        if ok then
            petConfig = mod
        end
    end
    local petProgressionConfigModule = ReplicatedStorage:FindFirstChild("Configs")
        and ReplicatedStorage.Configs:FindFirstChild("pet_progression")
    local petProgressionConfig = nil
    if petProgressionConfigModule then
        local ok, mod = pcall(function()
            return require(petProgressionConfigModule)
        end)
        if ok then
            petProgressionConfig = mod
        end
    end
    local inventoryConfigModule = ReplicatedStorage:FindFirstChild("Configs")
        and ReplicatedStorage.Configs:FindFirstChild("inventory")
    local inventoryConfig = nil
    if inventoryConfigModule then
        local ok, mod = pcall(function()
            return require(inventoryConfigModule)
        end)
        if ok then
            inventoryConfig = mod
        end
    end
    self._petTooltipFieldsConfig = (
        inventoryConfig
        and inventoryConfig.buckets
        and inventoryConfig.buckets.pets
        and inventoryConfig.buckets.pets.tooltip_fields
    ) or nil

    local function getPetConfigData(petType, variant)
        if petConfig and petConfig.getPet then
            return petConfig.getPet(petType, variant)
        end
        return nil
    end

    local function readNumberValue(folder, names)
        if not folder then
            return nil
        end
        for _, name in ipairs(names) do
            local value = folder:FindFirstChild(name)
            if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
                return tonumber(value.Value)
            end
        end
        return nil
    end

    local function readStringValue(folder, names)
        if not folder then
            return nil
        end
        for _, name in ipairs(names) do
            local value = folder:FindFirstChild(name)
            if value and value:IsA("StringValue") then
                return value.Value
            end
        end
        return nil
    end

    local function readBoolValue(folder, names)
        if not folder then
            return nil
        end
        for _, name in ipairs(names) do
            local value = folder:FindFirstChild(name)
            if value and value:IsA("BoolValue") then
                return value.Value
            end
        end
        return nil
    end

    local function getConfiguredEternalPercent(pdata, isHuge)
        local eternalPercent = 0
        if type(pdata and pdata.eternal) == "table" and pdata.eternal.enabled == true then
            eternalPercent = tonumber(pdata.eternal.power_percent) or 0
        end
        if isHuge then
            eternalPercent = math.max(100, eternalPercent)
        end
        return eternalPercent
    end

    local function getPowerMultiplierForLevel(level)
        if not petProgressionConfig or petProgressionConfig.enabled == false then
            return 1
        end

        level = math.max(1, math.floor(tonumber(level) or 1))
        local scaling = petProgressionConfig.power_scaling or {}
        local perLevel = tonumber(scaling.percent_per_level) or 0
        local maxBonus = tonumber(scaling.max_bonus_percent) or 0
        local bonus = math.min(maxBonus, math.max(0, (level - 1) * perLevel))
        return 1 + bonus
    end

    local function getConfiguredPowerForLevel(pdata, level, isHuge)
        -- Shared source of truth: huge pets use huge_base_power, then level scaling.
        local base = PetPower.configuredBasePower(pdata, isHuge == true)
        if base <= 0 then
            return 0
        end
        return PetPower.withLevel(base, level, petProgressionConfig)
    end

    local function getConfiguredMaxEnchantments(rarityId)
        local enchanting = petConfig and petConfig.enchanting
        if type(rarityId) ~= "string" or type(enchanting) ~= "table" then
            return 0
        end
        local byRarity = enchanting.max_enchantments_by_rarity
        local maxEnchantments = type(byRarity) == "table" and byRarity[rarityId]
        if maxEnchantments == nil then
            maxEnchantments = enchanting.default_max_enchantments
        end
        return tonumber(maxEnchantments) or 0
    end

    local function getRarityData(rarityId, pdata)
        if type(pdata and pdata.rarity) == "table" then
            return pdata.rarity
        end
        if petConfig and petConfig.rarities and type(rarityId) == "string" then
            return petConfig.rarities[rarityId]
        end
        return nil
    end

    local function getRarityDisplayName(rarityId, pdata)
        local rarityData = getRarityData(rarityId, pdata)
        if type(rarityData) == "table" and type(rarityData.name) == "string" then
            return rarityData.name
        end
        return tostring(rarityId or "basic"):gsub("^%l", string.upper)
    end

    local function getRarityColor(rarityId, variant, pdata)
        local rarityData = getRarityData(rarityId, pdata)
        if type(rarityData) == "table" and typeof(rarityData.color) == "Color3" then
            return rarityData.color
        end
        return rarityColors[rarityId] or rarityColors[variant] or rarityColors.basic
    end

    local function countFolderChildren(folder, names)
        if not folder then
            return 0
        end
        for _, name in ipairs(names) do
            local child = folder:FindFirstChild(name)
            if child and child:IsA("Folder") then
                return #child:GetChildren()
            end
        end
        return 0
    end

    local function readEnchantSummaries(folder)
        local summaries = {}
        if not folder then
            return summaries
        end

        local enchantFolder = folder:FindFirstChild("enchantments")
            or folder:FindFirstChild("Enchantments")
        if not enchantFolder or not enchantFolder:IsA("Folder") then
            return summaries
        end

        local children = enchantFolder:GetChildren()
        table.sort(children, function(a, b)
            return tostring(a.Name) < tostring(b.Name)
        end)
        for _, child in ipairs(children) do
            if child:IsA("Folder") then
                local id = readStringValue(child, { "id", "Id" })
                local displayName = readStringValue(child, { "display_name", "DisplayName" })
                    or id
                    or child.Name
                local strength =
                    readNumberValue(child, { "strength", "Strength", "value", "Value" })
                local profile = readStringValue(child, { "roll_profile", "RollProfile" })
                table.insert(summaries, {
                    id = id,
                    displayName = displayName,
                    strength = strength,
                    profile = profile,
                })
            end
        end

        return summaries
    end

    local function readPrimitiveValues(folder)
        local values = {}
        if not folder then
            return values
        end
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("StringValue") or child:IsA("BoolValue") then
                values[child.Name] = child.Value
            elseif child:IsA("NumberValue") or child:IsA("IntValue") then
                values[child.Name] = tonumber(child.Value)
            end
        end
        return values
    end

    -- Stacks
    if stacksFolder then
        for _, stackFolder in ipairs(stacksFolder:GetChildren()) do
            if stackFolder:IsA("Folder") then
                local itemId = stackFolder:FindFirstChild("ItemId")
                local variantValue = stackFolder:FindFirstChild("Variant")
                local qtyValue = stackFolder:FindFirstChild("Quantity")
                if itemId and variantValue and qtyValue then
                    local petType = itemId.Value
                    local variant = variantValue.Value
                    local eternalPercent = 0
                    local pdata = getPetConfigData(petType, variant)
                    local power = getConfiguredPowerForLevel(pdata, 1)
                    local rarityId = variant
                    local displayName = variant:gsub("^%l", string.upper)
                        .. " "
                        .. petType:gsub("^%l", string.upper)
                    if pdata then
                        eternalPercent = getConfiguredEternalPercent(pdata, false)
                        rarityId = pdata.rarity_id or variant
                        displayName = pdata.name or displayName
                    end
                    -- Always cache stack display data so ghost cards can render even at quantity 0
                    self._stackDataByKey = self._stackDataByKey or {}
                    self._stackDataByKey[stackFolder.Name] = {
                        id = "stack|" .. stackFolder.Name,
                        name = displayName,
                        icon = petIcons[petType] or "🐾",
                        rarity = getRarityDisplayName(rarityId, pdata),
                        rarityId = rarityId,
                        color = getRarityColor(rarityId, variant, pdata),
                        category = "Pets",
                        count = qtyValue.Value,
                        power = power,
                        basePower = power,
                        effectivePower = power,
                        eternalPercent = eternalPercent,
                        special = rarityId == "exclusive"
                            or rarityId == "secret"
                            or rarityId == "huge",
                        enchantable = false,
                        maxEnchantments = 0,
                        source = "Stack",
                        uid = stackFolder.Name,
                        folder_source = "pets",
                        petType = petType,
                        variant = variant,
                        use3DModel = true,
                    }
                    -- Only create a visible inventory card when count > 0
                    if (qtyValue.Value or 0) > 0 then
                        table.insert(self.inventoryData, self._stackDataByKey[stackFolder.Name])
                    end
                end
            end
        end
    end

    -- Special (unique)
    if specialFolder then
        for _, uidFolder in ipairs(specialFolder:GetChildren()) do
            if uidFolder:IsA("Folder") then
                local itemId = uidFolder:FindFirstChild("ItemId")
                if itemId then
                    local petType = itemId.Value
                    -- Try to read Variant if present in unique folder
                    local variant = "basic"
                    local variantVal = uidFolder:FindFirstChild("Variant")
                        or uidFolder:FindFirstChild("variant")
                    if variantVal and variantVal:IsA("StringValue") then
                        variant = variantVal.Value
                    end
                    local hugeValue = uidFolder:FindFirstChild("huge")
                        or uidFolder:FindFirstChild("Huge")
                    local isHuge = hugeValue
                        and hugeValue:IsA("BoolValue")
                        and hugeValue.Value == true
                    local serialValue = uidFolder:FindFirstChild("serial")
                        or uidFolder:FindFirstChild("Serial")
                    local serial = serialValue and serialValue.Value or nil
                    local serialSource =
                        readStringValue(uidFolder, { "serial_source", "SerialSource" })
                    local grantSource =
                        readStringValue(uidFolder, { "grant_source", "GrantSource" })
                    local hatcherName = readStringValue(
                        uidFolder,
                        { "hatcher_name", "HatcherName" }
                    ) or readStringValue(uidFolder, { "source", "Source" })
                    local tooltipFields = readPrimitiveValues(uidFolder)
                    if hatcherName then
                        tooltipFields.hatcher_name = hatcherName
                    end
                    local locked = readBoolValue(uidFolder, { "locked", "Locked" })
                    local pdata = getPetConfigData(petType, variant)
                    local rarityValue = uidFolder:FindFirstChild("rarity_id")
                        or uidFolder:FindFirstChild("rarity_override")
                    local storedRarityId = rarityValue
                        and rarityValue:IsA("StringValue")
                        and rarityValue.Value
                    local rarityId = isHuge and "huge"
                        or (pdata and pdata.rarity_id)
                        or storedRarityId
                        or variant
                    local storedEnchantable =
                        readBoolValue(uidFolder, { "enchantable", "Enchantable" })
                    local storedMaxEnchantments = readNumberValue(
                        uidFolder,
                        { "max_enchantments", "MaxEnchantments", "MaxEnchants" }
                    )
                    local unlockedEnchantSlots = readNumberValue(
                        uidFolder,
                        { "unlocked_enchant_slots", "UnlockedEnchantSlots" }
                    )
                    local configuredMaxEnchantments = getConfiguredMaxEnchantments(rarityId)
                    local maxEnchantments = configuredMaxEnchantments
                    if configuredMaxEnchantments <= 0 and storedRarityId == rarityId then
                        maxEnchantments = storedMaxEnchantments or 0
                    end
                    if maxEnchantments > 0 then
                        unlockedEnchantSlots = math.clamp(
                            math.floor(tonumber(unlockedEnchantSlots) or 1),
                            0,
                            maxEnchantments
                        )
                    else
                        unlockedEnchantSlots = 0
                    end
                    local enchantmentCount =
                        countFolderChildren(uidFolder, { "enchantments", "Enchantments" })
                    local enchantments = readEnchantSummaries(uidFolder)
                    local enchantable = maxEnchantments > 0
                        or (storedEnchantable == true and storedRarityId == rarityId)
                    local level = readNumberValue(uidFolder, { "level", "Level" }) or 1
                    local power = getConfiguredPowerForLevel(pdata, level, isHuge)
                    local basePower = power
                    local effectivePower = power
                    local eternalBaselinePower = nil
                    local eternalPercent = readNumberValue(
                        uidFolder,
                        { "EternalPercent", "eternal_percent", "Eternal" }
                    ) or 0
                    if eternalPercent == 0 then
                        eternalPercent = getConfiguredEternalPercent(pdata, isHuge)
                    elseif isHuge then
                        eternalPercent = math.max(100, eternalPercent)
                    end
                    local petName = (pdata and (pdata.family_display_name or pdata.name))
                        or petType:gsub("^%l", string.upper)
                    local item = {
                        id = "special|" .. uidFolder.Name,
                        name = (isHuge and "Huge " or "")
                            .. petName
                            .. (serial and (" #" .. tostring(serial)) or ""),
                        icon = petIcons[petType] or "🐾",
                        rarity = getRarityDisplayName(rarityId, pdata),
                        rarityId = rarityId,
                        color = getRarityColor(rarityId, variant, pdata),
                        category = "Pets",
                        count = 1,
                        power = power,
                        basePower = basePower,
                        effectivePower = effectivePower,
                        eternalBaselinePower = eternalBaselinePower,
                        eternalPercent = eternalPercent,
                        level = level,
                        huge = isHuge,
                        serial = serial,
                        serialSource = serialSource,
                        grantSource = grantSource,
                        hatcherName = hatcherName,
                        tooltipFields = tooltipFields,
                        locked = locked,
                        special = true,
                        enchantable = enchantable,
                        maxEnchantments = maxEnchantments,
                        unlockedEnchantSlots = unlockedEnchantSlots,
                        enchantmentCount = enchantmentCount,
                        enchantments = enchantments,
                        uid = uidFolder.Name,
                        folder_source = "pets",
                        petType = petType,
                        variant = variant,
                        use3DModel = true,
                    }
                    table.insert(self.inventoryData, item)
                end
            end
        end
    end
end

function InventoryPanel:_loadConsumablesFromFolder(consumablesFolder)
    -- Map item IDs to appropriate icons
    local itemIcons = {
        health_potion = "❤️",
        speed_potion = "⚡",
        trader_scroll = "📜",
        premium_boost = "💎",
        test_item = "🧪",
    }

    -- Iterate through all consumable items
    for _, itemFolder in pairs(consumablesFolder:GetChildren()) do
        if itemFolder:IsA("Folder") and itemFolder.Name ~= "Info" then
            local itemData = self:_extractConsumableDataFromFolder(itemFolder)
            if itemData then
                local displayData = {
                    id = itemFolder.Name,
                    name = itemData.id:gsub("_", " "):gsub("^%l", string.upper),
                    icon = itemIcons[itemData.id] or "🧪", -- Item-specific icon or fallback
                    rarity = "Common",
                    color = Color3.fromRGB(150, 150, 150),
                    category = "Items",
                    count = itemData.quantity or 1,
                    uid = itemFolder.Name,
                    folder_source = "consumables", -- Track which folder this came from
                }
                table.insert(self.inventoryData, displayData)
                self.logger:info("🧪 LOADED CONSUMABLE", {
                    name = displayData.name,
                    folder_source = displayData.folder_source,
                    category = displayData.category,
                    count = displayData.count,
                })
            end
        end
    end
end

-- Enhancements bucket (E7): each uid folder mirrors { id="enhancement", type, origins_csv,
-- name } via InventoryService value objects. Cards show the display name, a gear icon, and
-- the ORIGIN color (single = its origin's color, dual = chaotic purple) with Single/Dual as
-- the rarity line — same grammar as the ENHANCE strip in PowerChoiceMenu.
function InventoryPanel:_loadEnhancementsFromFolder(enhFolder)
    local ORIGIN_COLOR = {
        geomancer = Color3.fromRGB(150, 230, 150),
        pyromancer = Color3.fromRGB(255, 150, 120),
        cryomancer = Color3.fromRGB(140, 200, 255),
        sandwalker = Color3.fromRGB(240, 215, 130),
    }
    local DUAL_COLOR = Color3.fromRGB(196, 156, 255)
    for _, itemFolder in pairs(enhFolder:GetChildren()) do
        if itemFolder:IsA("Folder") and itemFolder.Name ~= "Info" then
            local nameV = itemFolder:FindFirstChild("name")
            local csvV = itemFolder:FindFirstChild("origins_csv")
            local typeV = itemFolder:FindFirstChild("type")
            local origins = {}
            if csvV and csvV:IsA("StringValue") then
                for o in string.gmatch(csvV.Value, "[^,]+") do
                    origins[#origins + 1] = o
                end
            end
            local single = #origins == 1
            local typeName = (typeV and typeV:IsA("StringValue") and typeV.Value) or nil
            local levelV = itemFolder:FindFirstChild("level")
            local level = (levelV and (levelV:IsA("NumberValue") or levelV:IsA("IntValue")))
                    and math.floor(levelV.Value)
                or nil
            -- short labels read BIG on the card (TextScaled): name = the TYPE ("Health"),
            -- second line = the origin pair ("Geo/Cryo") in the rarity color; the badge
            -- (colored disc + symbol + ring) carries the identity
            local shorts = {}
            for _, o in ipairs(origins) do
                shorts[#shorts + 1] = o:sub(1, 1):upper() .. o:sub(2, 3)
            end
            local displayData = {
                id = itemFolder.Name,
                name = typeName and (typeName:sub(1, 1):upper() .. typeName:sub(2))
                    or ((nameV and nameV:IsA("StringValue") and nameV.Value) or "Enhancement"),
                icon = "⚙️", -- fallback only; cards render the PetBadge enhancement badge
                rarity = single and "Single" or "Dual",
                color = (single and ORIGIN_COLOR[origins[1]]) or DUAL_COLOR,
                category = "Enhancements",
                count = 1,
                uid = itemFolder.Name,
                enhancement_type = typeName,
                level = level,
                origins = origins,
                origins_label = table.concat(shorts, "/"),
                folder_source = "enhancements",
            }
            table.insert(self.inventoryData, displayData)
        end
    end
end

function InventoryPanel:_loadToolsFromFolder(toolsFolder)
    -- Map tool IDs to appropriate icons
    local toolIcons = {
        basic_pickaxe = "⛏️",
        iron_pickaxe = "⛏️",
        diamond_pickaxe = "💎",
        wooden_sword = "🗡️",
        iron_sword = "⚔️",
        diamond_sword = "💎",
        crystal_staff = "🔮",
    }

    -- Iterate through all tool items
    for _, itemFolder in pairs(toolsFolder:GetChildren()) do
        if itemFolder:IsA("Folder") and itemFolder.Name ~= "Info" then
            local itemData = self:_extractToolDataFromFolder(itemFolder)
            if itemData then
                local displayData = {
                    id = itemFolder.Name,
                    name = itemData.id:gsub("_", " "):gsub("^%l", string.upper),
                    icon = toolIcons[itemData.id] or "🔧", -- Tool-specific icon or fallback
                    rarity = "Common",
                    color = Color3.fromRGB(150, 150, 150),
                    category = "Tools",
                    count = 1,
                    uid = itemFolder.Name,
                    folder_source = "tools", -- Track which folder this came from
                }
                table.insert(self.inventoryData, displayData)
            end
        end
    end
end

function InventoryPanel:_loadEggsFromFolder(eggsFolder)
    -- Iterate through all egg items
    for _, itemFolder in pairs(eggsFolder:GetChildren()) do
        if itemFolder:IsA("Folder") and itemFolder.Name ~= "Info" then
            local itemData = self:_extractEggDataFromFolder(itemFolder)
            if itemData then
                local displayData = {
                    id = itemFolder.Name,
                    name = itemData.id:gsub("_", " "):gsub("^%l", string.upper),
                    icon = "🥚",
                    rarity = "Common",
                    color = Color3.fromRGB(150, 150, 150),
                    category = "Eggs",
                    count = itemData.quantity or 1,
                    uid = itemFolder.Name,
                    folder_source = "eggs", -- Track which folder this came from
                }
                table.insert(self.inventoryData, displayData)
            end
        end
    end
end

function InventoryPanel:_extractConsumableDataFromFolder(itemFolder)
    local itemData = {}

    local itemId = itemFolder:FindFirstChild("ItemId")
    local quantity = itemFolder:FindFirstChild("Quantity")

    if not itemId then
        return nil
    end

    itemData.id = itemId.Value
    itemData.quantity = quantity and quantity.Value or 1

    return itemData
end

function InventoryPanel:_extractToolDataFromFolder(itemFolder)
    local itemData = {}

    local itemId = itemFolder:FindFirstChild("ItemId")
    if not itemId then
        return nil
    end

    itemData.id = itemId.Value

    return itemData
end

function InventoryPanel:_extractEggDataFromFolder(itemFolder)
    local itemData = {}

    local itemId = itemFolder:FindFirstChild("ItemId")
    local quantity = itemFolder:FindFirstChild("Quantity")

    if not itemId then
        return nil
    end

    itemData.id = itemId.Value
    itemData.quantity = quantity and quantity.Value or 1

    return itemData
end

-- 🖼️ PET IMAGE ICON CREATION (Using Pre-generated Images)
function InventoryPanel:_createPetImageIcon(parent, item)
    self.logger:info(
        "🖼️ CREATING PET IMAGE",
        { itemId = item.id, petType = item.petType, variant = item.variant }
    )

    if item.huge == true then
        return self:_create3DPetIcon(parent, item)
    end

    -- Try to get pre-generated image from AssetPreloadService
    local imageViewport = self:_getPetImageFromAssets(item.petType, item.variant)

    if imageViewport then
        -- Use the pre-generated ViewportFrame
        imageViewport.Name = "PetImage"
        imageViewport.Size = UDim2.new(1, 0, 1, 0) -- Fill the iconBG
        imageViewport.Position = UDim2.new(0, 0, 0, 0)
        imageViewport.BackgroundTransparency = 1
        imageViewport.ZIndex = 104
        imageViewport.Parent = parent

        self.logger:info("✅ PET IMAGE LOADED", {
            itemId = item.id,
            petType = item.petType,
            variant = item.variant,
            source = "pre-generated",
        })

        return imageViewport
    else
        -- Fallback to emoji if image not available
        self.logger:warn("❌ PET IMAGE NOT FOUND, using emoji fallback", {
            itemId = item.id,
            petType = item.petType,
            variant = item.variant,
        })

        local fallbackIcon = Instance.new("TextLabel")
        fallbackIcon.Name = "PetEmojiFallback"
        fallbackIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
        fallbackIcon.Position = UDim2.new(0.1, 0, 0.1, 0)
        fallbackIcon.BackgroundTransparency = 1
        fallbackIcon.Text = item.icon or "🐾"
        fallbackIcon.TextScaled = true
        fallbackIcon.Font = Enum.Font.GothamBold
        fallbackIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
        fallbackIcon.ZIndex = 104
        fallbackIcon.Parent = parent

        task.spawn(function()
            for _ = 1, 20 do
                task.wait(0.25)
                if not parent.Parent then
                    return
                end
                if parent:FindFirstChild("PetImage") then
                    return
                end

                local retryViewport = self:_getPetImageFromAssets(item.petType, item.variant, true)
                if retryViewport then
                    if fallbackIcon.Parent then
                        fallbackIcon:Destroy()
                    end

                    retryViewport.Name = "PetImage"
                    retryViewport.Size = UDim2.new(1, 0, 1, 0)
                    retryViewport.Position = UDim2.new(0, 0, 0, 0)
                    retryViewport.BackgroundTransparency = 1
                    retryViewport.ZIndex = 104
                    retryViewport.Parent = parent

                    self.logger:info("✅ PET IMAGE LOADED AFTER RETRY", {
                        itemId = item.id,
                        petType = item.petType,
                        variant = item.variant,
                    })
                    return
                end
            end
        end)

        return fallbackIcon
    end
end

-- 🎛️ GET UI DISPLAY METHOD (User preference + Configuration-based)
function InventoryPanel:_getDisplayMethod(context)
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer

    if not player then
        return "images" -- Safe fallback
    end

    -- Use simplified DisplayPreferences utility
    local DisplayPreferences = require(script.Parent.Parent.Parent.Utils.DisplayPreferences)
    local result = DisplayPreferences.GetDisplayMethod(context)

    self.logger:info("Using display preference", {
        context = context,
        method = result,
        source = "SettingsService",
    })

    return result
end

-- 🔍 GET PET IMAGE FROM ASSETS (Helper function)
function InventoryPanel:_getPetImageFromAssets(petType, variant, quiet)
    -- Try to get image from ReplicatedStorage.Assets.Images.Pets
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local success, imageViewport = pcall(function()
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        if not assetsFolder then
            return nil
        end

        local imagesFolder = assetsFolder:FindFirstChild("Images")
        if not imagesFolder then
            return nil
        end

        local petsImagesFolder = imagesFolder:FindFirstChild("Pets")
        if not petsImagesFolder then
            return nil
        end

        local petTypeFolder = petsImagesFolder:FindFirstChild(petType)
        if not petTypeFolder then
            return nil
        end

        local petImageViewport = petTypeFolder:FindFirstChild(variant)
        if not petImageViewport then
            return nil
        end

        -- Clone the ViewportFrame to avoid "Parent property is locked" errors
        return petImageViewport:Clone()
    end)

    if success and imageViewport then
        self.logger:info("🎯 PET IMAGE FOUND", {
            petType = petType,
            variant = variant,
            path = "ReplicatedStorage.Assets.Images.Pets." .. petType .. "." .. variant,
        })
        return imageViewport
    elseif not quiet then
        self.logger:warn("🚫 PET IMAGE NOT FOUND", {
            petType = petType,
            variant = variant,
            error = success and "Image not found" or imageViewport,
        })
    end
    return nil
end

-- 🎮 3D VIEWPORT CREATION (For ViewportFrame display mode)
function InventoryPanel:_create3DPetIcon(parent, item)
    self.logger:info(
        "🎮 CREATING 3D VIEWPORT",
        { itemId = item.id, petType = item.petType, variant = item.variant }
    )

    -- Create ViewportFrame for 3D model
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "PetViewport"
    viewport.Size = UDim2.new(1, 0, 1, 0) -- Fill the iconBG
    viewport.Position = UDim2.new(0, 0, 0, 0)
    viewport.BackgroundTransparency = 1
    viewport.ZIndex = 104
    viewport.Parent = parent

    -- Create camera
    local camera = Instance.new("Camera")
    camera.Parent = viewport
    viewport.CurrentCamera = camera

    -- Load the 3D model
    self:_load3DPetModel(viewport, camera, item)

    return viewport
end

function InventoryPanel:_createEmojiFallback(viewport, item)
    -- Create emoji icon as fallback when 3D model fails
    local fallbackIcon = Instance.new("TextLabel")
    fallbackIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
    fallbackIcon.Position = UDim2.new(0.1, 0, 0.1, 0)
    fallbackIcon.BackgroundTransparency = 1
    fallbackIcon.Text = item.icon
    fallbackIcon.TextScaled = true
    fallbackIcon.Font = Enum.Font.GothamBold
    fallbackIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
    fallbackIcon.ZIndex = 105
    fallbackIcon.Parent = viewport
end

-- 🎮 3D PET MODEL LOADING (For ViewportFrame display mode)
function InventoryPanel:_load3DPetModel(viewport, camera, item)
    local InsertService = game:GetService("InsertService")
    local Locations = require(game:GetService("ReplicatedStorage").Shared.Locations)
    local petConfig = Locations.getConfig("pets")

    task.spawn(function()
        local success, result = pcall(function()
            -- Get pet data from config
            local petData = petConfig.getPet(item.petType, item.variant)
            if not petData or not petData.asset_id then
                self.logger:warn("No pet data or asset ID found", {
                    petType = item.petType,
                    variant = item.variant,
                })
                return
            end

            -- Try to load from ReplicatedStorage.Assets first (like egg system)
            local modelClone = nil
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

            if assetsFolder then
                local modelsFolder = assetsFolder:FindFirstChild("Models")
                if modelsFolder then
                    local petsFolder = modelsFolder:FindFirstChild("Pets")
                    if petsFolder then
                        local petTypeFolder = petsFolder:FindFirstChild(item.petType)
                        if petTypeFolder then
                            local petModel = petTypeFolder:FindFirstChild(item.variant)
                            if petModel then
                                modelClone = petModel:Clone()
                                self.logger:debug(
                                    "Loaded pet model from ReplicatedStorage.Assets",
                                    {
                                        petType = item.petType,
                                        variant = item.variant,
                                        path = petModel:GetFullName(),
                                    }
                                )
                            end
                        end
                    end
                end
            end

            -- Fallback to InsertService loading
            if not modelClone then
                local assetId = petData.asset_id
                if assetId and assetId ~= "rbxassetid://0" then
                    local assetNumber = tonumber(assetId:match("%d+"))
                    if assetNumber then
                        local asset = InsertService:LoadAsset(assetNumber)
                        modelClone = asset:FindFirstChildOfClass("Model")
                        if modelClone then
                            modelClone = modelClone:Clone()
                            self.logger:debug("Loaded pet model from InsertService", {
                                assetId = assetId,
                                petType = item.petType,
                                variant = item.variant,
                            })
                        end
                        asset:Destroy()
                    end
                end
            end

            if not modelClone then
                self.logger:warn("Failed to load pet model, creating emoji fallback", {
                    petType = item.petType,
                    variant = item.variant,
                    assetId = petData.asset_id,
                })

                -- Create emoji fallback in the viewport
                self:_createEmojiFallback(viewport, item)
                return
            end

            if petVisualsOk and PetVariantVisuals then
                PetVariantVisuals.ApplyServerMetadata(modelClone, item.petType, item.variant)
                PetVariantVisuals.ApplyStaticVisuals(modelClone)
            end

            local transform = getAssetTransform(petData)
            applyUnbakedAssetTransform(modelClone, transform)

            if item.huge == true then
                local assetScale = tonumber(modelClone:GetAttribute("AssetScale"))
                    or transform.scale
                    or 1
                local hugeScale = tonumber(modelClone:GetAttribute("HugeScale"))
                    or transform.hugeScale
                    or 1
                if hugeScale and hugeScale > 0 then
                    modelClone:ScaleTo(assetScale * hugeScale)
                end
            end

            -- Position model in viewport
            local modelCFrame = CFrame.new(0, 0, 0)
            if modelClone.PrimaryPart then
                modelClone:SetPrimaryPartCFrame(modelCFrame)
            else
                modelClone:MoveTo(modelCFrame.Position)
            end

            modelClone.Parent = viewport

            -- Calculate camera position
            local modelSize = modelClone:GetExtentsSize()
            local zoomMultiplier = petData.viewport_zoom or 1.5
            local baseDistance = math.max(modelSize.X, modelSize.Y, modelSize.Z) * 1.2 -- Slightly closer for inventory
            local distance = baseDistance / zoomMultiplier

            -- Safety clamp
            if distance < 1 then
                distance = 1
            end

            local modelPosition = modelClone:GetBoundingBox().Position

            if item.huge == true then
                local _, boundingSize = modelClone:GetBoundingBox()
                local target = modelPosition + Vector3.new(0, boundingSize.Y * 0.22, 0)
                local closeDistance = math.max(0.8, math.max(boundingSize.X, boundingSize.Z) * 0.7)
                local cameraDirection = getCameraDirection(petData.camera)
                camera.FieldOfView = 58
                camera.CFrame = CFrame.new(target + cameraDirection * closeDistance, target)

                self.logger:info("Huge pet close-up loaded in inventory", {
                    petType = item.petType,
                    variant = item.variant,
                    modelSize = boundingSize,
                    distance = closeDistance,
                    camera = petData.camera,
                })
                return
            end

            -- Set up rotating camera (like egg system)
            local cameraAngle = 0
            local rotationSpeed = 2 -- degrees per frame
            local connection

            connection = game:GetService("RunService").Heartbeat:Connect(function()
                if viewport.Parent and modelClone.Parent then
                    -- Rotate camera around the model
                    camera.CFrame = CFrame.Angles(0, math.rad(cameraAngle), 0)
                        * CFrame.new(modelPosition + Vector3.new(0, 0, distance), modelPosition)
                    cameraAngle = cameraAngle + rotationSpeed
                    if cameraAngle >= 360 then
                        cameraAngle = 0
                    end
                else
                    -- Clean up if viewport or model is destroyed
                    connection:Disconnect()
                end
            end)

            self.logger:info("3D pet model loaded in inventory", {
                petType = item.petType,
                variant = item.variant,
                modelSize = modelSize,
                distance = distance,
            })
        end)

        if not success then
            self.logger:warn("Failed to load 3D pet model, creating emoji fallback", {
                error = result,
                petType = item.petType,
                variant = item.variant,
            })

            -- Create emoji fallback on error
            self:_createEmojiFallback(viewport, item)
        end
    end)
end

function InventoryPanel:_extractPetDataFromFolder(petFolder)
    local petData = {}

    -- Required fields (match what InventoryService actually creates)
    local itemId = petFolder:FindFirstChild("ItemId") -- Changed from "PetType"
    local variant = petFolder:FindFirstChild("variant") -- Changed from "Variant" (case)

    if not itemId or not variant then
        self.logger:warn("Invalid pet folder structure", {
            folderName = petFolder.Name,
            hasItemId = itemId ~= nil,
            hasVariant = variant ~= nil,
            children = {},
        })

        -- Debug: List all children to see what's actually there
        local actualChildren = {}
        for _, child in pairs(petFolder:GetChildren()) do
            table.insert(actualChildren, child.Name .. " (" .. child.ClassName .. ")")
        end

        self.logger:warn("🔍 PET FOLDER DEBUG - Available children", {
            folderName = petFolder.Name,
            children = actualChildren,
        })

        return nil
    end

    petData.id = itemId.Value
    petData.variant = variant.Value

    -- Optional fields
    local level = petFolder:FindFirstChild("level") -- Changed case
    if level then
        petData.level = level.Value
    end

    -- Stats are in a folder structure
    local statsFolder = petFolder:FindFirstChild("stats")
    if statsFolder and statsFolder:IsA("Folder") then
        petData.stats = {}

        local health = statsFolder:FindFirstChild("health")
        if health then
            petData.stats.health = health.Value
        end

        local speed = statsFolder:FindFirstChild("speed")
        if speed then
            petData.stats.speed = speed.Value
        end
    else
        -- Fallback: try direct children (in case structure is different)
        local health = petFolder:FindFirstChild("health")
        local speed = petFolder:FindFirstChild("speed")

        if health or speed then
            petData.stats = {
                health = health and health.Value or 100,
                speed = speed and speed.Value or 1.0,
            }
        end
    end

    local nickname = petFolder:FindFirstChild("nickname") -- Changed case
    if nickname then
        petData.nickname = nickname.Value
    end

    return petData
end

function InventoryPanel:_updateItemsDisplay()
    -- Cleanup old right-click connections to prevent memory leaks
    if self._rightClickConnections then
        for itemId, connection in pairs(self._rightClickConnections) do
            if connection then
                connection:Disconnect()
            end
        end
        self._rightClickConnections = {}
    end

    -- Clear existing items in both grids
    local function clearChildren(container)
        if container then
            for _, child in ipairs(container:GetChildren()) do
                -- item cards are Frames; the empty-slot rings are ImageLabels named EmptySlotRing.
                -- Clear BOTH each rebuild, else stale empty rings leak in and pile up (the layout
                -- helpers UIGridLayout/UIPadding are neither, so they survive).
                if child:IsA("Frame") or child.Name == "EmptySlotRing" then
                    child:Destroy()
                end
            end
        end
    end
    clearChildren(self.equippedGrid)
    clearChildren(self.inventoryGrid)
    self.itemFrames = {}

    -- Get current category folders for filtering
    local categoryFolders = self:_getCategoryFolders(self.selectedCategory)

    -- Filter items
    local filteredItems = {}
    for _, item in ipairs(self.inventoryData) do
        local matchesCategory =
            self:_itemMatchesCategory(item, self.selectedCategory, categoryFolders)
        local matchesSearch = (
            self.searchTerm == "" or item.name:lower():find(self.searchTerm, 1, true)
        )

        if matchesCategory and matchesSearch then
            table.insert(filteredItems, item)
        end
    end

    -- Sort: equipped first, then by power desc, then by count desc, then name
    table.sort(filteredItems, function(a, b)
        local aEquipped = self:_isItemEquipped(a)
        local bEquipped = self:_isItemEquipped(b)
        if aEquipped ~= bEquipped then
            return aEquipped and not bEquipped
        end
        local ap = tonumber(a.power) or 0
        local bp = tonumber(b.power) or 0
        if ap == bp then
            -- tie-break: stacks with higher count first
            local ac = tonumber(a.count) or 1
            local bc = tonumber(b.count) or 1
            if ac ~= bc then
                return ac > bc
            end
            return tostring(a.name) < tostring(b.name)
        end
        return ap > bp
    end)

    -- Create item frames into equipped or inventory sections
    local eqIndex, invIndex = 1, 1
    for _, item in ipairs(filteredItems) do
        local isStack = typeof(item.id) == "string" and string.sub(item.id, 1, 6) == "stack|"
        local isEquipped = self:_isItemEquipped(item)
        if isStack then
            isEquipped = false
        end -- keep the stack in inventory
        local container = isEquipped and self.equippedGrid or self.inventoryGrid
        self:_createItemFrameInto(item, isEquipped and eqIndex or invIndex, container)
        if isEquipped then
            eqIndex += 1
        else
            invIndex += 1
        end
    end

    -- Add ghost cards for equipped instances drawn from stacks (one per equipped UID)
    if self.equippedItems and self.equippedItems.pets then
        for equippedUid, _ in pairs(self.equippedItems.pets) do
            if typeof(equippedUid) == "string" then
                local parts = string.split(equippedUid, "|")
                if #parts >= 2 and parts[1] == "stack" then
                    local stackKey = parts[2]
                    local stackData = self._stackDataByKey and self._stackDataByKey[stackKey]
                    if stackData then
                        local ghost = table.clone(stackData)
                        ghost.id = "equipped_instance|" .. equippedUid
                        ghost.uid = equippedUid
                        ghost.count = 1
                        self:_createItemFrameInto(ghost, eqIndex, self.equippedGrid)
                        eqIndex += 1
                    end
                end
            end
        end
    end

    -- Pad the equipped row with blank rings for the remaining open slots (eqIndex-1 = # filled).
    self:_renderEmptySlotRings(eqIndex - 1)
end

function InventoryPanel:_getCategoryFolders(categoryName)
    -- Get folders that belong to the selected category
    if not self.inventoryConfig or not self.inventoryConfig.display_categories then
        -- Fallback mapping for legacy categories
        local fallbackMapping = {
            All = { "pets", "consumables", "tools", "eggs", "resources" },
            Pets = { "pets" },
            Items = { "consumables" },
            Eggs = { "eggs" },
            Tools = { "tools" },
            Resources = { "resources" },
        }
        return fallbackMapping[categoryName] or {}
    end

    -- Find the category in configuration
    for _, categoryConfig in ipairs(self.inventoryConfig.display_categories) do
        if categoryConfig.name == categoryName then
            return categoryConfig.folders
        end
    end

    return {}
end

function InventoryPanel:_itemMatchesCategory(item, categoryName, categoryFolders)
    -- "All" category shows everything
    if categoryName == "All" then
        return true
    end

    -- Check if item's folder source is in the category's folder list
    if item.folder_source then
        for _, folderName in ipairs(categoryFolders) do
            if item.folder_source == folderName then
                self.logger:debug("✅ FILTER MATCH", {
                    item = item.name,
                    category = categoryName,
                    folder_source = item.folder_source,
                    matched_folder = folderName,
                })
                return true
            end
        end
        self.logger:debug("❌ FILTER NO MATCH", {
            item = item.name,
            category = categoryName,
            folder_source = item.folder_source,
            available_folders = categoryFolders,
        })
        return false -- Don't fall back to legacy if folder_source exists
    end

    -- Fallback: check legacy category field (only if no folder_source)
    local legacyMatch = item.category == categoryName
    self.logger:debug("🔄 FILTER LEGACY", {
        item = item.name,
        category = categoryName,
        item_category = item.category,
        matched = legacyMatch,
    })
    return legacyMatch
end

function InventoryPanel:_colorSequenceFromList(colors, fallbackColor)
    local usableColors = {}
    if type(colors) == "table" then
        for _, color in ipairs(colors) do
            if typeof(color) == "Color3" then
                table.insert(usableColors, color)
            end
        end
    end

    if #usableColors == 0 then
        usableColors = { fallbackColor or Color3.fromRGB(45, 45, 55) }
    end
    if #usableColors == 1 then
        return ColorSequence.new(usableColors[1])
    end

    local keypoints = {}
    for index, color in ipairs(usableColors) do
        local t = (index - 1) / (#usableColors - 1)
        table.insert(keypoints, ColorSequenceKeypoint.new(t, color))
    end
    return ColorSequence.new(keypoints)
end

function InventoryPanel:_getPetCardVisualConfig()
    return (
        self.inventoryConfig
        and self.inventoryConfig.buckets
        and self.inventoryConfig.buckets.pets
        and self.inventoryConfig.buckets.pets.card_visuals
    ) or {}
end

function InventoryPanel:_getPetCardVisualStyle(item)
    local config = self:_getPetCardVisualConfig()
    local rarityId = tostring(item.rarityId or item.rarity or "common"):lower()
    local variantId = tostring(item.variant or "basic"):lower()

    local ringConfig = (config.rarity_rings and config.rarity_rings[rarityId])
        or config.ring_default
        or {}
    local variantRingConfig = variantId ~= "basic"
            and config.variant_rings
            and config.variant_rings[variantId]
        or nil
    local backgroundConfig = (config.variant_backgrounds and config.variant_backgrounds[variantId])
        or (config.variant_backgrounds and config.variant_backgrounds.basic)
        or {}

    return {
        ring = ringConfig,
        rarityRing = ringConfig,
        variantRing = variantRingConfig,
        background = backgroundConfig,
    }
end

function InventoryPanel:_animateGradientRotation(gradient, seconds)
    if not gradient then
        return
    end

    local tween = TweenService:Create(
        gradient,
        TweenInfo.new(seconds or 3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
        { Rotation = 360 }
    )
    tween:Play()
end

function InventoryPanel:_createItemFrameInto(item, layoutOrder, parentContainer)
    -- Item frame
    local itemFrame = Instance.new("Frame")
    itemFrame.Name = item.id
    local cardStyle = self:_getPetCardVisualStyle(item)
    itemFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    itemFrame.BorderSizePixel = 0
    itemFrame.LayoutOrder = layoutOrder
    itemFrame.ZIndex = 102
    itemFrame.Size = UDim2.new(0, self.cardSize.X, 0, self.cardSize.Y)
    print("cardSize", self.cardSize)
    itemFrame.Parent = parentContainer or self.itemsGrid

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = itemFrame

    -- Pet border: rarity owns the outer frame; variant treatments layer inside it.
    local stroke = Instance.new("UIStroke")
    stroke.Name = "RarityStroke"
    stroke.Color = item.color
    stroke.Thickness = tonumber(cardStyle.ring.thickness) or 2
    stroke.Transparency = 0
    stroke.Parent = itemFrame
    stroke:SetAttribute("BaseThickness", stroke.Thickness)

    local ringGradient = Instance.new("UIGradient")
    ringGradient.Name = "RarityRingGradient"
    ringGradient.Color = self:_colorSequenceFromList(cardStyle.ring.colors, item.color)
    ringGradient.Rotation = tonumber(cardStyle.ring.rotation) or 0
    ringGradient.Parent = stroke
    if cardStyle.ring.animated == true then
        self:_animateGradientRotation(ringGradient, tonumber(cardStyle.ring.rotation_seconds) or 3)
    end

    if cardStyle.variantRing then
        local variantFrame = Instance.new("Frame")
        variantFrame.Name = "VariantStrokeFrame"
        variantFrame.BackgroundTransparency = 1
        variantFrame.BorderSizePixel = 0
        variantFrame.Position = UDim2.new(0, 4, 0, 4)
        variantFrame.Size = UDim2.new(1, -8, 1, -8)
        variantFrame.ZIndex = 104
        variantFrame.Parent = itemFrame

        local variantCorner = Instance.new("UICorner")
        variantCorner.CornerRadius = UDim.new(0, 9)
        variantCorner.Parent = variantFrame

        local variantStroke = Instance.new("UIStroke")
        variantStroke.Name = "VariantStroke"
        variantStroke.Color = item.color
        variantStroke.Thickness = tonumber(cardStyle.variantRing.thickness) or 2
        variantStroke.Transparency = 0
        variantStroke.Parent = variantFrame

        local variantGradient = Instance.new("UIGradient")
        variantGradient.Name = "VariantRingGradient"
        variantGradient.Color =
            self:_colorSequenceFromList(cardStyle.variantRing.colors, item.color)
        variantGradient.Rotation = tonumber(cardStyle.variantRing.rotation) or 0
        variantGradient.Parent = variantStroke
        if cardStyle.variantRing.animated == true then
            self:_animateGradientRotation(
                variantGradient,
                tonumber(cardStyle.variantRing.rotation_seconds) or 3
            )
        end
    end

    -- Background gradient
    local gradient = Instance.new("UIGradient")
    gradient.Name = "VariantBackgroundGradient"
    gradient.Color =
        self:_colorSequenceFromList(cardStyle.background.colors, Color3.fromRGB(45, 45, 55))
    gradient.Rotation = tonumber(cardStyle.background.rotation) or 45
    gradient.Parent = itemFrame
    if cardStyle.background.animated == true then
        self:_animateGradientRotation(
            gradient,
            tonumber(cardStyle.background.rotation_seconds) or 5
        )
    end

    -- Item icon background
    local iconBG = Instance.new("Frame")
    local configuredIconSize: Vector2? = nil
    local configuredIconScale: number? = nil
    do
        -- Load UI config via Locations to avoid scope issues with ConfigLoader
        local okUI, uiCfg = pcall(function()
            return Locations.getConfig("ui")
        end)
        if
            okUI
            and uiCfg
            and uiCfg.panel_configs
            and uiCfg.panel_configs.inventory_panel
            and uiCfg.panel_configs.inventory_panel.grid
        then
            local g = uiCfg.panel_configs.inventory_panel.grid
            if g.icon_size and typeof(g.icon_size) == "Vector2" then
                configuredIconSize = g.icon_size
            end
            if typeof(g.icon_scale) == "number" then
                configuredIconScale = g.icon_scale
            end
        end
    end
    local iconSize = configuredIconSize and configuredIconSize.X
        or (configuredIconScale and math.floor(
            self.cardSize.X * math.clamp(configuredIconScale, 0.1, 1.2)
        ))
        or math.floor(self.cardSize.X * 0.5)
    iconBG.Size = UDim2.new(0, iconSize, 0, iconSize)
    iconBG.Position =
        UDim2.new(0.5, -math.floor(iconSize / 2), 0, math.floor(self.cardSize.Y * 0.08))
    iconBG.BackgroundColor3 = item.color
    iconBG.BackgroundTransparency = 0.8
    iconBG.BorderSizePixel = 0
    iconBG.ZIndex = 103
    iconBG.Parent = itemFrame

    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(0, math.floor(self.cardSize.X * 0.3))
    iconCorner.Parent = iconBG

    if cardStyle.variantRing then
        iconBG.BackgroundTransparency = 0.35
        local iconGradient = Instance.new("UIGradient")
        iconGradient.Name = "VariantIconGradient"
        iconGradient.Color = self:_colorSequenceFromList(cardStyle.variantRing.colors, item.color)
        iconGradient.Rotation = tonumber(cardStyle.variantRing.rotation) or 0
        iconGradient.Parent = iconBG
        if cardStyle.variantRing.animated == true then
            self:_animateGradientRotation(
                iconGradient,
                tonumber(cardStyle.variantRing.rotation_seconds) or 3
            )
        end
    end

    -- Item icon (3D model or emoji fallback)
    self.logger:info("🎨 CREATING ICON", {
        itemId = item.id,
        use3DModel = item.use3DModel,
        petType = item.petType,
        variant = item.variant,
        icon = item.icon,
    })

    if item.use3DModel then
        -- Check configuration to determine display method
        local displayMethod = self:_getDisplayMethod("inventory")

        if displayMethod == "images" then
            -- Use pre-generated pet image
            self.logger:info(
                "🖼️ USING PET IMAGE",
                { itemId = item.id, petType = item.petType, config = "images" }
            )
            local imageIcon = self:_createPetImageIcon(iconBG, item)
        elseif displayMethod == "viewports" then
            -- Use 3D ViewportFrame
            self.logger:info(
                "🎮 USING 3D VIEWPORT",
                { itemId = item.id, petType = item.petType, config = "viewports" }
            )
            local viewport = self:_create3DPetIcon(iconBG, item)
        else
            -- Unknown config, default to images
            self.logger:warn("🚨 UNKNOWN DISPLAY METHOD, defaulting to images", {
                displayMethod = displayMethod,
                itemId = item.id,
            })
            local imageIcon = self:_createPetImageIcon(iconBG, item)
        end
    elseif item.folder_source == "enhancements" and item.enhancement_type and item.origins then
        -- the SAME two-layer badge as the PowerChoiceMenu ENHANCE strip (one assembly path):
        -- disc = first origin's color + type symbol, ring tinted the second origin's color
        PetBadge.createEnhancementBadge(iconBG, {
            size = UDim2.fromScale(0.92, 0.92),
            position = UDim2.fromScale(0.5, 0.5),
            anchor = Vector2.new(0.5, 0.5),
            record = { type = item.enhancement_type, origins = item.origins },
            zindex = 104,
        })
        if item.level then
            -- level chip, top-left (pets use that spot for the equipped check — free here)
            local lvl = Instance.new("TextLabel")
            lvl.Name = "EnhLevel"
            local lW = math.max(16, math.floor(self.cardSize.X * 0.3))
            local lH = math.max(12, math.floor(self.cardSize.Y * 0.2))
            local lM = math.max(2, math.floor(self.cardSize.X * 0.05))
            lvl.Size = UDim2.fromOffset(lW, lH)
            lvl.Position = UDim2.fromOffset(lM, lM)
            lvl.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
            lvl.BackgroundTransparency = 0.25
            lvl.Text = "L" .. tostring(item.level)
            lvl.TextColor3 = item.color or Color3.fromRGB(255, 255, 255)
            lvl.TextScaled = true
            lvl.Font = Enum.Font.GothamBold
            lvl.ZIndex = 105
            lvl.Parent = itemFrame
            local lc = Instance.new("UICorner")
            lc.CornerRadius = UDim.new(0, 5)
            lc.Parent = lvl
        end
    else
        -- Use emoji fallback
        self.logger:info("🎭 USING EMOJI FALLBACK", { itemId = item.id, icon = item.icon })
        local icon = Instance.new("TextLabel")
        local calcBase = iconSize
        if configuredIconSize then
            calcBase = configuredIconSize.Y
        elseif configuredIconScale then
            calcBase = math.floor(self.cardSize.Y * math.clamp(configuredIconScale, 0.1, 1.2))
        end
        local ti = math.max(8, math.floor(calcBase * 0.8))
        icon.Size = UDim2.new(0, ti, 0, ti)
        icon.Position = UDim2.new(0.5, -math.floor(ti / 2), 0.5, -math.floor(ti / 2))
        icon.BackgroundTransparency = 1
        icon.Text = item.icon
        icon.TextScaled = true
        icon.Font = Enum.Font.GothamBold
        icon.ZIndex = 104
        icon.Parent = iconBG
    end

    -- Quantity badge (top-right)
    local qty = tonumber(item.count) or 1
    if qty > 1 then
        local qtyLabel = Instance.new("TextLabel")
        qtyLabel.Name = "QtyLabel"
        local qW = math.max(12, math.floor(self.cardSize.X * 0.28))
        local qH = math.max(10, math.floor(self.cardSize.Y * 0.22))
        local qM = math.max(2, math.floor(self.cardSize.X * 0.06))
        qtyLabel.Size = UDim2.new(0, qW, 0, qH)
        qtyLabel.Position = UDim2.new(1, -qW - qM, 0, qM)
        qtyLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        qtyLabel.BorderSizePixel = 0
        qtyLabel.Text = "×" .. tostring(qty)
        qtyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        qtyLabel.TextScaled = true
        qtyLabel.Font = Enum.Font.GothamBold
        qtyLabel.ZIndex = 105
        qtyLabel.Parent = itemFrame
        local qc = Instance.new("UICorner")
        qc.CornerRadius = UDim.new(0, 6)
        qc.Parent = qtyLabel
    end

    -- Equipped icon (top-left)
    local equippedIcon = Instance.new("TextLabel")
    equippedIcon.Name = "EquippedIcon"
    local eW = math.max(12, math.floor(self.cardSize.X * 0.28))
    local eH = math.max(10, math.floor(self.cardSize.Y * 0.22))
    local eM = math.max(2, math.floor(self.cardSize.X * 0.06))
    equippedIcon.Size = UDim2.new(0, eW, 0, eH)
    equippedIcon.Position = UDim2.new(0, eM, 0, eM)
    equippedIcon.BackgroundTransparency = 1
    equippedIcon.Text = self:_isItemEquipped(item) and "✓" or ""
    equippedIcon.TextColor3 = Color3.fromRGB(255, 215, 0)
    equippedIcon.TextScaled = true
    equippedIcon.Font = Enum.Font.GothamBold
    equippedIcon.ZIndex = 105
    equippedIcon.Parent = itemFrame

    -- Name (center bottom) and strength below it (configurable spacing)
    local nameLabel = Instance.new("TextLabel")
    local powerLabel = Instance.new("TextLabel")

    local nameHeightScale = 0.17
    local nameBottomOffsetScale = 0.31
    local powerHeightScale = 0.14
    local powerBottomOffsetScale = 0.17
    local nameFont = Enum.Font.GothamBold
    local nameColor = Color3.fromRGB(255, 255, 255)
    local powerFont = Enum.Font.Gotham
    local powerPrefix = "⚡ "
    local powerColorOverride: Color3? = nil
    local useRarityColorForPower = true

    do
        local okUI, uiCfg = pcall(function()
            return ConfigLoader:LoadConfig("ui")
        end)
        if
            okUI
            and uiCfg
            and uiCfg.panel_configs
            and uiCfg.panel_configs.inventory_panel
            and uiCfg.panel_configs.inventory_panel.grid
        then
            local g = uiCfg.panel_configs.inventory_panel.grid
            if typeof(g.name_label) == "table" then
                nameHeightScale = typeof(g.name_label.height_scale) == "number"
                        and g.name_label.height_scale
                    or nameHeightScale
                nameBottomOffsetScale = typeof(g.name_label.bottom_offset_scale) == "number"
                        and g.name_label.bottom_offset_scale
                    or nameBottomOffsetScale
                if typeof(g.name_label.font) == "EnumItem" then
                    nameFont = g.name_label.font
                end
                if typeof(g.name_label.color) == "Color3" then
                    nameColor = g.name_label.color
                end
            end
            if typeof(g.power_label) == "table" then
                powerHeightScale = typeof(g.power_label.height_scale) == "number"
                        and g.power_label.height_scale
                    or powerHeightScale
                powerBottomOffsetScale = typeof(g.power_label.bottom_offset_scale) == "number"
                        and g.power_label.bottom_offset_scale
                    or powerBottomOffsetScale
                if typeof(g.power_label.font) == "EnumItem" then
                    powerFont = g.power_label.font
                end
                if typeof(g.power_label.prefix) == "string" then
                    powerPrefix = g.power_label.prefix
                end
                if typeof(g.power_label.color) == "Color3" then
                    powerColorOverride = g.power_label.color
                end
                if typeof(g.power_label.color_from_rarity) == "boolean" then
                    useRarityColorForPower = g.power_label.color_from_rarity
                end
            end
        end
    end

    nameLabel.Size = UDim2.new(1, -8, 0, math.max(8, math.floor(self.cardSize.Y * nameHeightScale)))
    nameLabel.Position =
        UDim2.new(0, 4, 1, -math.max(12, math.floor(self.cardSize.Y * nameBottomOffsetScale)))
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = item.name
    nameLabel.TextColor3 = nameColor
    nameLabel.TextScaled = true
    nameLabel.Font = nameFont
    nameLabel.ZIndex = 103
    nameLabel.Parent = itemFrame

    powerLabel.Name = "PowerLabel"
    powerLabel.Size =
        UDim2.new(1, -8, 0, math.max(6, math.floor(self.cardSize.Y * powerHeightScale)))
    powerLabel.Position =
        UDim2.new(0, 4, 1, -math.max(8, math.floor(self.cardSize.Y * powerBottomOffsetScale)))
    powerLabel.BackgroundTransparency = 1
    -- Pet cards show the TWO intrinsic numbers (⛏ mining / ⚔ combat) from PetPower so the card
    -- matches what the pet actually does in-world. item.power is the player-independent base
    -- (huge/level-aware); context multipliers (player level, boosts) are intentionally excluded so
    -- the number is the same for everyone (fair trade comparison). Non-pets keep the single power.
    local powerText = (item.power and (powerPrefix .. tostring(item.power))) or ""
    if item.folder_source == "enhancements" and item.origins_label then
        powerText = item.origins_label -- "Geo/Cryo" under the type name, in the rarity color
    end
    if PetPowerView and item.category == "Pets" and item.petType and item.power then
        local okProfile, profile = pcall(function()
            return PetPowerView.profile({
                base = item.power,
                petType = item.petType,
                variant = item.variant,
            })
        end)
        if okProfile and profile then
            powerText = string.format(
                "⛏ %d  ⚔ %d",
                PetPowerView.displayRound(profile.miningBase),
                PetPowerView.displayRound(profile.combatBase)
            )
        end
    end
    powerLabel.Text = powerText
    powerLabel.TextColor3 = (useRarityColorForPower and item.color)
        or powerColorOverride
        or item.color
    powerLabel.TextScaled = true
    powerLabel.Font = powerFont
    powerLabel.ZIndex = 103
    powerLabel.Parent = itemFrame

    -- Archetype chip (top-left): identifies the pet's role at a glance — Tank / Melee /
    -- Blaster / Buffer / Control — so buffers (the per-zone support pets) are easy to spot.
    if PetPowerView and item.category == "Pets" and item.petType then
        local okRole, role = pcall(function()
            return PetPowerView.roleInfo(item.petType, item.role)
        end)
        if okRole and role and role.label then
            -- Preferred: the universal element-disc + tinted-ring BADGE (top-left, square).
            local built = false
            if PetBadge then
                local element = PetBadge.elementForPetType(item.petType)
                -- Relative: a square badge sized to ~half the card's HEIGHT (aspect-ratio
                -- constraint), poking off the top-left corner by a fraction of the card. No
                -- pixel math — it scales with cardSize automatically.
                local holder = Instance.new("Frame")
                holder.Name = "RoleBadge"
                holder.Size = UDim2.new(1, 0, 0.5, 0) -- full width box, half-height -> square fits to height
                holder.Position = UDim2.fromScale(-0.1, -0.1)
                holder.BackgroundTransparency = 1
                holder.ZIndex = 106
                holder.Parent = itemFrame
                local hAspect = Instance.new("UIAspectRatioConstraint")
                hAspect.AspectRatio = 1
                hAspect.AspectType = Enum.AspectType.FitWithinMaxSize
                hAspect.Parent = holder
                local b =
                    PetBadge.create(holder, { element = element, role = role.id, zIndex = 106 })
                built = b and b.disc and b.disc.Visible == true
                if not built then
                    holder:Destroy() -- no disc art for this (element, role) -> fall back to text chip
                end
            end
            -- Fallback: the original coloured text chip (Tank / Melee / ...).
            if not built then
                local tint = role.color and Color3.fromRGB(role.color.r, role.color.g, role.color.b)
                    or Color3.fromRGB(70, 70, 90)
                local chip = Instance.new("TextLabel")
                chip.Name = "RoleChip"
                chip.Size = UDim2.new(
                    0,
                    math.max(28, math.floor(self.cardSize.X * 0.5)),
                    0,
                    math.max(10, math.floor(self.cardSize.Y * 0.16))
                )
                chip.Position = UDim2.new(0, 3, 0, 3)
                chip.BackgroundColor3 = tint
                chip.BackgroundTransparency = 0.15
                chip.Text = " " .. tostring(role.label) .. " "
                chip.TextColor3 = Color3.fromRGB(255, 255, 255)
                chip.TextScaled = true
                chip.Font = Enum.Font.GothamBold
                chip.ZIndex = 104
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 4)
                corner.Parent = chip
                chip.Parent = itemFrame
            end
        end
    end

    -- Support buff this pet PROVIDES (bottom-right): the per-zone buffer pets (bunny=Heal,
    -- penguin=Defense, emberimp=Offense, meerkat=Coin Yield) emit a team aura — surface it so
    -- "what does a meerkat do?" reads at a glance. Element-disc (biome colour) + short label.
    if POWER_ICONS and PET_ROLES and item.category == "Pets" and item.petType then
        local aura = PET_ROLES.support_auras and PET_ROLES.support_auras[item.petType]
        local meta = aura and SUPPORT_META[aura.kind]
        local symbol = aura and POWER_ICONS.support_symbol and POWER_ICONS.support_symbol[aura.kind]
        local disc = meta and symbol and POWER_ICONS.discFor(meta.element, symbol)
        if disc then
            local holder = Instance.new("Frame")
            holder.Name = "SupportBadge"
            holder.Size = UDim2.new(0.4, 0, 0.4, 0) -- square (aspect), ~40% of card
            holder.Position = UDim2.fromScale(0.66, 0.5) -- lower-right corner, slight overhang
            holder.BackgroundTransparency = 1
            holder.ZIndex = 107
            holder.Parent = itemFrame
            local aspect = Instance.new("UIAspectRatioConstraint")
            aspect.AspectRatio = 1
            aspect.AspectType = Enum.AspectType.FitWithinMaxSize
            aspect.Parent = holder
            local img = Instance.new("ImageLabel")
            img.Name = "Icon"
            img.Size = UDim2.fromScale(1, 1)
            img.BackgroundTransparency = 1
            img.Image = disc
            img.ScaleType = Enum.ScaleType.Fit
            img.ZIndex = 107
            img.Parent = holder
            -- short label hugging the bottom of the card
            local lbl = Instance.new("TextLabel")
            lbl.Name = "SupportLabel"
            lbl.Size = UDim2.new(1, -4, 0, math.max(8, math.floor(self.cardSize.Y * 0.15)))
            lbl.Position = UDim2.new(0, 2, 1, -math.max(8, math.floor(self.cardSize.Y * 0.15)))
            lbl.BackgroundTransparency = 1
            lbl.Text = meta.label
            lbl.TextColor3 = Color3.fromRGB(255, 230, 140)
            lbl.TextStrokeTransparency = 0.3
            lbl.TextScaled = true
            lbl.Font = Enum.Font.GothamBold
            lbl.TextXAlignment = Enum.TextXAlignment.Right
            lbl.ZIndex = 107
            lbl.Parent = itemFrame
        end
    end

    -- Add interaction system (includes hover effects)
    -- DEBUG SPAM SUPPRESSED
    self:_addItemInteractions(itemFrame, item)
    -- DEBUG SPAM SUPPRESSED

    -- Apply equipped styling if item is equipped
    local isEquipped = self:_isItemEquipped(item)
    self:_applyEquippedStyling(itemFrame, isEquipped, item.color)

    -- #179 down-lockout identity (read by _refreshLockoutVisuals for the availability ring / red
    -- count). Equipped = lives in the equipped grid; stacks key off <id:variant>, specials off uid.
    do
        local ref = (type(item.uid) == "string" and item.uid) or item.id
        if type(ref) == "string" and ref:sub(1, 6) == "stack|" then
            itemFrame:SetAttribute("LockKind", "stack")
            itemFrame:SetAttribute("LockId", (string.split(ref, "|"))[2] or "")
        elseif type(item.uid) == "string" and item.uid ~= "" then
            itemFrame:SetAttribute("LockKind", "special")
            itemFrame:SetAttribute("LockId", item.uid)
        end
        itemFrame:SetAttribute("LockEquipped", itemFrame.Parent == self.equippedGrid)
    end
    -- Store reference
    table.insert(self.itemFrames, itemFrame)
    -- Index by stack key for live count updates
    if item.id:sub(1, 6) == "stack|" then
        self._stackFrames = self._stackFrames or {}
        self._stackDataByKey = self._stackDataByKey or {}
        local key = item.uid or item.id:sub(7)
        self._stackFrames[key] = itemFrame
        self._stackDataByKey[key] = item
    end
end

function InventoryPanel:_selectCategory(categoryName)
    self.selectedCategory = categoryName

    -- Update category tabs visual state
    local categoryContainer = self.frame:FindFirstChild("CategoryContainer")
    if categoryContainer then
        for _, tab in ipairs(categoryContainer:GetChildren()) do
            if tab:IsA("TextButton") then
                local isSelected = tab.Name:find(categoryName)
                tab.BackgroundColor3 = isSelected and Color3.fromRGB(52, 152, 219)
                    or Color3.fromRGB(40, 40, 50)
            end
        end
    end

    -- Update items display
    self:_updateItemsDisplay()
end

function InventoryPanel:_addButtonHoverEffect(button, originalColor)
    button.MouseEnter:Connect(function()
        local tween = TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
            BackgroundColor3 = Color3.new(
                math.min(1, originalColor.R + 0.1),
                math.min(1, originalColor.G + 0.1),
                math.min(1, originalColor.B + 0.1)
            ),
        })
        tween:Play()
    end)

    button.MouseLeave:Connect(function()
        local tween = TweenService:Create(
            button,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad),
            { BackgroundColor3 = originalColor }
        )
        tween:Play()
    end)
end

function InventoryPanel:_addItemHoverEffect(itemFrame)
    local originalSize = itemFrame.Size
    local stroke = itemFrame:FindFirstChild("UIStroke")

    itemFrame.MouseEnter:Connect(function()
        local sizeTween =
            TweenService:Create(itemFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Size = UDim2.new(
                    originalSize.X.Scale,
                    originalSize.X.Offset + 5,
                    originalSize.Y.Scale,
                    originalSize.Y.Offset + 5
                ),
            })
        sizeTween:Play()

        if stroke then
            local strokeTween = TweenService:Create(
                stroke,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                { Transparency = 0, Thickness = 3 }
            )
            strokeTween:Play()
        end
    end)

    itemFrame.MouseLeave:Connect(function()
        local sizeTween = TweenService:Create(
            itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            { Size = originalSize }
        )
        sizeTween:Play()

        if stroke then
            local strokeTween = TweenService:Create(
                stroke,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                { Transparency = 0.3, Thickness = 2 }
            )
            strokeTween:Play()
        end
    end)
end

function InventoryPanel:_animateEntrance()
    -- Start slightly off-screen and transparent
    self.frame.Position = UDim2.new(0.5, 0, 0.5, 50)
    self.frame.BackgroundTransparency = 1

    -- Animate to final position
    local tween = TweenService:Create(
        self.frame,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(0.5, 0, 0.5, 0),
            BackgroundTransparency = 0,
        }
    )
    tween:Play()
end

-- Public interface methods
function InventoryPanel:IsVisible()
    return self.isVisible
end

function InventoryPanel:GetFrame()
    return self.frame
end

function InventoryPanel:UpdateInventory(newData)
    if newData then
        self.inventoryData = newData
        if self.isVisible then
            self:_updateItemsDisplay()
        end
    end
end

-- 🔄 REAL-TIME INVENTORY UPDATES
function InventoryPanel:RefreshFromRealData()
    if self.isVisible then
        self:_loadRealInventoryData()
        self:_refreshCategoryTabs() -- Update category counts too
        self:_updateItemsDisplay()
        self.logger:info("Inventory refreshed from real data")
    end
end

function InventoryPanel:_formatNumber(value)
    local numberValue = tonumber(value)
    if not numberValue then
        return "-"
    end
    if math.abs(numberValue - math.floor(numberValue)) < 0.001 then
        return tostring(math.floor(numberValue))
    end
    return string.format("%.1f", numberValue)
end

function InventoryPanel:_hideItemTooltip()
    if self.itemTooltip then
        self.itemTooltip:Destroy()
        self.itemTooltip = nil
    end
end

function InventoryPanel:_formatTooltipFieldLabel(fieldName)
    local labels = self._petTooltipFieldsConfig and self._petTooltipFieldsConfig.labels
    if type(labels) == "table" and labels[fieldName] then
        return tostring(labels[fieldName])
    end

    local words = {}
    for word in tostring(fieldName):gmatch("[^_]+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2))
    end
    return table.concat(words, " ")
end

function InventoryPanel:_formatTooltipFieldValue(value)
    if type(value) == "boolean" then
        return value and "Yes" or "No"
    end
    if type(value) == "number" then
        return self:_formatNumber(value)
    end
    return tostring(value)
end

function InventoryPanel:_readNumberValue(folder, names)
    if not folder then
        return nil
    end
    for _, name in ipairs(names) do
        local value = folder:FindFirstChild(name)
        if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
            return tonumber(value.Value)
        end
    end
    return nil
end

function InventoryPanel:_readStringValue(folder, names)
    if not folder then
        return nil
    end
    for _, name in ipairs(names) do
        local value = folder:FindFirstChild(name)
        if value and value:IsA("StringValue") then
            return value.Value
        end
    end
    return nil
end

function InventoryPanel:_readBoolValue(folder, names)
    if not folder then
        return nil
    end
    for _, name in ipairs(names) do
        local value = folder:FindFirstChild(name)
        if value and value:IsA("BoolValue") then
            return value.Value
        end
    end
    return nil
end

function InventoryPanel:_readPrimitiveValues(folder)
    local values = {}
    if not folder then
        return values
    end
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("StringValue") or child:IsA("BoolValue") then
            values[child.Name] = child.Value
        elseif child:IsA("NumberValue") or child:IsA("IntValue") then
            values[child.Name] = tonumber(child.Value)
        end
    end
    return values
end

function InventoryPanel:_countFolderChildren(folder, names)
    if not folder then
        return 0
    end
    for _, name in ipairs(names) do
        local child = folder:FindFirstChild(name)
        if child and child:IsA("Folder") then
            return #child:GetChildren()
        end
    end
    return 0
end

function InventoryPanel:_readEnchantSummaries(folder)
    local summaries = {}
    if not folder then
        return summaries
    end

    local enchantFolder = folder:FindFirstChild("enchantments")
        or folder:FindFirstChild("Enchantments")
    if not enchantFolder or not enchantFolder:IsA("Folder") then
        return summaries
    end

    local children = enchantFolder:GetChildren()
    table.sort(children, function(a, b)
        return tostring(a.Name) < tostring(b.Name)
    end)
    for _, child in ipairs(children) do
        if child:IsA("Folder") then
            local id = self:_readStringValue(child, { "id", "Id" })
            local displayName = self:_readStringValue(child, { "display_name", "DisplayName" })
                or id
                or child.Name
            local strength =
                self:_readNumberValue(child, { "strength", "Strength", "value", "Value" })
            local profile = self:_readStringValue(child, { "roll_profile", "RollProfile" })
            table.insert(summaries, {
                id = id,
                displayName = displayName,
                strength = strength,
                profile = profile,
            })
        end
    end

    return summaries
end

function InventoryPanel:_getReplicatedSpecialPetFolder(uid)
    if type(uid) ~= "string" or uid == "" or not self.player then
        return nil
    end

    local inventoryFolder = self.player:FindFirstChild("Inventory")
    local petsFolder = inventoryFolder and inventoryFolder:FindFirstChild("pets")
    local specialFolder = petsFolder and petsFolder:FindFirstChild("Special")
    return specialFolder and specialFolder:FindFirstChild(uid) or nil
end

function InventoryPanel:_getConfiguredPetPower(petType, variant, level, isHuge)
    local okPets, petsConfig = pcall(function()
        return ConfigLoader:LoadConfig("pets")
    end)
    if not okPets or not petsConfig or not petsConfig.getPet then
        return nil
    end

    local pdata = petsConfig.getPet(petType, variant)
    -- Shared source of truth (huge-aware): huge pets use huge_base_power.
    local base = PetPower.configuredBasePower(pdata, isHuge == true)
    if base <= 0 then
        return nil
    end

    local progressionConfig = select(
        2,
        pcall(function()
            return ConfigLoader:LoadConfig("pet_progression")
        end)
    )
    return PetPower.withLevel(base, level, progressionConfig)
end

function InventoryPanel:_refreshPetTooltipFromReplicatedState(item)
    if not item or item.category ~= "Pets" or not item.special or type(item.uid) ~= "string" then
        return item
    end

    local petFolder = self:_getReplicatedSpecialPetFolder(item.uid)
    if not petFolder then
        return item
    end

    local level = self:_readNumberValue(petFolder, { "level", "Level" }) or item.level or 1
    local exp = self:_readNumberValue(petFolder, { "exp", "Exp", "xp", "XP" }) or item.exp or 0
    local maxLevel = self:_readNumberValue(petFolder, { "max_level", "MaxLevel" }) or item.maxLevel
    local xpToNext = self:_readNumberValue(
        petFolder,
        { "xp_to_next_level", "XpToNextLevel", "XPToNextLevel" }
    ) or item.xpToNextLevel

    item.level = math.max(1, math.floor(tonumber(level) or 1))
    item.exp = math.max(0, math.floor(tonumber(exp) or 0))
    item.maxLevel = maxLevel and math.max(1, math.floor(tonumber(maxLevel) or 1)) or nil
    item.xpToNextLevel = xpToNext and math.max(0, math.floor(tonumber(xpToNext) or 0)) or nil
    item.unlockedEnchantSlots = self:_readNumberValue(
        petFolder,
        { "unlocked_enchant_slots", "UnlockedEnchantSlots" }
    ) or item.unlockedEnchantSlots
    item.maxEnchantments = self:_readNumberValue(
        petFolder,
        { "max_enchantments", "MaxEnchantments", "MaxEnchants" }
    ) or item.maxEnchantments
    item.enchantmentCount = self:_countFolderChildren(petFolder, { "enchantments", "Enchantments" })
    item.enchantments = self:_readEnchantSummaries(petFolder)
    item.locked = self:_readBoolValue(petFolder, { "locked", "Locked" })

    local tooltipFields = self:_readPrimitiveValues(petFolder)
    local hatcherName = self:_readStringValue(petFolder, { "hatcher_name", "HatcherName" })
        or self:_readStringValue(petFolder, { "source", "Source" })
    if hatcherName then
        tooltipFields.hatcher_name = hatcherName
    end
    item.tooltipFields = tooltipFields

    local isHuge = self:_readBoolValue(petFolder, { "huge", "Huge" }) == true or item.huge == true
    local basePower = self:_getConfiguredPetPower(item.petType, item.variant, 1, isHuge)
    local leveledPower = self:_getConfiguredPetPower(item.petType, item.variant, item.level, isHuge)
    if basePower then
        item.basePower = basePower
    end
    if leveledPower then
        item.power = leveledPower
        item.effectivePower = math.max(tonumber(item.effectivePower) or 0, leveledPower)
    end

    return item
end

function InventoryPanel:_appendConfiguredTooltipFields(lines, item)
    local fields = item and item.tooltipFields
    if type(fields) ~= "table" then
        return
    end

    local config = self._petTooltipFieldsConfig or {}
    local hidden = {}
    for _, fieldName in ipairs(config.hidden or {}) do
        hidden[fieldName] = true
    end
    for _, fieldName in ipairs({
        "level",
        "Level",
        "exp",
        "Exp",
        "xp",
        "XP",
        "max_level",
        "MaxLevel",
        "xp_to_next_level",
        "XpToNextLevel",
        "XPToNextLevel",
    }) do
        hidden[fieldName] = true
    end

    local appended = {}
    local function appendField(fieldName)
        if appended[fieldName] or hidden[fieldName] then
            return
        end
        local value = fields[fieldName]
        if value == nil or value == "" or type(value) == "table" then
            return
        end

        appended[fieldName] = true
        table.insert(lines, {
            label = self:_formatTooltipFieldLabel(fieldName),
            value = self:_formatTooltipFieldValue(value),
        })
    end

    for _, fieldName in ipairs(config.order or {}) do
        appendField(fieldName)
    end

    local fieldNames = {}
    for fieldName in pairs(fields) do
        table.insert(fieldNames, fieldName)
    end
    table.sort(fieldNames)

    for _, fieldName in ipairs(fieldNames) do
        appendField(fieldName)
    end
end

function InventoryPanel:_showItemTooltip(item)
    if not self.frame or not item then
        return
    end

    self:_hideItemTooltip()
    item = self:_refreshPetTooltipFromReplicatedState(item)

    -- Enhancements get their OWN tooltip — the pet fields (Type/Variant/Power/Enchants)
    -- are meaningless for them (Jason: "it's not distinguishing... we need to give
    -- different information").
    if item.folder_source == "enhancements" then
        local okCfg, enhCfg = pcall(function()
            return require(ReplicatedStorage.Configs:WaitForChild("enhancements"))
        end)
        local values = (okCfg and enhCfg and enhCfg.values) or {}
        local single = item.rarity == "Single"
        local value = single and values.single or values.dual
        local originNames = {}
        for _, o in ipairs(item.origins or {}) do
            originNames[#originNames + 1] = o:sub(1, 1):upper() .. o:sub(2)
        end
        local lines = {
            {
                label = "Boosts",
                value = tostring(item.enhancement_type or "?"):gsub("^%l", string.upper),
            },
            { label = "Level", value = tostring(item.level or "?") },
            {
                label = "Grade",
                value = (item.rarity or "?")
                    .. (value and (" (+" .. math.floor(value * 100 + 0.5) .. "%)") or ""),
            },
            {
                label = single and "Origin" or "Origins",
                value = #originNames > 0 and table.concat(originNames, " + ") or "Unknown",
            },
            {
                label = "Usable by",
                value = #originNames > 0 and table.concat(originNames, " or ") or "—",
            },
            { label = "Slot via", value = "Level-up menu → ENHANCE" },
        }
        item.tooltip_title = (#originNames > 0 and (item.origins_label .. " ") or "")
            .. tostring(item.name or "Enhancement")
        self:_renderItemTooltip(item, lines)
        return
    end

    local lines = {
        { label = "Rarity", value = item.rarity or "-" },
        { label = "Type", value = item.petType or "-" },
        { label = "Variant", value = item.variant or "-" },
        { label = "Power", value = self:_formatNumber(item.effectivePower or item.power) },
    }

    if item.basePower and item.effectivePower and item.basePower ~= item.effectivePower then
        table.insert(lines, { label = "Base", value = self:_formatNumber(item.basePower) })
    end
    if item.special and item.maxLevel and item.maxLevel > 1 then
        table.insert(lines, {
            label = "Level",
            value = tostring(item.level or 1) .. "/" .. tostring(item.maxLevel),
        })
        local xpToNext = tonumber(item.xpToNextLevel) or 0
        if xpToNext > 0 then
            table.insert(lines, {
                label = "XP",
                value = self:_formatNumber(item.exp or 0) .. "/" .. self:_formatNumber(xpToNext),
            })
        else
            table.insert(lines, { label = "XP", value = "Max" })
        end
    end
    if tonumber(item.eternalPercent) and tonumber(item.eternalPercent) > 0 then
        table.insert(lines, {
            label = "Eternal",
            value = self:_formatNumber(item.eternalPercent) .. "% of top-team average",
        })
    end
    if item.eternalBaselinePower then
        table.insert(lines, {
            label = "Baseline",
            value = self:_formatNumber(item.eternalBaselinePower),
        })
    end
    if item.huge then
        table.insert(lines, {
            label = "Huge",
            value = item.serial and ("#" .. tostring(item.serial)) or "Yes",
        })
    elseif item.serial then
        table.insert(lines, { label = "Serial", value = "#" .. tostring(item.serial) })
    end
    if item.enchantable then
        local maxEnchantments = tonumber(item.maxEnchantments) or 0
        local unlockedEnchantSlots = tonumber(item.unlockedEnchantSlots) or maxEnchantments
        local enchantmentCount = tonumber(item.enchantmentCount) or 0
        local value = tostring(enchantmentCount)
        if unlockedEnchantSlots > 0 then
            value = value .. "/" .. tostring(unlockedEnchantSlots)
            if maxEnchantments > unlockedEnchantSlots then
                value = value .. " (max " .. tostring(maxEnchantments) .. ")"
            end
        elseif maxEnchantments > 0 then
            value = value .. "/0 (max " .. tostring(maxEnchantments) .. ")"
        end
        table.insert(lines, { label = "Enchants", value = value })
        for index, enchant in ipairs(item.enchantments or {}) do
            local strength = tonumber(enchant.strength)
            local suffix = strength and (" +" .. self:_formatNumber(strength)) or ""
            table.insert(lines, {
                label = "Enchant " .. tostring(index),
                value = tostring(enchant.displayName or enchant.id or "-") .. suffix,
            })
        end
    elseif item.enchantmentCount and item.enchantmentCount > 0 then
        table.insert(lines, { label = "Enchants", value = tostring(item.enchantmentCount) })
    else
        table.insert(lines, { label = "Enchants", value = "None" })
    end
    if item.locked ~= nil then
        table.insert(lines, { label = "Locked", value = item.locked and "Yes" or "No" })
    end
    if item.serialSource and item.serialSource ~= "" then
        table.insert(lines, { label = "Serial Source", value = tostring(item.serialSource) })
    end
    self:_appendConfiguredTooltipFields(lines, item)
    if item.count and item.count > 1 then
        table.insert(lines, { label = "Owned", value = tostring(item.count) })
    end

    self:_renderItemTooltip(item, lines)
end

-- Shared tooltip frame renderer (pet + enhancement paths both feed it their lines).
function InventoryPanel:_renderItemTooltip(item, lines)
    local tooltip = Instance.new("Frame")
    tooltip.Name = "ItemTooltip"
    tooltip.Size = UDim2.new(0, 250, 0, 52 + (#lines * 22))
    tooltip.Position = UDim2.new(1, -270, 0, 72)
    tooltip.BackgroundColor3 = Color3.fromRGB(24, 25, 32)
    tooltip.BorderSizePixel = 0
    tooltip.ZIndex = 300
    tooltip.Parent = self.frame
    self.itemTooltip = tooltip

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = tooltip

    local stroke = Instance.new("UIStroke")
    stroke.Color = item.color or Color3.fromRGB(120, 130, 150)
    stroke.Thickness = 2
    stroke.Transparency = 0.15
    stroke.Parent = tooltip

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -20, 0, 28)
    title.Position = UDim2.new(0, 10, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = item.tooltip_title or item.name or "Pet"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.ZIndex = 301
    title.Parent = tooltip

    for index, line in ipairs(lines) do
        local row = Instance.new("TextLabel")
        row.Name = "Line" .. tostring(index)
        row.Size = UDim2.new(1, -20, 0, 20)
        row.Position = UDim2.new(0, 10, 0, 34 + ((index - 1) * 22))
        row.BackgroundTransparency = 1
        row.Text = tostring(line.label) .. ": " .. tostring(line.value)
        row.TextColor3 = Color3.fromRGB(215, 220, 230)
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.TextScaled = true
        row.Font = Enum.Font.Gotham
        row.ZIndex = 301
        row.Parent = tooltip
    end
end

-- 🖱️ ITEM INTERACTION SYSTEM
function InventoryPanel:_addItemInteractions(itemFrame, item)
    -- DEBUG SPAM SUPPRESSED
    self.logger:info("🔧 ADDING INTERACTIONS", {
        itemId = item.id,
        itemName = item.name,
        hasSignals = self.signals ~= nil,
    })

    -- Left-click: Primary action (consume/equip)
    local leftClickDetection = Instance.new("TextButton")
    leftClickDetection.Size = UDim2.new(1, 0, 1, 0)
    leftClickDetection.BackgroundTransparency = 1
    leftClickDetection.Text = ""
    leftClickDetection.ZIndex = 105
    leftClickDetection.Parent = itemFrame

    leftClickDetection.Activated:Connect(function()
        -- DEBUG SPAM SUPPRESSED
        self:_handlePrimaryAction(item)
    end)

    -- Right-click: Context menu (using UserInputService with frame detection)
    local isMouseOverFrame = false

    leftClickDetection.MouseEnter:Connect(function()
        isMouseOverFrame = true
        self:_showItemTooltip(item)
    end)

    leftClickDetection.MouseLeave:Connect(function()
        isMouseOverFrame = false
        self:_hideItemTooltip()
    end)

    -- Global right-click detection (but only act if over this frame)
    local userInputService = game:GetService("UserInputService")
    local rightClickConnection = userInputService.InputBegan:Connect(function(input, gameProcessed)
        -- print("🔍 RIGHT CLICK INPUT:", input.UserInputType, "gameProcessed:", gameProcessed, "isMouseOver:", isMouseOverFrame, "for item:", item.id)

        -- For right-clicks, we ignore gameProcessed because we want to handle custom context menus
        -- For left-clicks, we still respect gameProcessed to avoid conflicts with normal UI
        if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
            return -- Only handle right-clicks in this listener
        end

        -- right-click debug removed (noisy)
        if isMouseOverFrame then
            print("🖱️ RIGHT CLICK DETECTED ON:", item.id)
            local mouse = Players.LocalPlayer:GetMouse()
            self.logger:info(
                "🖱️ RIGHT CLICK ON ITEM",
                { itemId = item.id, x = mouse.X, y = mouse.Y }
            )
            self:_showAdvancedContextMenu(item, mouse.X, mouse.Y)
        else
            -- skip noisy spam
        end
    end)

    -- Store connection for cleanup (prevent memory leaks)
    if not self._rightClickConnections then
        self._rightClickConnections = {}
    end
    self._rightClickConnections[item.id] = rightClickConnection

    -- DEBUG SPAM SUPPRESSED

    -- CONSOLIDATED: Enhanced hover effects for visual feedback
    local originalSize = itemFrame.Size
    local stroke = itemFrame:FindFirstChild("UIStroke")
    -- DEBUG SPAM SUPPRESSED

    -- UPDATED MouseEnter to include BOTH tracking AND hover effects
    itemFrame.MouseEnter:Connect(function()
        isMouseOverFrame = true
        self:_showItemTooltip(item)
        -- DEBUG SPAM SUPPRESSED

        -- Background color change
        local bgTween = TweenService:Create(
            itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            { BackgroundColor3 = Color3.fromRGB(55, 55, 65) }
        )
        bgTween:Play()

        -- Size increase
        local sizeTween =
            TweenService:Create(itemFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Size = UDim2.new(
                    originalSize.X.Scale,
                    originalSize.X.Offset + 5,
                    originalSize.Y.Scale,
                    originalSize.Y.Offset + 5
                ),
            })
        sizeTween:Play()

        -- Stroke enhancement
        if stroke then
            local strokeTween = TweenService:Create(
                stroke,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                { Transparency = 0, Thickness = 3 }
            )
            strokeTween:Play()
        end
    end)

    -- UPDATED MouseLeave to include BOTH tracking AND hover effects
    itemFrame.MouseLeave:Connect(function()
        isMouseOverFrame = false
        self:_hideItemTooltip()
        -- DEBUG SPAM SUPPRESSED

        -- Background color reset
        local bgTween = TweenService:Create(
            itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            { BackgroundColor3 = Color3.fromRGB(45, 45, 55) }
        )
        bgTween:Play()

        -- Size reset
        local sizeTween = TweenService:Create(
            itemFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            { Size = originalSize }
        )
        sizeTween:Play()

        -- Stroke reset
        if stroke then
            local strokeTween = TweenService:Create(
                stroke,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                { Transparency = 0.3, Thickness = 2 }
            )
            strokeTween:Play()
        end
    end)
end

function InventoryPanel:_showDeleteConfirmation(item)
    self.logger:info("🗑️ ITEM DELETE REQUESTED", { itemId = item.id, itemName = item.name })

    -- Create confirmation dialog
    local confirmFrame = Instance.new("Frame")
    confirmFrame.Name = "DeleteConfirmation"
    confirmFrame.Size = UDim2.new(0, 300, 0, 150)
    confirmFrame.Position = UDim2.new(0.5, -150, 0.5, -75)
    confirmFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    confirmFrame.BorderSizePixel = 0
    confirmFrame.ZIndex = 200
    confirmFrame.Parent = self.frame

    local confirmCorner = Instance.new("UICorner")
    confirmCorner.CornerRadius = UDim.new(0, 12)
    confirmCorner.Parent = confirmFrame

    local confirmStroke = Instance.new("UIStroke")
    confirmStroke.Color = Color3.fromRGB(231, 76, 60)
    confirmStroke.Thickness = 2
    confirmStroke.Parent = confirmFrame

    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 30)
    titleLabel.Position = UDim2.new(0, 10, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Delete Item?"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 18
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.ZIndex = 201
    titleLabel.Parent = confirmFrame

    -- Message
    local messageLabel = Instance.new("TextLabel")
    messageLabel.Size = UDim2.new(1, -20, 0, 40)
    messageLabel.Position = UDim2.new(0, 10, 0, 45)
    messageLabel.BackgroundTransparency = 1
    messageLabel.Text = "Are you sure you want to delete:\n" .. item.name .. "?"
    messageLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    messageLabel.TextSize = 14
    messageLabel.Font = Enum.Font.Gotham
    messageLabel.ZIndex = 201
    messageLabel.TextWrapped = true
    messageLabel.Parent = confirmFrame

    -- Warning for valuable items
    if item.power and item.power > 10 then
        local warningLabel = Instance.new("TextLabel")
        warningLabel.Size = UDim2.new(1, -20, 0, 20)
        warningLabel.Position = UDim2.new(0, 10, 0, 85)
        warningLabel.BackgroundTransparency = 1
        warningLabel.Text = "⚠️ This item cannot be recovered!"
        warningLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
        warningLabel.TextSize = 12
        warningLabel.Font = Enum.Font.GothamBold
        warningLabel.ZIndex = 201
        warningLabel.Parent = confirmFrame
    end

    -- Buttons
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Size = UDim2.new(1, -20, 0, 35)
    buttonContainer.Position = UDim2.new(0, 10, 1, -45)
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.ZIndex = 201
    buttonContainer.Parent = confirmFrame

    local buttonLayout = Instance.new("UIListLayout")
    buttonLayout.FillDirection = Enum.FillDirection.Horizontal
    buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
    buttonLayout.Padding = UDim.new(0, 10)
    buttonLayout.Parent = buttonContainer

    -- Cancel button
    local cancelButton = Instance.new("TextButton")
    cancelButton.Size = UDim2.new(0, 80, 1, 0)
    cancelButton.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
    cancelButton.BorderSizePixel = 0
    cancelButton.Text = "Cancel"
    cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    cancelButton.TextSize = 14
    cancelButton.Font = Enum.Font.Gotham
    cancelButton.LayoutOrder = 1
    cancelButton.ZIndex = 202
    cancelButton.Parent = buttonContainer

    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0, 6)
    cancelCorner.Parent = cancelButton

    -- Delete button
    local deleteButton = Instance.new("TextButton")
    deleteButton.Size = UDim2.new(0, 80, 1, 0)
    deleteButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
    deleteButton.BorderSizePixel = 0
    deleteButton.Text = "Delete"
    deleteButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    deleteButton.TextSize = 14
    deleteButton.Font = Enum.Font.GothamBold
    deleteButton.LayoutOrder = 2
    deleteButton.ZIndex = 202
    deleteButton.Parent = buttonContainer

    local deleteCorner = Instance.new("UICorner")
    deleteCorner.CornerRadius = UDim.new(0, 6)
    deleteCorner.Parent = deleteButton

    -- Button actions
    cancelButton.Activated:Connect(function()
        confirmFrame:Destroy()
    end)

    deleteButton.Activated:Connect(function()
        confirmFrame:Destroy()
        self:_deleteItem(item)
    end)

    -- Entrance animation
    confirmFrame.BackgroundTransparency = 1
    confirmFrame.Size = UDim2.new(0, 0, 0, 0)
    confirmFrame.Position = UDim2.new(0.5, 0, 0.5, 0)

    local tween = TweenService:Create(
        confirmFrame,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            BackgroundTransparency = 0,
            Size = UDim2.new(0, 300, 0, 150),
            Position = UDim2.new(0.5, -150, 0.5, -75),
        }
    )
    tween:Play()
end

-- 🎮 PRIMARY ACTIONS (Left-click)
function InventoryPanel:_handlePrimaryAction(item)
    -- DEBUG SPAM SUPPRESSED
    self.logger:info("🖱️ PRIMARY ACTION", {
        itemId = item.id,
        itemName = item.name,
        folder_source = item.folder_source,
        count = item.count,
    })

    if item.folder_source == "consumables" then
        -- Consume the item
        self:_consumeItem(item)
    elseif item.folder_source == "pets" then
        -- Equip/unequip pet
        self:_togglePetEquipped(item)
    elseif item.folder_source == "tools" then
        -- Equip/unequip tool
        self:_toggleToolEquipped(item)
    else
        -- Default: Show info
        self:_showItemInfo(item)
    end
end

function InventoryPanel:_consumeItem(item)
    self.logger:info("🍎 CONSUMING ITEM", { itemId = item.id, itemName = item.name })

    if self.signals then
        self.signals.ConsumeItem:FireServer({
            bucket = item.folder_source,
            itemUid = item.uid,
            itemId = item.id,
            quantity = 1,
        })
        self.logger:info("✅ Consume request sent to server")
    else
        self.logger:warn("❌ Signals not available for consumption")
    end
end

function InventoryPanel:_togglePetEquipped(item)
    self.logger:info("🐾 TOGGLING PET EQUIPPED", { itemId = item.id, itemName = item.name })

    if self.signals then
        local payload = { bucket = item.folder_source, itemId = item.id }
        local equippedUid = self:_getEquippedUidForPetItem(item)
        if equippedUid then
            payload.itemUid = equippedUid
        elseif typeof(item.id) == "string" and string.sub(item.id, 1, 6) == "stack|" then
            local stackKey = string.sub(item.id, 7)
            payload.itemUid = "stack|"
                .. stackKey
                .. "|"
                .. game:GetService("HttpService"):GenerateGUID(false)
            payload.isStackEquip = true
        elseif typeof(item.uid) == "string" and string.sub(item.uid, 1, 6) == "stack|" then
            -- Only generate a new instance if this is NOT a ghost equipped instance
            if
                not (
                    typeof(item.id) == "string"
                    and string.sub(item.id, 1, 18) == "equipped_instance|"
                )
            then
                local stackKey = string.sub(item.uid, 7)
                payload.itemUid = "stack|"
                    .. stackKey
                    .. "|"
                    .. game:GetService("HttpService"):GenerateGUID(false)
                payload.isStackEquip = true
            else
                payload.itemUid = item.uid -- toggle existing equipped instance
            end
        elseif typeof(item.uid) == "string" and string.find(item.uid, ":", 1, true) then
            -- Legacy stack key (id:variant)
            payload.itemUid = "stack|"
                .. item.uid
                .. "|"
                .. game:GetService("HttpService"):GenerateGUID(false)
            payload.isStackEquip = true
        elseif typeof(item.id) == "string" and string.find(item.id, ":", 1, true) then
            payload.itemUid = "stack|"
                .. item.id
                .. "|"
                .. game:GetService("HttpService"):GenerateGUID(false)
            payload.isStackEquip = true
        else
            -- Unique/special: use exact UID
            payload.itemUid = item.uid
        end
        self.signals.TogglePetEquipped:FireServer(payload)
        self.logger:info("✅ Toggle pet request sent to server")
    else
        self.logger:warn("❌ Signals not available for pet equipping")
    end
end

function InventoryPanel:_getPetStackKey(item)
    if typeof(item.uid) == "string" then
        if string.sub(item.uid, 1, 6) == "stack|" then
            return string.sub(item.uid, 7)
        end
        if string.find(item.uid, ":", 1, true) then
            return item.uid
        end
    end

    if typeof(item.id) == "string" then
        if string.sub(item.id, 1, 6) == "stack|" then
            return string.sub(item.id, 7)
        end
        if string.find(item.id, ":", 1, true) then
            return item.id
        end
    end

    return nil
end

function InventoryPanel:_getEquippedUidForPetItem(item)
    if not (self.equippedItems and self.equippedItems.pets) then
        return nil
    end

    if typeof(item.id) == "string" and string.sub(item.id, 1, 18) == "equipped_instance|" then
        return item.uid
    end

    if typeof(item.id) == "string" and string.sub(item.id, 1, 6) == "stack|" then
        return nil
    end

    local rawUid = item.uid
    if typeof(rawUid) == "string" then
        if string.sub(rawUid, 1, 6) == "stack|" then
            return nil
        end

        if self.equippedItems.pets[rawUid] then
            return rawUid
        end

        local specialUid = "special|" .. rawUid
        if self.equippedItems.pets[specialUid] then
            return specialUid
        end
    end

    return nil
end

function InventoryPanel:_toggleToolEquipped(item)
    self.logger:info("🔧 TOGGLING TOOL EQUIPPED", { itemId = item.id, itemName = item.name })

    if self.signals then
        self.signals.ToggleToolEquipped:FireServer({
            bucket = item.folder_source,
            itemUid = item.uid,
            itemId = item.id,
        })
        self.logger:info("✅ Toggle tool request sent to server")
    else
        self.logger:warn("❌ Signals not available for tool equipping")
    end
end

-- 🖱️ ADVANCED CONTEXT MENU (Right-click)
function InventoryPanel:_showAdvancedContextMenu(item, x, y)
    print("🖱️ SHOWING CONTEXT MENU FOR:", item.id, "at", x, y)
    self.logger:info("🖱️ ADVANCED CONTEXT MENU", { itemId = item.id, x = x, y = y })

    -- Calculate menu size based on available options
    local menuOptions = self:_getContextMenuOptions(item)
    local menuHeight = #menuOptions * 35 + 10

    -- Clamp menu position to screen bounds
    local screenSize = workspace.CurrentCamera.ViewportSize
    local clampedX = math.min(x, screenSize.X - 160) -- Leave 10px margin
    local clampedY = math.min(y, screenSize.Y - menuHeight - 10)
    clampedX = math.max(clampedX, 10) -- Minimum 10px from left edge
    clampedY = math.max(clampedY, 10) -- Minimum 10px from top edge

    print(
        "📍 CLAMPED POSITION: x="
            .. clampedX
            .. " y="
            .. clampedY
            .. " (screen: "
            .. screenSize.X
            .. "x"
            .. screenSize.Y
            .. ")"
    )

    -- Create ScreenGui container (required for visibility)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ContextMenuGui"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = Players.LocalPlayer.PlayerGui

    -- Create context menu
    local contextMenu = Instance.new("Frame")
    contextMenu.Name = "AdvancedContextMenu"
    contextMenu.Size = UDim2.new(0, 150, 0, menuHeight)
    contextMenu.Position = UDim2.new(0, clampedX, 0, clampedY)
    contextMenu.BackgroundColor3 = Color3.fromRGB(255, 100, 100) -- BRIGHT RED for testing
    contextMenu.BackgroundTransparency = 0 -- Make it fully opaque
    contextMenu.BorderSizePixel = 2 -- Add visible border
    contextMenu.BorderColor3 = Color3.fromRGB(255, 255, 0) -- YELLOW border
    contextMenu.ZIndex = 1000 -- Much higher ZIndex
    -- Parent to ScreenGui (this makes it visible!)
    contextMenu.Parent = screenGui

    -- Debug: Print the exact path
    local fullPath = contextMenu:GetFullName()
    print("🔍 CONTEXT MENU FULL PATH:", fullPath)
    print("🔍 PLAYER GUI CHILDREN COUNT:", #Players.LocalPlayer.PlayerGui:GetChildren())

    local menuCorner = Instance.new("UICorner")
    menuCorner.CornerRadius = UDim.new(0, 8)
    menuCorner.Parent = contextMenu

    local menuStroke = Instance.new("UIStroke")
    menuStroke.Color = Color3.fromRGB(100, 100, 110)
    menuStroke.Thickness = 1
    menuStroke.Parent = contextMenu

    local menuLayout = Instance.new("UIListLayout")
    menuLayout.FillDirection = Enum.FillDirection.Vertical
    menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
    menuLayout.Padding = UDim.new(0, 2)
    menuLayout.Parent = contextMenu

    local menuPadding = Instance.new("UIPadding")
    menuPadding.PaddingTop = UDim.new(0, 5)
    menuPadding.PaddingBottom = UDim.new(0, 5)
    menuPadding.PaddingLeft = UDim.new(0, 5)
    menuPadding.PaddingRight = UDim.new(0, 5)
    menuPadding.Parent = contextMenu

    -- Create menu options
    print("📋 CREATING", #menuOptions, "MENU OPTIONS")
    for i, option in ipairs(menuOptions) do
        print("🔧 CREATING OPTION:", option.text, "action:", option.action)
        self:_createContextMenuOption(contextMenu, option, i, item)
    end

    local parentName = contextMenu.Parent and contextMenu.Parent.Name or "nil"
    print(
        "✅ CONTEXT MENU CREATED - Parent:",
        parentName,
        "Position:",
        contextMenu.Position,
        "Size:",
        contextMenu.Size
    )

    -- Auto-close functionality (pass ScreenGui to destroy the whole thing)
    self:_setupContextMenuAutoClose(screenGui)
end

function InventoryPanel:_getContextMenuOptions(item)
    local options = {}

    -- Get configuration for this item type
    local itemType = item.folder_source or "unknown"
    local config = self.contextMenuConfig

    if not config then
        -- Fallback if no config loaded
        return self:_getFallbackContextMenuOptions(item)
    end

    -- Get item type configuration
    local typeConfig = config.item_types[itemType] or config.fallback
    if not typeConfig or not typeConfig.actions then
        return self:_getFallbackContextMenuOptions(item)
    end

    print("🎯 USING CONFIG FOR ITEM TYPE:", itemType, "actions:", #typeConfig.actions)

    -- Process base actions for this item type
    for _, actionConfig in ipairs(typeConfig.actions) do
        self:_addConfiguredAction(options, actionConfig, item)
    end

    -- Add item-specific overrides if they exist
    if typeConfig.item_overrides and typeConfig.item_overrides[item.id] then
        local overrides = typeConfig.item_overrides[item.id]
        if overrides.additional_actions then
            print("🔧 ADDING ITEM-SPECIFIC ACTIONS FOR:", item.id)
            for _, actionConfig in ipairs(overrides.additional_actions) do
                self:_addConfiguredAction(options, actionConfig, item)
            end
        end
    end

    -- Sort by order
    table.sort(options, function(a, b)
        return (a.order or 999) < (b.order or 999)
    end)

    print("📋 FINAL OPTIONS COUNT:", #options)

    return options
end

function InventoryPanel:_addConfiguredAction(options, actionConfig, item)
    local itemCount = item.count or 1

    if actionConfig.enabled == false then
        return
    end
    if
        actionConfig.enabled_check
        and not self:_passesActionEnabledCheck(actionConfig.enabled_check, item)
    then
        return
    end

    -- Check if action should be enabled
    if actionConfig.min_count and itemCount < actionConfig.min_count then
        print(
            "❌ SKIPPING ACTION:",
            actionConfig.action,
            "- not enough items (need",
            actionConfig.min_count,
            "have",
            itemCount,
            ")"
        )
        return -- Skip if not enough items
    end

    -- Handle quantity-based actions (delete, consume, etc.)
    if actionConfig.quantities then
        print(
            "🔢 PROCESSING QUANTITY ACTION:",
            actionConfig.action,
            "with quantities:",
            table.concat(actionConfig.quantities, ", ")
        )
        for _, quantity in ipairs(actionConfig.quantities) do
            local actualQuantity = quantity
            if quantity == "all" then
                actualQuantity = itemCount
            elseif type(quantity) == "number" and quantity > itemCount then
                print("⏭️ SKIPPING QUANTITY:", quantity, "- not enough items")
                -- Skip if we don't have enough items
            else
                -- Get color for this quantity
                local color = actionConfig.color
                if actionConfig.quantity_colors and actionConfig.quantity_colors[quantity] then
                    color = actionConfig.quantity_colors[quantity]
                end

                -- Format text with quantity
                local text = actionConfig.text
                if quantity == "all" then
                    text = string.format(text:gsub("%%d", "All (%d)"), itemCount)
                else
                    text = string.format(text, quantity)
                end

                table.insert(options, {
                    text = text,
                    action = actionConfig.action,
                    quantity = actualQuantity,
                    color = Color3.fromRGB(color[1], color[2], color[3]),
                    order = actionConfig.order,
                    confirmation = actionConfig.confirmation,
                })
            end
        end
    else
        -- Single action (info, equip, etc.)
        print("➡️ ADDING SINGLE ACTION:", actionConfig.action, actionConfig.text)
        table.insert(options, {
            text = actionConfig.text,
            action = actionConfig.action,
            color = Color3.fromRGB(
                actionConfig.color[1],
                actionConfig.color[2],
                actionConfig.color[3]
            ),
            order = actionConfig.order,
            confirmation = actionConfig.confirmation,
        })
    end
end

function InventoryPanel:_passesActionEnabledCheck(checkName, item)
    if checkName == "can_enchant" then
        if item.folder_source ~= "pets" or item.enchantable ~= true then
            return false
        end
        if type(item.uid) ~= "string" or item.uid == "" then
            return false
        end
        return (tonumber(item.unlockedEnchantSlots) or tonumber(item.maxEnchantments) or 0) > 0
    end

    return true
end

function InventoryPanel:_getFallbackContextMenuOptions(item)
    -- Basic fallback when config fails to load
    print("🔄 USING FALLBACK OPTIONS FOR:", item.id)
    local options = {}
    local itemCount = item.count or 1

    table.insert(options, {
        text = "ℹ️ Info",
        action = "info",
        color = Color3.fromRGB(100, 150, 255),
        order = 1,
    })

    if itemCount > 1 then
        table.insert(options, {
            text = "🗑️ Delete 1",
            action = "delete",
            quantity = 1,
            color = Color3.fromRGB(255, 200, 100),
            order = 2,
        })
        table.insert(options, {
            text = "🗑️ Delete All (" .. itemCount .. ")",
            action = "delete",
            quantity = itemCount,
            color = Color3.fromRGB(230, 76, 60),
            order = 3,
        })
    else
        table.insert(options, {
            text = "🗑️ Delete",
            action = "delete",
            quantity = 1,
            color = Color3.fromRGB(230, 76, 60),
            order = 2,
        })
    end

    return options
end

function InventoryPanel:_createContextMenuOption(parent, option, layoutOrder, item)
    print("🔧 CREATING BUTTON:", option.text, "color:", option.color)
    local optionButton = Instance.new("TextButton")
    optionButton.Size = UDim2.new(1, 0, 0, 30)
    optionButton.BackgroundColor3 = option.color or Color3.fromRGB(60, 60, 70) -- Fallback color
    optionButton.BackgroundTransparency = 0.8
    optionButton.BorderSizePixel = 0
    optionButton.Text = option.text
    optionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    optionButton.TextSize = 12
    optionButton.Font = Enum.Font.Gotham
    optionButton.LayoutOrder = layoutOrder
    optionButton.ZIndex = 1001 -- Higher than context menu
    optionButton.Parent = parent

    local optionCorner = Instance.new("UICorner")
    optionCorner.CornerRadius = UDim.new(0, 4)
    optionCorner.Parent = optionButton

    -- Hover effect
    optionButton.MouseEnter:Connect(function()
        local tween = TweenService:Create(
            optionButton,
            TweenInfo.new(0.1, Enum.EasingStyle.Quad),
            { BackgroundTransparency = 0.3 }
        )
        tween:Play()
    end)

    optionButton.MouseLeave:Connect(function()
        local tween = TweenService:Create(
            optionButton,
            TweenInfo.new(0.1, Enum.EasingStyle.Quad),
            { BackgroundTransparency = 0.8 }
        )
        tween:Play()
    end)

    -- Action
    optionButton.Activated:Connect(function()
        print("🖱️ CONTEXT MENU OPTION CLICKED:", option.text)
        self.logger:info(
            "🖱️ CONTEXT MENU ACTION",
            { action = option.action, text = option.text, quantity = option.quantity }
        )

        -- Find and destroy the ScreenGui (parent of parent)
        local screenGui = parent.Parent
        if screenGui and screenGui:IsA("ScreenGui") then
            screenGui:Destroy()
        else
            parent:Destroy() -- Fallback
        end
        self:_executeContextMenuAction(option, item)
    end)

    -- Also add debug for mouse events on the button
    optionButton.MouseButton1Click:Connect(function()
        print("🔘 BUTTON MouseButton1Click DETECTED:", option.text)
    end)

    optionButton.MouseButton1Down:Connect(function()
        print("🔽 BUTTON MouseButton1Down DETECTED:", option.text)
    end)

    print("✅ BUTTON CREATED AND ADDED TO PARENT:", optionButton.Text, "Parent:", parent.Name)
end

function InventoryPanel:_executeContextMenuAction(option, item)
    print(
        "🎬 EXECUTING ACTION:",
        option.action,
        "quantity:",
        option.quantity,
        "for item:",
        item.id
    )

    if option.action == "info" then
        self:_showItemInfo(item)
    elseif option.action == "delete" then
        self:_deleteItemQuantity(item, option.quantity)
    elseif option.action == "consume" then
        self:_consumeItemQuantity(item, option.quantity)
    elseif option.action == "equip" then
        self:_toggleItemEquipped(item)
    elseif option.action == "rename" then
        self:_renameItem(item)
    elseif option.action == "sell" then
        self:_sellItem(item)
    elseif option.action == "upgrade" then
        self:_upgradeItem(item)
    elseif option.action == "hatch" then
        self:_hatchEgg(item, option.quantity or 1)
    elseif option.action == "hatch_multiple" then
        self:_hatchEgg(item, option.quantity)
    else
        self.logger:warn("❓ UNKNOWN ACTION", { action = option.action, itemId = item.id })
        print("❓ UNKNOWN ACTION:", option.action)
    end
end

-- 🍎 CONSUME ACTIONS
function InventoryPanel:_consumeItemQuantity(item, quantity)
    print("🍎 CONSUMING ITEM:", item.id, "quantity:", quantity)
    self.logger:info("🍎 CONSUME ITEM", {
        itemId = item.id,
        itemName = item.name,
        quantity = quantity,
        folder_source = item.folder_source,
    })

    if self.signals and self.signals.ConsumeItem then
        self.signals.ConsumeItem:FireServer({
            bucket = item.folder_source,
            itemUid = item.uid,
            itemId = item.id,
            quantity = quantity,
        })
        self.logger:info("✅ Consume request sent to server")
    else
        self.logger:warn("❌ Signals not available for consuming")
    end
end

-- 🐾 EQUIP ACTIONS
function InventoryPanel:_toggleItemEquipped(item)
    print("🐾 TOGGLING EQUIPPED:", item.id)
    if item.folder_source == "pets" then
        self:_togglePetEquipped(item)
    elseif item.folder_source == "tools" then
        self:_toggleToolEquipped(item)
    else
        self.logger:warn("❓ Cannot equip item type", { folder_source = item.folder_source })
    end
end

-- ✏️ RENAME ACTIONS
function InventoryPanel:_renameItem(item)
    print("✏️ RENAME ITEM:", item.id)
    -- TODO: Show text input dialog for renaming
    self.logger:info("✏️ RENAME REQUESTED", { itemId = item.id })
    print("🚧 RENAME NOT IMPLEMENTED YET")
end

-- 💰 SELL ACTIONS
function InventoryPanel:_sellItem(item)
    print("💰 SELL ITEM:", item.id)
    -- TODO: Implement selling to shop
    self.logger:info("💰 SELL REQUESTED", { itemId = item.id })
    print("🚧 SELL NOT IMPLEMENTED YET")
end

-- ⬆️ UPGRADE ACTIONS
function InventoryPanel:_upgradeItem(item)
    print("⬆️ UPGRADE ITEM:", item.id)
    -- TODO: Implement item upgrading
    self.logger:info("⬆️ UPGRADE REQUESTED", { itemId = item.id })
    print("🚧 UPGRADE NOT IMPLEMENTED YET")
end

-- 🥚 HATCH ACTIONS
function InventoryPanel:_hatchEgg(item, quantity)
    print("🥚 HATCH EGG:", item.id, "quantity:", quantity)
    -- TODO: Implement egg hatching from inventory
    self.logger:info("🥚 HATCH REQUESTED", { itemId = item.id, quantity = quantity })
    print("🚧 HATCH NOT IMPLEMENTED YET - Use egg interaction in world")
end

function InventoryPanel:_deleteItemQuantity(item, quantity)
    self.logger:info("🗑️ DELETING ITEM QUANTITY", {
        itemId = item.id,
        itemName = item.name,
        quantity = quantity,
        totalCount = item.count,
    })

    local itemUid = item.uid or item.uniqueId
    if item.folder_source and itemUid then
        if self.signals then
            self.signals.DeleteInventoryItem:FireServer({
                bucket = item.folder_source,
                itemUid = itemUid,
                itemId = item.id,
                quantity = quantity,
                reason = "player_deleted",
            })
            self.logger:info("✅ Delete quantity request sent to server")
        else
            self.logger:warn("❌ Signals not available for deletion")
        end
    else
        self.logger:warn("❌ Cannot delete item - missing source or UID")
    end

    -- Immediate UI feedback
    task.wait(0.1)
    self:RefreshFromRealData()
end

function InventoryPanel:_setupContextMenuAutoClose(contextMenu)
    -- SIMPLE SOLUTION: Just auto-close after 5 seconds, no click detection
    -- Let the button events handle themselves without interference
    task.spawn(function()
        task.wait(5)
        if contextMenu.Parent then
            print("🕒 AUTO-CLOSING CONTEXT MENU AFTER 5 SECONDS")
            contextMenu:Destroy()
        end
    end)
end

function InventoryPanel:_showItemContextMenu(item, x, y)
    self.logger:info("🖱️ ITEM CONTEXT MENU", { itemId = item.id, x = x, y = y })

    -- Create context menu
    local contextMenu = Instance.new("Frame")
    contextMenu.Name = "ItemContextMenu"
    contextMenu.Size = UDim2.new(0, 120, 0, 80)
    contextMenu.Position = UDim2.new(0, x, 0, y)
    contextMenu.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    contextMenu.BorderSizePixel = 0
    contextMenu.ZIndex = 150
    contextMenu.Parent = Players.LocalPlayer.PlayerGui

    local menuCorner = Instance.new("UICorner")
    menuCorner.CornerRadius = UDim.new(0, 6)
    menuCorner.Parent = contextMenu

    local menuStroke = Instance.new("UIStroke")
    menuStroke.Color = Color3.fromRGB(100, 100, 110)
    menuStroke.Thickness = 1
    menuStroke.Parent = contextMenu

    local menuLayout = Instance.new("UIListLayout")
    menuLayout.FillDirection = Enum.FillDirection.Vertical
    menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
    menuLayout.Parent = contextMenu

    -- Delete option
    local deleteOption = Instance.new("TextButton")
    deleteOption.Size = UDim2.new(1, 0, 0, 40)
    deleteOption.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
    deleteOption.BackgroundTransparency = 0.2
    deleteOption.BorderSizePixel = 0
    deleteOption.Text = "🗑️ Delete"
    deleteOption.TextColor3 = Color3.fromRGB(255, 255, 255)
    deleteOption.TextSize = 12
    deleteOption.Font = Enum.Font.Gotham
    deleteOption.LayoutOrder = 1
    deleteOption.ZIndex = 151
    deleteOption.Parent = contextMenu

    -- Info option
    local infoOption = Instance.new("TextButton")
    infoOption.Size = UDim2.new(1, 0, 0, 40)
    infoOption.BackgroundTransparency = 1
    infoOption.BorderSizePixel = 0
    infoOption.Text = "ℹ️ Info"
    infoOption.TextColor3 = Color3.fromRGB(255, 255, 255)
    infoOption.TextSize = 12
    infoOption.Font = Enum.Font.Gotham
    infoOption.LayoutOrder = 2
    infoOption.ZIndex = 151
    infoOption.Parent = contextMenu

    -- Actions
    deleteOption.Activated:Connect(function()
        contextMenu:Destroy()
        self:_showDeleteConfirmation(item)
    end)

    infoOption.Activated:Connect(function()
        contextMenu:Destroy()
        self:_showItemInfo(item)
    end)

    -- Auto-close after 3 seconds or on click outside
    local closeConnection
    local closeTimer = task.wait(3)

    closeConnection = game:GetService("UserInputService").InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            contextMenu:Destroy()
            closeConnection:Disconnect()
        end
    end)

    task.spawn(function()
        task.wait(3)
        if contextMenu.Parent then
            contextMenu:Destroy()
        end
        if closeConnection then
            closeConnection:Disconnect()
        end
    end)
end

function InventoryPanel:_deleteItem(item)
    self.logger:info("🗑️ DELETING ITEM", {
        itemId = item.id,
        itemName = item.name,
        folder_source = item.folder_source,
        uniqueId = item.uniqueId,
        uid = item.uid,
        hasSignals = self.signals ~= nil,
        signalsType = typeof(self.signals),
    })

    -- Debug: Check if DeleteInventoryItem signal exists
    if self.signals then
        self.logger:info("🔍 SIGNALS DEBUG", {
            hasDeleteSignal = self.signals.DeleteInventoryItem ~= nil,
            deleteSignalType = typeof(self.signals.DeleteInventoryItem),
            hasFireServerMethod = self.signals.DeleteInventoryItem
                and typeof(self.signals.DeleteInventoryItem.FireServer) == "function",
        })
    end

    -- Determine which network call to make based on source
    local itemUid = item.uid or item.uniqueId -- Check both field names
    if item.folder_source and itemUid then
        -- Real inventory item - call server to delete from ProfileStore
        if self.signals then
            self.signals.DeleteInventoryItem:FireServer({
                bucket = item.folder_source,
                itemUid = itemUid,
                itemId = item.id,
                reason = "player_deleted",
            })
            self.logger:info("✅ Delete request sent to server via Signals")
        else
            self.logger:warn("❌ Signals not available for deletion")
        end
    else
        self.logger:warn("❌ Cannot delete item - missing source or UID", {
            hasSource = item.folder_source ~= nil,
            hasUid = itemUid ~= nil,
            itemUid = itemUid,
            hasOldUid = item.uniqueId ~= nil,
            hasNewUid = item.uid ~= nil,
        })
    end

    -- Immediate UI feedback - remove from display
    task.wait(0.1)
    self:RefreshFromRealData()
end

function InventoryPanel:_showItemInfo(item)
    self.logger:info("ℹ️ SHOWING ITEM INFO", { itemId = item.id })
    -- This would show detailed item information
    -- For now, just log the item data
    print("=== ITEM INFO ===")
    for key, value in pairs(item) do
        print(key .. ":", value)
    end
    print("================")
end

-- 🌐 NETWORK INITIALIZATION
function InventoryPanel:_initializeNetworking()
    local success, signals = pcall(function()
        return require(ReplicatedStorage.Shared.Network.Signals)
    end)

    if success and signals then
        self.signals = signals
        self.logger:info("✅ Signals initialized for inventory")
    else
        self.logger:warn("❌ Failed to get Signals module:", signals)
    end
end

function InventoryPanel:SetupRealTimeUpdates()
    -- Watch for changes to the inventory folder
    local inventoryFolder = self.player:FindFirstChild("Inventory")
    if inventoryFolder then
        local petsFolder = inventoryFolder:FindFirstChild("pets")
        if petsFolder then
            -- Listen for new pets being added
            -- Mixed structure incremental listeners
            local stacks = petsFolder:FindFirstChild("Stacks")
            local special = petsFolder:FindFirstChild("Special")

            if stacks then
                stacks.ChildAdded:Connect(function(stackFolder)
                    if stackFolder:IsA("Folder") then
                        task.wait(0.05)
                        self:RefreshFromRealData()
                    end
                end)
                stacks.ChildRemoved:Connect(function()
                    self:RefreshFromRealData()
                end)
                -- Quantity change listener per existing stack
                for _, sf in ipairs(stacks:GetChildren()) do
                    local qty = sf:FindFirstChild("Quantity")
                    if qty then
                        qty:GetPropertyChangedSignal("Value"):Connect(function()
                            self:RefreshFromRealData()
                        end)
                    end
                end
                stacks.ChildAdded:Connect(function(sf)
                    local qty = sf:FindFirstChild("Quantity")
                    if qty then
                        qty:GetPropertyChangedSignal("Value"):Connect(function()
                            self:RefreshFromRealData()
                        end)
                    end
                end)
            end

            if special then
                special.ChildAdded:Connect(function()
                    task.wait(0.05)
                    self:RefreshFromRealData()
                end)
                special.ChildRemoved:Connect(function()
                    self:RefreshFromRealData()
                end)
            end

            -- Legacy fallback
            petsFolder.ChildAdded:Connect(function(child)
                if child:IsA("Folder") and child.Name ~= "Info" and not stacks and not special then
                    self.logger:info("New pet detected in inventory", { petFolder = child.Name })
                    task.wait(0.1)
                    self:RefreshFromRealData()
                end
            end)

            -- Listen for pets being removed
            petsFolder.ChildRemoved:Connect(function(child)
                if child:IsA("Folder") and child.Name ~= "Info" and not stacks and not special then
                    self.logger:info("Pet removed from inventory", { petFolder = child.Name })
                    self:RefreshFromRealData()
                end
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════════
-- ⚔️ EQUIPPED ITEM TRACKING
-- ═══════════════════════════════════════════════════════════════════════════════════

function InventoryPanel:_setupEquippedFolderListeners()
    local player = Players.LocalPlayer

    self.logger:info("⚔️ Setting up equipped folder listeners...")

    -- Use task.spawn to avoid blocking
    task.spawn(function()
        -- Wait for equipped folder to be created
        local equippedFolder = player:WaitForChild("Equipped", 10)
        if not equippedFolder then
            self.logger:warn("❌ No equipped folder found after 10 seconds")
            return
        end

        self.logger:info("✅ Found equipped folder")

        -- Track equipped items for quick lookup
        self.equippedItems = {
            pets = {},
            tools = {},
        }

        -- Set up pets folder listener
        task.spawn(function()
            local petsFolder = equippedFolder:FindFirstChild("pets")
            if not petsFolder then
                self.logger:info("⚔️ Waiting for pets folder to be created...")
                petsFolder = equippedFolder.ChildAdded:Wait()
                while petsFolder.Name ~= "pets" do
                    petsFolder = equippedFolder.ChildAdded:Wait()
                end
            end

            self.logger:info("✅ Found pets folder, setting up listener")
            self:_setupCategoryEquippedListener(petsFolder, "pets")
        end)

        -- Set up tools folder listener
        task.spawn(function()
            local toolsFolder = equippedFolder:FindFirstChild("tools")
            if toolsFolder then
                self.logger:info("✅ Found existing tools folder, setting up listener")
                self:_setupCategoryEquippedListener(toolsFolder, "tools")
            else
                self.logger:info("⚔️ Waiting for tools folder to be created...")
                -- Listen for tools folder to be created
                equippedFolder.ChildAdded:Connect(function(child)
                    if child.Name == "tools" then
                        self.logger:info("✅ Tools folder created, setting up listener")
                        self:_setupCategoryEquippedListener(child, "tools")
                    end
                end)
            end
        end)

        self.logger:info("⚔️ Equipped folder listeners setup complete")
        -- Force an initial display refresh after listeners are attached
        self:_updateItemsDisplay()
    end)
end

function InventoryPanel:_setupCategoryEquippedListener(categoryFolder, categoryName)
    self.logger:info("⚔️ Setting up listener for category: " .. categoryName)

    -- Load initial equipped items
    local initialCount = 0
    for _, slotValue in pairs(categoryFolder:GetChildren()) do
        if slotValue:IsA("StringValue") and slotValue.Value ~= "" then
            self.equippedItems[categoryName][slotValue.Value] = slotValue.Name
            initialCount = initialCount + 1
            self.logger:info("📍 Initial equipped item found", {
                category = categoryName,
                slot = slotValue.Name,
                itemUid = slotValue.Value,
            })
        end
    end

    -- Listen for equipped changes
    categoryFolder.ChildAdded:Connect(function(slotValue)
        if slotValue:IsA("StringValue") then
            self.logger:info("📍 ChildAdded in " .. categoryName, {
                slotName = slotValue.Name,
                slotValue = slotValue.Value,
            })
            -- Treat as equip of current value
            if slotValue.Value ~= "" then
                self:_onEquippedChanged(categoryName, slotValue.Value, slotValue.Name, "equipped")
            end
            -- Attach change watcher with last-value tracking for accurate unequip
            local last = slotValue.Value
            slotValue.Changed:Connect(function(newValue)
                self.logger:info("📍 Value changed in " .. categoryName, {
                    slotName = slotValue.Name,
                    oldValue = last,
                    newValue = newValue,
                })
                if newValue ~= "" then
                    self:_onEquippedChanged(categoryName, newValue, slotValue.Name, "equipped")
                else
                    -- Use previous value for unequip mapping removal
                    if last and last ~= "" then
                        self:_onEquippedChanged(categoryName, last, slotValue.Name, "unequipped")
                    end
                end
                last = newValue
            end)
        end
    end)

    categoryFolder.ChildRemoved:Connect(function(slotValue)
        if slotValue:IsA("StringValue") then
            self.logger:info("📍 ChildRemoved in " .. categoryName, {
                slotName = slotValue.Name,
                slotValue = slotValue.Value,
            })
            self:_onEquippedChanged(categoryName, slotValue.Value, slotValue.Name, "unequipped")
        end
    end)

    -- Listen for value changes within slots
    for _, slotValue in pairs(categoryFolder:GetChildren()) do
        if slotValue:IsA("StringValue") then
            local last = slotValue.Value
            slotValue.Changed:Connect(function(newValue)
                self.logger:info("📍 Value changed in " .. categoryName, {
                    slotName = slotValue.Name,
                    oldValue = last,
                    newValue = newValue,
                })
                if newValue ~= "" then
                    self:_onEquippedChanged(categoryName, newValue, slotValue.Name, "equipped")
                else
                    if last and last ~= "" then
                        self:_onEquippedChanged(categoryName, last, slotValue.Name, "unequipped")
                    end
                end
                last = newValue
            end)
        end
    end

    self.logger:info("⚔️ Set up equipped listener complete", {
        category = categoryName,
        initialEquipped = initialCount,
        totalSlots = #categoryFolder:GetChildren(),
    })

    -- Ensure UI reflects initial equipped state immediately
    -- Without this, the first open may not show equipped badges until the panel is reopened
    if initialCount > 0 then
        self:_updateItemsDisplay()
    end
end

function InventoryPanel:_onEquippedChanged(categoryName, itemUid, slotName, action)
    self.logger:info("⚔️ EQUIPPED CHANGED", {
        category = categoryName,
        itemUid = itemUid,
        slot = slotName,
        action = action,
    })

    if action == "equipped" and itemUid ~= "" then
        self.equippedItems[categoryName][itemUid] = slotName
        self.logger:info("✅ Added to equipped items", { itemUid = itemUid, slot = slotName })
    elseif action == "unequipped" then
        self.equippedItems[categoryName][itemUid] = nil
        self.logger:info("❌ Removed from equipped items", { itemUid = itemUid })
    end

    -- Debug: print occupied slots snapshot after every change
    if categoryName == "pets" then
        local occupied = {}
        local equippedFolder = Players.LocalPlayer:FindFirstChild("Equipped")
        if equippedFolder and equippedFolder:FindFirstChild("pets") then
            for _, slot in ipairs(equippedFolder.pets:GetChildren()) do
                if slot:IsA("StringValue") then
                    table.insert(
                        occupied,
                        slot.Name .. "=" .. (slot.Value ~= "" and slot.Value or "<empty>")
                    )
                end
            end
        end
        print("[EQUIPPED SLOTS] " .. table.concat(occupied, ", "))
    end

    -- If this is a stack-backed equip value (bridge format), adjust just that stack card
    if categoryName == "pets" and type(itemUid) == "string" then
        local parts = string.split(itemUid, "|")
        if #parts >= 3 and parts[1] == "stack" then
            local stackKey = parts[2] -- id:variant
            self._stackFrames = self._stackFrames or {}
            self._stackDataByKey = self._stackDataByKey or {}
            -- Avoid manual local count math to prevent double-decrement; refresh from replicated data
            self:RefreshFromRealData()
            return
        end
    end

    -- Fallback: refresh full display
    self.logger:info("🔄 Refreshing UI for equipped change")
    self:_updateItemsDisplay()
end

-- Debug function to manually check equipped items
function InventoryPanel:DebugEquippedItems()
    print("=== EQUIPPED ITEMS DEBUG ===")
    if self.equippedItems then
        for category, items in pairs(self.equippedItems) do
            print(category .. ":")
            for itemUid, slot in pairs(items) do
                print("  " .. itemUid .. " -> " .. slot)
            end
        end
    else
        print("equippedItems not initialized")
    end

    -- Also check the actual folders
    local player = Players.LocalPlayer
    local equippedFolder = player:FindFirstChild("Equipped")
    if equippedFolder then
        print("=== ACTUAL FOLDERS ===")
        for _, categoryFolder in pairs(equippedFolder:GetChildren()) do
            if categoryFolder:IsA("Folder") then
                print(categoryFolder.Name .. ":")
                for _, slotValue in pairs(categoryFolder:GetChildren()) do
                    if slotValue:IsA("StringValue") then
                        print("  " .. slotValue.Name .. " = " .. slotValue.Value)
                    end
                end
            end
        end
    else
        print("No equipped folder found")
    end
    print("===========================")
end

function InventoryPanel:_isItemEquipped(item)
    if not self.equippedItems then
        return false
    end

    if item.folder_source == "pets" then
        -- If this is a ghost equipped instance from a stack, uid will be the equippedUid
        if typeof(item.uid) == "string" and string.sub(item.uid, 1, 17) == "stackInstance|" then
            return true
        end
        return self.equippedItems.pets[item.uid] ~= nil
    elseif item.folder_source == "tools" then
        return self.equippedItems.tools[item.uid] ~= nil
    end

    return false
end

function InventoryPanel:_applyEquippedStyling(itemFrame, isEquipped, originalColor)
    if not itemFrame then
        return
    end

    local stroke = itemFrame:FindFirstChild("RarityStroke")
        or itemFrame:FindFirstChildOfClass("UIStroke")

    if isEquipped then
        -- Equipped styling: preserve rarity/variant colors and make the ring more prominent.
        if stroke then
            local baseThickness = tonumber(stroke:GetAttribute("BaseThickness"))
                or stroke.Thickness
                or 2
            stroke.Thickness = baseThickness + 1
            stroke.Transparency = 0
        end

        -- Add equipped icon
        local equippedIcon = itemFrame:FindFirstChild("EquippedIcon")
        if not equippedIcon then
            equippedIcon = Instance.new("TextLabel")
            equippedIcon.Name = "EquippedIcon"
            equippedIcon.Size = UDim2.new(0, 24, 0, 24)
            equippedIcon.Position = UDim2.new(1, -30, 0, 6)
            equippedIcon.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
            equippedIcon.BackgroundTransparency = 0.2
            equippedIcon.BorderSizePixel = 0
            equippedIcon.Text = "⚔️"
            equippedIcon.TextSize = 14
            equippedIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
            equippedIcon.ZIndex = 110
            equippedIcon.Parent = itemFrame

            local iconCorner = Instance.new("UICorner")
            iconCorner.CornerRadius = UDim.new(0, 12)
            iconCorner.Parent = equippedIcon
        end
    else
        -- Unequipped styling: restore base ring weight without changing rarity colors.
        if stroke then
            stroke.Color = originalColor or stroke.Color
            stroke.Thickness = tonumber(stroke:GetAttribute("BaseThickness")) or 2
            stroke.Transparency = 0
        end

        -- Remove equipped icon
        local equippedIcon = itemFrame:FindFirstChild("EquippedIcon")
        if equippedIcon then
            equippedIcon:Destroy()
        end
    end
end

function InventoryPanel:Destroy()
    self:Hide()
    self.logger:info("Professional inventory panel destroyed")
end

return InventoryPanel
