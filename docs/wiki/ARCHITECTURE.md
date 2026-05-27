# Architecture

Status: draft

## Summary

The desired shape is a small set of authoritative services backed by validated config. Feature services should be thin; shared infrastructure should handle persistence, validation, stats, modifiers, networking, map binding, and economy auditing.

## Foundation Services

- `ConfigLoader` validates config shape and cross-references at boot. Current focused validators cover currencies, game, breakables, pets/egg sources, events, economy exchange, egg system, inventory, UI, context menus, items, and monetization.
- `DataService` owns ProfileStore data, schema versioning, migrations, durable state, stat counter storage, and currency source/sink ledger aggregates.
- `StatsService` owns declared tracked counters and emits counter change signals.
- `ModifierService` plus shared `ModifierPipeline` resolve derived values from pets, enchants, upgrades, boosts, events, rebirths, and gamepasses. Breakable rewards now route through this path, with active global events registered as a provider.
- `EconomyService` owns currency mutation and passes source reasons into the ledger.
- `ServerClockService` owns deterministic UTC day/seed behavior.
- `WorldBindingService` discovers, validates, and serves Studio map hooks. In `auto`/`synthetic` map modes it fabricates missing baseplate hooks from `configs/areas.lua` and `configs/markers.lua`.
- `ZoneService` owns area unlocks and server-authoritative `TeleportPad`/`Portal` travel. It uses `WorldBindingService` for hook/spawn lookup and persists area unlock state through `DataService.GameData.UnlockedAreas`.
- `UpgradeService` owns config-driven permanent upgrade purchases. Levels persist under `DataService.Upgrades`; equip/storage effects feed inventory limits, and modifier effects register as `permanent_upgrades` providers.
- Phase 2 player actions use central `Signals` remotes: `PurchaseUpgrade`, `UpgradeResult`, `UnlockZoneRequest`, `ZoneUnlockResult`, and `ZoneTravelResult`. Service methods remain the authority; remotes are thin request/result bridges for future UI.
- `StudioSmokeTestService` is a Studio-only test bridge. It exposes controlled server-authoritative smoke-test actions to MCP/client runners and must remain disabled outside Studio.

## Gameplay Services

Planned services include upgrades, achievements, leaderboards, pet index, rebirths, enchants, auto-delete, rewards, Pet of the Day, chaseables, stock, and marketplace. Existing services already cover breakables, eggs, inventory, zones, auto-targeting, admin tools, basic events, and core economy.

## Resolution Rule

Any derived gameplay number should flow through one ordered modifier pipeline. Feature services should not each invent their own multiplier math.

## State Rule

Workspace instances are presentation and map hooks, not state of record. Durable state belongs in profiles. Temporary authoritative state belongs in explicit server services.

## Phase 0 Notes

Feature flags exist in `configs/game.lua`, `ConfigLoader:IsFeatureEnabled`, and server boot registration for safe optional modules. Keep future feature services behind the same flag pattern. `features.map_binding` is enabled for Phase 1.

## Links

- [Implementation Plan](../IMPLEMENTATION_PLAN.md)
- [Current Status](CURRENT_STATUS.md)
- [Map Integration Contract](MAP_INTEGRATION_CONTRACT.md)
