import assert from "node:assert/strict";
import { GameEngine, TableState } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

const engine = new GameEngine(gameConfigTables);

function fullBoard(craftState: TableState) {
  const state = engine.createInitialState();
  state.cultivation.current_level = 2;
  state.grid = Array.from({ length: engine.GRID_COLS * engine.GRID_ROWS }, (_, index) => ({
    uid: index + 1, id: 5001, col: index % engine.GRID_COLS, row: Math.floor(index / engine.GRID_COLS),
  }));
  state.uid_counter = state.grid.length + 2;
  state.grid[0] = { ...state.grid[0], id: 17001, craft: {
    _craft_init: true, _craft_state: craftState,
    _craft_stored: [{ id: 5001, uid: 64 }, { id: 9001, uid: 65 }],
    _craft_recipe: { id: 1, craft_time: 1 }, _craft_result_id: 27001,
    _craft_progress: 1, _craft_start_time: Date.now() - 10_000,
  } };
  return state;
}

async function main() {
  for (const craftState of [TableState.READY, TableState.CRAFTING]) {
    const state = fullBoard(craftState);
    const before = structuredClone(state);
    for (let attempt = 0; attempt < 2; attempt++) {
      assert.deepEqual(engine.executeCraftRetrieve(state, 0, 0), { ok: false, reason: "no_empty_cell" });
      assert.deepEqual(state, before, "failed retrieval must not mutate any player state");
    }
    const empty = state.grid.pop()!;
    const result = engine.executeCraftRetrieve(state, 0, 0);
    assert.equal(result.ok, true);
    if (!result.ok) throw new Error(result.reason);
    assert.equal(state.grid[0].craft, undefined);
    assert.deepEqual(state.grid.find(item => item.uid === result.resultUid), {
      uid: before.uid_counter + 1, id: 27001, col: empty.col, row: empty.row,
    });
    assert.equal(state.version, before.version + 1);
    assert.equal(state.grid.length, before.grid.length);
    const after = structuredClone(state);
    assert.equal(engine.executeCraftRetrieve(state, 0, 0).ok, false);
    assert.deepEqual(state, after, "a retry must not duplicate the product");
  }

  const storage = new MemoryStorage();
  const userId = "full-board-craft";
  const secret = "craft-full-board-test";
  const token = await signToken({ userId, deviceId: "test" }, secret);
  const router = createGameRouter(storage, engine, secret);
  const state = fullBoard(TableState.READY);
  await storage.saveState(userId, state);
  async function retrieve() {
    const response = new WorkerResponse();
    await router.handle({ method: "POST", path: "/craft/retrieve", query: {},
      headers: { authorization: `Bearer ${token}` }, body: { table_col: 0, table_row: 0 } }, response);
    return { status: response.statusCode, data: await response.toResponse().json() as any };
  }
  // Initialize unlocked activities before measuring retrieval changes.
  const loaded = new WorkerResponse();
  await router.handle({ method: "GET", path: "/state", body: {}, query: {},
    headers: { authorization: `Bearer ${token}` } }, loaded);
  assert.equal(loaded.statusCode, 200);
  const before = (await storage.loadState(userId))!;
  const rejected = await retrieve();
  assert.equal(rejected.status, 400);
  assert.equal(rejected.data.error, "no_empty_cell");
  const reloaded = (await storage.loadState(userId))!;
  assert.deepEqual(reloaded.grid, before.grid, "reload must retain the completed craft");
  assert.equal(reloaded.uid_counter, before.uid_counter);
  assert.equal(reloaded.version, before.version);
  assert.deepEqual(reloaded.quest_progress, before.quest_progress);
  reloaded.grid.pop();
  await storage.saveState(userId, reloaded);
  assert.equal((await retrieve()).status, 200);
  const saved = (await storage.loadState(userId))!;
  assert.equal(saved.grid[0].craft, undefined);
  assert.equal(saved.grid.filter(item => item.id === 27001).length, 1);
  assert.equal((await retrieve()).status, 400);
  console.log("CRAFT_RETRIEVE_FULL_BOARD_SERVER_SMOKE_OK");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
