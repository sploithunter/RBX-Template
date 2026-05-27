# Open Questions

Status: current

## Product And Economy

- Should offline/idle progression exist?
- How many currencies should ship in the template baseline?
- What should the first balanced economy loop target: crystals to coins, coins to eggs, or a clearer soft/premium split?
- Should direct player-to-player trade be in scope, or only auction-style marketplace?
- What is the minimum safe first trading contract? It should move unique pet records whole, preserve huge serials/enchantments/locks/signed metadata, and avoid minting new serials during transfer.

## Content And Pets

- What exact balance magnitudes should each enchant have? Storage direction is decided: stacks stay stack-only, and pets that need enchant/progression state must be unique from grant/craft/reward time. Enchants live on unique pet instances and feed the `enchants` modifier pipeline stage. Capacity is now config-driven by rarity.
- What should the first live pet XP sources be? The data/service foundation exists for unique pets, but breakable damage, breakable destroy, daycare/offline, and consumable XP items still need balancing decisions.
- What player-level-to-team-power curve feels good in real play? The implementation is config-driven and active, but the current +1% per level / +1 equipped slot per 10 levels defaults are first-pass tuning values.
- What should replace the legacy pet `Follow` mining script? Phase 4 now routes damage and cadence modifiers through it, but the long-term design should be a service-owned pet assignment/work loop.
- Should high-power pets be normalized by player progression, area tier, or both?
- Should forever/eternal pets use the reference-style percentage-of-current-best-power model, and what percent range keeps them prestigious without breaking early progression?
- What is the long-term automated Meshi-to-Roblox asset workflow?
- What are the first production-quality pet families after Bear and Dragon basics?

## Map Workflow

- How should the starter reference map be owned: checked-in `.rbxlx`, Studio template place, model artifact, or generated authoring command?
- Which map hooks should be required for the first authored island?
- Should authored maps be validated in CI, manually, or both?
- Should visual gate/portal assets for automated travel tests be checked into the repo, imported into the creator inventory, or discovered from Creator Store asset IDs at test time?

## Implementation

- How strict should config validation be during early prototyping versus shipping?
- Which systems should be feature-flagged first?
- What is the minimum useful admin panel for balancing and world-builder validation?

## Links

- [Current Status](CURRENT_STATUS.md)
- [Implementation Plan Open Decisions](../IMPLEMENTATION_PLAN.md)
