# Enhancement Store — design + plan

Buy/sell enhancements for **gems**. v1 scope and decisions locked with Jason.

## Decisions (locked)

- **Scope v1: NATURALS ONLY.** Origin (single/dual) enhancements stay drop-only / field-earned so they
  keep their value. `grade_mult` leaves room to price single/dual later.
- **Currency: gems.**
- **Pricing: STATIC** — a pure function of band level. `buy = base + per_level × level`, **flat across
  types** (natural magnitude 0.15 is identical on every axis, so type doesn't change price). No dynamic
  market (exploit-prone; revisit later). `EnhancementPricing` is the headless-tested SSOT.
- **Level gate:** sold in **increments of 5**, and the store shows the **one band the player can
  currently SLOT** — the nearest multiple of 5, which is always within the ±2 slot window.
  `band = round(playerLevel / 5) × 5` → L16-17 see **L15**, L18-22 see **L20**, L23-27 see **L25**, …
  Clamped to `[min_level, max_level]` (5..50). `spark` (rare proc tier) is excluded — found, not bought.
- **Sell-back: YES** (the junk sink). `sell = floor(value × fraction)` gems, **un-slotted stacks only**,
  fraction clamped to ≤1 so a sell never beats the buy (no arbitrage). Start at 30%. Unlike buy, sell
  uses the item's **actual level** (smooth 1–50, so L14 > L13), and works for **any grade** the player
  owns — single/dual have a real buyback even though they aren't sold.
- **Grade scaling (rarity-derived):** `grade_mult` from drop odds (rarer drop = pricier). Drops are
  natural 50% / dual 32.5% / single 17.5% → inverse, normalized to natural=1 → **dual ×1.54, single
  ×2.86**. One `grade_mult` table drives both buy and sell. `buyable_grades` (v1 = naturals only) gates
  *buying*; selling accepts all grades.
- **Tracking: free** — the gem ledger already records every move by `source`
  (`enh_buy:<type>_L<level>`, `enh_sell:…`). Add lifetime `enhancements_bought` / `enhancements_sold`
  stats to mirror `enhancements_found`; OpsAlert can flag anomalies.

## Starting price table (TUNE vs gem income — `configs/enhancements.lua` `shop` knobs)

base 20, per_level 10, sell 0.30:

| Band | Buy (gems) | Sell-back |
|------|-----------|-----------|
| L5   | 70        | 21        |
| L10  | 120       | 36        |
| L15  | 170       | 51        |
| L20  | 220       | 66        |
| L25  | 270       | 81        |
| L50  | 520       | 156       |

## Build phases

1. **DONE — pricing core.** `configs/enhancements.lua` `shop` block + `src/Shared/Game/EnhancementPricing.lua`
   (`bandFor` / `buyPrice` / `sellPrice`) + `tests/headless/specs/enhancement_pricing.spec.luau`.
2. **DONE — service + bus.** `EnhancementShopService` (`Catalog`/`Buy`/`Sell`) +
   `enhancement.shop.{catalog,buy,sell}` bus commands + boot registration.
   - **Stacks:** Buy routes through `EnhancementService:Grant` (increments the matching stack's
     quantity — no dup uids); Sell decrements by `quantity` via `InventoryService:RemoveItem` (deletes
     the stack at 0) and refunds `sellPrice × quantity`.
   - Buy: validate type/grade → deduct gems (`enh_buy:<type>_L<band>`) → Grant → **refund on grant
     fail** → critical save. Sell: read grade off the owned stack (single/dual buy back too) → remove
     N → `AddCurrency` (`enh_sell:<uid>`) → save.
   - Band uses `player:GetAttribute("Level")` (same source slotting uses → shown band always slottable).
   - Pending: live E2E via the bus (needs a Play session); lifetime `enhancements_bought/sold` stats.
3. **Sell-back polish + junk-sink event.** Wire a GameEvents reaction on sell (closes pending E9), add
   the lifetime stats.
4. **DONE (needs live tuning) — buy-to-fill UI.** Integrated into the `PowerChoiceMenu` slotting flow
   (Jason's pick) rather than a standalone shop: band-natural **buy offers appear as gem-priced entries
   in the existing AVAILABLE grid** (compatible types, sorted last since naturals are low value), with
   affordability dimming + the gem balance in the strip header. Clicking a buy offer →
   `enhancement.shop.buy` → stages the bought enhancement for the targeted slot → existing APPLY path
   slots it (CANCEL keeps it in inventory). Reuses the tested grid layout, so structurally low-risk.
   **Pending: live visual pass** (layout/price-chip placement; can't verify without a Play session).
   Sell-from-inventory UI + lifetime stats still to come.

## Anti-exploit invariants

- Buy price > sell price always (fraction ≤ 1).
- Server validates band == `bandFor(playerLevel)` (can't buy off-band), gem balance (atomic
  `RemoveCurrency`), and inventory cap (Grant refuses when full).
- Sell requires ownership + not currently slotted.
