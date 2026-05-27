# Current Status

Status: current

## Summary

This is a Rojo Roblox pet/clicker project being upgraded toward a config-as-code template. Phase 0 is complete, Phase 1 map integration is complete for the current synthetic/partial-authored baseline, Phase 2 economy depth is complete for the current baseline, and Phase 3 stats-derived wins are complete for pet index, achievements, and live leaderboards. The repo is ready to continue Phase 4 work; a first Phase 4 foundation slice already exists for unique-pet progression, enchant-slot unlocks, eternal/huge pet handling, config-only pet power, and offline team-power balancing. The playable loop includes breakable crystals, coin generation, eggs, hatching, persistent player data, imported pet assets, an admin panel, configurable currency conversion, basic global events/effects work, multi-area map hooks, server-authoritative area travel, active-zone spawner dormancy, config-driven upgrades, paid area unlocks, area-gated stronger breakables, first-time pet indexing, achievement rewards, and K1-backed leaderboards.

## Working Systems

- Rojo project builds and lints.
- Roblox Studio sync workflow is active.
- Data saving works after enabling Studio API access and saving the experience to Roblox.
- Breakable crystal spawners are present and visually tuned on the baseplate.
- Coin generator exists so testing can fund egg hatching.
- Eggs can hatch pets from configured asset ids.
- Original reference bear asset was restored for style consistency.
- Rainbow pet visual effect exists and applies to models such as Rainbow Bear.
- Admin control panel opens and includes event/effects testing commands.
- Global event support has started, including scheduled event concepts and a UTC event clock.
- `ConfigLoader` now validates all loaded configs at startup and has focused validators for core gameplay configs.
- Phase 0 foundation services are in place for profile schema versioning, stat counters, modifier resolution, currency ledger aggregation, deterministic UTC day/seed behavior, and feature flags.
- Studio Play boots successfully through the validated config loader; current remaining Output noise is warning-level placeholder/test data such as monetization ids and unknown legacy saved effects.
- Roblox Studio MCP is enabled and connected to Codex. Agents can now read Output, capture Studio screenshots, start/stop play, inspect the game tree, execute Luau, and read/edit Studio scripts through the official Studio MCP bridge.
- Phase 1 now has `configs/areas.lua`, `configs/markers.lua`, `WorldBindingService`, `ZoneService`, synthetic multi-area baseplate hooks, server-authoritative `TeleportPad`/`Portal` travel, and `BreakableSpawner` binding through `SpawnZone` when available.
- Synthetic `Spawn` and `Meadow` areas are configured. Spawn stays live for the starter loop; Meadow breakable spawning stays dormant until a player travels/enters it.
- Authored reference-map readiness exists: `scripts/studio/create_reference_map.luau` creates a tiny Studio-owned `Spawn`/`Meadow` marker map, and `tests/studio/MapContractSmoke.lua` verifies the live marker contract.
- `default.project.json` now keeps unknown Workspace instances, so Rojo sync does not delete designer-authored map geometry.
- Studio-only automated smoke testing has started with `StudioSmokeTestService` and `tests/studio/EggProximitySmoke.lua`.
- Spawn placement is now map-derived: `ZoneService` places characters at the active area's authored floor/`SpawnZone` through `WorldBindingService`, so the player does not fall when the Studio-owned map is offset from config defaults.
- `configs/upgrades.lua` and `UpgradeService` now provide permanent upgrades for pet equip slots, pet storage, and crystal reward value. Upgrade levels persist under `DataService.Upgrades`; inventory slot limits read the upgrade effects server-side.
- `Meadow` now has a paid unlock cost of `100 crystals`, and its breakable table includes stronger medium/big crystals. This is the first area-gated Phase 2 progression step.
- Phase 2 network bridges exist for UI/admin work: `PurchaseUpgrade`/`UpgradeResult`, `UnlockZoneRequest`/`ZoneUnlockResult`, and `ZoneTravelResult`. Locked-zone results include the configured unlock requirement payload.
- Pet inventory storage is already mixed: normal pets stack under `Inventory.pets.items["petId:variant"]` with a quantity, while special pets are individual records. Equipping a stacked pet creates an ephemeral equipped id and temporarily decrements the stack quantity.
- Phase 3 configs are live: `configs/pet_index.lua`, `configs/achievements.lua`, and `configs/leaderboards.lua`.
- `PetIndexService` records first-time pet/variant acquisition under `DataService.PetIndex`, increments/syncs `distinct_pets`, and grants index milestones once.
- `AchievementsService` listens to `StatsService.CounterChanged`, evaluates config tiers over K1 counters, stores completed tiers under `DataService.Achievements.Completed`, and grants rewards once.
- `LeaderboardService` builds in-server live boards from K1 counters and has a throttled OrderedDataStore path for global boards when config enables it.
- Inventory now allows adding to an existing pet stack even when storage slots are full, because existing stacks do not consume new slots.
- Admin tools now include zone lock testing controls. Developers can toggle, lock, paid-unlock, or bypass-unlock `Meadow` from the admin panel, and custom zone lock input supports future `zoneId:toggle|lock|unlock|bypass` testing.
- Locked portal/pad travel now shows a player-facing notice with the target area's unlock cost instead of only logging `ZoneTravelResult`. Travel hooks also have `ZoneTravelPrompt` proximity prompts for paid locked gates, and the client hides those prompts once the local player owns the destination so unlocked travel stays touch-only.
- Pet config now supports imported asset transform metadata. `asset_transform.scale` normalizes a model's default size, `asset_transform.orientation` fixes imported facing in degrees, and `asset_transform.huge_scale` controls the runtime size multiplier for pets stored with the `huge` trait.
- The Colorado Plays creator pet is configured from two Roblox model assets: normal/rainbow use `100466492312776`, golden uses `121192248833075`. Admin tools can grant basic, golden, rainbow, or huge Colorado for scale/orientation testing.
- `PetGrantService` now centralizes pet grants for hatching, admin tools, and Studio scripts. `PetSerialService` allocates global huge serial numbers before the pet is inserted into inventory, so future trading can preserve the entire unique pet record.
- Colorado Plays is currently an eternal pet family. Equip rebuilds cache team-relative `EffectivePower` from the configured eternal percent and top-team-average baseline, while preserving the pet's configured power as the minimum. Huge pets clamp to at least `100%` of that baseline. Inventory pet hover details now show power, base power when different, eternal percent, baseline, huge serials, enchant capacity, and stack count.
- Enchant capacity is now controlled by pet rarity config: Mythic pets get `1` slot, Secret/Exclusive pets get `2`, and Huge pets get `3`. Rarities with enchant slots are granted as unique pet records going forward; existing stacked pets are not retroactively promoted until a future stack-to-unique promotion flow exists.
- Phase 4 pet progression has a first foundation slice: `configs/pet_progression.lua` and `PetProgressionService` define unique-pet XP curves, max levels by rarity, capped power growth, and enchant slot unlock milestones. New unique pets keep their full potential `max_enchantments` but start with configured `unlocked_enchant_slots` (currently one slot) and gain the rest through levels.
- `scripts/balance_team_power.py` is available for offline balance passes. It reads current pet/progression configs and estimates team power across team size, pet level, eternal/huge rules, and optional player level/XP power assumptions before those assumptions are committed to gameplay code.
- Huge-and-above provenance is now captured as separate hatcher metadata. Future grants stamp `hatcher_name`/`hatcher_user_id` for pets meeting the configured provenance threshold; `grant_source` remains non-displayed audit data. `tests/studio/BackfillPetHatcherProvenance.lua` can backfill existing qualifying pets for the current Studio player.
- Pet tooltip metadata visibility is driven by `configs/inventory.lua` `tooltip_fields`, so fields can be hidden, labeled, or ordered without editing `InventoryPanel`.
- Pet inventory cards now distinguish rarity/specialness and variant separately. Rarity rings are config-driven and can animate around the card using a `UIGradient`; the default rarity ladder currently includes Common, Uncommon, Rare, Epic, Legendary, Mythical, Secret, Exclusive, and Huge. Variant backgrounds are also config-driven, including darker gold and rainbow fills. Inventory display reads rarity names/colors from `configs/pets.lua`.
- Generated pet/egg thumbnails are cached as ViewportFrames, not uploaded image assets. `AssetPreloadService` publishes `PetThumbnailsReady`, `PetThumbnailCount`, and `PetThumbnailFailures` on `ReplicatedStorage.Assets`; the Studio client prewarms those ViewportFrames offscreen before showing the menu UI, and inventory cards still retry fallback icons if a thumbnail arrives late.
- Pet power is now config-only durable data. `configs/pets.lua` defines family base power plus global Basic/Golden/Rainbow multipliers, while grant/progression/inventory save paths avoid writing per-copy power or stats power. `tests/studio/BackfillPetPowerSourceOfTruth.lua` can strip legacy saved power fields for the current Studio player.

