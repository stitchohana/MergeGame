import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { signToken } from "../src/middleware/auth";
import { WorkerResponse } from "../src/worker/http";
import { submitRealmMonster } from "./secret_realm_test_utils";

const engine=new GameEngine(gameConfigTables),service=engine.secretRealmService;
const realm=gameConfigTables.secretRealm;
assert.equal(realm.stages.length,6);assert.equal(realm.layout.length,168);
for(const cell of realm.layout)if(cell.id.startsWith("sword_")) {
  const expected=Math.min(11,Math.floor(cell.row/2)+1)-(cell.row>=12?1:0);
  assert.equal(cell.id,`sword_${expected}`);
}
for(let stage=1;stage<=6;stage++) {
  const mob=realm.monsters.find(m=>m.id===`mob_${stage}`)!;
  assert.deepEqual(mob.costs,[{id:`sword_${stage+3+(stage>=3?1:0)}`,count:1},{id:`qi_${Math.min(6,Math.max(3,stage+1))}`,count:1}]);
}
// Every stage counts living instances, including hidden mobs, but not offscreen mobs.
for(let stage=0;stage<realm.stages.length;stage++) {
  const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
  const p=()=>state.secret_realm!;
  p().stage=stage;p().start_row=stage*4;
  const staging=p().cells.find(c=>c.col===0&&c.row===p().start_row)!;delete staging.item;staging.fog=false;
  const current=(c:{row:number})=>c.row>=p().start_row&&c.row<p().start_row+8;
  const boss=p().cells.find(c=>c.monster===realm.stages[stage].boss)!;boss.fog=false;
  const mobs=p().cells.filter(c=>current(c)&&c.monster&&realm.monsters.some((m:any)=>m.id===c.monster&&!m.boss));
  // Unfinished overlap mobs from an older save are also prerequisites.
  assert.equal(mobs.length,stage===0?2:4);
  const grantCosts=(id:string)=>{
    for(const cost of realm.monsters.find((m:any)=>m.id===id)!.costs)
      for(let n=0;n<cost.count;n++)p().stash.push({uid:engine._nextUid(state),id:cost.id,immovable:false});
  };
  grantCosts(boss.monster!);
  let request=0;
  const body=(col:number,row:number)=>({action:"fight",col,row,period:p().period,version:p().version,request_id:`mob-gate-${stage}-${++request}`});
  const blocked=()=>{
    const before=structuredClone(state);
    assert.equal(service.transact(state,body(boss.col,boss.row)).reason,"mobs_remaining");
    assert.deepEqual(state,before,"blocked Boss never consumes costs, advances or records receipts");
  };
  assert.equal(service.view(state).remaining_mobs,mobs.length);
  assert.ok(service.view(state).cells.filter((c:any)=>c.fog).every((c:any)=>!c.enemy&&!c.monster));
  blocked();
  for(let n=0;n<mobs.length;n++) {
    const mob=p().cells.find(c=>c.col===mobs[n].col&&c.row===mobs[n].row)!;
    mob.fog=false;grantCosts(mob.monster!);
    submitRealmMonster(engine,state,mob.col,mob.row,`gate-mob-${stage}-${n}`);
    assert.equal(service.view(state).remaining_mobs,mobs.length-n-1);
    if(n<mobs.length-1)blocked();
  }
  // Earlier stages' remaining offscreen mobs deliberately survive in this fixture.
  if(stage>1)assert.ok(p().cells.some(c=>c.row<p().start_row&&c.monster?.startsWith("mob_")));
  const challenge=submitRealmMonster(engine,state,boss.col,boss.row,`gate-boss-${stage}`);
  assert.equal(p().stage,stage+1);
  assert.equal(service.view(state).remaining_mobs,stage===5?0:2);
  const saved=structuredClone(state);
  assert.equal(service.transact(state,challenge).replayed,true);
  assert.deepEqual(state,saved);
}
for(let stage=1;stage<=6;stage++) {
  const boss=realm.monsters.find((m:any)=>m.id===`boss_${stage}`)!;
  const qiCount=stage>=3?stage:1;
  assert.deepEqual(boss.costs,[{id:`sword_${stage+6}`,count:stage},{id:"qi_6",count:qiCount}]);
  const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
  const p=state.secret_realm!;p.stage=stage-1;p.start_row=(stage-1)*4;
  const staging=p.cells.find(c=>c.col===0&&c.row===p.start_row)!;delete staging.item;staging.fog=false;
  // Isolate Boss cost validation after the mob prerequisite has been satisfied.
  for(const c of p.cells)if(c.monster?.startsWith("mob_"))delete c.monster;
  const cell=p.cells.find(c=>c.monster===boss.id)!;cell.fog=false;
  const supply=(id:string,count=1,immovable=false)=>{for(let n=0;n<count;n++)p.stash.push({uid:engine._nextUid(state),id,immovable});};
  supply(`sword_${stage+6}`,stage);supply("qi_6",qiCount);
  supply(`sword_${stage+6}`,1,true);supply(`sword_${stage+5}`,stage);
  const spare=p.stash.filter(i=>i.id!=="qi_6"&&(i.id!==`sword_${stage+6}`||i.immovable));
  submitRealmMonster(engine,state,cell.col,cell.row,`six-cost-${stage}`,()=>{
    const target=state.secret_realm!.cells.find(c=>c.col===cell.col&&c.row===cell.row)!;
    assert.equal(target.monster,boss.id,"Boss survives until the last required item");
    assert.equal(target.submitted?.[`sword_${stage+6}`],stage);
    assert.equal(target.submitted?.qi_6??0,qiCount-1,"Boss requires every configured max-level qi");
    assert.equal(state.secret_realm!.stage,stage-1,"partial submission never advances");
  });
  const after=state.secret_realm!;
  for(const i of spare)assert.ok(after.stash.some(s=>s.uid===i.uid),"different-level and fixed swords are retained");
  assert.equal(after.stash.filter(i=>i.id===`sword_${stage+6}`&&!i.immovable).length,0);
  assert.equal(after.stash.filter(i=>i.id==="qi_6").length,0);
  assert.equal(after.stage,stage);assert.equal(after.completed,stage===6);
  assert.equal(after.start_row,stage===6?20:stage*4);
}

