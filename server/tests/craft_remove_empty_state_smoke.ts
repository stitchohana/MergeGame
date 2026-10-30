import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const state: any = engine.createInitialState();
state.grid = [{
  uid: 1,
  id: 17001,
  col: 0,
  row: 0,
  craft: {
    _craft_init: true,
    _craft_state: 1,
    _craft_stored: [{ id: 5001 }],
    _craft_recipe: {},
    _craft_progress: 0,
    _craft_result_id: -1,
    _craft_start_time: 0,
  },
}];

const result = engine.removeIngredientFromTable(state, 0, 0, 5001, 1, 0);
assert.equal(result.ok, true);
assert.equal(state.grid[0].craft._craft_stored.length, 0);
assert.equal(state.grid[0].craft._craft_state, 0);
assert.deepEqual(state.grid[0].craft._craft_recipe, {});

console.log("CRAFT_REMOVE_EMPTY_STATE_SERVER_SMOKE_OK");
