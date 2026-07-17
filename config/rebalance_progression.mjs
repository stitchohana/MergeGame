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
const isOrderExcluded = id => {
  const item = byId.get(id);
  const groupId = Number(item?.group_id ?? 0);
  const isEffectItem = Number(item?.type ?? 0) === 5;
  const isManualOrFormationScroll = groupId === 13 || groupId === 14;
  const isSwordFormationOrTalisman = id >= 28001 && id <= 28048;
  return isEffectItem || isManualOrFormationScroll || isSwordFormationOrTalisman;
};
const launcherOutputIds = new Set();
for (const launcher of [...items.launcher, ...items.regular]) {
  for (const spawn of launcher.spawns ?? []) launcherOutputIds.add(spawn.id);
  for (const id of launcher.fixed_spawns ?? []) launcherOutputIds.add(id);
}

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

for (const threshold of meridians.thresholds) {
  const stage = Number(threshold.stage);
  const requiredTier = stage <= 10 ? Math.ceil(stage / 2) : stage - 5;
  const launcherProducts = [...launcherOutputIds]
    .filter(id => itemTier.get(id) === requiredTier)
    .filter(id => !isOrderExcluded(id));
  const craftedProducts = recipes
    .map(recipe => recipe.result)
    .filter((id, index, values) => values.indexOf(id) === index)
    .filter(id => itemTier.get(id) === requiredTier)
    .filter(id => !isOrderExcluded(id))
    .filter(id => Number(byId.get(id)?.effect_type ?? 0) !== 5);
  threshold.item_pool = [...new Set([...launcherProducts, ...craftedProducts])].sort((a, b) => a - b);
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
const homeStamina = home.stages.reduce((sum, stage) => sum + stage.acupoints * 15 + 100, 0);
const targetQi = (naturalStamina + homeStamina) * qiPerValue;
const oldQi = home.stages.reduce((sum, stage) => sum + stage.acupoints * stage.qi_cost, 0);
const qiScale = targetQi / oldQi;
for (const stage of home.stages) stage.qi_cost = Math.max(1, Math.round(stage.qi_cost * qiScale));

// Home has 19 cultivation groups: nine single cycles, then ten groups of ten cycles.
let homeIndex = 0;
for (let groupIndex = 0; groupIndex < 19; groupIndex++) {
  const cycleCount = groupIndex < 9 ? 1 : 10;
  const stages = home.stages.slice(homeIndex, homeIndex + cycleCount);
  const targetExp = cultivation.stages[groupIndex].exp;
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
