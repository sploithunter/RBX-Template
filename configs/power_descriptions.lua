--[[
    Power descriptions — short blurbs for the hover tooltip (HotbarBar). Keyed by power id.

    One line each, "what it does" (from docs/PET_REALM_ICONS_AND_POWERS.md). The tooltip pairs this
    with the power's display_name (configs/powers.lua) + element. Targeting (single vs AoE) is the ring,
    so the text says the EFFECT; "squad"/"enemies" hints the target. Keep them short.
]]

return {
    -- Geomancer (earth) — tank / shields
    stone_skin = "Hardens the squad's skin: +Defense for 12s.",
    bulwark = "Squad bulwark: big +Defense for 15s.",
    mountains_strength = "+50% pet damage to the squad for 8s.",
    aegis = "Absorb shield on one selected pet (soaks 40) for 12s.",
    ironclad = "+80 Defense on one selected pet for 12s.",
    sunder = "Armor break: enemies take more damage.",
    bastion = "Signature: raises a defensive bastion over the squad.",
    seismic_hold = "Signature: roots enemies in place.",
    living_mountain = "Signature: a towering stone ward for the squad.",
    gaia_colossus = "Capstone: summons a stone colossus guardian.",

    -- Sandwalker (desert) — heal / evasion / debuff
    mirage_step = "Evasion: 30 dodge-absorb for 8s.",
    sandstorm = "Blinds enemies and makes them take +50% damage, 6s.",
    dune_shield = "Squad absorb shield (soaks 40) for 12s.",
    expose = "Exposes a target: reveal + accuracy/crit boost vs it.",
    cripple = "Cripples a target: slow + weaken.",
    oasis = "Signature: heals the squad over time.",
    mirage_veil = "Signature: veils the squad in protective mirage.",
    simoom = "Signature: a healing desert wind over the team.",
    genie_dunes = "Capstone: summons a djinn that revives + heals.",

    -- Cryomancer (ice) — control
    frost_bind = "Roots enemies in ice for 5s.",
    ice_armor = "Ice plating: +Defense to the squad for 12s.",
    blizzard = "Slows/roots enemies in an area for 6s.",
    disarm = "Disarms a target: reduces its attack.",
    focus_fire = "Designates a priority target for the squad.",
    permafrost = "Signature: long-hold freeze on enemies.",
    shatter = "Signature: a shattering ice burst.",
    absolute_zero = "Signature: deep-freeze hold on enemies.",
    eternal_winter = "Capstone: a field of eternal winter.",

    -- Pyromancer (lava) — damage / DoT
    mark_of_flame = "Burning mark: DoT, target takes +50% damage, 6s.",
    ember_ward = "Squad absorb shield (soaks 40) for 12s.",
    eruption = "Erupts for heavy AoE damage to enemies.",
    strike = "A basic fire strike on one enemy.",
    critical_strike = "+25% crit chance to the squad (combat & mining) for 12s.",
    wildfire = "Signature: a spreading vulnerability between enemies.",
    firestorm = "Signature: a team-AoE fire cleave.",
    cataclysm = "Capstone: a squad-scaled meteor burst.",
    inferno_brand = "Signature: a ramping burning brand.",

    -- Generic (white) — farming / luck / utility, any archetype
    prospector = "+coin yield for a duration.",
    windfall = "A burst of bonus coins / doubled pickups.",
    fortune = "+luck: better egg-hatch odds for a while.",
    huge_fortune = "Huge luck spike: big egg-hatch odds boost.",
    swift = "Toggle: +move speed for you and your pets.",
    hasten = "Toggle: powers recharge faster.",
    revive = "Instantly re-summons a downed pet, ignoring the clock.",
    recall = "Teleports you to your saved / last-egg spot.",
    world_travel = "Teleports you to a world / zone hub.",
    xp_surge = "+XP gain for a duration.",
    magnet = "Widens the radius that auto-collects coins/ore.",
}
