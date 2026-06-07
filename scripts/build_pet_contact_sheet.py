#!/usr/bin/env python3
"""Import pet model images and build labeled master contact sheets.

Primary source: ~/Downloads/PetImages/Basic and ~/Downloads/PetImages/Gold.
Expected filenames: {pet_id}_basic.png and {pet_id}_gold.png (e.g. bear_basic.png).
Basic supplements missing safari / preview pets from tracked repo assets.
"""

from __future__ import annotations

import argparse
import math
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets/exports/pets/basic"
SHEET_PATH = ROOT / "assets/exports/pets/basic_models_contact_sheet.png"
GOLD_OUT_DIR = ROOT / "assets/exports/pets/gold"
GOLD_SHEET_PATH = ROOT / "assets/exports/pets/gold_models_contact_sheet.png"

# Fallback repo assets when a pet is not in the Downloads Basic folder.
SUPPLEMENTS: dict[str, list[Path]] = {
    "cobra": [ROOT / "assets/source/references/pets/cobra_basic.png"],
    "elephant": [
        ROOT / "assets/exports/pets/elephant_basic_preview.png",
        ROOT / "assets/source/references/pets/elephant_basic.png",
    ],
    "giraffe": [ROOT / "assets/source/references/pets/giraffe_basic.png"],
    "hippo": [ROOT / "assets/source/references/pets/hippo_basic.png"],
    "lion": [ROOT / "assets/source/references/pets/lion_basic.png"],
    "rhino": [ROOT / "assets/source/references/pets/rhino_basic.png"],
    "tiger": [ROOT / "assets/source/references/pets/tiger_basic.png"],
    "water_buffalo": [ROOT / "assets/source/references/pets/water_buffalo_basic.png"],
    "zebra": [
        ROOT / "assets/exports/pets/zebra_basic_preview.png",
        ROOT / "assets/source/references/pets/zebra_basic.png",
    ],
}

