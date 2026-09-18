import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const homeConfig: any = gameConfigTables.homeMeridians;
const meridianConfig: any = gameConfigTables.meridians;
const launcherConfig: any[] = gameConfigTables.items.launcher as any[];
const launcherById = new Map(launcherConfig.map((item: any) => [Number(item.id), item]));

for (let level = 1; level <= 16; level += 1) {
  const mine = launcherById.get(25000 + level);
  const mineral = launcherById.get(15000 + level);
  assert.equal(mine.max_charges, 6);
  assert.equal(mine.recharge_time, 43200);
  assert.deepEqual(mine.spawns.map((spawn: any) => spawn.id), [1601]);
  assert.equal(mine.spawns[0].weight, 1000);
  const jadeSpawns = mineral.spawns.filter((spawn: any) => spawn.id >= 1501 && spawn.id <= 1516);
  assert.equal(jadeSpawns.reduce((sum: number, spawn: any) => sum + spawn.weight, 0), 50);
  assert.equal(mineral.spawns.reduce((sum: number, spawn: any) => sum + spawn.weight, 0), 1000);
}

assert.equal(Object.prototype.hasOwnProperty.call(homeConfig, "production_rewards"), false);
assert.equal(Object.prototype.hasOwnProperty.call(homeConfig, "production_reward_rules"), false);
assert.equal(Object.prototype.hasOwnProperty.call(homeConfig.stages[0], "acupoint_rewards"), false);
assert.equal(Object.prototype.hasOwnProperty.call(homeConfig.stages[0], "circulation_exp"), false);
assert.equal(Object.prototype.hasOwnProperty.call(homeConfig.stages[0], "acupoint_exp"), false);
assert.equal(Object.prototype.hasOwnProperty.call(homeConfig.stages[0], "circulation_reward"), true);
assert.equal(homeConfig.stages.length, 666);
assert.equal(homeConfig.stages.every((stage: any, index: number) =>
  stage.circulation_reward.items.length === ([1, 0, 2][index] ?? 2)), true);
assert.equal(homeConfig.stages.every((stage: any) => stage.circulation_reward.tokens.some((token: any) => token.token === 4 && token.amount > 0)), true);
assert.equal(Object.prototype.hasOwnProperty.call(meridianConfig, "order_pool"), false);
assert.equal(Object.prototype.hasOwnProperty.call(meridianConfig, "order_level_ranges"), true);
assert.equal(Object.prototype.hasOwnProperty.call(meridianConfig.thresholds[0], "fixed_order_batches"), false);
assert.equal(meridianConfig.thresholds[0].order_count, 6);
assert.deepEqual(
  meridianConfig.thresholds[0].fixed_orders.map((wave: any) => wave.item_ids),
  [[5003, 5004, 6001], [9003, 9004, 10001]],
);
assert.deepEqual(
  gameConfigTables.cultivation.stages[0].breakthrough_items,
  [{ item_id: 14101, count: 1 }, { item_id: 27001, count: 1 }],
);
assert.deepEqual(
  homeConfig.stages[2].circulation_reward.items,
  [{ id: 16001, count: 1 }, { id: 17001, count: 1 }],
);
assert.deepEqual(homeConfig.stages[0].circulation_reward.items, [{ id: 12001, count: 1 }]);
assert.deepEqual(homeConfig.stages[1].circulation_reward.items, []);
assert.equal(homeConfig.stages[1].circulation_reward.tokens.some((token: any) =>
  token.token === 1 && token.amount === 10), true);

const secondTutorialCirculationState: any = engine.createInitialState();
secondTutorialCirculationState.grid.push({
  uid: 999,
  id: 11001,
  col: 6,
  row: 8,
  charges: 0,
  last_charge_time: Date.now(),
  _recharge_remaining: 60000,
});
secondTutorialCirculationState.home_meridian_progress = [{
  stage: 1,
  lit: new Array(homeConfig.stages[1].acupoints).fill(true),
  circulation_completed: false,
}];
const secondTutorialCirculation = engine.runHomeMeridianCirculation(secondTutorialCirculationState, 1);
assert.equal(secondTutorialCirculation.ok, true);
if (!secondTutorialCirculation.ok) throw new Error("second tutorial circulation failed");
assert.equal(secondTutorialCirculationState.spirit_stones, 10);
assert.deepEqual(secondTutorialCirculation.rewards.items, []);
const refreshedLauncher = secondTutorialCirculationState.grid.find((item: any) => item.uid === 999);
assert.equal(refreshedLauncher.charges, launcherById.get(11001).max_charges);
assert.equal(Object.prototype.hasOwnProperty.call(refreshedLauncher, "last_charge_time"), false);
assert.equal(Object.prototype.hasOwnProperty.call(refreshedLauncher, "_recharge_remaining"), false);
assert.equal(secondTutorialCirculation.grid, secondTutorialCirculationState.grid);
assert.equal(secondTutorialCirculation.launchers_refreshed > 0, true);

