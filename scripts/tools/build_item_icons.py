from __future__ import annotations

import json
import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from remove_item_icon_backgrounds import make_transparent


ROOT = Path(__file__).resolve().parents[2]
ITEMS_PATH = ROOT / "config" / "json_output" / "items.json"
ATLAS_DIR = ROOT / "assets" / "items" / "atlases"
SIMPLE_ATLAS_DIR = ROOT / "assets" / "items" / "atlases_simple_generated"
ICON_DIR = ROOT / "assets" / "items" / "icons"
SIMPLE_ICON_DIR = ROOT / "assets" / "items" / "icons_simple"
MANIFEST_PATH = ROOT / "assets" / "items" / "icon_manifest.json"
SIMPLE_MANIFEST_PATH = ROOT / "assets" / "items" / "icon_manifest_simple.json"
PREVIEW_PATH = ROOT / "assets" / "items" / "icons_preview.png"
SIMPLE_PREVIEW_PATH = ROOT / "assets" / "items" / "icons_simple_preview.png"
ICON_SIZE = 256
VISIBLE_ALPHA_THRESHOLD = 16
MAX_CENTER_OFFSET = 0.06

SIMPLE_ATLAS_BY_GROUP = {
	"breakthrough_01": "atlas_023",
	"crafting_g31": "atlas_030",
	"crafting_g32": "atlas_020",
	"crafting_g33": "atlas_034",
	"crafting_g34": "atlas_002",
	"crafting_g35": "atlas_031",
	"effect_01": "atlas_006",
	"formation_01": "atlas_011",
	"launcher_g17": "atlas_013",
	"launcher_g18": "atlas_038",
	"launcher_g19": "atlas_015",
	"launcher_g20": "atlas_036",
	"launcher_g21": "atlas_039",
	"launcher_g22": "atlas_009",
	"pill_cult_01": "atlas_022",
	"pill_cult_02": "atlas_001",
	"pill_cult_03": "atlas_027",
	"pill_cult_04": "atlas_026",
	"pill_qi_01": "atlas_019",
	"pill_qi_02": "atlas_028",
	"pill_qi_03": "atlas_033",
	"pill_qi_04": "atlas_029",
	"regular_g01": "atlas_016",
	"regular_g02": "atlas_021",
	"regular_g03": "atlas_014",
	"regular_g06": "atlas_017",
	"regular_g07": "atlas_032",
	"regular_g08": "atlas_008",
	"regular_g09": "atlas_012",
	"regular_g10": "atlas_005",
	"regular_g11": "atlas_003",
	"regular_g12": "atlas_024",
	"regular_g13": "atlas_018",
	"regular_g14": "atlas_004",
	"sword_01": "atlas_037",
	"talisman_01": "atlas_010",
	"wine_01": "atlas_035",
	"wine_02": "atlas_007",
	"wine_03": "atlas_025",
	"wine_04": "atlas_040",
}


def load_items() -> tuple[dict, dict[int, dict]]:
	data = json.loads(ITEMS_PATH.read_text(encoding="utf-8"))
	by_id: dict[int, dict] = {}
	for category in ("regular", "launcher", "crafting", "effect"):
		for item in data.get(category, []):
			by_id[int(item["id"])] = item
	return data, by_id


def ids_for_group(data: dict, category: str, group_id: int) -> list[int]:
	items = [item for item in data[category] if item.get("group_id") == group_id]
	items.sort(key=lambda item: (int(item.get("level", 0)), int(item["id"])))
	return [int(item["id"]) for item in items]


def sequential_ids(start: int, count: int) -> list[int]:
	return list(range(start, start + count))


def build_jobs(data: dict) -> list[tuple[str, list[int]]]:
	jobs: list[tuple[str, list[int]]] = []
	for group_id in (1, 2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 14):
		jobs.append((f"regular_g{group_id:02d}", ids_for_group(data, "regular", group_id)))

	for prefix, start, count in (
		("pill_cult", 27001, 50),
		("pill_qi", 27051, 50),
		("wine", 27101, 50),
	):
		ids = sequential_ids(start, count)
		for batch_index in range(0, count, 16):
			jobs.append((f"{prefix}_{batch_index // 16 + 1:02d}", ids[batch_index:batch_index + 16]))

	jobs.extend(
		[
			("sword_01", sequential_ids(28001, 16)),
			("formation_01", sequential_ids(28017, 16)),
			("talisman_01", sequential_ids(28033, 16)),
			("breakthrough_01", sequential_ids(28049, 12)),
		]
	)

	for group_id in range(17, 23):
		jobs.append((f"launcher_g{group_id}", ids_for_group(data, "launcher", group_id)))
	for group_id in range(31, 36):
		jobs.append((f"crafting_g{group_id}", ids_for_group(data, "crafting", group_id)))

	effect_ids = sorted(int(item["id"]) for item in data["effect"])
	jobs.append(("effect_01", effect_ids))
	return jobs