PET_SECTIONS: list[tuple[str, list[str]]] = [
    ("Starter", ["bear", "bunny", "doggy", "dragon", "kitty", "colorado"]),
    ("Lava", ["emberling", "emberfox", "emberimp", "emberowl", "emberlion"]),
    ("Ice", ["snowflakeowl", "snowfox", "penguin", "snowleopard", "polarbear"]),
    ("Desert", ["fennec", "camel", "meerkat", "desertiguana", "scorpion"]),
    (
        "Safari",
        [
            "cobra",
            "elephant",
            "giraffe",
            "hippo",
            "lion",
            "rhino",
            "tiger",
            "water_buffalo",
            "zebra",
        ],
    ),
    ("Guardians", ["colossus", "djinn"]),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build basic pet model contact sheet.")
    parser.add_argument(
        "--basic-dir",
        default=str(Path.home() / "Downloads/PetImages/Basic"),
        help="Folder with basic pet model PNGs (default: ~/Downloads/PetImages/Basic)",
    )
    parser.add_argument(
        "--output-dir",
        default=str(OUT_DIR),
        help="Where to copy normalized {pet}_basic.png files",
    )
    parser.add_argument(
        "--gold-dir",
        default=str(Path.home() / "Downloads/PetImages/Gold"),
        help="Folder with golden pet model PNGs (default: ~/Downloads/PetImages/Gold)",
    )
    parser.add_argument(
        "--sheet",
        default=str(SHEET_PATH),
        help="Basic master contact sheet output path",
    )
    parser.add_argument(
        "--gold-sheet",
        default=str(GOLD_SHEET_PATH),
        help="Golden master contact sheet output path",
    )
    parser.add_argument(
        "--basic-only",
        action="store_true",
        help="Build only the basic contact sheet",
    )
    parser.add_argument("--columns", type=int, default=6)
    parser.add_argument("--thumb-size", type=int, default=280)
    parser.add_argument("--label-height", type=int, default=44)
    parser.add_argument("--padding", type=int, default=20)
    parser.add_argument("--section-gap", type=int, default=12)
    return parser.parse_args()


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


def fit_image(image: Image.Image, max_size: int) -> Image.Image:
    scale = min(max_size / image.width, max_size / image.height, 1.0)
    return image.resize(
        (max(1, int(image.width * scale)), max(1, int(image.height * scale))),
        Image.Resampling.LANCZOS,
    )


def first_existing(paths: list[Path]) -> Path | None:
    for path in paths:
        if path.is_file():
            return path
    return None


def resolve_source(
    pet_id: str,
    basic_dir: Path,
    download_by_pet: dict[str, Path],
) -> tuple[Path | None, str]:
    if pet_id in download_by_pet:
        return download_by_pet[pet_id], "download"

    supplement = first_existing(SUPPLEMENTS.get(pet_id, []))
    if supplement is not None:
        kind = "preview" if "preview" in supplement.name else "reference"
        return supplement, kind

    return None, "missing"


def download_by_pet_from(source_dir: Path, suffix: str) -> dict[str, Path]:
    found: dict[str, Path] = {}
    token = f"_{suffix}"
    for path in sorted(source_dir.glob("*.png")):
        stem = path.stem
        if not stem.endswith(token):
            continue
        pet_id = stem[: -len(token)]
        if pet_id:
            found[pet_id] = path
    return found


def import_images(
    source_dir: Path,
    output_dir: Path,
    suffix: str,
    *,
    use_supplements: bool = False,
) -> dict[str, tuple[Path, str]]:
    download_by_pet = download_by_pet_from(source_dir, suffix)
    output_dir.mkdir(parents=True, exist_ok=True)
    imported: dict[str, tuple[Path, str]] = {}

    for _section, pets in PET_SECTIONS:
        for pet_id in pets:
            if use_supplements:
                source, kind = resolve_source(pet_id, source_dir, download_by_pet)
            elif pet_id in download_by_pet:
                source, kind = download_by_pet[pet_id], "download"
            else:
                continue
            if source is None:
                continue
            destination = output_dir / f"{pet_id}_{suffix}.png"
            shutil.copy2(source, destination)
            imported[pet_id] = (destination, kind)

    return imported


def build_sheet(
    imported: dict[str, tuple[Path, str]],
    output_path: Path,
    title: str,
    columns: int,
    thumb_size: int,
    label_height: int,
    padding: int,
    section_gap: int,
) -> list[str]:
    entries: list[tuple[str, str, Path | None, str]] = []
    missing: list[str] = []

    for section_index, (section, pets) in enumerate(PET_SECTIONS):
        if section_index > 0 and entries:
            pad = (-len(entries)) % columns
            for _ in range(pad):
                entries.append(("", "", None, "pad"))

        for pet_id in pets:
            if pet_id in imported:
                path, kind = imported[pet_id]
                entries.append((section, pet_id, path, kind))
            else:
                entries.append((section, pet_id, None, "missing"))
                missing.append(pet_id)

    rows = math.ceil(len(entries) / columns)
    cell_w = thumb_size + padding * 2
    cell_h = thumb_size + label_height + padding * 2
    header_h = 40
    sheet_h = header_h + rows * cell_h + section_gap
    sheet = Image.new("RGBA", (columns * cell_w, sheet_h), (48, 48, 48, 255))
    draw = ImageDraw.Draw(sheet)
    title_font = load_font(22)
    label_font = load_font(16)
    note_font = load_font(12)

    draw.text(
        (columns * cell_w / 2, header_h / 2),
        title,
        fill=(235, 235, 235, 255),
        font=title_font,
        anchor="mm",
    )

    for index, (section, pet_id, path, kind) in enumerate(entries):
        if kind == "pad":
            continue

        col = index % columns
        row = index // columns
        x0 = col * cell_w + padding
        y0 = header_h + row * cell_h + padding

        prev_section = entries[index - 1][0] if index > 0 else ""
        if section and section != prev_section:
            draw.text(
                (4, y0 - 6),
                section,
                fill=(160, 200, 255, 255),
                font=note_font,
                anchor="ls",
            )

        if path is not None:
            fitted = fit_image(Image.open(path).convert("RGBA"), thumb_size)
            paste_x = x0 + (thumb_size - fitted.width) // 2
            paste_y = y0 + (thumb_size - fitted.height) // 2
            sheet.paste(fitted, (paste_x, paste_y), fitted)
        else:
            draw.rectangle(
                [x0, y0, x0 + thumb_size, y0 + thumb_size],
                outline=(90, 90, 90, 255),
                fill=(32, 32, 32, 255),
            )
            draw.text(
                (x0 + thumb_size / 2, y0 + thumb_size / 2),
                "missing",
                fill=(120, 120, 120, 255),
                font=note_font,
                anchor="mm",
            )

        suffix = "" if kind == "download" else f" ({kind})"
        draw.text(
            (x0 + thumb_size / 2, y0 + thumb_size + 10),
            f"{pet_id}{suffix}" if pet_id else "",
            fill=(235, 235, 235, 255),
            font=label_font,
            anchor="ma",
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, format="PNG", optimize=True, compress_level=9)
    return missing


def write_manifest(
    output_dir: Path,
    imported: dict[str, tuple[Path, str]],
    missing: list[str],
    sheet_path: Path,
    *,
    variant: str,
) -> None:
    lines = [
        f"# {variant.capitalize()} pet model images.",
        f"# Master contact sheet: {sheet_path.relative_to(ROOT)}",
        "",
        "pet\tsource\tkind\tfile",
    ]
    for _section, pets in PET_SECTIONS:
        for pet_id in pets:
            if pet_id in imported:
                path, kind = imported[pet_id]
                lines.append(f"{pet_id}\timported\t{kind}\t{path.name}")
            else:
                lines.append(f"{pet_id}\tmissing\t-\t-")
    if missing:
        lines.extend(
            ["", f"# Missing {variant} model images:", *[f"#   {pet}" for pet in missing]]
        )
    (output_dir / "manifest.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_variant_sheet(
    source_dir: Path,
    output_dir: Path,
    sheet_path: Path,
    suffix: str,
    title: str,
    variant: str,
    args: argparse.Namespace,
    *,
    use_supplements: bool = False,
) -> list[str]:
    imported = import_images(
        source_dir,
        output_dir,
        suffix,
        use_supplements=use_supplements,
    )
    missing = build_sheet(
        imported,
        sheet_path,
        title,
        args.columns,
        args.thumb_size,
        args.label_height,
        args.padding,
        args.section_gap,
    )
    write_manifest(output_dir, imported, missing, sheet_path, variant=variant)
    print(f"Imported {len(imported)} {variant} pet images -> {output_dir}")
    print(f"Contact sheet -> {sheet_path}")
    if missing:
        print(f"Missing ({len(missing)}): {', '.join(missing)}")
    return missing


def main() -> int:
    args = parse_args()
    basic_dir = Path(args.basic_dir).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    sheet_path = Path(args.sheet).expanduser().resolve()

    if not basic_dir.is_dir():
        raise SystemExit(f"Basic image folder not found: {basic_dir}")

    build_variant_sheet(
        basic_dir,
        output_dir,
        sheet_path,
        "basic",
        "Basic pet models",
        "basic",
        args,
        use_supplements=True,
    )

    if not args.basic_only:
        gold_dir = Path(args.gold_dir).expanduser().resolve()
        gold_output = Path(GOLD_OUT_DIR).expanduser().resolve()
        gold_sheet = Path(args.gold_sheet).expanduser().resolve()
        if not gold_dir.is_dir():
            raise SystemExit(f"Gold image folder not found: {gold_dir}")
        build_variant_sheet(
            gold_dir,
            gold_output,
            gold_sheet,
            "gold",
            "Golden pet models",
            "gold",
            args,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
