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
