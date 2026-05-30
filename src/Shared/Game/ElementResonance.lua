--[[
    ElementResonance (pure) — Feature 6.

    Looks up the element resonance multiplier for a pet element in a realm
    alignment ("heaven" / "hell" / "neutral") from configs/elements.lua. Unknown
    element or realm defaults to 1.0 (no effect).
]]

local ElementResonance = {}

function ElementResonance.multiplier(element, realmAlignment, config)
    local resonance = config and config.resonance
    local row = resonance and resonance[element]
    if not row then
        return 1.0
    end
    return row[realmAlignment] or 1.0
end

return ElementResonance
