# Pet Realm — Icons, Colors & Powers (Definitive Map)

**Status:** living SoT for the icon/badge system + the player power roster. Pairs with
`configs/power_icons.lua` (icon art ids + symbol/effect maps), `configs/powers.lua` (power defs +
effect kinds), `configs/pet_roles.lua` (support auras). Where this doc says **PROPOSED**, it's a
design target not yet in config.

The whole system is **one rule**: every icon in the game is a two-layer badge — a colored **disc**
(the element/color) behind a white **symbol** (what it does), optionally framed by a **ring** (the
targeting shape). One renderer (`src/Client/UI/PetBadge.lua`) draws it everywhere: hotbar, squad
cards, inventory cards, world VFX. So "define a power" = pick a **color + symbol (+ ring)**, and it
reads identically on every surface.

---

## Part A — The Icon System

### A.1 Color = Origin (the disc color)

The disc color is the power's **origin**. Four are the RPS elements; white is the generic/universal
tier (no element — shared powers everyone can pick).

| Color | Origin | Combat alias | Bright RGB (disc) | Dark RGB (ring) | Used for |
|---|---|---|---|---|---|
| 🟢 green | **earth** | grass | `91,255,81` | `33,92,29` | Geomancer (stone) |
| 🔴 red | **fire** | lava | `255,82,89` | `92,30,32` | Pyromancer (fire) |
| 🟡 yellow | **desert** | sand | `255,209,79` | `92,75,28` | Sandwalker (sand) |
| 🔵 blue | **ice** | ice | `81,136,255` | `29,49,92` | Cryomancer (frost) |
| ⚪ white | **generic** | — (neutral) | `220,220,225` | `70,70,78` | **Universal powers (Swift, Hasten, Fortune…) — any archetype can pick. Distinct color = "no origin".** |

`element_alias` maps combat tokens → badge keys: grass→earth, lava→fire, desert→desert, ice→ice.

### A.2 Targeting = the ring shape (powers only)

Archetype/identity badges use the plain **aura** ring (no direction). Powers add a directional ring
so you read *who it hits*:

| Targeting kind | Ring shape | Meaning |
|---|---|---|
| `self` / `none` | `aura` | self / squad / no direction |
| `single` | `target_in` | one enemy |
| `ally` | `target_out` | one ally |
| `enemy_aoe` | `aoe` | area on enemies |
| `team_aoe` | `target_aoe` | area on allies |

### A.3 Icon symbol catalog (24 symbols)

All symbols exist as art in 5 colors (white/blue/green/red/yellow), identical shape, different
color. **Uploaded** = decal + resolved image id present in `scripts/icon_ids.*.json` and wired in
`configs/power_icons.lua`. The other 14 have art but aren't uploaded/wired yet.

| Symbol | Reads as | Uploaded? | Currently used by |
|---|---|---|---|
| `armor_chest` | armor / defense | ✅ | armor powers, tank role, defense status |
| `shield` | shield / absorb | ✅ | shield powers, shield status |
| `fist_impact` | melee strike (impact) | ✅ | melee role, eruption (AoE damage) |
| `arrow_right` | ranged / speed / dash | ✅ | ranged role *(free for Swift)* |
| `star_sparkle` | support / burst / special | ✅ | support role, signature burst |
| `hand_stop` | control / root / stop | ✅ | root, control role |
| `chevrons_up` | buff / boost up | ✅ | damage buff |
| `chevrons_down` | debuff / slow down | ✅ | aoe_slow |
| `eye_hidden` | stealth / blind / evade | ✅ | dodge, aoe_blind |
| `contagion` | DoT / spread / plague | ✅ | mark_of_flame, wildfire |
| `coins_up` | **coin yield** | ⬜ art only | **(meerkat aura, farming powers)** |
| `plus` | **heal** | ⬜ art only | **(bunny aura, heal powers)** |
| `plus_down` | regen / heal-over-time | ⬜ art only | *(free — HoT / lifedrain)* |
| `clover_lucky` | **luck / rare-find** | ⬜ art only | **(egg-hatch luck, fortune powers)** |
| `clover_huge` | **HUGE luck (tier 2)** | 🎨 art made | **(big egg-hatch luck — the marquee "Huge Fortune" power)** |
| `gift_up` | reward / drop boost | ⬜ art only | *(free — windfall / loot)* |
| `capacitor` | energy / charge / focus | ⬜ art only | *(free — overclock / focus regen)* |
| `history` | recharge / cooldown / time | ⬜ art only | *(free — Hasten)* |
| `fist` | basic attack | ⬜ art only | *(free — strike)* |
| `fist_broken` | weaken / disarm | ⬜ art only | *(free — disarm)* |
| `shield_broken` | armor break / sunder | ⬜ art only | *(free — sunder / expose)* |
| `eye` | reveal / accuracy / perception | ⬜ art only | *(free — expose / focus-fire)* |
| `target` | designate / focus target | ⬜ art only | *(free — mark / assist)* |
| `target_down` | weaken target | ⬜ art only | *(free — cripple)* |
| `user_desk` | deploy / summon / collect | ⬜ art only | *(free — recall / magnet)* |