## Phase 0 Verification

Last checked: 2026-05-26

- `python3 scripts/wiki_status.py`: passes.
- Rojo 7.6.1 build: passes with `rojo build --output /tmp/rbx-template-phase0.rbxl`.
- Selene 0.25.0: passes with `selene --allow-warnings src configs tests`; current result is 0 errors, 646 warnings.
- StyLua 0.18.2 check: fails because the existing codebase has broad formatting drift. Treat formatting cleanup as a separate cleanup lane, not a Phase 0 blocker.
- Studio MCP smoke test: passes. `RBX-Template` is the active Studio instance, play mode starts/stops through MCP, screen capture works, and console output is readable.

## Phase 1 Verification

Last checked: 2026-05-27

- Rojo 7.6.1 build: passes with `rojo build --output /tmp/rbx-template-phase1-full.rbxl`.
- Targeted Selene for Phase 1 touched files: 0 errors, existing warnings only in legacy/bootstrap files.
- Full Selene: passes with warnings from the existing codebase.
- StyLua check for Phase 1 touched files: passes.
- ConfigLoader unit specs pass in Studio (`30` passed, `0` failed) and cover valid area/marker schemas plus missing-parent, cycle, and unsupported marker-attribute failures.
- Studio MCP smoke test: passes. Generated hook counts in play mode were `Zone=5`, `AreaZone=2`, `SpawnZone=2`, `EggStand=2`, `PODPodium=2`, `TeleportPad=2`, `Portal=2`.
- Active-zone dormancy smoke check passes: after boot, Spawn had spawned breakables and Meadow had `0`; after `TravelSmoke` unlocked/traveled to Meadow, Meadow filled to its configured `8` breakables.
- Travel smoke test passes through MCP with `TravelSmoke`. It verifies locked travel rejection, unlock, server-authoritative movement to Meadow, active-area update, and state restoration.
- Egg proximity smoke test: passes through MCP with `EggProximitySmoke`. It verifies far hatch rejection, near hatch success, UI target state, currency deduction, pet inventory increase, and state restoration.
- Authored reference map smoke passes through MCP with `MapContractSmoke` using `requireAuthored = true` and `allowSynthetic = false`: `Zone=5`, `AreaZone=2`, `SpawnZone=2`, `EggStand=2`, `PODPodium=2`, `TeleportPad=2`, `Portal=2`, all authored.
- Spawn safety smoke passes through MCP with `SpawnSafetySmoke` for `Spawn`: the player is placed above a real floor, vertical velocity is cleared, and active area state is synchronized.

