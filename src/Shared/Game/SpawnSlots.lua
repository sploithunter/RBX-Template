--[[
    SpawnSlots — pure slot-layout + occupancy registry for crystal/chest spawning.

    Replaces per-spawn raycasting + the O(N) min-distance scan with a PRECOMPUTED set of well-spaced
    spawn points (slots) plus an occupancy registry. The service raycast-validates a layout ONCE on
    world activation; thereafter spawning is O(free): claim a free slot, place, mark occupied; on
    mine, release. Overlap is impossible by construction — a jitter-free grid layout keeps neighbours
    >= `spacing` apart, so no runtime distance/clearance check is needed.

    Two slot kinds coexist (see design discussion — random little crystals + fixed special anchors):
      - common slots (kind = nil): generated over a spawner's area; claimed by ordinary spawns
      - typed slots (kind = "special"/…): authored FIXED anchors (giant crystal, chest); only claimed
        by a spawn requesting that exact kind, so a chest always lands in its hand-placed spot

    PURE: no Roblox APIs, no os/Date/math.random globals — an `rng` function (→ [0,1)) is injected so
    layouts + claims are deterministic in tests. The service passes Random:NextNumber.
]]

local SpawnSlots = {}

local function clamp(n, lo, hi)
    if n < lo then
        return lo
    elseif n > hi then
        return hi
    end
    return n
end

-- Jittered grid of { x, z } offsets centred on (0, 0), covering `width` × `depth` on a `spacing`
-- grid. `jitter` (0..0.5) displaces each point up to jitter*spacing; with jitter = 0, orthogonal
-- neighbours are guaranteed >= spacing apart (diagonals >= spacing*√2). rng() → [0,1); defaults to
-- centred (0.5) so an omitted rng yields a clean deterministic grid. The service adds the spawner
-- centre + raycasts the surface Y, then validates each point ONCE.
function SpawnSlots.layoutGrid(opts)
    opts = opts or {}
    local width = tonumber(opts.width) or 0
    local depth = tonumber(opts.depth) or 0
    local spacing = math.max(0.01, tonumber(opts.spacing) or 1)
    local jitter = clamp(tonumber(opts.jitter) or 0, 0, 0.5)
    local rng = opts.rng or function()
        return 0.5
    end

    local cols = math.max(1, math.floor(width / spacing))
    local rows = math.max(1, math.floor(depth / spacing))
    -- centre the grid symmetrically about (0,0): span = (n-1)*spacing
    local x0 = -((cols - 1) * spacing) / 2
    local z0 = -((rows - 1) * spacing) / 2

    local points = {}
    for c = 0, cols - 1 do
        for r = 0, rows - 1 do
            local jx = (rng() - 0.5) * 2 * jitter * spacing
            local jz = (rng() - 0.5) * 2 * jitter * spacing
            points[#points + 1] = { x = x0 + c * spacing + jx, z = z0 + r * spacing + jz }
        end
    end
    return points
end

-- ===== Occupancy registry =====

local Registry = {}
Registry.__index = Registry

-- A common slot (kind nil) is matched only by a kind-nil claim; a typed slot is matched only by a
-- claim of that exact kind — so special anchors never get consumed by ordinary spawns.
local function matches(slot, kind)
    return slot.kind == kind
end

-- slots: array of { id?, kind?, pos? }. Only `id` (unique; auto-numbered when absent) and `kind`
-- matter to the registry; `pos` (and any extra fields) are carried through for the caller.
function SpawnSlots.new(slots)
    local self = setmetatable({ _slots = {}, _byId = {} }, Registry)
    for i, s in ipairs(slots or {}) do
        local id = s.id == nil and i or s.id
        local slot = { id = id, kind = s.kind, pos = s.pos, ref = nil }
        self._slots[#self._slots + 1] = slot
        self._byId[id] = slot
    end
    return self
end

function Registry:total()
    return #self._slots
end

function Registry:freeCount(kind)
    local n = 0
    for _, s in ipairs(self._slots) do
        if s.ref == nil and matches(s, kind) then
            n += 1
        end
    end
    return n
end

function Registry:occupiedCount(kind)
    local n = 0
    for _, s in ipairs(self._slots) do
        if s.ref ~= nil and matches(s, kind) then
            n += 1
        end
    end
    return n
end

function Registry:isFull(kind)
    return self:freeCount(kind) == 0
end

function Registry:isOccupied(id)
    local s = self._byId[id]
    return s ~= nil and s.ref ~= nil
end

-- Claim a random free slot of `kind` (nil = common). rng() → [0,1). `ref` is an opaque token (the
-- spawned model) stored so release-by-ref works. Returns the slot { id, kind, pos } or nil if none
-- free. The returned table is the registry's own slot record — treat pos/id as read-only.
function Registry:claim(kind, rng, ref)
    rng = rng or function()
        return 0
    end
    local free = {}
    for _, s in ipairs(self._slots) do
        if s.ref == nil and matches(s, kind) then
            free[#free + 1] = s
        end
    end
    if #free == 0 then
        return nil
    end
    local idx = math.floor(rng() * #free) + 1
    idx = clamp(idx, 1, #free)
    local slot = free[idx]
    slot.ref = ref ~= nil and ref or true
    return slot
end

-- Mark a specific slot occupied (e.g. re-hydrating from existing models on activation). No-op if the
-- id is unknown or already occupied; returns whether it newly occupied.
function Registry:occupy(id, ref)
    local s = self._byId[id]
    if s and s.ref == nil then
        s.ref = ref ~= nil and ref or true
        return true
    end
    return false
end

-- Free a slot by id. Returns whether it freed one.
function Registry:release(id)
    local s = self._byId[id]
    if s and s.ref ~= nil then
        s.ref = nil
        return true
    end
    return false
end

-- Free whichever slot holds this ref (the mined model). Returns the freed slot id or nil.
function Registry:releaseByRef(ref)
    for _, s in ipairs(self._slots) do
        if s.ref == ref then
            s.ref = nil
            return s.id
        end
    end
    return nil
end

return SpawnSlots
