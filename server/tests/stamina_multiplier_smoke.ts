import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);

function stateAt(stamina: number, cultivationLevel = 2): any {
  const state: any = engine.createInitialState();
  state.stamina = stamina;
  state.cultivation.current_level = cultivationLevel;
  state.stamina_multiplier_max = 1;
  state.stamina_multiplier_expires_at = 0;
  return state;
}

for (const [stamina, expected] of [
  [199, 1], [200, 2], [399, 2], [400, 4], [799, 4], [800, 4],
] as const) {
  const state = stateAt(stamina);
  const boost = engine.refreshStaminaMultiplierFromBalance(state, 1_000);
  assert.equal(boost.maxMultiplier, expected, `stamina ${stamina}`);
  assert.equal(boost.expiresAt, expected > 1 ? 3_601_000 : 0);
}

for (const [cultivationLevel, expected] of [
  [1, 4],  // Mortal uses the Qi Refining cap.
  [2, 4], [10, 4],   // Qi Refining
  [11, 8], [13, 8],  // Foundation Establishment
  [14, 16], [16, 16], // Golden Core
  [17, 32], [19, 32], // Nascent Soul
  [20, 32], // Later realms retain the highest configured progression cap.
] as const) {
  const state = stateAt(3_200, cultivationLevel);
  const boost = engine.refreshStaminaMultiplierFromBalance(state, 1_000);
  assert.equal(boost.maxMultiplier, expected, `cultivation level ${cultivationLevel}`);
  assert.equal(engine.getCultivationStaminaMultiplierCap(state), expected);
}

for (const [cultivationLevel, stamina, expected] of [
  [11, 799, 4], [11, 800, 8],
  [14, 1_599, 8], [14, 1_600, 16],
  [17, 3_199, 16], [17, 3_200, 32],
] as const) {
  const state = stateAt(stamina, cultivationLevel);
  assert.equal(
    engine.refreshStaminaMultiplierFromBalance(state, 1_000).maxMultiplier,
    expected,
    `cultivation level ${cultivationLevel}, stamina ${stamina}`,
  );
}

const legacyHighMultiplier = stateAt(3_200, 2);
legacyHighMultiplier.stamina_multiplier_max = 32;
legacyHighMultiplier.stamina_multiplier_expires_at = 3_601_000;
assert.equal(engine.getStaminaMultiplierState(legacyHighMultiplier, 1_000).maxMultiplier, 4);
assert.equal(engine.tickStaminaMultiplier(legacyHighMultiplier, 1_000), true);
assert.equal(legacyHighMultiplier.stamina_multiplier_max, 4);
assert.equal(legacyHighMultiplier.stamina_multiplier_expires_at, 3_601_000);

const refreshed = stateAt(400);
engine.refreshStaminaMultiplierFromBalance(refreshed, 1_000);
refreshed.stamina = 200;
const refreshedBoost = engine.refreshStaminaMultiplierFromBalance(refreshed, 2_000);
assert.equal(refreshedBoost.maxMultiplier, 4, "lower-tier retrigger keeps the active maximum");
assert.equal(refreshedBoost.expiresAt, 3_602_000, "all tiers share one refreshed expiry");
assert.equal(engine.getStaminaMultiplierState(refreshed, 3_602_001).maxMultiplier, 1);
assert.equal(engine.tickStaminaMultiplier(refreshed, 3_602_001), true);

const launcherState = stateAt(400);
launcherState.grid = [{ uid: 100, id: 11001, col: 0, row: 0, charges: 5 }];
launcherState.uid_counter = 100;
launcherState.spawn_seed = 12345;
launcherState.spawn_sequence = 0;
engine.refreshStaminaMultiplierFromBalance(launcherState);
const boostedSpawn = engine.executeSpawn(launcherState, 0, 0, 0, 4);
assert.equal(boostedSpawn.ok, true);
if (boostedSpawn.ok) {
  assert.equal(boostedSpawn.staminaMultiplier, 4);
  assert.equal(boostedSpawn.staminaCost, 4);
  assert.equal(engine.getItemData(boostedSpawn.spawnedId)?.level, 3);
  assert.equal(launcherState.stamina, 396);
  assert.equal(launcherState.grid.find((item: any) => item.uid === 100)?.charges, 4);
}

const inactiveState = stateAt(199);
inactiveState.grid = [{ uid: 110, id: 11001, col: 0, row: 0, charges: 5 }];
assert.deepEqual(engine.executeSpawn(inactiveState, 0, 0, 0, 2), {
  ok: false,
  reason: "stamina_multiplier_not_active",
});

