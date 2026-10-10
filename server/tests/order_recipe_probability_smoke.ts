import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

function createEngine(probability?: unknown, omit = false): any {
  const config = structuredClone(gameConfigTables.gameConfig) as any;
  if (omit) delete config.orders;
  else config.orders = { recipe_product_probability: probability };
  return new GameEngine({ ...gameConfigTables, gameConfig: config });
}

function withRolls<T>(rolls: number[], action: () => T): T {
  const original = Math.random;
  let index = 0;
  Math.random = () => {
    assert.ok(index < rolls.length, "unexpected random draw");
    return rolls[index++];
  };
  try { return action(); } finally { Math.random = original; }
}

const log = console.log;
console.log = () => {};
try {
  const engine: any = new GameEngine(gameConfigTables);
  assert.equal(Number((gameConfigTables.gameConfig as any).orders?.recipe_product_probability), 0.8);
  const pool = [5004, 6004, 27001, 27002];
  const unequalCategoryWeights = new Map([[5004, 10000], [6004, 10000], [27001, 1], [27002, 3]]);
  const pick = (target: any, categoryRoll: number, itemRoll = 0, weights = unequalCategoryWeights) =>
    withRolls([0, categoryRoll, itemRoll], () => target._genOneAcupoint(pool, 1, 1, weights)).item_ids[0];

  assert.equal(pick(engine, 0.799), 27001);
  assert.equal(pick(engine, 0.8), 5004);
  assert.equal(pick(engine, 0.1, 0.249), 27001);
  assert.equal(pick(engine, 0.1, 0.25), 27002);
  assert.equal(pick(engine, 0.9, 0.499), 5004);
  assert.equal(pick(engine, 0.9, 0.5), 6004);
  assert.equal(pick(engine, 0.1, 0, new Map([[5004, 1], [6004, 1], [27001, 10000], [27002, 30000]])), 27001);

  assert.equal(pick(createEngine(0.25), 0.249), 27001);
  assert.equal(pick(createEngine(0.25), 0.25), 5004);
  assert.equal(pick(createEngine("0.8"), 0.799), 27001);
  assert.equal(pick(createEngine(0), 0), 5004);
  assert.equal(pick(createEngine(1), 0.999), 27001);
  assert.equal(pick(createEngine(-2), 0), 5004);
  assert.equal(pick(createEngine(2), 0.999), 27001);
  for (const target of [createEngine(undefined, true), createEngine("invalid"), createEngine(Infinity)]) {
    assert.equal(pick(target, 0.799), 27001);
    assert.equal(pick(target, 0.8), 5004);
  }

  assert.deepEqual(withRolls([0, 0], () => engine._genOneAcupoint([5004], 1, 1)).item_ids, [5004]);
  assert.deepEqual(withRolls([0, 0], () => engine._genOneAcupoint([27001], 1, 1)).item_ids, [27001]);
  assert.deepEqual(withRolls([0], () => engine._genOneAcupoint([], 0, 0)).item_ids, []);
  assert.deepEqual(withRolls([0, 0.1, 0, 0, 0], () =>
    engine._genOneAcupoint([5004, 6004, 27001], 3, 3)).item_ids, [27001, 5004, 6004]);

  const batch = withRolls([0, 0.1, 0, 0, 0.1, 0, 0, 0, 0, 0], () =>
    engine._generateRandomMeridianBatch(pool, unequalCategoryWeights, 4, 1, 1));
  const selected = batch.flatMap((order: any) => order.item_ids);
  assert.equal(selected.length, 4);
  assert.equal(new Set(selected).size, 4);
  assert.deepEqual(new Set(selected), new Set(pool));

  const initial = engine.createInitialState();
  const fixed = withRolls([], () => engine.generateMeridianRequirements(initial));
  assert.deepEqual(fixed.acupoints.map((order: any) => order.item_ids), [[5003], [5004], [6001]]);

  // A seeded sample avoids flaky results and checks the actual category draw.
  let seed = 4321;
  const originalRandom = Math.random;
  let productCount = 0;
  Math.random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 0x100000000;
  };
  try {
    for (let index = 0; index < 20000; index++) {
      if (engine._genOneAcupoint(pool, 1, 1, unequalCategoryWeights).item_ids[0] >= 27000) productCount++;
    }
  } finally { Math.random = originalRandom; }
  assert.ok(Math.abs(productCount / 20000 - 0.8) < 0.01, `observed ${productCount}/20000`);
  console.log = log;
  console.log(`ORDER_RECIPE_PROBABILITY_SMOKE_OK product_ratio=${productCount / 20000}`);
} finally { console.log = log; }
