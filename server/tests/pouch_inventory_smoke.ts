import assert from "node:assert/strict";
import { GameEngine, TableState } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

async function main() {
  const engine = new GameEngine(gameConfigTables);
  const makeState = (ids: number[]) => {
    const state = engine.createInitialState();
    state.grid = [];
    state.pouch = [];
    state.cultivation.current_qi = 0;
    state.cultivation.max_qi = 100000;
    state.meridian_acupoints = [{ item_id: ids[0], count: ids.length, item_ids: ids,
      name: "inventory", completed: false, total_value: 1 } as any];
    return state;
  };
  const pouchOnly = makeState([5001, 5001]);
  pouchOnly.pouch = [{ uid: 11, id: 5001 }, { uid: 12, id: 5001 }, { uid: 13, id: 6001 }];
  const completed = engine.completeMeridianAcupoint(pouchOnly, 0, [5001, 5001], "pouch-only");
  assert.equal(completed.ok, true);
  assert.deepEqual(pouchOnly.pouch, [{ uid: 13, id: 6001 }]);
  assert.ok(completed.ok && completed.pouch === pouchOnly.pouch);
  assert.equal(pouchOnly.grid.length, 0);
  const replay = structuredClone(pouchOnly);
  assert.equal(engine.completeMeridianAcupoint(pouchOnly, 0, [5001, 5001], "pouch-only").ok, false);
  assert.deepEqual(pouchOnly, replay);

  const mixed = makeState([5001, 5001, 6001]);
  mixed.grid = [{ uid: 21, id: 5001, col: 0, row: 0 }, { uid: 22, id: 6001, col: 1, row: 0, immovable: true }];
  mixed.pouch = [{ uid: 23, id: 5001 }, { uid: 24, id: 6001 }, { uid: 25, id: 5001 }];
  assert.equal(engine.completeMeridianAcupoint(mixed, 0, [6001, 5001, 5001]).ok, true);
  assert.deepEqual(mixed.grid.map(item => item.uid), [22]);
  assert.deepEqual(mixed.pouch.map((item: any) => item.uid), [25]);

  for (const failure of ["shortage", "qi", "wrong_items", "locked", "duplicate_uid"]) {
    const state = makeState([5001, 5001]);
    state.grid = [{ uid: 31, id: 5001, col: 0, row: 0 }];
    if (failure !== "shortage") state.pouch = [{ uid: failure === "duplicate_uid" ? 31 : 32, id: 5001, immovable: failure === "locked" }];
    if (failure === "qi") state.cultivation.current_qi = state.cultivation.max_qi;
    const before = structuredClone(state);
    assert.equal(engine.completeMeridianAcupoint(state, 0, failure === "wrong_items" ? [5001, 6001] : [5001, 5001]).ok, false);
    assert.deepEqual(state, before, failure + " must not partially consume inventory");
  }
  const legacy = makeState([5001, 5001]);
  legacy.pouch = [5001, 5001, 6001];
  assert.equal(engine.completeMeridianAcupoint(legacy, 0, [5001, 5001]).ok, true);
  assert.deepEqual(legacy.pouch, [6001]);

  const full = makeState([5001]);
  full.grid = Array.from({ length: 63 }, (_, i) => ({ uid: 100 + i, id: 6001, col: i % 7, row: Math.floor(i / 7) }));
  full.pouch = [{ uid: 199, id: 5001 }];
  assert.equal(engine.completeMeridianAcupoint(full, 0, [5001]).ok, true);
  assert.equal(full.grid.length, 63, "bag submission requires no empty cell");

  const supply = makeState([27001]);
  supply.pouch = [{ uid: 40, id: 27001 }];
  assert.deepEqual((engine as any).getOutstandingOrderItemCounts(supply).size, 0);
  assert.deepEqual(engine.getMissingOrderSupplyMaterials(supply), []);
  supply.pouch = [{ uid: 41, id: 5001 }, { uid: 42, id: 9001 }];
  assert.deepEqual(engine.getMissingOrderSupplyMaterials(supply), []);
  const facilities = engine.createInitialState();
  const pool = engine.getUnlockedOrderPool(facilities);
  facilities.pouch = facilities.grid.map(({ col, row, ...item }) => ({ ...item, uid: item.uid! }));
  facilities.grid = [];
  assert.deepEqual(engine.getUnlockedOrderPool(facilities), pool);

  const transfer = makeState([5001]);
  const craft = { _craft_init: true, _craft_state: TableState.CRAFTING, _craft_stored: [{ uid: 52, id: 5001 }],
    _craft_recipe: { result: 27001, craft_time: 1 }, _craft_progress: 0, _craft_result_id: 27001, _craft_start_time: Date.now() - 2000 };
  transfer.grid = [{ uid: 51, id: 17001, col: 0, row: 0, charges: 1, last_charge_time: Date.now(), atk_base: 12,
    craft, storage: { max_slots: 3, items: [{ id: 6001 }] } }];
  const original = structuredClone(transfer.grid[0]);
  assert.equal(engine.pouchDeposit(transfer, 51).ok, true);
  assert.equal(engine.tickCraftingState(transfer), true);
  assert.equal((transfer.pouch[0] as any).craft._craft_state, TableState.READY);
  const withdrawn = engine.pouchWithdraw(transfer, 51, 2, 3);
  assert.equal(withdrawn.ok, true);
  assert.deepEqual(transfer.grid[0], { ...original, col: 2, row: 3, craft: { ...craft, _craft_state: TableState.READY, _craft_progress: 1 } });
  assert.ok(withdrawn.ok && withdrawn.item === transfer.grid[0]);
  transfer.grid = [];
  assert.equal(engine.switchBoard(transfer, 1).ok, true);
  assert.equal(engine.switchBoard(transfer, 0).ok, true);
  assert.deepEqual(transfer.grid, [], "switching must preserve an intentionally empty board");

  class FailingStorage extends MemoryStorage {
    fail = false;
    override async saveState(id: string, state: any) {
      if (this.fail) { this.fail = false; throw new Error("save_failed"); }
      return super.saveState(id, state);
    }
  }
  const storage = new FailingStorage();
  const stored = makeState([5001, 5001]);
  stored.pouch = [{ uid: 71, id: 5001 }, { uid: 72, id: 5001 }];
  await storage.saveState("inventory", stored);
  const router = createGameRouter(storage, engine, "inventory-secret");
  const token = await signToken({ userId: "inventory", deviceId: "test" }, "inventory-secret");
  const request = async (path: string, body: any = {}, method = "POST") => {
    const response = new WorkerResponse();
    await router.handle({ method, path, body, query: {}, headers: { authorization: "Bearer " + token } }, response);
    return { status: response.statusCode, data: await response.toResponse().json() as any };
  };
  assert.equal((await request("/state", {}, "GET")).data.grid.length, 0);
  const before = await storage.loadState("inventory");
  storage.fail = true;
  assert.equal((await request("/meridian/complete", { index: 0, item_ids: [5001, 5001], request_id: "persist" })).status, 500);
  assert.deepEqual(await storage.loadState("inventory"), before);
  const response = await request("/meridian/complete", { index: 0, item_ids: [5001, 5001], request_id: "persist" });
  assert.equal(response.status, 200);
  assert.deepEqual(response.data.pouch, []);
  const reload = await request("/state", {}, "GET");
  assert.deepEqual(reload.data.grid, []);
  assert.deepEqual(reload.data.pouch, []);
  const transferState = await storage.loadState("inventory");
  assert.ok(transferState);
  transferState.grid = [{ uid: 73, id: 15001, col: 0, row: 0, charges: 0, last_charge_time: Date.now(), atk_base: 15 }];
  await storage.saveState("inventory", transferState);
  assert.equal((await request("/pouch/deposit", { uid: 73 })).status, 200);
  const retrieved = await request("/pouch/withdraw", { uid: 73 });
  assert.equal(retrieved.status, 200);
  assert.equal(retrieved.data.item.uid, 73);
  assert.equal(retrieved.data.item.charges, 0);
  assert.equal(retrieved.data.item.atk_base, 15);
  assert.ok(retrieved.data.item.last_charge_time > 0);
  const recharging = makeState([5001]);
  recharging.pouch = [{ uid: 80, id: 15001, charges: 0, last_charge_time: 1 }];
  engine.tickLauncherRecharge(recharging);
  assert.equal((recharging.pouch[0] as any).charges, engine.getItemData(15001)!.max_charges ?? 3);
  console.log("pouch_inventory_smoke: passed");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
