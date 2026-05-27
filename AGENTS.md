# Agent Instructions

This project uses a lightweight Karpathy-style LLM wiki. Treat the wiki as persistent project memory.

## Start Of Work

1. Read `docs/wiki/INDEX.md`.
2. Read any linked wiki page relevant to the task before making architectural or gameplay changes.
3. Prefer the wiki for current project decisions, but verify against source files before editing code.

## During Work

Update the wiki when you make or discover anything that should survive the chat:

- Architecture decisions or reversals.
- Map/Studio/Rojo contract changes.
- New services, configs, data shapes, network packets, or save fields.
- Important implementation gotchas.
- Reference-game findings worth preserving.
- Manual Studio workflow discoveries.
- Open questions that block or shape future work.

Do not update the wiki for tiny mechanical edits, formatting-only changes, or facts that are already captured accurately.

## Wiki Rules

- Keep pages short and linked.
- Prefer updating an existing page over creating a duplicate.
- Add a dated entry to `docs/wiki/LOG.md` for meaningful sessions.
- If a page may be stale, mark it clearly rather than silently trusting it.
- Raw source notes belong in `docs/wiki/raw/`; synthesized project knowledge belongs in normal wiki pages.
- The wiki is maintained by agents, but source code and formal requirements remain the final authority.

## Useful Commands

- `python3 scripts/wiki_status.py`

