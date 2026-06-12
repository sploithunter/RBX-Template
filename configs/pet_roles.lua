--[[
    Pet roles (archetypes) — Halo & Horns [PROTOTYPE].

    The City-of-Heroes-style squad card shows a small archetype chip on the left so you
    can read a pet's combat ROLE at a glance (tank / melee / ranged / support / control).

    Resolution order (SquadHud): the pet's `PetRole` attribute (per-pet override) ->
    `by_type[PetType]` -> `default`. Until real role art is uploaded, each role renders a
    coloured letter glyph; drop an `icon` asset id on a role to swap the glyph for art.

    Colours are {r, g, b} (0-255) so this stays plain data; the client builds the Color3.
]]

return {
    default = "melee",

    -- PetType -> role id. Extend as pets are designed; a pet can also override with a
    -- `PetRole` attribute on its model.
    by_type = {
        bear = "tank",
        -- Jason: "in real life a polar bear has no predators other than people and it
        -- actually hunts humans — top tier tough and scary." A HIGH-DAMAGE tank: the
        -- tank role brings the toughness + taunt; a per-pet aptitude override in
        -- pets.lua (mining/combat_mult 1.0) overcomes the tank damage debuff.
        polarbear = "tank",
        doggy = "melee",
        dog = "melee",
        bunny = "support", -- Grass buffer (LUCK — lucky rabbit/clover) — see support_auras
        cat = "ranged",
        kitty = "ranged", -- the actual pet id ("cat" above was the intended mapping)
        dragon = "ranged", -- Jason: it flies and breathes fire — the rare early ranged chase
        bird = "ranged",
        colorado = "ranged",
        colorado_creator = "ranged", -- the apex is a BLASTER like its species twin (the
        -- two-species split missed this map and it fell to default=melee — Jason caught it)
        -- One BUFFER (support archetype) per zone — trades attack for a team aura. Their
        -- specific aura flavour lives in support_auras below.
        penguin = "support", -- Ice buffer (defense)
        emberimp = "support", -- Lava buffer (offense)
        meerkat = "support", -- Desert buffer (yield)
    },

    -- Per-zone BUFFER auras (City-of-Heroes support). Resolved by SupportAura.forPet
    -- (PetType key; a model `SupportAura` attribute can override later) and applied by
    -- EnemyService:_supportPass every `interval` seconds while the buffer is deployed +
    -- alive. The buff is short-lived (`duration`s) and refreshed each interval, so it
    -- fades a beat after the buffer is recalled/downed. These run on a SEPARATE channel
    -- from player Powers (Feature 14), so an aura STACKS with an activated power buff
    -- instead of clobbering it. Every number is a dev knob.
    --   heal     — mend the most-hurt non-downed ally; `fraction` of its pool (or flat `amount`).
    --   defense  — TeamDefenseBuff on every ally (added on the armor curve in _hitPet); `amount`.
    --   offense  — PetTeamDamageBuff on the owner; ×`mult` to mining AND combat damage (_mine).
    --   yield    — CoinYieldBuff on the owner; ×`mult` to mined-coin payout (BreakableSpawner).
    --   luck     — HatchLuckBuff on the owner; adds (mult-1) to hatch luck while deployed
    --              (EggService folds it into luckBoost — boosts rare species AND variants).
    --   buff     — GENERIC (Jason): { kind="buff", attr="<Attr>", mult, target="player"|
    --              "pets"|"both", interval, duration }. Player target stacks on the bar
    --              (xN); pets target badges each ally. The attr needs a CONSUMER (BuffStack
    --              axis / EggService / movement) — that's the only per-buff code.
    support_auras = {
        -- Grass: LUCK (Jason: heal was off-theme — lucky rabbit's foot + clover fields).
        -- durations sit WELL above intervals so the continuously-refreshed buffs never
        -- gap between stamps (a 3s window on a 2s tick flickered at the boundary)
        -- BASES REBASED for variant scaling (Jason: "rainbows should hit 25% — adjust
        -- the base accordingly... give people a reason to roll until they get rainbow
        -- bunnies"): rainbow (x1.5) lands exactly on the OLD value, so basic +16.7%,
        -- golden +20.8%, rainbow +25% (and defense ~53/67/80, heal 20%/25%/30%).
        bunny = { kind = "luck", interval = 2.0, mult = 1.1667, duration = 6 },
        penguin = { kind = "defense", interval = 2.0, amount = 53.3, duration = 6 }, -- Ice
        emberimp = { kind = "offense", interval = 2.0, mult = 1.1667, duration = 6 }, -- Lava
        meerkat = { kind = "yield", interval = 2.0, mult = 1.1667, duration = 6 }, -- Desert
        -- Bear: RAGE — an inherent power the pet casts on ITSELF (Jason: per-SPECIES
        -- assignment like the zone buffers, NOT a tank-role trait — "I don't want all
        -- tanks to have rage"). The starter tank gets angry as it soaks: at or below
        -- half health (enrage_below, endurance fraction) it pulses a self damage buff.
        -- mult 1.5 = +50% basic; the variant multipliers scale the fraction (golden
        -- +62.5%, rainbow +75%), so a raging bear claws back the tank role's 0.6
        -- haircut exactly while it's doing its job (0.6 × 1.5 = 0.9; rainbow 1.05).
        bear = { kind = "rage", enrage_below = 0.5, mult = 1.5, interval = 2.0, duration = 6 },
        -- Colorado (meet-egg / wild): TWO buffs, not all — "all" was really meant for
        -- creator testing (Jason). Heal + luck: the creator's gift is lucky and kind,
        -- and neither duplicates a zone buffer's whole identity.
        colorado = {
            { kind = "heal", interval = 1.5, fraction = 0.2 },
            { kind = "luck", interval = 2.0, mult = 1.1667, duration = 6 },
        },
        -- The colorado_creator SPECIES (the apex — different pet, same model): every
        -- buffer at once — the creator's testing/scaling tool.
        -- (the apex is a rainbow record, so x1.5 puts it at the old full values)
        colorado_creator = {
            { kind = "heal", interval = 1.5, fraction = 0.2 },
            { kind = "defense", interval = 2.0, amount = 53.3, duration = 6 },
            { kind = "offense", interval = 2.0, mult = 1.1667, duration = 6 },
            { kind = "yield", interval = 2.0, mult = 1.1667, duration = 6 },
            { kind = "luck", interval = 2.0, mult = 1.1667, duration = 6 },
        },
    },

    -- VARIANT EFFECT MULTIPLIERS (Jason: "would it make sense for a variant pet to be
    -- better? ...they give people a reason to roll"): scales aura/effect MAGNITUDE
    -- only — never duration or recharge (potency is containable, recharge compounds).
    -- One global knob; PowerModel P7 (pet-cast parity) reuses this same table.
    variant_effect_multipliers = {
        basic = 1.0,
        golden = 1.25,
        rainbow = 1.5,
    },

    -- Role definitions. glyph = placeholder letter (until art exists via `icon`).
    -- attack_range = how far the pet can deal damage (server mining gate, studs).
    -- standoff = how far back it holds in the attack formation (client), studs. Keep
    -- standoff < attack_range so the pet can still hit from where it stands. Melee/tank
    -- crowd in close (standoff 0); ranged hangs back and snipes; support/control sit at
    -- mid range. This is the melee-closes / ranged-kites dynamic.
    -- threat_mult scales the aggro a role generates (passive threat × this), so a tank
    -- holds the enemy's attention and soaks for the squad while dps/ranged stay safer.
    -- mining_mult / combat_mult: the role's DAMAGE knobs — the classic archetype curve
    -- (blasters/melee hit hardest at 1.0, tanks moderate, support/control trade damage for
    -- utility), split by target kind. Damage routes through PetPowerView.profile (the same
    -- resolver the inventory card runs — display = dealt, #132): a crystal swing uses
    -- mining_mult (the card's ⛏), an enemy swing combat_mult (the card's ⚔). pets.lua can
    -- override per pet — bump mining_mult on a "miner" and combat_mult on a "fighter" to
    -- create specialists (which spawn trades). The legacy single damage_mult is retired.
    -- auto_heal makes a support pet periodically heal the most-hurt ally (the bunny's
    -- grass-biome flavor; element-specific support variants can key off this later).
    -- defense = innate damage reduction (the role's "toughness"), added to the pet's
    -- own Defense attribute + any DefenseBuff before the armor curve in _hitPet. Tanks
    -- are naturally tough; melee a little; ranged/support are squishy. Tune freely.
    roles = {
        tank = {
            label = "Tank",
            glyph = "T",
            color = { 70, 130, 195 },
            icon = "",
            attack_range = 9,
            standoff = 0,
            threat_mult = 5,
            implicit_taunt = true,
            mining_mult = 0.6,
            combat_mult = 0.6,
            defense = 100,
        },
        melee = {
            label = "Melee",
            glyph = "M",
            color = { 205, 85, 70 },
            icon = "",
            attack_range = 9,
            standoff = 0,
            threat_mult = 1,
            mining_mult = 1.0,
            combat_mult = 1.0,
            defense = 20,
        },
        -- kite = true: holds near the player and snipes instead of orbiting the enemy, so
        -- an enemy chasing it has to close the gap (the melee-closes / ranged-kites loop).
        ranged = {
            label = "Blaster",
            glyph = "R",
            color = { 120, 180, 85 },
            icon = "",
            attack_range = 28,
            standoff = 17,
            kite = true,
            mining_mult = 1.0,
            combat_mult = 1.0,
            defense = 0,
        },
        support = {
            label = "Buffer",
            glyph = "S",
            color = { 150, 110, 215 },
            icon = "",
            attack_range = 16,
            standoff = 9,
            -- 0.35 -> 0.45 (Jason, 2026-06-12): the rainbow-imp buffer team only beat the
            -- three-strongest team 202 vs 194 (~4%) — "a little weak". The BODY aptitude is
            -- the safe lever to sweeten buffers: it's per-pet and linear. The AURA fractions
            -- stay put because they stack ADDITIVELY across multiple buff pets (BuffStack) —
            -- raising those raises the multi-buffer ceiling, "we don't want it to get crazy".
            mining_mult = 0.45,
            combat_mult = 0.45,
            auto_heal = { interval = 1.5, fraction = 0.3 },
            defense = 10,
        },
        control = {
            label = "Control",
            glyph = "C",
            color = { 90, 185, 205 },
            icon = "",
            attack_range = 20,
            standoff = 12,
            mining_mult = 0.5,
            combat_mult = 0.5,
            defense = 40,
        },
    },
}
