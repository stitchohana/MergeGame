const sharp = require("sharp");

async function main() {
	const file = "assets/ui/xianxia_v3_layers_v2/layers/board_frame_empty.png";
	const temp = "tmp/board_frame_transparent.png";
	const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
	const result = Buffer.from(data);
	for (let y = 0; y < info.height; y++) {
		for (let x = 0; x < info.width; x++) {
			if (x >= 22 && x < 680 && y >= 26 && y < 880) continue;
			const i = (y * info.width + x) * 4;
			const r = data[i], g = data[i + 1], b = data[i + 2];
			const isBackdrop = (Math.abs(r - g) < 18 && Math.abs(g - b) < 24) || (g >= r - 5 && b >= g - 35);
			if (isBackdrop) result[i + 3] = 0;
		}
	}
	await sharp(result, { raw: info }).png().toFile(temp);
}
main().catch((error) => { console.error(error); process.exit(1); });