const realmCappedState = stateAt(3_200, 2);
realmCappedState.grid = [{ uid: 115, id: 11001, col: 0, row: 0, charges: 5 }];
engine.refreshStaminaMultiplierFromBalance(realmCappedState);
assert.deepEqual(engine.executeSpawn(realmCappedState, 0, 0, 0, 8), {
  ok: false,
  reason: "stamina_multiplier_not_active",
});

const insufficientState = stateAt(400);
insufficientState.grid = [{ uid: 120, id: 11001, col: 0, row: 0, charges: 5 }];
engine.refreshStaminaMultiplierFromBalance(insufficientState);
insufficientState.stamina = 3;
assert.deepEqual(engine.executeSpawn(insufficientState, 0, 0, 0, 4), {
  ok: false,
  reason: "insufficient_stamina",
});

const baseLevelTwoState = stateAt(200);
baseLevelTwoState.grid = [{ uid: 130, id: 11001, col: 0, row: 0, charges: 5 }];
baseLevelTwoState.spawn_seed = 7;
baseLevelTwoState.spawn_sequence = 0;
engine.refreshStaminaMultiplierFromBalance(baseLevelTwoState);
const cropLauncher = engine.getItemData(11001)!;
const originalSpawns = cropLauncher.spawns;
cropLauncher.spawns = [{ id: 5002, weight: 1 }];
const levelTwoSpawn = engine.executeSpawn(baseLevelTwoState, 0, 0, 0, 2);
cropLauncher.spawns = originalSpawns;
assert.equal(levelTwoSpawn.ok, true);
if (levelTwoSpawn.ok) assert.equal(levelTwoSpawn.spawnedId, 5003);

const orderPriorityState = stateAt(400);
orderPriorityState.grid = [{ uid: 150, id: 11001, col: 0, row: 0, charges: 5 }];
orderPriorityState.uid_counter = 150;
orderPriorityState.spawn_seed = 11;
orderPriorityState.spawn_sequence = 0;
orderPriorityState.meridian_acupoints = [{
  item_ids: [5001, 5001],
  items: [
    { item_id: 5001, name: "露芽米", value: 1 },
    { item_id: 5001, name: "露芽米", value: 1 },
  ],
  completed: false,
}];
engine.refreshStaminaMultiplierFromBalance(orderPriorityState);
const priorityOriginalSpawns = cropLauncher.spawns;
cropLauncher.spawns = [{ id: 5001, weight: 1 }];
const firstPrioritySpawn = engine.executeSpawn(orderPriorityState, 0, 0, 0, 4);
assert.equal(firstPrioritySpawn.ok, true);
if (firstPrioritySpawn.ok) {
  assert.equal(firstPrioritySpawn.spawnedItems.length, 1, "one click only spawns one item");
  assert.equal(firstPrioritySpawn.spawnedId, 5001);
  assert.equal(firstPrioritySpawn.staminaMultiplier, 1);
  assert.equal(firstPrioritySpawn.requestedStaminaMultiplier, 4);
  assert.equal(firstPrioritySpawn.staminaCost, 1);
  assert.equal(firstPrioritySpawn.staminaRefund, 3);
  assert.equal(orderPriorityState.stamina, 399);
}
const secondPrioritySpawn = engine.executeSpawn(orderPriorityState, 0, 0, 1, 4);
assert.equal(secondPrioritySpawn.ok, true);
if (secondPrioritySpawn.ok) {
  assert.equal(secondPrioritySpawn.spawnedItems.length, 1, "the second click also spawns one item");
  assert.equal(secondPrioritySpawn.spawnedId, 5001);
  assert.equal(secondPrioritySpawn.staminaCost, 1);
  assert.equal(secondPrioritySpawn.staminaRefund, 3);
}
const normalSpawnAfterOrderFilled = engine.executeSpawn(orderPriorityState, 0, 0, 2, 4);
cropLauncher.spawns = priorityOriginalSpawns;
assert.equal(normalSpawnAfterOrderFilled.ok, true);
if (normalSpawnAfterOrderFilled.ok) {
  assert.equal(normalSpawnAfterOrderFilled.spawnedId, 5003);
  assert.equal(normalSpawnAfterOrderFilled.staminaMultiplier, 4);
  assert.equal(normalSpawnAfterOrderFilled.staminaCost, 4);
  assert.equal(normalSpawnAfterOrderFilled.staminaRefund, 0);
}

