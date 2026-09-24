import assert from "node:assert/strict";
import { BattlePassService } from "../src/engine/battle_pass";
import { gameConfigTables } from "../src/worker/config_data";

const service = new BattlePassService(gameConfigTables.battlePass, gameConfigTables.activities, gameConfigTables.tokens, gameConfigTables.gameConfig);
const definitions = service.getDefinitions();
assert.equal(definitions.length, 1);
assert.equal(definitions[0].activity_id, 4);
assert.equal(definitions[0].points_token_id, 5);
assert.equal(gameConfigTables.gameConfig.battle_pass.points_per_value, 0.1);
assert.equal(gameConfigTables.gameConfig.battle_pass.premium_unlock_cost, 500);
assert.equal(definitions[0].tiers.length, 50);
assert.equal(definitions[0].tiers[49].required_points, 500);
assert.equal(service.getDefinition(4)?.tiers[0].free_rewards.tokens?.[0].amount, 10);
assert.equal(service.getDefinition(4)?.tiers[0].premium_rewards.tokens?.[0].amount, 10);
assert.equal(service.isActive(4, Date.parse("2026-08-31T23:59:59+08:00")), false);
assert.equal(service.isActive(4, Date.parse("2026-09-01T00:00:00+08:00")), true);
assert.equal(service.isActive(4, Date.parse("2026-09-30T23:59:59+08:00")), true);
assert.equal(service.isActive(4, Date.parse("2026-10-01T00:00:00+08:00")), false);

const cloneConfig = (): any => structuredClone(gameConfigTables.battlePass);
assert.throws(() => new BattlePassService({ passes: [...cloneConfig().passes, ...cloneConfig().passes] }, gameConfigTables.activities, gameConfigTables.tokens, gameConfigTables.gameConfig), /only_one/);
assert.throws(() => new BattlePassService({ passes: [{ ...cloneConfig().passes[0], activity_id: 999 }] }, gameConfigTables.activities, gameConfigTables.tokens, gameConfigTables.gameConfig), /activity_not_found/);
assert.throws(() => new BattlePassService({ passes: [{ ...cloneConfig().passes[0], points_token_id: 999 }] }, gameConfigTables.activities, gameConfigTables.tokens, gameConfigTables.gameConfig), /token_not_found/);
assert.throws(() => new BattlePassService(cloneConfig(), gameConfigTables.activities, gameConfigTables.tokens, { battle_pass: { premium_unlock_cost: -1 } }), /invalid_unlock_cost/);
assert.throws(() => new BattlePassService(cloneConfig(), gameConfigTables.activities, gameConfigTables.tokens, { battle_pass: { premium_unlock_cost: 500, points_per_value: 0 } }), /invalid_points_per_value/);
const activeActivities: any = structuredClone(gameConfigTables.activities);
const activePass = activeActivities.activities.find((entry: any) => entry.id === 4);
activePass.enabled = true;
activePass.start_time = "2026-01-01T00:00:00Z";
activePass.end_time = "2999-01-01T00:00:00Z";
const doubledRate = new BattlePassService(cloneConfig(), activeActivities, gameConfigTables.tokens, {
  battle_pass: { premium_unlock_cost: 500, points_per_value: 0.2 },
});
const rateState: any = { spirit_stones: 500 };
assert.equal(doubledRate.awardOrderPoints(rateState, 95, "", Date.parse(activePass.start_time)), true);
assert.equal(rateState.battle_pass_progress[4].points, 19);
console.log("battle_pass_config_smoke: ok");
