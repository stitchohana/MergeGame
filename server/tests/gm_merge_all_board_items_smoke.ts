import assert from "node:assert/strict";
import { GameEngine, TableState } from "../src/engine/game_engine";
import { signToken } from "../src/middleware/auth";
import { createGMRouter, mergeAllBoardItems } from "../src/routes/gm";
import { MemoryStorage } from "../src/storage/memory";
import { gameConfigTables } from "../src/worker/config_data";
import { WorkerRequest, WorkerResponse } from "../src/worker/http";

const engine = new GameEngine(gameConfigTables);
function fixture(boardType = 0) {
  const state = engine.createInitialState();
  const ids = [5001, 5001, 5001, 5001, 9001, 9001, 9001,
    11001, 11001, 11001, 11001, 17001, 17001, 17001, 17001, 17001, 17001];
  state.grid = ids.map((id, index) => ({ uid: 100 + index, id,
    col: index % engine.GRID_COLS, row: Math.floor(index / engine.GRID_COLS) }));
  for (const [index, craftState] of [[13, TableState.HAS_ITEMS], [14, TableState.CRAFTING], [15, TableState.READY]]) {
    state.grid[index].craft = { _craft_init: true, _craft_state: craftState,
      _craft_stored: craftState === TableState.HAS_ITEMS ? [{id: 9001, uid: 700}] : [],
      _craft_recipe: {}, _craft_progress: 0, _craft_result_id: craftState >= TableState.CRAFTING ? 10001 : 0,
      _craft_start_time: Date.now() };
  }
  state.grid[16].storage = {items: [{id: 5001}], max_slots: 1};
  state.board_type = boardType;
  const inactive = [{ uid: 800, id: 5001, col: 0, row: 0 }, { uid: 801, id: 5001, col: 1, row: 0 }];
  if (boardType === 1) { state.saved_grid = inactive; state.battle_grid = state.grid; }
  else state.battle_grid = inactive;
  state.pouch = [{uid: 900, id: 5001}, {uid: 901, id: 5001}];
  state.pending_rewards = [{uid: 902, id: 5001, name: "露芽米"}];
  return state;
}

async function main() {
  for (const boardType of [0, 1]) {
    const state = fixture(boardType);
    const originalGrid = state.grid;
    const inactive = structuredClone(boardType === 1 ? state.saved_grid : state.battle_grid);
    const protectedItems = structuredClone(state.grid.slice(13));
    const pouch = structuredClone(state.pouch);
    const pending = structuredClone(state.pending_rewards);
    const stamina = state.stamina;
    const version = state.version;
    assert.equal(mergeAllBoardItems(state, engine), 8);
    assert.equal(state.grid, originalGrid, "cached grid aliases must remain current");
    assert.deepEqual(state.grid.map(item => item.id).sort((a, b) => a - b),
      [5003, 9001, 9002, 11003, 17001, 17001, 17001, 17001, 17002]);
    assert.deepEqual(state.grid.filter(item => item.uid! >= 113 && item.uid! <= 116), protectedItems);
    assert.equal(state.grid.find(item => item.id === 11003)!.charges, engine.getMaxCharges(11003));
    assert.ok(state.crafted_item_ids.includes(5002) && state.crafted_item_ids.includes(5003));
    assert.ok(state.unlocked_production_item_ids.includes(11003));
    assert.equal(state.version, version + 8);
    assert.equal(state.stamina, stamina);
    assert.deepEqual(state.pouch, pouch);
    assert.deepEqual(state.pending_rewards, pending);
    assert.deepEqual(boardType === 1 ? state.saved_grid : state.battle_grid, inactive);
    const after = structuredClone(state);
    assert.equal(mergeAllBoardItems(state, engine), 0);
    assert.deepEqual(state, after, "repeating the command must do nothing");
  }

  const locked = fixture();
  locked.grid = [
    {uid: 1, id: 5001, col: 0, row: 0, immovable: true},
    {uid: 2, id: 5001, col: 1, row: 0, immovable: true},
  ];
  assert.equal(mergeAllBoardItems(locked, engine), 0);
  locked.grid.push({uid: 3, id: 5001, col: 2, row: 0});
  assert.equal(mergeAllBoardItems(locked, engine), 1);
  assert.deepEqual(locked.grid.map(item => [item.id, item.col, item.immovable]), [[5001, 1, true], [5002, 0, undefined]]);

  const maxState = fixture();
  const maxItem = gameConfigTables.items.regular.find(item => !engine.getNextLevel(item.type, item.level, item.group_id))!;
  maxState.grid = [maxItem.id, maxItem.id, 99999999, 99999999].map((id, col) => ({uid: col + 1, id, col, row: 0}));
  assert.equal(mergeAllBoardItems(maxState, engine), 0);
  maxState.grid = [];
  assert.equal(mergeAllBoardItems(maxState, engine), 0);

  const full = fixture();
  full.grid = Array.from({length: engine.MAX_CELLS}, (_, index) => ({uid: 1000 + index, id: 5001,
    col: index % engine.GRID_COLS, row: Math.floor(index / engine.GRID_COLS)}));
  assert.equal(mergeAllBoardItems(full, engine), 57);
  assert.deepEqual(full.grid.map(item => item.id).sort((a, b) => a - b), [5001, 5002, 5003, 5004, 5005, 5006]);

  const storage = new MemoryStorage();
  const initial = fixture(1);
  await storage.saveState("gm-merge-user", initial);
  const secret = "gm-merge-smoke-secret";
  const token = await signToken({userId: "gm-merge-user", deviceId: "gm-device"}, secret);
  const router = createGMRouter(storage, engine, secret, "test-key");
  async function request(key = "test-key", authorization = `Bearer ${token}`) {
    const req: WorkerRequest = {method: "POST", path: "/exec", headers: {authorization}, query: {},
      body: {gm_key: key, cmd: "merge_all_board_items"}};
    const res = new WorkerResponse();
    assert.equal(await router.handle(req, res), true);
    const response = res.toResponse();
    return {status: response.status, data: await response.json() as any};
  }
  assert.equal((await request("wrong-key")).status, 403);
  assert.equal((await request("test-key", "")).status, 401);
  assert.deepEqual(await storage.loadState("gm-merge-user"), initial);
  const result = await request();
  assert.equal(result.status, 200);
  assert.equal(result.data.merged_count, 8);
  assert.equal(result.data.remaining_count, 9);
  assert.ok(result.data.newly_discovered_item_ids.includes(11003));
  const saved = (await storage.loadState("gm-merge-user"))!;
  assert.deepEqual(saved.grid, result.data.grid);
  assert.deepEqual(saved.battle_grid, saved.grid);
  assert.deepEqual(saved.saved_grid, initial.saved_grid);
  assert.equal((await request()).data.merged_count, 0);
  console.log("GM_MERGE_ALL_BOARD_ITEMS_SMOKE_OK chain facilities craft_states storage locked max current_board aliases retry auth persistence");
}

void main();
