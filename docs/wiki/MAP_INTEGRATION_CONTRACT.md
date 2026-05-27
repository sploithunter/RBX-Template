# Map Integration Contract

Status: current

## Summary

The map can be hand-built in Studio, but gameplay systems must bind to stable hooks. The contract is CollectionService tags, attributes, and a few declared child-marker names. This lets a world builder reshape the map without rewriting services.

## Ownership

Rojo owns:

- `src/`
- `configs/`
- UI and networking code
- validation and admin tools
- server/client behavior

Studio owns:

- Workspace geometry
- terrain and decorations
- invisible zones and spawn volumes
- portals, pads, stands, podiums, and anchor placement

## Canonical Hooks

- `Zone`
- `AreaZone`
- `SpawnZone`
- `TeleportPad`
- `Portal`
- `EggStand` or contracted names like `EggStand_Basic`
- `PODPodium` or contracted names like `PetDisplay_Podium`
- `ChaseableRegion`
- `ShopAnchor` / `NPCAnchor`

## Rules

1. Every gameplay area has a stable id.
2. Every gameplay object is discoverable by tag, attribute, or contracted name.
3. Services do not use hardcoded coordinates or fragile Workspace paths.
4. Startup validation reports missing or invalid hooks precisely.
5. New areas require config plus Studio markers, not core code changes.

## Synthetic Fallback

If no authored map exists, or if `map.mode = "synthetic"`, `WorldBindingService` should fabricate valid zones, spawn volumes, egg stands, portals, teleport pads, and displays from config. Feature services should not know whether hooks were authored or synthesized.

## Current Implementation

`configs/areas.lua` declares the starter zone tree:

- `spawn_world -> spawn_island -> Spawn`
- `spawn_world -> meadow_island -> Meadow`

`configs/markers.lua` declares marker schemas for canonical hooks. `WorldBindingService` validates those configs, detects authored hooks, and synthesizes missing hooks in `auto`/`synthetic` modes.

For authored-map tests, `scripts/studio/create_reference_map.luau` creates a tiny Studio-owned `AuthoredReferenceMap` with the same `Spawn`/`Meadow` contract. `tests/studio/MapContractSmoke.lua` verifies whether the live hooks are authored or synthetic.

The current synthetic baseline creates:

- `Zone` hooks for `spawn_world`, `spawn_island`, `meadow_island`, `Spawn`, and `Meadow`;
- `AreaZone` hooks for `Spawn` and `Meadow`;
- `SpawnZone` hooks for `spawn_crystals` at `Workspace.Game.Breakables.Crystals.<AreaId>.SpawnArea`;
- two `EggStand` hooks that also satisfy the legacy `EggSpawnPoint` search;
- `PODPodium` hooks for each area;
- bidirectional `TeleportPad` hooks between `Spawn` and `Meadow`;
- bidirectional `Portal` hooks between `spawn_island` and `meadow_island`.

`BreakableSpawner` now asks `WorldBindingService` for `SpawnZone` parts before falling back to legacy child-name scanning.

`ZoneService` consumes the zone tree plus bound `TeleportPad`/`Portal` hooks. It validates unlocks on the server, persists `GameData.UnlockedAreas`, moves the character to the target zone spawn, and updates the active area through `WorldBindingService`.

Spawn placement is resolved from the live map before falling back to configured synthetic coordinates. `WorldBindingService:GetSpawnCFrameForZone` uses the area's authored `AreaZone` center, raycasts down to real floor geometry while excluding marker parts, and returns a safe above-floor CFrame. If no floor hit is found, it falls back to the area's `SpawnZone`, then finally to config `synthetic.spawn_position`. This keeps Studio-authored maps portable when islands move.

Active-zone dormancy is implemented for breakable spawning: Spawn is live for the starter loop, while non-default configured areas stay dormant until a player enters/travels there. Entering/traveling to an area fills that area's configured spawner.

When authored `TeleportPad`/`Portal` hooks already exist for a source/target pair, `WorldBindingService` does not create duplicate synthetic travel hooks.

## Links

- [Foundation & Requirements K8](../FOUNDATION_AND_REQUIREMENTS.md)
- [Implementation Plan Phase 1](../IMPLEMENTATION_PLAN.md)
- [Map Marker Reference](../MAP_MARKER_REFERENCE.md)
- [Decisions](DECISIONS.md)
