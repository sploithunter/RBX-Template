### UI Import Guide (MCP → Config-as-Code)

This guide explains how to import UI from a classic Studio game (via MCP) into this Rojo/config-as-code project and reproduce it using configuration only.

## Relevant files

- `configs/ui.lua` — central UI configuration (icons, label geometry, actions, panes, rows)
- `src/Client/UI/BaseUI.lua` — builds UI from `configs/ui.lua` (semantic positions, rows, badges, constraints)
- `default.project.json` — Rojo mapping (optionally maps `src/UI_Templates` → `ReplicatedStorage.UI_Templates`)
- Optional: `src/UI_Templates/` — template instances if you use TemplateManager (not required for this button pattern)

## Imported layout convention

- The first step of an import is to mirror the target game's major layout frames as configuration-only anchors. These are created under `ui.panes` and are always prefixed with `imported_`.
- Examples: `imported_top_bar`, `imported_bottom_bar`, `imported_left_rail`, `imported_right_cluster`, `imported_boosts_stack`, `imported_notifications`.
- Each imported pane records only the MCP container’s relative Position (scale), Size (scale), and AnchorPoint. Their purpose is to act as anchors/containers for subsequent UI we reconstruct via config.
- Follow-up passes then replace the placeholder contents inside these `imported_*` panes with real elements (`currency_display`, `menu_button`, `row`, etc.) while preserving their position/size semantics.

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
- Aspect constraints
  - Most imported buttons and currency cards use `UIAspectRatioConstraint`. Capture:
    - `AspectRatio` (width/height)
    - `DominantAxis` (usually width)
  - In config, set per element:
    - `aspect = { ratio = <number>, dominant_axis = "width" | "height" }`
  - This preserves MCP shapes across different resolutions.
  - Container name Noti (with UIAspectRatioConstraint, dominant axis = width)
  - Child text Txt (with UIStroke + UITextSizeConstraint)
  - Corner positions like "top-left-corner" place the badge partly outside the button (sticker look)

### New: Text label with depth (Inner duplicate)

- Pattern name in config: `text_label_with_depth`
- Where it shows up in MCP:
  - A `TextLabel` with a child `TextLabel` named `Inner`
  - Both have the same text, font, and colors
  - The child `Inner` has `Size = {1,0},{1,0}` (fills the parent) and a slight positional offset (scale-based), commonly around Y ≈ 0.469 vs parent 0.5
  - Both usually have a bold `UIStroke` (thickness ~4) and a `UITextSizeConstraint`
- In our config-as-code, you just declare:

```lua
{ type = "text_label_with_depth", config = {
  text = "Codes",
  position_scale = { x = 0.27, y = 0.021 },
  size = { scaleX = 0.305, scaleY = 0.451 },
  rotation = -2,
  -- Most values come from global defaults (see defaults.text_label_with_depth)
  -- Only override when MCP differs
}}
```

- Global defaults (set in `configs/ui.lua.defaults.text_label_with_depth`):
  - `font = FredokaOne`
  - `stroke = { color = Color3.fromRGB(0,55,70), thickness = 4 }`
  - `text_size_constraint = { max_text_size = 48, min_text_size = 12 }`
  - `depth_offset = { x = 0, y = -0.031 }` (applied to the Inner child)

- Recognizing it quickly in MCP:
  - If a title or big label appears to “pop”, check for a child `Inner` TextLabel
  - Confirm both labels have `UIStroke`; inner is positioned slightly offset from center
  - Prefer capturing scale components for `Position`/`Size`; avoid pixel offsets

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

## Practical advice from recent imports

### What to capture from MCP (and how)

- Pane anchors: Record Position (scale), Size (scale), AnchorPoint for each major container; create `imported_*` panes that mirror those anchors.
- Aspect ratios: Most buttons/cards use `UIAspectRatioConstraint`. Copy `AspectRatio` and `DominantAxis`.
- Icons: Asset IDs from `Icon.Image` (normalize to `rbxassetid://123`). Prefer semantic positions: `icon_config.position_kind = "left_center_edge"` with minimal offset.
- Amount text: Font, stroke, gradient.
  - Font: FredokaOne
  - Stroke: color `Color3.fromRGB(102,56,0)`, thickness `2.5`
  - Gradient: Use the console snippet below to extract `ColorSequence` as keypoints. Paste into `amount_config.gradient.keypoints`.
- Plus buttons: Note which currencies have a `+`. Our builder auto-reserves right padding when a plus is present so centered labels stay visually centered.

### Things we wish we knew upfront (Codes import)

