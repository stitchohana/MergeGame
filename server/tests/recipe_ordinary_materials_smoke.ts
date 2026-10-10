import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const recipes = gameConfigTables.recipes.recipes;
const productIds = new Set(recipes.map(recipe => recipe.result));
const ordinaryIds = new Set(gameConfigTables.items.regular
  .filter(item => Number(item.type ?? 0) === 0)
  .map(item => item.id));
const replacedRecipeIds = new Set([
  31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
  41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
  81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
  91, 92, 93, 94, 95, 96, 97, 100, 143, 145,
  147, 148, 149, 150, 160, 201, 204, 207,
]);
const log = console.log;
let matchedCount = 0;

try {
  console.log = () => {};
  for (const recipe of recipes) {
    assert.equal(new Set(recipe.ingredients).size, recipe.ingredients.length,
      `duplicate ingredient in recipe ${recipe.id}`);
    for (const ingredient of recipe.ingredients) {
      assert.ok(ordinaryIds.has(ingredient), `non-ordinary ingredient ${ingredient} in recipe ${recipe.id}`);
      assert.ok(!productIds.has(ingredient), `recipe product ${ingredient} in recipe ${recipe.id}`);
    }
    // Existing unrelated material-combination collisions remain outside this migration.
    if (!replacedRecipeIds.has(recipe.id)) continue;
    const table = gameConfigTables.items.crafting.find(item => item.recipes.includes(recipe.id));
    assert.ok(table, `recipe ${recipe.id} has no crafting table`);
    const state = engine.createInitialState();
    state.grid = [{ uid: 1, id: table.id, col: 0, row: 0 },
      ...recipe.ingredients.map((id, index) => ({ uid: index + 2, id, col: index + 1, row: 0 }))];
    for (const [index, ingredient] of recipe.ingredients.entries()) {
      const inserted = engine.addIngredientToTable(state, 0, 0, ingredient, index + 1, 0);
      assert.ok(inserted.ok, `recipe ${recipe.id} ingredient insertion failed`);
    }
    const matched = engine.validateCraftStart(state, 0, 0);
    assert.ok(matched.valid, `recipe ${recipe.id} failed to match`);
    assert.equal(matched.recipe.result, recipe.result, `recipe ${recipe.id} matched a different product`);
    matchedCount += 1;
  }
} finally {
  console.log = log;
}

assert.equal(matchedCount, replacedRecipeIds.size);
console.log(`RECIPE_ORDINARY_MATERIALS_SMOKE_OK recipes=${recipes.length} matched=${matchedCount}`);
