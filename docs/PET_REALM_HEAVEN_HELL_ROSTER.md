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

## Heaven 2 — "The Aurora Reaches" — full pool (5 per origin, 20 + the dragon)

The second ascent — **farther from base reality** (see the Design Document's *Realm aesthetic
gradient*). Heaven 1's gilded paradise **de-materializes** into prismatic, auroral light:
floating cloud-sea and refracting crystal, ground giving way to sky. **Palette: white / silver /
pearl / prismatic / aurora — NO gold** (gold & rainbow are reserved for the shiny variant tiers;
from Heaven 2 up the gradient deliberately moves off metal into pure light).

**The dragon rotates to Ice this time** → **Aurora Dragon** (rebirth dragon #3 of 11). And it is
the **first melee dragon** — Ice leans *control*, so the Aurora Dragon wades *in* and freezes
rather than firing from range. Dragons are always SECRET, but they are *not* always ranged.

**Rarity escalation — first Mythic apexes.** Heaven/Hell 1 topped out at Epic for the non-dragon
apexes; from layer 2 the three non-dragon apexes per realm (phoenix / ent / roc) are **Mythic** —
one rung under the Secret dragon (`…epic → legendary → mythic → secret`). Note the storage
consequence (Storage v2): a Mythic apex is an **enchant-keyed stack** (its hatch-rolled effect
splits it into its own pile), whereas the **Secret dragon is a per-uid unique** carrying
`player_class`/`hatched_by` for the rebirth gate. So the dragon stays the only true one-of-a-kind
chase per realm; the Mythic apexes are grand but farmable/stackable.

### 🔥 Fire — leans damage (coronal / white-sun light)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Coronal Cherub | Melee | Common | cool white-flame cherub, dawn-bright halo |
| Prism Lion | Melee (bruiser) | Uncommon | crystal-maned lion, refracts a light-charge |
| Lance Seraph | Ranged | Rare | lances of white sunfire from standoff |
| Lumen Salamander | Support (offense buff) | Uncommon | bathes the squad in radiant light → +damage |
| Dawnfire Phoenix | Blaster (ranged apex) | Mythic | reborn in white flame — fire's non-dragon apex |

### ❄️ Ice — leans control (aurora / prismatic) — **the dragon origin**
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Frostlight Doe | Melee | Common | crystalline frost-deer |
| Prism Fox | Control | Uncommon | refracted light that slows & binds |
| Starlight Owl | Ranged | Uncommon | aurora-arrows from the dark |
| Glacial Archon | Support (shield) | Rare | wreathes the squad in prismatic frost-light |
| **★ Aurora Dragon** | **Melee / Control (capstone)** | **SECRET** | prism-scaled dragon that wades IN — frost-breath roots & slows, claws in melee. **The first non-ranged dragon.** Heaven 2's chase + rebirth dragon #3 of 11 |

### 🌿 Grass — leans sustain/heal (bloom-light)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Bloomspirit Lamb | Support (heal) | Common | lamb of living white light |
| Lightleaf Hare | Melee | Common | swift petal-winged hare |
| Crystalbark Stag | Tank | Uncommon | crystal-antlered stag, light-armor |
| Radiant Sprite | Support (yield/luck) | Uncommon | bloom-spirit, boosts harvest |
| Worldbloom Ent | Tank / Heal apex | Mythic | towering light-tree, big HP + regen aura (grander Worldroot) |

### 🏜️ Desert — leans durable/utility (glass / radiant)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Glassling Scarab | Support (coin/yield) | Common | sun-fused glass beetle |
| Mirage Lynx | Melee (evasion) | Uncommon | light-mirage cat that dodges |
| Radiant Glass Sphinx | Tank | Rare | clear-glass guardian, refracts hits |
| Sunwell Camel | Support (regen) | Uncommon | radiant slow-heal aura |
| Empyreal Roc | Blaster (ranged apex) | Mythic | vast light-feathered bird, prism-talon dives |

**Role coverage** mirrors Heaven 1 (Tank ×4 · Melee ×5 · Ranged ×3 · Support ×6 · Control ×1–2)
+ the secret dragon. Apexes: Dawnfire Phoenix (fire), **Aurora Dragon (ice = SECRET)**,
Worldbloom Ent (grass), Empyreal Roc (desert).

## Hell 2 — "The Frozen Dark" — full pool (5 per origin, 20 + the dragon)

The second descent — and per Dante's logic, **the deeper hell goes COLD**, not hotter. Hell 1's
ash & ember **de-materializes** into black-ice and frostbitten void: lightless, sinking, the
sky raining grey-frost. **Palette: black / obsidian / black-ice / ember-on-black / sickly-violet.**
Same give→take inversion as Hell 1 — supports **drain / shred / curse** instead of heal/shield —
and every entry is a 1:1 mirror of the Heaven 2 pet in the same slot (rig re-skins).

**The dragon (Ice) mirrors heaven** → **Rimewraith Dragon** (rebirth dragon #8 of 11), likewise
**melee / control** — the black-ice twin of the Aurora Dragon.

### 🔥 Fire — leans damage (cold-fire / black frost-ember)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Frostcinder Imp | Melee | Common | imp of black cold-fire |
| Rimemane Lion | Melee (bruiser) | Uncommon | frost-charred black lion |
| Hoarfrost Phoenix | Ranged | Rare | cold-bolt volleys; rises from black frost |
| Frostbrand Salamander | Support (frostbite curse) | Uncommon | brands foes → squad deals bonus frost-burn |
| Deadfire Phoenix | Blaster (ranged apex) | Mythic | ashen-cold non-dragon fire apex |

### ❄️ Ice — leans control (black-ice / dread) — **the dragon origin**
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Rimegloom Hare | Melee | Common | frostbitten dark hare |
| Dread Fox | Control | Uncommon | spectral chill — fear/root |
| Gravefrost Owl | Ranged | Uncommon | black shards from the dark |
| Black Archon | Support (armor-shred) | Rare | fallen frost-angel strips enemy armor |
| **★ Rimewraith Dragon** | **Melee / Control (capstone)** | **SECRET** | black-ice revenant dragon — wades IN, frostbite-breath holds & freezes, claws in melee. Mirror of the Aurora Dragon (also non-ranged). Hell 2's chase + rebirth dragon #8 of 11 |

### 🌿 Grass — leans sustain (frostrot / drain)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Frostblight Lamb | Support (life-drain heal) | Common | frozen rotted lamb, leech-heals the squad |
| Gloom Hare | Melee | Common | gaunt frostbitten hare |
| Icerot Stag | Tank | Uncommon | frozen-thorned stag, spreads chill-rot |
| Rimewither Sprite | Support (wither-curse) | Uncommon | frost-blight saps foes' output |
| Frostgrave Ent | Tank / Drain apex | Mythic | frozen dead-tree, big HP + life-leech aura |

### 🏜️ Desert — leans durable/utility (black glass / frost-carrion)
| Pet | Role | Rarity | Hook |
|-----|------|--------|------|
| Frostcarrion Scarab | Support (coin-from-kills) | Common | feeds on the frozen-fallen |
| Wraithfrost Jackal | Melee (evasion) | Uncommon | black-ice mirage jackal, dodges + flanks |
| Obsidian Sphinx | Tank | Rare | black-glass guardian, sharp + durable |
| Frostdust Camel | Support (regen-denial) | Uncommon | frost-wraith stops enemy healing |
| Rime Roc | Blaster (ranged apex) | Mythic | black-frost bird, ice-talon dives |

**Role coverage** mirrors Heaven 2. Apexes: Deadfire Phoenix (fire), **Rimewraith Dragon
(ice = SECRET)**, Frostgrave Ent (grass), Rime Roc (desert).

## Layer-2 odds & base power

**`base_power` is a bounded, GLOBAL tier number — it does NOT inflate per realm.** Realm
progression comes from the **depth multiplier** (`WorldContext.difficultyFor`, ×~2 at layer 2)
applied at runtime, not from bigger base numbers. So a Heaven-2 common has the same `base_power`
as a Heaven-1 common; it just hits harder in-world. The ceiling is exclusive (50); the secret
dragon is only just above the mythic apex on paper — its real value is being the **unique
rebirth key** + depth, not raw stats.

| Tier | `base_power` | Egg weight | ≈ Odds (in pool) | Note |
|------|-----------|------------|------------------|------|
| Common | 12 | 40 | ~42% | same as Heaven 1 |
| Uncommon | 16 | 24 | ~25% each | |
| Rare | 22 | 6 | ~6% | tops the supporting cast |
| **Mythic apex** | **44** | **0.3** | **~1 in 320** | grand but farmable / enchant-stackable |
| **Secret dragon** | **46** | **0.05** | **~1 in 2,000** | per-uid unique; matches Empyrean's knob |

`huge_base_power` tracks the existing pattern (secret huge ≈ 180 like Empyrean; mythic huge ≈ 120).
Luck axis, charged hatch, and golden/rainbow gamepass multipliers all stack on top of these base
odds, same as every other egg.

**Two egg archetypes per layer** (only the dragon-origin egg carries a Secret):

- **Dragon egg — Ice / aurora_2:** Common + Uncommon ×2 + Rare + **Secret dragon (0.05)** → the
  Aurora / Rimewraith chase sits at ~1 in 2,000 (same difficulty knob as Empyrean). Per-realm
  rarity is held constant across all 11 dragons on purpose — the **all-11 self-hatch collection**
  is the real wall, not making each dragon individually rarer.
- **The other three eggs — fire / grass / desert:** Common + Uncommon ×2 + Rare + **Mythic apex
  (0.3)** → top prize is the Mythic apex at ~1 in 320. No secret in these pools.

## Deeper realms (3–5)

Heaven 3–5 / Hell 3–5 reuse this per-origin skeleton with grander forms and depth-scaled stats
(`WorldContext.difficultyFor`), continuing the de-materialize gradient (toward pure radiance up,
pure void down) and the dragon rotation: **Grass** at tier 3 (Verdant / Blight Dragon),
**Desert** at tier 4 (Gilded / Glass Dragon), and the two **pure apex dragons** at the ends —
**Seraph Dragon** (Heaven 5) and **Void Dragon** (Hell 5), the grandest of the 11.
