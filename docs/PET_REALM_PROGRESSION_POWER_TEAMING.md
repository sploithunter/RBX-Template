# Pet Realm — Progression, Power & Teaming Design

> Companion to `PET_REALM_DESIGN_DOCUMENT.md`. Captures the power/level/teaming model worked
> out in design discussion. This is the spec the accuracy curve (first build) and everything
> after it bind to. Everything here is **config-as-code** — every number a dev knob.

---

## 0. Context

Two flat spots surfaced: **accuracy** was a flat 8% miss regardless of target, while **damage**
already scaled by level + rank (asymmetry to fix). And **pet power** had never been scaled, so we
can set the rules *before* power creep forces our hand. Out of that came a unified model: three
identity numbers, one shared combat curve, and a bounded "pets-are-stars" power system that can't
trivialize the level ladder. This doc pins all of it.

---

## 1. The three identity numbers

A player is described by three orthogonal numbers. **Never conflate them.**

| Number | What it means | Drives | Teaming effect |
|---|---|---|---|
| **Effective Level** | combat strength | the level-diff curve (accuracy + damage), enemy con colours, pet *realization* | **synced** while teamed (sidekick up / exemplar down) |
| **Claimed Level** | what you've earned | powers, pets, equip/power slots, egg-hatch | never changed by teaming |
| **Soul** | which side (Halo↔Horns) | realm access + the heaven/hell gates | never changed by teaming (guests earn none) |

- **Effective Level** = normally your own level; overridden by team-sync. **Every combat curve
  reads Effective Level**, so sidekick/exemplar/solo all flow through one value.
- **Entitlement level = `min(Claimed, Effective)`** — exemplar *down* claws back slots/powers
  (CoH-style); sidekick *up* never grants powers you haven't earned.
- Already built: the level system splits **earned** (XP-derived, combat/egg) from **claimed**
  (entitlements). Effective Level is the combat one with a team-sync override layered on.

---

## 2. Accuracy & damage curve (FIRST BUILD)

**Today:** pet attacks are a flat `hit_chance = 0.92` (8% miss) with **no level/rank variation**
— and the roll isn't gated, so **mining whiffs 8% on inert crystals** (a bug). Damage, by
contrast, already scales: `LevelScale.factor` = ±8%/level (clamp 0.3–2.5), enemies spawn at
`effectiveLevel(base, rank_offset)` (trash +0 / lieutenant +1 / boss +2), and armor mitigates on
the `k/(armor+k)` curve (boss ~70%).

**Fix — bring accuracy to parity with damage, reusing the same inputs:**
- A pure `Accuracy` resolver: `toHit(effAtkLevel, targetLevel, targetRank, cfg)` →
  `base_to_hit` × level-diff "purple-patch" step × rank penalty, clamped `[floor, cap]`.
- **Combat** (enemy target) → full curve. **Mining** (no `EnemyId`, no level/rank) → `mining_hit_chance = 1.0` (crystals never dodge; crit stays as an upside). This also **fixes the
  8% mining whiff**.
- Build it to read **`EffectiveLevel(player)` from day one** — today it returns your real level
  (nothing changes); teaming later just makes that accessor return the synced value and **every
  curve picks it up for free**.

Config sketch (`combat.lua accuracy`):
```
base_to_hit = 0.92, per_level_step = 0.04, floor = 0.05, cap = 0.95,
rank_to_hit = { trash_mob = 0, mid_tier = -0.05, boss = -0.10 },
mining_hit_chance = 1.0,
```

---

## 3. World structure & gating (heaven/hell — two axes)

- **Geometry:** a 4-biome surface ring + **5 Heaven layers** + **5 Hell layers**, each layer the
  4-biome ring re-themed = **44 areas** (reskins, not 44 bespoke maps). A single run traverses
  *surface + one direction* ≈ 24 areas → ~**2 player levels per area** to cap (50).
- **Two gating axes, paced differently:**
  - **Depth (the layers) → LEVEL-gated** (`requires_level`, ~5 levels/layer) + the existing
    `requires_soul` + `token_cost`. "Level decides how deep."
  - **The ring (4 biomes per layer) → CURRENCY-gated** (the existing grind). "Coins decide how
    wide."
