import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine({
  ...gameConfigTables,
  cultivation: {
    stages: [
      { name: "起始", exp: 30, max_qi: 1000, breakthrough_items: [
        { item_id: 5001, count: 2 },
        { item_id: 5002, count: 1 },
      ] },
      { name: "下一层", exp: 999, max_qi: 2000 },
    ],
  },
});

const completeState: any = engine.createInitialState();
completeState.grid = [{ uid: 101, id: 5001, col: 0, row: 0 }];
completeState.pouch = [
  { uid: 102, id: 5001 },
  { uid: 103, id: 5002 },
];
completeState.cultivation.current_exp = 30;
const completed = engine.executeTryBreakthrough(completeState, 0, 1, 30);
assert.equal(completed.ok, true);
assert.equal(completeState.cultivation.current_level, 2);
assert.deepEqual(completeState.grid, []);
assert.deepEqual(completeState.pouch, []);

const blockedState: any = engine.createInitialState();
blockedState.grid = [{ uid: 201, id: 5001, col: 0, row: 0 }];
blockedState.pouch = [{ uid: 202, id: 5002 }];
blockedState.cultivation.current_exp = 30;
const beforeGrid = structuredClone(blockedState.grid);
const beforePouch = structuredClone(blockedState.pouch);
const blocked = engine.executeTryBreakthrough(blockedState, 0, 1, 30);
assert.equal(blocked.ok, false);
if (blocked.ok) throw new Error("expected breakthrough to be rejected");
assert.equal(blocked.reason, "breakthrough_items_insufficient");
assert.deepEqual(blockedState.grid, beforeGrid);
assert.deepEqual(blockedState.pouch, beforePouch);
assert.equal(blockedState.cultivation.current_level, 1);

const orderState: any = engine.createInitialState();
orderState.meridian_acupoints = [
  { item_ids: [9991], completed: false },
  { item_ids: [9992], completed: false },
];
engine.applyRewards(orderState, { tokens: [{ token: 4, amount: 30 }], items: [] });
assert.equal(orderState.meridian_acupoints.length, 1);
assert.equal(orderState.meridian_acupoints[0].breakthrough_order, true);
assert.equal(orderState.meridian_acupoints[0].breakthrough_level, 1);
assert.deepEqual(orderState.meridian_acupoints[0].item_ids, [5001, 5001, 5002]);

orderState.cultivation.current_qi = orderState.cultivation.max_qi;
orderState.grid = [
  { uid: 301, id: 5001, col: 0, row: 0 },
  { uid: 302, id: 5001, col: 1, row: 0 },
  { uid: 303, id: 5002, col: 2, row: 0 },
];
const orderCompleted = engine.completeMeridianAcupoint(orderState, 0, [5001, 5001, 5002]);
assert.equal(orderCompleted.ok, false);
if (orderCompleted.ok) throw new Error("expected breakthrough order to require confirmation");
assert.equal(orderCompleted.reason, "breakthrough_confirmation_required");
assert.equal(orderState.cultivation.current_level, 1);
assert.equal(orderState.grid.length, 3);

const confirmedOrderBreakthrough = engine.executeTryBreakthrough(orderState, 0, 1, 30);
assert.equal(confirmedOrderBreakthrough.ok, true);
assert.equal(orderState.cultivation.current_level, 2);
assert.deepEqual(orderState.grid, []);
assert.equal(orderState.meridian_acupoints.some((order: any) => order.breakthrough_order === true), false);

console.log("BREAKTHROUGH_ITEMS_SERVER_SMOKE_OK");
