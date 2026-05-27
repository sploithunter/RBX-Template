# RBX Template

A configuration-as-code Roblox pet/clicker template built with Rojo. The project is designed so code owns reusable game systems and Studio/world builders own map geometry, art, and invisible gameplay markers.

## Current Checkpoint

Phase 3 is complete for the current baseline. The repo is ready to move deeper into Phase 4.

- Phase 0: foundations complete.
- Phase 1: map integration contract complete for synthetic and partial authored maps.
- Phase 2: economy depth complete for the current baseline.
- Phase 3: stats-derived wins complete: pet index, achievements, and live leaderboards.
- Phase 4: foundation has begun: unique pet XP/levels, enchant-slot unlock milestones, eternal/huge pet handling, source-of-truth pet power, and offline balance tooling.

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
- `configs/areas.lua`: zone tree and area unlock requirements.
- `configs/markers.lua`: Studio-authored map marker contract.
- `configs/breakables.lua`: crystals, spawn tables, and world/area spawner settings.
- `configs/upgrades.lua`: permanent player upgrades.
- `configs/pet_index.lua`, `configs/achievements.lua`, `configs/leaderboards.lua`: Phase 3 stats-derived systems.

Durable pet power has a single source of truth in `configs/pets.lua`: family base power plus variant multipliers. Saved pet inventory records should store identity and mutable per-copy state such as level, XP, enchants, serials, hatcher metadata, lock state, and Huge/Eternal traits, but not power values.

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

See `docs/wiki/CURRENT_STATUS.md` for detailed verification history and `docs/IMPLEMENTATION_PLAN.md` for the phase roadmap.

## Next Phase

Phase 4 should build on the current pet progression foundation:

- Hatch-time enchant rolls.
- Manual enchant/reroll flow.
- Modifier semantics for enchants.
- Live pet XP sources and balancing.
- Stack-to-unique promotion for normal pets that receive per-copy state.
- Rebirth design only if it remains dramatic and meaningfully different from old ColorfulClickers-style multiplier rebirths.
