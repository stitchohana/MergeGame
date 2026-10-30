import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { createGMRouter } from "../src/routes/gm";
import { signToken } from "../src/middleware/auth";
import { MemoryStorage } from "../src/storage/memory";
import { WorkerResponse } from "../src/worker/http";

async function main() {
  const engine=new GameEngine(gameConfigTables),service=engine.secretRealmService;
  const state=engine.createInitialState();
  const locked=structuredClone(state);
  assert.equal(service.gmGrantSwords(state,1,1).reason,"activity_locked");
  assert.deepEqual(state,locked);
  state.cultivation.current_level=2;
  for(const [level,amount,reason] of [[0,1,"invalid_level"],[13,1,"invalid_level"],[1.5,1,"invalid_level"],["2",1,"invalid_level"],
    [undefined,1,"invalid_level"],[1,0,"invalid_amount"],[1,-1,"invalid_amount"],[1,1.5,"invalid_amount"],
    [1,1001,"invalid_amount"],[1,"2","invalid_amount"],[1,undefined,"invalid_amount"]]) {
    const before=structuredClone(state);
    assert.equal(service.gmGrantSwords(state,level,amount).reason,reason);
    assert.deepEqual(state,before,"invalid grants do not initialize progress or consume UIDs");
  }
  const storage=new MemoryStorage(),user="gm-realm-user",secret="test-gm-realm",key="test-key";
  await storage.saveState(user,state);
  const router=createGMRouter(storage,engine,secret,key);
  const token=await signToken({userId:user,deviceId:"gm-realm-device"},secret);
  async function send(body:any,gmKey=key,authorization=`Bearer ${token}`) {
    const res=new WorkerResponse();
    await router.handle({method:"POST",path:"/exec",headers:{authorization},query:{},body:{cmd:"add_secret_realm_swords",gm_key:gmKey,...body}},res);
    const output=res.toResponse();return {status:output.status,data:await output.json() as any};
  }
  let before=(await storage.loadState(user))!;
  assert.equal((await send({level:7,amount:3},"wrong-key")).status,403);
  assert.equal((await send({level:7,amount:3},key,"")).status,401);
  assert.equal((await send({level:13,amount:3})).status,400);
  assert.deepEqual(await storage.loadState(user),before);
  const first=await send({level:7,amount:3});
  assert.equal(first.status,200);assert.equal(first.data.granted_count,3);assert.equal(first.data.sword_level,7);
  let saved=(await storage.loadState(user))!;
  assert.equal(first.data.storage_revision,saved.storage_revision);
  assert.deepEqual(first.data.secret_realm.stash,saved.secret_realm!.stash);
  assert.equal(saved.secret_realm!.stash.length,3);
  assert.ok(saved.secret_realm!.stash.every(i=>i.id==="sword_7"&&!i.immovable));
  assert.deepEqual(saved.grid,before.grid);assert.equal(saved.version,before.version+1);
  const initialCells=structuredClone(saved.secret_realm!.cells),oldVersion=saved.secret_realm!.version;
  assert.equal((await send({level:1,amount:1})).status,200);
  assert.equal((await send({level:12,amount:1000})).status,200);
  saved=(await storage.loadState(user))!;
  const p=saved.secret_realm!;
  assert.equal(p.version,oldVersion+2);assert.deepEqual(p.cells,initialCells,"grant does not occupy or overwrite board cells");
  assert.equal(p.stash.filter(i=>i.id==="sword_1").length,1);
  assert.equal(p.stash.filter(i=>i.id==="sword_12").length,1000);
  assert.equal(new Set([...p.stash,...p.cells.flatMap(c=>c.item?[c.item]:[])].map(i=>i.uid)).size,p.stash.length+p.cells.filter(c=>c.item).length);
  assert.equal(service.previewMerge(saved,{action:"move",uid:p.cells[0].item!.uid,col:0,row:1,period:p.period,version:oldVersion,request_id:"stale-gm-preview"}).reason,"state_conflict");
  before=structuredClone(saved);
  assert.equal((await send({level:1,amount:0})).data.error,"invalid_amount");
  assert.deepEqual(await storage.loadState(user),before);
  p.completed=true;p.stage=6;await storage.saveState(user,saved);
  assert.equal((await send({level:5,amount:2})).status,200,"GM can supply completed realms for remaining-item testing");
  const completed=(await storage.loadState(user))!.secret_realm!;
  assert.equal(completed.completed,true);assert.equal(completed.stage,6);
  assert.equal(completed.stash.filter(i=>i.id==="sword_5").length,2);
  console.log("GM_SECRET_REALM_SWORDS_SMOKE_OK validation auth initialization count level persistence versions completed");
}
void main();
