import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine=new GameEngine(gameConfigTables), service=engine.secretRealmService;
function fixture() {
  const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
  const p=state.secret_realm!;
  for(const c of p.cells.filter(c=>c.row<8)) {
    c.fog=false;delete c.monster;delete c.submitted;
    c.item={uid:engine._nextUid(state),id:"sword_1",immovable:true};
  }
  return {state,p,at:(col:number,row:number)=>p.cells.find(c=>c.col===col&&c.row===row)!};
}
for(const slots of [0,1,3]) {
  const {state,p,at}=fixture();
  at(2,2).item!.id="sword_6";
  at(0,0).item={uid:engine._nextUid(state),id:"sword_6",immovable:false};
  for(let x=0;x<slots;x++)delete at(x,1).item;
  // Revealing a preconfigured item must not include it in the drop manifest.
  at(3,2).fog=true;
  const hiddenUid=at(3,2).item!.uid;
  const before=new Set(p.cells.flatMap(c=>c.item?[c.item.uid]:[]));
  const body={action:"move",uid:at(0,0).item!.uid,col:2,row:2,period:p.period,version:p.version,
    request_id:`merge-effects-${slots}`,accept_reward_loss:true};
  const snapshot=structuredClone(state);
  assert.ok(!service.previewMerge(state,body).effects);
  assert.deepEqual(state,snapshot,"preview is read only");
  const result=service.transact(state,body);
  assert.equal(result.ok,true);assert.equal(result.effects.kind,"merge");
  const next=state.secret_realm!;
  const newDrops=next.cells.filter(c=>c.item&&!before.has(c.item.uid)&&!(c.col===2&&c.row===2));
  assert.deepEqual(result.effects.drops.map((d:any)=>d.item.uid).sort(),newDrops.map(c=>c.item!.uid).sort());
  assert.ok(!result.effects.drops.some((d:any)=>d.item.uid===hiddenUid));
  assert.ok(result.effects.drops.length<=3,"discarded drops have no visual manifest");
  for(const d of result.effects.drops)assert.deepEqual(next.cells.find(c=>c.col===d.col&&c.row===d.row)!.item,d.item);
  const after=structuredClone(state), replay=service.transact(state,body);
  assert.deepEqual(replay.effects,result.effects);assert.deepEqual(state,after);
}
for(const boss of [false,true]) {
  const {state,p,at}=fixture();
  const target=at(3,6);delete target.item;target.monster=boss?"boss_1":"mob_1";
  at(0,0).item={uid:engine._nextUid(state),id:boss?"qi_6":"qi_3",immovable:false};
  const body={action:"fight",uid:at(0,0).item!.uid,col:3,row:6,period:p.period,version:p.version,request_id:`kill-${boss}`};
  const before=structuredClone(state);
  assert.equal(service.transact(state,body).ok,true);
  const partial=state.secret_realm!.receipts.at(-1)!.effects!;
  assert.equal(partial.defeated,false);assert.equal(partial.drops.length,0);
  assert.deepEqual(partial.submitted,{[boss?"qi_6":"qi_3"]:1});
  Object.assign(state,before);
  const monster=state.secret_realm!.cells.find(c=>c.col===3&&c.row===6)!;
  monster.submitted={[boss?"sword_7":"sword_4"]:1};
  const result=service.transact(state,body), next=state.secret_realm!;
  assert.equal(result.ok,true);assert.equal(result.effects.defeated,true);
  assert.equal(result.effects.drops.length,4);
  assert.equal(result.effects.drops.filter((d:any)=>d.stash).length,2);
  for(const d of result.effects.drops) {
    const actual=next.cells.find(c=>c.item?.uid===d.item.uid)?.item??next.stash.find(i=>i.uid===d.item.uid);
    assert.deepEqual(actual,d.item);
  }
  if(boss) {
    assert.equal(next.start_row,4);
    assert.ok(result.effects.drops.some((d:any)=>d.row===0),"outgoing reward retains its pre-scroll landing position");
  }
  const snapshot=structuredClone(state);
  assert.deepEqual(service.transact(state,body).effects,result.effects);
  assert.deepEqual(state,snapshot,"replay returns the same manifest without new grants");
  assert.equal(service.transact(state,{...body,uid:999}).reason,"state_conflict");
}
console.log("SECRET_REALM_EFFECTS_SMOKE_OK: exact grants, no fog/previews/lost drops, partial/full combat, stash, Boss pre-scroll positions, replay");
