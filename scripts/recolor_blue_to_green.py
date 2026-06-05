#!/usr/bin/env python3
"""Recolor blue UI art to green or red while preserving alpha and shading.

Usage:
  python3 scripts/recolor_blue_to_green.py input.png output.png --color green
  python3 scripts/recolor_blue_to_green.py assets/ui/ring_frames_transparent assets/ui/ring_frames_red --color red
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

COLOR_DEFAULTS = {
    "green": "_green",
    "red": "_red",
    "amber": "_amber",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Recolor blue-toned transparent PNG art.")
    parser.add_argument("input", help="Input PNG or directory of PNGs")
    parser.add_argument(
        "output",
        nargs="?",
        help="Output PNG path, or output directory when input is a directory",
    )
    parser.add_argument(
        "--color",
        choices=["green", "red", "amber"],
        default="green",
        help="Target color (default: green)",
    )
    parser.add_argument(
        "--suffix",
        help="Filename suffix when processing a directory (default: _green or _red)",
    )
    parser.add_argument(
        "--min-blue-excess",
        type=float,
        default=8.0,
        help="Minimum (blue - min(red,green)) before a pixel is recolored",
    )
    return parser.parse_args()


def recolor_blue_ui(
    image: Image.Image,
    color: str,
    min_blue_excess: float = 8.0,
) -> Image.Image:
    rgba = np.array(image.convert("RGBA"), dtype=np.float32)
    alpha = rgba[:, :, 3]
    mask = alpha > 0

    red = rgba[:, :, 0]
    green = rgba[:, :, 1]
    blue = rgba[:, :, 2]

    blue_excess = np.clip(blue - np.minimum(red, green), 0, 255)
    recolor = mask & (blue_excess > min_blue_excess)

    if color == "green":
        green[recolor] = np.clip(green[recolor] + blue_excess[recolor] * 0.92, 0, 255)
        blue[recolor] = np.clip(blue[recolor] - blue_excess[recolor] * 0.78, 0, 255)
        red[recolor] = np.clip(red[recolor] * 0.85 + blue_excess[recolor] * 0.05, 0, 255)
    elif color == "red":
        red[recolor] = np.clip(red[recolor] + blue_excess[recolor] * 0.92, 0, 255)
        blue[recolor] = np.clip(blue[recolor] - blue_excess[recolor] * 0.78, 0, 255)
        green[recolor] = np.clip(green[recolor] * 0.85 + blue_excess[recolor] * 0.05, 0, 255)
    elif color == "amber":
        red[recolor] = np.clip(red[recolor] + blue_excess[recolor] * 0.88, 0, 255)
        green[recolor] = np.clip(green[recolor] + blue_excess[recolor] * 0.58, 0, 255)
        blue[recolor] = np.clip(blue[recolor] - blue_excess[recolor] * 0.82, 0, 255)

    rgba[:, :, 0] = red
    rgba[:, :, 1] = green
    rgba[:, :, 2] = blue
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8))


def output_name_for(input_path: Path, output: Path | None, suffix: str) -> Path:
    if output is None:
        return input_path.with_name(f"{input_path.stem}{suffix}{input_path.suffix}")

    if output.suffix.lower() == ".png":
        return output

    output.mkdir(parents=True, exist_ok=True)
    stem = input_path.stem
    if stem.endswith("_transparent"):
        stem = f"{stem[:-12]}_transparent{suffix}"
    else:
        stem = f"{stem}{suffix}"
    return output / f"{stem}.png"


def collect_inputs(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if path.is_dir():
        return sorted(p for p in path.glob("*.png") if p.is_file())
    raise FileNotFoundError(f"Input not found: {path}")


def main() -> int:
    args = parse_args()
    input_path = Path(args.input).expanduser().resolve()
    output_arg = Path(args.output).expanduser().resolve() if args.output else None
    suffix = args.suffix or COLOR_DEFAULTS[args.color]

    try:
        inputs = collect_inputs(input_path)
    except FileNotFoundError as error:
        print(error, file=sys.stderr)
        return 1

    if not inputs:
        print(f"No PNG files found in: {input_path}", file=sys.stderr)
        return 1

    if len(inputs) > 1 and output_arg is not None and output_arg.suffix.lower() == ".png":
        print("Output must be a directory when processing multiple inputs.", file=sys.stderr)
        return 1

    for source in inputs:
        destination = output_name_for(source, output_arg, suffix)
        destination.parent.mkdir(parents=True, exist_ok=True)
        result = recolor_blue_ui(Image.open(source), args.color, args.min_blue_excess)
        result.save(destination)
        print(destination)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
