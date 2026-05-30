--[[
    ActiveSquad (pure) — Feature 9.

    Rules for the active fighting squad: a max size, and an in-combat swap
    cooldown (out of combat, swaps are instant). A stacked pet occupies one slot
    regardless of its count. Never mutates input; the service applies the result.

    Pure: standard Lua only; unit-tested via `mise run test-headless`.
]]

local ActiveSquad = {}

-- Whether another pet can be deployed given the current squad size.
function ActiveSquad.canDeploy(currentSize, maxSize)
    if currentSize >= maxSize then
        return { ok = false, reason = "active_squad_full" }
    end
    return { ok = true }
end

-- Whether a swap is allowed now. Out of combat: always. In combat: only once the
-- swap cooldown has elapsed (returns remaining time when blocked).
function ActiveSquad.canSwap(inCombat, lastSwapAt, now, cooldown)
    if not inCombat or lastSwapAt == nil then
        return { ok = true }
    end
    local elapsed = now - lastSwapAt
    if elapsed >= cooldown then
        return { ok = true }
    end
    return { ok = false, reason = "swap_cooldown_active", remaining = cooldown - elapsed }
end

return ActiveSquad
