#!/usr/bin/env python3

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Remove a near-white background from a pet reference image.")
    parser.add_argument("input", help="Input PNG/JPG reference image")
    parser.add_argument("output", help="Output transparent PNG")
    parser.add_argument("--threshold", type=int, default=242, help="RGB threshold for white background pixels")
    parser.add_argument("--softness", type=int, default=20, help="Feather range below the threshold")
    parser.add_argument(
        "--mode",
        choices=["edge-white", "ring-white", "all-white"],
        default="edge-white",
        help=(
            "edge-white: background connected to image edges; "
            "ring-white: edge background plus center hole (for ring/frame UI art); "
            "all-white: every near-white pixel."
        ),
    )
    return parser.parse_args()


def background_alpha(red: int, green: int, blue: int, threshold: int, softness: int) -> int:
    whiteness = min(red, green, blue)
    if whiteness >= threshold:
        return 0
    if softness <= 0 or whiteness <= threshold - softness:
        return 255

    return int(255 * (threshold - whiteness) / softness)


def is_background_candidate(red: int, green: int, blue: int, threshold: int, softness: int) -> bool:
    return min(red, green, blue) >= threshold - softness


def flood_connected_background(
    image: Image.Image,
    threshold: int,
    softness: int,
    seeds: list[tuple[int, int]],
) -> set[tuple[int, int]]:
    width, height = image.size
    pixels = image.load()
    queue: deque[tuple[int, int]] = deque()
    seen: set[tuple[int, int]] = set()

    def enqueue(x: int, y: int) -> None:
        if (x, y) in seen:
            return
        red, green, blue, _alpha = pixels[x, y]
        if not is_background_candidate(red, green, blue, threshold, softness):
            return
        seen.add((x, y))
        queue.append((x, y))

    for seed in seeds:
        if 0 <= seed[0] < width and 0 <= seed[1] < height:
            enqueue(seed[0], seed[1])

    while queue:
        x, y = queue.popleft()
        for next_x, next_y in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= next_x < width and 0 <= next_y < height:
                enqueue(next_x, next_y)

    return seen


def edge_connected_background(image: Image.Image, threshold: int, softness: int) -> set[tuple[int, int]]:
    width, height = image.size
    seeds: list[tuple[int, int]] = []
    for x in range(width):
        seeds.extend([(x, 0), (x, height - 1)])
    for y in range(height):
        seeds.extend([(0, y), (width - 1, y)])
    return flood_connected_background(image, threshold, softness, seeds)


def ring_connected_background(image: Image.Image, threshold: int, softness: int) -> set[tuple[int, int]]:
    width, height = image.size
    center_x = width // 2
    center_y = height // 2
    center_seeds = [
        (center_x, center_y),
        (center_x - 1, center_y),
        (center_x + 1, center_y),
        (center_x, center_y - 1),
        (center_x, center_y + 1),
    ]
    outer = edge_connected_background(image, threshold, softness)
    inner = flood_connected_background(image, threshold, softness, center_seeds)
    return outer | inner


def main() -> None:
    args = parse_args()
    source = Path(args.input)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    image = Image.open(source).convert("RGBA")
    pixels = []
    background_mask = None
    if args.mode == "edge-white":
        background_mask = edge_connected_background(image, args.threshold, args.softness)
    elif args.mode == "ring-white":
        background_mask = ring_connected_background(image, args.threshold, args.softness)

    for index, (red, green, blue, alpha) in enumerate(image.getdata()):
        if background_mask is not None:
            x = index % image.width
            y = index // image.width
            if (x, y) not in background_mask:
                pixels.append((red, green, blue, alpha))
                continue

        next_alpha = min(alpha, background_alpha(red, green, blue, args.threshold, args.softness))
        pixels.append((red, green, blue, next_alpha))

    image.putdata(pixels)
    image.save(output)
    print(output)


if __name__ == "__main__":
    main()
