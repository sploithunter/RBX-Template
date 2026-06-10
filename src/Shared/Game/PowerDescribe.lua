--[[
    PowerDescribe — derive a human description for ANY power from its config record.

    57 powers and counting: hand-written blurbs drift the moment a magnitude is tuned, so the
    DEFAULT description is BUILT from the live numbers (effect_kinds family/magnitude/duration +
    the def's target/focus/cooldown). A hand-written `description` on the power def overrides
    the summary sentence; the stat lines always come from the numbers.

    describe(powersCfg, powerId) -> {
        summary = "Hardens your squad: +80 Defense.",
        lines   = { "Lasts 12s", "Focus 16", "Recharge 24s" },   -- only the ones that apply
    }
    Pure — no services, no Instances (headless-tested).
]]

local PowerDescribe = {}

local TARGET_TEXT = {
    single_pet = "one pet",
    team_aoe = "your squad",
    friendly = "an ally's squad",
    player_field = "a field around you",
    single = "one enemy",
    single_spread = "one enemy, spreading to others",
    targeted_aoe = "enemies in the area",
    eruption = "enemies around the target",
}

local function pct(fraction)
    return ("%d%%"):format(math.floor(fraction * 100 + 0.5))
end

-- multiplier-style magnitudes (1.5 = +50%) vs fraction-style (+0.5 = +50%)
local function multPct(magnitude)
    return pct((tonumber(magnitude) or 1) - 1)
end

local function span(seconds)
    seconds = tonumber(seconds) or 0
    if seconds >= 60 and seconds % 60 == 0 then
        return ("%dm"):format(seconds / 60)
    end
    return ("%ds"):format(seconds)
end

-- family -> summary builder(kind, targetText). Anything unlisted falls back to the subtitle.
local FAMILY_TEXT = {
    absorb = function(kind, target)
        if kind.evade then
            return ("Lets %s dodge — turning aside up to %d damage."):format(
                target,
                kind.magnitude
            )
        end
        local extra = kind.evade_heal and (" Heals %d on each evade."):format(kind.evade_heal) or ""
        return ("Shields %s — soaks %d damage before it hurts."):format(target, kind.magnitude)
            .. extra
    end,
    defense_buff = function(kind, target)
        return ("Hardens %s: +%d Defense."):format(target, kind.magnitude)
    end,
    armor = function(kind, target)
        return ("Armors %s: %s less damage taken."):format(target, pct(kind.magnitude))
    end,
    buff = function(kind, target)
        return ("%s deals +%s damage."):format(target, multPct(kind.magnitude))
    end,
    crit = function(kind, target)
        return ("+%s crit chance for %s."):format(pct(kind.magnitude), target)
    end,
    root = function(_, target)
        return ("Holds %s in place."):format(target)
    end,
    root_guard = function(kind, target)
        return ("Roots %s AND hardens your squad (+%d Defense)."):format(target, kind.magnitude)
    end,
    vulnerable = function(kind, target)
        local s = ("%s takes +%s damage."):format(target, multPct(kind.magnitude))
        if kind.dot then
            s ..= (" Burns ~%d/s."):format(kind.dot.per_tick)
        end
        if kind.frozen_bonus then
            s ..= (" Frozen targets take ×%.1f more."):format(kind.frozen_bonus)
        end
        return s
    end,
    coin_yield = function(kind)
        return ("+%s coins from mining."):format(pct(kind.magnitude))
    end,
    luck = function(kind)
        return ("+%s luck — rarer pets from eggs."):format(pct(kind.magnitude))
    end,
    move_speed = function(kind)
        return ("+%s move speed for you and your pets."):format(pct(kind.magnitude))
    end,
    recharge = function(kind)
        return ("Your powers recharge %s faster."):format(pct(kind.magnitude))
    end,
    xp = function(kind)
        return ("+%s XP from everything."):format(pct(kind.magnitude))
    end,
    magnet = function(kind)
        return ("Pulls in drops from %d studs further away."):format(kind.magnitude)
    end,
    heal = function(kind, target)
        local amount = kind.magnitude <= 1 and pct(kind.magnitude) .. " endurance"
            or ("%d endurance"):format(kind.magnitude)
        if (tonumber(kind.duration) or 0) > 0 then
            return ("Restores %s to %s over time."):format(amount, target)
        end
        return ("Instantly restores %s to %s."):format(amount, target)
    end,
    heal_blind = function(kind, target)
        return ("Heals your squad %d AND blinds %s (+%s damage taken)."):format(
            kind.magnitude,
            target,
            multPct(kind.vuln or 1.5)
        )
    end,
    team_cleave = function(kind)
        return ("Your squad's hits cleave: %s of each hit splashes nearby enemies."):format(
            pct(kind.magnitude)
        )
    end,
    revive = function()
        return "Instantly revives a downed pet, no waiting."
    end,
    recall = function()
        return "Teleports you back to your saved spot."
    end,
    world_travel = function()
        return "Opens travel to another realm hub."
    end,
    summon = function(kind)
        return ("Summons a mighty %s to fight beside your squad."):format(
            tostring(kind.guardian or "guardian")
        )
    end,
    taunt = function(_, target)
        return ("Forces %s to attack the taunting pet."):format(target)
    end,
    rage = function(kind)
        return ("The lower a pet's endurance, the harder it hits (up to +%s)."):format(
            pct(kind.magnitude)
        )
    end,
    fear = function(_, target)
        return ("Sends %s fleeing in terror."):format(target)
    end,
}

function PowerDescribe.describe(powersCfg, powerId)
    local def = (powersCfg.powers or {})[powerId]
    if not def then
        return nil
    end
    local kind = (powersCfg.effect_kinds or {})[def.effect] or {}
    local target = TARGET_TEXT[def.target] or "your squad"

    local summary = def.description -- hand-written override wins
    if not summary then
        local builder = FAMILY_TEXT[kind.family]
        summary = builder and builder(kind, target)
            or (def.subtitle and def.subtitle .. "." or "A mysterious power.")
    end

    local lines = {}
    local passive = kind.passive == true or kind.toggle == true
    if passive then
        lines[#lines + 1] = "Always on while owned"
    else
        if (tonumber(kind.duration) or 0) > 0 then
            lines[#lines + 1] = "Lasts " .. span(kind.duration)
        end
        if (tonumber(def.focus_cost) or 0) > 0 then
            lines[#lines + 1] = ("Focus %d"):format(def.focus_cost)
        end
        if (tonumber(def.cooldown_seconds) or 0) > 0 then
            lines[#lines + 1] = "Recharge " .. span(def.cooldown_seconds)
        end
    end
    return { summary = summary, lines = lines }
end

return PowerDescribe
