const sharp = require("sharp");

async function main() {
	const source = "assets/ui/xianxia_v3_layers_v2/layers/board_reference_crop.png";
	const output = "assets/ui/xianxia_v3_layers_v2/layers/board_frame_empty_hd.png";
	const { data, info } = await sharp(source).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
	const result = Buffer.from(data);

	for (let y = 26; y < 880; y++) {
		for (let x = 22; x < 680; x++) {
			const i = (y * info.width + x) * 4;
			const shade = Math.round(246 - (y - 26) * 0.004);
			result[i] = shade + 2;
			result[i + 1] = shade - 4;
			result[i + 2] = shade - 17;
			result[i + 3] = 255;
		}
	}

	for (let y = 0; y < info.height; y++) {
		for (let x = 0; x < info.width; x++) {
			if (x >= 22 && x < 680 && y >= 26 && y < 880) continue;
			const i = (y * info.width + x) * 4;
			const r = data[i], g = data[i + 1], b = data[i + 2];
			const isBackdrop = (Math.abs(r - g) < 18 && Math.abs(g - b) < 24) || (g >= r - 5 && b >= g - 35);
			if (isBackdrop) result[i + 3] = 0;
		}
	}

	await sharp(result, { raw: info })
		.resize(info.width * 2, info.height * 2, { kernel: sharp.kernel.lanczos3 })
		.png()
		.toFile(output);
}
main().catch((error) => { console.error(error); process.exit(1); });
