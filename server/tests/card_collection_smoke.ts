import assert from "node:assert/strict";
import { CardCollectionService } from "../src/engine/card_collection";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { QuestType } from "../src/storage/interface";

const engine = new GameEngine(gameConfigTables);
const activities = structuredClone(gameConfigTables.activities.activities);
const config = structuredClone(gameConfigTables.cardCollection);
function packs(state: any, star: number) { return state.pending_rewards.filter((r: any) => r.kind === "card_pack" && r.pack_id === star).length; }
for (const random of [0, 0.999999999]) {
  const service = new CardCollectionService(config, activities, () => random);
  for (let star = 1; star <= 5; star++) {
    const state = engine.createInitialState();
    const progress = service.ensureProgress(state)[1];
    progress.packs[star] = 2;
    assert.equal(service.migratePacksToPending(state), true);
    const [first, second] = state.pending_rewards;
    const migrated = JSON.stringify(state);
    assert.equal(service.migratePacksToPending(state), false);
    assert.equal(JSON.stringify(state), migrated);
    const result = service.openPending(state, 1, second.uid, false, "first", 0);
    assert.ok(result.ok);
    if (!result.ok) throw new Error(result.reason);
    assert.equal(result.cards!.reduce((n, c) => n + c.gained!, 0), star + 1);
    assert.equal(result.cards![0].star, star);
    assert.equal(packs(state, star), 1);
    assert.equal(state.pending_rewards[0].uid, first.uid); // Exact selected UID, not first matching star.
    assert.equal(progress.opened_count, 1);
    const after = JSON.stringify(state);
    assert.deepEqual(service.openPending(state, 1, second.uid, false, "first", 0), result);
    assert.equal(JSON.stringify(state), after);
    assert.deepEqual(service.openPending(state, 1, first.uid, false, "different", 0), { ok: false, reason: "state_conflict" });
    assert.deepEqual(service.openPending(state, 1, second.uid, true, "first", 0), { ok: false, reason: "request_mismatch" });
    assert.equal(service.openPending(state, 1, first.uid, false, "second", 1).ok, true);
    assert.equal(service.openPending(state, 1, first.uid, false, "third", 2).ok, false);
    assert.equal(Object.values(progress.cards).reduce((a, b) => a + b, 0), 2 * (star + 1));
  }
}
const single = structuredClone(config);
single.packs.forEach(p => { p.card_count = 1; p.normal_weights = []; });
const singles = new CardCollectionService(single, activities, () => 0, (state, rewards) => engine.applyRewards(state, rewards));
const mixed = engine.createInitialState();
const mixedProgress = singles.ensureProgress(mixed)[1];
for (let star = 1; star <= 5; star++) mixedProgress.packs[star] = 1;
singles.migratePacksToPending(mixed);
const selectedUid = mixed.pending_rewards[2].uid;
const normal = [{uid:9001,id:5001,name:"first"},{uid:9002,id:5002,name:"last"}];
mixed.pending_rewards.splice(2,0,normal[0]); mixed.pending_rewards.push(normal[1]);
mixed.grid = Array.from({length:63},(_,i)=>({uid:100+i,id:5001,col:i%7,row:Math.floor(i/7)}));
assert.deepEqual(engine.questEngine.claimPendingReward(mixed,selectedUid,engine),{ok:false,reason:"card_pack_open_required"});
const all = singles.openPending(mixed,1,selectedUid,true,"all",0);
assert.ok(all.ok);
if (!all.ok) throw new Error(all.reason);
assert.deepEqual(all.cards!.map(c=>c.star),[1,2,3,4,5]);
assert.equal(all.opened_packs,5);
assert.deepEqual(all.completed_sets,[{collection_id:1,set_id:1}]);
assert.deepEqual(all.rewards,{...config.card_sets[0].rewards,items:[]});
assert.equal(mixed.stamina,engine.createInitialState().stamina+300);
assert.equal(mixed.spirit_stones,engine.createInitialState().spirit_stones+1000);
assert.deepEqual(mixedProgress.claimed_sets,[1]);
assert.deepEqual(mixedProgress.last_open,all);
assert.deepEqual(mixed.pending_rewards,normal);
singles.awardSource(mixed,"order",0,0);
const withNewPack = JSON.stringify(mixed);
assert.deepEqual(singles.openPending(mixed,1,selectedUid,true,"all",0),all);
assert.equal(JSON.stringify(mixed),withNewPack); // Retry doesn't open later rewards.
mixed.grid.pop();
assert.equal(engine.questEngine.claimPendingReward(mixed,normal[0].uid,engine).ok,true);
assert.equal(mixed.grid.at(-1)!.id,normal[0].id);
assert.equal(mixed.pending_rewards[0].uid,normal[1].uid);
// Selected opens award only after the final missing card; duplicates and replays pay nothing extra.
const selectedState=engine.createInitialState();
const selectedProgress=singles.ensureProgress(selectedState)[1];
for (const id of [101,102,103]) selectedProgress.cards[id]=1;
singles.awardPack(selectedState,4,1);
const incomplete=singles.openPending(selectedState,1,selectedState.pending_rewards[0].uid,false,"incomplete",0);
assert.ok(incomplete.ok && incomplete.completed_sets===undefined && incomplete.rewards===undefined);
assert.deepEqual(selectedProgress.claimed_sets,[]);
assert.equal(selectedState.stamina,engine.createInitialState().stamina);
singles.awardPack(selectedState,5,2);
const finalUid=selectedState.pending_rewards[0].uid;
const complete=singles.openPending(selectedState,1,finalUid,false,"complete",1);
assert.ok(complete.ok && complete.completed_sets?.length===1);
assert.equal(selectedState.stamina,engine.createInitialState().stamina+300);
assert.equal(selectedState.spirit_stones,engine.createInitialState().spirit_stones+1000);
const completedSnapshot=JSON.stringify(selectedState);
assert.deepEqual(singles.openPending(selectedState,1,finalUid,false,"complete",1),complete);
assert.equal(JSON.stringify(selectedState),completedSnapshot);
const duplicate=singles.openPending(selectedState,1,selectedState.pending_rewards[0].uid,false,"duplicate",2);
assert.ok(duplicate.ok && duplicate.rewards===undefined && duplicate.completed_sets===undefined);
assert.equal(selectedState.stamina,engine.createInitialState().stamina+300);
assert.equal(selectedState.spirit_stones,engine.createInitialState().spirit_stones+1000);
assert.deepEqual(selectedProgress.claimed_sets,[1]);
// Reward application runs on a copy, so even a callback that throws after crediting is atomic.
const failedState=engine.createInitialState();
const failedProgress=singles.ensureProgress(failedState)[1];
for (const id of [101,102,103,104]) failedProgress.cards[id]=1;
singles.awardPack(failedState,5,1);
const failing=new CardCollectionService(single,activities,()=>0,(state,rewards)=>{
  engine.applyRewards(state,rewards); throw new Error("reward_failed");
});
const failedSnapshot=JSON.stringify(failedState);
assert.throws(()=>failing.openPending(failedState,1,failedState.pending_rewards[0].uid,false,"reward-failed",0),/reward_failed/);
assert.equal(JSON.stringify(failedState),failedSnapshot);
// Invalid configuration and RNG failures do not partially mutate a batch.
const broken = engine.createInitialState(); singles.ensureProgress(broken)[1].packs[1]=1; singles.migratePacksToPending(broken);
broken.pending_rewards.push({uid:999,id:99,name:"unknown",kind:"card_pack",collection_id:1,pack_id:99});
const brokenBefore=JSON.stringify(broken);
assert.deepEqual(singles.openPending(broken,1,broken.pending_rewards[0].uid,true,"broken",0),{ok:false,reason:"pack_not_found"});
assert.equal(JSON.stringify(broken),brokenBefore);
let rolls=0;
const badRandom=new CardCollectionService(config,activities,()=>++rolls>2?NaN:0);
const rngState=engine.createInitialState(); badRandom.ensureProgress(rngState)[1].packs[1]=2;badRandom.migratePacksToPending(rngState);
const rngBefore=JSON.stringify(rngState);
assert.throws(()=>badRandom.openPending(rngState,1,rngState.pending_rewards[0].uid,true,"rng",0),/invalid_random_value/);
assert.equal(JSON.stringify(rngState),rngBefore);
// All-open includes every collection; any inactive pack leaves the entire queue intact.
const multiConfig = structuredClone(single);
multiConfig.collections.push({collection_id:2,activity_id:6,name:"second"});
multiConfig.card_sets.push({set_id:4,collection_id:2,name:"second set",rewards:{tokens:[{token:3,amount:1}]}});
multiConfig.cards.push({card_id:201,set_id:4,name:"second card",star:1,icon:""});
multiConfig.packs.push({pack_id:6,collection_id:2,name:"second pack",star:1,icon:"",card_count:1,normal_weights:[]});
const multiActivities = [...activities, {...activities[0],id:6,enabled:true,start_time:undefined,end_time:undefined}];
const multiService = new CardCollectionService(multiConfig,multiActivities,()=>0,(state,rewards)=>engine.applyRewards(state,rewards));
const multiState = engine.createInitialState();
multiService.ensureProgress(multiState)[1].packs[5]=1; multiService.ensureProgress(multiState)[2].packs[6]=1;
// Existing unpaid sets and a newly completed set across collections settle in the same open.
for (const card of multiConfig.cards.filter(c=>c.set_id===1 || c.set_id===2)) multiState.card_collection_progress![1].cards[card.card_id]=1;
multiService.migratePacksToPending(multiState);
const inactive = new CardCollectionService(multiConfig,multiActivities.map(a=>a.id===6?{...a,enabled:false}:a),()=>0);
const beforeMulti=JSON.stringify(multiState);
assert.deepEqual(inactive.openPending(multiState,1,multiState.pending_rewards[0].uid,true,"multi",0),{ok:false,reason:"activity_inactive"});
assert.equal(JSON.stringify(multiState),beforeMulti);
const multiResult=multiService.openPending(multiState,1,multiState.pending_rewards[0].uid,true,"multi",0);
assert.ok(multiResult.ok && multiResult.opened_packs===2);
if (!multiResult.ok) throw new Error(multiResult.reason);
assert.deepEqual(multiResult.completed_sets,[{collection_id:1,set_id:1},{collection_id:1,set_id:2},{collection_id:2,set_id:4}]);
assert.deepEqual(multiResult.rewards,{tokens:[{token:3,amount:801},{token:1,amount:3000}],items:[]});
assert.equal(multiState.stamina,engine.createInitialState().stamina+801);
assert.equal(multiState.spirit_stones,engine.createInitialState().spirit_stones+3000);
assert.deepEqual(multiState.card_collection_progress![1].claimed_sets,[1,2]);
assert.deepEqual(multiState.card_collection_progress![2].claimed_sets,[4]);
assert.equal(multiState.card_collection_progress![2].cards[201],1);
assert.equal(multiState.card_collection_progress![1].opened_count,1);
assert.equal(multiState.card_collection_progress![2].opened_count,1);
assert.equal(multiState.pending_rewards.length,0);
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
service.migratePacksToPending(state);
const disabledBefore = JSON.stringify(state);
disabled.awardSource(state, "order", 0, 900);
assert.deepEqual(disabled.openPending(state, 1, state.pending_rewards[0].uid, false, "disabled", 0), {ok:false,reason:"activity_inactive"});
assert.equal(JSON.stringify(state), disabledBefore);

