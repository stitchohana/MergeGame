import assert from "node:assert/strict";
import { GameEngine, TableState } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);

const initial = engine.createInitialState();
for (const item of initial.grid) {
  assert(initial.crafted_item_ids.includes(item.id), `initial item ${item.id} should be known`);
}
assert.equal(engine.recordItemDiscovery(initial, 3004), true);
assert.equal(engine.recordItemDiscovery(initial, 3004), false);
assert.equal(initial.crafted_item_ids.filter(id => id === 3004).length, 1);

const legacy = engine.createInitialState();
legacy.crafted_item_ids = [1002, 1002];
legacy.grid = [{ uid: 1, id: 13002, col: 0, row: 0 }];
legacy.pending_rewards = [{ uid: 2, id: 3004, name: "白石髓" }];
legacy.pouch = [{ uid: 3, id: 3001 }];
assert.equal(engine.initializeItemDiscoveries(legacy), true);
for (const id of [1002, 13002, 3004, 3001]) assert(legacy.crafted_item_ids.includes(id));
assert.equal(engine.initializeItemDiscoveries(legacy), false);

const spawned = engine.createInitialState();
spawned.grid = [{ uid: 1, id: 11001, col: 0, row: 0, charges: 5 }];
spawned.crafted_item_ids = [11001];
spawned.uid_counter = 1;
const spawn = engine.executeSpawn(spawned, 0, 0, 0);
assert(spawn.ok);
assert(spawned.crafted_item_ids.includes(spawn.spawnedId));

const merged = engine.createInitialState();
merged.grid = [
  { uid: 1, id: 1001, col: 0, row: 0 },
  { uid: 2, id: 1001, col: 1, row: 0 },
];
merged.crafted_item_ids = [1001];
merged.uid_counter = 2;
const merge = engine.executeMerge(merged, 0, 0, 1, 0);
assert(merge.ok);
assert(merged.crafted_item_ids.includes(merge.resultId));

const rewarded = engine.createInitialState();
assert(!rewarded.crafted_item_ids.includes(3004));
engine.applyRewards(rewarded, { items: [{ id: 3004, count: 2 }] });
assert.equal(rewarded.crafted_item_ids.filter(id => id === 3004).length, 1);

const crafted = engine.createInitialState();
crafted.grid = [{
  uid: 1, id: 17001, col: 0, row: 0,
  craft: {
    _craft_init: true, _craft_state: TableState.READY, _craft_stored: [],
    _craft_recipe: {}, _craft_progress: 1, _craft_result_id: 27002, _craft_start_time: 0,
  },
}];
crafted.crafted_item_ids = [17001];
crafted.uid_counter = 1;
const craft = engine.executeCraftRetrieve(crafted, 0, 0);
assert(craft.ok);
assert(crafted.crafted_item_ids.includes(craft.resultId));

console.log("ITEM_DISCOVERY_SMOKE_OK");
