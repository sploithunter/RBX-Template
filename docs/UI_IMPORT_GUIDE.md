### UI Import Guide (MCP → Config-as-Code)

This guide explains how to import UI from a classic Studio game (via MCP) into this Rojo/config-as-code project and reproduce it using configuration only.

## Relevant files

- `configs/ui.lua` — central UI configuration (icons, label geometry, actions, panes, rows)
- `src/Client/UI/BaseUI.lua` — builds UI from `configs/ui.lua` (semantic positions, rows, badges, constraints)
- `default.project.json` — Rojo mapping (optionally maps `src/UI_Templates` → `ReplicatedStorage.UI_Templates`)
- Optional: `src/UI_Templates/` — template instances if you use TemplateManager (not required for this button pattern)

## What’s standardized (global defaults you can rely on)

These live under `defaults.menu_button` in `configs/ui.lua` and apply to every `menu_button` unless overridden.

- Icon (MCP style)
  - size = { scale_x = 0.894, scale_y = 0.733 }
  - position = { scale_x = 0.5, scale_y = 0.5 } (center)
- Shape
  - Square buttons via UIAspectRatioConstraint (dominant axis = width, ratio = 1.0)
- Label (button name)
  - font = FredokaOne
  - position_kind = "bottom_center_edge"
    - anchor (0.5, 0.5)
    - position (0.5, 0.925)
    - height scale 0.258
  - stroke
    - color = Color3.fromRGB(0, 53, 76)
    - thickness = 3
    - transparency = 0
    - lineJoin = Miter
  - UITextSizeConstraint applied automatically
- Optional badge (decorator)
  - Container name Noti (with UIAspectRatioConstraint, dominant axis = width)
  - Child text Txt (with UIStroke + UITextSizeConstraint)
  - Corner positions like "top-left-corner" place the badge partly outside the button (sticker look)

## Accessing MCP (what to read)

Use the MCP server (Explorer-like queries) to inspect the live game:

- List children: read `game.StarterGui.Guis` and subfolders (e.g., `Layout.Left`)
- Read properties for layout containers:
  - `Position` (use scale components)
  - `Size` (use scale components)
  - `AnchorPoint` (Don't make assumptions here.  This value is always set even though it's defaulted by studio.  You should always be able to read it.)
- Read per-button info:
  - `Icon.Image` asset IDs (these go into `config.icon = "rbxassetid://..."`)
  - If badges exist, note their text (e.g., "-25%") and placement (typically top-left-corner)

You do NOT need to copy internal button positions from MCP. We standardize layout with evenly spaced rows and square aspect constraints.

## Reusable row layout (square icons, left→right, then top→bottom)

The left pane pattern is deliberately reusable anywhere (left, right, top overlays):

```lua
-- Evenly spaced 3 rows × 2 buttons layout
my_buttons_pane = {
  position_scale = {x = 0.995, y = 0.5},
  size = {scaleX = 0.22, scaleY = 0.26},
  anchor = "center-right",
  layout = {type = "list", direction = "vertical", spacing = 6, padding = {top = 4, bottom = 4, left = 4, right = 4}},
  contents = {
    {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
      {type = "menu_button", config = {name = "A", text = "A", icon = "rbxassetid://...", action = "open_A"}},
      {type = "menu_button", config = {name = "B", text = "B", icon = "rbxassetid://...", action = "open_B"}},
    }}},
    {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
      {type = "menu_button", config = {name = "C", text = "C", icon = "rbxassetid://...", action = "open_C"}},
      {type = "menu_button", config = {name = "D", text = "D", icon = "rbxassetid://...", action = "open_D"}},
    }}},
    {type = "row", config = {height_scale = 0.166, spacing = 8, contents = {
      {type = "menu_button", config = {name = "E", text = "E", icon = "rbxassetid://...", action = "open_E"}},
      {type = "menu_button", config = {name = "F", text = "F", icon = "rbxassetid://...", action = "open_F"}},
    }}}
  }
}
```

- `height_scale = 0.166` ≈ one-sixth of the pane’s height per row. Adjust as needed.
- Buttons inherit icon size, square aspect, bottom-center-edge label, and stroked text.
- To add a Store-style sticker:
  - `notification = { enabled = true, text = "-25%", position = "top-left-corner", aspect_ratio = 1.6 }`

## Mapping MCP → config quickly