const lowestOrderLevelState = stateAt(400);
lowestOrderLevelState.grid = [{ uid: 160, id: 11001, col: 0, row: 0, charges: 5 }];
lowestOrderLevelState.uid_counter = 160;
lowestOrderLevelState.spawn_seed = 12;
lowestOrderLevelState.spawn_sequence = 0;
lowestOrderLevelState.meridian_acupoints = [{
  item_ids: [5002, 5001],
  items: [{ item_id: 5002 }, { item_id: 5001 }],
  completed: false,
}];
engine.refreshStaminaMultiplierFromBalance(lowestOrderLevelState);
cropLauncher.spawns = [{ id: 5001, weight: 1 }];
const lowestOrderSpawn = engine.executeSpawn(lowestOrderLevelState, 0, 0, 0, 4);
assert.equal(lowestOrderSpawn.ok, true);
if (lowestOrderSpawn.ok) assert.equal(lowestOrderSpawn.spawnedId, 5001);
const nextOrderLevelSpawn = engine.executeSpawn(lowestOrderLevelState, 0, 0, 1, 4);
cropLauncher.spawns = priorityOriginalSpawns;
assert.equal(nextOrderLevelSpawn.ok, true);
if (nextOrderLevelSpawn.ok) {
  assert.equal(nextOrderLevelSpawn.spawnedId, 5002);
  assert.equal(nextOrderLevelSpawn.staminaMultiplier, 2);
  assert.equal(nextOrderLevelSpawn.staminaCost, 2);
  assert.equal(nextOrderLevelSpawn.staminaRefund, 2);
}

const lowBalanceOrderState = stateAt(1);
lowBalanceOrderState.grid = [{ uid: 170, id: 11001, col: 0, row: 0, charges: 5 }];
lowBalanceOrderState.uid_counter = 170;
lowBalanceOrderState.spawn_seed = 13;
lowBalanceOrderState.spawn_sequence = 0;
lowBalanceOrderState.meridian_acupoints = [{
  item_ids: [5001], items: [{ item_id: 5001 }], completed: false,
}];
lowBalanceOrderState.stamina_multiplier_max = 4;
lowBalanceOrderState.stamina_multiplier_expires_at = Date.now() + 60_000;
cropLauncher.spawns = [{ id: 5001, weight: 1 }];
const lowBalanceOrderSpawn = engine.executeSpawn(lowBalanceOrderState, 0, 0, 0, 4);
cropLauncher.spawns = priorityOriginalSpawns;
assert.equal(lowBalanceOrderSpawn.ok, true);
if (lowBalanceOrderSpawn.ok) {
  assert.equal(lowBalanceOrderSpawn.staminaCost, 1);
  assert.equal(lowBalanceOrderState.stamina, 0);
}

const breakthroughOrderState = stateAt(400);
breakthroughOrderState.grid = [{ uid: 180, id: 16002, col: 0, row: 0, charges: 5 }];
breakthroughOrderState.uid_counter = 180;
breakthroughOrderState.spawn_seed = 1;
breakthroughOrderState.spawn_sequence = 0;
breakthroughOrderState.meridian_acupoints = [{
  item_ids: [14101],
  items: [{ item_id: 14101 }],
  completed: false,
  breakthrough_order: true,
  breakthrough_level: 2,
}];
engine.refreshStaminaMultiplierFromBalance(breakthroughOrderState);
const advancedBookLauncher = engine.getItemData(16002)!;
const originalBookSpawns = advancedBookLauncher.spawns;
advancedBookLauncher.spawns = [{ id: 14102, weight: 1 }];
const breakthroughOrderSpawn = engine.executeSpawn(breakthroughOrderState, 0, 0, 0, 4);
advancedBookLauncher.spawns = originalBookSpawns;
assert.equal(breakthroughOrderSpawn.ok, true);
if (breakthroughOrderSpawn.ok) {
  assert.equal(breakthroughOrderSpawn.spawnedItems.length, 1);
  assert.equal(breakthroughOrderSpawn.spawnedId, 14101);
  assert.equal(breakthroughOrderSpawn.staminaCost, 1);
  assert.equal(breakthroughOrderSpawn.staminaRefund, 3);
  assert.equal(breakthroughOrderSpawn.orderPriority, true);
}

const unrelatedRollState = stateAt(400);
unrelatedRollState.grid = [{ uid: 181, id: 16001, col: 0, row: 0, charges: 5 }];
unrelatedRollState.uid_counter = 181;
unrelatedRollState.spawn_seed = 2; // Rolls group 13; the order requires group 14.
unrelatedRollState.spawn_sequence = 0;
unrelatedRollState.meridian_acupoints = [{
  item_ids: [14101],
  items: [{ item_id: 14101 }],
  completed: false,
  breakthrough_order: true,
  breakthrough_level: 2,
}];
engine.refreshStaminaMultiplierFromBalance(unrelatedRollState);
const unrelatedRollSpawn = engine.executeSpawn(unrelatedRollState, 0, 0, 0, 4);
assert.equal(unrelatedRollSpawn.ok, true);
if (unrelatedRollSpawn.ok) {
  assert.equal(unrelatedRollSpawn.spawnedId, 13103);
  assert.equal(unrelatedRollSpawn.staminaCost, 4);
  assert.equal(unrelatedRollSpawn.staminaRefund, 0);
  assert.equal(unrelatedRollSpawn.orderPriority, false);
}

