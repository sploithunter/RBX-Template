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
    -- sound rides the primitive: self ⇒ cast clip, target ⇒ impact clip (silent if none authored)
    local phase = (prim.anchor == "target") and "impact" or "cast"
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
    end)
end

return PowerFXProbe
