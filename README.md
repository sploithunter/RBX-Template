# RBX Template

A configuration-as-code Roblox pet/clicker template built with Rojo. The project is designed so code owns reusable game systems and Studio/world builders own map geometry, art, and invisible gameplay markers.

## Current Checkpoint

Phase 3 is complete for the current baseline. Phase 4's core pet progression/enchant baseline is in progress.

- Phase 0: foundations complete.
- Phase 1: map integration contract complete for synthetic and partial authored maps.
- Phase 2: economy depth complete for the current baseline.
- Phase 3: stats-derived wins complete: pet index, achievements, and live leaderboards.
- Phase 4: core progression/enchant systems are active: unique pet XP/levels, enchant-slot unlock milestones, hatch-time enchant rolls, manual reroll service hooks, enchant modifier providers, eternal/huge pet handling, source-of-truth pet power, and offline balance tooling.

## Core Loop

The playable baseline includes:

- Breakable crystal and coin spawning.
- Eggs and hatching from configured asset ids.
- Persistent player data through ProfileStore.
- Mixed pet inventory storage: normal pets stack, special pets are unique records.
- Pet equip limits, storage limits, and config-driven upgrades.
- Paid area unlocks and server-authoritative portal/pad travel.
- Active-zone breakable spawning so inactive areas stay dormant.
- Pet index milestones, achievements, and live leaderboard service.
- Admin and Studio smoke-test tooling for repeatable validation.

## Configuration As Code

Most gameplay tuning lives in `configs/*.lua`. Designers should be able to add or rebalance content by editing configs and Studio markers instead of writing service code.

Important configs:

- `configs/game.lua`: feature flags and global settings.
- `configs/pets.lua`: pet families, rarity, variant multipliers, asset ids, transforms, eternal settings, and enchant capacity.
- `configs/pet_progression.lua`: unique-pet XP curves, level caps, power growth, and enchant-slot unlocks.
- `configs/enchants.lua`: enchant effects, rarity roll profiles, roll counts, chance weights, strength ranges, reroll costs, and modifier mappings.
- `configs/areas.lua`: zone tree and area unlock requirements.
- `configs/markers.lua`: Studio-authored map marker contract.
- `configs/breakables.lua`: crystals, spawn tables, and world/area spawner settings.
- `configs/upgrades.lua`: permanent player upgrades.
- `configs/pet_index.lua`, `configs/achievements.lua`, `configs/leaderboards.lua`: Phase 3 stats-derived systems.

Durable pet power has a single source of truth in `configs/pets.lua`: family base power plus variant multipliers. Saved pet inventory records should store identity and mutable per-copy state such as level, XP, enchants, serials, hatcher metadata, lock state, and Huge/Eternal traits, but not power values.

Enchant chance also has a single source of truth in `configs/enchants.lua`. Services read configured rarity profiles, weighted chance entries, slot counts, and strength ranges; saved pets store the rolled enchant identity/strength, while modifier semantics remain configurable.

## AI And Wiki Workflow

This repo is intended to be developed with Codex or another AI coding agent. The persistent project memory lives in `docs/wiki/`, so useful decisions survive beyond one chat thread and future agents can move quickly without rediscovering the same context.

Recommended start-of-work flow for any agent:

1. Read `AGENTS.md`.
2. Read `docs/wiki/INDEX.md`.
3. Follow the links relevant to the task, especially `CURRENT_STATUS.md`, `DECISIONS.md`, `ARCHITECTURE.md`, `STUDIO_WORKFLOW.md`, and `MAP_INTEGRATION_CONTRACT.md`.
4. Verify the wiki against source files before editing code, because code and formal requirements remain the final authority.
5. Make the smallest useful code/config/doc change.
6. Run the relevant local checks and Studio smoke runners.
7. Update the wiki before finishing if the work changed architecture, config shape, map contracts, data shapes, save fields, network packets, Studio workflow, or project direction.

The wiki pattern is deliberately lightweight:

- `docs/wiki/INDEX.md` is the table of contents.
- `docs/wiki/CURRENT_STATUS.md` says what is true right now.
- `docs/wiki/DECISIONS.md` captures durable decisions and rationale.
- `docs/wiki/ARCHITECTURE.md` explains service and data boundaries.
- `docs/wiki/STUDIO_WORKFLOW.md` captures Rojo, Studio, MCP, and smoke-test workflow.
- `docs/wiki/LOG.md` records dated session summaries.
- `docs/wiki/raw/` is for unsynthesized notes; do not treat raw notes as current truth until they are compiled into a normal wiki page.

Use `python3 scripts/wiki_status.py` as a quick health check after wiki edits. The goal is not heavy documentation; the goal is a short, current project memory that lets an AI agent and a human developer maintain momentum together.

## Studio And Rojo Workflow

Prerequisites:

- Roblox Studio.
- Rojo 7.6.1 or newer.
- `mise` for local tool versions.

Common commands:

```bash
mise exec -- rojo serve --port 34872
mise exec -- rojo build --output /tmp/rbx-template.rbxl
mise exec -- selene configs src tests --allow-warnings
python3 scripts/wiki_status.py
python3 scripts/balance_team_power.py --list-pets
```

In Roblox Studio:

1. Open the place.
2. Connect the Rojo plugin to `localhost:34872`.
3. Start Play mode for datastore/API-dependent tests.
4. Keep Studio API access enabled when testing persistence.

Useful Studio command-bar runners after Rojo sync:

```lua
return require(game:GetService("ReplicatedStorage").Tests.studio.GrantColoradoTestPets).runText()
return require(game:GetService("ReplicatedStorage").Tests.studio.BackfillPetHatcherProvenance).runText()
return require(game:GetService("ReplicatedStorage").Tests.studio.BackfillPetPowerSourceOfTruth).runText()
return require(game:GetService("ReplicatedStorage").Tests.studio.EternalPowerSmoke).runText()
return require(game:GetService("ReplicatedStorage").Tests.studio.Phase4PetProgressionSmoke).runText()
```

## Project Structure

```text
configs/                  Gameplay and system configuration
docs/                     Requirements, implementation plan, and reference docs
docs/wiki/                Persistent LLM-maintained project memory
scripts/                  Local tools and Studio helper scripts
src/Client/               Client UI and local systems
src/Server/               Server services and Studio smoke bridge
src/Shared/               Shared config loader, network signals, and utilities
tests/studio/             Studio command-bar/MCP smoke runners
tests/unit/               Unit specs for config and service behavior
```

## Verification Baseline

Latest local checkpoint:

- `rojo build`: passes.
- `selene configs src tests --allow-warnings`: passes with existing warnings.
- `python3 scripts/wiki_status.py`: passes.
- `git diff --check`: passes.
- Phase 3 Studio smoke coverage exists for pet index, achievements, leaderboards, and Phase 2 regressions.
- `Phase4PetProgressionSmoke`: passes in Studio for hatch enchants, breakable XP, manual reroll, and profile restoration.

See `docs/wiki/CURRENT_STATUS.md` for detailed verification history and `docs/IMPLEMENTATION_PLAN.md` for the phase roadmap.

## Next Phase

Remaining Phase 4-adjacent work:

- Stack-to-unique promotion for normal pets that receive per-copy state.
- Rebirth design only if it remains dramatic and meaningfully different from old ColorfulClickers-style multiplier rebirths.