// Boss-centered 3x3 fog cannot be opened by merges; the final viewport mob
// reveals all nine cells atomically, preserving their original hidden contents.
for(let stage=0;stage<realm.stages.length;stage++) {
  const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
  const p=()=>state.secret_realm!;
  p().stage=stage;p().start_row=stage*4;
  const boss=p().cells.find(c=>c.monster===realm.stages[stage].boss)!;
  const inside=(c:{col:number;row:number})=>Math.abs(c.col-boss.col)<=1&&Math.abs(c.row-boss.row)<=1;
  const current=(c:{row:number})=>c.row>=p().start_row&&c.row<p().start_row+8;
  const at=(col:number,row:number)=>p().cells.find(c=>c.col===col&&c.row===row)!;
  const zone=()=>p().cells.filter(inside);
  assert.equal(zone().length,9);assert.ok(zone().every(c=>c.fog));
  const hidden=service.view(state).cells.filter((c:any)=>c.special_fog);
  assert.equal(hidden.length,9);
  assert.ok(hidden.every((c:any)=>Object.keys(c).sort().join(',')==='col,fog,row,special_fog'));
  let serial=0;
  const act=(action:string,more:any)=>service.transact(state,{action,period:p().period,version:p().version,request_id:`seal-${stage}-${++serial}`,...more});
  for(const c of p().cells.filter(current))if(!inside(c)&&!c.monster)c.fog=false;
  const source=at(0,p().start_row), target=at(1,boss.row-1), ordinary=at(0,boss.row-1);
  delete source.monster;source.item={uid:engine._nextUid(state),id:'sword_1',immovable:false};source.fog=false;
  target.item={uid:engine._nextUid(state),id:'sword_1',immovable:true};target.fog=false;ordinary.fog=true;
  const snapshot=structuredClone(state);
  const merge={action:'move',uid:source.item.uid,col:target.col,row:target.row,period:p().period,version:p().version,request_id:`seal-preview-${stage}`};
  assert.equal(service.previewMerge(state,merge).ok,true);assert.deepEqual(state,snapshot);
  assert.equal(service.transact(state,merge).ok,true);
  assert.ok(zone().every(c=>c.fog),'adjacent merges leave all special fog locked');
  assert.equal(at(ordinary.col,ordinary.row).fog,false,'ordinary cardinal fog still reveals');
  const beforeBlocked=structuredClone(state);
  assert.equal(act('place',{uid:p().stash[0]?.uid??999,col:boss.col,row:boss.row-1}).reason,'invalid_target');
  assert.deepEqual(state,beforeBlocked);
  const contents=zone().map(c=>({...structuredClone(c),fog:false}));
  const mobs=p().cells.filter(c=>current(c)&&c.monster&&realm.monsters.some(m=>m.id===c.monster&&!m.boss));
  assert.equal(service.view(state).remaining_mobs,mobs.length,'fogged and overlap mobs count');
  let last:any;
  for(const [n,mob] of mobs.entries()) {
    const cell=at(mob.col,mob.row);cell.fog=false;
    const def=realm.monsters.find(m=>m.id===cell.monster)!;
    for(const cost of def.costs)for(let i=0;i<cost.count;i++)p().stash.push({uid:engine._nextUid(state),id:cost.id,immovable:false});
    last=submitRealmMonster(engine,state,cell.col,cell.row,`seal-mob-${stage}-${n}`,()=>{
      assert.ok(zone().every(c=>c.fog),'partial mob submission never unlocks the seal');
    });
    assert.equal(service.view(state).remaining_mobs,mobs.length-n-1);
    assert.ok(zone().every(c=>c.fog===(n<mobs.length-1)));
  }
  assert.deepEqual(zone(),contents,'unsealing preserves all nine occupants, UIDs, levels and fixed flags');
  assert.equal(service.view(state).cells.filter((c:any)=>c.special_fog).length,0);
  assert.equal(service.view(state).cells.find((c:any)=>c.monster===realm.stages[stage].boss).enemy.boss,true);
  const saved=structuredClone(state);assert.equal(service.transact(state,last).replayed,true);assert.deepEqual(state,saved);
  assert.equal(service.view(JSON.parse(JSON.stringify(state))).cells.filter((c:any)=>c.special_fog).length,0,'saved unlock remains visible on reopen');
  for(const cost of realm.monsters.find(m=>m.id===realm.stages[stage].boss)!.costs)
    for(let i=0;i<cost.count;i++)p().stash.push({uid:engine._nextUid(state),id:cost.id,immovable:false});
  submitRealmMonster(engine,state,boss.col,boss.row,`seal-boss-${stage}`);
  assert.equal(p().stage,stage+1);
  assert.equal(service.view(state).cells.filter((c:any)=>c.special_fog).length,stage===5?0:9,'new stage has its own locked 3x3 seal');
}

