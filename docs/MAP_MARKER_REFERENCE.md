# Map Marker Reference

This project treats Studio-authored maps as geometry plus invisible gameplay hooks. Rojo owns scripts and config; Studio owns the world. The handoff is CollectionService tags plus Instance attributes.

## Required Tags

| Tag | Required Attributes | Optional Attributes | Purpose |
| --- | --- | --- | --- |
| `Zone` | `ZoneId`, `Kind` | `ParentZoneId` | World/island/area grouping zone. `Kind` is `world`, `island`, or `area`. |
| `AreaZone` | `AreaId` | `ParentZoneId` | Gameplay area volume. Player enter/exit events are centralized here. |
| `SpawnZone` | `AreaId`, `SpawnerId` | `DepthOffset`, `MaxCountOverride` | Breakable/collectible spawn volume. Current crystal spawner uses `SpawnerId = "spawn_crystals"`. |
| `TeleportPad` | `AreaId`, `TargetZoneId` | none | Area-to-area travel hook. |
| `Portal` | `ZoneId`, `TargetZoneId` | none | World/island travel hook. |
| `EggStand` | `EggId` | `AreaId`, `SpawnId` | Egg placement hook. The legacy egg spawner also accepts a part named `EggSpawnPoint`. |
| `EnchanterStation` | `EnchanterId` | `AreaId`, `TouchPartName`, `AnimationRootName` | Map-built pet enchant/reroll station. `EnchanterId` references `configs/enchants.lua` `stations`; `TouchPartName` points at the child part players touch/prompt against. |
| `PODPodium` | none | `AreaId`, `Slot` | Pet-of-the-day display anchor. |
| `ChaseableRegion` | `AreaId`, `ChaseableId` | none | Future chaseable spawn region. |
| `ShopAnchor` | `AnchorId` | `AreaId` | Shop or UI world anchor. |
| `NPCAnchor` | `AnchorId` | `AreaId` | NPC placement anchor. |

## Config Source

- Marker schemas live in `configs/markers.lua`.
- Zone and area ids live in `configs/areas.lua`.
- Breakable world ids currently mirror area ids in `configs/breakables.lua`.
- Egg ids are read from `configs/pets.lua` under `egg_sources`.
- Enchanter ids are read from `configs/enchants.lua` under `stations`.

## Current Synthetic Baseline

`configs/game.lua` sets `map.mode = "auto"` and `features.map_binding = true`.

With no authored tagged map present, `WorldBindingService` creates:

- `Zone` hooks for `spawn_world`, `spawn_island`, `meadow_island`, `Spawn`, and `Meadow`;
- `AreaZone` hooks for `Spawn` and `Meadow`;
- `Workspace.Game.Breakables.Crystals.<AreaId>.SpawnArea` tagged as `SpawnZone`;
- two `EggStand`/`EggSpawnPoint` hooks for `basic_egg` and `golden_egg`;
- per-area `PODPodium` hooks;
- bidirectional `TeleportPad` hooks between `Spawn` and `Meadow`;
- bidirectional `Portal` hooks between `spawn_island` and `meadow_island`.

Current verified play-mode hook counts are `Zone=5`, `AreaZone=2`, `SpawnZone=2`, `EggStand=2`, `PODPodium=2`, `TeleportPad=2`, and `Portal=2`.

Feature services should bind through `WorldBindingService` when possible. Legacy folder/name lookups should remain fallback paths while older systems are migrated.

Breakable spawners honor active-zone dormancy. Spawn is live for the starter loop; non-default areas such as Meadow do not fill until a player enters or travels there.

## World Builder Rule

For an authored map, place invisible parts with the tags and attributes above. Visual names can change freely. Behavior must remain stable as long as the tags, attributes, and declared contracted names remain intact.

For the current imported enchanter, `scripts/studio/tag_enchanter_station.luau` can tag `Workspace.Enchanter`, set the required attributes, preserve cosmetic floating scripts, and disable the old copied touch gameplay script.
