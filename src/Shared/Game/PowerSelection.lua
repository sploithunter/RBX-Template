--[[
    PowerSelection — pure functional core for level-up power selection (Feature 14).

    No Roblox APIs. The service supplies the player's level, selected list, and the
    archetype's available power pool (computed via ArchetypeLogic). Selections are
    one-per-selection-level and accumulate; a power must be in the archetype pool
    and not already selected.

      selectionsReached(level, selectionLevels)                 -> integer
      pendingSelections(level, selectedCount, selectionLevels)  -> integer (>= 0)
      isSelected(powerId, selectedList)                         -> boolean
      canSelect(powerId, availablePowers, selectedList, level, selectionLevels)
                                                                -> { ok, reason? }
]]

local PowerSelection = {}

-- How many selection levels the player has reached at `level`.
function PowerSelection.selectionsReached(level, selectionLevels)
    local lvl = tonumber(level) or 1
    local count = 0
    for _, threshold in ipairs(selectionLevels or {}) do
        if lvl >= threshold then
            count += 1
        end
    end
    return count
end

-- Selections available to spend = levels reached - already selected (never < 0).
function PowerSelection.pendingSelections(level, selectedCount, selectionLevels)
    local reached = PowerSelection.selectionsReached(level, selectionLevels)
    return math.max(0, reached - (tonumber(selectedCount) or 0))
end

local function contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then
            return true
        end
    end
    return false
end

function PowerSelection.isSelected(powerId, selectedList)
    return contains(selectedList, powerId)
end

-- Validate a selection: in the archetype pool, not a duplicate, and a selection
-- is currently pending (level reached one not yet spent).
function PowerSelection.canSelect(powerId, availablePowers, selectedList, level, selectionLevels)
    if not contains(availablePowers, powerId) then
        return { ok = false, reason = "not_in_archetype_pool" }
    end
    if contains(selectedList, powerId) then
        return { ok = false, reason = "already_selected" }
    end
    local pending = PowerSelection.pendingSelections(level, #(selectedList or {}), selectionLevels)
    if pending <= 0 then
        return { ok = false, reason = "no_pending_selection" }
    end
    return { ok = true }
end

return PowerSelection
