import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const packageEntry = require.resolve("@oai/artifact-tool", { paths: [process.env.CODEX_NODE_MODULES] });
const { FileBlob, SpreadsheetFile } = await import(pathToFileURL(packageEntry));

const configDir = path.dirname(fileURLToPath(import.meta.url));
const jsonDir = path.join(configDir, "json_output");
const xlsxDir = path.join(configDir, "xlsx");
const previewDir = process.env.ORDER_QI_PREVIEW_DIR ?? path.join(configDir, "order_qi_previews");
const ORDER_REWARD_ID = 219;
const ORDER_QI_PER_VALUE = 1;
const BEGINNER_QI_COST_PER_ACUPOINT = 5;
// Offline balance targets only. These values are deliberately not exported to
// JSON/XLSX or read by the game at runtime.
const TARGET_ORDERS_PER_CIRCULATION = [
  null, 4, 5, 5, 6, 6, 7, 7, 8, 8,
  9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
];

const readJson = async name => JSON.parse(await fs.readFile(path.join(jsonDir, name), "utf8"));

async function openWorkbook(name) {
  return SpreadsheetFile.importXlsx(await FileBlob.load(path.join(xlsxDir, `${name}.xlsx`)));
}

async function renderWorkbook(name, sheetName, suffix) {
  const workbook = await openWorkbook(name);
  const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.mkdir(previewDir, { recursive: true });
  await fs.writeFile(
    path.join(previewDir, `${name}_${suffix}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

function rowsByHeader(sheet) {
  const rows = sheet.getUsedRange().values;
  const headers = rows[0].map(value => String(value ?? "").trim());
  const columns = new Map(headers.map((header, index) => [header, index]));
  return { rows, columns };
}

function updateColumnByKey(sheet, keyHeader, valueHeader, valuesByKey) {
  const { rows, columns } = rowsByHeader(sheet);
  const keyColumn = columns.get(keyHeader);
  const valueColumn = columns.get(valueHeader);
  if (keyColumn === undefined || valueColumn === undefined) {
    throw new Error(`worksheet is missing ${keyHeader}/${valueHeader}`);
  }
  let updated = 0;
  for (let row = 1; row < rows.length; row++) {
    const key = String(rows[row][keyColumn] ?? "").trim();
    if (!valuesByKey.has(key)) continue;
    sheet.getCell(row, valueColumn).values = [[valuesByKey.get(key)]];
    updated += 1;
  }
  return updated;
}

function updateReward219(sheet) {
  const { rows, columns } = rowsByHeader(sheet);
  const rewardColumn = columns.get("reward_id");
  const tokenColumn = columns.get("tokens(token:amount)");
  const itemColumn = columns.get("items(id:count)");
  if (rewardColumn === undefined || tokenColumn === undefined || itemColumn === undefined) {
    throw new Error("rewards worksheet is missing reward_id/tokens(token:amount)");
  }
  let orderRewardRow = -1;
  for (let row = 1; row < rows.length; row += 1) {
    const rewardId = Number(rows[row][rewardColumn]);
    if ([1, 2, ORDER_REWARD_ID].includes(rewardId)) {
      // These rewards are token-only. Clear the legacy numeric placeholder
      // that some XLSX exports left in the item column.
      sheet.getCell(row, itemColumn).values = [[""]];
    }
    if (rewardId >= 301 && rewardId <= 313) {
      // Breakthrough rewards are item-only; clear the matching token placeholder.
      sheet.getCell(row, tokenColumn).values = [[""]];
    }
    if (rewardId === ORDER_REWARD_ID) {
      orderRewardRow = row;
      sheet.getCell(row, tokenColumn).values = [[`2:${ORDER_QI_PER_VALUE}`]];
    }
  }
  if (orderRewardRow < 0) throw new Error(`reward ${ORDER_REWARD_ID} is missing from rewards worksheet`);
  return orderRewardRow;
}

function getOrderPool(items, meridians, cultivationLevel) {
  const regular = items.regular.filter(item => Number(item.type ?? 0) === 0);
  const recipeProducts = items.regular.filter(item => Number(item.type ?? 0) === 4);
  const range = (meridians.order_level_ranges ?? []).find(entry =>
    cultivationLevel >= Number(entry.cultivation_min)
    && cultivationLevel <= Number(entry.cultivation_max));
  if (!range) return [...regular, ...recipeProducts];
  const [regularMin, regularMax] = range.items_regular;
  const [recipeMin, recipeMax] = range.items_recipe_product;
  return [
    ...regular.filter(item => Number(item.level) >= regularMin && Number(item.level) <= regularMax),
    ...recipeProducts.filter(item => Number(item.level) >= recipeMin && Number(item.level) <= recipeMax),
  ];
}

function calculateTargets(items, meridians, cultivation) {
  const targets = new Map();
  for (let index = 0; index < cultivation.stages.length; index += 1) {
    const cultivationStage = cultivation.stages[index];
    const cultivationLevel = Number(cultivationStage.level ?? cultivationStage.stage ?? index + 1);
    const threshold = (meridians.thresholds ?? []).find(entry => Number(entry.stage) === cultivationLevel);
    if (!threshold) continue;
    const targetOrderCount = TARGET_ORDERS_PER_CIRCULATION[cultivationLevel - 1];
    if (!Number.isFinite(targetOrderCount) || targetOrderCount <= 0) continue;
    const values = getOrderPool(items, meridians, cultivationLevel)
      .map(item => Number(item.value))
      .filter(value => Number.isFinite(value) && value > 0);
    if (values.length === 0) continue;
    const averageItemValue = values.reduce((sum, value) => sum + value, 0) / values.length;
    const typeMin = Math.max(1, Number(threshold.count_min ?? 1));
    const typeMax = Math.min(values.length, Math.max(typeMin, Number(threshold.count_max ?? typeMin)));
    const averageOrderValue = averageItemValue * ((typeMin + typeMax) / 2);
    targets.set(cultivationLevel, {
      averageOrderValue,
      targetOrderCount,
      cycleQi: averageOrderValue * targetOrderCount,
    });
  }
  return targets;
}

function updateHomeCosts(home, targets) {
  const qiCostsByName = new Map();
  const summary = new Map();
  for (const stage of home.stages) {
    const cultivationLevel = Number(stage.cultivation_level);
    const target = targets.get(cultivationLevel);
    const targetCycleQi = target?.cycleQi;
    if (!Number.isFinite(targetCycleQi) || targetCycleQi <= 0) continue;
    const acupoints = Math.max(1, Number(stage.acupoints));
    const oldQiCost = Math.max(1, Number(stage.qi_cost));
    const oldCycleQi = acupoints * oldQiCost;
    const scale = targetCycleQi / oldCycleQi;
    const newQiCost = cultivationLevel === 1
      ? BEGINNER_QI_COST_PER_ACUPOINT
      : Math.max(1, Math.round(oldQiCost * scale));
    qiCostsByName.set(String(stage.name), newQiCost);
    stage.qi_cost = newQiCost;
    const entry = summary.get(cultivationLevel) ?? {
      averageOrderValue: target.averageOrderValue,
      targetOrderCount: target.targetOrderCount,
      minCycleQi: Infinity,
      maxCycleQi: 0,
      minQiCost: Infinity,
      maxQiCost: 0,
      count: 0,
    };
    const cycleQi = acupoints * newQiCost;
    entry.minCycleQi = Math.min(entry.minCycleQi, cycleQi);
    entry.maxCycleQi = Math.max(entry.maxCycleQi, cycleQi);
    entry.minQiCost = Math.min(entry.minQiCost, newQiCost);
    entry.maxQiCost = Math.max(entry.maxQiCost, newQiCost);
    entry.count += 1;
    summary.set(cultivationLevel, entry);
  }
  return { qiCostsByName, summary };
}

function updateCultivationCapacity(cultivation, targets) {
  const maxQiByName = new Map();
  for (let index = 0; index < cultivation.stages.length; index += 1) {
    const stage = cultivation.stages[index];
    const cultivationLevel = Number(stage.level ?? stage.stage ?? index + 1);
    const targetCycleQi = targets.get(cultivationLevel);
    if (!Number.isFinite(targetCycleQi) || targetCycleQi <= 0) continue;
    const oldMaxQi = Math.max(0, Number(stage.max_qi ?? 0));
    const newMaxQi = Math.max(oldMaxQi, Math.ceil(targetCycleQi / 100) * 100);
    stage.max_qi = newMaxQi;
    maxQiByName.set(String(stage.name), newMaxQi);
  }
  return maxQiByName;
}

async function saveWorkbook(workbook, name) {
  const tempPath = path.join(xlsxDir, `${name}.xlsx.tmp`);
  const output = await SpreadsheetFile.exportXlsx(workbook);
  await output.save(tempPath);
  await fs.rename(tempPath, path.join(xlsxDir, `${name}.xlsx`));
}

const items = await readJson("items.json");
const meridians = await readJson("meridians.json");
const home = await readJson("home_meridians.json");
const cultivation = await readJson("cultivation.json");
const targets = calculateTargets(items, meridians, cultivation);

if (process.argv.includes("--render-before")) {
  await renderWorkbook("home_meridians", "home_meridians", "before");
  await renderWorkbook("cultivation", "cultivation", "before");
  await renderWorkbook("rewards", "rewards", "before");
  process.exit(0);
}

const { qiCostsByName, summary } = updateHomeCosts(home, targets);
await fs.writeFile(path.join(jsonDir, "home_meridians.json"), `${JSON.stringify(home, null, 2)}\n`, "utf8");

const homeWorkbook = await openWorkbook("home_meridians");
const homeRowsUpdated = updateColumnByKey(
  homeWorkbook.worksheets.getItem("home_meridians"),
  "name",
  "qi_cost",
  qiCostsByName,
);
updateColumnByKey(
  homeWorkbook.worksheets.getItem("home_meridians"),
  "name",
  "circulation_reward",
  new Map(home.stages.map(stage => [
    String(stage.name),
    JSON.stringify(stage.circulation_reward ?? {}),
  ])),
);
homeWorkbook.recalculate();
await saveWorkbook(homeWorkbook, "home_meridians");

await renderWorkbook("home_meridians", "home_meridians", "after");

console.log(JSON.stringify({
  orderRewardId: ORDER_REWARD_ID,
  orderQiPerValue: ORDER_QI_PER_VALUE,
  targetOrdersPerCirculation: TARGET_ORDERS_PER_CIRCULATION,
  beginnerQiCostPerAcupoint: BEGINNER_QI_COST_PER_ACUPOINT,
  homeRowsUpdated,
  stages: Object.fromEntries([...summary.entries()].map(([level, entry]) => [level, entry])),
}, null, 2));
