import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { QuestType } from "../src/storage/interface";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

async function main() {
  const tables = structuredClone(gameConfigTables);
  const now = Date.now();
  for (const activity of tables.activities.activities) {
    activity.enabled = true;
    activity.start_time = new Date(now - 86400000).toISOString();
    activity.end_time = new Date(now + 86400000).toISOString();
  }
  const engine = new GameEngine(tables);
  const state = engine.createInitialState();
  const storage = new MemoryStorage();
  const supplyOrder: any = { item_ids: [5001, 5001], completed: false };
  state.meridian_acupoints = [supplyOrder];
  const before = structuredClone(state);
  for (const q of tables.quests.quests) engine.questEngine.incrementQuestProgress(state, q.type, 999, engine);
  engine.activityEngine.recordOrderSupplyAction(state, 5001);
  engine.activityEngine.initProgress(state);
  engine.activityEngine.checkAndReset(state, engine.questResetHour);
  assert.equal(engine.questEngine.initQuestProgress(state), false);
  assert.equal(engine.questEngine.checkAndResetQuests(state, engine.questResetHour), false);
  assert.equal(engine.battlePassService.awardOrderPoints(state, 200, "novice"), false);
  engine.cardCollectionService.awardSource(state, "order", 0, 200);
  engine.cardCollectionService.awardPack(state, 1, 1);
  assert.equal(await engine.stairClimbService.enroll(storage, "novice", state), false);
  assert.deepEqual(state, before, "novice actions must not initialize or accumulate activity/task data");
  const locked = { ok: false, reason: "activity_locked" };
  assert.deepEqual(engine.questEngine.claimQuestReward(state, 1001, engine), locked);
  assert.deepEqual(engine.activityEngine.claimOrderSupply(state, 7, 0, engine), locked);
  assert.deepEqual(engine.battlePassService.unlock(state, 4), locked);
  assert.deepEqual(engine.battlePassService.claim(state, 4, 1, "free", r => engine.applyRewards(state, r)), locked);
  assert.deepEqual(engine.cardCollectionService.openPending(state, 1, 1, false, "open", 0), locked);
  assert.deepEqual(engine.cardCollectionService.exchange(state, 1, "exchange", 0), locked);
  assert.equal(await engine.stairClimbService.settlePlayer(storage, "novice", state, () => assert.fail()), false);
  assert.equal(engine.battlePassService.settleExpired(state, () => { assert.fail(); }), false);
  assert.equal((await engine.stairClimbService.view(storage, "novice", state)).status, "locked");
  const applied = engine.applyRewards(state, { tokens: [{ token: 1, amount: 3 }, { token: 2, amount: 4 }, { token: 5, amount: 100 }], items: [{ id: 1701, count: 1 }, { id: 5001, count: 1 }] });
  assert.deepEqual(applied.tokens, [{ token: 1, amount: 3 }, { token: 2, amount: 4 }]);
  assert.deepEqual(applied.items, [{ id: 5001, count: 1 }]);
  assert.equal(state.pending_rewards.some(r => r.kind === "card_pack"), false);

  // Existing onboarding orders still award base resources, but no pack or score.
  state.cultivation.current_qi = 0;
  state.meridian_acupoints = [{ item_ids: [5001], name: "novice order", completed: false, total_value: 200, fixed_order_rewards: true, rewards: { tokens: [{ token: 2, amount: 7 }, { token: 5, amount: 100 }], items: [{ id: 1701, count: 1 }] } } as any];
  state.grid = [{ id: 5001, uid: ++state.uid_counter, col: 0, row: 0 }];
  const order: any = engine.completeMeridianAcupoint(state, 0, [5001], "novice-order");
  assert.equal(order.ok, true);
  assert.equal(order.qi_gained, 7);
  assert.deepEqual(order.rewards, { tokens: [{ token: 2, amount: 7 }], items: [] });
  assert.deepEqual(state.battle_pass_progress ?? {}, {});
  assert.deepEqual(state.stair_climb_progress ?? {}, {});

  await storage.saveState("novice", state);
  const router = createGameRouter(storage, engine, "novice-test-secret");
  const token = await signToken({ userId: "novice", deviceId: "test" }, "novice-test-secret");
  const readState = async () => {
    const response = new WorkerResponse();
    await router.handle({ method: "GET", path: "/state", body: {}, query: {}, headers: { authorization: "Bearer " + token } }, response);
    assert.equal(response.statusCode, 200);
    return await response.toResponse().json() as any;
  };
  const novice = await readState();
  assert.deepEqual(novice.activity_defs, []);
  assert.deepEqual(novice.quest_defs, []);
  assert.deepEqual(novice.activity_progress, {});
  assert.deepEqual(novice.quest_progress, {});
  assert.equal(novice.activities_unlocked, false);

  const unlocked = (await storage.loadState("novice"))!;
  unlocked.cultivation.current_level = 2;
  await storage.saveState("novice", unlocked);
  const normal = await readState();
  assert.equal(normal.activities_unlocked, true);
  assert.ok(normal.activity_defs.length > 0 && normal.quest_defs.length > 0);
  const active = (await storage.loadState("novice"))!;
  assert.ok(Object.values(active.quest_progress!).every(q => q.current_count === 0), "no backfill at unlock");
  assert.equal(active.battle_pass_progress![4].points, 0);
  assert.equal(engine.battlePassService.awardOrderPoints(active, 200, "after-unlock"), true);
  assert.equal(active.battle_pass_progress![4].points, 20);
  const quest = tables.quests.quests.find(q => q.type === QuestType.MERGE)!;
  engine.questEngine.incrementQuestProgress(active, QuestType.MERGE, 1, engine);
  assert.equal(active.quest_progress![quest.id].current_count, 1);
  active.meridian_acupoints = [{ item_ids: [5001, 5001], name: "supply", completed: false }];
  engine.activityEngine.recordOrderSupplyAction(active, 5001);
  assert.equal(active.activity_progress![7].current_count, 1);
  engine.cardCollectionService.awardSource(active, "order", 0, 200);
  assert.ok(active.pending_rewards.some(r => r.kind === "card_pack"));
  console.log("NOVICE_ACTIVITY_ACCESS_SMOKE_OK");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
