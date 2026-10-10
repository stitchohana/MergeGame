import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

async function main() {
  const engine = new GameEngine(gameConfigTables);
  const state = engine.createInitialState();
  assert.equal(state.pouch_capacity, 7);
  assert.equal(engine.getPouchState(state).pouch_next_unlock_cost, 100);
  state.grid = Array.from({ length: 8 }, (_, i) => ({ uid: i + 1, id: 5001, col: i % 7, row: Math.floor(i / 7) }));
  for (let uid = 1; uid <= 7; uid++) assert.equal(engine.pouchDeposit(state, uid).ok, true);
  const full = structuredClone(state);
  assert.deepEqual(engine.pouchDeposit(state, 8), { ok: false, reason: "pouch_full" });
  assert.deepEqual(state, full);
  state.spirit_stones = 99;
  const poor = structuredClone(state);
  assert.deepEqual(engine.pouchUnlock(state, 7), { ok: false, reason: "insufficient_stones" });
  assert.deepEqual(state, poor);
  state.spirit_stones = 1000;
  assert.equal(engine.pouchUnlock(state, 7).ok, true);
  assert.equal(state.spirit_stones, 900);
  assert.equal(state.pouch_capacity, 8);
  assert.equal(engine.getPouchState(state).pouch_next_unlock_cost, 150);
  const unlocked = structuredClone(state);
  assert.deepEqual(engine.pouchUnlock(state, 7), { ok: false, reason: "state_conflict" });
  assert.deepEqual(state, unlocked);
  assert.equal(engine.pouchDeposit(state, 8).ok, true);
  assert.equal(engine.pouchUnlock(state, 8).ok, true);
  assert.equal(state.spirit_stones, 750);
  assert.equal(engine.getPouchState(state).pouch_next_unlock_cost, 200);
  // Exact UID matters when several stored items share an item ID.
  assert.equal(engine.pouchWithdraw(state, 4, 0, 0).ok, true);
  assert.equal(state.grid[0].uid, 4);
  assert.ok(!state.pouch.some((p: any) => p.uid === 4));

  const legacy = structuredClone(state);
  delete legacy.pouch_capacity;
  delete legacy.pouch_unlock_count;
  assert.equal(engine.ensurePouchCapacity(legacy), true);
  assert.equal(legacy.pouch_capacity, 7);
  legacy.pouch.push({ uid: 99, id: 5001 }, { uid: 100, id: 5001 });
  delete legacy.pouch_capacity;
  engine.ensurePouchCapacity(legacy);
  assert.equal(legacy.pouch_capacity, 9);
  assert.equal(engine.getPouchState(legacy).pouch_next_unlock_cost, 100);

  const custom = new GameEngine({ ...gameConfigTables, gameConfig: {
    ...gameConfigTables.gameConfig, pouch: { initial_slots: "3", unlock_cost_base: "25", unlock_cost_increment: "10" },
  } });
  const customState = custom.createInitialState();
  customState.spirit_stones = 100;
  assert.equal(customState.pouch_capacity, 3);
  assert.equal(custom.pouchUnlock(customState, 3).ok, true);
  assert.equal(customState.spirit_stones, 75);
  assert.equal(custom.getPouchState(customState).pouch_next_unlock_cost, 35);
  const invalid = new GameEngine({ ...gameConfigTables, gameConfig: { ...gameConfigTables.gameConfig, pouch: { initial_slots: -1, unlock_cost_base: "bad", unlock_cost_increment: 0 } } });
  assert.deepEqual(invalid.getPouchState(invalid.createInitialState()), { pouch_capacity: 7, pouch_next_unlock_cost: 100 });

  class FailingStorage extends MemoryStorage {
    fail = false;
    override async saveState(id: string, value: any) {
      if (this.fail) { this.fail = false; throw new Error("save_failed"); }
      return super.saveState(id, value);
    }
  }
  const storage = new FailingStorage();
  const stored = engine.createInitialState();
  stored.spirit_stones = 500;
  await storage.saveState("pouch", stored);
  const router = createGameRouter(storage, engine, "pouch-test-secret");
  const token = await signToken({ userId: "pouch", deviceId: "test" }, "pouch-test-secret");
  async function request(path: string, body: any = {}, method = "POST") {
    const response = new WorkerResponse();
    await router.handle({ method, path, body, headers: { authorization: "Bearer " + token }, query: {} }, response);
    return { status: response.statusCode, data: await response.toResponse().json() as any };
  }
  await request("/state", {}, "GET");
  const before = await storage.loadState("pouch");
  for (const expected_capacity of [undefined, "7", -1, 7.5]) {
    assert.equal((await request("/pouch/unlock", { expected_capacity })).status, 400);
  }
  storage.fail = true;
  assert.equal((await request("/pouch/unlock", { expected_capacity: 7 })).status, 500);
  assert.deepEqual(await storage.loadState("pouch"), before);
  const results = await Promise.all([request("/pouch/unlock", { expected_capacity: 7 }), request("/pouch/unlock", { expected_capacity: 7 })]);
  assert.deepEqual(results.map(r => r.status), [200, 409]);
  assert.equal(results[0].data.spirit_stones, 400);
  assert.equal(results[0].data.pouch_capacity, 8);
  assert.equal(results[0].data.pouch_next_unlock_cost, 150);
  const reloaded = await request("/state", {}, "GET");
  assert.equal(reloaded.data.pouch_capacity, 8);
  assert.equal(reloaded.data.spirit_stones, 400);
  assert.equal(reloaded.data.pouch_next_unlock_cost, 150);
  console.log("POUCH_CAPACITY_SMOKE_OK initial=7 costs=100,150,200 full=true replay_safe=true persistence=true");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
