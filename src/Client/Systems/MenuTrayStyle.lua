--[[
    MenuTrayStyle (client) — skin the lower-left tray buttons (Trade/Admin/Daily/Quest/Shop/Items/
    Effects/Settings) AND the Rewards button with Jason's pill art: a glossy pill_panel background +
    a neon pill_frame border behind the existing icon + label, matching
    assets/ui/reference/quest_button_reference.jpg.

    Done as a scoped post-process (named buttons only) so BaseUI's button-building logic is untouched.
    The tray takes the home-area pill color (via UITheme, sapphire default) and re-tints on area change;
    Rewards keeps a fixed citrine (gold) pill for its identity and is moved into the lower-left next to
    the Pets paw. Idempotent per button.

    Icon-ready: the restyle lifts whatever icon child BaseUI made (TextLabel emoji OR ImageLabel asset)
    above the pills and only outlines TEXT — so swapping in real icon image ids later needs no change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PILL = require(ReplicatedStorage.Configs:WaitForChild("pill_ui"))

local MenuTrayStyle = {}
local started = false

local TRAY_BUTTONS = {
    "PetsButton",
    "AdminButton",
    "DailyButton",
    "QuestButton",
    "ShopButton",
    "EffectsButton",
    "SettingsButton",
}

local function pillKey(theme)
    local key = theme and theme.color
    if key == nil or key == "neutral" or not PILL.panels[key] then
        key = "sapphire"
    end
    return key
end

-- Skin one button with a pill_panel + pill_frame of `key`, lifting its icon/label above. If rebind is
-- given, the panel/frame are recorded so they can be re-tinted when the area changes.
local function styleButton(btn, key, rebind)
    if btn:GetAttribute("Pillified") then
        return
    end
    btn:SetAttribute("Pillified", true)

    if btn:IsA("ImageButton") then
        btn.Image = ""
    end
    btn.BackgroundTransparency = 1
    for _, c in ipairs(btn:GetChildren()) do
        if c:IsA("UIGradient") or c:IsA("UIStroke") or c:IsA("UICorner") then
            c:Destroy()
        end
    end

    local panel = Instance.new("ImageLabel")
    panel.Name = "PillPanel"
    panel.BackgroundTransparency = 1
    panel.ScaleType = Enum.ScaleType.Fit
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromScale(0.84, 0.84)
    panel.Image = PILL.panels[key]
    panel.ZIndex = 13
    panel.Parent = btn
    local frame = Instance.new("ImageLabel")
    frame.Name = "PillFrame"
    frame.BackgroundTransparency = 1
    frame.ScaleType = Enum.ScaleType.Fit
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromScale(1.0, 1.0)
    frame.Image = PILL.frames[key]
    frame.ZIndex = 14
    frame.Parent = btn

    for _, c in ipairs(btn:GetChildren()) do
        if c ~= panel and c ~= frame and c:IsA("GuiObject") then
            c.ZIndex = 16
            if c:IsA("TextLabel") then
                c.TextColor3 = Color3.fromRGB(245, 248, 255)
                if not c:FindFirstChildOfClass("UIStroke") then
                    local s = Instance.new("UIStroke")
                    s.Color = Color3.fromRGB(10, 30, 60)
                    s.Thickness = 2
                    s.Parent = c
                end
            end
        end
    end

    if rebind then
        table.insert(rebind, { panel = panel, frame = frame })
    end
end

function MenuTrayStyle.start()
    if started then
        return
    end
    started = true
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")
    local Theme = require(script.Parent.Parent.UI.UITheme)

    task.spawn(function()
        local base = pg:WaitForChild("ProfessionalBaseUI", 20)
        local mc = base and base:WaitForChild("MainContainer", 10)
        if not mc then
            return
        end

        local styled = {} -- tray panels/frames that re-tint with the area
        local theme = Theme.palette(player)

        -- 8 tray buttons (area color)
        local pane = mc:WaitForChild("menu_buttons_pane", 15)
        task.spawn(function()
            for _ = 1, 10 do
                if pane then
                    for _, name in ipairs(TRAY_BUTTONS) do
                        local btn = pane:FindFirstChild(name)
                        if btn then
                            styleButton(btn, pillKey(theme), styled)
                        end
                    end
                end
                task.wait(0.5)
            end
        end)

        -- Rewards: move into the lower-left next to the Pets paw, reshape from the wide horizontal
        -- button into a SQUARE icon-top/label-bottom button (so the square pill fits), gold pill.
        task.spawn(function()
            -- Rewards joins the menu tray GRID (Jason): square gold restyle, then the button is
            -- adopted as the last grid cell — the UIGridLayout owns its size/position from there.
            local rewards = mc:WaitForChild("rewards_button_pane", 15)
            if rewards then
                rewards.Size = UDim2.fromOffset(66, 64)
                for _ = 1, 10 do
                    local rb = rewards:FindFirstChild("RewardsButton")
                    if rb then
                        -- re-stack the icon (top-centre) + label (bottom) like a tray button
                        for _, c in ipairs(rb:GetChildren()) do
                            if c:IsA("TextLabel") then
                                if c.Text == "Rewards" then
                                    c.AnchorPoint = Vector2.new(0.5, 0)
                                    c.Position = UDim2.new(0.5, 0, 1, -19)
                                    c.Size = UDim2.new(1, -8, 0, 15)
                                    c.TextScaled = true
                                    c.TextXAlignment = Enum.TextXAlignment.Center
                                else
                                    c.AnchorPoint = Vector2.new(0.5, 0.5)
                                    c.Position = UDim2.new(0.5, 0, 0.4, 0)
                                    c.Size = UDim2.fromOffset(26, 26)
                                end
                            end
                        end
                        styleButton(rb, "citrine", nil) -- fixed gold, not area-tinted
                        -- adopt into the tray grid: last cell, grid layout sizes it
                        if pane then
                            rb.LayoutOrder = 99
                            rb.Parent = pane
                            rewards:Destroy() -- empty bottom-right pane (and its ViewportScale)
                        end
                        break
                    end
                    task.wait(0.5)
                end
            end
        end)

        -- re-tint the tray on area change
        Theme.bind(player, function(p)
            theme = p
            local key = pillKey(p)
            for _, s in ipairs(styled) do
                s.panel.Image = PILL.panels[key]
                s.frame.Image = PILL.frames[key]
            end
        end)
    end)
end

return MenuTrayStyle
