# Remote Development Pipeline

Status: building

## Goal

Develop, test, build, and **release** a Roblox game from an AI/CLI agent with
**no GUI computer-use** — driving the game through code (the CommandBus boundary)
and the Roblox Studio MCP, not by clicking the screen.

## Stages

```
  edit ─► static checks ─► headless tests ─► Studio integration ─► build ─► release
  (src)   selene/stylua    lune (pure)       MCP + CommandBus       rojo     rojo upload
          /rojo build                        /AutomationService     build    (Open Cloud)
  └────────── fully automatable, no Studio ──────────┘ └─ needs open Studio ─┘ └ automatable* ┘
```

| Stage | Tool | Automatable unattended? | Notes |
|-------|------|--------------------------|-------|
| Static checks | `selene`, `stylua --check`, `rojo build` | ✅ yes | Pure CLI. Runs in GitHub Actions. |
| Headless tests | `lune` (`mise run test-headless`) | ✅ yes | Pure-logic only (no Roblox runtime). Runs in CI. |
| Studio integration | Roblox Studio MCP + CommandBus | ⚠️ partial | Needs an **open Studio** + Rojo connected (one-time human bring-up). Test *execution* is automated via `execute_luau`. |
| Build artifact | `rojo build --output game.rbxl` | ✅ yes | Place/model file. Runs in CI. |
| Release | `rojo upload` (Open Cloud) | ✅ yes* | *Needs an Open Cloud API key + universe/place IDs (user-provisioned) and per-release authorization. No GUI. |

## GAP ANALYSIS — hard limits

These cannot be closed with the current Claude Code harness + Roblox Studio
tooling. They are the reasons the pipeline is not 100% unattended.

### G1 — No headless Roblox runtime (fundamental)
Roblox's runtime (DataModel, Instances, services, physics, replication) only
exists inside Studio or a live Roblox server. There is **no official headless
engine**. Consequence: anything touching Roblox APIs (services, movement, UI,
replication) **must run in Studio**. Only Roblox-API-free pure logic can be
tested headlessly (lune). This is why the architecture pushes logic into pure
modules (`CommandBus`, `Navigation`, formulas) — to maximize the headless tier.

### G2 — Claude Code cannot launch or click Studio
This harness has **no desktop control** (only the browser MCP and the Roblox
Studio MCP). It cannot:
- launch Roblox Studio,
- click the Rojo plugin **Connect** button,
- open a `.rbxl` place file,
- toggle **Enable Studio as MCP server**, or
- restart Play from the GUI (it *can* via the MCP `start_stop_play` once connected).

These are **one-time, per-session human setup actions**. After bring-up, the MCP
automates the rest (`execute_luau`, `start_stop_play`, `screen_capture`,
`character_navigation`, `get_console_output`, inspection).

### G3 — Studio integration tier is not CI-runnable
GitHub-hosted runners have no Roblox Studio. `run-in-roblox` (the community
headless-Studio test launcher) needs Studio installed and is unreliable on
macOS; it also launches the GUI app. So the integration tier runs **locally,
against an open Studio via the MCP** — it cannot run in cloud CI today. The fast
gate (static + headless + build) is the CI-runnable portion.

### G4 — Release requires user-provisioned credentials + authorization
`rojo upload` is fully scriptable, but needs:
- an **Open Cloud API key** with publish scope (created by the user at
  create.roblox.com/credentials),
- the target **universe ID + place ID**, and
- per-release **authorization** (publishing mutates a public resource).

The agent never handles the secret value — the release script reads it from the
`ROBLOX_OPEN_CLOUD_KEY` environment variable. Account/credential creation is a
user-only action. The agent builds and validates the release command but does
not execute the publish.

### G5 — `screen_capture` is a backstop, not a gate
The MCP screenshot can time out (observed locally). Visual checks confirm "the
UI rendered / the player is where expected" but **state read back through the
CommandBus is the source of truth** for pass/fail. Do not gate a test purely on
a screenshot.

### G7 — MCP `execute_luau` is client-attached during Play
In play-solo, the Studio MCP runs `execute_luau` in the **client** Lua state, and
`get_console_output` surfaces client output only. So `_G.RBXTemplateServices` and
server services aren't directly reachable from the MCP during Play. Two
consequences, both handled:
- **Production commands** are driven over the `GameAPICommand` RemoteFunction
  (client → server bus), exactly as a real client would — and test-only commands
  are correctly *forbidden* on that path.
- **Test-only / automation commands** need server context, so AutomationService
  exposes a Studio-only `RunAutomationSuite` RemoteFunction the client invokes;
  the suite then runs server-side (isTest=true). Server boot errors aren't
  visible via the MCP in Play — diagnose those in edit mode (init-simulate) or by
  reading state through these remotes.

### G6 — Player control vs. automated movement (mitigated, pending live verify)
In play-solo the player's client control module can fight server `MoveTo`.
`AutomationService:NavigateTo` now disables the player's controls for the
duration via the `AutomationControl` RemoteEvent + the client
`AutomationControlBridge` (Studio-only), always re-enabling afterward
(pcall-wrapped), and still re-issues MoveTo + detects stalls as a backstop. The
control-disable path needs one live Studio confirmation. Not a hard limit.

## One-time setup (human)

1. Install toolchain: `mise install` (rojo, wally, selene, stylua, lune), then
   `wally install`.
2. Open Roblox Studio on a place; enable **Enable Studio as MCP server**.
3. In Studio, install/Connect the Rojo plugin to `rojo serve` (port 34872) from
   this repo checkout.
4. For release: create an Open Cloud API key (publish scope) and export
   `ROBLOX_OPEN_CLOUD_KEY`, plus set the universe/place IDs.

## Running the pipeline

```bash
# Fast gate — fully automatable, also runs in GitHub Actions
mise run ci                 # selene + stylua --check + rojo build + test-headless

# Individual stages
mise run lint               # selene
mise run format             # stylua (write)
mise run test-headless      # lune pure-logic tests
mise run build              # rojo build --output game.rbxl

# Studio integration (needs open Studio + Rojo connected; driven via MCP)
#   The agent calls GameAPIService:Execute(...) through execute_luau and runs
#   the scenario orchestrator (tests/studio/AutomationSuite). See below.

# Release (needs ROBLOX_OPEN_CLOUD_KEY + IDs + authorization)
mise run release            # wraps `rojo upload` via Open Cloud; refuses if env unset
```

## What the agent can do end-to-end today

- ✅ Edit → fast gate (static + headless + build) → green, unattended.
- ⚠️ Studio integration: once a human brings up Studio + Rojo, the agent runs the
  command-bus scenarios via the MCP and asserts on state.
- ⏸️ Release: the agent prepares and validates the publish command; the user
  provisions the key and authorizes the actual upload.
