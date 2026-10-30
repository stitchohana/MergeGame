import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { StairClimbService } from "../src/engine/stair_climb";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { JsonFileStorage } from "../src/storage/json_file";
import { D1Storage } from "../src/storage/d1";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";
import type { GameState } from "../src/storage/interface";

async function main() {
  const activities: any = structuredClone(gameConfigTables.activities);
  const activity = activities.activities.find((a: any) => a.widget === "StairClimb");
  const start = Date.parse(activity.start_time), end = Date.parse(activity.end_time);
  assert.equal(end - start, 3 * 86400000);
  assert.equal(gameConfigTables.stairClimb.settings[0].order_points_ratio, 0.1);
  assert.equal("config" in activity, false);
  const engine = new GameEngine({ ...gameConfigTables, activities });
  const service = engine.stairClimbService;
  assert.equal(service.isActive(start - 1), false);
  assert.equal(service.isActive(start), true);
  assert.equal(service.isActive(end), false);
  assert.equal(service.orderPoints(100), 10);
  assert.equal(service.orderPoints(250), 25);
  assert.equal(service.orderPoints(116), 11);
  assert.equal(service.orderPoints(0), 0);
  assert.equal(service.orderPoints(NaN), 0);
  const config2 = structuredClone(gameConfigTables.stairClimb);
  config2.settings[0].order_points_ratio = 0.25;
  assert.equal(new GameEngine({ ...gameConfigTables, activities, stairClimb: config2 }).stairClimbService.orderPoints(100), 25);
  for (let rank = 1; rank < 10; rank++) {
    assert.ok(service.reward(rank).stamina > service.reward(rank + 1).stamina);
    assert.ok(service.reward(rank).spirit_stones > service.reward(rank + 1).spirit_stones);
  }
  for (let rank = 11; rank <= 20; rank++) assert.deepEqual(service.reward(rank), service.reward(11));

  const storage = new MemoryStorage();
  const quiet = console.log; console.log = () => {};
  // Activity participants must have reached the activity unlock level.
  const createParticipant = () => {
    const state = engine.createInitialState();
    state.cultivation.current_level = 2;
    return state;
  };
  for (let i = 0; i < 25; i++) { const s = createParticipant(); await storage.saveState('same-' + i, s); }
  const other = createParticipant(); other.cultivation.current_level = 3; await storage.saveState('other', other);
  console.log = quiet;
  const p0 = (await storage.loadState('same-0'))!;
  const p1 = (await storage.loadState('same-1'))!;
  await Promise.all([service.enroll(storage, 'same-0', p0, start), service.enroll(storage, 'same-1', p1, start)]);
  await storage.saveState('same-0', p0); await storage.saveState('same-1', p1);
  let registry = (await storage.loadStairClimb(service.eventId))!;
  for (const g of registry.groups) assert.equal(g.members.length, 20);
  assert.equal(registry.groups[0].members.filter(m => m.bot).length, 0);
  const realIds = registry.groups.flatMap(g => g.members.filter(m => !m.bot).map(m => m.id));
  assert.equal(new Set(realIds).size, realIds.length);
  assert.ok(!realIds.includes('other'));
  const offlineId = registry.groups[0].members.find(m => m.id !== 'same-0' && m.id !== 'same-1')!.id;
  const offline = (await storage.loadState(offlineId))!;
  await service.enroll(storage, 'other', other, start); await storage.saveState('other', other);
  const otherGroup = (await storage.loadStairClimb(service.eventId))!.groups.find(g => g.realm === 3)!;
  assert.equal(otherGroup.members.filter(m => m.bot).length, 19);
  const before = await service.rows(storage, otherGroup, start);
  const after = await service.rows(storage, otherGroup, start + 7200000);
  assert.equal(before.filter(r => r.bot).every(r => r.points === 0), true);
  assert.ok(after.filter(r => r.bot).every(r => r.points > 0));
  assert.deepEqual(await service.rows(storage, otherGroup, end), await service.rows(storage, otherGroup, end + 86400000));
  const groupId = service.score(p0)!.group_id;
  p0.cultivation.current_level = 8;
  assert.equal(await service.enroll(storage, 'same-0', p0, start + 1), false);
  assert.equal(service.score(p0)!.group_id, groupId);
  assert.equal(service.awardOrderPoints(p0, 100, start), true);
  assert.equal(service.awardOrderPoints(p0, 250, start + 1), true);
  assert.equal(service.score(p0)!.points, 35);
  assert.equal(service.awardOrderPoints(p0, 100, end), false);
  await storage.saveState('same-0', p0);
  const p0View = await service.view(storage, 'same-0', p0, start + 2);
  assert.equal(p0View.my_rank, 1);
  assert.equal(p0View.rows.filter(r => r.is_self).length, 1);
  assert.equal(p0View.my_points, 35);
  // Earlier score wins ties, followed by immutable randomized member order.
  assert.equal(service.awardOrderPoints(p1, 350, start + 3), true);
  await storage.saveState('same-1', p1);
  const liveRows = await service.rows(storage, registry.groups.find(g => g.id === groupId)!, start + 4);
  if (service.score(p1)!.group_id === groupId) assert.ok(liveRows.find(r => r.points === 35)!.reached_at === start + 1);
  const apply = (s: GameState, r: any) => engine.applyRewards(s, r);
  assert.equal(await service.settlePlayer(storage, 'same-0', p0, r => apply(p0, r), end - 1), false);
  const balance = { stamina: p0.stamina, stones: p0.spirit_stones };
  assert.equal(await service.settlePlayer(storage, 'same-0', p0, r => apply(p0, r), end + 30000), true);
  await storage.saveState('same-0', p0);
  assert.equal(p0.stamina, balance.stamina + service.reward(service.score(p0)!.settlement!.rank).stamina);
  assert.ok(p0.stamina > p0.max_stamina); // Never discard stamina above natural regeneration cap.
  assert.equal(await service.settlePlayer(storage, 'same-0', p0, r => apply(p0, r), end + 60000), false);
  const restarted = new StairClimbService(engine.activityEngine.getActivities(), engine.cultivationStages);
  for (let i = 0; i < 15; i++) await restarted.settleBatch(storage, apply, end + 60000);
  const paidOffline = (await storage.loadState(offlineId))!;
  assert.ok(restarted.score(paidOffline)?.settlement); // Selected offline players receive ordinary prize.
  assert.equal(paidOffline.spirit_stones - offline.spirit_stones, restarted.score(paidOffline)!.settlement!.reward.spirit_stones);
  const final = await restarted.view(storage, 'same-0', p0, end + 60000);
  assert.equal(final.status, 'ended');

  // Persistent JSON storage survives a new instance; stale writes are rejected.
  const dir = mkdtempSync(join(tmpdir(), 'stair-climb-'));
  try {
    const files = new JsonFileStorage(dir); const u = await files.createUser('test-device');
    const state = createParticipant(); await files.saveState(u.userId, state);
    await service.enroll(files, u.userId, state, start); await files.saveState(u.userId, state);
    const freshFiles = new JsonFileStorage(dir);
    assert.equal((await freshFiles.loadStairClimb(service.eventId))!.groups.length, 1);
    const a = (await files.loadStairClimb(service.eventId))!, b = (await freshFiles.loadStairClimb(service.eventId))!;
    await files.saveStairClimb(a); await assert.rejects(freshFiles.saveStairClimb(b), /state_conflict/);
  } finally { rmSync(dir, { recursive: true, force: true }); }

  // Run actual D1 SQL against SQLite and independent storage instances.
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync('schema.sql', 'utf8'));
  db.exec("INSERT INTO users (user_id, device_id, created_at) VALUES ('left', 'left', '2026-10-28'), ('right', 'right', '2026-10-28')");
  const adapter = { prepare(sql: string) { return { bind(...args: any[]) { return {
    async first() { return db.prepare(sql).get(...args) ?? null; },
    async all() { return { results: db.prepare(sql).all(...args) }; },
    async run() { return { meta: { changes: Number(db.prepare(sql).run(...args).changes) } }; },
  }; } }; } };
  const left = new D1Storage(adapter as any), right = new D1Storage(adapter as any);
  const l = createParticipant(), r = createParticipant();
  await left.saveState('left', l); await right.saveState('right', r);
  await Promise.all([service.enroll(left, 'left', l, start), service.enroll(right, 'right', r, start)]);
  assert.equal((await left.loadStairClimb(service.eventId))!.groups.length, 1);
  assert.equal(service.score(l)!.group_id, service.score(r)!.group_id);
  await left.saveState('left', l); await right.saveState('right', r);
  const a = (await left.loadStairClimb(service.eventId))!, b = (await right.loadStairClimb(service.eventId))!;
  await left.saveStairClimb(a); await assert.rejects(right.saveStairClimb(b), /state_conflict/);
  const l1 = (await left.loadState('left'))!, l2 = (await right.loadState('left'))!;
  await Promise.all([service.settlePlayer(left, 'left', l1, rw => apply(l1, rw), end + 30000), service.settlePlayer(right, 'left', l2, rw => apply(l2, rw), end + 30000)]);
  await left.saveState('left', l1); await assert.rejects(right.saveState('left', l2), /state_conflict/);
  assert.equal((await right.loadState('left'))!.stamina, l.stamina + service.score(l1)!.settlement!.reward.stamina);
  db.close();

  // Real authenticated order route: reject invalid/replayed orders; failed persistence awards nothing.
  const realNow = Date.now;
  Date.now = () => start + 1000;
  try {
    class FailureStorage extends MemoryStorage {
      fail = false;
      failSettlement = false;
      failedPoints = 0;
      failedCompleted = false;
      override async saveState(id: string, s: GameState) {
        const score = routeEngine.stairClimbService.score(s);
        if (this.fail && (score?.points ?? 0) > 0) {
          this.fail = false; this.failedPoints = score!.points;
          this.failedCompleted = s.card_collection_order_requests?.includes('value-order') ?? false;
          throw new Error('save_failed_after_scoring');
        }
        if (this.failSettlement && score?.settlement) { this.failSettlement = false; throw new Error('settlement_save_failed'); }
        await super.saveState(id, s);
      }
    }
    const routeStorage = new FailureStorage();
    const routeEngine = new GameEngine({ ...gameConfigTables, activities });
    const ready = routeEngine.createInitialState(); ready.cultivation.current_level = 2; await routeStorage.saveState('route', ready);
    const router = createGameRouter(routeStorage, routeEngine, 'stair-test');
    const token = await signToken({ userId: 'route', deviceId: 'test' }, 'stair-test');
    async function request(path: string, body: any = {}, method = 'POST') {
      const res = new WorkerResponse();
      await router.handle({ method, path, body, headers: { authorization: 'Bearer ' + token }, query: {} }, res);
      return { status: res.statusCode, data: await res.toResponse().json() as any };
    }
    assert.equal((await request('/stair_climb', {}, 'GET')).data.stair_climb.rows.length, 20);
    const order = (await routeStorage.loadState('route'))!;
    order.grid.push({ uid: 9999, id: 5004, col: 6, row: 8 }, { uid: 9998, id: 5004, col: 5, row: 8 });
    order.meridian_acupoints = [{ item_ids: [5004, 5004], name: 'test', completed: false, total_value: 999999 } as any];
    await routeStorage.saveState('route', order);
    routeStorage.fail = true;
    assert.equal((await request('/meridian/complete', { index: 0, item_ids: [5004, 5004], request_id: 'value-order' })).status, 500);
    assert.equal(routeStorage.failedPoints, 4);
    assert.equal(routeStorage.failedCompleted, true);
    const failedOrder = (await routeStorage.loadState('route'))!;
    assert.equal(routeEngine.stairClimbService.score(failedOrder)!.points, 0);
    assert.equal(failedOrder.meridian_acupoints?.[0]?.completed, false);
    assert.equal(failedOrder.grid.filter(i => i.uid === 9999 || i.uid === 9998).length, 2);
    assert.equal(failedOrder.card_collection_order_requests?.includes('value-order') ?? false, false);
    const done = await request('/meridian/complete', { index: 0, item_ids: [5004, 5004], request_id: 'value-order' });
    assert.equal(done.status, 200);
    assert.equal(done.data.stair_climb_progress[service.eventId].points, 4); // Actual values 20 + 20, never stale order metadata.
    assert.equal((await request('/meridian/complete', { index: 0, item_ids: [5004, 5004], request_id: 'value-order' })).status, 400);
    assert.equal(routeEngine.stairClimbService.score((await routeStorage.loadState('route'))!)!.points, 4);
    assert.equal((await request('/meridian/complete', { index: 99, item_ids: [5004] })).status, 400);
    Date.now = () => end + 30000;
    const beforePayout = (await routeStorage.loadState('route'))!;
    routeStorage.failSettlement = true;
    assert.equal((await request('/stair_climb', {}, 'GET')).status, 500);
    const failedPayout = (await routeStorage.loadState('route'))!;
    assert.equal(routeEngine.stairClimbService.score(failedPayout)!.settlement, undefined);
    assert.equal(failedPayout.spirit_stones, beforePayout.spirit_stones);
    assert.equal(failedPayout.stamina, beforePayout.stamina);
    const ended = await request('/stair_climb', {}, 'GET');
    assert.equal(ended.data.stair_climb.status, 'ended');
    assert.ok(ended.data.stair_climb.settlement);
    assert.equal(ended.data.spirit_stones - beforePayout.spirit_stones, ended.data.stair_climb.settlement.reward.spirit_stones);
    assert.deepEqual(ended.data.stair_climb_progress[service.eventId].settlement, ended.data.stair_climb.settlement);
    const again = await request('/stair_climb', {}, 'GET');
    assert.equal(again.data.stamina, ended.data.stamina);
  } finally { Date.now = realNow; }
  console.log('stair_climb_smoke: ok');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
