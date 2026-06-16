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

## Hell 1 — "The Cinderreach" — full pool (5 per origin, 20 + the dragon)

The smoldering, ash-and-rot first descent. **Theme signature — give → take:** where Heaven
supports by GIVING (heal / shield / buff), Hell supports by TAKING (drain / shred / curse). Same
roles as Heaven, inverted morality — the City-of-Heroes debuffer/controller fantasy of the Hell
path. Origins keep their leans; only the flavor darkens. Every entry is a 1:1 mirror of the
Heaven 1 pet of the same slot (rig re-skins).

### 🔥 Fire — leans damage (infernal / brimstone)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Cinderling Imp | Melee | Common | charred imp, claws & cinders |
| Ashmane Lion | Melee (bruiser) | Uncommon | smoldering black lion, ember-maned |
| Ashfeather Phoenix | Ranged | Rare | cinder-bolts; rises from its own ash |
| Brimstone Salamander | Support (burn-curse) | Uncommon | brands foes — squad deals bonus burn (offense "buff" as an enemy debuff) |
| **★ Abyssal Wyrm** | **Damage (capstone)** | **SECRET** | void-black infernal wyrm — Hell 1's chase + rebirth dragon #7 of 11 |

### ❄️ Ice — leans control (black-ice / dread)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Rimelight Hare | Melee | Common | frostbitten dark hare |
| Rimewraith Fox | Control | Uncommon | spectral chill that freezes with dread (fear/root) |
| Dread Owl | Ranged | Uncommon | black owl, icy shards from the dark |
| Black Seraph | Support (armor-shred) | Rare | fallen frost-angel that strips enemy armor (shield inverted to anti-shield) |
| Black-Ice Leviathan | Tank / Control | Epic | vast black-ice serpent — holds + slows |

### 🌿 Grass — leans sustain (blight / rot / drain)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Blightlamb | Support (life-drain heal) | Common | rotted lamb that heals the squad by leeching enemy life |
| Dread Hare | Melee | Common | gaunt, fanged hare |
| Rotleaf Stag | Tank | Uncommon | thorned decaying stag — soaks + spreads rot |
| Wither Sprite | Support (wither-curse) | Uncommon | blight-spirit that saps foes' output |
| Gravewood Ent | Tank / Drain | Rare | dead-tree guardian, big HP + life-leech aura |

### 🏜️ Desert — leans durable/utility (ash / glass / carrion)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Carrion Scarab | Support (coin-from-kills) | Common | feeds on the fallen — yield on enemy death |
| Phantom Jackal | Melee (evasion) | Uncommon | ash-mirage jackal, dodges + flanks |
| Glass Sphinx | Tank | Rare | blackened-glass guardian, sharp + durable |
| Dust Camel | Support (regen-denial) | Uncommon | sand-wraith that stops enemy healing |
| Ash Roc | Ranged | Rare | great ash-feathered bird, glass-talon dives |

**Role coverage** mirrors Heaven 1 (Tank ×4 · Melee ×5 · Ranged ×3 · Support ×6 · Control ×1–2 ·
+ secret dragon) — same squad shapes, but the supports **debuff/drain** instead of heal/shield.
Apexes: Abyssal Wyrm (secret), Black-Ice Leviathan, Gravewood Ent, Ash Roc.

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
