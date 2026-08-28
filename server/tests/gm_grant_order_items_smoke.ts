import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { grantCurrentOrderItems } from "../src/routes/gm";

const engine = new GameEngine(gameConfigTables);

const state: any = engine.createInitialState();
state.meridian_acupoints = [
  { completed: false, item_ids: [5001, 9001, 5001, 999999] },
  { completed: true, item_ids: [5002] },
  { completed: false, item_ids: [6001] },
];
const beforePending = state.pending_rewards.length;
const beforeGrid = state.grid.length;
const result = grantCurrentOrderItems(state, engine);
assert.equal(result.error, undefined);
assert.equal(result.grantedCount, 4);
assert.equal(result.itemCounts["5001"], 2);
assert.equal(result.itemCounts["9001"], 1);
assert.equal(result.itemCounts["6001"], 1);
assert.equal(state.pending_rewards.length, beforePending);
assert.equal(state.grid.length, beforeGrid + 4);
assert.equal(new Set(state.grid.map((item: any) => item.uid)).size, state.grid.length);
assert.deepEqual(
  state.grid.slice(-4).map((item: any) => item.id),
  [5001, 9001, 5001, 6001],
);

const fullState: any = engine.createInitialState();
fullState.uid_counter = 1000;
for (let row = 0; row < engine.GRID_ROWS; row += 1) {
  for (let col = 0; col < engine.GRID_COLS; col += 1) {
    if (!fullState.grid.some((item: any) => item.col === col && item.row === row)) {
      fullState.grid.push({ uid: fullState.uid_counter++, id: 5001, col, row });
    }
  }
}
fullState.meridian_acupoints = [{ completed: false, item_ids: [5001] }];
const fullResult = grantCurrentOrderItems(fullState, engine);
assert.equal(fullResult.error, "grid_full");
assert.equal(fullResult.grantedCount, 0);
assert.equal(fullState.grid.length, engine.MAX_CELLS);

console.log("GM_GRANT_ORDER_ITEMS_SMOKE_OK");