## Phase 2 Verification

Last checked: 2026-05-27

- Rojo 7.6.1 build: passes with `rojo build --output /tmp/rbx-template-phase2-slice.rbxl`.
- Targeted StyLua check/format for touched Phase 2 files: passes.
- Targeted Selene for touched Phase 2 files: 0 errors, existing warnings only in older bootstrap/inventory/data/config files.
- `ConfigLoader.spec` passes in Studio with `33` passed and `0` failed, including upgrade config validation.
- `Phase2ProgressionSmoke` passes through MCP: locked Meadow rejects without crystals, paid Meadow unlock succeeds, pet equip-slot upgrade increases max pet slots from `3` to `4`, pet storage increases from `50` to `75`, and profile state is restored.
- The same Phase 2 smoke verifies `crystal_value` as a real modifier path: a base `100` crystal breakable reward resolves to `110` after level 1, proving player-specific upgrades are included in breakable reward resolution.
- Locked-zone responses include config-driven unlock requirements, so future UI can show cost/currency/prerequisite without hardcoding Meadow.
- `MeadowBreakableSmoke` verifies the first full area-gated mining loop: it unlocks/travels to Meadow, spawns a deterministic `BigBlueCrystal` through `BreakableSpawner`, breaks it through the normal contribution/death handler, pays `110 crystals` through the upgrade-aware economy path, increments `breakables_broken`, and restores the profile.
- `SyntheticExpansionSmoke` verifies the Phase 2 expansion contract without permanently changing the authored map: it temporarily injects a second synthetic world (`crystal_world -> CrystalCavern`), rebuilds bindings in synthetic mode, asserts a cross-world portal and spawn zone, travels through the portal, restores profile/map state, and leaves the authored-only marker contract at `synthetic=0`.
- Regression smokes still pass: `SpawnSafetySmoke`, authored-only `MapContractSmoke`, `TravelSmoke`, and `EggProximitySmoke`.

