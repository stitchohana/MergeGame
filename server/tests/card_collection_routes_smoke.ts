import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { GameEngine } from "../src/engine/game_engine";
import { CardCollectionService } from "../src/engine/card_collection";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { D1Storage } from "../src/storage/d1";
import { GameState } from "../src/storage/interface";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";
import { enqueue } from "../src/routes/queue";

class TestStorage extends MemoryStorage {
  fail = false;
  override async saveState(id: string, state: GameState) {
    if (this.fail) { this.fail = false; throw new Error("save_failed"); }
    return super.saveState(id, state);
  }
}

async function main() {
  const engine = new GameEngine(gameConfigTables); const storage = new TestStorage();
  engine.cardCollectionService = new CardCollectionService(gameConfigTables.cardCollection,gameConfigTables.activities.activities,()=>0,(state,rewards)=>engine.applyRewards(state,rewards));
  const state = engine.createInitialState();
  const progress = engine.cardCollectionService.ensureProgress(state)[1];
  progress.packs[5] = 4;
  for (const id of [101,102,103,104]) progress.cards[id]=1;
  await storage.saveState("cards", state);
  const router = createGameRouter(storage, engine, "test-cards-secret");
  const token = await signToken({userId:"cards",deviceId:"test-cards"}, "test-cards-secret");
  async function request(path: string, body: any, method = "POST") {
    const res = new WorkerResponse();
    await router.handle({method,path,body,headers:{authorization:"Bearer " + token},query:{}},res);
    return { status:res.statusCode, data:await res.toResponse().json() as any };
  }
  storage.fail = true;
  assert.equal((await request("/state",{},"GET")).status,500);
  const beforeMigration = (await storage.loadState("cards"))!;
  assert.equal(beforeMigration.card_collection_progress![1].packs[5],4);
  assert.equal(beforeMigration.pending_rewards.length,0);
  await request("/state",{},"GET"); // Persist legacy pack UIDs before exposing them to the client.
  const migrated = (await storage.loadState("cards"))!;
  const reload = await request("/state",{},"GET");
  assert.deepEqual(reload.data.pending_rewards, migrated.pending_rewards);
  const body = {collection_id:1,pack_uid:migrated.pending_rewards[0].uid,open_all:false,request_id:"open-once",expected_opened_count:0};
  assert.equal((await request("/card_collection/open",{...body,pack_uid:"5"})).status,400);
  assert.equal((await request("/card_collection/open",{...body,expected_opened_count:-1})).status,400);
  storage.fail = true;
  assert.equal((await request("/card_collection/open",body)).status,500);
  assert.deepEqual(await storage.loadState("cards"),migrated);
  const results = await Promise.all([request("/card_collection/open",body),request("/card_collection/open",body)]);
  assert.equal(results[0].status,200); assert.deepEqual(results[0].data.cards,results[1].data.cards);
  assert.equal(results[1].status,200);
  assert.deepEqual(results[0].data.completed_sets,[{collection_id:1,set_id:1}]);
  assert.equal(results[0].data.stamina,migrated.stamina+300);
  assert.equal(results[0].data.spirit_stones,migrated.spirit_stones+1000);
  assert.equal(results[1].data.stamina,results[0].data.stamina);
  assert.deepEqual((await storage.loadState("cards"))!.card_collection_progress![1].claimed_sets,[1]);
  assert.equal((await storage.loadState("cards"))!.pending_rewards.filter(r=>r.kind==="card_pack").length,3);
  assert.equal((await request("/card_collection/open",{...body,request_id:"stale"})).status,409);
  const loaded = await request("/state",{},"GET");
  assert.deepEqual(loaded.data.card_collection_progress[1].last_open.cards,results[0].data.cards);
  assert.deepEqual(loaded.data.card_collection_progress[1].last_open.rewards,results[0].data.rewards);
  assert.equal(loaded.data.card_collection_progress[1].recent_operations,undefined);

  const remainder = (await storage.loadState("cards"))!;
  for (const card of gameConfigTables.cardCollection.cards.filter(c=>c.set_id===2)) remainder.card_collection_progress![1].cards[card.card_id]=1;
  await storage.saveState("cards",remainder);
  const allBody = {...body, pack_uid:remainder.pending_rewards[0].uid, open_all:true, request_id:"all-once", expected_opened_count:1};
  assert.equal((await request("/claim_pending_reward",{uid:allBody.pack_uid})).data.error,"card_pack_open_required");
  storage.fail=true;
  assert.equal((await request("/card_collection/open",allBody)).status,500);
  assert.deepEqual(await storage.loadState("cards"),remainder);
  const competing=await Promise.all([request("/card_collection/open",allBody),request("/card_collection/open",{...allBody,open_all:false,request_id:"selected-race"})]);
  assert.equal(competing[0].status,200); assert.equal(competing[0].data.opened_packs,3);
  assert.equal(competing[1].status,409);
  assert.equal(competing[0].data.pending_rewards.length,0);
  assert.deepEqual(competing[0].data.completed_sets,[{collection_id:1,set_id:2}]);
  assert.equal(competing[0].data.stamina,migrated.stamina+800);
  assert.equal(competing[0].data.spirit_stones,migrated.spirit_stones+3000);
  assert.ok(competing[0].data.storage_revision>0);
  assert.deepEqual((await request("/card_collection/open",allBody)).data.cards,competing[0].data.cards);
  const ready = (await storage.loadState("cards"))!;
  const claim = {collection_id:1,set_id:1,request_id:"claim-once"};
  assert.equal((await request("/card_collection/claim",claim)).data.error,"already_claimed");
  assert.deepEqual(await storage.loadState("cards"),ready);
  assert.deepEqual(ready.card_collection_progress![1].claimed_sets,[1,2]);

  // Execute the actual D1 SQL against SQLite, simulating independent Worker instances.
  const db=new DatabaseSync(":memory:");
  db.exec("CREATE TABLE game_states (user_id TEXT PRIMARY KEY, state_json TEXT NOT NULL, updated_at INTEGER)");
  const adapter = {prepare(sql:string) {return {bind(...args:any[]) {return {
    async first() {return db.prepare(sql).get(...args) ?? null;},
    async run() {return {meta:{changes:Number(db.prepare(sql).run(...args).changes)}};},
  };}};}};
  const left=new D1Storage(adapter as any); const right=new D1Storage(adapter as any);
  const initial=engine.createInitialState(); await left.saveState("d1",initial);
  const a=(await left.loadState("d1"))!; const b=(await right.loadState("d1"))!;
  a.spirit_stones+=100; await left.saveState("d1",a);
  b.stamina+=200; await assert.rejects(right.saveState("d1",b),/state_conflict/);
  assert.equal((await right.loadState("d1"))!.spirit_stones,a.spirit_stones);
  assert.equal((await right.loadState("d1"))!.stamina,a.stamina);
  // Legacy rows upgrade without a schema migration.
  db.prepare("INSERT INTO game_states VALUES (?, ?, 0)").run("old",JSON.stringify(engine.createInitialState()));
  const old=(await left.loadState("old"))!; await left.saveState("old",old); assert.equal(old.storage_revision,1);
  await assert.rejects(enqueue("failure",async()=>{throw new Error("expected");}),/expected/);
  await enqueue("failure",async()=>{});
  db.close(); console.log("card_collection_routes_smoke: ok");
}
main().catch(error=>{console.error(error);process.exitCode=1;});
