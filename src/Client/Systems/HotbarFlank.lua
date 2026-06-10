--[[
    HotbarFlank (client) — dock Pets + Powers on either side of the power bar (Jason):

        [pets] [ ----------powerbar---------- ] [powers]

    Post-process in the MenuTrayStyle/CurrencyStack mold: BaseUI still BUILDS the buttons
    in the tray pane (click wiring untouched), MenuTrayStyle pill-styles them, and THIS
    module adopts the two into HotbarBar's root frame — full bar height, square (aspect
    constraint, Jason's relative-sizing convention), inheriting the bar's ViewportScale.
    The tutorial's PetsButton pulse finds the button by name recursively, so the move is
    transparent to it.
]]

local Players = game:GetService("Players")

local HotbarFlank = {}
local started = false

local SIDE = { PetsButton = "left", PowersButton = "right" }
local GAP = 14 -- px between the bar pill and each flank button

function HotbarFlank.start()
    if started then
        return
    end
    started = true
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")

    task.spawn(function()
        local hotbarGui = pg:WaitForChild("HotbarBar", 30)
        local bar = hotbarGui and hotbarGui:WaitForChild("Bar", 10)
        local base = pg:WaitForChild("ProfessionalBaseUI", 20)
        local mc = base and base:WaitForChild("MainContainer", 10)
        local pane = mc and mc:WaitForChild("menu_buttons_pane", 15)
        if not (bar and pane) then
            return
        end

        for name, side in pairs(SIDE) do
            task.spawn(function()
                local btn = pane:WaitForChild(name, 15)
                if not btn then
                    return
                end
                -- let MenuTrayStyle pill it first (the adopt would hide it from that pass)
                local deadline = os.clock() + 8
                while not btn:GetAttribute("Pillified") and os.clock() < deadline do
                    task.wait(0.25)
                end
                btn.AnchorPoint = side == "left" and Vector2.new(1, 0.5) or Vector2.new(0, 0.5)
                btn.Position = side == "left" and UDim2.new(0, -GAP, 0.5, 0)
                    or UDim2.new(1, GAP, 0.5, 0)
                btn.Size = UDim2.new(0, 0, 1, 0) -- height = the bar; width via aspect
                local aspect = btn:FindFirstChildOfClass("UIAspectRatioConstraint")
                    or Instance.new("UIAspectRatioConstraint")
                aspect.AspectRatio = 1
                aspect.DominantAxis = Enum.DominantAxis.Height
                aspect.Parent = btn
                btn.Parent = bar -- inherits the bar's ViewportScale
            end)
        end
    end)
end

return HotbarFlank
