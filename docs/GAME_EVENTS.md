# Game Events — one hook, config-driven reactions

> **Vision (Jason):** when something happens by functionality — a level changes, a death, a hit, an
> area unlock — code fires a *named event*, and **configuration** decides what reacts: audio, a
> visualization, (later) a toast or callback. They're all linked through one hook, so you change
> reactions in config without touching the firing code.

## The shape

```
code DETECTS an event ─► GameEvents.fire("level_up", ctx) ─► configs/game_events.lua[name] ─► reactions
                                                               level_up = {                    ├─ sound  ✅
                                                                 sound = "celebratory_jingle",  ├─ vfx    ✅
                                                                 vfx   = { kind="burst", ... }, ├─ toast  (todo)
                                                               }                                └─ callback (todo)
```

- **Event** = a named thing that happens (`level_up`, `area_unlocked`, …). Detecting it is the only
  inherently-code part.
- **Reaction kind** = `sound`, `vfx`, … Each kind has ONE generic handler registered in the
  dispatcher. Adding a kind makes it usable from config everywhere.
- **Binding** = `configs/game_events.lua` maps event → `{ kind = spec, ... }`. Pure config.

## Files

| Piece | Path |
|---|---|
| Event → reactions registry (config) | `configs/game_events.lua` |
| Client dispatcher (`fire` + reaction handlers + server bridge) | `src/Client/Systems/GameEvents.lua` |
| Sound catalog (referenced by `sound` reactions; each has a `bus`) | `configs/sounds.lua` |
| Server→client bridge remote | `Signals.GameEvent` (`src/Shared/Network/Signals.lua`) |
| Config-integrity guardrail | `tests/headless/specs/game_events.spec.luau` |

## How to add an EVENT SOURCE (fire it)

- **Client-detected** (an attribute changed, a UI result): `require(...Systems.GameEvents).fire("name", ctx)`.
  Examples already wired: `level_up` (ClaimedLevel increase, in `LevelUpController`),
  `area_unlocked` (ZoneUnlockResult ok, in `init.client`).
- **Server-originated** (death, hit, purchase): `Signals.GameEvent:FireClient(player, "name", ctx)`.
  The client `GameEvents.start()` bridge forwards it to `fire()`. No new service needed.

Then add the reactions in `configs/game_events.lua`. Done — no dispatcher code.

## How to add a REACTION KIND

In `src/Client/Systems/GameEvents.lua`, register a handler: `REACTIONS.<kind> = function(spec, ctx) ... end`.
Add `<kind>` to `KNOWN_KINDS` in the spec. Now any event can use `<kind> = <spec>` in config.

Current kinds:
- `sound = "<key in configs/sounds.lua>"` — one-shot on the sound's configured `bus`.
- `vfx = { kind = "burst", color = {r,g,b}?, count = n? }` — self-contained celebratory burst at the
  local player (no asset dependency). Extend with more `kind`s or route to `CombatFX`.

## Status

- ✅ Bus + dispatcher + server bridge + guardrail spec.
- ✅ Reaction kinds: `sound`, `vfx` (burst).
- ✅ Sources wired: `level_up`, `area_unlocked` (both audio + visual, config-only).
- ⏳ More sources to route — but several (`egg_hatch`, `purchase`, combat `hit`) already have ad-hoc
  reactions; migrating them onto the bus means refactoring working systems + re-tuning feel, so do it
  deliberately (with eyes on the result), not as a blind sweep.
- ⏳ Reaction kinds to add: `toast`, `callback`, and a richer `vfx` (CombatFX-backed).

## Migration worklist (hit one by one)

Legend: ✅ on the bus · 🔁 has an ad-hoc reaction today → migrate/consolidate (careful not to
double-play) · ✨ no reaction today → new opportunity · ⚠️ high-frequency → be tasteful (maybe a
float/number, not a stinger).

### Progression
- ✅ `level_up` — ClaimedLevel↑ (`LevelUpController`) — sound + gold burst
- ✅ `area_unlocked` — ZoneUnlockResult ok (`init.client`) — jingle + green burst
- ✨ `rank_up` — Soul rank segment fills ("Seasoned Soul" 2/10) — find the rank source, add fanfare
- ⚠️ `ascend_prompt` — stepping on the altar (LevelUp_OpenChoice) — optional whoosh; low priority

### Economy
- 🔁 `purchase_success` — `PurchaseSuccess` (s→c, has toast) — add sound/vfx via bus
- 🔁 `sell_success` — `SellSuccess` (s→c)
- 🔁 `economy_error` — `EconomyError` / insufficient-currency notices — error blip
- ✨ `first_purchase_bonus` — `FirstPurchaseBonus` (s→c)
- ⚠️ `currency_gain` — drop pickups — per-coin is too frequent; use coin-float (#172), not a stinger

### Eggs & Pets
- 🔁 `egg_hatch` — `EggHatchingService` (pop sound + reveal) — consolidate; don't double the pop
- ✨ `egg_hatch_rare` — rarity gate at hatch — special fanfare for rare/legendary pulls
- ✨ `new_species` — `PetIndexUpdated` (first time discovering a pet) — celebratory
- ✨ `pet_fusion` — `FusionService` success — currently no reaction
- ⚠️ `pet_equip` / `pet_unequip` — `InventoryUpdate` — minor UI blip at most

### Combat
- ⚠️ `pet_hit` — `Combat_PetHit` (s→c) — already has FX; leave (per-hit)
- ⚠️ `heal` — `Combat_Heal` (s→c) — already floats a number; leave
- ⚠️ `power_cast` — `Power_Cooldown`/`Power_AreaFx` (+ PowerSound) — already FX+sound; leave
- 🔁 `pet_down` — `CombatService:DownPetInCombat` (→ Spirit Form visual) — add a "down" sound
- ✨ `pet_revive` — Revive power / re-summon — no reaction today
- ✨ `enemy_defeated` — `EnemyService:_onDefeated` — kill confirm (watch frequency)
- ⚠️ `crystal_broken` — `BreakableSpawner` — very frequent; coin-float (#172), not a stinger

### Social
- ✅(ish) `trade_request` — TradeRequest popup — already handled
- ✨ `trade_complete` — `TradeService` "completed" — celebratory for both players
- 🔁 `enchant_result` — `EnchantPetResult` (s→c) — success/fail blip

### Meta / UI
- ✨ `achievement_completed` — `AchievementCompleted` (s→c) — fanfare + banner
- ✨ `quest_complete` — quest claim (RewardService/QuestPanel) — fanfare
- ✨ `daily_claim` — `DailyService` claim / streak milestone — chime

### Ambient
- ✅(ish) `area_change` — CurrentArea↑ → music swap (`AreaMusicController`) — optional whoosh on top
