import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const PREMIUM_RATE = 0.20;
const DEFAULT_MATERIAL_VALUE = 1;
const require = createRequire(import.meta.url);
const packageEntry = require.resolve("@oai/artifact-tool", { paths: [process.env.CODEX_NODE_MODULES] });
const { FileBlob, SpreadsheetFile } = await import(pathToFileURL(packageEntry));
const configDir = path.dirname(fileURLToPath(import.meta.url));
const jsonDir = path.join(configDir, "json_output");
const workbookPath = path.join(configDir, "xlsx", "items.xlsx");
const previewDir = process.env.ITEM_VALUE_PREVIEW_DIR ?? path.join(configDir, "item_value_previews");

const readJson = async name => JSON.parse(await fs.readFile(path.join(jsonDir, name), "utf8"));
const asInt = value => value === null || value === undefined || value === "" ? null : Number(value);
const withPremium = materialTotal => materialTotal + Math.max(1, Math.ceil(materialTotal * PREMIUM_RATE));

async function openWorkbook() {
  return SpreadsheetFile.importXlsx(await FileBlob.load(workbookPath));
}

async function renderWorkbook(workbook, suffix) {
  await fs.mkdir(previewDir, { recursive: true });
  for (const sheetName of ["items_regular", "items_recipe_product"]) {
    const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
    await fs.writeFile(
      path.join(previewDir, `${sheetName}_${suffix}.png`),
      new Uint8Array(await preview.arrayBuffer()),
    );
  }
}

function updateValuesById(sheet, valuesById) {
  const rows = sheet.getUsedRange().values;
  const headers = rows[0].map(value => String(value ?? "").trim());
  const idColumn = headers.indexOf("id");
  const valueColumn = headers.indexOf("value");
  if (idColumn < 0 || valueColumn < 0) throw new Error("items worksheet is missing id/value columns");
  let updated = 0;
  for (let row = 1; row < rows.length; row++) {
    const itemId = Number(rows[row][idColumn]);
    if (!valuesById.has(itemId)) continue;
    sheet.getCell(row, valueColumn).values = [[valuesById.get(itemId)]];
    updated++;
  }
  return updated;
}

function calculateValues(items, recipes) {
  const allItems = [...items.regular, ...items.launcher, ...items.crafting, ...(items.effect ?? [])];
  const byId = new Map();
  for (const item of allItems) if (!byId.has(Number(item.id))) byId.set(Number(item.id), item);

  const changedMergeItems = [];
  const mergeChains = new Map();
  for (const item of items.regular.filter(item => Number(item.type) === 0 && Number.isInteger(Number(item.group_id)))) {
    const groupId = Number(item.group_id);
    if (!mergeChains.has(groupId)) mergeChains.set(groupId, []);
    mergeChains.get(groupId).push(item);
  }
  for (const chain of mergeChains.values()) {
    chain.sort((a, b) => Number(a.level) - Number(b.level));
    let previousItem = null;
    for (const item of chain) {
      const oldValue = asInt(item.value) ?? DEFAULT_MATERIAL_VALUE;
      let newValue = Math.max(DEFAULT_MATERIAL_VALUE, oldValue);
      if (previousItem && Number(item.level) === Number(previousItem.level) + 1) {
        newValue = Math.max(newValue, withPremium(Number(previousItem.value) * 2));
      }
      item.value = newValue;
      if (newValue !== oldValue) changedMergeItems.push({ id: Number(item.id), oldValue, newValue });
      previousItem = item;
    }
  }

  const recipesByResult = new Map();
  for (const recipe of recipes) {
    const resultId = Number(recipe.result);
    if (!recipesByResult.has(resultId)) recipesByResult.set(resultId, []);
    recipesByResult.get(resultId).push(recipe);
  }
  const resolved = new Map();
  const visiting = new Set();
  const resolve = itemId => {
    if (resolved.has(itemId)) return resolved.get(itemId);
    const item = byId.get(itemId);
    if (!item) throw new Error(`recipe references unknown item id ${itemId}`);
    if (!recipesByResult.has(itemId)) {
      const value = Math.max(0, asInt(item.value) ?? DEFAULT_MATERIAL_VALUE);
      resolved.set(itemId, value);
      return value;
    }
    if (visiting.has(itemId)) throw new Error(`recipe value cycle detected at item ${itemId}`);
    visiting.add(itemId);
    const materialTotals = recipesByResult.get(itemId).map(recipe =>
      recipe.ingredients.reduce((sum, ingredientId) => sum + resolve(Number(ingredientId)), 0));
    visiting.delete(itemId);
    const value = Math.max(asInt(item.value) ?? 0, withPremium(Math.max(...materialTotals)));
    resolved.set(itemId, value);
    return value;
  };

  const changedRecipeProducts = [];
  for (const resultId of [...recipesByResult.keys()].sort((a, b) => a - b)) {
    const item = byId.get(resultId);
    const oldValue = asInt(item.value) ?? 0;
    const newValue = resolve(resultId);
    item.value = newValue;
    if (newValue !== oldValue) changedRecipeProducts.push({ id: resultId, oldValue, newValue });
  }
  return { changedMergeItems, changedRecipeProducts, productIds: new Set(recipesByResult.keys()) };
}

