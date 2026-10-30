import assert from "node:assert/strict";
import { CardCollectionService, type CardCollectionConfig } from "../src/engine/card_collection";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine = new GameEngine(gameConfigTables);
const config: CardCollectionConfig = structuredClone(gameConfigTables.cardCollection);
const firstCardByStar = new Map([1,2,3,4,5].map(star => [star, config.cards.find(c=>c.star===star)!.card_id]));
const activities = structuredClone(gameConfigTables.activities.activities);
const single = structuredClone(config);
single.packs.forEach(pack => { pack.card_count = 1; pack.normal_weights = []; });
const service = new CardCollectionService(single, activities, () => 0, (state, rewards) => engine.applyRewards(state, rewards));
service.bindPackItems(gameConfigTables.items.effect);

for (let star = 1; star <= 5; star++) {
  const state = engine.createInitialState(); state.cultivation.current_level = 2;
  const p = service.ensureProgress(state)[1];
  service.awardPack(state, star, 2);
  const first = service.openPending(state, 1, state.pending_rewards[0].uid, false, "first", 0);
  assert.ok(first.ok && first.duplicate_points_gained === 0);
  const uid = state.pending_rewards[0].uid;
  const duplicate = service.openPending(state, 1, uid, false, "duplicate", 1);
  assert.ok(duplicate.ok && duplicate.duplicate_points_gained === star);
  assert.equal(p.duplicate_points, star);
  assert.equal(p.total_duplicate_points, star);
  assert.equal(p.cards[firstCardByStar.get(star)!], 2);
  const after = JSON.stringify(state);
  assert.deepEqual(service.openPending(state, 1, uid, false, "duplicate", 1), duplicate);
  assert.equal(JSON.stringify(state), after);
}

// The first copy in a batch stays new, while subsequent copies each refund their star value.
const allState = engine.createInitialState(); allState.cultivation.current_level = 2;
const allProgress = service.ensureProgress(allState)[1];
for (const card of config.cards.filter(c => c.set_id === 1 && ![...firstCardByStar.values()].includes(c.card_id))) allProgress.cards[card.card_id] = 1;
for (let star = 1; star <= 5; star++) service.awardPack(allState, star, 2);
const all = service.openPending(allState, 1, allState.pending_rewards[0].uid, true, "all", 0);
assert.ok(all.ok);
if (!all.ok) throw new Error(all.reason);
assert.equal(all.duplicate_points_gained, 15);
assert.deepEqual(all.cards!.map(card => [card.is_new, card.gained, card.duplicate_points]), [1,2,3,4,5].map(star => [true, 2, star]));
assert.equal(allProgress.duplicate_points, 15);
assert.equal(allProgress.total_duplicate_points, 15);
assert.deepEqual(allProgress.claimed_sets, [1]);
assert.equal(allState.stamina, 400); // Set rewards still settle with duplicate points.
assert.equal(service.publicProgress(allState)[1].duplicate_points, 15);

// Two equal cards in the same single pack refund the second card only.
const samePackConfig = structuredClone(single);
samePackConfig.packs[0].card_count = 2;
samePackConfig.packs[0].normal_weights = [1,0,0,0,0];
const samePack = new CardCollectionService(samePackConfig, activities, () => 0);
const sameState = engine.createInitialState(); sameState.cultivation.current_level = 2;
samePack.awardPack(sameState, 1, 1);
const same = samePack.openPending(sameState, 1, sameState.pending_rewards[0].uid, false, "same", 0);
assert.ok(same.ok && same.duplicate_points_gained === 1);

const multiConfig = structuredClone(single);
multiConfig.collections.push({collection_id:2,activity_id:9006,name:"second",duplicate_points_by_star:[10,20,30,40,50]});
const secondSetId = Math.max(...config.card_sets.map(s=>s.set_id)) + 1;
const secondCardId = Math.max(...config.cards.map(c=>c.card_id)) + 1;
multiConfig.card_sets.push({set_id:secondSetId,collection_id:2,name:"second set",rewards:{tokens:[{token:3,amount:1}]}});
multiConfig.cards.push({card_id:secondCardId,set_id:secondSetId,name:"second card",star:1,icon:""});
multiConfig.packs.push({pack_id:6,collection_id:2,name:"second pack",star:1,icon:"",card_count:1,normal_weights:[]});
const multi = new CardCollectionService(multiConfig,[...activities,{...activities[0],id:9006,enabled:true,start_time:undefined,end_time:undefined}],()=>0,(state,rewards)=>engine.applyRewards(state,rewards));
const multiState = engine.createInitialState(); multiState.cultivation.current_level = 2;
multi.awardPack(multiState, 1, 2); multi.awardPack(multiState, 6, 2);
const multiOpen = multi.openPending(multiState,1,multiState.pending_rewards[0].uid,true,"multi",0);
assert.ok(multiOpen.ok && multiOpen.duplicate_points_gained === 11);
assert.equal(multiState.card_collection_progress![1].duplicate_points,1);
assert.equal(multiState.card_collection_progress![2].duplicate_points,10);

