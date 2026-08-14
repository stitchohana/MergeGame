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
// Order eligibility is category-driven. Facility unlock state is applied by
// the server at runtime, so this balance script must not filter by group_id.
const isOrderCandidate = id => {
  const item = byId.get(id);
  return item && (Number(item.type ?? 0) === 0 || Number(item.type ?? 0) === 4);
};

// A crafted product inherits the highest progression tier of its ingredients.
const itemTier = new Map();
for (const item of allItems) {
  if (item.level != null) itemTier.set(item.id, Number(item.level));
}
for (let pass = 0; pass < 100; pass++) {
  let changed = false;
  for (const recipe of recipes) {
    const ingredientTiers = recipe.ingredients.map(id => itemTier.get(id));
    if (ingredientTiers.some(tier => tier == null)) continue;
    const tier = Math.max(...ingredientTiers);
    if (tier > (itemTier.get(recipe.result) ?? 0)) {
      itemTier.set(recipe.result, tier);
      changed = true;
    }
  }
  if (!changed) break;
}

const uniqueRecipeResults = [...new Set(recipes.map(recipe => recipe.result))];
const makeOrderPool = (regularTiers, craftedMinTier, craftedMaxTier) => {
  const regularProducts = items.regular
    .filter(item => Number(item.type ?? 0) === 0)
    .filter(item => regularTiers.has(Number(item.level)))
    .map(item => item.id)
    .filter(isOrderCandidate);
  const craftedProducts = uniqueRecipeResults
    .filter(id => itemTier.has(id))
    .filter(id => itemTier.get(id) >= craftedMinTier && itemTier.get(id) <= craftedMaxTier)
    .filter(isOrderCandidate);
  return [...new Set([...regularProducts, ...craftedProducts])].sort((a, b) => a - b);
};

const orderPoolsByPeriod = {
  qi: makeOrderPool(new Set([4]), 1, 4),
  foundation: makeOrderPool(new Set([7, 8]), 5, 8),
  goldenCore: makeOrderPool(new Set([10, 11, 12]), 9, 12),
  nascentSoul: makeOrderPool(new Set([13, 14, 15, 16]), 13, 16),
};
const orderPoolForStage = stage => {
  if (stage <= 10) return orderPoolsByPeriod.qi;
  if (stage <= 13) return orderPoolsByPeriod.foundation;
  if (stage <= 16) return orderPoolsByPeriod.goldenCore;
  return orderPoolsByPeriod.nascentSoul;
};

for (const threshold of meridians.thresholds) {
  const stage = Number(threshold.stage);
  threshold.item_pool = orderPoolForStage(stage);
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
  const maxOrderValue = threshold.item_pool
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
