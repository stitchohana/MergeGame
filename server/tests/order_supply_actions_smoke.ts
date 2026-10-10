import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

async function main() {
  const config = { ...gameConfigTables, recipes: { recipes: gameConfigTables.recipes.recipes.map(recipe =>
    recipe.result === 27002 ? { ...recipe, ingredients: [27001, 9002] } : recipe) } };
  const engine = new GameEngine(config);
  const storage = new MemoryStorage();
  const router = createGameRouter(storage, engine, "supply-actions-secret");
  const token = await signToken({ userId: "actions", deviceId: "test" }, "supply-actions-secret");
  async function request(path: string, body: unknown) {
    const response = new WorkerResponse();
    await router.handle({ method: "POST", path, body, headers: { authorization: `Bearer ${token}` }, query: {} }, response);
    return { status: response.statusCode, data: await response.toResponse().json() as any };
  }
  const order = (id: number, extra = {}) => ({ item_id: id, name: "test", count: 1, completed: false, ...extra });
  const state = engine.createInitialState();
  // One result matches two orders but only counts once, without submitting either.
  state.meridian_acupoints = [order(5002), order(5002, { item_ids: [5002, 9002] })];
  state.grid = [0, 1, 2, 3].map(col => ({ id: 5001, uid: engine._nextUid(state), col, row: 0 }));
  await storage.saveState("actions", state);
  const first = await request("/merge", { from: [0, 0], to: [1, 0] });
  assert.equal(first.status, 200);
  assert.equal(first.data.activity_progress[7].current_count, 1);
  assert.ok(Number.isInteger(first.data.storage_revision));
  assert.equal((await storage.loadState("actions"))!.meridian_acupoints!.length, 2);
  assert.equal((await request("/merge", { from: [0, 0], to: [1, 0] })).status, 400);
  // Failed batches must not persist partial progress.
  const operations = [{ type: "merge", from: [2, 0], to: [3, 0] }];
  assert.equal((await request("/actions/batch", { operations: [...operations, { type: "invalid", from: [0, 0], to: [1, 0] }] })).status, 400);
  assert.equal((await storage.loadState("actions"))!.activity_progress![7].current_count, 1);
  const batch = await request("/actions/batch", { operations });
  assert.equal(batch.status, 200);
  assert.equal(batch.data.activity_progress[7].current_count, 2);

  // Completed orders, breakthrough placeholders and unrelated results don't count.
  for (const orders of [[], [order(9002)], [order(5002, { completed: true })], [order(5002, { breakthrough_order: true })]]) {
    const unrelated = engine.createInitialState();
    unrelated.meridian_acupoints = orders;
    unrelated.grid = [0, 1].map(col => ({ id: 5001, uid: engine._nextUid(unrelated), col, row: 0 }));
    assert.equal(engine.executeMerge(unrelated, 0, 0, 1, 0).ok, true);
    assert.equal(unrelated.activity_progress?.[7]?.current_count ?? 0, 0);
  }

  // Starting a sub-recipe must not count toward its parent's order.
  const parentRecipe = config.recipes.recipes.find(parent =>
    config.recipes.recipes.some(child => parent.ingredients.includes(child.result)));
  assert.ok(parentRecipe, "need a nested test recipe for the regression");
  const childRecipe = config.recipes.recipes.find(child => parentRecipe.ingredients.includes(child.result))!;
  for (const orders of [[], [order(parentRecipe.result)], [order(childRecipe.result, { completed: true })],
    [order(childRecipe.result, { breakthrough_order: true })]]) {
    const subCraft = (await storage.loadState("actions"))!;
    subCraft.meridian_acupoints = orders;
    subCraft.grid = [{ id: 17001, uid: engine._nextUid(subCraft), col: 0, row: 0,
      craft: { _craft_init: true, _craft_state: 1, _craft_stored: childRecipe.ingredients.map(id => ({ id })),
        _craft_recipe: childRecipe, _craft_progress: 0, _craft_result_id: -1, _craft_start_time: 0 } }];
    await storage.saveState("actions", subCraft);
    const subStarted = await request("/craft/start", { table_col: 0, table_row: 0 });
    assert.equal(subStarted.status, 200);
    assert.equal(subStarted.data.activity_progress[7].current_count, 2);
  }
  // Exact recipe output counts once even when two orders directly request it.
  const crafting = (await storage.loadState("actions"))!;
  const recipe = gameConfigTables.recipes.recipes[0];
  crafting.meridian_acupoints = [order(recipe.result), order(5001, { item_ids: [5001, recipe.result] })];
  crafting.grid = [{ id: 17001, uid: engine._nextUid(crafting), col: 0, row: 0,
    craft: { _craft_init: true, _craft_state: 1, _craft_stored: recipe.ingredients.map(id => ({ id })),
      _craft_recipe: recipe, _craft_progress: 0, _craft_result_id: -1, _craft_start_time: 0 } }];
  await storage.saveState("actions", crafting);
  const started = await request("/craft/start", { table_col: 0, table_row: 0 });
  assert.equal(started.status, 200);
  assert.equal(started.data.activity_progress[7].current_count, 3);
  assert.ok(started.data.storage_revision > batch.data.storage_revision);
  assert.equal((await request("/craft/start", { table_col: 0, table_row: 0 })).status, 400);
  const afterStart = (await storage.loadState("actions"))!;
  assert.equal(afterStart.activity_progress![7].current_count, 3);
  afterStart.grid[0].craft!._craft_state = 3;
  assert.equal(engine.executeCraftRetrieve(afterStart, 0, 0).ok, true);
  assert.equal(afterStart.activity_progress![7].current_count, 3);

  // Direct launcher output counts once, with progress included even for correct predictions.
  const spawning = (await storage.loadState("actions"))!;
  spawning.meridian_acupoints = [];
  spawning.grid = [{ uid: engine._nextUid(spawning), id: 11001, col: 0, row: 0, charges: 5 }];
  spawning.stamina = 400;
  spawning.spawn_seed = 12345;
  spawning.spawn_sequence = 0;
  const preview = engine.executeSpawn(structuredClone(spawning), 0, 0, 0);
  assert.ok(preview.ok);
  spawning.meridian_acupoints = [order(preview.spawnedId), order(9002, { item_ids: [preview.spawnedId, 9002] })];
  await storage.saveState("actions", spawning);
  const spawnBody = { launcher_pos: [0, 0], request_id: "supply-spawn-1", expected_sequence: 0,
    predicted_id: preview.spawnedId, predicted_target: [preview.targetCol, preview.targetRow] };
  const spawned = await request("/spawn", spawnBody);
  assert.equal(spawned.status, 200);
  assert.equal(spawned.data.prediction_matches, true);
  assert.equal(spawned.data.activity_progress[7].current_count, 4);
  const replay = await request("/spawn", spawnBody);
  assert.equal(replay.data.replayed, true);
  assert.equal(replay.data.activity_progress[7].current_count, 4);
  assert.equal((await request("/spawn", { ...spawnBody, request_id: "stale-sequence" })).status, 409);

  // Sub-materials, completed orders and failed spawns do not count.
  for (const orders of [[], [order(recipe.result)], [order(preview.spawnedId, { completed: true })]]) {
    const unrelatedSpawn = structuredClone(spawning);
    unrelatedSpawn.meridian_acupoints = orders;
    assert.equal(engine.executeSpawn(unrelatedSpawn, 0, 0, 0).ok, true);
    assert.equal(unrelatedSpawn.activity_progress![7].current_count, 3);
  }
  const failedSpawn = structuredClone(spawning);
  failedSpawn.stamina = 0;
  assert.equal(engine.executeSpawn(failedSpawn, 0, 0, 0).ok, false);
  assert.equal(failedSpawn.activity_progress![7].current_count, 3);

  // Boosted output matches by final ID and still counts one item, not the multiplier.
  const boosted = structuredClone(spawning);
  boosted.meridian_acupoints = [];
  engine.refreshStaminaMultiplierFromBalance(boosted);
  const boostedPreview = engine.executeSpawn(structuredClone(boosted), 0, 0, 0, 4);
  assert.ok(boostedPreview.ok);
  boosted.meridian_acupoints = [order(boostedPreview.spawnedId)];
  const boostedResult = engine.executeSpawn(boosted, 0, 0, 0, 4);
  assert.ok(boostedResult.ok);
  assert.equal(boostedResult.spawnedId, boostedPreview.spawnedId);
  assert.equal(boosted.activity_progress![7].current_count, 4);
  console.log("order_supply_actions_smoke: ok");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