- **Side separation is Soul, not level** (this is the key insight): Heaven layers need **soul ≥
  +20/+40/+60/+80/+100**, Hell layers **≤ −20…−100**, paid in **light_tokens / shadow_tokens**
  (non-tradeable). A maxed Horns player clears every *level* gate but is **hard-locked out of
  Heaven** by soul sign + having the wrong tokens (and a side's tokens are only earned *on* that
  side — chicken-and-egg by design).
- **"No easy way up" = the Soul ratchet.** Soul polarizes with conquest; the **surface is the
  only neutral crossing point**. Retreat-to-surface is always free; crossing to the *opposite
  deep realm* requires re-aligning Soul across zero (~24 conquests) and earning the new side's
  tokens from scratch — a deliberate **fall/redemption arc**, not a portal hop.
- **Pacing rule:** area at depth D spawns enemies ≈ level **2D**; arriving on-level = even-con,
  the level-diff curve soft-walls under-levelling and trivializes over-levelling. (Currently
  built: cap 50, layers config has 3/side + soul + token gates — to expand to 5/side + add the
  `requires_level` third gate.)

---

## 4. Teaming — guest pass + sidekick/exemplar

> **One rule: teaming syncs the POWER axis (Effective Level + XP); it never grants the SIDE axis
> (tokens / soul / realm-progress).**

- **Guest pass:** while partied with a *resident* of a realm you can't access, you ride in as a
  **guest** — present, fight, earn **XP** — but **zero tokens / soul / conquest**, can't use that
  realm's altar/shop/eggs, your alignment untouched, access lapses when the host leaves (graceful
  auto-recall to surface). The angel walks Hell at the demon's side and gains nothing but the
  fight (and a small **"Arrangement" buff** for cross-aligned teams).
- **Sidekick / exemplar (both):** **lead-anchored** — the team's Effective Level = the host's
  (NOT the highest; "highest dictates" invites passive carries/exploits). Low members sidekick
  *up* to lead−1; high members exemplar *down* to the lead. Reuses the level-diff curve (sync the
  effective level → the curve does the rest). Exemplar also claws back slots/powers via
  `min(Claimed, Effective)`.
- **Why it can't be gamed:** a low Halo + high Horns in Hell — the low player fights at tier
  (survives) but with his own low kit, earns XP only, **no** shadow tokens / soul / Halo
  progress, and **no** high-level entitlements. He plays; he doesn't *become*. (Non-tradeable
  side-tokens already block handing keys across.)

---

## 5. Pet power model — pets are stars, but bounded

> **Realized power = `Baseline(EffectiveLevel vs pet tier) × PetMultiplier × situational(buffs /
> auras / element)`.** The pet is the headline number and the chase; **Effective Level gates how
> much of it is realized**; a hard ceiling caps the top.

