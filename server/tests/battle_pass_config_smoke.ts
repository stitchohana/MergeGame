import assert from "node:assert/strict";
import { BattlePassService } from "../src/engine/battle_pass";
import { gameConfigTables } from "../src/worker/config_data";

const service = new BattlePassService(gameConfigTables.battlePass, gameConfigTables.activities, gameConfigTables.tokens, gameConfigTables.gameConfig);
const definitions = service.getDefinitions();
assert.equal(definitions.length, 1);
assert.equal(definitions[0].activity_id, 4);
assert.equal(definitions[0].points_token_id, 5);
assert.equal(Number(gameConfigTables.gameConfig.battle_pass.points_per_value), 0.1);
assert.equal(Number(gameConfigTables.gameConfig.battle_pass.premium_unlock_cost), 500);
assert.equal(definitions[0].tiers.length, 50);
assert.equal(definitions[0].tiers[49].required_points, 500);
assert.equal(service.getDefinition(4)?.tiers[0].free_rewards.tokens?.[0].amount, 10);
assert.equal(service.getDefinition(4)?.tiers[0].premium_rewards.tokens?.[0].amount, 10);
const rewards = definitions[0].tiers.flatMap(tier => [tier.free_rewards, tier.premium_rewards]);
assert.equal(rewards.filter(reward => reward.tokens?.[0]?.token === 3).length, 50);
assert.equal(rewards.filter(reward => reward.items?.[0]?.id === 1701).length, 50);
for (const tier of definitions[0].tiers) {
  const expected = tier.level % 2 === 0
    ? { items: [{ id: 1701, count: 1 }] }
    : { tokens: [{ token: 3, amount: 10 }] };
  assert.deepEqual(tier.free_rewards, expected);
  assert.deepEqual(tier.premium_rewards, expected);
}
assert.equal(gameConfigTables.activities.activities.find((entry: any) => entry.id === 4)?.cycle, 3);
assert.equal(service.isActive(4, Date.parse("2026-08-31T23:59:59+08:00")), true);
assert.equal(service.isActive(4, Date.parse("2026-09-01T00:00:00+08:00")), true);
assert.equal(service.isActive(4, Date.parse("2026-09-30T23:59:59+08:00")), true);
assert.equal(service.isActive(4, Date.parse("2026-10-01T00:00:00+08:00")), true);

const monthEnd = Date.parse("2026-09-30T23:59:59+08:00");
const monthStart = Date.parse("2026-10-01T00:00:00+08:00");
assert.equal(service.getPeriodKey(monthEnd), "2026-09");
assert.equal(service.getPeriodKey(monthStart), "2026-10");
const boundaryState: any = { battle_pass_progress: {
  4: { points: 120, premium_unlocked: true, free_claimed_levels: [1], premium_claimed_levels: [1], period_key: "2026-09" },
} };
service.ensureProgress(boundaryState, monthEnd);
assert.equal(boundaryState.battle_pass_progress[4].points, 120);
service.ensureProgress(boundaryState, monthStart);
assert.deepEqual(boundaryState.battle_pass_progress[4], {
  points: 0,
  premium_unlocked: false,
  free_claimed_levels: [],
  premium_claimed_levels: [],
  period_key: "2026-10",
});
assert.equal(service.awardOrderPoints(boundaryState, 100, "october-order", monthStart), true);
assert.equal(boundaryState.battle_pass_progress[4].points, 10);

const monthlyState: any = { battle_pass_progress: {
  4: { points: 120, premium_unlocked: true, free_claimed_levels: [1], premium_claimed_levels: [1], period_key: "2026-09" },
} };
service.ensureProgress(monthlyState, Date.parse("2026-10-08T12:00:00+08:00"));
assert.deepEqual(monthlyState.battle_pass_progress[4], {
  points: 0,
  premium_unlocked: false,
  free_claimed_levels: [],
  premium_claimed_levels: [],
  period_key: "2026-10",
});

const cloneConfig = (): any => structuredClone(gameConfigTables.battlePass);
assert.throws(() => new BattlePassService({ passes: [...cloneConfig().passes, ...cloneConfig().passes] }, gameConfigTables.activities, gameConfigTables.tokens, gameConfigTables.gameConfig), /only_one/);
assert.throws(() => new BattlePassService({ passes: [{ ...cloneConfig().passes[0], activity_id: 999 }] }, gameConfigTables.activities, gameConfigTables.tokens, gameConfigTables.gameConfig), /activity_not_found/);
assert.throws(() => new BattlePassService({ passes: [{ ...cloneConfig().passes[0], points_token_id: 999 }] }, gameConfigTables.activities, gameConfigTables.tokens, gameConfigTables.gameConfig), /token_not_found/);
assert.throws(() => new BattlePassService(cloneConfig(), gameConfigTables.activities, gameConfigTables.tokens, { battle_pass: { premium_unlock_cost: -1 } }), /invalid_unlock_cost/);
assert.throws(() => new BattlePassService(cloneConfig(), gameConfigTables.activities, gameConfigTables.tokens, { battle_pass: { premium_unlock_cost: 500, points_per_value: 0 } }), /invalid_points_per_value/);
const activeActivities: any = structuredClone(gameConfigTables.activities);
const activePass = activeActivities.activities.find((entry: any) => entry.id === 4);
activePass.enabled = true;
activePass.cycle = 0;
activePass.start_time = "2026-01-01T00:00:00Z";
activePass.end_time = "2999-01-01T00:00:00Z";
const doubledRate = new BattlePassService(cloneConfig(), activeActivities, gameConfigTables.tokens, {
  battle_pass: { premium_unlock_cost: 500, points_per_value: 0.2 },
});
const rateState: any = { spirit_stones: 500 };
assert.equal(doubledRate.awardOrderPoints(rateState, 95, "", Date.parse(activePass.start_time)), true);
assert.equal(rateState.battle_pass_progress[4].points, 19);
console.log("battle_pass_config_smoke: ok");