---

## Part B — Player Powers

### B.1 The model: pick 10 of 20

Each player has a **pool of 20 powers** and selects **10** over their level-up arc. The pool is:

- **Origin powers** (element-colored) — themed to the player's archetype. Attack / defense /
  control flavor.
- **Generic powers** (white) — shared, any archetype can pick (Swift, Hasten, Fortune, Prospector…).
  Distinct color so "this isn't an origin power" reads instantly.

So a player's 20 ≈ *their archetype's origin powers + the shared generic pool.* The same icons are
reused for **pet powers** (support auras) — see Part C.

### B.2 Powers that EXIST today (`configs/powers.lua`)

Effect families: `absorb` (flat shield pool), `defense_buff` (armor %), `buff` (pet damage ×),
`vulnerable` (enemy takes more), `root` (lock/slow), plus pyro signature families.

| Power | Display name | Origin | Effect | Symbol | Ring | What it does |
|---|---|---|---|---|---|---|
| `aegis` | Aegis | 🟢 earth | shield (single_pet) | `shield` | aura | Absorb shield (40) on **one selected pet**, 12s |
| `dune_shield` | Dune Shield | 🟡 desert | shield | `shield` | aura | Squad absorb shield (40), 12s |
| `ember_ward` | Ember Ward | 🔴 fire | shield | `shield` | aura | Squad absorb shield (40), 12s |
| `ironclad` | Ironclad | 🟢 earth | armor (single_pet) | `armor_chest` | aura | +80 Defense on **one selected pet**, 12s |
| `stone_skin` | Stone Skin | 🟢 earth | armor | `armor_chest` | aura | Squad +80 Defense %, 12s |
| `ice_armor` | Ice Armor | 🔵 ice | armor | `armor_chest` | aura | Squad +80 Defense %, 12s |
| `bulwark` | Bulwark | 🟢 earth | team_shield | `armor_chest` | aura | Squad +120 Defense %, 15s |
| `mountains_strength` | Mountain's Strength | 🟢 earth | damage_buff | `chevrons_up` | aura | +50% pet damage, 8s |
| `mirage_step` | Mirage Step | 🟡 desert | dodge | `eye_hidden` | aura | 30 dodge-absorb, 8s |
| `sandstorm` | Sandstorm | 🟡 desert | aoe_blind | `eye_hidden` | aoe | Blind enemies, ×1.5 vuln, 6s |
| `frost_bind` | Frost Bind | 🔵 ice | root | `hand_stop` | aoe | Root enemies, 5s |
| `blizzard` | Blizzard | 🔵 ice | aoe_slow | `chevrons_down` | aoe | Slow/root enemies, 6s |
| `mark_of_flame` | Mark of Flame | 🔴 fire | damage_over_time | `contagion` | target_in | DoT vuln ×1.5 on target, 6s |
| `eruption` | Eruption | 🔴 fire | aoe_damage | `fist_impact` | aoe | AoE vuln ×2.0, 5s |
| `wildfire` | Wildfire ⚡sig | 🔴 fire | burn_spread | `contagion` | target_in | Spreading vulnerability (L15) |
| `firestorm` | Firestorm ⚡sig | 🔴 fire | team_cleave | `star_sparkle` | target_aoe | Team-AoE cleave splash (L20) |
| `cataclysm` | Cataclysm ⚡cap | 🔴 fire | amplified_burst | `star_sparkle` | aoe | Meteor burst, squad-scaled (L30) |

