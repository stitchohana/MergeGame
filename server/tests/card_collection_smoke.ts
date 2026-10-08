import assert from "node:assert/strict";
import { CardCollectionService } from "../src/engine/card_collection";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { QuestType } from "../src/storage/interface";

const engine = new GameEngine(gameConfigTables);
const activities = structuredClone(gameConfigTables.activities.activities);
const config = structuredClone(gameConfigTables.cardCollection);
for (const random of [0, 0.999999999]) {
  const service = new CardCollectionService(config, activities, () => random);
  for (let star = 1; star <= 5; star++) {
    const state = engine.createInitialState();
    const progress = service.ensureProgress(state)[1];
    progress.packs[star] = 2;
    const result = service.open(state, 1, star, "first", 0);
    assert.equal(result.ok, true);
    if (!result.ok) throw new Error(result.reason);
    assert.equal(result.cards!.length, star + 1);
    assert.equal(result.cards![0].star, star);
    assert.equal(progress.packs[star], 1);
    assert.equal(progress.opened_count, 1);
    const after = JSON.stringify(state);
    assert.deepEqual(service.open(state, 1, star, "first", 0), result);
    assert.equal(JSON.stringify(state), after);
    assert.deepEqual(service.open(state, 1, star, "different", 0), { ok: false, reason: "state_conflict" });
    assert.deepEqual(service.open(state, 1, star, "first", 1), { ok: false, reason: "request_mismatch" });
    assert.deepEqual(service.open(state, 1, star, "second", 1).ok, true);
    assert.deepEqual(service.open(state, 1, star, "third", 2), { ok: false, reason: "insufficient_packs" });
    assert.equal(Object.values(progress.cards).reduce((a, b) => a + b, 0), 2 * (star + 1));
    assert.equal(service.publicProgress(JSON.parse(JSON.stringify(state)))[1].last_open!.cards!.length, star + 1);
  }
}
const single = structuredClone(config);
single.packs.forEach(p => { p.card_count = 1; p.normal_weights = []; });
const singles = new CardCollectionService(single, activities, () => 0);
for (let star = 1; star <= 5; star++) {
  const state = engine.createInitialState(); singles.ensureProgress(state)[1].packs[star] = 1;
  const result = singles.open(state, 1, star, "single", 0);
  assert.ok(result.ok && result.cards!.length === 1 && result.cards![0].star === star);
}
const invalid = structuredClone(config); invalid.cards = invalid.cards.filter(c => c.star !== 5);
assert.throws(() => new CardCollectionService(invalid, activities), /empty.*pool/);
const badWeights = structuredClone(config); badWeights.packs[0].normal_weights = [0,0,0,0,0];
assert.throws(() => new CardCollectionService(badWeights, activities), /invalid weights/);

const service = engine.cardCollectionService;
const state = engine.createInitialState(); const progress = service.ensureProgress(state)[1];
assert.deepEqual(service.claim(state, 1, 1, "claim", r => engine.applyRewards(state, r)), {ok:false,reason:"set_incomplete"});
for (const card of config.cards.filter(c => c.set_id === 1)) progress.cards[card.card_id] = 1;
const beforeStamina = state.stamina; const beforeStones = state.spirit_stones;
const claimed = service.claim(state, 1, 1, "claim", r => engine.applyRewards(state, r));
assert.ok(claimed.ok); assert.equal(state.stamina, beforeStamina + 300); assert.equal(state.spirit_stones, beforeStones + 1000);
assert.deepEqual(service.claim(state, 1, 1, "claim", () => { throw new Error("reapplied"); }), claimed);
assert.deepEqual(service.claim(state, 1, 1, "claim2", r => r), {ok:false,reason:"already_claimed"});
assert.equal(Object.keys(progress.cards).length, 5);

const disabledActivities = structuredClone(activities); disabledActivities.find(a => a.id === 5)!.enabled = false;
const disabled = new CardCollectionService(config, disabledActivities);
progress.packs[1] = 1;
const disabledBefore = JSON.stringify(state);
disabled.awardSource(state, "order", 0, 900);
assert.deepEqual(disabled.open(state, 1, 1, "disabled", 0), {ok:false,reason:"activity_inactive"});
assert.equal(JSON.stringify(state), disabledBefore);