const thirdTutorialCirculationState: any = engine.createInitialState();
thirdTutorialCirculationState.home_meridian_progress = [{
  stage: 2,
  lit: new Array(homeConfig.stages[2].acupoints).fill(true),
  circulation_completed: false,
}];
const thirdTutorialCirculation = engine.runHomeMeridianCirculation(thirdTutorialCirculationState, 2);
assert.equal(thirdTutorialCirculation.ok, true);
if (!thirdTutorialCirculation.ok) throw new Error("third tutorial circulation failed");
assert.equal(thirdTutorialCirculation.rewards.items?.some((item: any) =>
  item.id === 17001 && item.count === 1), true);
assert.equal(thirdTutorialCirculationState.pending_rewards.some((item: any) => item.id === 17001), true);
assert.deepEqual((engine as any)._genFixedAcupoint({ item_id: 5003 }).item_ids, [5003]);
assert.deepEqual((engine as any)._genFixedAcupoint({ item_ids: [5004] }).item_ids, [5004]);
assert.deepEqual(
  (engine as any)._getFixedOrderWaves({ fixed_orders: [
    { item_ids: [5003, 5004] },
    { item_ids: [6001] },
  ] }).map((wave: any[]) => wave.map((order: any) => order.item_id)),
  [[5003, 5004], [6001]],
);
assert.deepEqual(
  (engine as any)._getFixedOrderWaves({ fixed_orders: [
    { item_ids: [5003] },
    { item_ids: [5004] },
  ] }).map((wave: any[]) => wave.map((order: any) => order.item_id)),
  [[5003], [5004]],
);

const fixedOrderState: any = engine.createInitialState();
fixedOrderState.cultivation.max_qi = 100000;
fixedOrderState.grid = [5003, 5004, 6001, 9003, 9004, 10001].map((id, index) => ({
  uid: index + 1,
  id,
  col: index,
  row: 0,
}));
const fixedOrderResult = engine.generateMeridianRequirements(fixedOrderState);
assert.deepEqual(
  fixedOrderResult.acupoints.map((order: any) => order.item_ids[0]),
  [5003, 5004, 6001],
);
assert.equal(fixedOrderState.meridian_fixed_order_cursor, 3);

const firstOrderCompleted = engine.completeMeridianAcupoint(fixedOrderState, 0, [5003]);
assert.equal(firstOrderCompleted.ok, true);
if (!firstOrderCompleted.ok) throw new Error(`first fixed order failed: ${firstOrderCompleted.reason}`);
assert.deepEqual(
  firstOrderCompleted.meridian_acupoints.map((order: any) => order.item_ids[0]),
  [5004, 6001],
);

const secondOrderCompleted = engine.completeMeridianAcupoint(fixedOrderState, 0, [5004]);
assert.equal(secondOrderCompleted.ok, true);
if (!secondOrderCompleted.ok) throw new Error(`second fixed order failed: ${secondOrderCompleted.reason}`);
assert.deepEqual(
  secondOrderCompleted.meridian_acupoints.map((order: any) => order.item_ids[0]),
  [6001],
);

const thirdOrderCompleted = engine.completeMeridianAcupoint(fixedOrderState, 0, [6001]);
assert.equal(thirdOrderCompleted.ok, true);
if (!thirdOrderCompleted.ok) throw new Error(`third fixed order failed: ${thirdOrderCompleted.reason}`);
assert.deepEqual(
  thirdOrderCompleted.meridian_acupoints.map((order: any) => order.item_ids[0]),
  [],
);
assert.equal(fixedOrderState.meridian_fixed_order_cursor, 3);
assert.equal(fixedOrderState.meridian_fixed_wave_pending, true);

// Re-entering the board requests an order refresh. That refresh must not
// bypass the circulation gate while the completed tutorial wave is empty.
const refreshWhileWaiting = engine.generateMeridianRequirements(fixedOrderState);
assert.deepEqual(refreshWhileWaiting.acupoints, []);
assert.equal(fixedOrderState.meridian_fixed_order_cursor, 3);
assert.equal(fixedOrderState.meridian_fixed_wave_pending, true);

// Existing saves from before the pending flag was introduced are recognized
// by their empty order list and already-advanced fixed-order cursor.
delete fixedOrderState.meridian_fixed_wave_pending;
const legacyRefreshWhileWaiting = engine.generateMeridianRequirements(fixedOrderState);
assert.deepEqual(legacyRefreshWhileWaiting.acupoints, []);
assert.equal(fixedOrderState.meridian_fixed_order_cursor, 3);
assert.equal(fixedOrderState.meridian_fixed_wave_pending, true);

// Completing the tutorial wave leaves the order list empty. The next wave is
// revealed only after the player lights every node and explicitly runs the
// corresponding circulation.
const firstTutorialStage = homeConfig.stages[0];
for (let acupointIndex = 0; acupointIndex < firstTutorialStage.acupoints; acupointIndex += 1) {
  const lightResult = engine.lightHomeAcupoint(fixedOrderState, 0, acupointIndex);
  assert.equal(lightResult.ok, true);
  if (!lightResult.ok) throw new Error(`tutorial acupoint 0:${acupointIndex} failed: ${lightResult.reason}`);
}
assert.deepEqual(fixedOrderState.meridian_acupoints, []);

