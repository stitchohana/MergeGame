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
  const service = engine.shopService;
  const state = engine.createInitialState();
  state.grid = [];
  state.spirit_stones = 10000;
  state.meridian_acupoints = [
    { item_ids: [1001, 1006, 27004, 1006], completed: false },
    { item_ids: [2006], completed: true },
  ] as any;
  const now = 1_800_000_000_000;
  const view = service.view(state, now);
  assert.equal(view.refresh_cost, 100);
  assert.equal(view.purchase_limit, 5);
  assert.equal(view.remaining_seconds, 14400);
  assert.equal(view.items.filter(item => item.id === 1006).length, 1);
  assert.ok(view.items.find(item => item.id === 1006)?.order_required);
  assert.equal(view.items.find(item => item.id === 1006)?.price, engine.getItemData(1006)!.value);
  assert.ok(!view.items.some(item => item.id === 2006));
  const recipe = gameConfigTables.recipes.recipes.find(recipe => recipe.result === 27004)!;
  for (const id of recipe.ingredients) assert.ok(view.items.find(item => item.id === id)?.order_required);
  assert.deepEqual(view.items.map(item => item.id).sort((a, b) => a - b),
    [...new Set([1001, 1006, ...recipe.ingredients])].sort((a, b) => a - b));
  assert.ok(view.items.every(item => item.order_required));
  assert.equal(view.items.find(item => item.id === 1001)!.price, 10);
  assert.ok(!view.items.some(item => [2001, 15101, 15201].includes(item.id)));
  assert.deepEqual(engine.buyItem(state, 2001, 5, 0, view.revision, now), { ok: false, reason: "not_in_shop" });
  assert.ok(view.items.every(item => engine.getItemData(item.id)!.type !== 4
    && !gameConfigTables.recipes.recipes.some(recipe => recipe.result === item.id)));
  for (let col = 0; col < 5; col++) assert.equal(engine.buyItem(state, 1001, col, 0, view.revision, now).ok, true);
  assert.equal(service.view(state, now).items.find(item => item.id === 1001)!.remaining, 0);
  const beforeSixth = structuredClone(state);
  assert.deepEqual(engine.buyItem(state, 1001, 5, 0, view.revision, now), { ok: false, reason: "purchase_limit_reached" });
  assert.deepEqual(state, beforeSixth);
  const reloaded = JSON.parse(JSON.stringify(state)) as GameState;
  assert.equal(service.view(reloaded, now).items.find(item => item.id === 1001)!.remaining, 0);
  const snapshot = structuredClone(state);
  snapshot.shop!.items.push({ id: 2001, price: 10, purchased: 2, order_required: false });
  const savedOffers = structuredClone(snapshot);
  assert.equal(service.ensure(snapshot, now + 1000), false);
  service.view(snapshot, now + 1000);
  assert.deepEqual(snapshot, savedOffers, "Reading an existing shop must not rewrite its saved offers");
  const noOrders = engine.createInitialState();
  noOrders.meridian_acupoints = [];
  assert.deepEqual(service.view(noOrders, now).items, []);
  noOrders.meridian_acupoints = [{ item_ids: [1001], completed: true }] as any;
  assert.equal(service.refresh(noOrders, noOrders.shop!.revision, now).ok, false);
  noOrders.spirit_stones = 100;
  assert.equal(service.refresh(noOrders, noOrders.shop!.revision, now).ok, true);
  assert.deepEqual(service.view(noOrders, now).items, []);
  state.meridian_acupoints = [{ item_ids: [1001, 2006], completed: false }] as any;
  assert.ok(!service.view(state, now + 1000).items.some(item => item.id === 2006));
  const balance = state.spirit_stones;
  assert.equal(service.refresh(state, view.revision, now + 1000).ok, true);
  assert.equal(state.spirit_stones, balance - 100);
  const refreshed = service.view(state, now + 1000);
  assert.equal(refreshed.items.find(item => item.id === 1001)!.remaining, 5);
  assert.ok(refreshed.items.find(item => item.id === 2006)?.order_required);
  assert.ok(!refreshed.items.some(item => item.id === 1006));
  assert.deepEqual(service.refresh(state, view.revision, now + 1000), { ok: false, reason: "shop_changed" });
  assert.equal(state.spirit_stones, balance - 100);
  assert.deepEqual(engine.buyItem(state, 1001, 5, 0, view.revision, now + 1000), { ok: false, reason: "shop_changed" });
  state.spirit_stones = 99;
  const poor = structuredClone(state);
  assert.deepEqual(service.refresh(state, refreshed.revision, now + 1000), { ok: false, reason: "insufficient_stones" });
  assert.deepEqual(state, poor);
  assert.equal(service.ensure(state, refreshed.next_refresh_at - 1), false);
  assert.equal(service.ensure(state, refreshed.next_refresh_at), true);
  assert.equal(state.spirit_stones, 99);
  assert.equal(state.shop!.next_refresh_at, refreshed.next_refresh_at + service.refreshInterval);
  const offlineUntil = state.shop!.next_refresh_at + service.refreshInterval * 3 + 500;
  assert.equal(service.view(state, offlineUntil).remaining_seconds, 14400);
  assert.ok(state.shop!.next_refresh_at > offlineUntil);
  const stable = structuredClone(state);
  assert.deepEqual(engine.buyItem(state, 1001, 0.5, 1, state.shop!.revision, offlineUntil), { ok: false, reason: "out_of_bounds" });
  assert.deepEqual(state, stable);

  const storage = new TestStorage();
  const saved = engine.createInitialState();
  saved.grid = [];
  saved.meridian_acupoints = [{ item_ids: [1001], completed: false }] as any;
  saved.spirit_stones = 10000;
  await storage.saveState("shop", saved);
  const router = createGameRouter(storage, engine, "shop-secret");
  const token = await signToken({ userId: "shop", deviceId: "shop-device" }, "shop-secret");
  const request = async (path: string, body: any = {}, method = "POST") => {
    const response = new WorkerResponse();
    await router.handle({ method, path, body, headers: { authorization: "Bearer " + token }, query: {} }, response);
    return { status: response.statusCode, data: await response.toResponse().json() as any };
  };
  const listing = await request("/shop/items", {}, "GET");
  assert.equal(listing.status, 200);
  assert.deepEqual(listing.data.items.map((item: any) => item.id), [1001]);
  assert.ok((await storage.loadState("shop"))!.shop);
  const revision = listing.data.revision;
  for (let col = 0; col < 4; col++) assert.equal((await request("/shop/buy", {
    item_id: 1001, target_col: col, target_row: 0, shop_revision: revision,
  })).status, 200);
  const race = await Promise.all([4, 5].map(col => request("/shop/buy", {
    item_id: 1001, target_col: col, target_row: 0, shop_revision: revision,
  })));
  assert.deepEqual(race.map(result => result.status).sort(), [200, 400]);
  assert.equal(race.find(result => result.status === 200)!.data.shop.items.find((item: any) => item.id === 1001).remaining, 0);
  const persisted = await storage.loadState("shop");
  storage.fail = true;
  assert.equal((await request("/shop/refresh", { shop_revision: revision })).status, 500);
  assert.deepEqual(await storage.loadState("shop"), persisted);
  const doubleRefresh = await Promise.all([1, 2].map(() => request("/shop/refresh", { shop_revision: revision })));
  assert.deepEqual(doubleRefresh.map(result => result.status).sort(), [200, 409]);
  assert.equal((await storage.loadState("shop"))!.spirit_stones, persisted!.spirit_stones - 100);
  assert.equal((await request("/shop/items", {}, "GET")).data.items.find((item: any) => item.id === 1001).remaining, 5);
  const expired = (await storage.loadState("shop"))!;
  expired.shop!.next_refresh_at = Date.now() - 1;
  expired.shop!.items[0].purchased = 5;
  await storage.saveState("shop", expired);
  const auto = await request("/shop/items", {}, "GET");
  assert.equal(auto.status, 200);
  assert.ok(auto.data.items.every((item: any) => item.remaining === 5));
  assert.equal((await storage.loadState("shop"))!.spirit_stones, expired.spirit_stones);
  for (const body of [{}, { shop_revision: "1" }, { shop_revision: 1.5 }]) {
    assert.equal((await request("/shop/refresh", body)).status, 400);
  }
  console.log("SHOP_REFRESH_SMOKE_OK order_only snapshot_preserved empty_orders limit recipes auto manual persistence race rollback");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
