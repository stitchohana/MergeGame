import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { deterministicSpawnRoll } from "../src/engine/spawn_rng";

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
  [1, 1],  // Novice players cannot trigger stamina multipliers.
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

const novice = stateAt(400, 1);
const noBoost = { maxMultiplier: 1, expiresAt: 0, remainingSeconds: 0 };
assert.deepEqual(engine.addStamina(novice, 400, 1_000), noBoost);
assert.equal(novice.stamina, 800, "novice stamina rewards still apply");
novice.stamina_multiplier_max = 4;
novice.stamina_multiplier_expires_at = Date.now() + 3_600_000;
assert.deepEqual(engine.getStaminaMultiplierState(novice), noBoost, "legacy novice boost is never usable");
novice.grid = [{ uid: 100, id: 11001, col: 0, row: 0, charges: 5 }];
assert.deepEqual(engine.executeSpawn(novice, 0, 0, 0, 4), { ok: false, reason: "stamina_multiplier_not_active" });
assert.equal(engine.tickStaminaMultiplier(novice), true);
assert.equal(novice.stamina_multiplier_max, 1);
assert.equal(novice.stamina_multiplier_expires_at, 0);
const singleSpawn = engine.executeSpawn(novice, 0, 0, 0, 1);
assert.ok(singleSpawn.ok);
if (singleSpawn.ok) assert.equal(singleSpawn.staminaCost, 1);
novice.cultivation.current_level = 2;
assert.deepEqual(engine.getStaminaMultiplierState(novice), noBoost, "unlock does not restore a novice timer");
assert.equal(engine.addStamina(novice, 1).maxMultiplier, 4, "new stamina gains work normally after unlock");

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

const springLauncher = engine.getItemData(12008)!;
const originalSpringSpawns = springLauncher.spawns;
springLauncher.spawns = [{ id: 9001, weight: 1 }, { id: 10001, weight: 1 }];
const springPriorityState = stateAt(400);
springPriorityState.grid = [{ uid: 155, id: 12008, col: 0, row: 0, charges: 5 }];
springPriorityState.uid_counter = 155;
springPriorityState.spawn_sequence = 0;
springPriorityState.meridian_acupoints = [{
  item_ids: [9001], items: [{ item_id: 9001 }], completed: false,
}];
let springSeed = 1;
while (deterministicSpawnRoll(springSeed, 0, 155, 2) !== 1) springSeed++;
springPriorityState.spawn_seed = springSeed;
engine.refreshStaminaMultiplierFromBalance(springPriorityState);
const springPrioritySpawn = engine.executeSpawn(springPriorityState, 0, 0, 0, 4);
springLauncher.spawns = originalSpringSpawns;
assert.equal(springPrioritySpawn.ok, true);
if (springPrioritySpawn.ok) {
  assert.equal(springPrioritySpawn.spawnedId, 9001);
  assert.equal(springPrioritySpawn.staminaMultiplier, 1);
  assert.equal(springPrioritySpawn.staminaCost, 1);
  assert.equal(springPrioritySpawn.orderPriority, true);
}

