import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import type { GameState } from "../src/storage/interface";
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
  const service = engine.resourcePurchaseService;
  const state = engine.createInitialState();
  state.spirit_stones = 1000;
  state.cultivation.current_qi = state.cultivation.max_qi;
  const beforeReset = Date.parse("2026-10-14T04:59:59+08:00");
  const afterReset = Date.parse("2026-10-14T05:00:00+08:00");
  const period = service.periodKey(beforeReset);
  const initialStamina = state.stamina;
  assert.equal(service.offers(state, beforeReset).stamina.cost, 100);
  assert.equal(service.buy(state, "stamina", 0, period, "first", beforeReset).ok, true);
  assert.equal(state.stamina, initialStamina + 100);
  assert.equal(state.spirit_stones, 900);
  assert.equal(service.offers(state, beforeReset).stamina.cost, 200);
  assert.equal(service.offers(state, beforeReset).qi.cost, 100);
  const snapshot = structuredClone(state);
  assert.equal(service.buy(state, "stamina", 0, period, "first", beforeReset).ok, true);
  assert.deepEqual(state, snapshot);
  assert.equal(service.buy(state, "qi", 0, period, "first", beforeReset).ok, false);
  assert.equal(service.buy(state, "stamina", 0, period, "stale", beforeReset).ok, false);
  assert.equal(service.buy(state, "stamina", 1, period, "second", beforeReset).ok, true);
  assert.equal(state.spirit_stones, 700);
  assert.equal(service.buy(state, "qi", 0, period, "qi-first", beforeReset).ok, true);
  assert.equal(state.cultivation.current_qi, state.cultivation.max_qi + 100);
  assert.equal(service.offers(state, beforeReset).qi.cost, 200);
  assert.equal(service.offers(state, beforeReset).stamina.cost, 300);
  assert.equal(service.offers(state, afterReset).stamina.cost, 100);
  assert.equal(service.offers(state, afterReset).qi.cost, 100);
  assert.equal(service.buy(state, "stamina", 2, period, "expired-quote", afterReset).ok, false);
  assert.equal(service.buy(state, "qi", 0, service.periodKey(afterReset), "qi-today", afterReset).ok, true);
  assert.equal(service.offers(state, afterReset).stamina.cost, 100);
  state.spirit_stones = 99;
  const poor = structuredClone(state);
  assert.equal(service.buy(state, "stamina", 0, service.periodKey(afterReset), "poor", afterReset).ok, false);
  assert.deepEqual(state, poor);

  const storage = new TestStorage();
  const saved = engine.createInitialState();
  saved.spirit_stones = 1000;
  await storage.saveState("purchase", saved);
  const router = createGameRouter(storage, engine, "purchase-secret");
  const token = await signToken({ userId: "purchase", deviceId: "purchase-device" }, "purchase-secret");
  const request = async (path: string, body: any = {}, method = "POST") => {
    const response = new WorkerResponse();
    await router.handle({ method, path, body, headers: { authorization: "Bearer " + token }, query: {} }, response);
    return { status: response.statusCode, data: await response.toResponse().json() as any };
  };
  const quote = await request("/resources/purchase-info", {}, "GET");
  assert.equal(quote.status, 200);
  const body = { resource: "stamina", expected_purchase_count: 0, period_key: quote.data.resource_purchase.period_key, request_id: "network-retry" };
  for (const resource of ["coins", "", null]) assert.equal((await request("/resources/buy", { ...body, resource })).status, 400);
  for (const count of [-1, "0", 0.5]) assert.equal((await request("/resources/buy", { ...body, expected_purchase_count: count })).status, 400);
  assert.equal((await request("/resources/buy", { ...body, request_id: "" })).status, 400);
  const persistedBefore = await storage.loadState("purchase");
  storage.fail = true;
  assert.equal((await request("/resources/buy", body)).status, 500);
  assert.deepEqual(await storage.loadState("purchase"), persistedBefore);
  const repeated = await Promise.all([request("/resources/buy", body), request("/resources/buy", body)]);
  assert.equal(repeated[0].status, 200);
  assert.equal(repeated[1].status, 200);
  assert.equal(repeated[0].data.spirit_stones, 900);
  assert.equal(repeated[1].data.spirit_stones, 900);
  assert.equal(repeated[1].data.stamina, saved.stamina + 100);
  const reloaded = await request("/resources/purchase-info", {}, "GET");
  assert.equal(reloaded.data.resource_purchase.stamina.cost, 200);
  assert.equal(reloaded.data.resource_purchase.qi.cost, 100);
  const next = { ...body, expected_purchase_count: 1, request_id: "next" };
  const race = await Promise.all([request("/resources/buy", next), request("/resources/buy", { ...next, request_id: "competing" })]);
  assert.equal(race[0].status, 200);
  assert.equal(race[1].status, 409);
  assert.equal((await storage.loadState("purchase"))!.spirit_stones, 700);
  console.log("RESOURCE_PURCHASE_SMOKE_OK pricing reset independent replay race rollback overflow persistence");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