- **Pets are the star** (this is a pet game — diverging from CoH's player-centric model), but with
  **hard caps**, so a god-pet on a low player can't break the curve: it realizes only at *their*
  baseline and **blooms as they level**. This is exactly what makes a rare/dream hatch *safe* in a
  noob's hands.
- **Acquisition is world-gated:** strong pets only hatch **deep** (behind level + soul). The only
  leak is trade — handled by the realization gate (an over-tier traded pet under-performs until you
  grow into it).
- **Numbers = integers for display** (Roblox is float64 underneath; compute in float, display
  rounded). **Start base high (~1,000)** so per-tier steps don't round-collide; use K/M suffixes
  past thousands.
- **Tier curve, not hand-authored numbers:** `power = tierBase(layer/rarity) × variant × aptitude`,
  `tierBase` geometric (~1.3–1.5×/tier, ~25–35 tiers). Thousands of ordered, collision-free,
  progressing pets from a tiny config. Adjacent tiers ≥ ~25–40% apart so each reads as an upgrade.
- **Hard ceiling = the Creator value, code-enforced:** a single `max_pet_power` clamp in the
  resolver. Nothing — huge, titanic, colossal, anything — can exceed it. Proposed apex ≈ **1,000,000** (TBD at balance); starter ~1,000.
- Variant multipliers: basic 1.0 / golden 1.5 / rainbow 2.5 (existing `pet_power.lua`).
- The **⛏ mining / ⚔ combat** aptitude split (already shipped) drives specialists → the trading
  economy. Element matchups (resonance) + support/buffers add team-comp depth.

---

## 6. Pet identity — five orthogonal axes

| Axis | Values | Role |
|---|---|---|
| **Species** | colorado, bear, penguin, … | base power + aptitude split |
| **Variant** | basic / golden / rainbow | multiplier (1.0 / 1.5 / 2.5) + look |
| **Size** | normal / huge / titanic / colossal | bounded prestige ladder, all **under** the cap |
| **Class** | normal / **Creator** | Creator = the apex cap + permanently untradeable |
| **Shiny** | yes / no | **cosmetic prestige only** (`shiny_mult = 1.0`, never balance) |

`huge` stays a normal, meaningful multiplier; the apex is **not** "a huge," it's its own **Creator
class** (decoupled from size math).

---

## 7. Creator & Meet-the-Creator pets + Shiny

- **Creator class** = the apex (`max_pet_power`), e.g. **Creator Rainbow Colorado**.
  - **Creator accounts only** — a `creators = { <userId>, … }` allowlist (just the dev now;
    extensible to teammates). Players can never obtain one.
  - **Untradeable, always, hardcoded** (intrinsic to the class — not a flippable flag). The
    absolute ceiling cannot leak.
  - It's the dev flex *and* the balance/test anchor: held by a creator at level 50, it measures
    max-power pacing; content is tuned knowing players can't reach it. Player's *real* ceiling =
    the top **normal-class** pet.
  - `Creator` is an **extensible class** (future creators' apexes tie at the cap), with the
    Rainbow Colorado as flagship.
- **Meet-the-Creator pet** (the player memento, kept from Colorful Hatchers):
  - Granted **once ever per player** (a profile flag) when an allowlisted **creator joins the
    server**; auto-hatches.
  - **Normal odds** (the regular egg config) — can roll **huge / golden / rainbow** like any pet
    (a huge-rainbow MtC is its own grail).
  - **Always shiny** (its defining exclusive trait), and **tradeable** — a circulating prestige
    collectible whose supply is throttled by how often creators actually show up.
- **Shiny** = a new **5th orthogonal trait**, **power-neutral** (sparkle/VFX only). `base_chance =
  0` for now → the *only* shiny source today is the Meet-the-Creator egg, so "shiny" literally
  reads as "you met the Creator" until/unless shiny odds are sprinkled elsewhere.

---

## 8. Open knobs (set at the balance pass)

- Accuracy curve: `per_level_step`, rank penalties, floor/cap.
- Pet ceiling magnitude (Creator value), tier step %, tier count, starter base.
- Pet-multiplier band width vs Effective-Level baseline weight (how "star" vs "gated").
- `requires_level` thresholds per layer; soul thresholds for layers 4–5; reward multipliers.
- Meet-the-Creator hatch rates (huge/golden/rainbow chances).
- Sidekick XP scaling (power-level pace) — side-progress stays resident-gated regardless.

---

## 9. Already built (so this binds to real code)

- Level cap 50; claimed/earned split; claimable level-up + Ascension Altar (hybrid: filler
  auto-claims, training claimed at the altar); +1 egg-hatch/level.
- Pet caps raised to **10 equip + 10 active**; **10 power picks** across `{3,7,11,15,19,24,29,34,40,46}`.
- Soul/alignment (`soul.lua`, `AlignmentService`), layers (`layers.lua`, 3/side + soul + token
  gates), `light_tokens`/`shadow_tokens` (non-tradeable).
- PetPower resolver + `pet_power.lua` (variant mults, context placeholders), ⛏/⚔ aptitude split.
- LevelScale (damage curve) + enemy rank/armor; CombatRoll (the flat hit roll to replace).
