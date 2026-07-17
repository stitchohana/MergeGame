import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const packageEntry = require.resolve("@oai/artifact-tool", { paths: [process.env.CODEX_NODE_MODULES] });
const { FileBlob, SpreadsheetFile } = await import(pathToFileURL(packageEntry));
const root = path.dirname(fileURLToPath(import.meta.url));
const xlsxDir = path.join(root, "xlsx");
const jsonDir = path.join(root, "json_output");
const previewDir = process.env.BALANCE_PREVIEW_DIR ?? path.join(root, "balance_previews");
const balancedDir = path.join(root, "xlsx_balanced");
const readJson = async name => JSON.parse(await fs.readFile(path.join(jsonDir, name), "utf8"));

async function open(name) {
  return SpreadsheetFile.importXlsx(await FileBlob.load(path.join(xlsxDir, `${name}.xlsx`)));
}

async function render(name, sheetName, suffix) {
  const sourceDir = suffix === "after" ? balancedDir : xlsxDir;
  const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(sourceDir, `${name}.xlsx`)));
  const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.mkdir(previewDir, { recursive: true });
  await fs.writeFile(path.join(previewDir, `${name}_${suffix}.png`), new Uint8Array(await preview.arrayBuffer()));
}

function updateById(sheet, idHeader, valueHeader, values) {
  const used = sheet.getUsedRange();
  const rows = used.values;
  const headers = rows[0].map(value => String(value ?? "").trim());
  const idCol = headers.indexOf(idHeader);
  let valueCol = headers.indexOf(valueHeader);
  if (valueCol < 0) {
    valueCol = headers.length;
    sheet.getCell(0, valueCol).values = [[valueHeader]];
  }
  for (let row = 1; row < rows.length; row++) {
    const rawId = rows[row][idCol];
    const key = typeof [...values.keys()][0] === "number" ? Number(rawId) : String(rawId ?? "").trim();
    const value = values.get(key);
    if (value != null) sheet.getCell(row, valueCol).values = [[value]];
  }
}

async function save(workbook, name) {
  await fs.mkdir(balancedDir, { recursive: true });
  const output = await SpreadsheetFile.exportXlsx(workbook);
  await output.save(path.join(balancedDir, `${name}.xlsx`));
}

if (process.argv.includes("--render-before")) {
  await render("items", "items_regular", "before");
  await render("meridians", "meridians", "before");
  await render("home_meridians", "home_meridians", "before");
  await render("cultivation", "cultivation", "before");
  await render("rewards", "rewards", "before");
  process.exit(0);
}

const items = await readJson("items.json");
const itemValues = new Map([...items.regular, ...items.launcher, ...items.crafting, ...(items.effect ?? [])].map(item => [item.id, item.value]));
const itemBook = await open("items");
for (const sheetName of ["items_regular", "items_recipe_product", "items_effect"]) {
  updateById(itemBook.worksheets.getItem(sheetName), "id", "value", itemValues);
}
await save(itemBook, "items");

const meridians = await readJson("meridians.json");
const meridianBook = await open("meridians");
updateById(meridianBook.worksheets.getItem("meridians"), "stage", "acupoint_rewards", new Map(meridians.thresholds.map(stage => [stage.stage, stage.acupoint_rewards])));
await save(meridianBook, "meridians");

const rewards = await readJson("rewards.json");
const rewardBook = await open("rewards");
const rewardSheet = rewardBook.worksheets.getItem("rewards");
const rewardRows = rewardSheet.getUsedRange().values;
const rewardHeaders = rewardRows[0].map(value => String(value ?? "").trim());
const rewardIdCol = rewardHeaders.indexOf("reward_id");
const tokenCol = rewardHeaders.indexOf("tokens(token:amount)");
let orderRewardRow = rewardRows.findIndex((row, index) => index > 0 && Number(row[rewardIdCol]) === 219);
if (orderRewardRow < 0) orderRewardRow = rewardRows.length;
rewardSheet.getCell(orderRewardRow, rewardIdCol).values = [[219]];
rewardSheet.getCell(orderRewardRow, tokenCol).values = [["2:10"]];
await save(rewardBook, "rewards");

const home = await readJson("home_meridians.json");
const homeBook = await open("home_meridians");
const homeSheet = homeBook.worksheets.getItem("home_meridians");
updateById(homeSheet, "name", "qi_cost", new Map(home.stages.map(stage => [stage.name, stage.qi_cost])));
updateById(homeSheet, "name", "acupoint_exp", new Map(home.stages.map(stage => [stage.name, stage.acupoint_rewards.tokens[0].amount])));
updateById(homeSheet, "name", "circulation_exp", new Map(home.stages.map(stage => [stage.name, stage.circulation_rewards.tokens[0].amount])));
await save(homeBook, "home_meridians");

const cultivation = await readJson("cultivation.json");
const cultivationBook = await open("cultivation");
const cultivationSheet = cultivationBook.worksheets.getItem("cultivation");
updateById(cultivationSheet, "name", "exp", new Map(cultivation.stages.map(stage => [stage.name, stage.exp])));
updateById(cultivationSheet, "name", "max_qi", new Map(cultivation.stages.map(stage => [stage.name, stage.max_qi])));
await save(cultivationBook, "cultivation");

await render("items", "items_regular", "after");
await render("meridians", "meridians", "after");
await render("home_meridians", "home_meridians", "after");
await render("cultivation", "cultivation", "after");
await render("rewards", "rewards", "after");
