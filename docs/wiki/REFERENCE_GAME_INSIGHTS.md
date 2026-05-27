# Reference Game Insights

Status: current

## Summary

The newer reference game at `/Users/jason/Documents/ColorfulClickers_exchange-rojo` contains many useful progression ideas, but its implementation is scattered across many one-off scripts. Use it as inspiration and translate concepts into config-driven services.

## Most Valuable Ideas

- Central global clock and deterministic daily behavior.
- Achievements over tracked counters.
- Rebirths as a reset-for-permanent-progress loop.
- Egg configs with costs, currencies, odds, secret/huge outcomes, and special pets.
- Pet team calculation with stats and enchants.
- Eternal/forever pet semantics: the newer reference game's equip-best logic treated an `Eternal` value as a percentage of the player's current top damage for the relevant damage type, rather than as a huge fixed stat. This keeps ultra-rare pets valuable forever without letting a traded/gifted endgame pet erase early progression.
- Enchants such as HomeWorld, Efficiency, Tactics, Luck, Leadership, and SecretLuck.
- Pet of the Day selected deterministically and displayed on a podium.
- Rare/dark breakable variants with low spawn weight and high value.
- Auto-targeting and auto-delete quality-of-life systems.
- Pet index and collection progress.
- Daily gifts, codes, and reward tracks.
- Limited stock pets/items.
- Seasonal chaseables and event currencies.
- Marketplace/exchange as a later, careful feature.

## Do Not Copy Directly

- Hardcoded Workspace paths.
- Workspace `Value` objects as source of truth.
- Scattered per-feature counters.
- External database/webhook marketplace design.
- One-off Workspace scripts for every area.
- Magic numbers buried in service logic.

## Translation Rule

For every reference feature, ask:

1. What config declares this content?
2. Which service owns the behavior?
3. Which profile fields persist it?
4. Which stats/counters observe it?
5. Which modifier pipeline stage affects it?
6. Which map hooks bind it to Studio geometry?

## Links

- [Decisions](DECISIONS.md)
- [Implementation Plan](../IMPLEMENTATION_PLAN.md)
