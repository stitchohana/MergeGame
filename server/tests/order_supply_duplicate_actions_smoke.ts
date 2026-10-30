import assert from "node:assert/strict";
import { GameEngine, TableState } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { GameState } from "../src/storage/interface";

async function main() {
  const engine = new GameEngine(gameConfigTables);
  const order = (id: number, count = 1, extra = {}) => ({ item_ids: Array(count).fill(id), name: "test", completed: false, ...extra });
  const progress = (s: GameState) => s.activity_progress?.[7]?.current_count ?? 0;
  const merge = (s: GameState) => {
    s.grid = [0, 1].map(col => ({ id: 5001, uid: engine._nextUid(s), col, row: 0 }));
    assert.equal(engine.executeMerge(s, 0, 0, 1, 0).ok, true);
  };
  const state = engine.createInitialState(); state.cultivation.current_level = 2;
  state.meridian_acupoints = [order(5002)];
  merge(state);
  assert.equal(progress(state), 1);
  merge(state); // Even removing the original product must not credit the same slot again.
  assert.equal(progress(state), 1);
  const storage = new MemoryStorage();
  await storage.saveState("duplicates", state);
  const reloaded = (await storage.loadState("duplicates"))!;
  merge(reloaded);
  assert.equal(progress(reloaded), 1);
  reloaded.activity_progress![7].current_count = 5;
  assert.equal(engine.activityEngine.claimOrderSupply(reloaded, 7, 0, engine).ok, true);
  merge(reloaded);
  assert.equal(progress(reloaded), 0, "claim must not reset coverage of the current order");
  reloaded.meridian_acupoints = [order(5002)];
  merge(reloaded);
  assert.equal(progress(reloaded), 1, "a fresh order may count the same item ID");

  const multiple = engine.createInitialState(); multiple.cultivation.current_level = 2;
  multiple.meridian_acupoints = [order(5002, 2), order(5002, 1, { item_ids: [5002, 9001] })];
  for (let i = 1; i <= 4; i++) {
    merge(multiple);
    assert.equal(progress(multiple), Math.min(i, 3));
  }

  // Preexisting inventory covers demand without awarding progress; one remaining slot counts.
  for (const source of ["grid", "pouch", "pending", "storage"] as const) {
    const existing = engine.createInitialState(); existing.cultivation.current_level = 2;
    existing.meridian_acupoints = [order(5002, 2)];
    existing.grid = [0, 1].map(col => ({ id: 5001, uid: engine._nextUid(existing), col, row: 0 }));
    if (source === "grid") existing.grid.push({ id: 5002, uid: engine._nextUid(existing), col: 2, row: 0 });
    if (source === "pouch") existing.pouch = [{ id: 5002, uid: engine._nextUid(existing) }];
    if (source === "pending") existing.pending_rewards = [{ id: 5002, uid: engine._nextUid(existing), name: "existing" }];
    if (source === "storage") existing.grid.push({ id: 17001, col: 2, row: 0, storage: { items: [{ id: 5002 }], max_slots: 1 } });
    assert.equal(engine.executeMerge(existing, 0, 0, 1, 0).ok, true);
    assert.equal(progress(existing), 1);
    merge(existing);
    assert.equal(progress(existing), 1);
  }

  const recipe = gameConfigTables.recipes.recipes[0];
  const makeTable = (s: GameState, tableState = TableState.HAS_ITEMS, col = 0) => ({
    id: 17001, uid: engine._nextUid(s), col, row: 0,
    craft: { _craft_init: true, _craft_state: tableState, _craft_stored: recipe.ingredients.map(id => ({ id })),
      _craft_recipe: recipe, _craft_result_id: tableState === TableState.HAS_ITEMS ? -1 : recipe.result,
      _craft_progress: 0, _craft_start_time: Date.now() },
  });
  const crafting = engine.createInitialState(); crafting.cultivation.current_level = 2;
  crafting.meridian_acupoints = [order(recipe.result)];
  crafting.grid = [makeTable(crafting)];
  assert.equal(engine.executeCraftStart(crafting, 0, 0).ok, true);
  assert.equal(progress(crafting), 1);
  crafting.grid[0].craft!._craft_state = TableState.READY;
  assert.equal(engine.executeCraftRetrieve(crafting, 0, 0).ok, true);
  crafting.grid = [makeTable(crafting)];
  assert.equal(engine.executeCraftStart(crafting, 0, 0).ok, true);
  assert.equal(progress(crafting), 1);
  for (const tableState of [TableState.CRAFTING, TableState.READY]) {
    const covered = engine.createInitialState(); covered.cultivation.current_level = 2;
    covered.meridian_acupoints = [order(recipe.result)];
    covered.grid = [makeTable(covered, tableState), makeTable(covered, TableState.HAS_ITEMS, 1)];
    assert.equal(engine.executeCraftStart(covered, 1, 0).ok, true);
    assert.equal(progress(covered), 0, "existing table outputs cover the order");
  }

  const spawnConfig = { ...gameConfigTables, items: { ...gameConfigTables.items,
    launcher: gameConfigTables.items.launcher.map(item => item.id === 11001
      ? { ...item, spawns: [{ id: 5002, weight: 1 }], fixed_spawns: [] } : item) } };
  const spawnEngine = new GameEngine(spawnConfig);
  const spawning = spawnEngine.createInitialState(); spawning.cultivation.current_level = 2;
  spawning.meridian_acupoints = [order(5002)];
  spawning.grid = [{ id: 11001, uid: spawnEngine._nextUid(spawning), col: 0, row: 0, charges: 5 }];
  for (let i = 0; i < 3; i++) {
    assert.equal(spawnEngine.executeSpawn(spawning, 0, 0, spawning.spawn_sequence ?? 0).ok, true);
    assert.equal(progress(spawning), 1);
  }
  console.log("order_supply_duplicate_actions_smoke: ok");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
