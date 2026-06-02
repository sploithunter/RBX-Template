--[[
    CombatAuraController — reactive combat VFX for Halo & Horns.

    PowerService sets combat attributes server-side; this client controller watches them and
    attaches the matching CombatFX so powers READ on the battlefield, not just in the numbers:

      pet  CombatShield > 0      -> element shield bubble + armor reskin (stones out)  [absorb]
      pet  DefenseBuffUntil      -> defensive buff aura for the remaining duration       [defense_buff]
      pet  HealFxUntil           -> heal aura for the remaining duration                 [heal]
      player PetDamageBuffUntil  -> damage buff aura on every owned pet                   [buff]
      enemy VulnerableUntil      -> debuff aura while vulnerable                          [vulnerable]
      enemy RootedUntil          -> debuff aura while rooted                              [root]

    Each pet's element comes from CombatOrigin (the same resolution the attack VFX uses): element
    from PetType, unified to the owner's archetype when origin.unify_to_player is set. The shield's
    armor reskin is element-themed via origin.element_reskin. Enemy debuffs use the caster's
    element (player archetype) so the wither reads in the player's theme.

    The *Until attributes are absolute os.time() stamps set once and expiring silently, so each is
    attached with duration = until - now and the effect self-expires; a re-cast (attribute change)
    restarts it. CombatShield is a depleting magnitude: the bubble persists (duration 0) while it's
    above zero and pops when it reaches zero.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Shared.Effects.CombatFX)
local CombatOrigin = require(ReplicatedStorage.Shared.Game.CombatOrigin)
local PowerIcons = require(ReplicatedStorage.Configs:WaitForChild("power_icons"))

local CombatAuraController = {}

local localPlayer = Players.LocalPlayer
local started = false

-- per Instance -> { slot -> handle }; per Instance -> { connections } for cleanup.
local handles = setmetatable({}, { __mode = "k" })
local conns = setmetatable({}, { __mode = "k" })
local armorIcons = setmetatable({}, { __mode = "k" }) -- pet -> BillboardGui (shield icon while armored)

-- A gold shield badge that floats over an armored pet, so "this pet has armor" reads at a glance.
local function showArmorIcon(pet)
    if armorIcons[pet] and armorIcons[pet].Parent then
        return
    end
    local pp = pet.PrimaryPart or pet:FindFirstChildWhichIsA("BasePart")
    if not pp then
        return
    end
    local up = 4
    local okE, ext = pcall(function()
        return pet:GetExtentsSize()
    end)
    if okE and ext then
        up = ext.Y * 0.5 + 2
    end
    local bb = Instance.new("BillboardGui")
    bb.Name = "ArmorIcon"
    bb.AlwaysOnTop = true
    bb.Size = UDim2.fromOffset(34, 34)
    bb.StudsOffset = Vector3.new(0, up, 0)
    bb.Adornee = pp
    -- the real shield art (same asset the squad card uses), not a platform emoji
    local img = Instance.new("ImageLabel")
    img.BackgroundTransparency = 1
    img.Size = UDim2.fromScale(1, 1)
    img.Image = (PowerIcons.status and PowerIcons.status.shield) or ""
    img.ImageColor3 = Color3.fromRGB(235, 200, 70) -- gold tint
    img.Parent = bb
    bb.Parent = pp
    armorIcons[pet] = bb
end

local function hideArmorIcon(pet)
    local bb = armorIcons[pet]
    if bb then
        armorIcons[pet] = nil
        pcall(function()
            bb:Destroy()
        end)
    end
end

local originCfg = {}
local reskinDefs = {} -- config.reskins: reskin key ("stone"/"lava"/...) -> { material, color }

local function elementForPet(pet)
    local petEl = originCfg.pettype_element and originCfg.pettype_element[pet:GetAttribute("PetType")]
    local archetype = localPlayer and localPlayer:GetAttribute("Archetype")
    return CombatOrigin.resolve(petEl, archetype, originCfg)
end

-- The element a player-applied debuff reads in (the caster's theme): archetype element, else default.
local function casterElement()
    local archetype = localPlayer and localPlayer:GetAttribute("Archetype")
    return CombatOrigin.resolve(nil, archetype, originCfg)
end

local function stopSlot(entity, slot)
    local t = handles[entity]
    local h = t and t[slot]
    if h then
        t[slot] = nil
        pcall(function()
            if h.stop then
                h.stop()
            end
        end)
    end
end

local function setSlot(entity, slot, spec)
    stopSlot(entity, slot)
    local ok, handle = pcall(CombatFX.attach, entity, spec)
    if ok and handle then
        handles[entity] = handles[entity] or {}
        handles[entity][slot] = handle
    end
end

-- Seconds remaining on an absolute os.time() "until" attribute (0 if absent/expired).
local function remaining(entity, attr)
    local untilT = entity:GetAttribute(attr) or 0
    return untilT - os.time()
end

-- ===== Pets =====
-- A pet is "armored" while EITHER defensive power family is active:
--   absorb (CombatShield > 0, e.g. Stone Skin / Ice Armor / Dune Shield / Ember Ward) — depletes
--     as it soaks hits, so the look persists (duration 0) until it hits zero, OR
--   defense_buff (DefenseBuffUntil in the future, e.g. Bulwark) — a timed team hardening.
-- Either one shows the element shield bubble + armor reskin. The look attaches once on the
-- bare->armored transition and clears on armored->bare (so CombatShield ticking down as it
-- absorbs doesn't re-pop the bubble every hit).
local function isArmored(pet)
    return (pet:GetAttribute("CombatShield") or 0) > 0 or (pet:GetAttribute("DefenseBuffUntil") or 0) > os.time()
end

local function refreshArmor(pet)
    local active = handles[pet] and handles[pet].shield
    if isArmored(pet) then
        if not active then
            -- element -> reskin KEY (origin.element_reskin) -> reskin {material,color} (config.reskins).
            local element = elementForPet(pet)
            local reskinKey = originCfg.element_reskin and originCfg.element_reskin[element]
            local reskin = reskinKey and reskinDefs[reskinKey]
            setSlot(pet, "shield", { category = "shield", element = element, reskin = reskin, duration = 0 })
        end
        showArmorIcon(pet)
    elseif active then
        stopSlot(pet, "shield")
        hideArmorIcon(pet)
    else
        hideArmorIcon(pet)
    end
end

local function refreshTimedAura(pet, attr, slot, category, element)
    local secs = remaining(pet, attr)
    if secs > 0.05 then
        setSlot(pet, slot, { category = category, element = element or elementForPet(pet), duration = secs })
    else
        stopSlot(pet, slot)
    end
end

local function hookPet(pet)
    if conns[pet] or not pet:IsA("Model") then
        return
    end
    local list = {}
    conns[pet] = list
    -- both defensive families -> armor look
    list[#list + 1] = pet:GetAttributeChangedSignal("CombatShield"):Connect(function()
        refreshArmor(pet)
    end)
    list[#list + 1] = pet:GetAttributeChangedSignal("DefenseBuffUntil"):Connect(function()
        refreshArmor(pet)
        -- defense_buff is time-gated and expires silently: re-check when it lapses to drop the armor.
        local secs = remaining(pet, "DefenseBuffUntil")
        if secs > 0 then
            task.delay(secs + 0.1, function()
                refreshArmor(pet)
            end)
        end
    end)
    list[#list + 1] = pet:GetAttributeChangedSignal("HealFxUntil"):Connect(function()
        refreshTimedAura(pet, "HealFxUntil", "heal", "heal")
    end)
    -- catch any already-active state at hook time
    refreshArmor(pet)
    refreshTimedAura(pet, "HealFxUntil", "heal", "heal")
end

local function unhook(entity)
    local list = conns[entity]
    if list then
        for _, c in ipairs(list) do
            c:Disconnect()
        end
        conns[entity] = nil
    end
    local t = handles[entity]
    if t then
        for slot in pairs(t) do
            stopSlot(entity, slot)
        end
        handles[entity] = nil
    end
    hideArmorIcon(entity)
end

-- Player-level damage buff -> a buff aura on every owned pet for the remaining duration.
local function refreshPlayerDamageBuff(petsFolder)
    local secs = remaining(localPlayer, "PetDamageBuffUntil")
    if not petsFolder then
        return
    end
    for _, pet in ipairs(petsFolder:GetChildren()) do
        if pet:IsA("Model") then
            if secs > 0.05 then
                setSlot(pet, "dmgbuff", { category = "buff", element = elementForPet(pet), duration = secs })
            else
                stopSlot(pet, "dmgbuff")
            end
        end
    end
end

-- ===== Enemies =====
local function refreshEnemyDebuff(enemy)
    -- show a debuff aura while either vulnerable or rooted; duration = the longer remaining.
    local secs = math.max(remaining(enemy, "VulnerableUntil"), remaining(enemy, "RootedUntil"))
    if secs > 0.05 then
        setSlot(enemy, "debuff", { category = "debuff", element = casterElement(), duration = secs })
    else
        stopSlot(enemy, "debuff")
    end
end

local function hookEnemy(enemy)
    if conns[enemy] or not enemy:IsA("Model") then
        return
    end
    local list = {}
    conns[enemy] = list
    list[#list + 1] = enemy:GetAttributeChangedSignal("VulnerableUntil"):Connect(function()
        refreshEnemyDebuff(enemy)
    end)
    list[#list + 1] = enemy:GetAttributeChangedSignal("RootedUntil"):Connect(function()
        refreshEnemyDebuff(enemy)
    end)
    refreshEnemyDebuff(enemy)
end

-- Watch a folder's children (current + future), hooking each and unhooking on removal.
local function watchFolder(folder, hook)
    for _, child in ipairs(folder:GetChildren()) do
        hook(child)
    end
    folder.ChildAdded:Connect(hook)
    folder.ChildRemoved:Connect(unhook)
end

-- Non-blocking: run cb(child) for a named child of `parent` now if present, else once it appears.
local function whenChild(parent, name, cb)
    local existing = parent:FindFirstChild(name)
    if existing then
        cb(existing)
        return
    end
    local conn
    conn = parent.ChildAdded:Connect(function(child)
        if child.Name == name then
            conn:Disconnect()
            cb(child)
        end
    end)
end

function CombatAuraController.start()
    if started then
        return
    end
    started = true

    local cfg = require(ReplicatedStorage.Configs:WaitForChild("combat_fx"))
    originCfg = cfg.origin or {}
    reskinDefs = cfg.reskins or {}

    -- Pets: workspace.PlayerPets[<localPlayer>] (each level appears when pets first spawn).
    whenChild(Workspace, "PlayerPets", function(root)
        whenChild(root, localPlayer.Name, function(mine)
            watchFolder(mine, hookPet)
            localPlayer:GetAttributeChangedSignal("PetDamageBuffUntil"):Connect(function()
                refreshPlayerDamageBuff(mine)
            end)
            refreshPlayerDamageBuff(mine)
        end)
    end)

    -- Enemies: workspace.Game.Enemies.
    whenChild(Workspace, "Game", function(g)
        whenChild(g, "Enemies", function(enemies)
            watchFolder(enemies, hookEnemy)
        end)
    end)
end

return CombatAuraController