// Water put in a forge cannot satisfy an alchemy order or disable priority.
const misplacedMaterialState = stateAt(400);
misplacedMaterialState.grid = [
  { uid: 156, id: 12008, col: 0, row: 0, charges: 5 },
  { uid: 157, id: 18002, col: 1, row: 0, craft: {
    _craft_state: 1, _craft_stored: [{ id: 9001 }], _craft_recipe: {},
  } },
];
misplacedMaterialState.uid_counter = 157;
misplacedMaterialState.spawn_seed = springSeed;
misplacedMaterialState.spawn_sequence = 0;
misplacedMaterialState.meridian_acupoints = [{
  item_ids: [27001], items: [{ item_id: 27001 }], completed: false,
}];
const outstandingMisplaced = (engine as any).getOutstandingOrderItemCounts(misplacedMaterialState);
assert.equal(outstandingMisplaced.get(9001), 1);
// The same material in a compatible furnace does satisfy the demand.
misplacedMaterialState.grid[1].id = 17002;
assert.equal((engine as any).getOutstandingOrderItemCounts(misplacedMaterialState).has(9001), false);
misplacedMaterialState.grid[1].craft._craft_stored.push({ id: 3001 });
assert.equal((engine as any).getOutstandingOrderItemCounts(misplacedMaterialState).get(9001), 1);
misplacedMaterialState.grid[1].id = 18002;
misplacedMaterialState.grid[1].craft._craft_stored = [{ id: 9001 }];
misplacedMaterialState.grid.push({ uid: 158, id: 5001, col: 2, row: 0 });
engine.refreshStaminaMultiplierFromBalance(misplacedMaterialState);
const misplacedMaterialSpawn = engine.executeSpawn(misplacedMaterialState, 0, 0, 0, 4);
assert.equal(misplacedMaterialSpawn.ok, true);
if (misplacedMaterialSpawn.ok) {
  assert.equal(misplacedMaterialSpawn.spawnedId, 9001);
  assert.equal(misplacedMaterialSpawn.staminaCost, 1);
  assert.equal(misplacedMaterialSpawn.orderPriority, true);
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
unrelatedRollState.spawn_seed = 2;
unrelatedRollState.spawn_sequence = 0;
unrelatedRollState.meridian_acupoints = [{
  item_ids: [14101],
  items: [{ item_id: 14101 }],
  completed: false,
  breakthrough_order: true,
  breakthrough_level: 2,
}];
engine.refreshStaminaMultiplierFromBalance(unrelatedRollState);
// Only group 13 is available here; group 14 must not be prioritized.
const unrelatedLauncher = engine.getItemData(16001)!;
const originalUnrelatedSpawns = unrelatedLauncher.spawns;
unrelatedLauncher.spawns = [{ id: 13101, weight: 1 }];
const unrelatedRollSpawn = engine.executeSpawn(unrelatedRollState, 0, 0, 0, 4);
unrelatedLauncher.spawns = originalUnrelatedSpawns;
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
// Keep nested-recipe coverage independent of the live recipe table.
const originalRecipes = (engine as any).recipes;
(engine as any).recipes = [
  { id: 32, result: 27081, ingredients: [27002, 9004] },
  { id: 2, result: 27002, ingredients: [5002, 9002] },
];
const originalTableRecipes = (engine as any).recipesByTable.get(17001);
(engine as any).recipesByTable.set(17001, (engine as any).recipes);
const storedIntermediateOutstanding = (engine as any).getOutstandingOrderItemCounts(
  storedIntermediateState,
) as Map<number, number>;
(engine as any).recipes = originalRecipes;
(engine as any).recipesByTable.set(17001, originalTableRecipes);
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

// Repeated current-schema order slots must be prioritized independently.
for (const order of [{ item_ids: [9001, 9001], completed: false }]) {
  const state = stateAt(400);
  state.grid = [{uid: 600, id: 12004, col: 0, row: 0, charges: 5}];
  state.uid_counter = 600;
  state.meridian_acupoints = [order];
  const launcher = engine.getItemData(12004)!;
  const totalWeight = launcher.spawns!.reduce((total, spawn) => total + spawn.weight, 0);
  let seed = 1;
  while (deterministicSpawnRoll(seed, 0, 600, totalWeight) < launcher.spawns![0].weight) seed++;
  state.spawn_seed = seed;
  state.spawn_sequence = 0;
  engine.refreshStaminaMultiplierFromBalance(state);
  for (let sequence = 0; sequence < 3; sequence++) {
    const result = engine.executeSpawn(state, 0, 0, sequence, 4);
    assert.ok(result.ok);
    if (!result.ok) throw new Error(result.reason);
    assert.equal(result.orderPriority, sequence < 2);
    assert.equal(result.staminaCost, sequence < 2 ? 1 : 4);
    assert.equal(result.staminaRefund, sequence < 2 ? 3 : 0);
    if (sequence < 2) assert.equal(result.spawnedId, 9001);
  }
}

console.log("STAMINA_MULTIPLIER_SMOKE_OK thresholds=true realm_caps=true normalization=true refresh=true spawn_upgrade=true order_priority=true refund=true cap=true restrictions=true duplicate_order_counts=true");