const state = engine.createInitialState(); state.cultivation.current_level = 2;
const p = service.ensureProgress(state)[1];
p.duplicate_points = 199; p.total_duplicate_points = 200;
const before = JSON.stringify(state);
assert.deepEqual(service.exchange(state,1,"poor",0),{ok:false,reason:"insufficient_points"});
assert.equal(JSON.stringify(state), before);
p.duplicate_points = 200;
state.pending_rewards.push({uid:8000,id:5001,name:"ordinary"});
const exchange = service.exchange(state,1,"exchange",0);
assert.ok(exchange.ok && exchange.exchanged && exchange.points_spent === 200 && exchange.pack_id === 5);
assert.equal(p.duplicate_points,0);
assert.equal(p.total_duplicate_points,200);
assert.equal(p.exchange_count,1);
assert.deepEqual(state.pending_rewards.map(r => [r.id,r.kind]),[[5001,undefined],[1705,"card_pack"]]);
assert.equal(state.pending_rewards[1].collection_id,1);
const afterExchange = JSON.stringify(state);
assert.deepEqual(service.exchange(state,1,"exchange",0),exchange);
assert.equal(JSON.stringify(state),afterExchange);
assert.deepEqual(service.exchange(state,1,"exchange",1),{ok:false,reason:"request_mismatch"});
assert.deepEqual(service.exchange(state,1,"stale",0),{ok:false,reason:"state_conflict"});
assert.deepEqual(service.exchange(state,1,"poor",1),{ok:false,reason:"insufficient_points"});
assert.deepEqual(service.exchange(state,1,"bad",-1),{ok:false,reason:"invalid_params"});
assert.deepEqual(service.exchange(state,1,"bad",0.5),{ok:false,reason:"invalid_params"});
assert.deepEqual(service.exchange(state,999,"unknown",0),{ok:false,reason:"exchange_unavailable"});

const disabled = new CardCollectionService(single,activities.map(a=>a.id===5?{...a,enabled:false}:a));
assert.deepEqual(disabled.exchange(state,1,"disabled",1),{ok:false,reason:"activity_inactive"});
assert.equal(service.openPending(state,1,state.pending_rewards[1].uid,false,"redeemed-open",0).ok,true);
assert.equal(p.cards[firstCardByStar.get(5)!],1); // The redeemed pack works through the normal same-star guarantee.
assert.equal(p.duplicate_points,0);

// Awarding a pack can fail without committing points or counters.
const failing = new CardCollectionService(single,activities);
failing.awardPack = (working) => { working.pending_rewards = []; throw new Error("award_failed"); };
const failState = engine.createInitialState(); failState.cultivation.current_level = 2;
failing.ensureProgress(failState)[1].duplicate_points = 200;
const failBefore = JSON.stringify(failState);
assert.throws(()=>failing.exchange(failState,1,"failed",0),/award_failed/);
assert.equal(JSON.stringify(failState),failBefore);

const tunedConfig = structuredClone(single);
tunedConfig.collections[0].duplicate_points_by_star = [2,4,6,8,10];
tunedConfig.collections[0].exchange_cost = 250;
const tuned = new CardCollectionService(tunedConfig,activities,()=>0);
const tunedState = engine.createInitialState(); tunedState.cultivation.current_level = 2;
const tunedProgress = tuned.ensureProgress(tunedState)[1];
tunedProgress.cards[firstCardByStar.get(5)!]=1;
tuned.awardPack(tunedState,5,1);
const tunedOpen=tuned.openPending(tunedState,1,tunedState.pending_rewards[0].uid,false,"tuned",0);
assert.ok(tunedOpen.ok && tunedOpen.duplicate_points_gained===10);
tunedProgress.duplicate_points=200;
assert.deepEqual(tuned.exchange(tunedState,1,"tuned-exchange",0),{ok:false,reason:"insufficient_points"});
tunedProgress.duplicate_points=250;
assert.ok(tuned.exchange(tunedState,1,"tuned-exchange",0).ok);
assert.equal(tunedProgress.duplicate_points,0);

// After replay receipt eviction, the monotonic exchange count still blocks an old request.
const history = engine.createInitialState(); history.cultivation.current_level = 2;
const hp = service.ensureProgress(history)[1]; hp.duplicate_points = 8000;
for (let i=0;i<33;i++) assert.equal(service.exchange(history,1,`history-${i}`,i).ok,true);
assert.equal(history.card_pack_operations!.length,32);
const historyBefore = JSON.stringify(history);
assert.deepEqual(service.exchange(history,1,"history-0",0),{ok:false,reason:"state_conflict"});
assert.equal(JSON.stringify(history),historyBefore);
assert.equal(hp.duplicate_points,1400);

for (const patch of [{duplicate_points_by_star:[1,2,3,4,0]}, {duplicate_points_by_star:[1,2]}, {exchange_cost:0}, {exchange_cost:1.5}, {exchange_pack_id:1}]) {
  const invalid = structuredClone(single);
  Object.assign(invalid.collections[0],patch);
  assert.throws(()=>new CardCollectionService(invalid,activities),/invalid (duplicate points|exchange)/);
}
console.log("card_duplicate_points_smoke: ok");