const overrides = structuredClone(config);
overrides.source_rewards.push({collection_id:1,source_type:"order",source_id:999,min_value:0,pack_id:1,count:1,enabled:false} as any);
const overrideService = new CardCollectionService(overrides, activities);
const excluded = engine.createInitialState();
overrideService.awardSource(excluded, "order", 999, 100);
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
service.migratePacksToPending(historyState);
const oldUid=historyState.pending_rewards[0].uid;
for (let i=0;i<33;i++) assert.equal(service.openPending(historyState,1,historyState.pending_rewards[0].uid,false,`history-${i}`,i).ok,true);
assert.equal(historyState.card_pack_operations!.length,32);
assert.deepEqual(service.openPending(historyState,1,oldUid,false,"history-0",0),{ok:false,reason:"state_conflict"});
assert.equal(packs(historyState,1),7);

// Manual quest packs follow claiming; automatic quests award on completion.
const questTables = structuredClone(gameConfigTables);
questTables.rewards.rewards["9991"] = { tokens: [{token:1,amount:7}], items: [{id:1701,count:1}] };
questTables.rewards.rewards["9992"] = { items: [{id:1702,count:2}] };
questTables.quests.quests = [
  {id:9991,type:QuestType.MERGE,name:"manual",description:"",target_count:1,rewards:9991,auto_reward:false,reset_cycle:1},
  {id:9992,type:QuestType.MERGE,name:"auto",description:"",target_count:10,rewards:9992,auto_reward:true,reset_cycle:0},
  {id:9993,type:QuestType.MERGE,name:"manual no pack",description:"",target_count:1,rewards:1,auto_reward:false,reset_cycle:0},
  {id:9994,type:QuestType.MERGE,name:"auto no pack",description:"",target_count:1,rewards:1,auto_reward:true,reset_cycle:0},
];
const questEngine = new GameEngine(questTables); const questState = questEngine.createInitialState();
questEngine.questEngine.initQuestProgress(questState);
assert.deepEqual(questEngine.questEngine.claimQuestReward(questState, 9991, questEngine), {ok:false,reason:"quest_not_completed"});
assert.equal(packs(questState, 1), 0);
questEngine.questEngine.incrementQuestProgress(questState, QuestType.MERGE, 10, questEngine);
assert.equal(packs(questState, 1), 0);
assert.equal(questState.quest_progress![9991].completed, true);
assert.equal(questState.quest_progress![9991].claimed, false);
assert.equal(packs(questState, 2), 2);
assert.equal(questState.quest_progress![9994].claimed, true);
assert.equal(questEngine.questEngine.claimQuestReward(questState, 9993, questEngine).ok, true);
assert.equal(questState.pending_rewards.length, 2);
questEngine.questEngine.incrementQuestProgress(questState, QuestType.MERGE, 10, questEngine);
assert.equal(packs(questState, 1), 0);
assert.equal(questEngine.questEngine.claimQuestReward(questState, 9991, questEngine).ok, true);
assert.equal(packs(questState, 1), 1);
assert.deepEqual(questEngine.questEngine.claimQuestReward(questState, 9991, questEngine), {ok:false,reason:"already_claimed"});
assert.equal(packs(questState, 1), 1);
questState.quest_last_reset = Date.now() - 86400000 * 2;
questEngine.questEngine.incrementQuestProgress(questState, QuestType.MERGE, 1, questEngine);
assert.equal(packs(questState, 1), 1);
assert.equal(questEngine.questEngine.claimQuestReward(questState, 9991, questEngine).ok, true);
assert.equal(packs(questState, 1), 2);
assert.equal(packs(questState, 2), 2);
assert.deepEqual(questState.pending_rewards.map(r => r.id), [1702,1702,1701,1701]);