const recipeMaterialState = stateAt(400);
recipeMaterialState.grid = [
  { uid: 190, id: 11001, col: 0, row: 0, charges: 5 },
  { uid: 191, id: 5001, col: 1, row: 0, immovable: true },
];
recipeMaterialState.uid_counter = 190;
recipeMaterialState.spawn_seed = 21;
recipeMaterialState.spawn_sequence = 0;
recipeMaterialState.meridian_acupoints = [{
  item_ids: [27001],
  items: [{ item_id: 27001 }],
  completed: false,
  breakthrough_order: true,
  breakthrough_level: 2,
}];
engine.refreshStaminaMultiplierFromBalance(recipeMaterialState);
cropLauncher.spawns = [{ id: 5002, weight: 1 }];
const recipeMaterialSpawn = engine.executeSpawn(recipeMaterialState, 0, 0, 0, 4);
cropLauncher.spawns = priorityOriginalSpawns;
assert.equal(recipeMaterialSpawn.ok, true);
if (recipeMaterialSpawn.ok) {
  assert.equal(recipeMaterialSpawn.spawnedId, 5001);
  assert.equal(recipeMaterialSpawn.staminaCost, 1);
  assert.equal(recipeMaterialSpawn.staminaRefund, 3);
  assert.equal(recipeMaterialSpawn.orderPriority, true);
}

const storedIntermediateState = stateAt(400);
storedIntermediateState.meridian_acupoints = [{
  item_ids: [27081],
  items: [{ item_id: 27081 }],
  completed: false,
}];
storedIntermediateState.grid = [{
  uid: 195,
  id: 17001,
  col: 0,
  row: 0,
  craft: {
    _craft_state: 1,
    _craft_stored: [{ id: 27002 }],
    _craft_recipe: {},
    _craft_result_id: -1,
  },
}];
const storedIntermediateOutstanding = (engine as any).getOutstandingOrderItemCounts(
  storedIntermediateState,
) as Map<number, number>;
assert.equal(storedIntermediateOutstanding.has(27002), false);
assert.equal(storedIntermediateOutstanding.has(5002), false);
assert.equal(storedIntermediateOutstanding.has(9002), false);
assert.equal(storedIntermediateOutstanding.get(9004), 1);

const freeState = stateAt(400);
freeState.grid = [{ uid: 140, id: 11001, col: 0, row: 0, charges: 5 }];
freeState.spawn_seed = 8;
freeState.spawn_sequence = 0;
engine.refreshStaminaMultiplierFromBalance(freeState);
const originalNoCost = cropLauncher.no_cost;
cropLauncher.no_cost = true;
assert.deepEqual(engine.executeSpawn(freeState, 0, 0, 0, 2), {
  ok: false,
  reason: "stamina_multiplier_not_applicable",
});
const freeSpawn = engine.executeSpawn(freeState, 0, 0, 0, 1);
cropLauncher.no_cost = originalNoCost;
assert.equal(freeSpawn.ok, true);
if (freeSpawn.ok) {
  assert.equal(freeSpawn.staminaCost, 0);
  assert.equal(freeState.stamina, 400);
}

const mineState = stateAt(1_600, 17);
mineState.grid = [{ uid: 200, id: 25001, col: 0, row: 0, charges: 6 }];
mineState.uid_counter = 200;
mineState.spawn_seed = 99;
mineState.spawn_sequence = 0;
engine.refreshStaminaMultiplierFromBalance(mineState);
assert.equal(engine.getLauncherSafeStaminaMultiplier(25001), 8);
const capped = engine.executeSpawn(mineState, 0, 0, 0, 16);
assert.deepEqual(capped, { ok: false, reason: "stamina_multiplier_above_launcher_cap" });
const mineSpawn = engine.executeSpawn(mineState, 0, 0, 0, 8);
assert.equal(mineSpawn.ok, true);
if (mineSpawn.ok) assert.equal(engine.getItemData(mineSpawn.spawnedId)?.level, 4);

const battleState = stateAt(400);
battleState.board_type = 1;
battleState.grid = [{ uid: 300, id: 11001, col: 0, row: 0, charges: 5 }];
engine.refreshStaminaMultiplierFromBalance(battleState);
assert.deepEqual(engine.executeSpawn(battleState, 0, 0, 0, 2), {
  ok: false,
  reason: "stamina_multiplier_not_applicable",
});

console.log("STAMINA_MULTIPLIER_SMOKE_OK thresholds=true realm_caps=true normalization=true refresh=true spawn_upgrade=true order_priority=true refund=true cap=true restrictions=true");
