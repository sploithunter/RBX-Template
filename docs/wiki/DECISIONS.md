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

## Pet Storage And Enchants

Normal pets should remain stack-count records keyed by canonical pet id + variant. Any pet with per-copy state that affects gameplay or ownership value, such as enchantments, serials, signatures, huge/eternal status, nickname, lock state, or custom progression, should be promoted to a unique special instance before that state is applied. Enchants should be stored on the pet instance and contribute through the `enchants` modifier pipeline stage; stack records must stay free of enchant/progression fields.

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
