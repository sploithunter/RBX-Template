# Current Status

Status: current

## Summary

This is a Rojo Roblox pet/clicker project being upgraded toward a config-as-code template. Phase 0 is complete, Phase 1 map integration is complete for the current synthetic/partial-authored baseline, Phase 2 economy depth is complete for the current baseline, Phase 3 stats-derived wins are complete for pet index, achievements, and live leaderboards, and Phase 4 progression depth is complete for the current baseline. Phase 5 has started with server-authoritative auto-target mode selection and hatch auto-delete filters. The playable loop includes breakable crystals, coin generation, eggs, hatching, persistent player data, imported pet assets, an admin panel, configurable currency conversion, basic global events/effects work, multi-area map hooks, server-authoritative area travel, active-zone spawner dormancy, config-driven upgrades, paid area unlocks, area-gated stronger breakables, first-time pet indexing, achievement rewards, K1-backed leaderboards, unique pet progression, enchant systems, player-level power, and first-pass auto systems.

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
- Enchant capacity is now controlled by pet rarity config: Mythic pets get `1` slot, Secret/Exclusive pets get `2`, and Huge pets get `3`. Rarities with enchant slots are granted as unique pet records going forward; normal stacked pets stay stack-only and are not planned for generic stack-to-unique promotion.
- Phase 4 pet progression has a first foundation slice: `configs/pet_progression.lua` and `PetProgressionService` define unique-pet XP curves, max levels by rarity, capped power growth, and enchant slot unlock milestones. New unique pets keep their full potential `max_enchantments` but start with configured `unlocked_enchant_slots` (currently one slot) and gain the rest through levels.
- `configs/enchants.lua` is the single source of truth for enchant chance and behavior. It defines rarity roll profiles, roll counts, weighted chance entries, strength low/high/scale ranges, duplicate policy, reroll cost, and modifier mappings. The initial template ports the useful ColorfulClickers concepts (`HomeWorld`, `Luck`, `SecretLuck`, `Tactics`, `Leadership`, `Efficiency`) into config-first effects and adds this-game examples for crystal rewards, coin rewards, and pet XP.
- `EnchantService` rolls hatch-time enchants for eligible unique pets through `PetGrantService`, exposes server-authoritative manual rerolls through `EnchantPetRequest`/`EnchantPetResult`, and registers equipped unique pet enchants as `enchants` modifier providers. Live enchant consumers now include `breakable_reward`, `pet_xp`, `hatch_luck`, `secret_hatch_luck`, `pet_damage`, `team_power`, and `pet_efficiency`.
- Map-authored enchanter stations now bind through `EnchanterStation` hooks. The current Studio `Workspace.Enchanter` model is tagged as `basic_enchanter`, uses its `EnchantTouchPart` child as the touch/prompt volume, keeps its floating cosmetic scripts, and opens a dedicated pet enchant panel for server-authoritative rerolls.
- Equipped unique pets now receive configurable breakable-destroy XP through `PetProgressionService:AwardBreakableDestroyed`. `BreakableSpawner` calls this after contribution rewards, and pet XP can itself be modified by enchant effects such as `scholar`.
- `configs/player_progression.lua` and `PlayerProgressionService` now make player level affect team power through the modifier pipeline and grant extra equipped pet slots at configured level milestones. The initial default is +1% team power per level after level 1, capped at +100%, and +1 equipped pet slot every 10 levels capped at +3 bonus slots.
- `scripts/balance_team_power.py` is available for offline balance passes. It reads current pet/progression/player-progression configs and estimates team power across team size, pet level, eternal/huge rules, and the configured player-level power curve.
- Pet mining still uses a stabilized legacy `Follow` script cloned onto pet models. Phase 4 routes pet damage and efficiency modifiers through it, but a future service-owned PetWork/Combat loop should replace this bridge for cleaner tests and configuration.
- Huge-and-above provenance is now captured as separate hatcher metadata. Future grants stamp `hatcher_name`/`hatcher_user_id` for pets meeting the configured provenance threshold; `grant_source` remains non-displayed audit data. `tests/studio/BackfillPetHatcherProvenance.lua` can backfill existing qualifying pets for the current Studio player.
- Pet tooltip metadata visibility is driven by `configs/inventory.lua` `tooltip_fields`, so fields can be hidden, labeled, or ordered without editing `InventoryPanel`.
- Pet inventory cards now distinguish rarity/specialness and variant separately. Rarity rings are config-driven and can animate around the card using a `UIGradient`; the default rarity ladder currently includes Common, Uncommon, Rare, Epic, Legendary, Mythical, Secret, Exclusive, and Huge. Variant backgrounds are also config-driven, including darker gold and rainbow fills. Inventory display reads rarity names/colors from `configs/pets.lua`.
- Generated pet/egg thumbnails are cached as ViewportFrames, not uploaded image assets. `AssetPreloadService` publishes `PetThumbnailsReady`, `PetThumbnailCount`, and `PetThumbnailFailures` on `ReplicatedStorage.Assets`; the Studio client prewarms those ViewportFrames offscreen before showing the menu UI, and inventory cards still retry fallback icons if a thumbnail arrives late.
- Pet power is now config-only durable data. `configs/pets.lua` defines family base power plus global Basic/Golden/Rainbow multipliers, while grant/progression/inventory save paths avoid writing per-copy power or stats power. `tests/studio/BackfillPetPowerSourceOfTruth.lua` can strip legacy saved power fields for the current Studio player.
- `configs/auto_systems.lua` and `AutoTargetService` now provide the first Phase 5 auto-system slice. Target mode choices persist under `Settings.AutoSystems.auto_target`; clients request auto-target work and the server selects the breakable. The configured default modes are nearest, highest value, weakest, strongest, and selected currency.
- Hatch auto-delete filters persist under `Settings.AutoSystems.auto_delete` and are enforced in `EggService` before `PetGrantService` writes inventory. Filters can match rarity, pet family, or variant, and Secret/Exclusive/Huge are protected by default.
- Egg hatching is treated as two-stage: first roll chooses the pet species, second hidden roll chooses basic/golden/rainbow. Egg previews stay species-only and show basic-form pets, while `egg_sources.<id>.variant_rolls` controls allowed variants and optional cost multipliers such as the starter `20x` no-basic/golden mode.
- Special hatch reveal metadata is driven by `egg_system.hatching.animation`: configured rarities mark per-result special outcomes, aggregate reveal metadata is returned to the client, and Skip Hatch remains a hard animation-suppression preference instead of being overridden by rare outcomes.
- Hatch mode stubs now include Golden and Charged. Golden removes basic variants and uses its configured multiplier; Charged uses its configured multiplier plus hatch-luck and secret-luck bonuses. Both are server-entitlement checked and surfaced through the hatch settings drawer.
- Admin hatch entitlement tools now expose the egg shop stubs before the shop UI exists. Developers can view, lock, unlock, reset, or directly set Auto, Golden, Charged, Fast, Skip, and max hatch count attributes from the admin panel; snapshots include effective hatch entitlement status.
- Hatch settings education is now config-driven. `configs/egg_system.lua` owns help copy for core hatch controls, mode toggles, and auto-delete filters; the hatch drawer renders a `HelpText` line and the interactive controls carry `HelpText` attributes for hover/focus updates.
- Auto-hatch failure feedback now explicitly stops with a reason for no-currency and no-storage sessions, and the client loop also reports when the player moves too far away, e.g. `Auto hatch stopped: out of currency`, `Auto hatch stopped: storage full`, or `Auto hatch stopped: too far away`.
- Hatch reveal markers are now config-driven. `egg_system.hatching.animation.reveal_badges` controls rarity, variant, special, and auto-delete badges, and `EggHatchingService:GetActiveAnimationDebugState()` lets Studio smokes inspect the live client animation contract without relying on screenshots.
- Hatch mode education now reads player entitlement state. The settings drawer grays locked modes, stores `ModeState`/`ModeOwned` attributes on each mode toggle, shows a `ModeStatus` summary, and uses config-driven locked/available/active help text.
- Server hatch debugging now has a bounded recent-history path. `EggService` records successful and rejected hatches with request count, actual count, cost, stop reason, options, entitlements, sampled results, auto-delete counts, special counts, and authored animation metadata. Admin tools expose this through `Admin_RequestHatchHistory`, and the admin panel has a Recent Hatch History action.
- Egg source unlock requirements are now server-authoritative for both real hatches and no-mutation hatch simulations. `egg_sources.<id>.unlock_requirement` can point at a stat/counter threshold, rejected hatches return `egg_locked` with current/required progress, and auto-hatch feedback maps that code to `locked egg`.
- Studio hatch forcing now uses player `ForcePet`/`ForceVariant` attributes directly before the roll, avoiding the earlier copied-config gotcha where mutating `Locations.getConfig("pets")` did not reliably affect `simulateHatch`.
- `ConfigLoader` now validates the expanded egg-system hatch contract, including hatch count relationships, debug/history limits, animation capacity, reveal badge field types, shop max-count defaults, and hatch-panel button labels.
- Egg hatching has a no-mutation simulation path for admin/testing. `EggService:SimulateHatchBatch` rolls the same server pet/variant/luck pipeline and reports costs, counts, auto-delete matches, special reveal counts, and animation metadata without spending currency, granting pets, incrementing stats, or playing client animation. Admin tools expose this through `Admin_RequestHatchSimulation`.
- The near-egg hatch panel now reads the same effective Max Hatch and Auto Hatch entitlement state that the server uses. Selected hatch count clamps to player/config max entitlement, controls expose `MaxEntitledHatchCount`, and locked Auto is grayed/blocked client-side before the server-authoritative rejection path.
- Hatch animation presentation has another config-first slice. `egg_system.hatching.animation.layout` controls grid padding and min/max egg sizes, `special_glow` controls the special hatch rarity stroke/pulse, and the client animation debug state exposes layout/glow metadata for Studio smokes.
- Fast Hatch presentation speed is no longer hardcoded in `EggHatchingService`. `egg_system.hatching.animation.fast_hatch_speed_scale` owns the duration multiplier, `ConfigLoader` validates it, and the animation debug state exposes resolved Fast/Silent timing metadata.
- Hatch selected count is now a persisted player setting. The near-egg panel writes changes through `HatchSettings_SetCount`, `SettingsService` stores them under `Settings.AutoSystems.hatch.selected_count`, and clients restore the replicated `Player.Settings.AutoSystems.Hatch.SelectedCount` value when the hatch panel is rebuilt.
- Hatch mode toggles are now persisted player preferences too. `SettingsService` sanitizes the configured hatch mode keys, stores them under `Settings.AutoSystems.hatch.modes`, replicates `Player.Settings.AutoSystems.Hatch.Modes`, and `EggInteractionService` restores/persists Show, Golden, Charged, Fast, Skip, and Silent toggles while the server still enforces entitlement on hatch requests.
- The near-egg hatch panel now has config-driven responsive scaling. `configs/egg_system.lua` owns `ui.hatch_panel.responsive`, `ConfigLoader` validates its scale bounds, `EggInteractionService` applies a `UIScale` against the current viewport, and tests cover desktop/mobile fit math.
- Skip Hatch is enforced as an animation-suppression preference in both hatch presentation layers. The interaction service does not start hatch animation when resolved options include `skipHatch`, and `EggHatchingService` also returns an immediate completed/skipped result without enabling the animation GUI if called directly with `skipHatch`.
- Show Hatch is a free, default-on hatch presentation preference. Players can turn it off to hide hatch animations without owning Skip Hatch; the setting persists under `Settings.AutoSystems.hatch.modes.showHatch`, flows through the server hatch options, and makes `EggHatchingService` return the same immediate skipped presentation result.
- Hatch animation now has max-count Studio coverage. `EggHatchingService` falls back to a resolved `1280x720` animation viewport if Studio reports an uninitialized tiny camera size, exposes container/frame geometry in its debug state, and `EggAnimationMaxBatchSmoke` verifies all `99` authored egg frames fit in the compact `10x10` layout.
- Hatch mode education now surfaces configured economics. Golden/Charged mode UI reads cost and luck values from `egg_system.hatching.shop_stubs`, exposes `CostMultiplier`/`LuckBonus`/`SecretLuckBonus` attributes for tests, and includes those details in help/status text.
- Expanded hatch drawer layout is now covered without relying on screenshots. `EggProximitySmoke` opens the real `PlayerGui` drawer, verifies responsive desktop/mobile fit math, and asserts visible drawer controls stay inside the configured drawer bounds.
- Special hatch reveal now includes a config-driven backdrop layer. `egg_system.hatching.animation.special_backdrop` controls a rarity-colored backdrop behind special pet reveals, `ConfigLoader` validates it, and animation debug state exposes the backdrop contract for Studio smokes.

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
- Studio MCP smoke test: latest expected generated hook counts are `Zone=5`, `AreaZone=2`, `SpawnZone=2`, `EggStand=1`, `PODPodium=2`, `TeleportPad=2`, `Portal=2`. Earlier Phase 1 verification used two egg stands before golden hatching moved into `basic_egg` variant-roll config.
- Active-zone dormancy smoke check passes: after boot, Spawn had spawned breakables and Meadow had `0`; after `TravelSmoke` unlocked/traveled to Meadow, Meadow filled to its configured `8` breakables.
- Travel smoke test passes through MCP with `TravelSmoke`. It verifies locked travel rejection, unlock, server-authoritative movement to Meadow, active-area update, and state restoration.
- Egg proximity smoke test: passes through MCP with `EggProximitySmoke`. It verifies far hatch rejection, near hatch success, UI target state, currency deduction, pet inventory increase, and state restoration.
- Authored reference map smoke should now expect one authored `EggStand` for `basic_egg`; rerun `MapContractSmoke` after regenerating the reference map.
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