const firstTutorialRun = engine.runHomeMeridianCirculation(fixedOrderState, 0);
assert.equal(firstTutorialRun.ok, true);
if (!firstTutorialRun.ok) throw new Error(`tutorial circulation failed: ${firstTutorialRun.reason}`);
assert.deepEqual(
  firstTutorialRun.meridian_acupoints.map((order: any) => order.item_ids[0]),
  [9003, 9004, 10001],
);
assert.equal(fixedOrderState.meridian_fixed_order_cursor, 6);
assert.equal(fixedOrderState.meridian_fixed_wave_pending, false);

const state: any = engine.createInitialState();
assert.deepEqual(
  state.grid.filter((item: any) => [12001, 17001, 16001].includes(item.id)).map((item: any) => item.id).sort((a: number, b: number) => a - b),
  [12001],
);
state.cultivation.current_level = 2;
state.cultivation.current_exp = 0;
state.cultivation.current_qi = 10000;

const level2Stages = homeConfig.stages
  .map((stage: any, index: number) => ({ stage, index }))
  .filter(({ stage }: any) => stage.cultivation_level === 2);
assert.equal(level2Stages.length, 6);
let expectedPendingRewardCount = 0;
let expectedExp = 0;
for (const { stage, index } of level2Stages) {
  assert.equal(stage.acupoints, 4);
  for (let acupointIndex = 0; acupointIndex < stage.acupoints; acupointIndex += 1) {
    const result = engine.lightHomeAcupoint(state, index, acupointIndex);
    assert.equal(result.ok, true);
    if (!result.ok) throw new Error(`acupoint ${index}:${acupointIndex} failed: ${result.reason}`);
    assert.equal(result.circulation_completed, false);
    assert.equal(result.circulation_ready, acupointIndex === stage.acupoints - 1);
    assert.equal(result.rewards.items?.length ?? 0, 0);
    assert.equal(
      (result.rewards.tokens ?? []).some((token: any) => token.token === 4),
      false,
    );
    assert.equal(state.cultivation.current_exp, expectedExp);
  }
  assert.equal(state.pending_rewards.length, expectedPendingRewardCount);
  if (index === level2Stages[level2Stages.length - 1].index) {
    const expBeforeGate = state.cultivation.current_exp;
    // Verify the explicit run gate independently of whether the pending
    // circulation is what supplies the final EXP needed for breakthrough.
    state.cultivation.current_exp = 48;
    const blockedBreakthrough = engine.executeTryBreakthrough(
      state,
      0,
      2,
      state.cultivation.current_exp,
    );
    assert.equal(blockedBreakthrough.ok, false);
    if (blockedBreakthrough.ok) throw new Error("breakthrough should wait for circulation run");
    assert.equal(blockedBreakthrough.reason, "circulation_pending");
    state.cultivation.current_exp = expBeforeGate;
  }
  const runResult = engine.runHomeMeridianCirculation(state, index);
  assert.equal(runResult.ok, true);
  if (!runResult.ok) throw new Error(`circulation ${index} failed`);
  assert.equal(runResult.circulation_completed, true);
  assert.equal(runResult.circulation_ready, false);
  assert.equal(runResult.rewards.items?.length ?? 0, 2);
  const cycleExp = (runResult.rewards.tokens ?? [])
    .filter((token: any) => token.token === 4)
    .reduce((sum: number, token: any) => sum + Number(token.amount ?? 0), 0);
  assert.equal(cycleExp, 8);
  expectedExp += cycleExp;
  assert.equal(state.cultivation.current_exp, expectedExp);
  expectedPendingRewardCount += 2;
}

assert.equal(state.cultivation.current_exp, expectedExp);
assert.equal(expectedExp, 48);
assert.equal(engine.isBreakthroughReady(2, state.cultivation.current_exp), true);
assert.deepEqual(
  state.pending_rewards.map((reward: any) => reward.id).length,
  12,
);

const duplicateRun = engine.runHomeMeridianCirculation(state, level2Stages[0].index);
assert.equal(duplicateRun.ok, false);
if (duplicateRun.ok) throw new Error("completed circulation could be run twice");
assert.equal((duplicateRun as any).reason, "circulation_completed");

const notReadyState: any = engine.createInitialState();
notReadyState.cultivation.current_level = 2;
notReadyState.cultivation.current_qi = 10000;
const notReady = engine.runHomeMeridianCirculation(notReadyState, level2Stages[0].index);
assert.equal(notReady.ok, false);
if (notReady.ok) throw new Error("unlit circulation could be run");
assert.equal((notReady as any).reason, "circulation_not_ready");

console.log("HOME_MERIDIAN_EXP_SERVER_SMOKE_OK");
