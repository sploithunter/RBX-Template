--[[
    CurrencyStyle (client) — skin the left-side currency boxes (gems + the per-area coins) with Jason's
    pill art: a glossy pill_panel background + pill_frame border, stretched (9-slice) to the wide box so
    the corners stay proportional. Each box takes the gem color of its currency's area, matching the
    border color BaseUI already gave it:
        gems -> amethyst, grass -> emerald, desert -> citrine, lava -> ruby, ice -> sapphire.

    Scoped post-process of ProfessionalBaseUI's *_pane currency frames (BaseUI logic untouched).
    Idempotent per box.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PILL = require(ReplicatedStorage.Configs:WaitForChild("pill_ui"))

local CurrencyStyle = {}
local started = false

local BOXES = {
    gems_pane = "amethyst",
    grass_coins_pane = "emerald",
    desert_coins_pane = "citrine",
    lava_coins_pane = "ruby",
    ice_coins_pane = "sapphire",
}

local SLICE = Rect.new(180, 180, 330, 330)

local function styleBox(pane, key)
    if pane:GetAttribute("Pillified") then
        return
    end
    pane:SetAttribute("Pillified", true)

    pane.BackgroundTransparency = 1
    for _, c in ipairs(pane:GetChildren()) do
        if c:IsA("UIStroke") or c:IsA("UICorner") or c:IsA("UIGradient") then
            c:Destroy()
        end
    end

    local panel = Instance.new("ImageLabel")
    panel.Name = "PillPanel"
    panel.BackgroundTransparency = 1
    panel.ScaleType = Enum.ScaleType.Slice
    panel.SliceCenter = SLICE
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromScale(1, 1)
    panel.Image = PILL.panels[key]
    panel.ZIndex = 1
    panel.Parent = pane
    local frame = Instance.new("ImageLabel")
    frame.Name = "PillFrame"
    frame.BackgroundTransparency = 1
    frame.ScaleType = Enum.ScaleType.Slice
    frame.SliceCenter = SLICE
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromScale(1, 1)
    frame.Image = PILL.frames[key]
    frame.ZIndex = 2
    frame.Parent = pane

    -- lift the content (icon + value) above the pills + outline the value so it reads on the panel
    for _, c in ipairs(pane:GetChildren()) do
        if c ~= panel and c ~= frame and c:IsA("GuiObject") then
            c.ZIndex = 5
            for _, d in ipairs(c:GetDescendants()) do
                if d:IsA("GuiObject") then
                    d.ZIndex = 6
                end
                if d:IsA("TextLabel") and not d:FindFirstChildOfClass("UIStroke") then
                    local s = Instance.new("UIStroke")
                    s.Color = Color3.fromRGB(8, 12, 24)
                    s.Thickness = 2
                    s.Parent = d
                end
            end
        end
    end
end

function CurrencyStyle.start()
    if started then
        return
    end
    started = true
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")

    task.spawn(function()
        local base = pg:WaitForChild("ProfessionalBaseUI", 20)
        local mc = base and base:WaitForChild("MainContainer", 10)
        if not mc then
            return
        end
        for _ = 1, 12 do
            for name, key in pairs(BOXES) do
                local pane = mc:FindFirstChild(name)
                if pane then
                    styleBox(pane, key)
                end
            end
            task.wait(0.5)
        end
    end)
end

return CurrencyStyle
