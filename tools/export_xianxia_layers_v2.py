from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = PROJECT_ROOT / "assets" / "ui" / "xianxia_v3_layers_v2"
SOURCE_ROOT = OUTPUT_ROOT / "_source_sheets"
LAYER_ROOT = OUTPUT_ROOT / "layers"
COMPOSITE_ROOT = OUTPUT_ROOT / "composites"


def trim_alpha(image: Image.Image, padding: int = 10) -> Image.Image:
	image = image.convert("RGBA")
	alpha = image.getchannel("A")
	bounds = alpha.getbbox()
	if bounds is None:
		raise ValueError("Sprite cell is fully transparent")
	left, top, right, bottom = bounds
	left = max(0, left - padding)
	top = max(0, top - padding)
	right = min(image.width, right + padding)
	bottom = min(image.height, bottom + padding)
	return image.crop((left, top, right, bottom))


def pad_to_square(image: Image.Image) -> Image.Image:
	size = max(image.width, image.height)
	canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	canvas.alpha_composite(
		image,
		((size - image.width) // 2, (size - image.height) // 2),
	)
	return canvas


def export_sheet(
	sheet_name: str,
	assets: list[tuple[str, tuple[int, int, int, int]]],
	destination: Path,
	kind: str,
	manifest: list[dict[str, object]],
) -> None:
	sheet_path = SOURCE_ROOT / sheet_name
	with Image.open(sheet_path) as sheet:
		sheet = sheet.convert("RGBA")
		for asset_name, bounds in assets:
			sprite = trim_alpha(sheet.crop(bounds))
			if asset_name in {"board_square_cell", "delete_button", "info_button", "add_button"}:
				sprite = pad_to_square(sprite)
			output_path = destination / f"{asset_name}.png"
			sprite.save(output_path)
			alpha = sprite.getchannel("A")
			manifest.append(
				{
					"name": asset_name,
					"kind": kind,
					"file": output_path.relative_to(OUTPUT_ROOT).as_posix(),
					"width": sprite.width,
					"height": sprite.height,
					"has_alpha": alpha.getextrema()[0] == 0,
					"partially_transparent_pixels": sum(
						1 for value in alpha.getdata() if 0 < value < 255
					),
				}
			)


def checkerboard(width: int, height: int, tile: int = 12) -> Image.Image:
	canvas = Image.new("RGBA", (width, height), (235, 239, 235, 255))
	draw = ImageDraw.Draw(canvas)
	dark = (205, 213, 207, 255)
	for y in range(0, height, tile):
		for x in range(0, width, tile):
			if (x // tile + y // tile) % 2:
				draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill=dark)
	return canvas


def make_contact_sheet(manifest: list[dict[str, object]]) -> None:
	items = [item for item in manifest if item["kind"] == "layer"]
	columns = 4
	cell_width = 250
	cell_height = 230
	rows = (len(items) + columns - 1) // columns
	sheet = Image.new("RGB", (columns * cell_width, rows * cell_height), "#e8ede9")
	draw = ImageDraw.Draw(sheet)
	font = ImageFont.load_default(size=14)

	for index, item in enumerate(items):
		column = index % columns
		row = index // columns
		cell_x = column * cell_width
		cell_y = row * cell_height
		with Image.open(OUTPUT_ROOT / str(item["file"])) as sprite:
			sprite = sprite.convert("RGBA")
			preview = sprite.copy()
			preview.thumbnail((210, 175), Image.Resampling.LANCZOS)
			board = checkerboard(preview.width, preview.height)
			board.alpha_composite(preview)
			x = cell_x + (cell_width - board.width) // 2
			y = cell_y + 8
			sheet.paste(board.convert("RGB"), (x, y))
		draw.text((cell_x + 8, cell_y + 190), str(item["name"]), fill="#294238", font=font)
		draw.text(
			(cell_x + 8, cell_y + 208),
			f'{item["width"]}×{item["height"]}',
			fill="#5b7067",
			font=font,
		)

	sheet.save(OUTPUT_ROOT / "transparent_layers_contact_sheet.png")


def main() -> None:
	LAYER_ROOT.mkdir(parents=True, exist_ok=True)
	COMPOSITE_ROOT.mkdir(parents=True, exist_ok=True)
	manifest: list[dict[str, object]] = []

	export_sheet(
		"sheet_pure_components_alpha.png",
		[
			("resource_panel_empty", (70, 90, 630, 350)),
			("energy_lightning_icon", (790, 80, 1040, 390)),
			("qi_spirit_flame_icon", (190, 410, 510, 780)),
			("spirit_stone_icon", (750, 420, 1035, 790)),
			("order_frame_empty", (70, 800, 590, 1195)),
			("cultivation_progress_empty", (635, 920, 1190, 1090)),
		],
		LAYER_ROOT,
		"layer",
		manifest,
	)
	export_sheet(
		"sheet_top_character_alpha.png",
		[
			("cultivator_character", (540, 500, 980, 1035)),
			("cultivation_progress_4_of_7", (55, 1180, 560, 1385)),
			("cultivation_reward_icon", (620, 1130, 925, 1420)),
		],
		LAYER_ROOT,
		"layer",
		manifest,
	)
	export_sheet(
		"sheet_orders_frames_alpha.png",
		[
			("confirm_button", (90, 465, 520, 780)),
			("board_frame_empty", (640, 445, 1160, 910)),
			("board_square_cell", (90, 930, 355, 1195)),
			("item_detail_frame_empty", (430, 930, 1205, 1215)),
		],
		LAYER_ROOT,
		"layer",
		manifest,
	)
	export_sheet(
		"sheet_buttons_alpha.png",
		[
			("cultivation_button", (120, 70, 455, 535)),
			("delete_button", (590, 165, 895, 490)),
			("shop_button", (110, 620, 455, 1115)),
			("info_button", (610, 735, 855, 995)),
			("item_detail_title_tab", (65, 1200, 520, 1405)),
			("add_button", (600, 1190, 865, 1450)),
		],
		LAYER_ROOT,
		"layer",
		manifest,
	)

	export_sheet(
		"sheet_top_character_alpha.png",
		[
			("resource_energy_composite", (55, 120, 505, 380)),
			("resource_qi_composite", (535, 120, 1010, 400)),
			("resource_stone_composite", (55, 620, 505, 900)),
		],
		COMPOSITE_ROOT,
		"composite",
		manifest,
	)
	export_sheet(
		"sheet_orders_frames_alpha.png",
		[
			("order_left_composite", (45, 40, 610, 430)),
			("order_right_composite", (640, 40, 1220, 430)),
		],
		COMPOSITE_ROOT,
		"composite",
		manifest,
	)

	document = {
		"version": 2,
		"description": "Fresh ImageGen assets exported as independently layered transparent PNG files.",
		"background": "background.png",
		"assets": manifest,
	}
	(OUTPUT_ROOT / "layers.json").write_text(
		json.dumps(document, ensure_ascii=False, indent=2),
		encoding="utf-8",
	)
	make_contact_sheet(manifest)

	print(f"Exported {sum(item['kind'] == 'layer' for item in manifest)} transparent layers")
	print(f"Exported {sum(item['kind'] == 'composite' for item in manifest)} optional composites")


if __name__ == "__main__":
	main()