// Reproduce the reported flow through a real merge, then manually claim its task.
const mergeQuestState = questEngine.createInitialState();
mergeQuestState.grid = [{uid:9001,id:5001,col:0,row:0},{uid:9002,id:5001,col:1,row:0}];
assert.equal(questEngine.executeMerge(mergeQuestState,0,0,1,0).ok,true);
assert.equal(mergeQuestState.quest_progress![9991].completed,true);
assert.equal(packs(mergeQuestState,1),0);
assert.equal(questEngine.questEngine.claimQuestReward(mergeQuestState,9991,questEngine).ok,true);
assert.equal(packs(mergeQuestState,1),1);
assert.equal(questEngine.questEngine.claimQuestReward(mergeQuestState,9993,questEngine).ok,true);
assert.equal(mergeQuestState.pending_rewards.length,1);

// Effect item rewards preserve ordinary rewards and never discover a board item.
const effectsState = engine.createInitialState();
const effectsBefore = structuredClone(effectsState);
const effectRewards = {tokens:[{token:1,amount:10}],items:[{id:1703,count:2},{id:5001,count:1}]};
assert.deepEqual(engine.applyRewards(effectsState,effectRewards),effectRewards);
assert.equal(effectsState.spirit_stones,effectsBefore.spirit_stones+10);
assert.equal(packs(effectsState,3),2);
assert.deepEqual(effectsState.pending_rewards.map(r=>[r.id,r.kind]),[[1703,"card_pack"],[1703,"card_pack"],[5001,undefined]]);
assert.ok(!effectsState.crafted_item_ids?.includes(1703));
assert.ok(!effectsState.unlocked_production_item_ids?.includes(1703));
assert.equal(engine.cardCollectionService.openPending(effectsState,1,effectsState.pending_rewards[0].uid,false,"effect-item",0).ok,true);
assert.equal(packs(effectsState,3),1);
const beforeInvalid = JSON.stringify(effectsState);
assert.throws(()=>engine.applyRewards(effectsState,{tokens:[{token:1,amount:50}],items:[{id:1703,count:1.5}]}),/invalid reward count/);
assert.equal(JSON.stringify(effectsState),beforeInvalid);
const invalidEffectTables=structuredClone(gameConfigTables);
invalidEffectTables.items.effect.find(i=>i.id===1701)!.effect_value=999;
assert.throws(()=>new GameEngine(invalidEffectTables),/invalid\/duplicate pack effect item/);

