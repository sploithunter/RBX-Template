--[[
    AdminController (client) — one place to gate all the admin/dev overlays behind a single toggle.

    The dev overlays (DevSpawnPanel, DevMetricsHud, BuffStatsHud) used to be always-on in Studio,
    cluttering the play screen. Now they're HIDDEN by default and revealed by a small "🛠 ADMIN" chip
    in the lower-left — only visible to admins (player attribute IsAdmin) or in Studio.

    Toggling sets LocalPlayer attribute "AdminOverlaysOn" (the SoT other admin UI can read) and flips
    `.Enabled` on the overlay ScreenGuis by name. Default OFF → a clean screen for normal testing.

    Phase 1 of the HUD-restyle goal; later phases add the area/power toggles + kill button under the
    same chip and restyle it with the pill kit.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)

local AdminController = {}
local started = false

-- Areas the area-cycle button rotates through (matches ZoneService ADMIN_AREAS).
local ADMIN_AREAS = { "Grass", "Desert", "Ice", "Lava", "Spawn" }

-- The dev/admin overlay ScreenGuis this chip shows/hides (by Name in PlayerGui).
local OVERLAYS = { "DevSpawnPanel", "DevMetricsHud", "BuffStatsHud" }

local function isAdmin(player)
    return RunService:IsStudio() or player:GetAttribute("IsAdmin") == true
end

local function setOverlays(pg, on)
    for _, name in ipairs(OVERLAYS) do
        local gui = pg:FindFirstChild(name)
        if gui and gui:IsA("ScreenGui") then
            gui.Enabled = on
        end
    end
end

function AdminController.start()
    if started then
        return
    end
    started = true
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")

    -- Wait for IsAdmin to replicate (data loads after boot) before deciding to show the chip.
    if not isAdmin(player) then
        local deadline = os.clock() + 15
        while os.clock() < deadline and player:GetAttribute("IsAdmin") == nil do
            task.wait(0.5)
        end
        if not isAdmin(player) then
            return -- not an admin: never build the chip, overlays stay as they were
        end
    end

    player:SetAttribute("AdminOverlaysOn", false)

    local gui = Instance.new("ScreenGui")
    gui.Name = "AdminController"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 90
    gui.Parent = pg

    local chip = Instance.new("TextButton")
    chip.Name = "AdminToggle"
    chip.Size = UDim2.fromOffset(118, 30)
    chip.Position = UDim2.new(0, 315, 1, -12) -- bottom, in the gap right of the menu tray
    chip.AnchorPoint = Vector2.new(0, 1)
    chip.BackgroundColor3 = Color3.fromRGB(40, 26, 54)
    chip.BackgroundTransparency = 0.1
    chip.AutoButtonColor = true
    chip.Font = Enum.Font.GothamBold
    chip.TextSize = 13
    chip.TextColor3 = Color3.fromRGB(200, 180, 235)
    chip.Text = "🛠 ADMIN: OFF"
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = chip
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(150, 110, 230)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.3
    stroke.Parent = chip
    chip.Parent = gui

    -- Area-cycle button (shown only when admin mode is ON): rotate CurrentArea/HomeArea for testing
    -- the area theme + play feel.
    local areaBtn = Instance.new("TextButton")
    areaBtn.Name = "AreaCycle"
    areaBtn.Size = UDim2.fromOffset(118, 26)
    areaBtn.Position = UDim2.new(0, 315, 1, -46) -- just above the ADMIN chip
    areaBtn.AnchorPoint = Vector2.new(0, 1)
    areaBtn.BackgroundColor3 = Color3.fromRGB(26, 40, 54)
    areaBtn.BackgroundTransparency = 0.1
    areaBtn.Font = Enum.Font.GothamBold
    areaBtn.TextSize = 12
    areaBtn.TextColor3 = Color3.fromRGB(180, 210, 235)
    areaBtn.Text = "AREA: …"
    areaBtn.Visible = false
    local ac = Instance.new("UICorner")
    ac.CornerRadius = UDim.new(0, 8)
    ac.Parent = areaBtn
    areaBtn.Parent = gui
    local function refreshAreaLabel()
        local a = player:GetAttribute("HomeArea") or player:GetAttribute("CurrentArea") or "Spawn"
        areaBtn.Text = "AREA: " .. tostring(a) .. " ▸"
    end
    refreshAreaLabel()
    player:GetAttributeChangedSignal("CurrentArea"):Connect(refreshAreaLabel)
    player:GetAttributeChangedSignal("HomeArea"):Connect(refreshAreaLabel)
    areaBtn.Activated:Connect(function()
        local cur = player:GetAttribute("HomeArea") or player:GetAttribute("CurrentArea") or "Spawn"
        local idx = 1
        for i, a in ipairs(ADMIN_AREAS) do
            if a == cur then
                idx = i
                break
            end
        end
        local nextArea = ADMIN_AREAS[(idx % #ADMIN_AREAS) + 1]
        Signals.Admin_SetArea:FireServer({ area = nextArea })
    end)

    local on = false
    local function apply()
        setOverlays(pg, on)
        chip.Text = on and "🛠 ADMIN: ON" or "🛠 ADMIN: OFF"
        chip.TextColor3 = on and Color3.fromRGB(120, 240, 150) or Color3.fromRGB(200, 180, 235)
        stroke.Color = on and Color3.fromRGB(90, 220, 120) or Color3.fromRGB(150, 110, 230)
        areaBtn.Visible = on
        player:SetAttribute("AdminOverlaysOn", on)
    end

    chip.Activated:Connect(function()
        on = not on
        apply()
    end)

    -- The overlays may not exist at this instant (they start in their own pcall blocks); apply a few
    -- times early so they begin hidden once they appear.
    task.spawn(function()
        for _ = 1, 6 do
            apply()
            task.wait(0.5)
        end
    end)
end

return AdminController