async function main() {
  const storage=new MemoryStorage(),user="realm-current",secret="realm-expansion-test";
  const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);await storage.saveState(user,state);
  const router=createGameRouter(storage,engine,secret);
  const token=await signToken({userId:user,deviceId:"current"},secret);
  const get=async()=>{
    const response=new WorkerResponse();
    await router.handle({method:"GET",path:"/secret_realm",headers:{authorization:`Bearer ${token}`},query:{},body:{}},response);
    assert.equal(response.statusCode,200);return await response.toResponse().json() as any;
  };
  const first=await get();assert.equal(first.secret_realm.stage,0);assert.equal(first.secret_realm.start_row,0);
  assert.equal(first.secret_realm.completed,false);assert.equal(first.secret_realm.cells.length,48);
  const saved=(await storage.loadState(user))!;assert.equal(saved.secret_realm!.cells.length,168);
  assert.equal((await get()).storage_revision,first.storage_revision,"repeated GET neither changes nor saves initialized progress");
  assert.deepEqual(await storage.loadState(user),saved);
  saved.secret_realm!.stage=6;saved.secret_realm!.completed=true;saved.secret_realm!.start_row=20;
  const completed=structuredClone(saved);assert.equal(service.initialize(saved),false);assert.deepEqual(saved,completed);
  console.log("SECRET_REALM_EXPANSION_SMOKE_OK six_boss_costs atomicity current_progress completed_unchanged persistence idempotence");
}
void main();
