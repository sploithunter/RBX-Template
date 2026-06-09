--[[
    PowerChoiceMenu — the interactive level-up workflow (Feature 14/15 surface).

    Dual column: NATURAL (generic pool, purple) + one ORIGIN archetype (element-coloured).
    You level up from 1; every level grants SOMETHING to do (config-driven cadence):
      • a power-pick level (in powers.selection_levels) -> pick ONE not-yet-owned power
        that's unlocked at your level (click an "available" row).
      • otherwise -> place 2 enhancement slots onto powers you already own (click an "owned"
        row to add a slot, up to 6 — the slots PowerSlotRow already draws).

    STAGE → COMMIT. Clicking a row STAGES the choice; nothing is final until you press COMMIT.
      • pick beat: clicking is a radio — a second power replaces the first; clicking the staged
        one clears it.
      • slot beat: each click stages a slot; ↶ UNDO pops the last staged action.
      • COMMIT writes the staged beat into `owned` + the log; then LEVEL UP unlocks the next beat.
        You cannot level past an un-committed beat, and must spend the grant before committing.
      • committed picks are permanent (RESET is the dev full-run wipe; real respec comes later).

    TWO MODES (same UX, different data source):
      • LIVE (default when the GameAPICommand bus is up): the SERVER is authoritative. On open we
        load archetype.get / power.get / augment.get / levelup.getState; the origin is LOCKED to the
        player's real archetype. COMMIT sends the staged beat to the bus (pick -> power.select,
        slot -> augment.place), LEVEL UP -> levelup.claim (one real level per click); admins can
        bank a level first (levelup.bank) to walk the track without grinding XP. After each call we
        re-read the server and re-render. RESET = discard staged + resync (no destructive wipe).
      • PREVIEW (fallback if the bus isn't reachable): a purely local model (level / owned / pending
        / staged + self.log), origin cycles via the header, RESET wipes the local run from L1.

    MenuManager panel interface: new() -> { Show(parent), Hide(), GetFrame() }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local powersCfg = require(Configs:WaitForChild("powers"))
local archetypesCfg = require(Configs:WaitForChild("archetypes"))
local PowerSelection = require(ReplicatedStorage.Shared.Game.PowerSelection)
local PowerSlotRow = require(script.Parent.Parent.PowerSlotRow)

-- Bus call (mirrors LevelUpController): returns the handler's domain result, or nil if the bus
-- isn't up. Synchronous (RemoteFunction). Used only in LIVE mode.
local function callBus(name, args)
    local remote = ReplicatedStorage:FindFirstChild("GameAPICommand")
    if not remote then
        return nil
    end
    local ok, envelope = pcall(function()
        return remote:InvokeServer(name, args or {})
    end)
    if not ok or type(envelope) ~= "table" then
        return nil
    end
    return envelope.result
end

local function isAdmin()
    local lp = Players.LocalPlayer
    return RunService:IsStudio() or (lp and lp:GetAttribute("IsAdmin") == true)
end

local ORIGINS = { "geomancer", "sandwalker", "cryomancer", "pyromancer" }
local ORIGIN_COLOR = {
    geomancer = Color3.fromRGB(150, 230, 150),
    sandwalker = Color3.fromRGB(240, 215, 130),
    cryomancer = Color3.fromRGB(140, 200, 255),
    pyromancer = Color3.fromRGB(255, 150, 120),
}
local NATURAL_COLOR = Color3.fromRGB(196, 156, 255)
local MAX_LEVEL = 50
local MAX_SLOTS = 6
local SLOTS_PER_ROUND = 2

-- chip palette (base colours; dimmed when a chip is disabled)
local COMMIT_COLOR = Color3.fromRGB(235, 200, 90)
local UNDO_COLOR = Color3.fromRGB(150, 150, 165)
local LEVEL_COLOR = Color3.fromRGB(120, 205, 130)
local RESET_COLOR = Color3.fromRGB(150, 120, 200)
local STAGED_GLOW = Color3.fromRGB(235, 200, 90)

-- selection levels -> set, for O(1) "is this a power level?"
local SEL = {}
for _, l in ipairs(powersCfg.selection_levels or {}) do
    SEL[l] = true
end

-- what a given level grants: "power" (1, on a selection level) or "slots" (2). L1 grants nothing —
-- the lowest power unlocks at L2, so the first LEVEL UP (to L2) hands you your first pick.
local function grantFor(level)
    if SEL[level] then
        return "power", 1
    end
    return "slots", SLOTS_PER_ROUND
end

local function pickLevelOf(id)
    local def = powersCfg.powers[id]
    return PowerSelection.pickLevel(def and def.unlock_level or 1, powersCfg.selection_levels)
end

local PowerChoiceMenu = {}
PowerChoiceMenu.__index = PowerChoiceMenu

function PowerChoiceMenu.new()
    local self = setmetatable({}, PowerChoiceMenu)
    self.frame = nil
    self.originIndex = 1
    self.level = 1
    self.owned = {} -- [powerId] = slotCount (1..6) — COMMITTED only
    self.pendingPower = 0 -- power picks granted this beat (not yet committed)
    self.pendingSlots = 0 -- slots granted this beat (not yet committed)
    self.staged = {} -- { { action = "pick"|"slot", id = powerId }, ... } — reversible, pre-commit
    self.log = {} -- COMMITTED actions (preview mode only): { { action, id, level }, ... }
    -- live (server-backed) state
    self.live = false -- true once the bus loads real state; false = local preview fallback
    self.archetype = nil -- the player's real origin (live mode locks the ORIGIN column to it)
    self.pendingLevels = 0 -- earned - claimed (claimable level-ups waiting), from the server
    self.atMax = false
    self.notice = nil -- transient error/notice text (e.g. a rejected bus call)
    -- ui refs
    self.naturalCol = nil
    self.originCol = nil
    self.originHeader = nil
    self.statusLabel = nil
    self.levelBtn = nil
    self.commitBtn = nil
    self.undoBtn = nil
    return self
end

-- ---- staged-buffer helpers ----------------------------------------------

function PowerChoiceMenu:_stagedPickCount()
    local n = 0
    for _, s in ipairs(self.staged) do
        if s.action == "pick" then
            n += 1
        end
    end
    return n
end

function PowerChoiceMenu:_stagedSlotCount()
    local n = 0
    for _, s in ipairs(self.staged) do
        if s.action == "slot" then
            n += 1
        end
    end
    return n
end

function PowerChoiceMenu:_stagedSlotsOn(id)
    local n = 0
    for _, s in ipairs(self.staged) do
        if s.action == "slot" and s.id == id then
            n += 1
        end
    end
    return n
end

function PowerChoiceMenu:_isStagedPick(id)
    for _, s in ipairs(self.staged) do
        if s.action == "pick" and s.id == id then
            return true
        end
    end
    return false
end

-- slots that would show on a row: committed base + staged slots (staged pick = its inherent 1)
function PowerChoiceMenu:_effectiveSlots(id)
    if self.owned[id] then
        return self.owned[id] + self:_stagedSlotsOn(id)
    elseif self:_isStagedPick(id) then
        return 1
    end
    return 1
end

function PowerChoiceMenu:_remainingPicks()
    return self.pendingPower - self:_stagedPickCount()
end

function PowerChoiceMenu:_remainingSlots()
    return self.pendingSlots - self:_stagedSlotCount()
end

-- is there ANY committed power that could still take a slot? (avoids a late-game commit soft-lock)
function PowerChoiceMenu:_canPlaceSlot()
    for id, count in pairs(self.owned) do
        if count + self:_stagedSlotsOn(id) < MAX_SLOTS then
            return true
        end
    end
    return false
end

-- COMMIT is allowed once the beat's grant is fully allocated (picks always; slots unless none fit)
function PowerChoiceMenu:_canCommit()
    if self.pendingPower == 0 and self.pendingSlots == 0 then
        return false -- nothing granted this beat
    end
    if self:_remainingPicks() > 0 then
        return false
    end
    if self:_remainingSlots() > 0 and self:_canPlaceSlot() then
        return false
    end
    return true
end

-- ---- live (server-backed) state -----------------------------------------

-- Pull the player's REAL state off the bus into the menu's cache. Returns false if the bus isn't
-- up (caller falls back to local preview). Slot count per power = #data.Slots[id] (incl. the free
-- inherent slot). pendingPower/pendingSlots come straight from the server's owed amounts.
function PowerChoiceMenu:_loadLive()
    local arche = callBus("archetype.get", {})
    local lvl = callBus("levelup.getState", {})
    local pw = callBus("power.get", {})
    local aug = callBus("augment.get", {})
    if not (arche and lvl and lvl.state and pw and aug) then
        return false
    end
    local st = lvl.state
    self.archetype = arche.archetype
    self.level = st.claimedLevel or 1
    self.pendingLevels = math.max(0, st.pendingLevels or 0)
    self.atMax = st.atMax == true or self.level >= MAX_LEVEL
    self.owned = {}
    local slots = aug.slots or {}
    for _, id in ipairs(pw.powers or {}) do
        local list = slots[id]
        self.owned[id] = (type(list) == "table" and #list) or 1
    end
    self.pendingPower = math.max(0, pw.pending or 0)
    self.pendingSlots = math.max(0, aug.unallocated or 0)
    self.staged = {}
    return true
end

-- Decide the mode on open: LIVE if the bus loads real state, else local PREVIEW.
function PowerChoiceMenu:_initState()
    self.notice = nil
    self.live = self:_loadLive()
    if not self.live then
        self:_reset()
    end
end

-- ---- model ---------------------------------------------------------------

function PowerChoiceMenu:_grant(level)
    local kind, n = grantFor(level)
    if kind == "power" then
        self.pendingPower += n
    else
        self.pendingSlots += n
    end
end

function PowerChoiceMenu:_reset()
    if self.live then
        -- live: RESET = discard staged + resync from the server (NOT a destructive wipe).
        self.staged = {}
        self.notice = nil
        self:_loadLive()
        return
    end
    self.level = 1
    self.owned = {}
    self.pendingPower = 0
    self.pendingSlots = 0
    self.staged = {}
    self.log = {}
    -- L1 grants nothing; the first LEVEL UP (to L2) hands the first power pick.
end

function PowerChoiceMenu:_levelUp()
    if self.atMax or self.level >= MAX_LEVEL then
        return
    end
    -- must commit (clear) the current beat before advancing
    if self.pendingPower > 0 or self.pendingSlots > 0 then
        return
    end
    if self.live then
        -- claim the next real level. Admins can BANK a level first to walk the track without
        -- grinding XP; real players claim only what they've earned.
        if self.pendingLevels <= 0 then
            if isAdmin() then
                callBus("levelup.bank", { count = 1 })
            else
                self.notice = "Earn more XP to level up"
                self:_render()
                return
            end
        end
        local res = callBus("levelup.claim", { expectedLevel = self.level })
        self.notice = (res and res.ok == false) and ("Claim failed: " .. tostring(res.reason))
            or nil
        self:_loadLive()
        self:_render()
        return
    end
    self.level += 1
    self:_grant(self.level)
    self:_render()
end

-- click a row: stage a slot (committed power) OR stage/clear a pick (radio on a pick beat).
function PowerChoiceMenu:_onRow(id)
    self.notice = nil
    if self.owned[id] then
        -- committed power: stage a slot if the beat grants slots and it isn't maxed
        if self:_remainingSlots() > 0 and self:_effectiveSlots(id) < MAX_SLOTS then
            self.staged[#self.staged + 1] = { action = "slot", id = id }
            self:_render()
        end
    elseif self:_isStagedPick(id) then
        -- clicking the staged pick clears it (undo)
        for i = #self.staged, 1, -1 do
            if self.staged[i].action == "pick" and self.staged[i].id == id then
                table.remove(self.staged, i)
            end
        end
        self:_render()
    else
        -- attempt to stage this as the pick
        if self.pendingPower > 0 and pickLevelOf(id) <= self.level then
            if self:_remainingPicks() > 0 then
                self.staged[#self.staged + 1] = { action = "pick", id = id }
            elseif self.pendingPower == 1 then
                -- radio: a second choice replaces the first
                for i = #self.staged, 1, -1 do
                    if self.staged[i].action == "pick" then
                        table.remove(self.staged, i)
                    end
                end
                self.staged[#self.staged + 1] = { action = "pick", id = id }
            else
                return
            end
            self:_render()
        end
    end
end

function PowerChoiceMenu:_undo()
    if #self.staged == 0 then
        return
    end
    table.remove(self.staged)
    self:_render()
end

-- RESET button. Admin + live: a FULL wipe (powers/slots cleared, back to L1, origin kept) so you
-- can retest the climb. Otherwise: just discard staged / local-preview wipe (see _reset).
function PowerChoiceMenu:_resetRun()
    if self.live and isAdmin() then
        local res = callBus("levelup.resetRun", {})
        self.staged = {}
        self.notice = (res and res.ok == false) and ("Reset failed: " .. tostring(res.reason))
            or nil
        self:_loadLive()
        self:_render()
        return
    end
    self:_reset()
    self:_render()
end

function PowerChoiceMenu:_commit()
    if not self:_canCommit() then
        return
    end
    if self.live then
        -- send the beat to the server. Picks FIRST (so a freshly-picked power exists before any
        -- slot lands on it — and it auto-gets its inherent slot), then the empty slots.
        local failed
        for _, s in ipairs(self.staged) do
            if s.action == "pick" then
                local res = callBus("power.select", { powerId = s.id })
                if not (res and res.ok ~= false) then
                    failed = (res and res.reason) or "select_failed"
                end
            end
        end
        for _, s in ipairs(self.staged) do
            if s.action == "slot" then
                local res = callBus("augment.place", { powerId = s.id })
                if not (res and res.ok ~= false) then
                    failed = (res and res.reason) or "place_failed"
                end
            end
        end
        self.staged = {}
        self.notice = failed and ("Commit issue: " .. failed) or nil
        self:_loadLive() -- the server is authoritative; re-read owned/pending/slots
        self:_render()
        return
    end
    for _, s in ipairs(self.staged) do
        if s.action == "pick" then
            self.owned[s.id] = 1 -- a freshly-picked power comes with its inherent first slot
        else
            self.owned[s.id] = (self.owned[s.id] or 1) + 1
        end
        self.log[#self.log + 1] = { action = s.action, id = s.id, level = self.level }
    end
    self.staged = {}
    self.pendingPower = 0
    self.pendingSlots = 0
    self:_render()
end

-- ---- render --------------------------------------------------------------

function PowerChoiceMenu:_statusText()
    if self.notice then
        return self.notice, Color3.fromRGB(255, 180, 120)
    end
    if self.pendingPower > 0 then
        if self:_remainingPicks() > 0 then
            return "PICK A POWER  —  choose 1", Color3.fromRGB(150, 230, 150)
        end
        return "READY — press COMMIT  (or click another to change)", COMMIT_COLOR
    elseif self.pendingSlots > 0 then
        local rs = self:_remainingSlots()
        if rs > 0 and self:_canPlaceSlot() then
            return ("PLACE A SLOT  (%d of %d left) — click an owned power"):format(
                rs,
                self.pendingSlots
            ),
                Color3.fromRGB(140, 200, 255)
        end
        return "READY — press COMMIT", COMMIT_COLOR
    end
    return "Level Up for your next choice", Color3.fromRGB(200, 200, 210)
end

function PowerChoiceMenu:_fillColumn(holder, pool)
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    if not pool then
        return
    end
    local ownedSet = {}
    for id in pairs(self.owned) do
        ownedSet[id] = true
    end
    local rows = PowerSelection.menuRows(
        pool,
        powersCfg.powers,
        self.level,
        ownedSet,
        powersCfg.selection_levels
    )
    for i, r in ipairs(rows) do
        local def = powersCfg.powers[r.id] or {}
        local stagedPick = self:_isStagedPick(r.id)
        local stagedSlots = self:_stagedSlotsOn(r.id)
        local hasStaged = stagedPick or stagedSlots > 0
        -- a row is ACTIONABLE this beat if you can act on it now (pick it / slot it)
        local actionable = (
            r.state == "owned"
            and self:_remainingSlots() > 0
            and self:_effectiveSlots(r.id) < MAX_SLOTS
        )
            or (
                r.state == "available"
                and not stagedPick
                and self.pendingPower > 0
                and (self:_remainingPicks() > 0 or self.pendingPower == 1)
            )
        local wrap = Instance.new("TextButton")
        wrap.Name = "Row_" .. r.id
        wrap.LayoutOrder = i
        wrap.Size = UDim2.fromScale(0.99, 0.075)
        wrap.BackgroundTransparency = 1
        wrap.AutoButtonColor = false
        wrap.Text = ""
        wrap.Parent = holder
        wrap.Activated:Connect(function()
            self:_onRow(r.id)
        end)
        PowerSlotRow.create(wrap, {
            powerId = r.id,
            name = def.display_name or r.id,
            subtitle = "L" .. tostring(r.pickLevel) .. "    " .. (def.subtitle or ""),
            state = r.state,
            slotCount = self:_effectiveSlots(r.id),
            selected = stagedPick,
            size = UDim2.fromScale(1, 1),
        })
        -- glow: gold = staged (unsaved); green/blue = actionable this beat
        local glowColor
        if hasStaged then
            glowColor = STAGED_GLOW
        elseif actionable then
            glowColor = (r.state == "owned") and Color3.fromRGB(140, 200, 255)
                or Color3.fromRGB(150, 230, 150)
        end
        if glowColor then
            local glow = Instance.new("UIStroke")
            glow.Color = glowColor
            glow.Thickness = hasStaged and 2.5 or 2
            glow.Transparency = hasStaged and 0 or 0.15
            local bar = wrap:FindFirstChild("PowerRow") and wrap.PowerRow:FindFirstChild("Bar")
            if bar then
                glow.Parent = bar
            end
        end
    end
end

function PowerChoiceMenu:_refreshOrigin()
    local origin, def
    if self.live then
        origin = self.archetype -- locked to the player's real origin (no cycling)
        def = origin and archetypesCfg.archetypes and archetypesCfg.archetypes[origin]
    else
        origin = ORIGINS[self.originIndex]
        def = archetypesCfg.archetypes and archetypesCfg.archetypes[origin]
    end
    if self.originHeader then
        if self.live and not origin then
            self.originHeader.Text = "NO ORIGIN YET"
            self.originHeader.TextColor3 = Color3.fromRGB(200, 200, 210)
        else
            local name = (def and def.display_name or tostring(origin)):upper()
            self.originHeader.Text = self.live and name or ("‹ " .. name .. " ›")
            self.originHeader.TextColor3 = ORIGIN_COLOR[origin] or Color3.new(1, 1, 1)
        end
    end
    if self.originCol then
        self:_fillColumn(self.originCol, def and def.power_pool)
    end
end

local function setChipEnabled(btn, on)
    if not btn then
        return
    end
    btn.Active = on
    btn.AutoButtonColor = on
    btn.BackgroundTransparency = on and 0 or 0.6
    btn.TextTransparency = on and 0 or 0.45
end

function PowerChoiceMenu:_render()
    if self.naturalCol then
        self:_fillColumn(self.naturalCol, archetypesCfg.generic_pool)
    end
    self:_refreshOrigin()
    if self.statusLabel then
        local txt, col = self:_statusText()
        self.statusLabel.Text = txt
        self.statusLabel.TextColor3 = col
    end
    local outstanding = self.pendingPower > 0 or self.pendingSlots > 0
    if self.levelBtn then
        local atMax = self.atMax or self.level >= MAX_LEVEL
        self.levelBtn.Text = atMax and ("MAX (L" .. MAX_LEVEL .. ")")
            or ("LEVEL UP  ▶   (L" .. self.level .. ")")
        local canLevel = not atMax and not outstanding
        -- live + non-admin: can only level up what XP has actually earned
        if self.live and not isAdmin() then
            canLevel = canLevel and self.pendingLevels > 0
        end
        setChipEnabled(self.levelBtn, canLevel)
    end
    setChipEnabled(self.commitBtn, self:_canCommit())
    setChipEnabled(self.undoBtn, #self.staged > 0)
end

-- ---- build ---------------------------------------------------------------

local function makeColumnHolder(parent, xScale)
    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(0.46, 0.82)
    f.Position = UDim2.fromScale(xScale, 0.14)
    f.BackgroundTransparency = 1
    f.Parent = parent
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0.004, 0)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = f
    return f
end

local function chip(parent, text, size, pos, color, order)
    local b = Instance.new("TextButton")
    b.LayoutOrder = order or 0
    b.Size = size
    b.Position = pos
    b.AnchorPoint = Vector2.new(0.5, 0.5)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(20, 20, 28)
    b.Font = Enum.Font.GothamBold
    b.TextScaled = true
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.4, 0)
    c.Parent = b
    return b
end

function PowerChoiceMenu:Show(parent)
    local root = Instance.new("Frame")
    root.Name = "PowerChoiceMenu"
    root.Size = UDim2.fromScale(0.5, 0.92)
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.fromScale(0.5, 0.5)
    root.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    root.BorderSizePixel = 0
    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0.02, 0)
    rc.Parent = root
    local rs = Instance.new("UIStroke")
    rs.Color = Color3.fromRGB(70, 64, 96)
    rs.Thickness = 2
    rs.Parent = root
    self.frame = root

    local title = Instance.new("TextLabel")
    title.Size = UDim2.fromScale(0.6, 0.05)
    title.Position = UDim2.fromScale(0.2, 0.012)
    title.BackgroundTransparency = 1
    title.Text = "POWER CHOICE"
    title.TextColor3 = Color3.fromRGB(235, 230, 250)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = root

    -- status line (what to do this beat)
    local status = Instance.new("TextLabel")
    status.Size = UDim2.fromScale(0.8, 0.035)
    status.Position = UDim2.fromScale(0.5, 0.075)
    status.AnchorPoint = Vector2.new(0.5, 0)
    status.BackgroundTransparency = 1
    status.Text = ""
    status.TextScaled = true
    status.Font = Enum.Font.GothamMedium
    status.Parent = root
    self.statusLabel = status

    -- close
    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(34, 34)
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -12, 0, 12)
    close.BackgroundColor3 = Color3.fromRGB(120, 50, 60)
    close.Text = "✕"
    close.TextColor3 = Color3.fromRGB(255, 235, 235)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 18
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(1, 0)
    cc.Parent = close
    close.Parent = root
    close.Activated:Connect(function()
        if _G.MenuManager then
            _G.MenuManager:CloseCurrentPanel()
        end
    end)

    -- headers
    local nHeader = Instance.new("TextLabel")
    nHeader.Size = UDim2.fromScale(0.46, 0.045)
    nHeader.Position = UDim2.fromScale(0.02, 0.105)
    nHeader.BackgroundTransparency = 1
    nHeader.Text = "NATURAL"
    nHeader.TextColor3 = NATURAL_COLOR
    nHeader.TextScaled = true
    nHeader.Font = Enum.Font.GothamBold
    nHeader.Parent = root

    local oHeader = Instance.new("TextButton")
    oHeader.Size = UDim2.fromScale(0.46, 0.045)
    oHeader.Position = UDim2.fromScale(0.52, 0.103)
    oHeader.BackgroundColor3 = Color3.fromRGB(46, 43, 60)
    oHeader.BackgroundTransparency = 0.35
    oHeader.AutoButtonColor = true
    oHeader.Text = ""
    oHeader.TextScaled = true
    oHeader.Font = Enum.Font.GothamBold
    oHeader.Parent = root
    local ohc = Instance.new("UICorner")
    ohc.CornerRadius = UDim.new(0.35, 0)
    ohc.Parent = oHeader
    local ohs = Instance.new("UIStroke")
    ohs.Color = Color3.fromRGB(120, 110, 150)
    ohs.Thickness = 1.5
    ohs.Parent = oHeader
    self.originHeader = oHeader
    oHeader.Activated:Connect(function()
        if self.live then
            return -- origin is locked to your real archetype in live mode
        end
        self.originIndex = (self.originIndex % #ORIGINS) + 1
        self:_reset() -- a new origin = a fresh run from L1
        self:_render()
    end)

    -- columns + divider
    self.naturalCol = makeColumnHolder(root, 0.02)
    self.originCol = makeColumnHolder(root, 0.52)
    local div = Instance.new("Frame")
    div.Size = UDim2.fromScale(0.0025, 0.78)
    div.Position = UDim2.fromScale(0.5, 0.55)
    div.AnchorPoint = Vector2.new(0.5, 0.5)
    div.BackgroundColor3 = Color3.fromRGB(120, 110, 80)
    div.BorderSizePixel = 0
    div.Parent = root

    -- bottom controls: ↶ UNDO · ✓ COMMIT · LEVEL UP ▶ · ↺ RESET
    self.undoBtn = chip(
        root,
        "↶ UNDO",
        UDim2.fromScale(0.17, 0.05),
        UDim2.fromScale(0.12, 0.965),
        UNDO_COLOR,
        1
    )
    self.undoBtn.Activated:Connect(function()
        self:_undo()
    end)

    self.commitBtn = chip(
        root,
        "✓ COMMIT",
        UDim2.fromScale(0.24, 0.055),
        UDim2.fromScale(0.36, 0.965),
        COMMIT_COLOR,
        2
    )
    self.commitBtn.Activated:Connect(function()
        self:_commit()
    end)

    self.levelBtn = chip(
        root,
        "LEVEL UP  ▶",
        UDim2.fromScale(0.24, 0.055),
        UDim2.fromScale(0.64, 0.965),
        LEVEL_COLOR,
        3
    )
    self.levelBtn.Activated:Connect(function()
        self:_levelUp()
    end)

    local resetBtn = chip(
        root,
        "↺ RESET",
        UDim2.fromScale(0.15, 0.05),
        UDim2.fromScale(0.88, 0.965),
        RESET_COLOR,
        4
    )
    resetBtn.Activated:Connect(function()
        self:_resetRun()
    end)

    -- The menu owns the level-up claim UX while open — suppress the old LevelUpController reveal
    -- modal so they don't fight over LevelUp_Claimed.
    _G.PowerChoiceMenuOpen = true
    self:_initState()
    self:_render()
    root.Parent = parent
end

function PowerChoiceMenu:Hide()
    _G.PowerChoiceMenuOpen = false
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
    self.naturalCol = nil
    self.originCol = nil
    self.originHeader = nil
    self.statusLabel = nil
    self.levelBtn = nil
    self.commitBtn = nil
    self.undoBtn = nil
end

function PowerChoiceMenu:GetFrame()
    return self.frame
end

return PowerChoiceMenu