## Phase 3 Verification

Last checked: 2026-05-27

- Rojo 7.6.1 build: passes with `mise exec -- rojo build --output /tmp/rbx-template-phase3.rbxl`.
- Targeted StyLua check/format for touched Phase 3 files: passes.
- Targeted Selene for touched Phase 3 files/configs/tests: 0 errors, existing warnings only in older bootstrap/config/inventory/data files.
- `ConfigLoader.spec` passes in Studio with `36` passed and `0` failed, including pet index, achievements, and leaderboard config validation.
- `Phase3StatsSmoke` passes through MCP: adding bear/basic twice and bunny/basic records only `2` distinct pet entries, syncs `distinct_pets=2`, grants the first pet-index milestone once, grants the first egg achievement over `eggs_hatched`, updates the live eggs leaderboard, and restores the profile.
- Phase 2 regression smoke still passes after Phase 3 profile/inventory changes: `Phase2ProgressionSmoke`.
- `EternalPowerSmoke` exists as a Studio runner for verifying cached eternal pet power after Rojo sync/restart.

## Admin/Map Test Verification

Last checked: 2026-05-27

- Studio MCP admin zone-lock smoke passes: it verifies Meadow travel rejects while locked, admin bypass unlock succeeds, portal/pad travel reaches Meadow, admin lock re-locks Meadow, and profile/travel state restores.
- Studio MCP prompt state smoke passes: locked Meadow shows the `Unlock 100 crystals` prompt, unlocking Meadow hides it for that player, and touch/server travel still moves to Meadow.

## Recent Planning State

The project now has two high-level source documents:

- `docs/FOUNDATION_AND_REQUIREMENTS.md`
- `docs/IMPLEMENTATION_PLAN.md`

Those documents define the planned foundation work: stats, modifier pipeline, save migrations, config validation, feature flags, economy ledger, and the map integration contract.

## Next Likely Work

Continue Phase 4 progression-depth work while keeping cleanup space for Studio and tooling warnings:

1. Build Phase 4 enchant behavior on top of the new rarity-slot config: hatch-time enchant rolls, manual enchant/reroll UI, modifier semantics, and stack-to-unique promotion for existing stackable pets that become enchantable.
2. Choose first live pet XP sources and balance them against the offline team-power calculator.
3. Decide whether player level modifies team power directly, gates content, or only affects luck/unlocks.
4. Expand the authored-map workflow with visible gate art/fixtures attached to the invisible `TeleportPad`/`Portal` hooks.
5. Clean up warning-level placeholder/test data in monetization, UI style rules, and saved effects.

## Links

- [Decisions](DECISIONS.md)
- [Architecture](ARCHITECTURE.md)
- [Studio Workflow](STUDIO_WORKFLOW.md)
- [Map Integration Contract](MAP_INTEGRATION_CONTRACT.md)
- [Map Marker Reference](../MAP_MARKER_REFERENCE.md)
- [Implementation Plan](../IMPLEMENTATION_PLAN.md)
