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
        choices=["edge-white", "all-white"],
        default="edge-white",
        help="edge-white removes only background connected to image edges; all-white removes every near-white pixel.",
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


def edge_connected_background(image: Image.Image, threshold: int, softness: int) -> set[tuple[int, int]]:
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

    for x in range(width):
        enqueue(x, 0)
        enqueue(x, height - 1)
    for y in range(height):
        enqueue(0, y)
        enqueue(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for next_x, next_y in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= next_x < width and 0 <= next_y < height:
                enqueue(next_x, next_y)

    return seen


def main() -> None:
    args = parse_args()
    source = Path(args.input)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    image = Image.open(source).convert("RGBA")
    pixels = []
    edge_background = (
        edge_connected_background(image, args.threshold, args.softness)
        if args.mode == "edge-white"
        else None
    )

    for index, (red, green, blue, alpha) in enumerate(image.getdata()):
        if edge_background is not None:
            x = index % image.width
            y = index // image.width
            if (x, y) not in edge_background:
                pixels.append((red, green, blue, alpha))
                continue

        next_alpha = min(alpha, background_alpha(red, green, blue, args.threshold, args.softness))
        pixels.append((red, green, blue, next_alpha))

    image.putdata(pixels)
    image.save(output)
    print(output)


if __name__ == "__main__":
    main()
