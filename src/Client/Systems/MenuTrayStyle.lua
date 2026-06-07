--[[
    MenuTrayStyle (client) — skin the lower-left tray buttons (Trade/Admin/Daily/Quest/Shop/Items/
    Effects/Settings) with Jason's pill art: a glossy pill_panel background + a neon pill_frame border
    behind the existing icon + label, matching assets/ui/reference/quest_button_reference.jpg.

    Done as a scoped post-process (only the 8 named buttons in ProfessionalBaseUI's menu_buttons_pane)
    so BaseUI's button-building logic is untouched. Area-themed via UITheme (defaults to the sapphire
    pill until a home area is chosen). Idempotent per button.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PILL = require(ReplicatedStorage.Configs:WaitForChild("pill_ui"))

local MenuTrayStyle = {}
local started = false

local BUTTONS = {
    "TradeButton",
    "AdminButton",
    "DailyButton",
    "QuestButton",
    "ShopButton",
    "InventoryButton",
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

local function styleButton(btn, theme, styled)
    if btn:GetAttribute("Pillified") then
        return
    end
    btn:SetAttribute("Pillified", true)

    -- strip the flat background styling
    if btn:IsA("ImageButton") then
        btn.Image = ""
    end
    btn.BackgroundTransparency = 1
    for _, c in ipairs(btn:GetChildren()) do
        if c:IsA("UIGradient") or c:IsA("UIStroke") or c:IsA("UICorner") then
            c:Destroy()
        end
    end

    local key = pillKey(theme)
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

    -- lift the existing icon / label / notification above the pills + outline the label
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

    table.insert(styled, { panel = panel, frame = frame })
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
        local pane
        for _ = 1, 30 do
            pane = mc and mc:FindFirstChild("menu_buttons_pane")
            if pane then
                break
            end
            task.wait(0.5)
        end
        if not pane then
            return
        end

        local styled = {}
        local theme = Theme.palette(player)
        local function applyAll()
            for _, name in ipairs(BUTTONS) do
                local btn = pane:FindFirstChild(name)
                if btn then
                    styleButton(btn, theme, styled)
                end
            end
        end
        -- buttons may stream in; retry a few times
        task.spawn(function()
            for _ = 1, 10 do
                applyAll()
                task.wait(0.5)
            end
        end)

        -- re-tint on area change
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