**That's 17 powers, and they're almost all attack/defense/control.** The two non-combat levers
(coin yield, egg luck) currently live only on *pets*, not as player powers.

### B.3 Gap analysis (Jason's read, confirmed)

| Category | Coverage | Notes |
|---|---|---|
| **Attack / debuff** | 🟢 Strong | DoT, AoE, blind, root, slow, signatures. A few open symbols (`fist`, `fist_broken`, `shield_broken`, `target_down`). |
| **Defense / shield / armor** | 🟢 Strong | shields + armor + team armor + single-target. |
| **Control** | 🟡 OK | root, slow, blind. Could add stun/knockback. |
| **Farming / economy** | 🔴 **Gap** | No player coin/mining/drop powers. `coins_up`, `gift_up`, `capacitor` art is ready. |
| **Luck / egg** | 🔴 **Gap** | Only one luck lever (egg hatch). `clover_lucky` ready — big room to push. |
| **Utility / travel** | 🔴 **Gap** | No Swift/Hasten yet (#158). `arrow_right`, `history` ready. |

### B.4 PROPOSED powers to fill the gaps (toward a 20-pool)

Generic (⚪ white) unless an origin fits better. All use **existing art** unless flagged
**[new icon?]**.

**Farming / economy (generic, ⚪):**
| Power | Symbol | Effect (proposed) |
|---|---|---|
| Prospector | `coins_up` | +X% coin yield for a duration |
| Mother Lode | `capacitor` | +X% mining throughput / ore for a duration |
| Windfall | `gift_up` | next N pickups doubled, or a burst of bonus drops |
| Magnet | `magnet` **[new icon]** | auto-collect nearby coins/ore (radius pull) |

> **Magnet + Windfall depend on a DROPS/PICKUP mechanic that doesn't exist yet** — coins are
> instant-credited on mine today, so there's nothing to collect. Building physical drops (pooled
> coin/ore parts → proximity collect → magnet widens the radius) is its own epic and unlocks the
> whole farming + rare-drop category. Until then, Prospector/Mother Lode (multipliers on the
> instant-credit path) work standalone.

**Luck / egg (generic, ⚪ — push this lever):**
| Power | Symbol | Effect (proposed) |
|---|---|---|
| Fortune | `clover_lucky` | +luck (better egg odds) for next N hatches |
| **Huge Fortune** | `clover_huge` | **BIG egg-hatch luck spike — the marquee, most-desirable luck power (tier 2)** |
| Lucky Streak | `clover_lucky` | temporary rare-find boost while farming |
| Wishbone | `star_sparkle` | next hatch guaranteed uncommon-or-better |

