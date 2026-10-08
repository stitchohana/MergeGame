import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { GameEngine } from "../src/engine/game_engine";
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
  const state = engine.createInitialState(); engine.cardCollectionService.ensureProgress(state)[1].packs[5] = 4;
  await storage.saveState("cards", state);
  const router = createGameRouter(storage, engine, "test-cards-secret");
  const token = await signToken({userId:"cards",deviceId:"test-cards"}, "test-cards-secret");
  async function request(path: string, body: any, method = "POST") {
    const res = new WorkerResponse();
    await router.handle({method,path,body,headers:{authorization:"Bearer " + token},query:{}},res);
    return { status:res.statusCode, data:await res.toResponse().json() as any };
  }
  await request("/state",{},"GET"); // Complete unrelated legacy migrations before save failure injection.
  const body = {collection_id:1,pack_id:5,request_id:"open-once",expected_opened_count:0};
  assert.equal((await request("/card_collection/open",{...body,pack_id:"5"})).status,400);
  assert.equal((await request("/card_collection/open",{...body,expected_opened_count:-1})).status,400);
  storage.fail = true;
  assert.equal((await request("/card_collection/open",body)).status,500);
  assert.equal((await storage.loadState("cards"))!.card_collection_progress![1].packs[5],4);
  const results = await Promise.all([request("/card_collection/open",body),request("/card_collection/open",body)]);
  assert.equal(results[0].status,200); assert.deepEqual(results[0].data.cards,results[1].data.cards);
  assert.equal((await storage.loadState("cards"))!.card_collection_progress![1].packs[5],3);
  assert.equal((await request("/card_collection/open",{...body,request_id:"stale"})).status,409);
  const loaded = await request("/state",{},"GET");
  assert.deepEqual(loaded.data.card_collection_progress[1].last_open.cards,results[0].data.cards);
  assert.equal(loaded.data.card_collection_progress[1].recent_operations,undefined);

  const ready = (await storage.loadState("cards"))!;
  for(const card of gameConfigTables.cardCollection.cards.filter(c=>c.set_id===1)) ready.card_collection_progress![1].cards[card.card_id]=1;
  await storage.saveState("cards",ready);
  const claim = {collection_id:1,set_id:1,request_id:"claim-once"};
  storage.fail=true;
  assert.equal((await request("/card_collection/claim",claim)).status,500);
  assert.deepEqual((await storage.loadState("cards"))!.card_collection_progress![1].claimed_sets,[]);
  const rewards=await Promise.all([request("/card_collection/claim",claim),request("/card_collection/claim",claim)]);
  assert.equal(rewards[0].status,200); assert.equal(rewards[0].data.stamina,rewards[1].data.stamina);
  assert.equal((await request("/card_collection/claim",{...claim,request_id:"again"})).data.error,"already_claimed");
  assert.equal((await storage.loadState("cards"))!.stamina,ready.stamina+300);

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
