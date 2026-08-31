import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { TokenType } from "../src/storage/interface";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);

const crossingState: any = engine.createInitialState();
crossingState.grid = [{ uid: 1, id: 5001, col: 0, row: 0 }];
crossingState.meridian_acupoints = [{
  item_ids: [5001],
  completed: false,
  fixed_order_rewards: true,
  rewards: { tokens: [{ token: TokenType.QI, amount: 10 }] },
}];
crossingState.cultivation.current_qi = crossingState.cultivation.max_qi - 1;

const crossed = engine.completeMeridianAcupoint(crossingState, 0, [5001]);
assert.equal(crossed.ok, true);
if (!crossed.ok) throw new Error(`expected completion success, got ${crossed.reason}`);
assert.equal(crossed.qi_gained, 10);
assert.equal(crossed.qi_full, true);
assert.equal(crossingState.cultivation.current_qi, crossingState.cultivation.max_qi + 9);
assert.deepEqual(crossingState.grid, []);

const overflowState: any = engine.createInitialState();
overflowState.grid = [{ uid: 2, id: 5001, col: 0, row: 0 }];
overflowState.meridian_acupoints = [{ item_ids: [5001], completed: false }];
overflowState.cultivation.current_qi = overflowState.cultivation.max_qi + 9;
const beforeGrid = structuredClone(overflowState.grid);
const beforeOrders = structuredClone(overflowState.meridian_acupoints);

const blocked = engine.completeMeridianAcupoint(overflowState, 0, [5001]);
assert.equal(blocked.ok, false);
if (blocked.ok) throw new Error("expected overflow completion to remain blocked");
assert.equal(blocked.reason, "qi_full");
assert.deepEqual(overflowState.grid, beforeGrid);
assert.deepEqual(overflowState.meridian_acupoints, beforeOrders);

console.log("QI_OVERFLOW_SERVER_SMOKE_OK");