const orderState = engine.createInitialState();
orderState.meridian_acupoints = [{item_id:5001,count:1,name:"order",completed:false,total_value:200} as any];
orderState.grid.push({uid:9999,id:5001,col:6,row:8});
assert.equal(engine.completeMeridianAcupoint(orderState, 0, []).ok, false);
assert.equal(engine.completeMeridianAcupoint(orderState, 0, [5001], "order-once").ok, true);
assert.equal(packs(orderState, 2), 1);
assert.equal(orderState.pending_rewards.find(r=>r.kind==="card_pack")!.id,1702);
assert.equal(engine.completeMeridianAcupoint(orderState, 0, [5001], "order-once").ok, false);
assert.equal(packs(orderState, 2), 1);

const circulationState = engine.createInitialState();
circulationState.home_meridian_progress = [{stage:0,lit:new Array(engine.getHomeMeridianDefs()[0].acupoints).fill(true),circulation_completed:false}];
assert.equal(engine.runHomeMeridianCirculation(circulationState, 0).ok, true);
assert.equal(packs(circulationState, 4), 1);
assert.equal(engine.runHomeMeridianCirculation(circulationState, 0).ok, false);
assert.equal(packs(circulationState, 4), 1);
assert.equal(circulationState.pending_rewards.filter(r=>r.kind==="card_pack").length,1);