## Phase 4 Verification

Last checked: 2026-05-27

- Rojo 7.6.1 build: passes with `mise exec -- rojo build --output /tmp/rbx-template-phase4-enchants.rbxl`.
- Targeted Selene for touched Phase 4 files/configs/tests: 0 errors, existing warnings only in older bootstrap/inventory/breakable/config files.
- `python3 scripts/wiki_status.py`: passes.
- `git diff --check`: passes.
- `Phase4PetProgressionSmoke` passes through Studio MCP after Rojo sync/restart. It granted a Huge Rainbow Colorado, verified a hatch-time enchant, awarded `25` pet XP from a `BigBlueCrystal` breakable context, rerolled enchant slot `1`, verified player-level slot bonus `1`, verified live hatch luck `0.1`, secret luck `0.05`, pet damage about `115`, team power `131.1`, pet efficiency `1.1`, and restored profile state.

## Phase 5 Verification

Last checked: 2026-05-27

- Rojo 7.6.1 build: passes with `mise exec -- rojo build --output /tmp/rbx-template-phase5-auto.rbxl`.
- Targeted Selene for touched Phase 5 files/configs/tests: 0 errors, existing warnings only in older bootstrap/data/settings/breakable files.
- Targeted StyLua check for the new/clean Phase 5 files passes.
- `git diff --check`: passes.
- `Phase5AutoSystemsSmoke` passes through Studio MCP after Rojo edit-mode sync. It creates a temporary `Phase5Smoke` breakable world, verifies nearest/highest value/weakest/strongest/selected-currency server target selection, verifies auto-delete rarity/type/variant matches, verifies protected Exclusive Colorado is not auto-deleted, and restores profile/map state.
- `HatchEntitlementAdminSmoke` passes through Studio MCP after stopping Play to let Rojo sync the new module, then restarting Play. It verifies status, lock-all, unlock-all, reset-all, and max hatch count changes for hatch entitlement attributes, then restores the player's original state.
- `EggProximitySmoke` passes through Studio MCP with the hatch drawer help-text contract. It verifies the near-egg panel, expected Hatch/Max/Auto/count controls, mode/filter controls, and config-driven help metadata.
- `EggProximitySmoke` also verifies locked hatch-mode education: mode controls expose locked state/help attributes and the drawer renders a locked-mode status summary.
- `EggAutoHatchSmoke` passes through Studio MCP. It initializes isolated client egg targeting/hatch panel services, verifies auto-hatch stop feedback for zero currency, zero pet storage, and moving out of range, then restores the profile.
- `StudioSmokeTestService` now supports `setupPetInventoryEmpty` for egg smokes so storage-limit tests can avoid accidental success through existing pet stacks.
- `EggAnimationContractSmoke` passes through Studio MCP. It creates a synthetic special Exclusive Rainbow Colorado and an auto-deleted Common Bear hatch, then verifies frame metadata, rarity/variant/special/auto-delete badges, and visible reveal-state updates.
- `EggHatchHistorySmoke` passes through Studio MCP. It verifies a deterministic auto-deleted batch hatch is recorded in server history with cost, count, sampled pet result, and auto-delete metadata.
- `ConfigLoader.spec` passes through Studio MCP in Play mode with `52` passed, `0` failed, and `0` skipped, including the egg-system validator coverage.
- `EggHatchSimulationSmoke` passes through Studio MCP. It forces a deterministic `7`-egg basic hatch simulation and verifies result counts plus no currency, inventory, or `eggs_hatched` counter mutation.
- `EggProximitySmoke` passes through Studio MCP with the effective hatch entitlement UI contract. It now asserts a configured `MaxEntitledHatchCount` and locked Auto control state in addition to the near-egg hatch transaction.
- `EggAutoHatchSmoke` still passes after the entitlement UI change, covering no-currency, no-storage, and too-far stop feedback.
- `EggAnimationContractSmoke` passes through Studio MCP after the hatch animation config polish. It verifies reveal badges plus configured grid layout metadata and special glow pulse metadata.
- Direct Studio validation of the new `egg_system` config rules passes: current config validates, invalid layout min/max fails, and invalid special glow transparency fails.
- `EggAnimationContractSmoke` also verifies configured Fast/Silent hatch timing metadata, and direct Studio validation rejects `fast_hatch_speed_scale` values above normal speed.
- `EggProximitySmoke` also verifies selected hatch count persistence by saving a count through the client interaction service, reading the replicated player setting/debug state, and resetting to one before the hatch transaction.
- `EggProximitySmoke` also verifies hatch mode persistence by toggling Silent Hatch through the client interaction service, reading the replicated hatch mode setting/debug state, and restoring the original value before the hatch transaction.
- `EggProximitySmoke` also verifies the responsive hatch panel layout contract: full scale on a desktop-sized viewport, scaled down and width-safe on a mobile-sized viewport.
- `EggAnimationMaxBatchSmoke` passes through Studio MCP. It starts a `99`-egg authored hatch animation, verifies the compact `10x10` layout, checks every frame stays inside the resolved animation viewport, and confirms all frames use the authored egg visual.
- `EggProximitySmoke` also verifies the hatch settings drawer exposes Golden/Charged cost and luck details from config.
- `EggProximitySmoke` also verifies the expanded hatch settings drawer renders with nonzero dimensions and no clipped visible controls.
- `EggAnimationContractSmoke` now verifies special hatch backdrop metadata, reveal visibility, and Skip Hatch suppression at the animation-service boundary; `ConfigLoader.spec` covers invalid backdrop transparency.
- `EggUnlockSmoke` passes through Studio MCP. It verifies `golden_egg` rejects at `9/10` configured hatch progress with `egg_locked`, succeeds at `10/10`, deducts the effective golden egg cost, grants one pet, and restores the profile/map state. `ConfigLoader.spec` now passes with `58` passed, `0` failed, and `0` skipped after adding unlock-requirement shape validation.
- `EggHatchSimulationSmoke` and `EggBatchHatchSmoke` still pass after the unlock gate change, covering the basic simulation and broader batch hatch regression paths.

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

Continue Phase 5 and follow-up polish while keeping cleanup space for Studio and tooling warnings:

1. Add richer UI controls for auto-target modes, selected currency, and hatch auto-delete filters.
2. Replace the legacy pet follow/mining script with a service-owned PetWork/Combat loop when hands-on play-feel testing is available.
3. Improve the first enchanter UI with richer result animation, better before/after messaging, and future enchant lock/protection options.
4. Improve enchant education/discoverability beyond the first config-sourced description text.
5. Expand the authored-map workflow with visible gate art/fixtures attached to the invisible `TeleportPad`/`Portal` hooks.
6. Clean up warning-level placeholder/test data in monetization, UI style rules, and saved effects.

## Links

- [Decisions](DECISIONS.md)
- [Architecture](ARCHITECTURE.md)
- [Studio Workflow](STUDIO_WORKFLOW.md)
- [Map Integration Contract](MAP_INTEGRATION_CONTRACT.md)
- [Map Marker Reference](../MAP_MARKER_REFERENCE.md)
- [Implementation Plan](../IMPLEMENTATION_PLAN.md)
