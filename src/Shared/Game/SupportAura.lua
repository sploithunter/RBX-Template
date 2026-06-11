--[[
    SupportAura — pure resolver for a pet's team "buffer" aura (Halo & Horns).

    Every zone has ONE support pet whose presence boosts the rest of the squad — the
    City-of-Heroes "buffer". The aura is config-as-code: configs/pet_roles.lua carries a
    `support_auras` table keyed by PetType (a pet can also override with a `SupportAura`
    model attribute later). This module is the Roblox-free lookup; EnemyService:_supportPass
    applies whatever it returns on the aura's interval.

    Aura kinds (the four zone flavours), all dev-tunable in pet_roles.lua:
      heal     — mend the most-hurt ally (Grass / bunny). { interval, fraction|amount }
      defense  — team damage reduction; writes TeamDefenseBuff on allies (Ice / penguin).
      offense  — team +damage on the owner; boosts mining AND combat (Lava / emberimp).
      yield    — team +coin payout on mining (Desert / meerkat). { interval, mult, duration }

    SupportAura.forPet(petType, rolesConfig) -> aura table (with .kind) | nil
    SupportAura.isBuffer(petType, rolesConfig) -> boolean
]]

local SupportAura = {}

function SupportAura.forPet(petType, rolesConfig)
    local list = SupportAura.aurasFor(petType, rolesConfig)
    return list and list[1] or nil
end

-- A pet's auras as a LIST. Config value may be a single aura table { kind = ... } or an
-- ARRAY of them (creator pets carry every buffer — Jason). Single wraps to a one-list.
-- isCreator: a CREATOR-CLASS record gets the `<petType>_creator` entry when one exists
-- (regular colorados buff less than Jason's apex).
function SupportAura.aurasFor(petType, rolesConfig, isCreator)
    if type(rolesConfig) ~= "table" or petType == nil then
        return nil
    end
    local auras = rolesConfig.support_auras
    if type(auras) ~= "table" then
        return nil
    end
    local entry = (isCreator == true and auras[tostring(petType) .. "_creator"]) or auras[petType]
    if type(entry) ~= "table" then
        return nil
    end
    if entry.kind ~= nil then
        return { entry }
    end
    if type(entry[1]) == "table" and entry[1].kind ~= nil then
        return entry
    end
    return nil
end

function SupportAura.isBuffer(petType, rolesConfig)
    return SupportAura.forPet(petType, rolesConfig) ~= nil
end

return SupportAura
