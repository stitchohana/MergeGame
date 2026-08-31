import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const homeConfig: any = gameConfigTables.homeMeridians;

const tutorialRewards = homeConfig.stages[0].acupoint_rewards;
assert.equal(Array.isArray(tutorialRewards), true);
assert.deepEqual(
  tutorialRewards.map((reward: any) => reward.items?.[0]?.id),
  [12001, 17001, 16001],
);
assert.deepEqual(
  tutorialRewards.map((reward: any) => reward.tokens?.find((token: any) => token.token === 4)?.amount),
  [10, 10, 10],
);

const state: any = engine.createInitialState();
state.cultivation.current_level = 2;
state.cultivation.current_exp = 0;
state.cultivation.current_qi = 10000;

for (let acupointIndex = 0; acupointIndex < 10; acupointIndex += 1) {
  const result = engine.lightHomeAcupoint(state, 1, acupointIndex);
  assert.equal(result.ok, true);
  if (!result.ok) throw new Error(`acupoint ${acupointIndex} failed: ${result.reason}`);
  assert.equal(result.circulation_completed, acupointIndex === 9);
  if (acupointIndex === 0) {
    assert.deepEqual(
      state.pending_rewards.map((reward: any) => reward.id),
      [14001, 19001],
    );
  }
}

assert.equal(state.cultivation.current_exp, 56);
assert.equal(engine.isBreakthroughReady(2, state.cultivation.current_exp), true);
assert.deepEqual(
  state.pending_rewards.map((reward: any) => reward.id),
  [14001, 19001, 11001, 12001, 11001, 17001],
);

console.log("HOME_MERIDIAN_EXP_SERVER_SMOKE_OK");
