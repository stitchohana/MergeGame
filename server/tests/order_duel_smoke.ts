import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { JsonFileStorage } from "../src/storage/json_file";
import { D1Storage } from "../src/storage/d1";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";
import type { GameState, IStorage } from "../src/storage/interface";

async function main() {
  // Production balance: bot fallback at one second and a slower five-point cadence.
  const balancedEngine = new GameEngine(gameConfigTables);
  const balanced = balancedEngine.orderDuelService;
  const balancedStore = new MemoryStorage();
  const beginner = balancedEngine.createInitialState();
  beginner.cultivation.current_level = 2;
  const balancedApply = (r: any) => balancedEngine.applyRewards(beginner, r);
  await balancedStore.saveState("beginner", beginner);
  assert.equal((await balanced.start(balancedStore, "beginner", beginner, 0, balancedApply, 1000)).status, "matching");
  assert.equal((await balanced.refresh(balancedStore, "beginner", beginner, balancedApply, 1999)).status, "matching");
  let balancedView = await balanced.refresh(balancedStore, "beginner", beginner, balancedApply, 2000);
  assert.equal(balancedView.status, "playing");
  assert.equal(balancedView.opponent.bot, true);
  assert.equal(balancedView.opponent.points, 0);
  const balancedRegistry = (await balancedStore.loadOrderDuel(balanced.eventId))!;
  const botMatch = balancedRegistry.matches[beginner.order_duel_progress!.match_id!];
  assert.ok(botMatch.bot_interval_ms >= 60000 && botMatch.bot_interval_ms <= 90000);
  balancedView = await balanced.refresh(balancedStore, "beginner", beginner, balancedApply, 61999);
  assert.equal(balancedView.opponent.points, 0);
  balancedView = await balanced.refresh(balancedStore, "beginner", beginner, balancedApply, 2000 + botMatch.bot_interval_ms);
  assert.equal(balancedView.opponent.points, 5);
  // Five minutes to complete the player's orders must still leave time to win.
  balanced.awardOrderPoints(beginner, 1000, 302000);
  await balancedStore.saveState("beginner", beginner);
  balancedView = await balanced.refresh(balancedStore, "beginner", beginner, balancedApply, 302000);
  assert.equal(balancedView.status, "matching");
  assert.equal(balancedView.last_result.won, true);
  assert.ok(balancedView.last_result.opponent_points <= 25);

  // Keep the original deterministic fixture for settlement and failure recovery cases.
  const data = structuredClone(gameConfigTables.orderDuel);
  data.settings[0].matchmaking_seconds = 10;
  data.settings[0].bot_order_value = 100;
  data.settings[0].bot_min_seconds = data.settings[0].bot_max_seconds = 30;
  const engine = new GameEngine({ ...gameConfigTables, orderDuel: data });
  const service = engine.orderDuelService;
  const state = () => { const s = engine.createInitialState(); s.cultivation.current_level = 2; return s; };
  const apply = (s: GameState) => (r: any) => engine.applyRewards(s, r);
  const refresh = (storage: IStorage, id: string, s: GameState, now: number) => service.refresh(storage, id, s, apply(s), now);
  assert.equal(service.orderPoints(0), 0);
  assert.equal(service.orderPoints(NaN), 0);
  assert.equal(service.orderPoints(1), 1);
  assert.equal(service.orderPoints(116), 11);
  assert.equal(service.tiers.length, 10);
  for (const mutate of [
    (d: any) => d.rewards.pop(),
    (d: any) => d.rewards[1].required_points = d.rewards[0].required_points,
    (d: any) => d.settings[0].bot_min_seconds = 0,
    (d: any) => d.settings[0].target_points = 1.5,
  ]) {
    const broken = structuredClone(data); mutate(broken);
    assert.throws(() => new GameEngine({ ...gameConfigTables, orderDuel: broken }), /invalid_order_duel/);
  }

  const storage = new MemoryStorage();
  const a = state(), b = state(), outsider = state();
  await storage.saveState("a", a); await storage.saveState("b", b); await storage.saveState("outsider", outsider);
  service.awardOrderPoints(a, 1000, 1000);
  assert.equal(service.progress(a).order_points, 0); // No points while resting.
  let view = await service.start(storage, "a", a, 0, apply(a), 1000);
  assert.equal(view.status, "matching");
  assert.equal((await service.start(storage, "a", a, 0, apply(a), 1001)).error, "state_conflict");
  view = await service.start(storage, "b", b, 0, apply(b), 2000);
  assert.equal(view.status, "playing"); assert.equal(view.opponent.bot, false);
  await refresh(storage, "a", a, 2000);
  assert.equal(a.order_duel_progress!.match_id, b.order_duel_progress!.match_id);
  assert.equal((await storage.loadOrderDuel(service.eventId))!.tickets.outsider, undefined);
  // Both durable orders reach target; earlier completion wins even when the later finisher polls first.
  service.awardOrderPoints(a, 1000, 3000); await storage.saveState("a", a);
  service.awardOrderPoints(b, 1000, 3001); await storage.saveState("b", b);
  const bBefore = b.stamina, aBefore = a.stamina;
  view = await refresh(storage, "b", b, 4000);
  assert.equal(view.status, "lost"); assert.equal(b.stamina, bBefore);
  view = await refresh(storage, "a", a, 4000);
  assert.equal(view.status, "matching"); assert.equal(view.victory_points, 10);
  assert.equal(a.stamina, aBefore + 30); assert.ok(a.stamina > a.max_stamina);
  await refresh(storage, "a", a, 4001); assert.equal(a.stamina, aBefore + 30);
  const round = b.order_duel_progress!.round;
  assert.equal((await service.rest(storage, "b", b, round)).status, "resting");
  service.awardOrderPoints(b, 1000, 4002); assert.equal(b.order_duel_progress!.order_points, 0);
  assert.equal((await service.start(storage, "b", b, round, apply(b), 5000)).status, "playing");
  await refresh(storage, "a", a, 5000);
  assert.equal(a.order_duel_progress!.order_points, 0); // No overrun from the winning order.
  // Claims are independent, no point consumption, and exactly once.
  assert.equal((await service.claim(storage, "a", a, 2, apply(a))).error, "insufficient_points");
  await service.claim(storage, "a", a, 1, apply(a));
  const balance = a.stamina;
  await service.claim(storage, "a", a, 1, apply(a));
  assert.equal(a.stamina, balance); assert.equal(a.order_duel_progress!.victory_points, 10);
  a.order_duel_progress!.victory_points = 100; await storage.saveState("a", a);
  await service.claim(storage, "a", a, 10, apply(a));
  assert.deepEqual(a.order_duel_progress!.claimed_tiers, [1, 10]);

  // Activity end freezes bot time, settles durable wins, permits unlocked claims, and never rematches.
  const timedActivities = structuredClone(gameConfigTables.activities);
  const timedActivity = timedActivities.activities.find(a => a.widget === "OrderDuel")!;
  Object.assign(timedActivity, { start_time: new Date(1000).toISOString(), end_time: new Date(100000).toISOString() });
  const timedEngine = new GameEngine({ ...gameConfigTables, activities: timedActivities, orderDuel: data });
  const timed = timedEngine.orderDuelService, timedStore = new MemoryStorage(), t = state();
  const timedApply = (rw: any) => timedEngine.applyRewards(t, rw);
  await timedStore.saveState("t", t);
  assert.equal((await timed.start(timedStore, "t", t, 0, timedApply, 999)).error, "activity_inactive");
  await timed.start(timedStore, "t", t, 0, timedApply, 1000);
  await timed.refresh(timedStore, "t", t, timedApply, 11000);
  timed.awardOrderPoints(t, 1000, 12000); await timedStore.saveState("t", t);
  view = await timed.refresh(timedStore, "t", t, timedApply, 100001);
  assert.equal(view.status, "resting"); assert.equal(view.victory_points, 10);
  assert.equal(view.active, false);
  await timed.claim(timedStore, "t", t, 1, timedApply);
  assert.deepEqual(t.order_duel_progress!.claimed_tiers, [1]);
  assert.equal((await timed.start(timedStore, "t", t, view.round, timedApply, 100001)).error, "activity_inactive");
  const cutoffState = state(); await timedStore.saveState("cutoff", cutoffState);
  const cutoffApply = (rw: any) => timedEngine.applyRewards(cutoffState, rw);
  await timed.start(timedStore, "cutoff", cutoffState, 0, cutoffApply, 1000);
  await timed.refresh(timedStore, "cutoff", cutoffState, cutoffApply, 11000);
  view = await timed.refresh(timedStore, "cutoff", cutoffState, cutoffApply, 9999999);
  assert.equal(view.status, "resting"); assert.equal(view.last_result, undefined);
  assert.equal((await timedStore.loadOrderDuel(timed.eventId))!.tickets.cutoff, undefined);

  // Bot clock survives restarts and beats an order that completes after its target time.
  const solo = state(); await storage.saveState("solo", solo);
  await service.start(storage, "solo", solo, 0, apply(solo), 10000);
  view = await refresh(storage, "solo", solo, 20000);
  assert.equal(view.opponent.bot, true); assert.equal(view.opponent.points, 0);
  view = await refresh(storage, "solo", solo, 50000); assert.equal(view.opponent.points, 10);
  view = await refresh(storage, "solo", solo, 50000); assert.equal(view.opponent.points, 10);
  service.awardOrderPoints(solo, 1000, 320001); await storage.saveState("solo", solo);
  view = await new GameEngine({ ...gameConfigTables, orderDuel: data }).orderDuelService.refresh(storage, "solo", solo, apply(solo), 320001);
  assert.equal(view.status, "lost"); assert.equal(view.last_result.opponent_points, 100);

  // A failed payout is recoverable; a durable payout followed by failed acknowledgement never duplicates it.
  class FailureStorage extends MemoryStorage {
    failState = false; failRegistry = false;
    override async saveState(id: string, s: GameState) {
      if (this.failState && s.order_duel_progress?.last_result?.won) { this.failState = false; throw new Error("payout_failed"); }
      return super.saveState(id, s);
    }
    override async saveOrderDuel(r: any) {
      if (this.failRegistry && Object.values(r.tickets).some((t: any) => !t.match_id)) { this.failRegistry = false; throw new Error("ack_failed"); }
      return super.saveOrderDuel(r);
    }
  }
  const failure = new FailureStorage(); let f = state(); await failure.saveState("f", f);
  await service.start(failure, "f", f, 0, apply(f), 1000); await refresh(failure, "f", f, 11000);
  service.awardOrderPoints(f, 1000, 12000); await failure.saveState("f", f);
  const original = f.stamina;
  failure.failState = true;
  await assert.rejects(refresh(failure, "f", f, 12000), /payout_failed/);
  f = (await failure.loadState("f"))!; assert.equal(f.stamina, original); assert.equal(f.order_duel_progress!.last_result, undefined);
  failure.failRegistry = true;
  await assert.rejects(refresh(failure, "f", f, 12001), /ack_failed/);
  f = (await failure.loadState("f"))!; assert.equal(f.stamina, original + 30);
  await refresh(failure, "f", f, 12002); assert.equal(f.stamina, original + 30);
  const copy = structuredClone(f); await failure.saveState("f", f);
  await assert.rejects(failure.saveState("f", copy), /state_conflict/);

  // Persistent adapters use the same CAS contract and survive recreation.
  const dir = mkdtempSync(join(tmpdir(), "order-duel-"));
  try {
    const files = new JsonFileStorage(dir), s = state(); await files.saveState("file", s);
    await service.start(files, "file", s, 0, apply(s), 1000);
    const reopened = new JsonFileStorage(dir);
    const r1 = (await files.loadOrderDuel(service.eventId))!, r2 = (await reopened.loadOrderDuel(service.eventId))!;
    assert.ok(r1.tickets.file); await files.saveOrderDuel(r1);
    await assert.rejects(reopened.saveOrderDuel(r2), /state_conflict/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync("schema.sql", "utf8"));
  db.exec("INSERT INTO users (user_id, device_id, created_at) VALUES ('l', 'l', 0), ('r', 'r', 0)");
  const adapter = { prepare(sql: string) { return { bind(...args: any[]) { return {
    async first() { return db.prepare(sql).get(...args) ?? null; },
    async run() { return { meta: { changes: Number(db.prepare(sql).run(...args).changes) } }; },
  }; } }; } };
  const left = new D1Storage(adapter as any), right = new D1Storage(adapter as any);
  const l = state(), r = state(); await left.saveState("l", l); await right.saveState("r", r);
  await Promise.all([service.start(left, "l", l, 0, apply(l), 1000), service.start(right, "r", r, 0, apply(r), 1000)]);
  assert.equal(Object.keys((await left.loadOrderDuel(service.eventId))!.matches).length, 1);
  const d1a = (await left.loadOrderDuel(service.eventId))!, d1b = (await right.loadOrderDuel(service.eventId))!;
  await left.saveOrderDuel(d1a); await assert.rejects(right.saveOrderDuel(d1b), /state_conflict/); db.close();

  // Real authenticated order route uses actual consumed values and rejects replay.
  const realNow = Date.now; let now = 1000000; Date.now = () => now;
  try {
    class OrderFailureStorage extends MemoryStorage {
      failOrder = false;
      override async saveState(id: string, value: GameState) {
        if (this.failOrder && (value.order_duel_progress?.order_points ?? 0) > 0) {
          this.failOrder = false; throw new Error("order_save_failed");
        }
        return super.saveState(id, value);
      }
    }
    const routeStore = new OrderFailureStorage(), s = state(); await routeStore.saveState("route", s);
    const router = createGameRouter(routeStore, engine, "duel-test");
    const token = await signToken({ userId: "route", deviceId: "duel" }, "duel-test");
    const request = async (path: string, body = {}, method = "POST") => {
      const res = new WorkerResponse();
      await router.handle({ method, path, body, headers: { authorization: "Bearer " + token }, query: {} }, res);
      return { status: res.statusCode, data: await res.toResponse().json() as any };
    };
    assert.equal((await request("/order_duel/start", { expected_round: 0 })).data.order_duel.status, "matching");
    now += 10000;
    assert.equal((await request("/order_duel", {}, "GET")).data.order_duel.status, "playing");
    const order = (await routeStore.loadState("route"))!;
    order.grid.push({ uid: 90001, id: 5004, col: 6, row: 8 }, { uid: 90002, id: 5004, col: 5, row: 8 });
    order.meridian_acupoints = [{ item_ids: [5004, 5004], name: "test", completed: false, total_value: 999999 } as any];
    await routeStore.saveState("route", order);
    routeStore.failOrder = true;
    assert.equal((await request("/meridian/complete", { index: 0, item_ids: [5004, 5004], request_id: "duel-order" })).status, 500);
    const failedOrder = (await routeStore.loadState("route"))!;
    assert.equal(failedOrder.order_duel_progress!.order_points, 0);
    assert.equal(failedOrder.grid.filter(item => [90001, 90002].includes(item.uid!)).length, 2);
    const failedRegistry = (await routeStore.loadOrderDuel(service.eventId))!;
    assert.equal(failedRegistry.matches[failedOrder.order_duel_progress!.match_id!].points.route, 0);
    const done = await request("/meridian/complete", { index: 0, item_ids: [5004, 5004], request_id: "duel-order" });
    assert.equal(done.status, 200); assert.equal(done.data.order_duel.my_points, 4);
    assert.equal((await request("/meridian/complete", { index: 0, item_ids: [5004, 5004], request_id: "duel-order" })).status, 400);
    assert.equal((await request("/state", {}, "GET")).data.order_duel.my_points, 4);
    assert.equal((await request("/order_duel/claim", { tier: -1 })).status, 400);
    const locked = state(); locked.cultivation.current_level = 1; await routeStore.saveState("locked", locked);
    assert.equal((await refresh(routeStore, "locked", locked, now)).status, "locked");
  } finally { Date.now = realNow; }

  console.log("ORDER_DUEL_SMOKE_OK");
}
main().catch(e => { console.error(e); process.exitCode = 1; });