**Utility / travel (generic, ⚪ — #158):**
| Power | Symbol | Effect (proposed) |
|---|---|---|
| Swift | `arrow_right` | +move speed (self + pets) |
| Hasten | `history` | +power recharge rate |
| Blink | `arrow_right` | short dash / reposition |
| Regroup | `user_desk` | instant squad recall to the player |

**Attack fill (origin-colored):**
| Power | Symbol | Effect (proposed) |
|---|---|---|
| Sunder | `shield_broken` | enemy armor break (takes more damage) |
| Disarm | `fist_broken` | reduce enemy attack |
| Focus Fire | `target` | designate priority target (+damage to it) |
| Expose | `eye` | reveal + accuracy/crit boost vs target |
| Cripple | `target_down` | slow + weaken one target |
| Strike | `fist` | basic single-target hit (low-level filler) |

**Icon shopping list (Jason to make — art gaps for high-value powers):**

| Priority | Icon | Unlocks / why |
|---|---|---|
| ★ high | `magnet` (horseshoe) | Magnet / collect powers — reads far better than `user_desk` |
| ★ high | `xp_up` (star + up arrow) | XP / level-boost power — a top-tier farming want; no good symbol today (`star_sparkle` taken) |
| ◐ med | `revive` (plus over a downed glyph) | revive a downed pet — distinct from heal |
| ◐ med | `knockback` (outward burst arrows) | repel / control — distinct from `hand_stop` (root) |
| ○ low | `home` / `portal` | recall-to-base / travel |

`clover_huge` is already made (Huge Fortune). Everything else in the roster above maps to existing
art — no other gaps.

---

## Part C — Pet support auras (same icons)

Support pets emit a team aura (`configs/pet_roles.lua` `support_auras`), applied by
`EnemyService:_supportPass`. **Design intent (Jason):** the buff is a per-pet attribute → every
affected pet shows the icon, exactly like shields. Today only heal stamps the pets; defense/offense
/yield need the per-pet display marker added (see the unification task).

| Pet | Role | Origin color | Aura | Symbol | What it does | Per-pet display today |
|---|---|---|---|---|---|---|
| bunny | Buffer | 🟢 earth | heal | `plus` | mend most-hurt ally 30% pool /1.5s | ✅ HEAL pulse |
| penguin | Buffer | 🔵 ice | defense | `armor_chest` | +80 team Defense /2s | ❌ (TeamDefenseBuff, no badge) |
| emberimp | Buffer | 🔴 fire | offense | `chevrons_up` | ×1.25 pet damage /2s | ❌ (on player, not pets) |
| meerkat | Buffer | 🟡 desert | yield | `coins_up` | ×1.25 coin yield /2s | ❌ (on player, not pets) |

**Two complementary displays:** inventory card = what a pet *provides* (identity); squad card =
what a pet *currently has* (live aura). The unification adds per-pet markers + badge entries so all
four read on the battlefield.

---

## Part D — Status badges (transient, squad cards + world)

`SquadHud.PET_EFFECTS` reads a pet/player attribute and resolves the power's disc via
`PetBadge.forPower` (so the badge matches the cast power), falling back to a static icon.

| Status | Symbol | Source attribute | Stamped by |
|---|---|---|---|
| DEF (armor) | `armor_chest` | `DefenseBuffUntil` / `DefenseBuffPowerId` | armor powers |
| ARM (shield) | `shield` | `CombatShieldUntil` / `CombatShieldPowerId` | shield powers |
| DMG | `chevrons_up` | `PetDamageBuffUntil` / `PetDamageBuffPowerId` | damage buff |
| HEAL | `plus` | `HealFxUntil` | heal aura/power |
| *(proposed)* YIELD | `coins_up` | `CoinYieldFxUntil` | meerkat aura |
| *(proposed)* OFF | `chevrons_up` | `OffenseFxUntil` | emberimp aura |
| *(proposed)* TEAM-DEF | `armor_chest` | `TeamDefenseFxUntil` | penguin aura |

---

## Part E — Buff math: how bonuses stack

The one rule for every percentage buff (luck, coin yield, mining, pet damage, move speed, recharge,
XP): **additive within an axis, on a base of 1.0.** Multiplicative compounding is banned except for a
tiny, deliberate set of global multipliers.

### E.1 The rule

```
multiplier(axis) = 1 + Σ(bonus_i)          -- every active source in that axis, summed
                   clamped to axis cap
output = base × multiplier(axis)
```

So **+25% luck and +25% luck = 1 + 0.25 + 0.25 = ×1.50** — NOT ×1.25 × ×1.25 (×1.5625). One source
is the easy case (×1.25); the rule just makes two+ behave linearly.

### E.2 Why additive, not multiplicative

Multiplicative stacking compounds: n stacks of +25% = `1.25^n`. Ten → ×9.3, twenty → ×86 — luck
becomes thousands of times better and the economy breaks. Additive is linear: `n × 25%` → +250% =
×3.5 for ten. Linear is tunable; compounding is not. **Default: every same-axis bonus adds.**

### E.3 Axes are independent

`luck`, `coin_yield`, `mining`, `pet_damage`, `move_speed`, `recharge`, `xp` are SEPARATE axes —
each its own additive sum, each applied to its own output. They never fold into each other (a coin
buff doesn't make luck better). A drop that is both "a coin" and "rare" gets `coin_yield` on the
payout and `luck` on the rarity roll — different stages, never one compounded number.

### E.4 Global multipliers (the only multiplicative exception)

A small, fixed set of whole-account multipliers multiply the final axis result. These are the ONLY
multiplicative things and are rare by design:

```
final = base × (1 + Σ axis bonuses) × Π(global_k)
```

Globals = e.g. 2× gamepass, a live event ×2, a rebirth/prestige multiplier. **Powers and pet auras
are NEVER globals** — they always go in the additive sum.

### E.5 Runaway guards (in order of preference)

1. **Concurrency is the natural cap** — you pick 10 of 20, the hotbar holds a few, and cooldowns
   mean temporary buffs come and go. You can't hold ten +luck powers active at once.
2. **Per-axis hard cap** — each axis clamps in config (e.g. `luck +300%`, `coin_yield +500%`). That's
   the clamp in E.1.
3. **Soft diminishing returns (use sparingly)** — if an axis must allow big stacking without running
   away: `effective = knee + (sum − knee) × dr_factor` past a knee point.

### E.6 Permanent vs temporary (same bucket)

- **Permanent/passive** (deployed pet aura, gear, level, rebirth) — in the sum while active.
- **Temporary** (a cast power for Ns) — in the sum only while its timer is live, then drops out.

Both land in the same per-axis sum; temporary sources just come and go.

### E.7 Implementation note (the refactor this implies)

Today buffs **SET a single attribute** (`PetDamageBuff`, `CoinYieldBuff`, …) → last-writer-wins
(clobber), and the two pet-vs-power damage buffs currently *multiply* (the compounding we're
banning). The model above wants a **per-axis accumulator**: each source registers `{axis, fraction,
sourceId, expiry}`; the consumer reads `1 + Σ(live fractions)` clamped to `axis cap`. Build this as
a shared pure module (`BuffStack`) with a headless spec pinning the math, then route powers + auras
through it.

### E.8 Worked example — luck

- Base hatch luck = ×1.0; cap `luck = +300%` (×4.0).
- Active: Fortune (+25%) + lucky pet aura (+15%) + 2× luck gamepass (global).
- `axis = 1 + 0.25 + 0.15 = 1.40` (under cap).
- `final = 1.0 × 1.40 × 2.0 = ×2.80 luck`.
- Add **Huge Fortune** (+50%): `axis = 1 + 0.25 + 0.15 + 0.50 = 1.90` → `final = ×3.80`. Linear and
  predictable — never ×1000, even with everything on.

> **Luck → odds is a separate mechanic** (the luck multiplier reweights the rarity table; define
> that in the egg/hatch config). This section governs only how the luck *number* stacks.

---

## Part F — Build order from here

1. **Upload + wire the 14 pending symbols** (esp. `coins_up`, `plus`, `clover_lucky`, `gift_up`,
   `capacitor`, `history`, `arrow_right`) across the 5 colors → `power_icons.lua discs`.
2. **Pet support display unification** — per-pet aura markers + status badges (Part C/D).
3. **Inventory "provides" icon + label** on pet cards (#165).
4. **`BuffStack` pure module + headless spec** — the per-axis additive accumulator from Part E
   (caps per axis, global multipliers, expiry). Prereq for ANY multiplier power to stack correctly;
   route the existing damage/yield/defense buffs through it (kills the current clobber + compounding).
5. **Generic power tier** — white-disc shared powers; add Swift/Hasten (#158) + farming/luck powers.
6. **Grow each archetype's origin pool toward ~12–14** so pool (origin + generic) ≈ 20, pick 10.
7. **Power-selection UI** already exists (pick-at-level-up) — point it at the 20-pool.
