# Emergent Behaviors

Mechanics that fell out of systems interacting rather than being designed — kept
deliberately (or at least knowingly). Each entry records the behavior, the systems
that produce it, and the verdict, so a future refactor doesn't "fix" something
players actually experience as a feature.

## Dormant zones (2026-06-11)

**Behavior:** A zone the local player hasn't unlocked appears *asleep*: any ore lit
by a previous key-holder gets mined out or swept by the inactive-world despawn, and
nothing repopulates until a player with the unlock is present. New players walking
into a locked biome see a depleted, still landscape that visibly "wakes up" —
crystals blooming — when someone who's earned it arrives.

**Produced by:** BreakableSpawner's active-world rule (a biome only spawns ore
while at least one *currently present* player has it unlocked) + the per-miner
zone gate (PetFollowService:_mine / AutoTargetService refuse locked-zone nodes)
+ open world geometry (walking in is never blocked).

**Verdict:** Keeper. It conveys "this place has nothing for you *yet*" with zero
UI, and the effect concentrates in small/early servers — exactly where new players
live. Optional lean-in someday: faint mist / "dormant" ambience on un-lit zones via
the area theme config. (Jason: "that's actually could be an interesting game
mechanic... probably not super useful but still.")

## Window-shopping locked zones (2026-06-11)

**Behavior:** Locked zones are physically enterable — players can walk through
Ice/Lava/Desert before unlocking, see the terrain and (if another player has it
lit) the ore they can't mine. The unlock buys *profit*, not *passage*.

**Produced by:** Open world geometry (no barriers) + server-side enforcement
living at the payout (the mine gate), not the border.

**Verdict:** Keeper. Previewing the next biome is better marketing than a wall;
enforcement at the economic layer is also simpler and cheat-resistant. Watch-item:
whether silent mining refusal needs a "🔒 Unlock Ice Fields first" nudge.
