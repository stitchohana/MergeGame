const sharp = require("sharp");

async function main() {
	const source = "assets/ui/xianxia_v3_layers_v2/layers/board_reference_crop.png";
	const output = "assets/ui/xianxia_v3_layers_v2/layers/board_frame_empty_hd.png";
	const { data, info } = await sharp(source).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
	const board = Buffer.from(data);
	for (let y = 26; y < 880; y++) {
		for (let x = 22; x < 680; x++) {
			const i = (y * info.width + x) * 4;
			const shade = Math.round(246 - (y - 26) * 0.004);
			board[i] = shade + 2;
			board[i + 1] = shade - 4;
			board[i + 2] = shade - 17;
			board[i + 3] = 255;
		}
	}
	// Preserve every border detail. Transparency is supplied by the surrounding canvas.
	for (let i = 3; i < board.length; i += 4) board[i] = 255;
	await sharp({ create: { width: info.width + 16, height: info.height + 16, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
		.composite([{ input: board, raw: info, left: 8, top: 8 }])
		.png()
		.toFile(output);
}
main().catch((error) => { console.error(error); process.exit(1); });
