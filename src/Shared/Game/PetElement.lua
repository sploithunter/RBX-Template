--[[
    PetElement (pure) — Feature 5.

    Element assignment at hatch is determined by the layer the hatch happened on
    (base → neutral, Heaven → light, Hell → shadow; chaotic is fusion-only, never
    at hatch), and the element is part of a stack's identity (a pet of a different
    element starts a new stack). Mappings are config-driven (configs/layers.lua).
]]

local PetElement = {}

-- Element a pet is born with when hatched on `layer` (default neutral).
function PetElement.elementForLayer(layer, layersConfig)
    local map = layersConfig and layersConfig.hatch_element
    return (map and map[layer]) or "neutral"
end

-- Realm alignment of a layer ("neutral"/"heaven"/"hell"), default neutral.
function PetElement.realmAlignmentForLayer(layer, layersConfig)
    local map = layersConfig and layersConfig.realm_alignment
    return (map and map[layer]) or "neutral"
end

-- Stack identity key: a different element (or variant) starts a new stack.
function PetElement.stackKey(petId, variant, element)
    return table.concat({ petId, variant or "basic", element or "neutral" }, ":")
end

return PetElement
