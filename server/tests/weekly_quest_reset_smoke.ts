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
  const realNow = Date.now;
  const realLog = console.log;
  let now = Date.parse("2026-10-19T04:59:59.999+08:00");
  Date.now = () => now;
  console.log = () => {};
  try {
    const tables = structuredClone(gameConfigTables);
    tables.quests.quests.push(
      { ...tables.quests.quests[0], id: 9901, reset_cycle: 1 },
      { ...tables.quests.quests[0], id: 9902, reset_cycle: 0 },
    );
    const engine = new GameEngine(tables);
    const ids = tables.weeklyTasks.weekly_tasks.flatMap(w => w.daily_quests.flat());
    const claimed = { current_count: 99, completed: true, claimed: true };
    const empty = { current_count: 0, completed: false, claimed: false };
    const filled = (last: string) => {
      const state = engine.createInitialState(); state.cultivation.current_level = 2;
      engine.questEngine.initQuestProgress(state);
      for (const id of [...ids, 9901, 9902]) state.quest_progress![id] = { ...claimed };
      state.quest_last_reset = Date.parse(last);
      engine.activityEngine.initProgress(state);
      state.activity_progress![3] = { completed: true, claimed: true, last_reset: Date.parse(last) };
      return state;
    };

    const state = filled("2026-10-18T06:00:00+08:00");
    engine.questEngine.checkAndResetQuests(state, engine.questResetHour);
    assert.deepEqual(state.quest_progress![1001], claimed, "Monday before 05:00 belongs to previous week");
    assert.equal(engine.activityEngine.getCurrentDay(3, engine.questResetHour), 6);
    now++;
    assert.equal(engine.questEngine.checkAndResetQuests(state, engine.questResetHour), true);
    for (const id of [...ids, 9901]) assert.deepEqual(state.quest_progress![id], empty, `reset quest ${id}`);
    assert.deepEqual(state.quest_progress![9902], claimed, "one-time rewards survive weekly rollover");
    assert.equal(engine.activityEngine.getCurrentDay(3, engine.questResetHour), 0);
    engine.activityEngine.checkAndReset(state, engine.questResetHour);
    assert.equal(state.activity_progress![3].claimed, false);
    const snapshot = structuredClone(state);
    assert.equal(engine.questEngine.checkAndResetQuests(state, engine.questResetHour), false);
    assert.deepEqual(state, snapshot, "same-period refresh is idempotent");

    // Keep a task claimed through every daily check; no midweek reset.
    state.quest_progress![1001] = { ...claimed };
    for (const day of [20, 21, 22, 23, 24, 25]) {
      now = Date.parse(`2026-10-${day}T05:00:00+08:00`);
      engine.questEngine.checkAndResetQuests(state, engine.questResetHour);
      assert.deepEqual(state.quest_progress![1001], claimed, `no extra reset on October ${day}`);
      state.activity_progress![3].claimed = true;
      engine.activityEngine.checkAndReset(state, engine.questResetHour);
      assert.equal(state.activity_progress![3].claimed, true, "weekly activity follows the same boundary");
    }
    now = Date.parse("2026-10-26T05:00:00+08:00");
    engine.questEngine.incrementQuestProgress(state, 1, 1, engine);
    assert.deepEqual(state.quest_progress![1001], { current_count: 1, completed: true, claimed: false });
    assert.equal(engine.questEngine.claimQuestReward(state, 1001, engine).ok, true);
    assert.equal(engine.questEngine.claimQuestReward(state, 1001, engine).ok, false);

    const year = filled("2026-12-31T12:00:00+08:00");
    now = Date.parse("2027-01-01T12:00:00+08:00");
    engine.questEngine.checkAndResetQuests(year, engine.questResetHour);
    assert.deepEqual(year.quest_progress![1001], claimed, "January 1 is still the same Monday-based week");
    engine.activityEngine.checkAndReset(year, engine.questResetHour);
    assert.equal(year.activity_progress![3].claimed, true);
    now = Date.parse("2027-01-04T05:00:00+08:00");
    engine.questEngine.checkAndResetQuests(year, engine.questResetHour);
    assert.deepEqual(year.quest_progress![1001], empty);
    engine.activityEngine.checkAndReset(year, engine.questResetHour);
    assert.equal(year.activity_progress![3].claimed, false);

    // A stale claim cannot redeem last week's unclaimed completion.
    now = Date.parse("2026-10-19T05:00:00+08:00");
    const stale = filled("2026-10-18T12:00:00+08:00");
    stale.quest_progress![1001].claimed = false;
    const rewards = structuredClone(stale.pending_rewards);
    assert.deepEqual(engine.questEngine.claimQuestReward(stale, 1001, engine), { ok: false, reason: "quest_not_completed" });
    assert.deepEqual(stale.pending_rewards, rewards);

    const storage = new TestStorage();
    const token = await signToken({ userId: "weekly", deviceId: "weekly-device" }, "weekly-secret");
    const request = async (path = "/state", body: any = {}, method = "GET") => {
      // A new router per request mirrors separate Worker instances.
      const router = createGameRouter(storage, engine, "weekly-secret");
      const res = new WorkerResponse();
      await router.handle({ method, path, body, headers: { authorization: "Bearer " + token }, query: {} }, res);
      return { status: res.statusCode, data: await res.toResponse().json() as any };
    };
    await storage.saveState("weekly", filled("2026-10-18T12:00:00+08:00"));
    const loaded = await request();
    assert.equal(loaded.status, 200);
    assert.equal(loaded.data.activity_current_day, 0);
    for (const id of ids) assert.deepEqual(loaded.data.quest_progress[id], empty);
    assert.deepEqual((await storage.loadState("weekly"))!.quest_progress![1001], empty);
    assert.equal((await request()).data.quest_progress[1001].claimed, false);

    // State reads and claims share one queue; neither can restore old progress.
    const ready = (await storage.loadState("weekly"))!;
    engine.questEngine.incrementQuestProgress(ready, 1, 1, engine);
    await storage.saveState("weekly", ready);
    const concurrent = await Promise.all([request(), request("/quest_claim", { quest_id: 1001 }, "POST"), request()]);
    assert.deepEqual(concurrent.map(r => r.status), [200, 200, 200]);
    assert.equal(concurrent[2].data.quest_progress[1001].claimed, true);
    assert.equal((await storage.loadState("weekly"))!.pending_rewards.filter(r => r.kind === "card_pack").length, 1);
    const afterClaim = (await storage.loadState("weekly"))!;
    assert.equal(afterClaim.pending_rewards.filter(r => r.kind === "card_pack").length, 1);
    assert.equal((await request("/quest_claim", { quest_id: 1001 }, "POST")).data.error, "already_claimed");
    assert.equal((await request()).data.quest_progress[1001].claimed, true, "relogin preserves this week's claim");

    // Direct claim without a state fetch still resets and saves on rejection.
    now = Date.parse("2026-10-26T05:00:00+08:00");
    assert.equal((await request("/quest_claim", { quest_id: 1001 }, "POST")).data.error, "quest_not_completed");
    assert.deepEqual((await storage.loadState("weekly"))!.quest_progress![1001], empty);

    // Never report a successful reset if saving it fails.
    await storage.saveState("weekly", { ...filled("2026-10-18T12:00:00+08:00"), storage_revision: (await storage.loadState("weekly"))!.storage_revision });
    storage.fail = true;
    assert.equal((await request()).status, 500);
    assert.equal((await storage.loadState("weekly"))!.quest_progress![1001].claimed, true);
    assert.equal((await request()).data.quest_progress[1001].claimed, false);

    now = Date.parse("2026-11-09T05:00:00+08:00");
    const offline = (await storage.loadState("weekly"))!;
    offline.quest_progress![1001] = { ...claimed };
    await storage.saveState("weekly", offline);
    assert.deepEqual((await request()).data.quest_progress[1001], empty, "multiple weeks offline reset once");
    realLog("WEEKLY_QUEST_RESET_SMOKE_OK boundary timezone midweek year rollover claim persistence retry offline");
  } finally {
    Date.now = realNow;
    console.log = realLog;
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
