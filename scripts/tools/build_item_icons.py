from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
ITEMS_PATH = ROOT / "config" / "json_output" / "items.json"
ATLAS_DIR = ROOT / "assets" / "items" / "atlases"
ICON_DIR = ROOT / "assets" / "items" / "icons"
MANIFEST_PATH = ROOT / "assets" / "items" / "icon_manifest.json"
PREVIEW_PATH = ROOT / "assets" / "items" / "icons_preview.png"
ICON_SIZE = 256


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


def crop_icons(jobs: list[tuple[str, list[int]]], by_id: dict[int, dict]) -> list[dict]:
	ICON_DIR.mkdir(parents=True, exist_ok=True)
	manifest: list[dict] = []
	seen_ids: set[int] = set()

	for atlas_name, item_ids in jobs:
		atlas_path = ATLAS_DIR / f"{atlas_name}.png"
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
				output_path = ICON_DIR / f"{item_id}.png"
				icon.save(output_path, format="PNG", optimize=True)

				item = by_id[item_id]
				manifest.append(
					{
						"id": item_id,
						"name": item.get("name", ""),
						"icon": f"res://assets/items/icons/{item_id}.png",
						"atlas": atlas_name,
						"cell": cell_index,
					}
				)

	if seen_ids != set(by_id):
		missing = sorted(set(by_id) - seen_ids)
		extra = sorted(seen_ids - set(by_id))
		raise ValueError(f"Icon coverage mismatch: missing={missing[:20]} extra={extra[:20]}")
	return sorted(manifest, key=lambda entry: entry["id"])


def build_preview(manifest: list[dict]) -> None:
	samples = manifest[:: max(1, len(manifest) // 80)][:80]
	thumb_size = 96
	label_height = 20
	cols = 10
	rows = (len(samples) + cols - 1) // cols
	preview = Image.new("RGB", (cols * thumb_size, rows * (thumb_size + label_height)), "#EEE8D5")
	draw = ImageDraw.Draw(preview)
	for index, entry in enumerate(samples):
		row, col = divmod(index, cols)
		with Image.open(ICON_DIR / f"{entry['id']}.png") as icon:
			thumb = icon.convert("RGB").resize((thumb_size, thumb_size), Image.Resampling.LANCZOS)
		preview.paste(thumb, (col * thumb_size, row * (thumb_size + label_height)))
		draw.text((col * thumb_size + 4, row * (thumb_size + label_height) + thumb_size + 2), str(entry["id"]), fill="#4F584C")
	preview.save(PREVIEW_PATH, format="PNG", optimize=True)


def main() -> None:
	data, by_id = load_items()
	jobs = build_jobs(data)
	if len(jobs) != 40:
		raise ValueError(f"Expected 40 atlases, got {len(jobs)}")
	manifest = crop_icons(jobs, by_id)
	MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	build_preview(manifest)
	print(f"Generated {len(manifest)} icons from {len(jobs)} atlases")


if __name__ == "__main__":
	main()
