--[[
    Focus — Halo & Horns [PROTOTYPE] (Feature 12: Player Character / Spirit Presence).

    The player is an ethereal, invulnerable supporter: NO health stat exists.
    Instead the player has a Focus pool spent to cast support powers, regenerating
    over time and disrupted by enemy "Sundering" attacks. Read by
    `src/Shared/Game/FocusMath.lua`.

    Open design question (GWT Feature 12 — "Focus regen pauses while at zero"):
    resolved to ALWAYS regenerate (no stun-at-zero). See docs/wiki/DECISIONS.md.
    The behavior is config-flagged so a game can opt into a stun later.
]]

return {
    focus_max = 100,
    regen_per_second = 5,
    -- false: Focus regenerates normally even from 0 (the resolved default).
    -- true: Focus stays at 0 for one tick of "stun" before regen resumes.
    regen_pauses_at_zero = false,
}
