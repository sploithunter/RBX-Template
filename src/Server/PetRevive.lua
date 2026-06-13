--[[
    PetRevive — THE single definition of what reviving a pet means.

    Jason: "why do we have three revive sites? Why does the caster matter at
    all?" It shouldn't. Casters (squad Summon button, the Revive power, genie
    summon, natural recovery) decide WHETHER and WHICH pet; this module owns
    WHAT happens: clear the downed state, heal, zero cooldown, teleport the
    REUSED model to its owner (it otherwise pops up wherever it died and
    resumes that fight), and drop any stale target so it falls into formation.

    Add future revive behavior (VFX, events, invulnerability windows) HERE.
]]

local Players = game:GetService("Players")

local PetRevive = {}

-- pet: the pet Model. owner (optional): the owning Player; resolved from the
-- pet's folder name when omitted. Safe on non-downed pets (idempotent).
function PetRevive.revive(pet, owner)
    if not (pet and pet.Parent) then
        return false
    end
    pet:SetAttribute("CombatDowned", false)
    pet:SetAttribute("CombatDamageTaken", 0)
    pet:SetAttribute("CooldownUntil", 0)
    pet:SetAttribute("DownedReason", "")
    owner = owner or Players:FindFirstChild(pet.Parent.Name)
    local hrp = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        pet:PivotTo(CFrame.new(hrp.Position + Vector3.new(2, 2, 2)))
    end
    local tid = pet:FindFirstChild("TargetID")
    if tid then
        tid.Value = 0
    end
    return true
end

return PetRevive
