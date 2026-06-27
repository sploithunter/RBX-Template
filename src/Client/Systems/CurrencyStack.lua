--[[
    CurrencyStack (client) — gather the five currency panes into ONE tight vertical stack.

    Each currency is its own BaseUI pane (own pill background/border — keep that), but as
    separate panes their POSITIONS are fixed pixel offsets while their SIZES shrink with
    UIViewportScale — so on small screens the pills drift apart (Jason: "they should be
    stacked"). Reparenting them into a single list container fixes it structurally: the
    UIListLayout owns the spacing and ONE UIScale on the container scales pills AND gaps
    together, so the stack reads identically at every viewport size.

    Post-process in the MenuTrayStyle/QuestTrackerStyle mold: BaseUI logic untouched.
    CurrencyStyle finds these panes recursively, so the reparent is transparent to it.
]]

local Players = game:GetService("Players")

local CurrencyStack = {}
local started = false

-- top-to-bottom pill order (gems first, then biome coins)
local PANES = {
    "gems_pane",
    "grass_coins_pane",
    "desert_coins_pane",
    "lava_coins_pane",
    "ice_coins_pane",
}

function CurrencyStack.start()
    if started then
        return
    end
    started = true
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")

    task.spawn(function()
        -- No give-up timeout (see MenuTrayStyle): a non-owner's late/stalled BaseUI boot used to
        -- outlast the old 20s window, leaving the currency boxes un-stacked/unstyled.
        local base = pg:WaitForChild("ProfessionalBaseUI")
        local mc = base and base:WaitForChild("MainContainer", 10)
        if not mc then
            return
        end

        local stack = Instance.new("Frame")
        stack.Name = "CurrencyStack"
        stack.AnchorPoint = Vector2.new(0, 0.5)
        stack.Position = UDim2.new(0, 15, 0.5, 0)
        stack.Size = UDim2.fromOffset(140, 0)
        stack.AutomaticSize = Enum.AutomaticSize.Y
        stack.BackgroundTransparency = 1
        stack.ZIndex = 12
        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Vertical
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        layout.Padding = UDim.new(0, 5)
        layout.Parent = stack
        stack.Parent = mc
        -- ONE scale for the whole stack: pills + gaps shrink together (tight at any size)
        require(script.Parent.Parent.UI.UIViewportScale).attach(stack)

        for order, name in ipairs(PANES) do
            task.spawn(function()
                local pane = mc:WaitForChild(name, 15)
                if not pane then
                    return
                end
                -- the pane's own per-pane scale would double-shrink inside the scaled stack
                local own = pane:FindFirstChild("ViewportScale")
                if own then
                    own:Destroy()
                end
                pane.LayoutOrder = order
                pane.Parent = stack
            end)
        end
    end)
end

return CurrencyStack
