--[[
    Potions — the "brew charge" consumable system (pure math: src/Shared/Game/BrewMeter.lua).

    ONE METER PER AXIS (Jason). A meter is a normalized charge [0,1] shown as a draining pie-icon;
    its magnitude tapers with the charge (magnitude = charge × cap) and a sip closes a fraction of
    the gap to full (diminishing → asymptotes to the cap; 1000 potions can't 1000× anything, and
    front-loading is wasted). When a meter drains to empty the icon goes away.

    Each meter feeds a BuffStack axis (configs/buffs.lua) via a player attribute — its cap stays
    UNDER that axis's hard backstop (potions are one contributor, not the whole axis). Debuff
    meters (target = "enemy") apply the same charge math to a thrown target instead of the drinker.

    Every number is a dev knob. NOTE: `icon` values are placeholders — the pie-icon renderer reuses
    the hotbar radial-cooldown clock + the power-icon registry; final art ids resolve there.
]]

return {
    -- tick the drain this often (server heartbeat coalesce); UI interpolates the pie between ticks
    tick_seconds = 1,

    meters = {
        -- buff_axis = configs/buffs.lua axis (the hard cap backstop); buff_attr = the player
        -- attribute the PotionService writes ("<attr>" + "<attr>Until"); cap stays under the axis cap.
        damage = {
            display_name = "Berserk",
            cap = 1.5, -- +150% pet damage at full (axis backstop: pet_damage 5.0)
            drain_seconds = 60,
            full_threshold = 0.98,
            buff_axis = "pet_damage",
            color = { 220, 70, 70 }, -- damage = red
            buff_attr = "PetDamageBuff",
            icon = "⚔️",
            target = "player",
        },
        luck = {
            display_name = "Fortune",
            cap = 1.0, -- +100% luck at full (axis backstop: luck 3.0 — luck is precious, keep it low)
            drain_seconds = 45,
            full_threshold = 0.98,
            buff_axis = "luck",
            color = { 70, 200, 110 }, -- luck = green
            buff_attr = "LuckBuff",
            icon = "🍀",
            target = "player",
        },
        speed = {
            display_name = "Swiftness",
            cap = 0.5, -- +50% move speed at full (axis backstop: move_speed 1.0)
            drain_seconds = 30,
            full_threshold = 0.98,
            buff_axis = "move_speed",
            color = { 80, 160, 240 }, -- speed = blue
            buff_attr = "MoveSpeedBuff",
            icon = "💨",
            target = "player",
        },
        -- DEBUFF meter: same math, but the charge lives on the THROWN enemy (vulnerability up).
        weaken = {
            display_name = "Weakness",
            cap = 0.5, -- enemies take +50% damage at full
            drain_seconds = 20,
            full_threshold = 0.98,
            buff_attr = "VulnerableMult",
            color = { 200, 50, 90 }, -- weaken = crimson
            icon = "🩸",
            target = "enemy",
        },
    },

    -- Consumables that feed a meter. sip_fraction = how much of the gap-to-full ONE drink closes.
    -- All potions are tradeable (the trade `potions` bucket); throw = applied to a target enemy.
    potions = {
        berserk_brew = {
            display_name = "Berserk Brew",
            description = "Pet damage surges, then fades. Sip to top it up.",
            meter = "damage",
            sip_fraction = 0.5,
            tradeable = true,
            icon = "⚔️",
        },
        fortune_flask = {
            display_name = "Fortune Flask",
            description = "Luck climbs toward its peak; precious, so it drains fast.",
            meter = "luck",
            sip_fraction = 0.4,
            tradeable = true,
            icon = "🍀",
        },
        swift_tonic = {
            display_name = "Swift Tonic",
            description = "Move faster for a short burst.",
            meter = "speed",
            sip_fraction = 0.6,
            tradeable = true,
            icon = "💨",
        },
        weakening_vial = {
            display_name = "Weakening Vial",
            description = "Throw it — the target takes more damage until it wears off.",
            meter = "weaken",
            sip_fraction = 0.5,
            tradeable = true,
            throw = true,
            icon = "🩸",
        },
    },
}