const overrides = structuredClone(config);
overrides.source_rewards.push({collection_id:1,source_type:"quest",source_id:999,min_value:0,pack_id:1,count:1,enabled:false} as any);
const overrideService = new CardCollectionService(overrides, activities);
const excluded = engine.createInitialState();
overrideService.awardSource(excluded, "quest", 999, 100);
assert.deepEqual(overrideService.ensureProgress(excluded)[1].packs, {});
const scheduled = structuredClone(activities);
Object.assign(scheduled.find(a => a.id === 5)!, {start_time:"2026-10-01T00:00:00Z",end_time:"2026-11-01T00:00:00Z"});
const scheduledService = new CardCollectionService(config, scheduled);
assert.equal(scheduledService.isActive(1, Date.parse("2026-10-01T00:00:00Z") - 1), false);
assert.equal(scheduledService.isActive(1, Date.parse("2026-10-01T00:00:00Z")), true);
assert.equal(scheduledService.isActive(1, Date.parse("2026-11-01T00:00:00Z")), false);
// Receipt eviction must not allow an old open request to spend another pack.
const historyState = engine.createInitialState();
const historyProgress = service.ensureProgress(historyState)[1]; historyProgress.packs[1] = 40;
for (let i=0;i<33;i++) assert.equal(service.open(historyState,1,1,`history-${i}`,i).ok,true);
assert.equal(historyProgress.recent_operations.length,32);
assert.deepEqual(service.open(historyState,1,1,"history-0",0),{ok:false,reason:"state_conflict"});
assert.equal(historyProgress.packs[1],7);

// Source integration: task completion (not claiming), both auto/manual rewards and reset.
const questTables = structuredClone(gameConfigTables);
questTables.quests.quests = [
  {id:9991,type:QuestType.MERGE,name:"manual",description:"",target_count:1,rewards:1,auto_reward:false,reset_cycle:1},
  {id:9992,type:QuestType.MERGE,name:"auto",description:"",target_count:10,rewards:1,auto_reward:true,reset_cycle:0},
];
const questEngine = new GameEngine(questTables); const questState = questEngine.createInitialState();
questEngine.questEngine.incrementQuestProgress(questState, QuestType.MERGE, 10, questEngine);
assert.equal(questState.card_collection_progress![1].packs[1], 1);
assert.equal(questState.card_collection_progress![1].packs[2], 1);
questEngine.questEngine.incrementQuestProgress(questState, QuestType.MERGE, 10, questEngine);
questEngine.questEngine.claimQuestReward(questState, 9991, questEngine);
assert.equal(questState.card_collection_progress![1].packs[1], 1);
questState.quest_last_reset = Date.now() - 86400000 * 2;
questEngine.questEngine.incrementQuestProgress(questState, QuestType.MERGE, 1, questEngine);
assert.equal(questState.card_collection_progress![1].packs[1], 2);
assert.equal(questState.card_collection_progress![1].packs[2], 1);

const orderState = engine.createInitialState();
orderState.meridian_acupoints = [{item_id:5001,count:1,name:"order",completed:false,total_value:200} as any];
orderState.grid.push({uid:9999,id:5001,col:6,row:8});
assert.equal(engine.completeMeridianAcupoint(orderState, 0, []).ok, false);
assert.equal(engine.completeMeridianAcupoint(orderState, 0, [5001], "order-once").ok, true);
assert.equal(orderState.card_collection_progress![1].packs[2], 1);
assert.equal(engine.completeMeridianAcupoint(orderState, 0, [5001], "order-once").ok, false);
assert.equal(orderState.card_collection_progress![1].packs[2], 1);

const circulationState = engine.createInitialState();
circulationState.home_meridian_progress = [{stage:0,lit:new Array(engine.getHomeMeridianDefs()[0].acupoints).fill(true),circulation_completed:false}];
assert.equal(engine.runHomeMeridianCirculation(circulationState, 0).ok, true);
assert.equal(circulationState.card_collection_progress![1].packs[3], 1);
assert.equal(engine.runHomeMeridianCirculation(circulationState, 0).ok, false);
assert.equal(circulationState.card_collection_progress![1].packs[3], 1);
console.log("card_collection_smoke: ok");
