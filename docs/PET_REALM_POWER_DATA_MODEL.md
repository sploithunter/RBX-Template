# Pet Realm — Unified Power Data Model (plan)

Status: **PLAN** (design locked in conversation 2026-06-07; not yet implemented).
Owner decisions captured inline under "Decisions". This supersedes the fragmented power
config once migrated.

## 1. Why

A power is currently described across **four** tables, joined by id/effect-key by hand:

| Today | File | Holds |
|---|---|---|
| `powers` | `configs/powers.lua` | cost, cooldown, archetype/generic, `effect` (→ effect_kind key), display_name |
| `effect_kinds` | `configs/powers.lua` | `family` (dispatch), magnitude, duration, dot, radius, ramp… |
| badge maps | `configs/power_icons.lua` | element / symbol / ring resolution |
| blurbs | `configs/power_descriptions.lua` | tooltip desc + type override |

Consequences: a power's facts live in 4 places; "base" values are flat (no scaling layer —
only pets scale today); powers can't miss or crit even though the design doc says they should;
and bespoke art (Firestorm icon, splitting duplicate badges) has no home. **One registered
record per id** fixes all of it and gives every later feature (scaling, accuracy, pet-cast) a
single seam.

## 2. The unified `Power` record

One table `configs/powers.lua` → `powers[id]`, four logical sections. A power fills only the
fields its `kind` uses; everything else is nil and ignored.

```lua
eternal_winter = {
  --— identity / registry —--
  id      = "eternal_winter",
  name    = "Eternal Winter",
  origin  = { "pyromancer" },            -- pool membership + disc colour; {} or multi ⇒ white/generic
  kind    = { "aoe", "hold", "dot" },    -- descriptive tags (§3) — drive tooltip type line + badge
  effect  = "root",                      -- mechanics dispatch key (the _applyEffect branch)
  selectLvl = 30,                        -- unlock level (was selection_levels index)

  --— base stats (PRE-scaling; resolver applies × level/kind calc, §4) —--
  costBase      = 0,      -- focus cost
  rechargeBase  = 40,     -- cooldown s              (was cooldown_seconds)
  durationBase  = 12,     -- effect lifetime s
  damageBase    = 0.5,    -- direct/DoT damage magnitude (per tick for dot, else upfront)
  tickBase      = 1,      -- dot/hot interval s
  radiusBase    = 16,     -- AoE radius studs
  magnitudeBase = 0,      -- buff/debuff fraction (+0.5 = +50%)
  healBase      = 0,      -- hp restored (heal/hot)
  shieldBase    = 0,      -- absorb amount
  targetsBase   = nil,    -- max enemies/allies affected (nil = all in radius / single by kind)
  accuracyBase  = 1.0,    -- to-hit multiplier; 1 = always lands before the level calc (§5)
  critBase      = 0,      -- crit chance the cast itself carries (§6)

  --— visuals / assets (ALL optional — derived from origin+kind when omitted, §7) —--
  icon            = nil,  -- bespoke badge art, overrides composed disc+symbol
  ring            = nil,  -- bespoke targeting ring, overrides kind-derived ring
  sourceAnimation = nil,  -- caster anim/VFX on cast (overrides CombatFX matrix)
  targetAnimation = nil,  -- anim/VFX at target/impact (overrides CombatFX matrix)
}
```

