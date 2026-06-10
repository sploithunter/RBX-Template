--[[
    BootLoader (ReplicatedFirst) — gates play behind a loading screen until the client is ready.

    ReplicatedFirst runs FIRST, before StarterPlayerScripts. We cover the screen immediately, lock
    the player's controls, and only reveal the game once all readiness gates pass:
      1. game:IsLoaded()                       — assets/instances replicated
      2. LocalPlayer:GetAttribute("DataLoaded")  — server profile replicated (set by DataService)
      3. LocalPlayer:GetAttribute("ClientUIReady") — MenuManager + panels + BaseUI up (set by
         src/Client/init.client at the end of UI init)

    A hard timeout reveals anyway, so a stuck/never-sent signal can never trap the player on the
    loading screen. This closes the class of "I interacted before the game finished loading" bugs
    (e.g. triggering the Ascension Altar before MenuManager existed -> legacy fallback modal).
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local ACCENT = Color3.fromRGB(150, 85, 225) -- purple, matches the level-up / ascend accent
local HARD_TIMEOUT = 25 -- seconds: reveal regardless, so a missing signal never hangs the boot
local MIN_DISPLAY = 2 -- seconds: never blink past the screen even on instant loads
local SETTLE = 0.75 -- seconds after the last gate: restyle passes (tray/currency/quest) land

ReplicatedFirst:RemoveDefaultLoadingScreen()

-- ---- loading screen ----------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BootLoader"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000000 -- above every other GUI
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(12, 13, 18)
bg.BorderSizePixel = 0
bg.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.fromScale(0.8, 0.12)
title.Position = UDim2.fromScale(0.5, 0.42)
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(235, 238, 245)
title.Text = "PET REALM"
title.Parent = bg

local status = Instance.new("TextLabel")
status.Size = UDim2.fromScale(0.6, 0.05)
status.Position = UDim2.fromScale(0.5, 0.56)
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.TextScaled = true
status.TextColor3 = Color3.fromRGB(150, 155, 170)
status.Text = "Loading…"
status.Parent = bg

local track = Instance.new("Frame")
track.Size = UDim2.fromScale(0.4, 0.012)
track.Position = UDim2.fromScale(0.5, 0.64)
track.AnchorPoint = Vector2.new(0.5, 0.5)
track.BackgroundColor3 = Color3.fromRGB(35, 37, 45)
track.BorderSizePixel = 0
track.Parent = bg
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = ACCENT
fill.BorderSizePixel = 0
fill.Parent = track
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

-- ---- control lock ------------------------------------------------------
-- Disable the default PlayerModule controls while loading so the player can't move/interact behind
-- the cover. Wrapped in pcall + retry because PlayerModule may not exist the instant we boot.
local function setControls(enabled)
    pcall(function()
        local ps = localPlayer:FindFirstChild("PlayerScripts")
        local pm = ps and ps:FindFirstChild("PlayerModule")
        if pm then
            local controls = require(pm):GetControls()
            if enabled then
                controls:Enable()
            else
                controls:Disable()
            end
        end
    end)
end

-- ---- gates -------------------------------------------------------------
-- Ordered: each label shows while its check is pending. "Completely loaded" means the
-- replicated WORLD CONTENT and the player's own state, not just the engine IsLoaded bit.
local gates = {
    {
        label = "Loading world…",
        check = function()
            return game:IsLoaded()
        end,
    },
    {
        label = "Building the realm…",
        check = function()
            -- authored map content replicated: the Game tree exists and the farmables are in
            local gameFolder = Workspace:FindFirstChild("Game")
            local breakables = gameFolder and gameFolder:FindFirstChild("Breakables")
            return breakables ~= nil and #breakables:GetDescendants() > 0
        end,
    },
    {
        label = "Syncing your data…",
        check = function()
            return localPlayer:GetAttribute("DataLoaded") == true
        end,
    },
    {
        label = "Waking your pets…",
        check = function()
            -- character spawned + the per-player pet folder exists (PetFollowService)
            if not localPlayer.Character then
                return false
            end
            local pets = Workspace:FindFirstChild("PlayerPets")
            return pets ~= nil and pets:FindFirstChild(localPlayer.Name) ~= nil
        end,
    },
    {
        label = "Preparing UI…",
        check = function()
            return localPlayer:GetAttribute("ClientUIReady") == true
        end,
    },
    {
        label = "Polishing…",
        check = function()
            -- the HUD actually exists on screen (BaseUI + hotbar guis parented)
            local pg = localPlayer:FindFirstChild("PlayerGui")
            return pg ~= nil
                and pg:FindFirstChild("ProfessionalBaseUI") ~= nil
                and pg:FindFirstChild("PlayerBar") ~= nil
        end,
    },
}

task.spawn(function()
    local start = os.clock()
    setControls(false)
    -- keep re-asserting the control lock for the first moment (PlayerModule loads slightly after us)
    task.spawn(function()
        for _ = 1, 20 do
            setControls(false)
            task.wait(0.1)
        end
    end)

    for i, gate in ipairs(gates) do
        status.Text = gate.label
        while not gate.check() do
            if os.clock() - start > HARD_TIMEOUT then
                break
            end
            task.wait(0.1)
        end
        TweenService:Create(fill, TweenInfo.new(0.25), { Size = UDim2.fromScale(i / #gates, 1) })
            :Play()
    end

    -- restyle passes (tray pills, currency stack, quest capsule) run just after the HUD guis
    -- appear — give them a beat so the reveal shows the FINISHED hud, and never blink the
    -- screen past MIN_DISPLAY even on instant local loads.
    status.Text = "Ready!"
    task.wait(math.max(SETTLE, MIN_DISPLAY - (os.clock() - start)))
    setControls(true)

    local t = TweenInfo.new(0.4)
    TweenService:Create(bg, t, { BackgroundTransparency = 1 }):Play()
    TweenService:Create(title, t, { TextTransparency = 1 }):Play()
    TweenService:Create(status, t, { TextTransparency = 1 }):Play()
    TweenService:Create(track, t, { BackgroundTransparency = 1 }):Play()
    TweenService:Create(fill, t, { BackgroundTransparency = 1 }):Play()
    task.wait(0.45)
    gui:Destroy()
end)
