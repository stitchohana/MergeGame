import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const tableCraft = {
  _craft_init: true,
  _craft_state: 1,
  _craft_stored: [{ id: 5002 }],
  _craft_recipe: {},
  _craft_progress: 0,
  _craft_result_id: -1,
  _craft_start_time: 0,
};

const blockedState: any = {
  grid: [
    { uid: 1, id: 17001, col: 0, row: 0, craft: tableCraft },
    { uid: 2, id: 17001, col: 1, row: 0, craft: { ...tableCraft, _craft_stored: [] } },
  ],
  version: 1,
};
const blocked = engine.validateMerge(blockedState, 0, 0, 1, 0);
assert.deepEqual(blocked, { valid: false, reason: "craft_table_has_materials" });

const cleanState: any = {
  grid: blockedState.grid.map((item: any) => ({ ...item, craft: { ...item.craft, _craft_stored: [] } })),
  version: 1,
};
assert.equal(engine.validateMerge(cleanState, 0, 0, 1, 0).valid, true);

console.log("MERGE_CRAFTING_TABLE_SERVER_SMOKE_OK blocked_with_material=true");