Registry-level tables that stay (they're cross-power, not per-power): `enemy_targeted_families`,
`farm_targeted_families`, `engage_radius`. `selection_levels` folds into per-power `selectLvl`.

## 3. `kind []` taxonomy (descriptive, not dispatch)

**Decision: `kind` is descriptive.** It drives the tooltip type line and the badge (ring + which
symbol), but a single `effect` string still selects the `_applyEffect` mechanics branch. This
avoids rewriting the ~20-branch effect switch on migration day.

Tags compose from two axes:

- **targeting** → the ring: `target` (single enemy) · `ally` (single ally) · `aoe` (area) ·
  `team` (whole squad) · `self` · `farm` (crystals).
- **category** → the symbol / type words: `damage` · `dot` · `hold` · `buff` · `debuff` ·
  `heal` · `shield` · `summon` · `travel` · `luck` · `yield`.

e.g. `{"aoe","hold","dot"}` → ring=AoE, type line "AoE Hold, DoT", burns. The tooltip's existing
`deriveType` (HotbarBar) reads `kind` directly instead of reverse-engineering it from the badge.

## 4. Base → Effective resolver

New pure core `src/Shared/Game/PowerStats.lua` (+ `tests/headless/specs/power_stats.spec.luau`):

```
PowerStats.resolveEffective(power, ctx) -> effective stats table
  ctx = { casterLevel, targetLevel?, kind, augments?, buffs? }
  -- every *Base × the level/kind calc, clamped per axis (configs/powers.lua `scaling`)
```

The formula the owner specified — **`base × (player/pet/enemy level + kind) calc`** — is the
single shape for every scaled axis:

- **accuracy** → `accuracyBase × Accuracy.toHit(casterEffLevel, targetLevel, combat.accuracy)`
  (the existing `src/Shared/Game/Accuracy.lua` curve, §5).
- **damage / per-tick** → `damageBase × levelScale(casterEffLevel)` (the per-tick scaling the owner
  asked for earlier; reuses the `PowerFormula` curve shape).
- **recharge / duration / radius** → `*Base × theme/level modifiers` as configured.

**Source-agnostic caster**: `casterEffLevel` = the player's level when the player casts, the pet's
`EffectiveLevel` when a pet casts (the seam from the Accuracy work already exists). Same record,
same resolver, different `ctx.casterLevel`.

## 5. Accuracy / chance-to-miss (specced, not yet built)

Design doc requires powers can miss; only pet/enemy attacks roll it today (mining is exempt —
crystals have no level). Wire as a per-target gate inside `_applyEffect`:

```
hit = accuracyBase × Accuracy.toHit(casterEffLevel, targetLevel, combat.accuracy)
roll CombatRoll → on miss, that target gets nothing + a "Miss" tell (combat already shows these)
```

- `targetLevel` is the enemy's published Level (bakes in `rank_offset` → bosses harder to hit).
- `farm`-kind / crystal targets carry no level ⇒ auto-land (mirrors the mining exemption).
- **Decision: roll once on application** (the brand caught or it didn't), not per-tick. Per-tick
  miss is reserved for a power that explicitly opts in (`kind` tag `jitter`, future).

## 6. Crit (reserved field, future slice)

`critBase` feeds the existing `CombatRoll` crit path so a power's hit (incl. each DoT tick, if
desired) can crit. Stacks additively with the player `CritBuff` / pet `CritAura` already wired.
Inert until this slice lands; reserved now so the schema is stable.

## 7. Visuals: derive-by-default, override-per-power

The badge is *computed* today (`PetBadge.forPower`: disc←origin colour, symbol←kind, ring←targeting).
Keep that as the default; the four asset fields are **optional overrides** that win when present:

- `icon` / `ring` → bespoke badge art. **This is how duplicate badges get split** (drop an `icon`
  id on inferno_brand / mark_of_flame / wildfire — no mechanics, no remap) and how Firestorm's
  hand-drawn icon lands. No special path.
- `sourceAnimation` / `targetAnimation` → override the CombatFX matrix (which infers cast-burst +
  per-biome impact + heal skins from `element + variant`). Default = matrix; field = bespoke.

`origin []` picks the disc colour: single origin → that colour; empty/multi → white (generic tier).

## 8. Pet-cast parity

`_applyEffect(player, kind, now, powerId)` is already identity-neutral (only the Contrib loot
credit is owner-specific). The wrapper `PowerService:Cast` is player-keyed (spends focus, stamps
cooldown, reads hotbar). Split it:

- **caster identity** (whose focus/recharge is charged) — player or pet,
- **owner identity** (loot credit + squad-buff reads) — the player,

then both call the **same** `_applyEffect`. DoT, crit, accuracy, holds, the shared badge all flow
through unchanged. This is the first step of #156 (active pet powers); not required for the schema.

## 9. Migration order (each phase gated by `mise run ci` + live MCP where noted)

Strangler pattern — build the new record beside the old tables, derive the legacy shapes from it so
nothing breaks, migrate consumers one at a time, delete the adapter last.

- **P0 — Schema + resolver (pure, no behaviour change).** Author the `Power` schema (this doc) +
  `PowerStats.resolveEffective` core + spec. No wiring yet. *Gate: spec green.*
- **P1 — Registry migration + adapter.** Author the ~40 unified records. Add an adapter that
  derives the legacy `powers` + `effect_kinds` shapes from the records, so every current consumer
  (PowerService, HotbarService, ArchetypeService, PowerSelection, PetBadge, the 5 client surfaces)
  keeps working untouched. *Gate: CI + live — every power still casts identically.*
- **P2 — `_applyEffect` reads the record.** Point the effect switch at `damageBase`/`durationBase`/
  `radiusBase`/`magnitudeBase`/`dot{}` on the record instead of `effect_kinds`. `effect` stays the
  dispatch key. *Gate: cast each family live; DoT series unchanged.*
- **P3 — Scaling.** Apply `PowerStats.resolveEffective` at cast for recharge/duration/damage(per-
  tick)/radius (the owner's per-tick scaling ask). *Gate: low vs high caster level shows the curve;
  balance pass.*
- **P4 — Accuracy roll.** `accuracyBase × Accuracy.toHit` per-target gate in `_applyEffect`, miss
  tell, farm/crystal exemption. *Gate: high-level caster vs low/boss enemy shows hit-rate spread;
  crystals never miss.*
- **P5 — Crit.** `critBase` via `CombatRoll` on power hits/ticks; additive with CritBuff/CritAura.
  *Gate: crit ticks observed.*
- **P6 — Visuals unification.** Badge resolver + tooltip read the record (`kind`→ring/symbol,
  `origin`→disc) with `icon`/`ring` overrides; CombatFX honours `sourceAnimation`/`targetAnimation`.
  Retire `power_icons` flat maps + `power_descriptions` into (or sourced from) the record. *Gate:
  render-sheet; a test `icon` override displays.*
- **P7 — Pet-cast parity.** Split `Cast` into caster/owner; expose a pet-cast entry (with #156).
  *Gate: DoT/crit/accuracy fire from a pet source, credit the owner.*
- **P8 — Cleanup.** Delete the legacy adapter + dead tables once all consumers read the record;
  update wiki + this doc to "implemented".

## 10. Files

- **New:** `src/Shared/Game/PowerStats.lua` (+ spec), `docs/PET_REALM_POWER_DATA_MODEL.md` (this).
- **Reshaped:** `configs/powers.lua` (unified records + adapter, then drop adapter).
- **Edited:** `src/Server/Services/PowerService.lua` (`_applyEffect` reads record; accuracy/crit
  gates; `Cast` caster/owner split), `src/Client/UI/PetBadge.lua` + the 5 client surfaces
  (HotbarBar/CombatAuraController/SquadHud/InventoryPanel/PlayerPowerBadges → read record + overrides),
  `configs/power_icons.lua` + `configs/power_descriptions.lua` (retire/source-from-record).
- **Reused unchanged:** `Accuracy.lua`, `CombatRoll.lua`, `PowerFormula.lua`, `BuffStack.lua`,
  `PowerSelection.lua`, `configs/archetypes.lua` (pools), `configs/combat.lua` (`accuracy` cfg).

## Decisions (locked)

1. `kind []` is **descriptive** (badge + tooltip); `effect` stays the mechanics dispatch key.
2. Accuracy = `accuracyBase × Accuracy.toHit(casterEffLevel, targetLevel, cfg)`, **roll once on
   application**, farm/crystals exempt. Specced in design doc; this builds it.
3. `origin []` is an **array** — pool membership + disc colour (empty/multi ⇒ white/generic).
4. Visuals **derive by default, override per-power** (`icon`/`ring`/`sourceAnimation`/`targetAnimation`).
5. Caster is **source-agnostic** — player or pet via `ctx.casterLevel`; `Cast` splits caster vs
   owner; `_applyEffect` is unchanged by source.
6. HP/damage are **floats** (no integer scaling); minor DoT (<1/tick) is intended.
7. Migration is **strangler** — adapter derives legacy tables until every consumer is moved.

## Open (defer until building)

- Exact `scaling` curve constants per axis (damage/recharge/duration vs caster level) — a balance
  pass, set in `configs/powers.lua` `scaling` with a spec to pin the arithmetic.
- Whether `power_descriptions` blurbs move *into* the record or stay a thin side-table keyed by id.
- `targetsBase` semantics for `team`/`aoe` caps (all-in-radius vs N-nearest).