const workbook = await openWorkbook();
if (process.argv.includes("--preview")) {
  await renderWorkbook(workbook, "before");
  const regularRows = workbook.worksheets.getItem("items_regular").getUsedRange().values;
  const header = regularRows[0].map(value => String(value ?? "").trim());
  const selected = regularRows.slice(1).filter(row => Number(row[header.indexOf("level")]) === 4 && Number(row[header.indexOf("value")]) === 9);
  console.log(JSON.stringify({ level4Value9Rows: selected }, null, 2));
  process.exit(0);
}

const items = await readJson("items.json");
const recipes = (await readJson("recipes.json")).recipes;
const result = calculateValues(items, recipes);
const regularValues = new Map(items.regular.filter(item => Number(item.type) === 0).map(item => [Number(item.id), Number(item.value)]));
const recipeValues = new Map(items.regular.filter(item => result.productIds.has(Number(item.id))).map(item => [Number(item.id), Number(item.value)]));

if (process.argv.includes("--verify")) {
  const failures = [];
  const chains = new Map();
  for (const item of items.regular.filter(item => Number(item.type) === 0)) {
    if (!chains.has(Number(item.group_id))) chains.set(Number(item.group_id), []);
    chains.get(Number(item.group_id)).push(item);
  }
  for (const chain of chains.values()) {
    chain.sort((a, b) => Number(a.level) - Number(b.level));
    for (let index = 1; index < chain.length; index++) {
      if (Number(chain[index].level) !== Number(chain[index - 1].level) + 1) continue;
      if (Number(chain[index].value) <= Number(chain[index - 1].value) * 2) {
        failures.push(`merge value ${chain[index].id} is not above two ${chain[index - 1].id}`);
      }
    }
  }
  const itemValues = new Map([...items.regular, ...items.launcher, ...items.crafting].map(item => [Number(item.id), asInt(item.value) ?? DEFAULT_MATERIAL_VALUE]));
  for (const recipe of recipes) {
    const materialTotal = recipe.ingredients.reduce((sum, id) => sum + (itemValues.get(Number(id)) ?? DEFAULT_MATERIAL_VALUE), 0);
    if ((itemValues.get(Number(recipe.result)) ?? 0) <= materialTotal) {
      failures.push(`recipe ${recipe.id} result ${recipe.result} does not exceed ${materialTotal}`);
    }
  }
  for (const [sheetName, expected] of [["items_regular", regularValues], ["items_recipe_product", recipeValues]]) {
    const rows = workbook.worksheets.getItem(sheetName).getUsedRange().values;
    const headers = rows[0].map(value => String(value ?? "").trim());
    const idColumn = headers.indexOf("id");
    const valueColumn = headers.indexOf("value");
    for (const row of rows.slice(1)) {
      const id = Number(row[idColumn]);
      if (expected.has(id) && Number(row[valueColumn]) !== expected.get(id)) {
        failures.push(`${sheetName} ${id} workbook=${row[valueColumn]} json=${expected.get(id)}`);
      }
    }
  }
  if (failures.length > 0) throw new Error(failures.slice(0, 20).join("\n"));
  console.log(JSON.stringify({
    mergeChains: chains.size,
    mergeItemsChecked: [...chains.values()].reduce((sum, chain) => sum + chain.length, 0),
    recipesChecked: recipes.length,
    workbookSheetsChecked: 2,
    recalculationIsStable: result.changedMergeItems.length === 0 && result.changedRecipeProducts.length === 0,
  }, null, 2));
  process.exit(0);
}

const regularRowsUpdated = updateValuesById(workbook.worksheets.getItem("items_regular"), regularValues);
const recipeRowsUpdated = updateValuesById(workbook.worksheets.getItem("items_recipe_product"), recipeValues);

const tempWorkbookPath = `${workbookPath}.tmp`;
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(tempWorkbookPath);
await fs.rename(tempWorkbookPath, workbookPath);
await fs.writeFile(path.join(jsonDir, "items.json"), `${JSON.stringify(items, null, 2)}\n`, "utf8");
await renderWorkbook(workbook, "after");

console.log(JSON.stringify({
  premiumRate: PREMIUM_RATE,
  changedMergeItems: result.changedMergeItems.length,
  changedRecipeProducts: result.changedRecipeProducts.length,
  regularRowsUpdated,
  recipeRowsUpdated,
  level4Byproducts: items.regular
    .filter(item => Number(item.type) === 0 && Number(item.level) === 4 && [2, 6, 8, 10, 12, 14].includes(Number(item.group_id)))
    .map(item => ({ id: item.id, name: item.name, value: item.value, orderReward: item.value * 10 })),
}, null, 2));
