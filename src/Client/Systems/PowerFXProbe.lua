--[[
    PowerFXProbe (client) — the admin FX-probe harness (docs/PET_REALM_POWER_DATA_MODEL.md §11).

    Plays the `configs/power_fx.lua` registry primitives on demand so you can eyeball every
    primitive × element through the REAL CombatFX renderer — the "first visual test". Three modes:
      • casting — each `probe.casting` primitive on the player, cycling elements.
      • impact  — spawns a dummy ~N studs ahead, plays each `probe.impact` primitive at it.
      • real    — casting then impact (the full chain).

    A floating label names each effect (id · element) as it plays. The screen-capture stills catch
    presence / colour / lighting; you confirm motion + (later) sound. Client-only: FX are rendered
    locally, so the admin button calls PowerFXProbe.run(mode) directly — no server round-trip.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CombatFX = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Effects"):WaitForChild("CombatFX")
)
local FloatingText = require(ReplicatedStorage.Shared.Effects.FloatingText)
local PowerSound = require(ReplicatedStorage.Shared.Effects.PowerSound)
local FX = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("power_fx"))

local PowerFXProbe = {}

local running = 0 -- token: a new run cancels any in-flight one

local function hrp()
    local char = Players.LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Play one registry primitive through CombatFX.
--   pbaoe (self burst)  → ctx.caster
--   st_aoe (strike)     → ctx.point  (a position)
--   st_attack (bolt)    → ctx.target (a target Instance — the dummy)
--   attached (aura/bubble) → ctx.caster, with spec.category + spec.duration
local function playPrimitive(prim, element, point, targetInst)
    local spec = {
        pattern = prim.pattern,
        element = element,
        origin = prim.origin,
        category = prim.category,
        duration = prim.duration,
    }
    local ctx = { caster = hrp() }
    local soundPos = point
    if prim.pattern == "st_attack" then
        ctx.target = targetInst -- bolt needs a target Instance, not a point
    elseif prim.anchor == "target" then
        ctx.point = point
    else
        local r = hrp()
        soundPos = r and r.Position
    end
    pcall(function()
        CombatFX.play(spec, ctx)
    end)
    -- sound rides the primitive: an explicit soundPhase wins (buff/shield), else self ⇒ cast clip,
    -- target ⇒ impact clip (silent if none authored).
    local phase = prim.soundPhase or ((prim.anchor == "target") and "impact" or "cast")
    pcall(function()
        PowerSound.play(phase, element, soundPos)
    end)
end

local function label(pos, text)
    pcall(function()
        FloatingText.show(pos + Vector3.new(0, 6, 0), text, {
            color = Color3.fromRGB(255, 255, 255),
            size = 22,
            duration = 1.4,
            rise = 4,
        })
    end)
end

-- A persistent screen-space readout pinned to the LEFT side, so you always know which primitive ×
-- element is on screen (the floating text marks the spot; this names it).
local labelGui
local function ensureSideLabel()
    if labelGui and labelGui.Parent then
        return labelGui
    end
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then
        return nil
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "FXProbeReadout"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 60
    local box = Instance.new("Frame")
    box.Name = "Box"
    -- top-RIGHT, in the clear band above the squad strip: the left column (admin spawn + active-buffs)
    -- is packed while the probe runs, so this is the clear "off to the side" readout spot.
    box.AnchorPoint = Vector2.new(1, 0)
    box.Position = UDim2.new(1, -16, 0, 110)
    box.Size = UDim2.fromOffset(320, 60)
    box.BackgroundColor3 = Color3.fromRGB(18, 16, 26)
    box.BackgroundTransparency = 0.2
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = box
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(155, 120, 235)
    stroke.Thickness = 2
    stroke.Parent = box
    local txt = Instance.new("TextLabel")
    txt.Name = "Txt"
    txt.BackgroundTransparency = 1
    txt.Position = UDim2.fromOffset(14, 8)
    txt.Size = UDim2.new(1, -28, 1, -16)
    txt.Font = Enum.Font.GothamBold
    txt.TextColor3 = Color3.fromRGB(245, 240, 255)
    txt.TextSize = 19
    txt.TextXAlignment = Enum.TextXAlignment.Left
    txt.TextYAlignment = Enum.TextYAlignment.Center
    txt.TextWrapped = true
    txt.RichText = true
    txt.Text = ""
    txt.Parent = box
    box.Parent = gui
    gui.Parent = pg
    labelGui = gui
    return gui
end
local function setSideLabel(modeWord, id, element)
    local gui = ensureSideLabel()
    if not gui then
        return
    end
    gui.Enabled = true
    gui.Box.Txt.Text = string.format(
        '<font color="#b88cff"><b>%s</b></font>\n%s  ·  <b>%s</b>',
        modeWord,
        id,
        element
    )
end
local function hideSideLabel()
    if labelGui then
        labelGui.Enabled = false
    end
end

function PowerFXProbe.run(mode)
    running += 1
    local token = running
    task.spawn(function()
        local root = hrp()
        if not root then
            return
        end
        local probe = FX.probe
        local step = probe.step_seconds or 1.6

        local function doCasting()
            for _, element in ipairs(probe.elements) do
                for _, id in ipairs(probe.casting) do
                    if token ~= running then
                        return
                    end
                    local prim = FX.primitives[id]
                    if prim then
                        setSideLabel("CASTING", id, element)
                        playPrimitive(prim, element)
                        local r = hrp()
                        if r then
                            label(r.Position, ("cast: %s · %s"):format(id, element))
                        end
                    end
                    task.wait(step)
                end
            end
        end

        local function doImpact()
            local dist = probe.dummy_distance or 16
            local r = hrp()
            if not r then
                return
            end
            local dummy = Instance.new("Part")
            dummy.Name = "FXProbeDummy"
            dummy.Anchored = true
            dummy.CanCollide = false
            dummy.CanQuery = false
            dummy.Size = Vector3.new(4, 6, 4)
            dummy.Color = Color3.fromRGB(60, 60, 70)
            dummy.Material = Enum.Material.SmoothPlastic
            dummy.Transparency = 0.4
            dummy.CFrame = r.CFrame * CFrame.new(0, 0, -dist)
            dummy.Parent = Workspace
            for _, element in ipairs(probe.elements) do
                for _, id in ipairs(probe.impact) do
                    if token ~= running then
                        dummy:Destroy()
                        return
                    end
                    local prim = FX.primitives[id]
                    if prim then
                        setSideLabel("IMPACT", id, element)
                        playPrimitive(prim, element, dummy.Position, dummy)
                        label(dummy.Position, ("impact: %s · %s"):format(id, element))
                    end
                    task.wait(step)
                end
            end
            dummy:Destroy()
        end

        if mode == "casting" then
            doCasting()
        elseif mode == "impact" then
            doImpact()
        elseif mode == "real" then
            doCasting()
            if token == running then
                doImpact()
            end
        end
        if token == running then
            hideSideLabel() -- run done (a newer run would have bumped the token)
        end
    end)
end

return PowerFXProbe
