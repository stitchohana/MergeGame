import assert from "node:assert/strict";
import { gameConfigTables } from "../src/worker/config_data";

const secondsByProductLevel = new Map<number, number>([
  [1, 60], [2, 180], [3, 300], [4, 600],
  [5, 1200], [6, 1800], [7, 2700], [8, 3600],
  [9, 5400], [10, 7200], [11, 10800], [12, 14400],
  [13, 21600], [14, 28800], [15, 36000], [16, 43200],
]);

const itemsConfig: any = gameConfigTables.items;
const recipesConfig: any = gameConfigTables.recipes;
const productLevelById = new Map<number, number>(
  itemsConfig.regular.map((item: any) => [item.id, item.level]),
);

for (const recipe of recipesConfig.recipes) {
  const productLevel = productLevelById.get(recipe.result);
  assert.notEqual(productLevel, undefined, `missing level for recipe ${recipe.id}`);
  assert.equal(
    recipe.craft_time,
    secondsByProductLevel.get(productLevel!),
    `unexpected craft time for recipe ${recipe.id} at product level ${productLevel}`,
  );
}

const configuredTimes = [...secondsByProductLevel.values()];
assert.equal(Math.min(...configuredTimes), 60);
assert.equal(Math.max(...configuredTimes), 12 * 60 * 60);
for (let index = 1; index < configuredTimes.length; index += 1) {
  assert.ok(configuredTimes[index] > configuredTimes[index - 1]);
}

console.log("CRAFT_TIME_PROGRESSION_SERVER_SMOKE_OK");
