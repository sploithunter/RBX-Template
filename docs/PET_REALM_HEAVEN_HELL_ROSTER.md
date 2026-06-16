# Heaven & Hell Pet Rosters

Status: design (working names; structure locked, art TBD) — Jason, 2026-06

Per-realm pet pools for the stacked Heaven/Hell layers. See the
[Design Document](PET_REALM_DESIGN_DOCUMENT.md) §3 (Loop & Overlay / Stacked Layers) for the
realm geometry, and the **Dragons, Secrets, and Player Class (Rebirth)** section for the
11-dragon rebirth gate that this roster feeds.

## Framing: 4 origins, ascended or fallen — not a 5th element

There are **4 origins** (Fire/Lava, Ice, Grass/Earth, Desert). A realm does **not** add a new
element — it **transfigures each origin**: Heaven = the *ascended* form (radiant/celestial),
Hell = the *fallen* form (corrupted/infernal). A pet keeps its **origin** (drives element/stats)
and gains a **realm** tag (drives the heaven/hell treatment) — resolved through
`src/Shared/Game/WorldContext.lua` (`{ realm, depth }` from the world folder). Every heaven pet
has a 1:1 hell mirror, so you model the **pair**, not two unrelated sets.

Origins lean a playstyle (loosely, not strictly):

| Origin | Lean |
|--------|------|
| Fire/Lava | **Damage** |
| Ice | **Control** (slow / hold / freeze) |
| Grass/Earth | **Sustain / heal / tank** |
| Desert | **Durable / utility** (evasion, yield, regen) |

A **complete realm roster = 4–5 pets per origin** covering the role spread, plus that realm's
**one secret dragon** (the chase pet + rebirth token).

## Heaven 1 — full pool (5 per origin, 20 + the dragon)

### 🔥 Fire — leans damage
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Emberling Cherub | Melee | Common | winged coal-imp, dawn-touched |
| Sunmane Lion | Melee (bruiser) | Uncommon | golden solar lion, charges in |
| Solar Phoenix | Ranged | Rare | dawn-bolt volleys |
| Radiant Salamander | Support (offense buff) | Uncommon | bathes the squad in +damage light |
| **★ Empyrean Dragon** | **Damage (capstone)** | **SECRET** | radiant gold-white wyrm — Heaven 1's chase + rebirth dragon #2 of 11 |

### ❄️ Ice — leans control
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Frostlight Hare | Melee | Common | shimmering frost-rabbit |
| Aurora Fox | Control | Uncommon | auroral light that slows & binds |
| Seraph Owl | Ranged | Uncommon | starlight arrows from standoff |
| Glacial Seraph | Support (shield) | Rare | wreathes the squad in protective frost-light |
| Aurora Leviathan | Tank / Control | Epic | vast aurora-scaled serpent — holds + slows |

### 🌿 Grass — leans sustain/heal
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Bloomlamb | Support (heal) | Common | haloed lamb in flowering light |
| Halo Hare | Melee | Common | swift winged hare |
| Goldleaf Stag | Tank | Uncommon | gilded-antler stag, nature armor |
| Verdant Sprite | Support (yield/luck) | Uncommon | bloom-spirit, boosts harvest |
| Worldroot Ent | Tank / Heal | Rare | radiant tree-guardian, big HP + regen aura |

### 🏜️ Desert — leans durable/utility
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Sun Scarab | Support (coin/yield) | Common | golden beetle, boosts coins |
| Mirage Jackal | Melee (evasion) | Uncommon | shimmering jackal that dodges |
| Gilded Sphinx | Tank | Rare | gold-stone guardian, soaks hits |
| Dawn Camel | Support (regen) | Uncommon | sun-blessed, slow heal aura |
| Solar Roc | Ranged | Rare | great golden bird, light-talon dives |

**Role coverage:** Tank ×4 · Melee ×5 · Ranged ×3 · Support ×6 (heal/shield/buff/yield/regen) ·
Control ×1–2 (ice owns it) · + the secret dragon. A player can field a full squad several ways,
and each origin has an apex (Empyrean Dragon, Aurora Leviathan, Worldroot Ent, Solar Roc) — with
**fire's apex being the secret/rebirth dragon**.

## Hell 1 — mirror skeleton

Same 20-name structure, fallen treatment (1:1 mirrors):

- Fire: Cinderling Imp · Ashmane Lion · Ashfeather Phoenix · Brimstone Salamander · **Abyssal Wyrm** (secret, dragon #7 of 11)
- Ice: Rimelight Hare · Rimewraith Fox · Dread Owl · Black Seraph · Black-Ice Leviathan
- Grass: Blightlamb · Dread Hare · Rotleaf Stag · Wither Sprite · Gravewood Ent
- Desert: Carrion Scarab · Phantom Jackal · Glass Sphinx · Dust Camel · Ash Roc

## Building economically

- **Model the dragon first** per realm — it's the chase + 1 of the 11 rebirth keys.
- **Rig reuse:** the dragon silhouette/animation rig re-skins across several of the 11
  (Empyrean ↔ Abyssal ↔ Aurora ↔ Rimewraith …) so 11 dragons isn't 11× the work.
- **Mirror reuse:** every heaven pet's rig re-skins to its hell mirror.
- New pets slot into a realm's egg/spawn pool by tagging **origin** (element/stats) + **realm**
  (`WorldContext`) — no new code per pet.

## Deeper realms (2–5)

Heaven 2–5 / Hell 2–5 reuse this per-origin skeleton with grander forms and depth-scaled stats
(`WorldContext.difficultyFor`). The two **pure apex dragons** live at the ends of the stack:
**Seraph Dragon** (Heaven 5) and **Void Dragon** (Hell 5) — the grandest of the 11.
