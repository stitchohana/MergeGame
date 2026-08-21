import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(root, "json_output");
const read = name => JSON.parse(fs.readFileSync(path.join(out, name), "utf8"));
const write = (name, data) => {
  const text = JSON.stringify(data, null, 2).split("\n").map(line => {
    const spaces = line.length - line.trimStart().length;
    return "\t".repeat(Math.floor(spaces / 4)) + " ".repeat(spaces % 4) + line.slice(spaces);
  }).join("\n");
  fs.writeFileSync(path.join(out, name), text + "\n");
};

const items = read("items.json");
const recipes = read("recipes.json").recipes;
const meridians = read("meridians.json");
const rewards = read("rewards.json");
const home = read("home_meridians.json");
const cultivation = read("cultivation.json");
const gameConfig = read("game_config.json");
const allItems = [...items.regular, ...items.launcher, ...items.crafting, ...(items.effect ?? [])];
const byId = new Map(allItems.map(item => [item.id, item]));
const cost = new Map();

// A launch costs one stamina. Weighted outputs cost the reciprocal of their drop chance.
for (const launcher of [...items.launcher, ...items.regular]) {
  const spawns = launcher.spawns ?? [];
  const fixed = launcher.fixed_spawns ?? [];
  const totalWeight = spawns.reduce((sum, spawn) => sum + spawn.weight, 0);
  for (const spawn of spawns) {
    const candidate = totalWeight / spawn.weight;
    cost.set(spawn.id, Math.min(cost.get(spawn.id) ?? Infinity, candidate));
  }
  for (const id of fixed) cost.set(id, Math.min(cost.get(id) ?? Infinity, 1));
}

const groups = new Map();
for (const item of allItems) {
  if (item.group_id == null || item.level == null) continue;
  if (!groups.has(item.group_id)) groups.set(item.group_id, []);
  groups.get(item.group_id).push(item);
}
for (const group of groups.values()) group.sort((a, b) => a.level - b.level);

for (let pass = 0; pass < 100; pass++) {
  let changed = false;
  for (const group of groups.values()) {
    for (let i = 1; i < group.length; i++) {
      const previous = cost.get(group[i - 1].id);
      if (previous == null) continue;
      const candidate = previous * 2 ** Math.max(1, group[i].level - group[i - 1].level);
      if (candidate < (cost.get(group[i].id) ?? Infinity)) {
        cost.set(group[i].id, candidate);
        changed = true;
      }
    }
  }
  for (const recipe of recipes) {
    const ingredientCosts = recipe.ingredients.map(id => cost.get(id));
    if (ingredientCosts.some(value => value == null)) continue;
    const candidate = ingredientCosts.reduce((sum, value) => sum + value, 0);
    if (candidate < (cost.get(recipe.result) ?? Infinity)) {
      cost.set(recipe.result, candidate);
      changed = true;
    }
  }
  if (!changed) break;
}

let changedValues = 0;
for (const item of allItems) {
  const expectedCost = cost.get(item.id);
  if (expectedCost == null || !Number.isFinite(expectedCost)) continue;
  const newValue = Math.max(1, Math.round(expectedCost));
  if (item.value !== newValue) changedValues++;
  item.value = newValue;
}

const qiPerValue = 10;
const orderRewardId = 219;
rewards.rewards[String(orderRewardId)] = { tokens: [{ token: 2, amount: qiPerValue }] };
// A crafted product inherits the highest regular-item level in its full recipe tree.
const itemTier = new Map();
const recipesByResult = new Map();
for (const recipe of recipes) {
  if (!recipesByResult.has(recipe.result)) recipesByResult.set(recipe.result, []);
  recipesByResult.get(recipe.result).push(recipe);
}
const getItemTier = (id, visiting = new Set()) => {
  if (itemTier.has(id)) return itemTier.get(id);
  const item = byId.get(id);
  const itemType = Number(item?.type ?? 0);
  if (!item || (itemType !== 0 && itemType !== 4)) return null;
  if (itemType === 0) return Number.isFinite(Number(item.level)) ? Number(item.level) : null;
  if (visiting.has(id)) return null;
  visiting.add(id);
  const ingredientTiers = (recipesByResult.get(id) ?? [])
    .flatMap(recipe => recipe.ingredients.map(ingredientId => getItemTier(ingredientId, visiting)));
  visiting.delete(id);
  const tier = ingredientTiers.length > 0 && ingredientTiers.every(value => value != null)
    ? Math.max(...ingredientTiers)
    : null;
  itemTier.set(id, tier);
  return tier;
};
for (const item of items.regular) {
  if (Number(item.type ?? 0) === 4) getItemTier(item.id);
}

