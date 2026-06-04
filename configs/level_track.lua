--[[
    Level track — what each level-up GRANTS (Halo & Horns, City-of-Heroes style).

    Total XP -> earnedLevel (LevelCurve). The player CLAIMS one level at a time; each claim
    runs this track for the new level. Pure lookup lives in src/Shared/Game/LevelTrack.lua;
    PlayerProgressionService:ClaimLevel applies it (S2). Every number here is a dev knob.

    A level can carry several rewards at once (flags are independent), but `kind` picks the
    headline the UI leads with: "power" > "milestone" > "slot" > "reward".

    IMPORTANT (sync): `power_levels` MUST match configs/powers.lua `selection_levels` and
    `slot_levels` MUST match configs/augmentation.lua `slot_grant_levels` — those configs gate
    the actual PowerService/Augmentation eligibility; this track only decides the level-up
    presentation + the bundled rewards. Keep them aligned (S3 will widen both toward 50).
]]

return {
    version = "1.0.0",
    max_level = 50,

    -- +1 egg max-hatch EVERY level: hatch = base + (claimedLevel - 1) * per_level.
    -- base 3 at L1 climbs to ~52 at L50. Consumed in HatchEntitlementService:GetMaxHatchCount.
    egg_hatch = {
        base = 3,
        per_level = 1,
    },

    -- Levels where the claim opens the POWER PICKER (PowerSelection / PowerService:Select).
    -- Mirror of powers.lua selection_levels.
    power_levels = { 5, 9, 13, 17, 21, 25 },

    -- Levels where the claim GRANTS enhancement slots to place on owned powers (Augmentation).
    -- Mirror of augmentation.lua slot_grant_levels. `slots_per_grant` enhancement slots each.
    slot_levels = { 8, 12, 18, 25, 35, 45 },
    slots_per_grant = 2,

    -- Big moments. Headline flair + a bundle from milestone_rewards below.
    milestones = { 10, 20, 30, 40, 50 },

    -- HYBRID gate (City-of-Heroes "train at a trainer"): which level KINDS must be claimed at
    -- the Ascension Altar vs auto-claimed in the field. Filler reward levels auto-apply with a
    -- toast; power/slot/milestone levels stall until you visit the altar (-> reveal modal).
    -- Set all false to revert to claim-anywhere.
    altar_kinds = {
        power = true,
        slot = true,
        milestone = true,
        reward = false,
    },

    -- The Ascension Altar station (a world part tagged "AscensionAltar"). If the map already has
    -- a tagged part, that's used; otherwise AscensionAltarService spawns a placeholder pillar at
    -- `position` (reskin later — the logic keys off the tag, not the visual).
    altar = {
        enabled = true,
        position = { 0, 6, 0 }, -- near Spawn; tune to taste (studs)
        size = { 6, 12, 6 },
        color = { 255, 205, 70 },
        action_text = "Ascend",
        object_text = "Ascension Altar",
        max_distance = 14,
        hold_duration = 0,
        key = "E",
    },

    -- Reward bundles (RewardBundle shape: { currencies = {...}, pets = {...}, ... }).
    -- `default` is granted on every plain "filler" level; per-level overrides stack on top.
    -- Kept light for now (S2/S3 flesh these out); coins scale a touch so later levels feel
    -- bigger. The bulk of non-power content is intended to come via quests + rewards.
    rewards = {
        default = { currencies = { Gems = 5 } },
    },

    -- Milestone bundles (granted IN ADDITION to the per-level reward). Creative latitude —
    -- team-size bumps, guaranteed pets, etc. land here as the systems wire up (S2+).
    milestone_rewards = {
        [10] = { currencies = { Gems = 25 } },
        [20] = { currencies = { Gems = 50 } },
        [30] = { currencies = { Gems = 75 } },
        [40] = { currencies = { Gems = 100 } },
        [50] = { currencies = { Gems = 200 } },
    },
}