// The displayed order tier and the actual item reward agree at every boundary.
for (const [value,star] of [[0,1],[199,1],[200,2],[599,2],[600,3],[10000,3]]) {
  const state=engine.createInitialState();
  state.grid=[{uid:9000,id:5001,col:0,row:0}];
  state.meridian_acupoints=[{item_id:5001,count:1,total_value:value,completed:false} as any];
  const expected={id:1700+star,count:1};
  assert.deepEqual(engine.cardCollectionService.getSourceRewardConfig("order",0,value).items,[expected]);
  const result=engine.completeMeridianAcupoint(state,0,[5001],`tier-${value}`);
  assert.ok(result.ok);
  assert.deepEqual(result.rewards.items,[expected]);
  assert.equal(packs(state,star),1);
  assert.equal(engine.completeMeridianAcupoint(state,0,[5001],`tier-${value}`).ok,false);
  assert.equal(packs(state,star),1);
}
for (const [index,id] of [1001,1006,1011,1016,1021,1026,1031].entries()) {
  const state=engine.createInitialState();
  const quest=engine.questEngine.getQuestDefs().find(q=>q.id===id)!;
  engine.questEngine.incrementQuestProgress(state,QuestType.MERGE,quest.target_count,engine);
  assert.equal(state.pending_rewards.length,0);
  assert.equal(engine.questEngine.claimQuestReward(state,id,engine).ok,true);
  assert.equal(packs(state,1+index%3),1);
  assert.equal(engine.getRewardConfig(Number(quest.rewards))!.tokens,undefined);
}
// Weekly rewards grant only stamina or card packs, without advancing cultivation.
const weeklyQuestIds=gameConfigTables.weeklyTasks.weekly_tasks.flatMap(w=>w.daily_quests.flat());
assert.equal(weeklyQuestIds.length,35);
for (const id of weeklyQuestIds) {
  const state=engine.createInitialState();
  const quest=engine.questEngine.getQuestDefs().find(q=>q.id===id)!;
  engine.questEngine.incrementQuestProgress(state,quest.type,quest.target_count,engine);
  const before=structuredClone(state);
  assert.equal(engine.questEngine.claimQuestReward(state,id,engine).ok,true);
  assert.deepEqual(state.cultivation,before.cultivation);
  if (quest.type===QuestType.MERGE) {
    assert.equal(state.stamina,before.stamina);
    assert.equal(state.pending_rewards.filter(r=>r.kind==="card_pack").length,1);
  } else {
    assert.equal(state.stamina,before.stamina+10);
    assert.deepEqual(state.pending_rewards,before.pending_rewards);
  }
  const after=JSON.stringify(state);
  assert.equal(engine.questEngine.claimQuestReward(state,id,engine).ok,false);
  assert.equal(JSON.stringify(state),after);
}
console.log("card_collection_smoke: ok");
