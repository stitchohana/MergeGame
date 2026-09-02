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
assert.equal(Object.prototype.hasOwnProperty.call(homeConfig.stages[0], "circulation_reward"), true);
assert.equal(homeConfig.stages.length, 666);
assert.equal(homeConfig.stages.every((stage: any) => stage.circulation_reward.items.length === 2), true);
assert.equal(Object.prototype.hasOwnProperty.call(meridianConfig, "order_pool"), false);
assert.equal(Object.prototype.hasOwnProperty.call(meridianConfig, "order_level_ranges"), true);
assert.equal(Object.prototype.hasOwnProperty.call(meridianConfig.thresholds[0], "fixed_order_batches"), false);
assert.equal(meridianConfig.thresholds[0].order_count, 7);
assert.deepEqual(
  meridianConfig.thresholds[0].fixed_orders.map((wave: any) => wave.item_ids),
  [[5003, 5004, 6001], [9003, 9004, 10001], [27001]],
);
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
fixedOrderState.grid = [5003, 5004, 6001, 9003, 9004, 10001, 27001].map((id, index) => ({
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
  [9003, 9004, 10001],
);
assert.equal(fixedOrderState.meridian_fixed_order_cursor, 6);

const state: any = engine.createInitialState();
assert.deepEqual(
  state.grid.filter((item: any) => [12001, 17001, 16001].includes(item.id)).map((item: any) => item.id).sort((a: number, b: number) => a - b),
  [12001, 12001, 16001, 17001],
);
state.cultivation.current_level = 2;
state.cultivation.current_exp = 0;
state.cultivation.current_qi = 10000;

const level2Stages = homeConfig.stages
  .map((stage: any, index: number) => ({ stage, index }))
  .filter(({ stage }: any) => stage.cultivation_level === 2);
assert.equal(level2Stages.length, 6);
for (const { stage, index } of level2Stages) {
  assert.equal(stage.acupoints, 4);
  for (let acupointIndex = 0; acupointIndex < stage.acupoints; acupointIndex += 1) {
    const result = engine.lightHomeAcupoint(state, index, acupointIndex);
    assert.equal(result.ok, true);
    if (!result.ok) throw new Error(`acupoint ${index}:${acupointIndex} failed: ${result.reason}`);
    assert.equal(result.circulation_completed, acupointIndex === stage.acupoints - 1);
  }
}

assert.equal(state.cultivation.current_exp, 48);
assert.equal(engine.isBreakthroughReady(2, state.cultivation.current_exp), true);
assert.deepEqual(
  state.pending_rewards.map((reward: any) => reward.id).length,
  12,
);

console.log("HOME_MERIDIAN_EXP_SERVER_SMOKE_OK");