const orderPoolForStage = stage => {
  const range = (meridians.order_pool?.level_ranges ?? []).find(entry =>
    stage >= Number(entry.cultivation_min) && stage <= Number(entry.cultivation_max));
  if (!range) return [];
  const [regularMin, regularMax] = range.items_regular;
  const [recipeMin, recipeMax] = range.items_recipe_product;
  const regularProducts = items.regular
    .filter(item => Number(item.type ?? 0) === 0)
    .filter(item => Number(item.level) >= regularMin && Number(item.level) <= regularMax)
    .map(item => item.id);
  const craftedProducts = items.regular
    .filter(item => Number(item.type ?? 0) === 4)
    .filter(item => {
      const tier = getItemTier(item.id);
      return tier != null && tier >= recipeMin && tier <= recipeMax;
    })
    .map(item => item.id);
  return [...new Set([...regularProducts, ...craftedProducts])].sort((a, b) => a - b);
};

for (const threshold of meridians.thresholds) {
  const stage = Number(threshold.stage);
  delete threshold.item_pool;
  threshold.order_count = Math.max(5, Number(threshold.order_count ?? 5));
  threshold.acupoint_rewards = orderRewardId;
  delete threshold.qi_per_value;
}

// Small early-game adjustments let integer EXP rewards stay close to a 70/30 split.
const earlyExpTargets = [30, 56, 90, 108, 157, 214, 320];
for (let i = 0; i < earlyExpTargets.length; i++) cultivation.stages[i].exp = earlyExpTargets[i];

const regenInterval = gameConfig.stamina.regen_interval;
const targetDays = 300;
const naturalStamina = Math.floor(targetDays * 86400 / regenInterval) * gameConfig.stamina.regen_amount;
const progressionHomeStages = String(home.stages[0]?.name ?? "").startsWith("凡人")
  ? home.stages.slice(1)
  : home.stages;
const homeStamina = progressionHomeStages.reduce((sum, stage) => sum + stage.acupoints * 15 + 100, 0);
const targetQi = (naturalStamina + homeStamina) * qiPerValue;
const oldQi = progressionHomeStages.reduce((sum, stage) => sum + stage.acupoints * stage.qi_cost, 0);
const qiScale = targetQi / oldQi;
for (const stage of progressionHomeStages) stage.qi_cost = Math.max(1, Math.round(stage.qi_cost * qiScale));

// Home has 19 cultivation groups: nine single cycles, then ten groups of ten cycles.
let homeIndex = 0;
for (let groupIndex = 0; groupIndex < 19; groupIndex++) {
  const cycleCount = groupIndex < 9 ? 1 : 10;
  const stages = progressionHomeStages.slice(homeIndex, homeIndex + cycleCount);
  const targetExp = cultivation.stages[groupIndex + 1]?.exp ?? cultivation.stages[groupIndex].exp;
  for (let i = 0; i < stages.length; i++) {
    const stage = stages[i];
    const cycleBudget = Math.floor(targetExp / cycleCount) + (i < targetExp % cycleCount ? 1 : 0);
    const acupointExp = Math.max(1, Math.round(cycleBudget * 0.7 / stage.acupoints));
    const holeTotal = acupointExp * stage.acupoints;
    const circulationExp = Math.max(1, cycleBudget - holeTotal);
    stage.acupoint_rewards = { tokens: [{ token: 4, amount: acupointExp }, { token: 3, amount: 15 }] };
    stage.circulation_rewards = { tokens: [{ token: 4, amount: circulationExp }, { token: 3, amount: 100 }] };
  }
  homeIndex += cycleCount;
}

// An order can contain the most valuable count_max distinct items. Keep two max orders bankable.
for (let i = 0; i < cultivation.stages.length; i++) {
  const threshold = meridians.thresholds.find(entry => entry.stage === i + 1);
  if (!threshold) continue;
  const maxOrderValue = orderPoolForStage(i + 1)
    .map(id => byId.get(id)?.value ?? 0)
    .sort((a, b) => b - a)
    .slice(0, threshold.count_max)
    .reduce((sum, value) => sum + value, 0);
  cultivation.stages[i].max_qi = Math.max(100, Math.ceil(maxOrderValue * qiPerValue * 2 / 100) * 100);
}

write("items.json", items);
write("meridians.json", meridians);
write("rewards.json", rewards);
write("home_meridians.json", home);
write("cultivation.json", cultivation);

const finalQi = home.stages.reduce((sum, stage) => sum + stage.acupoints * stage.qi_cost, 0);
console.log(JSON.stringify({ target_days: targetDays, natural_stamina: naturalStamina, home_reward_stamina: homeStamina, stamina_budget: naturalStamina + homeStamina, target_qi: targetQi, configured_qi_cost: finalQi, changed_item_values: changedValues }, null, 2));
