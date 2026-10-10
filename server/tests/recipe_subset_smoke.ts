import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const log = console.log;
console.log = () => {};
let matched = 0;
try {
  const engine = new GameEngine(gameConfigTables);
  const recipes = gameConfigTables.recipes.recipes;
  for (const recipe of recipes) {
    const materials = new Set(recipe.ingredients);
    for (const other of recipes) {
      if (recipe.id === other.id) continue;
      assert.ok(!(materials.size < other.ingredients.length && [...materials].every(id => other.ingredients.includes(id))),
        `recipe ${recipe.id} is a subrecipe of ${other.id}`);
    }
    const table = gameConfigTables.items.crafting.find(item => item.recipes.includes(recipe.id));
    assert.ok(table, `recipe ${recipe.id} has no crafting table`);
    for (const ingredients of [recipe.ingredients, [...recipe.ingredients].reverse()]) {
      const state = engine.createInitialState();
      state.grid = [{ uid: 1, id: table.id, col: 0, row: 0 },
        ...ingredients.map((id, index) => ({ uid: index + 2, id, col: index + 1, row: 0 }))];
      for (const [index, id] of ingredients.entries()) {
        const inserted = engine.addIngredientToTable(state, 0, 0, id, index + 1, 0);
        assert.ok(inserted.ok, `recipe ${recipe.id}: insertion failed`);
        if (index < ingredients.length - 1) {
          assert.equal(inserted.matched, false, `recipe ${recipe.id} matched before its final ingredient`);
        }
      }
      const result = engine.validateCraftStart(state, 0, 0);
      assert.ok(result.valid, `recipe ${recipe.id} failed to match`);
      assert.equal(result.recipe.id, recipe.id, `recipe ${recipe.id} matched another recipe`);
      assert.equal(result.recipe.result, recipe.result);
      matched++;
    }
  }
} finally {
  console.log = log;
}
assert.equal(matched, gameConfigTables.recipes.recipes.length * 2);
console.log(`RECIPE_SUBSET_SMOKE_OK recipes=${gameConfigTables.recipes.recipes.length} matched=${matched} premature_matches=0`);
