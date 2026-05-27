# Wiki Log

Status: current

## 2026-05-26

- Created the project wiki using the LLM Wiki pattern: source docs stay as source material, while `docs/wiki/*.md` stores compact synthesized project memory.
- Added root `AGENTS.md` so future coding agents know to read and update the wiki.
- Captured current status, durable decisions, architecture shape, map integration contract, reference game insights, and open questions.
- Source inspiration: Andrej Karpathy's LLM Wiki gist and the lightweight Markdown/raw/wiki/schema pattern.
- Began Phase 0 implementation with boot-time config validation in `ConfigLoader`, plus validators and unit specs for core gameplay config cross-references.
- Continued Phase 0: added profile `SchemaVersion`, additive migration ladder, `configs/stats.lua`, `StatsService`, stat counter persistence, currency ledger aggregates, `ModifierPipeline`, `ModifierService`, and feature flags in `configs/game.lua`.
- Finished Phase 0 foundation pass: added deterministic UTC day/seed helpers, boot-time optional module gating for Phase 0 feature flags, active global events as a modifier provider, breakable reward resolution through the modifier pipeline, and fixed pet ability config references caught by Studio startup validation.
- Enabled and verified Roblox Studio MCP for Codex. Studio Assistant settings now have `Enable Studio as MCP server` on, Codex quick connect is enabled, `RBX-Template` is the active Studio instance, and MCP calls can read Output, capture screenshots, and start/stop play.
- Wrapped Phase 0 verification: wiki status passes, Rojo 7.6.1 build passes, Selene passes with warnings, Studio MCP smoke test passes, and StyLua check remains a known formatting cleanup lane.
- Began Phase 1 map integration: added `configs/areas.lua`, `configs/markers.lua`, `WorldBindingService`, config validation for areas/markers, Rojo Workspace scoping for authored maps, and `BreakableSpawner` lookup through bound `SpawnZone` hooks.
- Verified Phase 1 synthetic baseline in Studio through MCP: `Zone=3`, `AreaZone=1`, `SpawnZone=1`, `EggStand=2`, `PODPodium=1`, with the core loop still running on the baseplate.
- Added and verified ConfigLoader unit coverage for the Phase 1 area tree and marker schema contract so missing parents, cycles, and unsupported marker attribute types fail before Studio startup. Also fixed a brittle monetization mock in the spec; `ConfigLoader.spec` now passes in Studio.
- Captured the automated travel-test direction: drive tests through invisible tagged `TeleportPad` / `Portal` markers, optionally attach visual gate assets from config, and use Studio MCP character movement plus assertions for full-loop verification.
- Captured egg proximity as a required Studio MCP smoke-test lane: move the character far/near egg stands, verify UI target state, server distance rejection, currency changes, and inventory/pet grants.
- Implemented `StudioSmokeTestService` and `tests/studio/EggProximitySmoke.lua`. Verified through Studio MCP that a far basic-egg hatch is rejected, a near hatch succeeds, currency/pet inventory changes are detected, and the player's original currency/pet bucket is restored.

## 2026-05-27

- Finished the Phase 1 map integration pass: added configured `Meadow`, generated multi-area `TeleportPad`/`Portal` hooks, added `ZoneService` for persisted unlocks and server-authoritative travel, and wired active-area updates through `WorldBindingService`.
- Added active-zone dormancy for breakable spawning. Spawn remains live for the base loop; Meadow stays empty until travel/entry activates it, then fills to its configured max.
- Added `tests/studio/TravelSmoke.lua` and extended `StudioSmokeTestService` with travel smoke actions. Verified locked travel rejection, unlock, movement to Meadow, active-area update, state restoration, and Meadow spawner activation through Studio MCP.
- Re-ran egg proximity smoke after travel work; near/far hatch behavior and restoration still pass.
- Captured a balance direction from the reference game: traded/gifted high-power pets should be normalized by player/area progression, while forever/eternal pets can stay valuable by scaling as a percentage of the player's current best relevant power instead of using a fixed endgame stat.
- Began map-readiness work for authored maps: added `scripts/studio/create_reference_map.luau`, `docs/AUTHORED_MAP_WORKFLOW.md`, and `tests/studio/MapContractSmoke.lua`; generated a tiny authored `Spawn`/`Meadow` reference map in Studio.
- Fixed `WorldBindingService` so existing authored `TeleportPad`/`Portal` source-target pairs suppress duplicate synthetic travel hooks. Verified authored-only markers with `MapContractSmoke`, then re-ran `TravelSmoke` and `EggProximitySmoke` successfully on the authored reference map.
- Added map-derived spawn safety: `ZoneService` now places newly spawned characters through `WorldBindingService` floor raycasts instead of relying only on config coordinates. Added `tests/studio/SpawnSafetySmoke.lua` and verified Spawn placement, authored marker contract, travel, and egg proximity through Studio MCP.
- Started Phase 2 economy-depth implementation: added `configs/upgrades.lua`, `UpgradeService`, upgrade config validation, additive profile `Upgrades` migration, server-side inventory limit integration, paid Meadow unlock cost, stronger Meadow breakables, and `tests/studio/Phase2ProgressionSmoke.lua`. Fixed breakable rewards to resolve per player so permanent upgrades can affect mining payouts. Verified `ConfigLoader.spec` (`33` passed), Phase 2 smoke including `crystalReward=100->110`, and existing spawn/map/travel/egg smokes in Studio.
- Added thin Phase 2 network bridges for upgrade purchases, zone unlock requests, and travel results through `src/Shared/Network/Signals.lua`. Locked-zone responses now carry the configured unlock requirement payload for UI/admin panels.
- Added `tests/studio/SyntheticExpansionSmoke.lua` plus a Studio-only smoke action that temporarily injects a second synthetic world/area, verifies cross-world portal generation and travel to `CrystalCavern`, and restores authored marker attributes/properties afterward. Verified the synthetic smoke and then authored-only `MapContractSmoke` (`synthetic=0`) to catch restore leaks.
- Completed Phase 2 for the current baseline. Added full-loop Meadow breakable smoke coverage: `BreakableSpawner` now has a Studio-only deterministic spawn helper, and `MeadowBreakableSmoke` proves unlock/travel to Meadow, `BigBlueCrystal` spawn, contribution-based break reward, `crystal_value` modifier payout, `breakables_broken` stat increment, and profile restoration. Re-ran synthetic expansion, authored map contract, Phase 2 progression, spawn safety, travel, and egg proximity smokes successfully.
