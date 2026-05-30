--[[
    Follow.server.lua — RETIRED (issue #4).

    Pet movement, follow/attack positioning, and the mining damage tick are now
    owned by the server-side, config-driven PetFollowService
    (src/Server/Services/PetFollowService.lua), composing the pure PetFormation
    core with CombatService:ResolvePetDamage (PowerFormula + the modifier
    pipeline). The ~1100 lines of legacy per-pet constraint / BodyMover movement
    code that used to live here were removed.

    This file remains only as an inert stub: PetHandler still clones it onto each
    pet model, so the instance must exist. It intentionally does nothing.

    Rollback (if ever needed) is via git history, not a runtime flag — the legacy
    movement code no longer exists in-tree.
]]

return
