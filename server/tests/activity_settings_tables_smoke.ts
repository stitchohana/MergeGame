import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { createGameRouter } from "../src/routes/game";
import { signToken } from "../src/middleware/auth";
import { MemoryStorage } from "../src/storage/memory";
import { WorkerResponse } from "../src/worker/http";

async function main() {
  const source = structuredClone(gameConfigTables);
  assert.ok(source.activities.activities.filter(activity => [6, 7].includes(activity.id)).every(activity => !("config" in activity)));
  const engine = new GameEngine(source);
  assert.equal(engine.stairClimbService.orderPoints(100), 10);
  assert.deepEqual(engine.stairClimbService.reward(20), {min_rank: 11, max_rank: 20, stamina: 50, spirit_stones: 500});
  const config = structuredClone(source);
  config.stairClimb.settings[0].order_points_ratio = 0.25;
  config.stairClimb.rewards[0].stamina = 321;
  config.orderSupply.settings[0].target_count = 2;
  config.orderSupply.settings[0].reward_count = 4;
  const changed = new GameEngine(config);
  assert.equal(changed.stairClimbService.orderPoints(100), 25);
  assert.equal(changed.stairClimbService.reward(1).stamina, 321);
  const state = changed.createInitialState();
  state.cultivation.current_level = 2;
  state.grid = [];
  state.meridian_acupoints = [{ item_ids: [5001, 5001], name: "test", completed: false }];
  changed.activityEngine.recordOrderSupplyAction(state, 5001);
  assert.equal(state.activity_progress![7].completed, false);
  changed.activityEngine.recordOrderSupplyAction(state, 5001);
  assert.equal(state.activity_progress![7].completed, true);
  const reward = changed.activityEngine.claimOrderSupply(state, 7, 0, changed);
  assert.ok(reward.ok);
  if (reward.ok) assert.equal(reward.spawned_items.length, 4);
  assert.deepEqual(gameConfigTables.activities, source.activities, "engine must not mutate activity metadata");
  assert.deepEqual(gameConfigTables.stairClimb, source.stairClimb);
  assert.deepEqual(gameConfigTables.orderSupply, source.orderSupply);

  for (const mutate of [
    (data: typeof config) => { data.orderSupply.settings = []; },
    (data: typeof config) => { data.orderSupply.settings.push({...data.orderSupply.settings[0]}); },
    (data: typeof config) => { data.orderSupply.settings[0].target_count = 0; },
    (data: typeof config) => { data.stairClimb.settings[0].activity_id = 99; },
    (data: typeof config) => { data.stairClimb.settings[0].bot_max_minutes = 1; },
    (data: typeof config) => { data.stairClimb.rewards[0].stamina = -1; },
    (data: typeof config) => { data.stairClimb.rewards[0].min_rank = 0.5; },
    (data: typeof config) => { data.stairClimb.rewards.pop(); },
    (data: typeof config) => { data.stairClimb.rewards.push({...data.stairClimb.rewards[0]}); },
  ]) {
    const invalid = structuredClone(config);
    mutate(invalid);
    assert.throws(() => new GameEngine(invalid), /invalid_|missing_/);
  }
  const storage = new MemoryStorage();
  const start = Date.parse(config.activities.activities.find(activity => activity.id === 6)!.start_time!);
  assert.ok(await changed.stairClimbService.enroll(storage, "settings-user", state, start));
  assert.ok(changed.stairClimbService.awardOrderPoints(state, 100, start));
  assert.equal(changed.stairClimbService.score(state)!.points, 25);
  await storage.saveState("settings-user", state);
  const secret = "settings-test";
  const token = await signToken({userId: "settings-user", deviceId: "device"}, secret);
  const response = new WorkerResponse();
  await createGameRouter(storage, changed, secret).handle({method: "GET", path: "/state",
    headers: {authorization: `Bearer ${token}`}, query: {}, body: {}}, response);
  const http = response.toResponse();
  assert.equal(http.status, 200);
  const data: any = await http.json();
  assert.equal(data.activity_defs.find((activity: any) => activity.id === 7).config.target_count, 2);
  assert.equal(data.activity_defs.find((activity: any) => activity.id === 6).config.order_points_ratio, 0.25);
  console.log("ACTIVITY_SETTINGS_TABLES_SMOKE_OK dedicated_sources changed_values validation wire_format source_immutable");
}
void main();