- Close buttons in MCP are typically pure ImageButtons with an image asset (no TextLabel child). Do not add a text child.
- The submit button text also uses the same depth pattern as titles; replicate it with `text_label_with_depth` rather than a plain label.
- For parity, always prefer scale-based `Position`/`Size` from MCP over pixel offsets; it matches across resolutions.
- When importing titles/labels, check for `UIStroke` thickness on both parent and `Inner` (often 4). Capture `MaxTextSize` when present.

### UI builder features to leverage

- Centering and spacing: In list layouts set `horizontal_alignment = "center"` and use `layout.padding.left/right` to avoid edge crowding. Use `spacing` to spread siblings evenly.
- Auto-fit sizing: For horizontal lists, if an element has `aspect = { ratio, dominant_axis }` and no explicit size, the builder will size each child to fill available width (minus spacing and padding) while respecting the pane height and aspect ratio.
- Gradients in config: You can specify either a `ColorSequence` directly or a portable `keypoints` table:

```lua
amount_config = {
  gradient = {
    rotation = -90,
    keypoints = {
      { t = 0.000, color = { r = 255, g = 162, b = 0 } },
      { t = 1.000, color = { r = 255, g = 247, b = 0 } },
    },
  }
}
```

### Quick checklist (top currencies example)

1. Create/verify `imported_top_bar` with Position/Size/Anchor from MCP.
2. Add three `currency_display` items with:
   - `background_image` (panel art)
   - `icon_config = { position_kind = "left_center_edge", size = { scale_x, scale_y } }`
   - `aspect = { ratio = 3.8, dominant_axis = "width" }` (or from MCP)
   - `amount_config` with `font = FredokaOne`, `stroke` (102,56,0, thickness 2.5), and `gradient.keypoints` (yellow range)
   - `plus_button` for premium currencies
3. Set `layout = { type = "list", direction = "horizontal", horizontal_alignment = "center", spacing = 10–12, padding = { left = 8–16, right = 8–16 } }`.
4. Ensure any legacy debug backgrounds are disabled (`debug.show_backgrounds = false`, pane `background.enabled = false`).

### Common pitfalls (and fixes)

- Forgetting aspect constraints → Buttons look stretched; add `aspect = { ratio, dominant_axis }` from MCP.
- Text not centered with plus button → Our builder now reserves right padding when `plus_button.enabled` is true.
- Left/right fill misaligned → Use `horizontal_alignment = "center"` and set `layout.padding.left/right`.
- Wrong icon anchoring → Prefer `icon_config.position_kind` over manual X offsets; keep offset small (0–3 px) for parity.
- Overlays showing debug backgrounds → Set `debug.show_backgrounds = false` and disable pane backgrounds.

## Quick reference and patterns

### Icon and text positioning

- **icon_config.position_kind**: `left_center_edge`, `right_center_edge`, `top_center_edge`, `bottom_center_edge`, `center`
  - These keep the icon's AnchorPoint at (0.5, 0.5) and snap to the chosen edge using relative scale.
  - Optional: `icon_config.offset = { x = 0, y = 0 }` to nudge in pixels.

- **text_config.position_kind**:
  - `bottom_center_edge` (default): label spans the bottom area MCP-style.
  - `right_center`: Anchor (1, 0.5), Position (1, 0.5). Add inset with `text_config.position.side_margin` (pixels).
  - `center`: Anchor (0.5, 0.5), Position (0.5, 0.5). Use `position_offset` to nudge (e.g., `{ x = -10, y = 0 }`).
  - `manual`: provide exact `anchor_point`, `position_scale` and `position_offset`.

### Aspect ratios (per button)

- Square: `aspect = { ratio = 1.0, dominant_axis = "width" }`
- Wide: `aspect = { ratio = 2.0, dominant_axis = "width" }`
- Avoid uneven ratios like 2.2 unless intentionally stretched.

### Button lists and child sizing (important for imported bottom bars)

- In horizontal list layouts, a child without an explicit `size` will try to fill available space.
- For wide buttons in a bar, set both axes so height doesn't collapse or overfill:
  - `size = { scaleX = 0.40–0.50, scaleY = 0.45–0.55 }`
  - Combine with `aspect = { ratio = 2.0, dominant_axis = "width" }` for rounded-rect skins.
- Use list `spacing` and `padding.left/right` to fine tune gaps between buttons.

### Backgrounds vs icons

- `background_image` sets the ImageButton’s background (full button skin).
- `icon` is a foreground ImageLabel/emoji layered above the background.
- Scale icons with `icon_config.size = { scale_x, scale_y }` (relative to button).
- Asset IDs may be `"rbxassetid://123"` or just `"123"` (auto-normalized).

