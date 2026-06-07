--[[
    CurrencyStyle (client) — skin the left-side currency boxes (gems + per-area coins) as ROUND
    capsules ("pills") in each currency's area color: gems=amethyst(purple), grass=emerald(green),
    desert=citrine(yellow), lava=ruby(red), ice=sapphire(blue).

    The round-end capsule comes from UICorner(1,0) on the pane itself (a full-circle ring asset just
    becomes an ellipse when stretched this thin, so we shape it programmatically) + a glossy gradient
    + a brighter stroke border. The value text is left clean — no heavy outline.

    Scoped post-process of ProfessionalBaseUI's *_pane currency frames (BaseUI logic untouched).
    Idempotent per box.
]]

local Players = game:GetService("Players")

local CurrencyStyle = {}
local started = false

-- area key -> capsule fill + lighter top/stroke
local COLORS = {
    amethyst = { fill = Color3.fromRGB(120, 60, 200), light = Color3.fromRGB(180, 110, 235) },
    emerald = { fill = Color3.fromRGB(40, 155, 75), light = Color3.fromRGB(95, 220, 125) },
    citrine = { fill = Color3.fromRGB(200, 150, 35), light = Color3.fromRGB(240, 200, 70) },
    ruby = { fill = Color3.fromRGB(185, 45, 45), light = Color3.fromRGB(235, 90, 90) },
    sapphire = { fill = Color3.fromRGB(40, 110, 210), light = Color3.fromRGB(95, 165, 240) },
}

local BOXES = {
    gems_pane = "amethyst",
    grass_coins_pane = "emerald",
    desert_coins_pane = "citrine",
    lava_coins_pane = "ruby",
    ice_coins_pane = "sapphire",
}

local function styleBox(pane, key)
    if pane:GetAttribute("Capsuled") then
        return
    end
    pane:SetAttribute("Capsuled", true)
    local col = COLORS[key]

    -- drop the old square border / any earlier squircle overlay, and any heavy text outlines added before
    for _, c in ipairs(pane:GetChildren()) do
        if
            c:IsA("UIStroke")
            or c:IsA("UICorner")
            or c:IsA("UIGradient")
            or c.Name == "PillPanel"
            or c.Name == "PillFrame"
        then
            c:Destroy()
        end
    end
    for _, d in ipairs(pane:GetDescendants()) do
        if d:IsA("UIStroke") and d.Parent and d.Parent:IsA("TextLabel") then
            d:Destroy()
        end
    end

    -- the pane itself becomes the round capsule
    pane.BackgroundColor3 = col.fill
    pane.BackgroundTransparency = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0) -- fully round ends (capsule)
    corner.Parent = pane
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new(col.light, col.fill) -- glossy: light top -> fill bottom
    grad.Parent = pane
    local stroke = Instance.new("UIStroke")
    stroke.Color = col.light
    stroke.Thickness = 2.5
    stroke.Parent = pane
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
