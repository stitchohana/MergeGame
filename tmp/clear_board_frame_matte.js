const sharp = require("sharp");

async function main() {
	const file = "assets/ui/xianxia_v3_layers_v2/layers/board_frame_empty_hd.png";
	const temp = "tmp/board_frame_empty_hd_matte.png";
	const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
	const result = Buffer.from(data);
	for (let y = 0; y < info.height; y++) {
		for (let x = 0; x < info.width; x++) {
			const nearExterior = x < 38 || x >= info.width - 38 || y < 38 || y >= info.height - 38;
			if (!nearExterior) continue;
			const i = (y * info.width + x) * 4;
			const r = data[i], g = data[i + 1], b = data[i + 2];
			const isLandscapeMatte = r < 225 && g >= r - 4 && b >= g - 32;
			if (isLandscapeMatte) result[i + 3] = 0;
		}
	}
	await sharp(result, { raw: info }).png().toFile(temp);
}
main().catch((error) => { console.error(error); process.exit(1); });
