#!/usr/bin/env python3
"""Copy renamed UI icons into assets and build a labeled contact sheet."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


DEFAULT_MAPPING = {
    "blue_icon_001.png": "plus.png",
    "blue_icon_002.png": "fist.png",
    "blue_icon_003.png": "target_down.png",
    "blue_icon_004.png": "shield_broken.png",
    "blue_icon_005.png": "shield.png",
    "blue_icon_006.png": "target.png",
    "blue_icon_007.png": "fist_broken.png",
    "blue_icon_008.png": "coins_up.png",
    "blue_icon_009.png": "clover_lucky.png",
    "blue_icon_010.png": "gift_up.png",
    "blue_icon_011.png": "plus_down.png",
    "blue_icon_012.png": "capacitor.png",
    "blue_icon_013.png": "user_desk.png",
    "blue_icon_014.png": "capacitor.png",
    "blue_icon_015.png": "user_desk.png",
    "blue_icon_016.png": "arrow_right.png",
    "blue_icon_017.png": "history.png",
    "blue_icon_018.png": "fist_impact.png",
    "blue_icon_019.png": "star_sparkle.png",
    "blue_icon_020.png": "armor_chest.png",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a labeled icon contact sheet.")
    parser.add_argument(
        "input_dir",
        nargs="?",
        help="Directory of normalized icon PNGs (optional with --rebuild-from)",
    )
    parser.add_argument(
        "--output-dir",
        default="assets/ui/blue_icons",
        help="Destination for renamed icons",
    )
    parser.add_argument(
        "--contact-sheet",
        default="assets/ui/blue_icons/contact_sheet.png",
        help="Contact sheet output path",
    )
    parser.add_argument(
        "--rebuild-from",
        help="Rebuild contact sheet from an existing assets directory (skips copy step)",
    )
    parser.add_argument("--columns", type=int, default=5, help="Grid columns")
    parser.add_argument("--thumb-size", type=int, default=256, help="Max icon size in sheet")
    parser.add_argument("--label-height", type=int, default=36, help="Label area height")
    parser.add_argument("--padding", type=int, default=24, help="Padding between cells")
    return parser.parse_args()


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


def fit_image(image: Image.Image, max_size: int) -> Image.Image:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    scale = min(max_size / width, max_size / height, 1.0)
    if scale == 1.0:
        return rgba
    new_size = (max(1, int(width * scale)), max(1, int(height * scale)))
    return rgba.resize(new_size, Image.Resampling.LANCZOS)


def unique_entries(input_dir: Path, mapping: dict[str, str]) -> list[tuple[str, Path, str]]:
    seen_names: set[str] = set()
    entries: list[tuple[str, Path, str]] = []
    skipped: list[str] = []

    for source_name, target_name in mapping.items():
        source_path = input_dir / source_name
        if not source_path.exists():
            continue
        if target_name in seen_names:
            skipped.append(f"{source_name} -> {target_name} (duplicate)")
            continue
        seen_names.add(target_name)
        entries.append((target_name, source_path, source_name))

    return entries, skipped


def build_contact_sheet(
    icons: list[tuple[str, Image.Image]],
    output_path: Path,
    columns: int,
    thumb_size: int,
    label_height: int,
    padding: int,
) -> None:
    if not icons:
        raise ValueError("No icons provided for contact sheet.")

    rows = math.ceil(len(icons) / columns)
    cell_w = thumb_size + padding * 2
    cell_h = thumb_size + label_height + padding * 2
    sheet = Image.new("RGBA", (columns * cell_w, rows * cell_h), (48, 48, 48, 255))
    draw = ImageDraw.Draw(sheet)
    font = load_font(18)

    for index, (name, image) in enumerate(icons):
        col = index % columns
        row = index // columns
        x0 = col * cell_w + padding
        y0 = row * cell_h + padding

        fitted = fit_image(image, thumb_size)
        paste_x = x0 + (thumb_size - fitted.width) // 2
        paste_y = y0 + (thumb_size - fitted.height) // 2
        sheet.paste(fitted, (paste_x, paste_y), fitted)

        label = Path(name).stem
        text_y = y0 + thumb_size + 8
        draw.text((x0 + thumb_size / 2, text_y), label, fill=(235, 235, 235, 255), font=font, anchor="ma")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, format="PNG", optimize=True, compress_level=9)


def main() -> int:
    args = parse_args()

    if args.rebuild_from:
        assets_dir = Path(args.rebuild_from).expanduser().resolve()
        contact_sheet = Path(args.contact_sheet).expanduser().resolve()
        icons = sorted(
            p
            for p in assets_dir.glob("*.png")
            if p.is_file() and p.name != contact_sheet.name
        )
        if not icons:
            raise SystemExit(f"No icons found in {assets_dir}")

        sheet_icons = [(path.name, Image.open(path)) for path in icons]
        build_contact_sheet(
            sheet_icons,
            contact_sheet,
            args.columns,
            args.thumb_size,
            args.label_height,
            args.padding,
        )

        manifest_lines = [
            f"assets_dir: {assets_dir}",
            f"icon_count: {len(icons)}",
            "",
            *[path.name for path in icons],
            "",
            f"contact_sheet: {contact_sheet.name}",
        ]
        (assets_dir / "manifest.txt").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
        print(f"Rebuilt contact sheet with {len(icons)} icons")
        print(f"Contact sheet: {contact_sheet}")
        return 0

    if not args.input_dir:
        raise SystemExit("Provide input_dir or use --rebuild-from")

    args.input_dir = Path(args.input_dir).expanduser().resolve()
    input_dir = args.input_dir
    output_dir = Path(args.output_dir).expanduser().resolve()
    contact_sheet = Path(args.contact_sheet).expanduser().resolve()

    entries, skipped = unique_entries(input_dir, DEFAULT_MAPPING)
    if not entries:
        raise SystemExit(f"No mapped icons found in {input_dir}")

    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_lines = [
        f"source_dir: {input_dir}",
        f"output_dir: {output_dir}",
        f"unique_icons: {len(entries)}",
        "",
    ]

    sheet_icons: list[tuple[str, Image.Image]] = []
    for target_name, source_path, source_name in entries:
        image = Image.open(source_path)
        destination = output_dir / target_name
        image.save(destination, format="PNG", optimize=True, compress_level=9)
        sheet_icons.append((target_name, image))
        manifest_lines.append(f"{target_name}\t<- {source_name}")

    if skipped:
        manifest_lines.extend(["", "skipped_duplicates:"])
        manifest_lines.extend(skipped)

    build_contact_sheet(
        sheet_icons,
        contact_sheet,
        args.columns,
        args.thumb_size,
        args.label_height,
        args.padding,
    )

    manifest_lines.extend(["", f"contact_sheet: {contact_sheet.name}"])
    (output_dir / "manifest.txt").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

    print(f"Wrote {len(entries)} icons to {output_dir}")
    print(f"Contact sheet: {contact_sheet}")
    if skipped:
        print(f"Skipped {len(skipped)} duplicate(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
