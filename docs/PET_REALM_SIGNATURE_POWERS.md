# Pet Realm — Signature Powers (design)

> **Design goal:** each of the four origins gets **4 signatures** — one **role-defining anchor** that
> makes that origin near-irresistible if you want that role, two mid-tier signatures that deepen the
> fantasy, and one **near-endgame capstone**: crazy damage on a long recharge. Firewall rule §16.5
> still holds — player powers never deal direct damage; "damage" routes *through the pets* (the
> `amplified_burst` family scales a burst by the squad's attack total and credits it to the pets), so
> every capstone is a pet-amplified meteor, not a player nuke.

**Role identity per origin** (the anchor each origin should "own"):

| Origin | Element | Role identity | The anchor (must-pick) |
|---|---|---|---|
| Geomancer | earth (green) | **SHIELD / tank** | Bastion |
| Pyromancer | fire/lava (red) | **DAMAGE** | Wildfire + Firestorm |
| Cryomancer | ice (blue) | **CONTROL** | Permafrost |
| Sandwalker | desert (yellow) | **HEAL / sustain** | Oasis |

Legend: **family** = the effect_kind family it routes through (✅ exists today, 🆕 needs a new mechanic).
**target** = single · enemy_aoe · targeted_aoe · team_aoe · friendly. Costs are starting points to tune.

---

## 🟢 Earth — Geomancer (SHIELD / tank)

| # | Power | Lvl | Role | Mechanic (family) | What it does | Target | Focus / CD |
|---|---|---|---|---|---|---|---|
| 1 | **Bastion** ⭐anchor | 15 | shield | absorb ✅ (big magnitude) | the premier squad shield — every pet gets a huge stone barrier that soaks a ton before it cracks. If you want SHIELD, you take Geomancer for this. | team_aoe | 30 / 35s |
| 2 | **Seismic Hold** | 22 | control+def | root ✅ + defense_buff ✅ | stone spikes ROOT every engaged enemy *and* harden the squad (+Defense) for the duration — a tank lockdown. | enemy_aoe | 30 / 40s |
| 3 | **Living Mountain** | 30 | sustain | defense_buff ✅ + heal-over-time 🆕 | the squad becomes a moving mountain: massive +Defense and a heal-tick each second for a window — near-unkillable while it lasts. | team_aoe | 40 / 55s |
| 4 | **Worldbreaker** 💥capstone | 44 | endgame dmg | amplified_burst ✅ (earth) | rip the ground open: a quake hits everything in a big radius for **squad-attack-total ×3.5**, then a fissure lingers ×1.6 vulnerability. Long recharge. | targeted_aoe | 70 / 110s |

---

## 🔴 Fire — Pyromancer (DAMAGE) — *3 exist, +1 new*

| # | Power | Lvl | Role | Mechanic (family) | What it does | Target | Focus / CD |
|---|---|---|---|---|---|---|---|
| 1 | **Wildfire** ⭐anchor | 15 | damage | burn_spread ✅ | a vulnerability mark that **contagions** to nearby enemies — turns a pack into a bonfire. *(exists)* | single_spread | 25 / 25s |
| 2 | **Firestorm** ⭐anchor | 20 | damage | team_cleave ✅ | for a window every pet swing **splashes** to nearby enemies — clears crowds. *(exists)* | team_aoe | 35 / 40s |
| 3 | **Inferno Brand** 🆕 | 28 | damage | vulnerable ✅ (ramping 🆕) | brand one target; its vulnerability **ramps up every second** it stays alive (execute pressure on tough targets/bosses). | single | 20 / 22s |
| 4 | **Cataclysm** 💥capstone | 40* | endgame dmg | amplified_burst ✅ (lava) | the meteor: **squad-attack-total ×3** to everything in 16 studs + a molten pit. The "huge long-recharge targeted AoE." *(exists — suggest re-leveling 30 → ~40 to make it true endgame.)* | targeted_aoe | 60 / 90s |

---

## 🔵 Ice — Cryomancer (CONTROL)

| # | Power | Lvl | Role | Mechanic (family) | What it does | Target | Focus / CD |
|---|---|---|---|---|---|---|---|
| 1 | **Permafrost** ⭐anchor | 15 | control | root ✅ (long/strong) | the premier lockdown — roots & slows every engaged enemy for the longest duration in the game. If you want CONTROL, you take Cryomancer for this. | enemy_aoe | 25 / 30s |
| 2 | **Shatter** | 22 | control→dmg | vulnerable ✅ (bonus vs rooted 🆕) | detonate the frozen: enemies currently rooted/slowed take a **massive vulnerability spike** — the payoff for your control. | enemy_aoe | 25 / 28s |
| 3 | **Absolute Zero** | 30 | hard CC | root ✅ (global) | flash-freeze **every enemy on screen** solid for a long window — mass hard crowd-control to reset a fight. | enemy_aoe | 45 / 60s |
| 4 | **Fimbulwinter** 💥capstone | 44 | endgame dmg | amplified_burst ✅ (ice) | a glacial apocalypse: **squad-attack-total ×3.5** ice burst in a huge radius + a lingering freeze field. Long recharge. | targeted_aoe | 70 / 110s |

---

## 🟡 Desert — Sandwalker (HEAL / sustain)

| # | Power | Lvl | Role | Mechanic (family) | What it does | Target | Focus / CD |
|---|---|---|---|---|---|---|---|
| 1 | **Oasis** ⭐anchor | 15 | heal | heal ✅ (+ HoT 🆕) | the premier heal — a burst that refills the squad *and* a strong heal-over-time. If you want HEAL, you take Sandwalker for this. | team_aoe | 25 / 30s |
| 2 | **Mirage Veil** | 22 | evasion+heal | dodge (absorb) ✅ + heal-on-evade 🆕 | the squad shimmers: big evasion/absorb, and each dodge **heals** the pet — sustain through a fight. | team_aoe | 20 / 25s |
| 3 | **Simoom** | 30 | heal+control | heal ✅ + aoe_blind ✅ | a swirling sandstorm: **heals the squad** inside it while **blinding/softening** every enemy caught in it. | team_aoe | 35 / 45s |
| 4 | **Glasstorm** 💥capstone | 44 | endgame dmg | amplified_burst ✅ (desert) | a vortex of razor glass: **squad-attack-total ×3.5** to everything in a wide radius, shredding ×1.6 vulnerability after. Long recharge. | targeted_aoe | 70 / 110s |

---

## Summary

- **4 anchors** (near-irresistible by role): **Bastion** (shield), **Wildfire/Firestorm** (damage),
  **Permafrost** (control), **Oasis** (heal). Pick your role → pick that origin.
- **4 endgame capstones** (crazy damage, long recharge, `amplified_burst` re-skinned per element):
  **Worldbreaker** · **Cataclysm** · **Fimbulwinter** · **Glasstorm** — each ~×3–3.5 squad-attack-total
  targeted AoE on a 90–110s cooldown, unlocking ~L40–44.

### What's already there vs new
- **Reuse (✅):** absorb, defense_buff, root, vulnerable, heal, burn_spread, team_cleave,
  amplified_burst — most of the 16 route through existing families, so they're badge-ready and
  firewall-safe out of the box.
- **New mechanics (🆕), small additions:** heal-over-time tick (Living Mountain, Oasis), ramping
  vulnerability (Inferno Brand), bonus-vs-rooted (Shatter), heal-on-evade (Mirage Veil), global root
  (Absolute Zero). Each is a modest variant of an existing family, not a new system.

### Implementation order (suggested)
1. The **4 capstones** first — they all share `amplified_burst` (just new configs + element + level),
   so the marquee "crazy damage" lands fast and reads great with the existing meteor VFX.
2. The **4 role anchors** (Bastion/Permafrost/Oasis + fire's already done) — these define each origin.
3. The **mid-tier 6** with their small new mechanics.

All slot into `configs/powers.lua` (`effect_kinds` + `powers` with the `signature`/`unlock_level`
schema), badges auto-resolve via `configs/power_icons.lua`, and they apply through the existing
PowerService families. Capstones reuse the Cataclysm VFX path tinted per element.