### Notification badge sizing (FREE, counts, stickers)

- Prefer scale-based badge sizing so it scales with the button:
  - `notification.size = { scale_x = 0.25–0.35, scale_y = 0.25–0.35 }`
- Use `aspect_ratio` to make pills vs squares (e.g., 2.0 for a small "FREE" pill).
- Avoid pixel sizes for badges except for tiny nudges; scale keeps parity across resolutions.

### Label text sizing defaults

- The builder applies a `UITextSizeConstraint` to button labels:
  - `MaxTextSize = 48`
  - `MinTextSize = 13`
  - Override with `text_config.max_text_size` / `text_config.min_text_size` if needed.

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

### Extracting ColorSequence gradients from MCP

To copy a UIGradient's colors from the MCP game into config-as-code, run this in the Studio console:

```lua
local g = game.StarterGui.Guis.Layout.Top.Currencies.Crystals.Amt:FindFirstChildOfClass("UIGradient")
local out = {}
for _,kp in ipairs(g.Color.Keypoints) do
  local c = kp.Value
  table.insert(out, string.format("{ t = %.3f, color = { r = %d, g = %d, b = %d } }",
    kp.Time, math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5)))
end
print("keypoints = {"..table.concat(out, ", ").."}")
```

Then paste the printed table into your element config:

```lua
amount_config = {
  gradient = {
    rotation = -90,
    keypoints = { { t = 0.000, color = { r = 255, g = 162, b = 0 } }, { t = 1.000, color = { r = 255, g = 247, b = 0 } } },
  }
}
```

The UI builder understands both direct `ColorSequence` values and this `keypoints` table format.

### Why we prefix anchors with imported_

Imported panes represent raw frame anchors from the reference game. Keeping them under `imported_*` makes the import process repeatable and keeps anchor discovery separate from semantic content. Replace each placeholder’s contents with real elements (`currency_display`, `menu_button`, `row`), not the anchors themselves.

### MCP overlays, thumbnails, and badges (advanced)

- **rbxthumb icons**: You can use Roblox thumbnails directly in `icon`.
  - Example: `"rbxthumb://type=AvatarHeadShot&id=USER_ID&w=420&h=420"`.
  - Useful for creator/profile badges and dynamic images.

- **Grid fill when using absolute anchors**: If a pane uses `position_scale` (MCP-style absolute position), also set a semantic `position` so grids fill from the expected corner.
  - Example: `position = "bottom-left"` + `position_scale = { x = ..., y = ... }` → grid `StartCorner = BottomLeft`.

- **Square aspect for imported buttons**: MCP buttons that should look square need `aspect = { ratio = 1.0, dominant_axis = "width" }` on each `menu_button`.

- **Notification badge controls**: The badge decorator supports size, corner radius, and tilt.
  - Fields: `size {pxX, pxY}`, `corner_radius`, `rotation`, `text_stroke_*`, and optional `gradient` on the badge text.
  - Example (tilted blue square with a white check):

```lua
notification = {
  enabled = true,
  text = "✓",
  position = "top-right-corner",
  size = { pxX = 18, pxY = 18 },
  corner_radius = 4,
  rotation = 15,
  background_color = Color3.fromRGB(41, 121, 255),
  text_color = Color3.fromRGB(255, 255, 255),
  text_stroke_color = Color3.fromRGB(0, 0, 0),
  text_stroke_thickness = 1.5
}
```

- **Overlay label pattern for MCP glyphs**: Builders often layer a TextLabel with gradient + stroke on top of the button. Use `overlay_label` on a `menu_button`:

```lua
overlay_label = {
  enabled = true,
  text = "", -- MCP PUA glyph
  height_scale = 1.0,
  position_kind = "center",
  -- Small nudge keeps it visually centered while staying relative
  position_offset = { x = -5, y = 0 },
  stroke = { color = Color3.fromRGB(49, 64, 88), thickness = 2, transparency = 0 },
  gradient = {
    rotation = -90,
    keypoints = {
      { t = 0.000, color = { r = 165, g = 197, b = 255 } },
      { t = 1.000, color = { r = 255, g = 255, b = 255 } },
    }
  },
  aspect_ratio = 1.0,
  text_max_size = 36
}
```

- **Extract both gradient and stroke**: When copying from MCP, capture `UIGradient` keypoints and `UIStroke` color/thickness from the source TextLabel for 1:1 visuals.

- **Dev visibility when mapping**: During import, enable pane backgrounds or set `ui.debug.show_backgrounds = true` to see bounds and layout while adjusting anchors.