#!/usr/bin/env python3
"""Remove the warm ivory background from generated item icons.

Only pixels connected to an image edge are considered background. This keeps
light-colored details inside the illustrated item intact while making the
surrounding background transparent.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
from statistics import median

from PIL import Image


def color_distance(pixel: tuple[int, int, int, int], base: tuple[int, int, int]) -> float:
	return sum((pixel[index] - base[index]) ** 2 for index in range(3)) ** 0.5


def border_color(image: Image.Image) -> tuple[int, int, int]:
	width, height = image.size
	pixels = image.load()
	border = []
	for x in range(width):
		border.append(pixels[x, 0])
		border.append(pixels[x, height - 1])
	for y in range(1, height - 1):
		border.append(pixels[0, y])
		border.append(pixels[width - 1, y])
	return tuple(int(median(pixel[channel] for pixel in border)) for channel in range(3))


def make_transparent(image: Image.Image, threshold: float, feather: float) -> Image.Image:
	image = image.convert("RGBA")
	width, height = image.size
	pixels = image.load()
	base = border_color(image)
	background: set[tuple[int, int]] = set()
	queue: deque[tuple[int, int]] = deque()

	for x in range(width):
		queue.extend(((x, 0), (x, height - 1)))
	for y in range(1, height - 1):
		queue.extend(((0, y), (width - 1, y)))

	while queue:
		x, y = queue.popleft()
		if (x, y) in background or color_distance(pixels[x, y], base) > threshold:
			continue
		background.add((x, y))
		for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			nx, ny = x + dx, y + dy
			if 0 <= nx < width and 0 <= ny < height:
				queue.append((nx, ny))

	transparent_at = max(threshold - feather, 0.0)
	for x, y in background:
		red, green, blue, _alpha = pixels[x, y]
		distance = color_distance(pixels[x, y], base)
		alpha = int(max(0.0, min(1.0, (distance - transparent_at) / feather)) * 255)
		pixels[x, y] = (red, green, blue, alpha)
	return image


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(description="Remove connected ivory backgrounds from item icons.")
	parser.add_argument("--icons-dir", type=Path, default=Path("assets/items/icons"))
	parser.add_argument("--output-dir", type=Path, default=None)
	parser.add_argument("--ids", default="", help="Comma-separated item IDs; empty processes every icon.")
	parser.add_argument("--threshold", type=float, default=38.0)
	parser.add_argument("--feather", type=float, default=18.0)
	return parser.parse_args()


def main() -> None:
	args = parse_args()
	requested_ids = {item_id.strip() for item_id in args.ids.split(",") if item_id.strip()}
	inputs = sorted(args.icons_dir.glob("*.png"))
	if requested_ids:
		inputs = [path for path in inputs if path.stem in requested_ids]
	if not inputs:
		raise SystemExit("No icon files matched the requested input.")

	output_dir = args.output_dir or args.icons_dir
	output_dir.mkdir(parents=True, exist_ok=True)
	for source in inputs:
		with Image.open(source) as image:
			result = make_transparent(image, args.threshold, args.feather)
			result.save(output_dir / source.name, "PNG")

	print(f"Processed {len(inputs)} icons into {output_dir}")


if __name__ == "__main__":
	main()
