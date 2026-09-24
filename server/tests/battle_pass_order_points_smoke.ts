import assert from "node:assert/strict";
import { BattlePassService } from "../src/engine/battle_pass";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const config: any = structuredClone(gameConfigTables.battlePass);
const activities: any = structuredClone(gameConfigTables.activities);
const activity = activities.activities.find((entry: any) => entry.id === config.passes[0].activity_id);
activity.enabled = true;
activity.start_time = "2026-09-22T00:00:00Z";
activity.end_time = "2999-01-01T00:00:00Z";
const service = new BattlePassService(config, activities, gameConfigTables.tokens, gameConfigTables.gameConfig);
const state: any = { spirit_stones: 700, pending_rewards: [] };
const start = Date.parse(activity.start_time);
const end = Date.parse(activity.end_time);

assert.equal(service.awardOrderPoints(state, 95, "", start), true);
assert.equal(state.battle_pass_progress[4].points, 9);
assert.equal(service.awardOrderPoints(state, 5, "", start + 1), false);
assert.equal(state.battle_pass_progress[4].points, 9);
assert.equal(service.awardOrderPoints(state, 100, "", start + 2), true);
assert.equal(state.battle_pass_progress[4].points, 19);
assert.equal(service.awardOrderPoints(state, 100, "", start - 1), false);
assert.equal(service.awardOrderPoints(state, 100, "", end), false);

const engine = new GameEngine({ ...gameConfigTables, activities });
const completedOrderState: any = engine.createInitialState();
completedOrderState.meridian_acupoints = [{
  item_id: 5001,
  name: "测试订单",
  count: 1,
  completed: false,
  total_value: 200,
}];
completedOrderState.grid.push({ uid: completedOrderState.uid_counter + 1, id: 5001, col: 6, row: 8 });
const completedOrder = engine.completeMeridianAcupoint(completedOrderState, 0, [5001], "order-test-once");
assert.equal(completedOrder.ok, true);
assert.equal(completedOrderState.battle_pass_progress[4].points, 20);
assert.equal(service.awardOrderPoints(completedOrderState, 200, "order-test-once"), false);
assert.equal(completedOrderState.battle_pass_progress[4].points, 20);
const invalidOrder = engine.completeMeridianAcupoint(completedOrderState, 99, [5001]);
assert.equal(invalidOrder.ok, false);
assert.equal(completedOrderState.battle_pass_progress[4].points, 20);

const applied: any[] = [];
const apply = (reward: any): any => { applied.push(structuredClone(reward)); return reward; };
assert.equal(service.claim(state, 4, 2, "free", apply, start + 3).reason, "insufficient_points");
assert.equal(service.claim(state, 4, 1, "premium", apply, start + 3).reason, "premium_not_unlocked");
const firstFree = service.claim(state, 4, 1, "free", apply, start + 3);
assert.equal(firstFree.ok, true);
assert.equal(service.claim(state, 4, 1, "free", apply, start + 3).reason, "already_claimed");
const insufficient = { ...state, spirit_stones: 499 };
assert.equal(service.unlock(insufficient, 4, start + 4).reason, "insufficient_spirit_stones");
assert.equal(insufficient.spirit_stones, 499);
assert.equal(service.unlock(state, 4, start + 4).ok, true);
assert.equal(state.spirit_stones, 200);
assert.equal(service.unlock(state, 4, start + 5).ok, true);
assert.equal(state.spirit_stones, 200);

assert.equal(service.settleExpired(state, apply, end), true);
assert.deepEqual(state.battle_pass_progress[4].free_claimed_levels.sort((a: number, b: number) => a - b), [1]);
assert.deepEqual(state.battle_pass_progress[4].premium_claimed_levels.sort((a: number, b: number) => a - b), [1]);
assert.equal(applied.length, 2);
assert.equal(service.settleExpired(state, apply, end + 1), false);
assert.equal(applied.length, 2);
assert.equal(service.claim(state, 4, 2, "free", apply, end + 1).reason, "activity_inactive");
console.log("battle_pass_order_points_smoke: ok");
