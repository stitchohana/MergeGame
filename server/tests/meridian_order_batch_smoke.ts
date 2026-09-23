import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const launcher = gameConfigTables.items.launcher.find((item: any) => Number(item.id) === 15001) as any;
assert.ok(launcher);
assert.deepEqual(launcher.spawns.map((spawn: any) => spawn.weight), [500, 250, 250]);

const weightedPool = (engine as any).getUnlockedOrderPoolWithWeights({
  cultivation: { current_level: 1 },
  grid: [{ uid: 1, id: 15001, col: 0, row: 0 }],
});
const itemByGroup = new Map<number, any>(
  gameConfigTables.items.regular.map((item: any) => [Number(item.id), item]),
);
const representativeWeights = new Map<number, number>();
for (const itemId of weightedPool.ids) {
  const item = itemByGroup.get(itemId);
  if (item && !representativeWeights.has(Number(item.group_id))) {
    representativeWeights.set(Number(item.group_id), weightedPool.weights.get(itemId));
  }
}
assert.equal(representativeWeights.get(3), 0.5);
assert.equal(representativeWeights.get(6), 0.25);
assert.equal(representativeWeights.get(40), 0.25);

const state: any = engine.createInitialState();
state.cultivation.current_level = 2;
state.cultivation.current_exp = 0;
state.cultivation.current_qi = 0;
state.cultivation.max_qi = 100000;
state.grid = [
  { uid: 1, id: 15001, col: 0, row: 0, charges: 0, last_charge_time: Date.now(), _recharge_remaining: 1000 },
  { uid: 2, id: 2004, col: 1, row: 0 },
  { uid: 3, id: 2004, col: 2, row: 0 },
];
state.meridian_threshold_idx = 1;
state.meridian_acupoints = [
  { item_ids: [2004], completed: false, total_value: 1 },
  { item_ids: [2004], completed: false, total_value: 1 },
];

const first = engine.completeMeridianAcupoint(state, 0, [2004]);
assert.equal(first.ok, true);
if (!first.ok) throw new Error(first.reason);
assert.equal(first.meridian_acupoints.length, 1);
assert.equal(state.grid.find((item: any) => item.id === 15001).charges, 0);

const second = engine.completeMeridianAcupoint(state, 0, [2004]);
assert.equal(second.ok, true);
if (!second.ok) throw new Error(second.reason);
assert.equal(second.meridian_acupoints.length, gameConfigTables.meridians.thresholds[1].order_count);
assert.equal(state.grid.find((item: any) => item.id === 15001).charges, launcher.max_charges);
assert.equal(Object.prototype.hasOwnProperty.call(state.grid.find((item: any) => item.id === 15001), "last_charge_time"), false);
const refreshedValues = second.meridian_acupoints.map((order: any) => Number(order.total_value));
assert.deepEqual(refreshedValues, [...refreshedValues].sort((left, right) => left - right));
const refreshedItemIds = second.meridian_acupoints.flatMap((order: any) => order.item_ids.map((itemId: number) => Number(itemId)));
assert.equal(new Set(refreshedItemIds).size, refreshedItemIds.length);
assert.equal(second.meridian_acupoints.every((order: any) => order.item_ids.length > 0), true);
for (const order of second.meridian_acupoints) {
  assert.equal(new Set(order.item_ids).size, order.item_ids.length);
}

console.log("MERIDIAN_ORDER_BATCH_SERVER_SMOKE_OK");