def center_visible_content(image: Image.Image) -> Image.Image:
	"""Center material whose transparent bounds visibly drift inside the icon canvas."""
	image = image.convert("RGBA")
	alpha = image.getchannel("A")
	bounds = alpha.point(lambda value: 255 if value > VISIBLE_ALPHA_THRESHOLD else 0).getbbox()
	if bounds is None:
		return image

	left, top, right, bottom = bounds
	content_center_x = (left + right - 1) / 2.0
	content_center_y = (top + bottom - 1) / 2.0
	canvas_center_x = (image.width - 1) / 2.0
	canvas_center_y = (image.height - 1) / 2.0
	offset_x = canvas_center_x - content_center_x
	offset_y = canvas_center_y - content_center_y
	if max(abs(offset_x) / image.width, abs(offset_y) / image.height) < MAX_CENTER_OFFSET:
		return image

	centered = Image.new("RGBA", image.size)
	centered.alpha_composite(image, (round(offset_x), round(offset_y)))
	return centered


def crop_icons(
	jobs: list[tuple[str, list[int]]],
	by_id: dict[int, dict],
	variant: str,
) -> list[dict]:
	is_simple = variant == "simple"
	atlas_dir = SIMPLE_ATLAS_DIR if is_simple else ATLAS_DIR
	icon_dir = SIMPLE_ICON_DIR if is_simple else ICON_DIR
	icon_dir.mkdir(parents=True, exist_ok=True)
	manifest: list[dict] = []
	seen_ids: set[int] = set()

	for atlas_name, item_ids in jobs:
		atlas_file = SIMPLE_ATLAS_BY_GROUP[atlas_name] if is_simple else atlas_name
		atlas_path = atlas_dir / f"{atlas_file}.png"
		if not atlas_path.exists():
			raise FileNotFoundError(f"Missing atlas: {atlas_path}")
		with Image.open(atlas_path) as source:
			atlas = source.convert("RGB")
			cell_width = atlas.width // 4
			cell_height = atlas.height // 4
			if cell_width <= 0 or cell_height <= 0:
				raise ValueError(f"Invalid atlas size: {atlas_path} {atlas.size}")

			for cell_index, item_id in enumerate(item_ids):
				if item_id not in by_id:
					raise KeyError(f"Unknown item id {item_id} in {atlas_name}")
				if item_id in seen_ids:
					raise ValueError(f"Duplicate item id {item_id}")
				seen_ids.add(item_id)

				row, col = divmod(cell_index, 4)
				left = col * cell_width
				top = row * cell_height
				right = atlas.width if col == 3 else (col + 1) * cell_width
				bottom = atlas.height if row == 3 else (row + 1) * cell_height
				icon = atlas.crop((left, top, right, bottom))
				icon = icon.resize((ICON_SIZE, ICON_SIZE), Image.Resampling.LANCZOS)
				icon = center_visible_content(make_transparent(icon, threshold=38.0, feather=18.0))
				output_path = icon_dir / f"{item_id}.png"
				icon.save(output_path, format="PNG", optimize=True)

				item = by_id[item_id]
				manifest.append(
					{
						"id": item_id,
						"name": item.get("name", ""),
						"icon": f"res://assets/items/{'icons_simple' if is_simple else 'icons'}/{item_id}.png",
						"atlas": atlas_file,
						"cell": cell_index,
					}
				)

	if seen_ids != set(by_id):
		missing = sorted(set(by_id) - seen_ids)
		extra = sorted(seen_ids - set(by_id))
		raise ValueError(f"Icon coverage mismatch: missing={missing[:20]} extra={extra[:20]}")
	return sorted(manifest, key=lambda entry: entry["id"])


def build_preview(manifest: list[dict], variant: str) -> None:
	icon_dir = SIMPLE_ICON_DIR if variant == "simple" else ICON_DIR
	preview_path = SIMPLE_PREVIEW_PATH if variant == "simple" else PREVIEW_PATH
	samples = manifest[:: max(1, len(manifest) // 80)][:80]
	thumb_size = 96
	label_height = 20
	cols = 10
	rows = (len(samples) + cols - 1) // cols
	preview = Image.new("RGB", (cols * thumb_size, rows * (thumb_size + label_height)), "#EEE8D5")
	draw = ImageDraw.Draw(preview)
	for index, entry in enumerate(samples):
		row, col = divmod(index, cols)
		with Image.open(icon_dir / f"{entry['id']}.png") as icon:
			thumb = icon.convert("RGBA").resize((thumb_size, thumb_size), Image.Resampling.LANCZOS)
		preview.paste(thumb, (col * thumb_size, row * (thumb_size + label_height)), thumb)
		draw.text((col * thumb_size + 4, row * (thumb_size + label_height) + thumb_size + 2), str(entry["id"]), fill="#4F584C")
	preview.save(preview_path, format="PNG", optimize=True)


def main() -> None:
	parser = argparse.ArgumentParser(description="Crop item icon atlases into individual PNGs.")
	parser.add_argument("--variant", choices=("original", "simple"), default="original")
	args = parser.parse_args()
	variant: str = args.variant
	data, by_id = load_items()
	jobs = build_jobs(data)
	if len(jobs) != 40:
		raise ValueError(f"Expected 40 atlases, got {len(jobs)}")
	if variant == "simple" and set(SIMPLE_ATLAS_BY_GROUP) != {name for name, _item_ids in jobs}:
		raise ValueError("Simple atlas mapping does not cover every generated atlas job")
	manifest = crop_icons(jobs, by_id, variant)
	manifest_path = SIMPLE_MANIFEST_PATH if variant == "simple" else MANIFEST_PATH
	manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	build_preview(manifest, variant)
	print(f"Generated {len(manifest)} icons from {len(jobs)} atlases")


if __name__ == "__main__":
	main()
