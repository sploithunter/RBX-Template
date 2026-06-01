--[[
    AggroTable — pure threat-table core (Halo & Horns combat).

    Each enemy keeps an aggro table: a map of attacker -> accumulated aggro value. The
    enemy targets (chases + attacks) whoever is highest. Aggro is built by hurting the
    enemy (pets mining it) and by passive threat (a tank's Threat stat ticks it up), and
    it DECAYS over time — so when nothing keeps attacking, the top entry bleeds to zero
    and the enemy disengages. Powers can `clear` an entry (pacify) or `add` a big chunk
    (taunt / a player drawing aggro).

    Pure + Roblox-free: keys are opaque (pet Models / Players at runtime, strings in
    tests); values are numbers. The caller resolves a key's world position + validity.
]]

local AggroTable = {}

function AggroTable.new()
    return { values = {} }
end

-- Add (or subtract) aggro for an attacker. Clamped at 0 (never negative). No-op for a
-- nil key or zero amount.
function AggroTable.add(state, key, amount)
    if key == nil or not amount or amount == 0 then
        return
    end
    local v = (state.values[key] or 0) + amount
    state.values[key] = (v > 0) and v or nil
end

function AggroTable.get(state, key)
    return state.values[key] or 0
end

-- Pacify: drop an attacker from the table entirely (aggro -> 0).
function AggroTable.clear(state, key)
    if key ~= nil then
        state.values[key] = nil
    end
end

-- Bleed every entry toward 0 by ratePerSecond * dt; entries that reach 0 are removed.
function AggroTable.decay(state, dt, ratePerSecond)
    local drop = (ratePerSecond or 0) * (dt or 0)
    if drop <= 0 then
        return
    end
    for key, v in pairs(state.values) do
        local nv = v - drop
        state.values[key] = (nv > 0) and nv or nil
    end
end

-- Highest-aggro key with value strictly above `minValue`, optionally filtered by
-- isValid(key) (e.g. skip downed/despawned attackers). Returns key, value — or nil if
-- the table is empty / everything is filtered out / nothing exceeds minValue.
function AggroTable.top(state, minValue, isValid)
    local floor = minValue or 0
    local bestKey, bestVal
    for key, v in pairs(state.values) do
        if v > floor and (not isValid or isValid(key)) then
            if not bestVal or v > bestVal then
                bestKey, bestVal = key, v
            end
        end
    end
    return bestKey, bestVal
end

-- Count of live entries (for tests / debug).
function AggroTable.size(state)
    local n = 0
    for _ in pairs(state.values) do
        n += 1
    end
    return n
end

return AggroTable