- Container (pane)
  - MCP Position → `pane.position_scale = {x = ..., y = ...}`
  - MCP Size → `pane.size = {scaleX = ..., scaleY = ...}`
  - MCP Anchor → `pane.anchor = "center-left" | "center-right" | "top-center" | ...`
- Button
  - MCP Icon.Image → `config.icon = "rbxassetid://..."` (icons are big by default via global `icon_config`)
  - Label defaults are already MCP-like; override `text_config` only if necessary
  - Sticker/promo → `config.notification` fields

## Hooking behavior (actions)

Buttons call named actions; wire them under `ui.actions`:

```lua
actions = {
  open_A = { type = "menu_panel", panel = "A", transition = "slide_in_right" },
  open_B = { type = "menu_panel", panel = "B", transition = "fade_in" },
}
```

You can also map to script calls, network calls, etc., as already demonstrated in `configs/ui.lua`.

## Recommended import workflow

1) Inspect MCP containers and record Position/Size (scale) + Anchor.
2) Design your target pane (position_scale, size, anchor).
3) Use the row pattern, add `menu_button`s with `{ name, text, icon, action }`.
4) If the Store needs a badge, enable `notification` and set text/effect.
5) Preview and nudge offsets only if necessary. The defaults match MCP proportions.

With these defaults and `BaseUI`, reproducing this button layout in any pane is configuration-only and repeatable.

## Quick reference and patterns

### Icon and text positioning

- **icon_config.position_kind**: `left_center_edge`, `right_center_edge`, `top_center_edge`, `bottom_center_edge`
  - These keep the icon's AnchorPoint at (0.5, 0.5) and snap to the chosen edge using relative scale.
  - Optional: `icon_config.offset = { x = 0, y = 0 }` to nudge in pixels.

- **text_config.position_kind**:
  - `bottom_center_edge` (default): label spans the bottom area MCP-style.
  - `right_center`: Anchor (1, 0.5), Position (1, 0.5). Add inset with `text_config.position.side_margin` (pixels).
  - `manual`: provide exact `anchor_point`, `position_scale` and `position_offset`.

### Aspect ratios (per button)

- Square: `aspect = { ratio = 1.0, dominant_axis = "width" }`
- Wide: `aspect = { ratio = 2.0, dominant_axis = "width" }`
- Avoid uneven ratios like 2.2 unless intentionally stretched.

### Backgrounds vs icons

- `background_image` sets the ImageButton’s background (full button skin).
- `icon` is a foreground ImageLabel/emoji layered above the background.
- Scale icons with `icon_config.size = { scale_x, scale_y }` (relative to button).
- Asset IDs may be `"rbxassetid://123"` or just `"123"` (auto-normalized).

### Patterns

- Wide button with left-edge icon and right-justified text
```lua
{type = "menu_button", config = {
  name = "FollowUs",
  text = "Follow US",
  background_image = "rbxassetid://17016922306",
  icon = "rbxassetid://113655698755065",
  icon_config = { position_kind = "left_center_edge", size = {scale_x = 0.65, scale_y = 0.65} },
  text_config = { position_kind = "right_center", position = { side_margin = 10 } },
  aspect = { ratio = 2.0, dominant_axis = "width" },
  action = "rewards_action"
}}
```

- Square button with badge
```lua
{type = "menu_button", config = {
  name = "Gifts",
  text = "Gifts",
  background_image = "rbxassetid://16992152563",
  icon = "rbxassetid://17016894485",
  icon_config = { size = {scale_x = 0.9, scale_y = 0.9} },
  aspect = { ratio = 1.0, dominant_axis = "width" },
  notification = { enabled = true, text = "1", position = "top-left-corner" },
  action = "rewards_action"
}}
```

### MCP → config checklist

- Pane: `Position` (scale), `Size` (scale), `AnchorPoint`
- Button: `background_image`, `icon` asset, `text_config.position_kind` (e.g., `right_center` or `bottom_center_edge`), `notification`
- Layout: list/grid rows and `height_scale` per row

### Common pitfalls

- Using non-square aspect for square buttons
- Forgetting `background_image` for buttons that use baked art
- Icon looks tiny: increase `icon_config.size` (0.6–0.9 typical)
- Right-justified text done with offsets only; prefer `position_kind = "right_center"` plus `side_margin`

### Troubleshooting

- If text AnchorPoint/Position don’t match the kind, ensure the kind is one of the supported values and avoid overriding `anchor_point`/`position_scale` unless using `manual`.
- If images appear stretched, confirm `aspect.ratio` and `dominant_axis`.