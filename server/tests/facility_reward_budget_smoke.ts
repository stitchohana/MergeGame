import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const definitions = new Map([...gameConfigTables.items.launcher, ...gameConfigTables.items.crafting].map(item => [item.id, item]));
const checkpoints = new Map([[10, 4], [13, 8], [16, 12], [19, 16], [20, 16]]);
const state = engine.createInitialState();
assert.deepEqual(state.grid.filter(item => gameConfigTables.items.launcher.some(def => def.id === item.id)).map(item => item.id), [11001]);
// Keep the simulation focused on facilities, receiving guaranteed items
// in chronological order and using the real server merge operation.
state.grid = state.grid.filter(item => definitions.has(item.id));
let nextUid = 100000;
let merges = 0;
let peakFacilities = state.grid.length;
const receive = (items: any[]) => {
  for (const reward of items) {
    if (!definitions.has(reward.id)) continue;
    for (let copy = 0; copy < (reward.count ?? 1); copy++) {
      const position = engine.findEmptyPos(state.grid);
      assert.ok(position, "facility rewards must fit after merging");
      state.grid.push({uid: nextUid++, id: reward.id, ...position});
      peakFacilities = Math.max(peakFacilities, state.grid.length);
      while (true) {
        const first = state.grid.find(item => state.grid.some(other => other !== item && other.id === item.id));
        if (!first) break;
        const second = state.grid.find(item => item !== first && item.id === first.id)!;
        const result = engine.executeMerge(state, first.col, first.row, second.col, second.row);
        assert.equal(result.ok, true, `failed merge of ${first.id}`);
        merges++;
      }
    }
  }
};

for (let level = 1; level <= 20; level++) {
  state.cultivation.current_level = level;
  if (level > 1) {
    const previous = gameConfigTables.cultivation.stages[level - 2];
    const reward = (gameConfigTables.rewards.rewards as any)[String(previous.breakthrough_reward_id)];
    assert.deepEqual(reward?.items.filter((item: any) => Math.floor(item.id / 100) === 250), [{id: 25001, count: 1}], "each breakthrough retains one level-1 mine");
    receive(reward?.items ?? []);
  }
  const cap = level <= 10 ? 4 : level <= 13 ? 8 : level <= 16 ? 12 : 16;
  for (const stage of gameConfigTables.homeMeridians.stages.filter(stage => stage.cultivation_level === level)) {
    receive(stage.circulation_reward.items);
    for (const item of state.grid.filter(item => Math.floor(item.id / 100) !== 250)) assert.ok(definitions.get(item.id)!.level <= cap, `early excess at ${stage.name}`);
  }
  const expected = checkpoints.get(level);
  if (!expected) continue;
  const families = level === 10 ? [110, 120, 130, 150, 160, 170, 180]
    : [110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 210, 230, 240];
  assert.deepEqual(state.grid.filter(item => Math.floor(item.id / 100) !== 250).map(item => item.id).sort((a, b) => a - b), families.map(family => family * 100 + expected));
  const mineLevels = new Map([[10, [1, 4]], [13, [3, 4]], [16, [1, 2, 3, 4]], [19, [2, 5]], [20, [1, 2, 5]]]);
  assert.deepEqual(state.grid.filter(item => Math.floor(item.id / 100) === 250).map(item => definitions.get(item.id)!.level).sort((a, b) => a - b), mineLevels.get(level));
  console.log(JSON.stringify({level, merged_level: expected, facilities: state.grid.length}));
}
assert.ok(merges > 0);
console.log("FACILITY_REWARD_BUDGET_SMOKE_OK", {peakFacilities});
