import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { GameState } from "../src/storage/interface";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

class TestStorage extends MemoryStorage {
  fail = false;
  override async saveState(id: string, state: GameState) {
    if (this.fail) { this.fail = false; throw new Error("save_failed"); }
    await super.saveState(id, state);
  }
}

async function main() {
  const engine = new GameEngine(gameConfigTables);
  const storage = new TestStorage();
  const state = engine.createInitialState();
  state.cultivation.current_level = 2;
  state.stamina = 199;
  engine.recordItemDiscovery(state, 1001);
  engine.recordItemDiscovery(state, 1002);
  await storage.saveState("catalog", state);
  const secret = "item-catalog-test-secret";
  const token = await signToken({ userId: "catalog", deviceId: "catalog" }, secret);
  const router = createGameRouter(storage, engine, secret);
  async function request(path: string, body: unknown = {}, method = "POST") {
    const res = new WorkerResponse();
    await router.handle({ method, path, body, headers: { authorization: "Bearer " + token }, query: {} }, res);
    return { status: res.statusCode, data: await res.toResponse().json() as any };
  }
  await request("/state", {}, "GET"); // Initialize unlocked activities before failure injection.
  assert.deepEqual((await request("/state", {}, "GET")).data.item_catalog_claimed_ids, []);
  for (const item_id of ["1001", null, 0, -1, 1.5]) {
    assert.equal((await request("/item_catalog/claim", { item_id })).data.error, "invalid_params");
  }
  assert.equal((await request("/item_catalog/claim", { item_id: 99999999 })).data.error, "item_not_found");
  assert.equal((await request("/item_catalog/claim", { item_id: 1016 })).data.error, "item_locked");
  const before = (await storage.loadState("catalog"))!;
  storage.fail = true;
  assert.equal((await request("/item_catalog/claim", { item_id: 1001 })).data.error, "save_failed");
  assert.deepEqual(await storage.loadState("catalog"), before);
  const claims = await Promise.all([
    request("/item_catalog/claim", { item_id: 1001 }),
    request("/item_catalog/claim", { item_id: 1001 }),
  ]);
  assert.equal(claims[0].status, 200);
  assert.equal(claims[0].data.reward_stamina, 1);
  assert.equal(claims[0].data.stamina, 200); // Rewards overflow the natural regeneration cap.
  assert.equal(claims[0].data.stamina_multiplier_max, 2);
  assert.equal(claims[1].status, 200);
  assert.equal(claims[1].data.already_claimed, true);
  assert.equal(claims[1].data.reward_stamina, 0);
  assert.equal(claims[1].data.stamina, 200);
  const loaded = await request("/state", {}, "GET");
  assert.deepEqual(loaded.data.item_catalog_claimed_ids, [1001]);
  const persisted = (await storage.loadState("catalog"))!;
  persisted.grid = persisted.grid.filter(item => item.id !== 1001);
  await storage.saveState("catalog", persisted);
  const reloadedEngine = new GameEngine(gameConfigTables);
  const restored = (await storage.loadState("catalog"))!;
  assert.equal(reloadedEngine.claimItemCatalogReward(restored, 1001).reward_stamina, 0);
  const second = await request("/item_catalog/claim", { item_id: 1002 });
  assert.equal(second.data.stamina, 201);
  assert.deepEqual(second.data.item_catalog_claimed_ids, [1001, 1002]);
  console.log("item_catalog_smoke: ok");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
