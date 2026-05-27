# Decisions

Status: current

## Config As Code

Content and tuning should live in `configs/*.lua`. Services should consume config rather than hardcoding content. Adding areas, breakables, eggs, pets, achievements, events, rewards, and similar content should usually be a config edit plus Studio markers, not a new script.

## Rojo And Studio Boundary

Rojo owns scripts, configs, UI logic, networking, validation, and service behavior. Studio/world builders own the physical map, art direction, terrain, decorations, and invisible gameplay markers. Systems bind to the map through tags, attributes, and contracted child-marker names.

## Map Binding

The project should implement `WorldBindingService` as the seam between hand-built maps and config-driven systems. Code should not hardcode map coordinates or fragile Workspace paths.

## Synthetic Map

The game should be able to run on a baseplate by synthesizing valid map hooks from config. Synthetic and authored maps must use the same binding API so tested mechanics transfer cleanly.

## Reference Game Usage

`/Users/jason/Documents/ColorfulClickers_exchange-rojo` is the preferred newer reference game. It is useful for ideas, not implementation style. Port concepts into this project's config/service architecture instead of copying scattered scripts.

## Economy Shape

The project should support multiple currencies, but the template baseline should stay small until balancing is understandable. Currency mutations should be tagged with source/sink metadata so the economy can be audited.

## Pet Assets

Pet models should be referenced by asset id where possible. Meshi can be used for asset creation, but current import is manual download followed by project-side upload/import. Automation is desired later.

## Pet Rarity And Variants

Pet rarity belongs to the pet family. Variants such as Basic, Golden, and Rainbow are visual/stat treatments and should not automatically promote a normal pet into Mythical/Secret/etc. For example, Rainbow Bear is still a Common Bear with the Rainbow variant treatment; Dragon is Secret because the Dragon family declares `rarity = "secret"`, and Colorado is Exclusive because the Colorado family declares `rarity = "exclusive"`. Startup config validation requires every pet family to declare a valid rarity so content typos fail early.

Inventory card visuals should communicate both rarity and variant without letting one erase the other. Rarity controls data, tooltip text, special/unique rules, and the outer card frame. Variant treatments such as Golden and Rainbow layer animated inset rings and background treatments inside that frame, so a Common Rainbow pet still looks Rainbow while remaining visibly Common.

## Pet Identity

Pet config table keys are durable save IDs and must be treated as migration-sensitive. Player inventory stores IDs such as `bear` plus variant IDs such as `rainbow`, not display labels. Pet families and variants use `display_name` for player-facing names so typo fixes and renames do not corrupt inventories. Startup validation rejects malformed pet/variant/rarity IDs and missing display names, but changing an existing pet key still requires an explicit migration/backfill plan.

Inventory and hatch-facing pet titles should prefer the pet family display name, not the variant display name. Variant identity remains visible through card effects and tooltip fields, while traits that materially change identity, such as Huge, may prefix the family name.

Pet power has a single durable source of truth: `configs/pets.lua`. Pet families declare base power, variants apply configured multipliers, and per-copy inventory records must not store power/base-power/effective-power values. Inventory may store identity and mutable per-copy state such as level, XP, enchants, serials, hatcher metadata, lock state, and Huge/Eternal flags. Runtime systems may cache computed power on spawned models or transient folders, but saved profile data should be backfilled when legacy power fields are found.

## Pet Storage And Enchants

Normal pets should remain stack-count records keyed by canonical pet id + variant. The project should not add a generic stack-to-unique promotion flow for normal pets; it is easy to create one-off edge cases and hard to reason about at scale. Per-copy state belongs only on pets that are unique from the moment they are granted, such as configured Mythic/Secret/Exclusive/Huge/future tiers, special rewards, or future explicitly unique craft outputs. Enchants should be stored on the unique pet instance and contribute through the `enchants` modifier pipeline stage; stack records must stay free of enchant/progression fields. Enchant capacity is declared by rarity in pet config so tiers such as Mythic, Exclusive, Huge, or future larger tiers can change slot counts without service edits.

Pet XP and levels are unique-pet progression state. Stack records do not gain XP or levels. Unique pets may scale power from a config-driven XP curve and capped per-level multiplier. Enchant capacity remains the pet's potential slot count, while `unlocked_enchant_slots` is progression-driven; unique enchantable pets start with one unlocked slot and unlock remaining slots at configured level milestones.

Player level must affect gameplay. It should not be cosmetic-only. The first target is a configurable contribution to team power, plus configurable level rewards such as additional equipped-pet slots every N levels. The exact balance curve belongs in config and should feed the shared modifier/equip-limit paths rather than special-case consumers.

## Pet Provenance

Valuable pet provenance and internal grant audit tags are separate. `grant_source` records the system reason a pet was created and should not be displayed as player-facing tooltip content. `hatcher_name` and `hatcher_user_id` record the player who created a valuable copy and may be displayed, traded, and preserved with the unique pet record.

## Stats-Derived Features

Pet index, achievements, and leaderboards should stay thin views over profile state and K1 stat counters. Pet index may persist compact first-discovery records because it is ownership history, but progress counters such as `distinct_pets`, `eggs_hatched`, and `breakables_broken` remain the shared source for achievements and leaderboards.

## Studio AI Workflow

Use Codex connected to Roblox Studio through the official Studio MCP server as the primary automated development workflow. Roblox Studio Assistant's external OpenAI/Anthropic/Google model settings currently require provider API keys; they do not replace Codex subscription access. Studio MCP plus Codex gives this project Output access, screenshots, play control, tree inspection, Luau execution, and script reads/edits without adding provider API keys inside Studio.

## Studio Smoke Tests

Automated Studio tests should move the player through real gameplay hooks rather than only calling service functions. Gate/teleport and egg-hatching tests should use Studio MCP movement/keyboard input where possible, with server-authoritative Luau assertions for currency, inventory, active area, and rejection cases. Visual assets are optional; invisible tagged markers remain the behavior source of truth.

## Marketplace

The reference game's external database/webhook marketplace should not be copied. If marketplace/exchange is implemented, it should be Roblox-native with escrow and anti-duplication guarantees.

## Links

- [Map Integration Contract](MAP_INTEGRATION_CONTRACT.md)
- [Studio Workflow](STUDIO_WORKFLOW.md)
- [Reference Game Insights](REFERENCE_GAME_INSIGHTS.md)
- [Foundation & Requirements](../FOUNDATION_AND_REQUIREMENTS.md)
