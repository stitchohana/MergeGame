import assert from "node:assert/strict";
import { GameEngine, TableState } from "../src/engine/game_engine";
import { signToken } from "../src/middleware/auth";
import { clearBoardItems, createGMRouter } from "../src/routes/gm";
import { createGameRouter } from "../src/routes/game";
import { GameState, GridItem } from "../src/storage/interface";
import { MemoryStorage } from "../src/storage/memory";
import { gameConfigTables } from "../src/worker/config_data";
import { WorkerRequest, WorkerResponse } from "../src/worker/http";

const engine = new GameEngine(gameConfigTables);

function fixture(boardType: number): GameState {
  const state = engine.createInitialState();
  const main: GridItem[] = [
    { uid: 100, id: 11001, col: 0, row: 0, charges: 3, last_charge_time: Date.now() },
    { uid: 101, id: 17001, col: 1, row: 0, craft: {
      _craft_init: true, _craft_state: TableState.HAS_ITEMS,
      _craft_stored: [{ id: 9003, uid: 900 }], _craft_recipe: {},
      _craft_progress: 0, _craft_result_id: 0, _craft_start_time: 0,
    } },
    { uid: 102, id: 5002, col: 2, row: 0, immovable: true },
    { uid: 103, id: 27081, col: 3, row: 0 },
    { uid: 104, id: 99999999, col: 4, row: 0 },
  ];
  const battle: GridItem[] = [
    { uid: 200, id: 18002, col: 0, row: 0 },
    { uid: 201, id: 9004, col: 1, row: 0 },
  ];
  state.board_type = boardType;
  state.grid = boardType === 1 ? battle : main;
  state.saved_grid = boardType === 1 ? main : undefined;
  state.battle_grid = boardType === 1 ? undefined : battle;
  state.pouch = [{ uid: 300, id: 5002 }];
  state.pending_rewards = [{ uid: 400, id: 9004, name: "玉壶露" }];
  return state;
}

async function main(): Promise<void> {
  for (const boardType of [0, 1]) {
    const state = fixture(boardType);
    const main = boardType === 1 ? state.saved_grid! : state.grid;
    const battle = boardType === 1 ? state.grid : state.battle_grid!;
    const facilities = structuredClone([main[0], main[1], battle[0]]);
    const pouch = structuredClone(state.pouch);
    const rewards = structuredClone(state.pending_rewards);
    const version = state.version;
    // Exercise an alias as well as the normal active/cached board layout.
    if (boardType === 1) state.battle_grid = state.grid;
    assert.equal(clearBoardItems(state, engine), 4);
    assert.deepEqual([...main, ...battle], facilities);
    assert.deepEqual(state.pouch, pouch);
    assert.deepEqual(state.pending_rewards, rewards);
    assert.equal(state.version, version + 1);
    assert.equal(state.board_type, boardType);
    assert.equal(clearBoardItems(state, engine), 0);
    assert.equal(state.version, version + 1);
  }
  const empty = engine.createInitialState();
  empty.grid = [{ uid: 500, id: 5002, col: 0, row: 0 }];
  assert.equal(clearBoardItems(empty, engine), 1);
  assert.deepEqual(empty.grid, []);

  const storage = new MemoryStorage();
  const initial = fixture(1);
  await storage.saveState("gm-clean-user", initial);
  const secret = "gm-clear-board-smoke-secret";
  const router = createGMRouter(storage, engine, secret, "test-key");
  const token = await signToken({ userId: "gm-clean-user", deviceId: "gm-device" }, secret);
  async function request(key: string): Promise<{ status: number; data: any }> {
    const req: WorkerRequest = { method: "POST", path: "/exec",
      headers: { authorization: `Bearer ${token}` }, query: {},
      body: { gm_key: key, cmd: "clear_board_items" } };
    const res = new WorkerResponse();
    assert.equal(await router.handle(req, res), true);
    const response = res.toResponse();
    return { status: response.status, data: await response.json() };
  }
  assert.equal((await request("wrong-key")).status, 403);
  assert.deepEqual(await storage.loadState("gm-clean-user"), initial);
  const result = await request("test-key");
  assert.equal(result.status, 200);
  assert.equal(result.data.ok, true);
  assert.equal(result.data.removed_count, 4);
  assert.match(result.data.msg, /4 件物品/);
  const saved = (await storage.loadState("gm-clean-user"))!;
  assert.deepEqual(saved.grid.map(item => item.uid), [200]);
  assert.deepEqual(saved.saved_grid!.map(item => item.uid), [100, 101]);
  assert.deepEqual(saved.saved_grid![1].craft, initial.saved_grid![1].craft);
  assert.deepEqual(saved.pouch, initial.pouch);
  assert.deepEqual(saved.pending_rewards, initial.pending_rewards);
  assert.equal((await request("test-key")).data.removed_count, 0);
  // Clearing a main board with no facilities must remain empty even while
  // viewing the battle board; fetching state must not recreate initial items.
  const noFacilities = fixture(1);
  noFacilities.saved_grid = [{ uid: 600, id: 5002, col: 0, row: 0 }];
  noFacilities.storage_revision = (await storage.loadState("gm-clean-user"))!.storage_revision;
  await storage.saveState("gm-clean-user", noFacilities);
  assert.equal((await request("test-key")).data.removed_count, 2);
  const gameRouter = createGameRouter(storage, engine, secret);
  const response = new WorkerResponse();
  assert.equal(await gameRouter.handle({ method: "GET", path: "/state",
    headers: { authorization: `Bearer ${token}` }, body: {}, query: {},
  }, response), true);
  const snapshot = response.toResponse();
  assert.equal(snapshot.status, 200);
  const data: any = await snapshot.json();
  assert.deepEqual(data.main_grid, []);
  assert.deepEqual(data.battle_grid.map((item: GridItem) => item.uid), [200]);
  console.log("GM_CLEAR_BOARD_ITEMS_SMOKE_OK boards facilities stored_materials alias idempotent empty auth persistence state_sync");
}

void main();
