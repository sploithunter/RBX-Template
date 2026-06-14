--[[
    EnemyHud — the foes side of the combat HUD. A top-right strip that appears the moment a fight
    starts and lists every enemy aggro'd onto YOUR squad, sorted nearest-first. Built from the
    exact same HudCard chrome as the pet cards (SquadHud, right-centre), so "enemies up top, your
    squad below" both hug the right edge and read identically. (It started left-centre but collided
    with the currency stack, hiding the cards behind the coin pills — top-right keeps it clear.)

    The chain player → selected pet → enemy is made legible: the enemy your SELECTED pet is
    currently attacking — the indirect target — gets an amber border, the same colour the world
    SquadTargetHighlight already puts on that enemy. So selecting a pet and watching which enemy
    card lights up tells you exactly what your squad is hitting, and clicking an enemy card directs
    the squad to focus it (the same assist-target the world-click / Z-cycle set).

    Reads are pure off replicated state: enemy models in workspace.Game.Enemies carry HP / MaxHP /
    Level / DisplayName / AggroOwner (the player name the enemy is fighting, mirrored from the
    server's aggro table); the selected pet is the player's CombatBuffTarget slot; a pet's foe is
    its TargetID (matched to the enemy's BreakableID). No bespoke server feed.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signals = require(ReplicatedStorage.Shared.Network.Signals)
local HudCard = require(script.Parent.Parent.UI.HudCard)

local EnemyHud = {}

local localPlayer = Players.LocalPlayer

-- Threat chip colour (red) — the enemy counterpart to the pet's element disc.
local THREAT_RED = Color3.fromRGB(200, 64, 64)
-- Don't paper the screen in a big pull: show the nearest N foes (the ones you can act on).
local MAX_CARDS = 8

local function enemiesFolder()
    local g = Workspace:FindFirstChild("Game")
    return g and g:FindFirstChild("Enemies")
end

local function petsFolder()
    local pp = Workspace:FindFirstChild("PlayerPets")
    return pp and pp:FindFirstChild(localPlayer.Name)
end

local function petSlot(pet)
    local pn = pet:FindFirstChild("PositionNumber")
    return pn and pn.Value or 0
end

-- The enemy a pet is attacking: TargetID resolves to an enemy by BreakableID, but only while
-- TargetType is "Enemy" (a mining pet's TargetID points at a crystal). Returns the bid or nil.
local function petEnemyBid(pet)
    local tt = pet:FindFirstChild("TargetType")
    local tid = pet:FindFirstChild("TargetID")
    if tid and tid.Value ~= 0 and tt and tostring(tt.Value) == "Enemy" then
        return tid.Value
    end
    return nil
end

-- The INDIRECT target: the enemy the player's SELECTED pet (CombatBuffTarget slot) is attacking.
-- This is the card that lights amber — player → pet → enemy. nil when nothing is selected, the
-- selected pet is downed, or it isn't attacking an enemy.
local function indirectTargetBid()
    local slot = localPlayer:GetAttribute("CombatBuffTarget")
    if not slot or slot == 0 then
        return nil
    end
    local folder = petsFolder()
    if not folder then
        return nil
    end
    for _, pet in ipairs(folder:GetChildren()) do
        if pet:IsA("Model") and petSlot(pet) == slot then
            if pet:GetAttribute("CombatDowned") then
                return nil
            end
            return petEnemyBid(pet)
        end
    end
    return nil
end

-- Every enemy aggro'd onto MY squad, nearest first. An enemy counts as "mine" when its server-
-- mirrored AggroOwner is me OR one of my pets is currently biting it (covers the assist-sniper
-- case where a pet hits a foe before its aggro settles). Loitering enemies that haven't engaged
-- my squad stay off the strip — the HUD is the FIGHT, not the neighbourhood.
local function engagedEnemies()
    local char = localPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local origin = hrp and hrp.Position

    local petTargets = {}
    local pf = petsFolder()
    if pf then
        for _, pet in ipairs(pf:GetChildren()) do
            if pet:IsA("Model") then
                local bid = petEnemyBid(pet)
                if bid then
                    petTargets[bid] = true
                end
            end
        end
    end

    local out = {}
    local enemies = enemiesFolder()
    if enemies then
        for _, m in ipairs(enemies:GetChildren()) do
            if m:IsA("Model") and m.PrimaryPart and (m:GetAttribute("HP") or 0) > 0 then
                local bid = m:FindFirstChild("BreakableID")
                local mine = bid
                    and (m:GetAttribute("AggroOwner") == localPlayer.Name or petTargets[bid.Value])
                if mine then
                    out[#out + 1] = {
                        bid = bid.Value,
                        model = m,
                        dist = origin and (m.PrimaryPart.Position - origin).Magnitude or 0,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return a.dist < b.dist
    end)
    return out
end

function EnemyHud.start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "EnemyHud"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    gui.Parent = localPlayer:WaitForChild("PlayerGui")

    -- Top-right container, growing downward — enemies up top, the squad strip below (both right-
    -- edge). Left-centre collided with the currency stack, so the cards hid behind the coin pills.
    local root = Instance.new("Frame")
    root.Name = "Strip"
    root.AnchorPoint = Vector2.new(1, 0)
    root.Position = UDim2.new(1, -8, 0, 8)
    root.Size = UDim2.fromOffset(186, 10)
    root.AutomaticSize = Enum.AutomaticSize.Y
    root.BackgroundTransparency = 1
    root.Parent = gui
    require(script.Parent.Parent.UI.UIViewportScale).attach(root)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.Padding = UDim.new(0, 4)
    layout.Parent = root

    local cards = {} -- bid -> card refs

    local function makeCard(bid)
        local card = HudCard.createCard(root, { name = "Enemy_" .. bid })
        -- Foes have no element disc art; the chip is a flat red threat square with the enemy's
        -- level (the glyph fallback the chrome already supports), so the strip reads at a glance.
        card.roleIcon.Image = ""
        card.roleRing.Image = ""
        card.roleChip.BackgroundColor3 = THREAT_RED
        card.roleChip.BackgroundTransparency = 0
        card.roleGlyph.Visible = true
        -- Click an enemy card to direct the squad to focus it (same assist-target as a world click).
        card.frame.MouseButton1Click:Connect(function()
            Signals.Combat_SetAssist:FireServer({ targetId = bid })
        end)
        return card
    end

    local accum = 0
    RunService.RenderStepped:Connect(function(dt)
        accum += dt
        if accum < 0.2 then
            return
        end
        accum = 0

        local list = engagedEnemies()
        local focusBid = indirectTargetBid()
        local present = {}
        for rank, e in ipairs(list) do
            if rank > MAX_CARDS then
                break
            end
            present[e.bid] = true
            local card = cards[e.bid]
            if not card then
                card = makeCard(e.bid)
                cards[e.bid] = card
            end
            local m = e.model
            card.frame.LayoutOrder = rank
            card.name.Text =
                tostring(m:GetAttribute("DisplayName") or m:GetAttribute("EnemyId") or "Enemy")
            card.roleGlyph.Text = tostring(m:GetAttribute("Level") or "!")
            local hp = m:GetAttribute("HP") or 0
            local maxHp = math.max(1, m:GetAttribute("MaxHP") or 1)
            local frac = math.clamp(hp / maxHp, 0, 1)
            card.fill.Size = UDim2.fromScale(frac, 1)
            card.fill.BackgroundColor3 = HudCard.healthColor(frac)
            card.note.Text = ""
            -- The indirect target (player → selected pet → THIS enemy) wears the amber border,
            -- matching the world target highlight; every other foe shows the idle outline.
            HudCard.applyHighlight(card, (e.bid == focusBid) and "target" or nil)
        end
        for bid, card in pairs(cards) do
            if not present[bid] then
                card.frame:Destroy()
                cards[bid] = nil
            end
        end
    end)
end

return EnemyHud
