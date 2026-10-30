import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

// Play the shipped ascending map using actual supply/actions. Never edit fog,
// instances or monsters. Reserve workspace so the run loses no merge rewards.
const engine=new GameEngine(gameConfigTables),service=engine.secretRealmService;
const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
let requests=0,orders=0,merges=0;
const p=()=>state.secret_realm!;
const visible=()=>p().cells.filter(c=>c.row>=p().start_row&&c.row<p().start_row+8&&!c.fog);
const empty=()=>visible().filter(c=>!c.item&&!c.monster);
const movable=(id:string)=>p().stash.filter(i=>i.id===id&&!i.immovable);
function act(action:string,fields:any) {
  assert.ok(requests<250000,"bounded six-stage progression");
  const body={action,period:p().period,version:p().version,request_id:`play-${++requests}`,...fields};
  if(["move","place"].includes(action)&&visible().some(c=>c.col===fields.col&&c.row===fields.row&&c.item)) {
    const preview=service.previewMerge(state,body);
    assert.equal(preview.ok,true);
    assert.deepEqual(preview.lost_drops,[],"workspace prevents merge reward loss");
  }
  const result=service.transact(state,body);
  assert.equal(result.ok,true,JSON.stringify({action,fields,result}));
}
function recallAll() { for(const c of visible())if(c.item&&!c.item.immovable)act("recall",{uid:c.item.uid}); }
function supply() { service.awardOrder(state);orders++; }
function ensureSpace(minimum=2) {
  recallAll();
  while(empty().length<minimum) {
    const target=visible().filter(c=>c.item?.id.startsWith("sword_")&&c.item.immovable&&c.item.id!=="sword_12")
      .sort((a,b)=>Number(a.item!.id.split('_')[1])-Number(b.item!.id.split('_')[1]))[0];
    assert.ok(target,"a fixed sword can be cleared for workspace");
    assert.ok(empty().length>=1,"at least one workspace cell survives advancement");
    const id=target.item!.id;
    ensureMovable(id);
    if(!visible().some(c=>c.col===target.col&&c.row===target.row&&c.item?.id===id&&c.item.immovable))continue;
    const item=movable(id)[0],slot=empty()[0];
    act("place",{uid:item.uid,col:slot.col,row:slot.row});
    act("move",{uid:item.uid,col:target.col,row:target.row});merges++;
    recallAll();
  }
}
function ensureMovable(id:string,count=1) {
  while(movable(id).length<count) {
    const [chain,text]=id.split("_"),level=Number(text);
    if(id==="sword_1")supply();
    else if(id==="qi_1")mergeOne("sword_4");
    else mergeOne(`${chain}_${level-1}`);
  }
}
function mergeOne(id:string,preferred?:{col:number;row:number}) {
  const [chain,text]=id.split("_"),outputLevel=Number(text)+1;
  const dropCount=chain==="sword"?gameConfigTables.secretRealm.merge_drops
    .filter((r:any)=>outputLevel>=r.min_level&&outputLevel<=r.max_level).flatMap((r:any)=>r.drops).reduce((n:number,d:any)=>n+d.count,0):0;
  const workspace=Math.max(2,dropCount+1);
  ensureSpace(workspace);ensureMovable(id);
  let target=visible().find(c=>c.item?.id===id&&c.item.immovable&&(!preferred||c.col===preferred.col&&c.row===preferred.row));
  if(!target)ensureMovable(id,2);
  ensureSpace(workspace);
  target=visible().find(c=>c.item?.id===id&&c.item.immovable&&(!preferred||c.col===preferred.col&&c.row===preferred.row));
  const source=movable(id)[0],slot=empty().find(c=>!preferred||c.col!==preferred.col||c.row!==preferred.row)!;
  act("place",{uid:source.uid,col:slot.col,row:slot.row});
  if(!target) {
    const other=movable(id)[0];assert.ok(other);
    target=empty().find(c=>preferred&&c.col===preferred.col&&c.row===preferred.row)??empty()[0];
    act("place",{uid:other.uid,col:target.col,row:target.row});
  }
  act("move",{uid:source.uid,col:target.col,row:target.row});merges++;recallAll();
}
function submitMonster(col:number,row:number,costs:Array<{id:string;count:number}>) {
  for(const cost of [...costs].reverse())for(let n=0;n<cost.count;n++) {
    ensureMovable(cost.id);
    ensureSpace(1);
    const source=movable(cost.id)[0],slot=empty()[0];
    act("place",{uid:source.uid,col:slot.col,row:slot.row});
    act("fight",{uid:source.uid,col,row});
  }
}
recallAll();ensureSpace();
for(let stage=0;stage<gameConfigTables.secretRealm.stages.length;stage++) {
  for(let n=0;n<100;n++) {
    if(!p().cells.some(c=>c.row>=p().start_row&&c.row<p().start_row+8&&c.monster&&c.fog&&gameConfigTables.secretRealm.monsters.some(m=>m.id===c.monster&&!m.boss)))break;
    const ordinaryFog=new Set(service.view(state).cells.filter((c:any)=>c.fog&&!c.special_fog).map((c:any)=>`${c.col},${c.row}`));
    const frontier=visible().find(c=>c.item?.immovable&&p().cells.some(neighbor=>ordinaryFog.has(`${neighbor.col},${neighbor.row}`)&&Math.abs(neighbor.row-c.row)+Math.abs(neighbor.col-c.col)===1));
    if(!frontier) {
      // Without low-level qi drops, a revealed frontier may now be empty.
      const slot=empty().find(c=>p().cells.some(neighbor=>ordinaryFog.has(`${neighbor.col},${neighbor.row}`)&&Math.abs(neighbor.row-c.row)+Math.abs(neighbor.col-c.col)===1));
      assert.ok(slot,"a revealed frontier remains available for merging");
      mergeOne("sword_1",slot);
      continue;
    }
    const id=frontier.item!.id;
    ensureMovable(id);
    // Crafting the source may itself have merged and revealed this frontier.
    if(visible().some(c=>c.col===frontier.col&&c.row===frontier.row&&c.item?.immovable))mergeOne(id,frontier);
    assert.ok(n<99,"all monster fog can be revealed");
  }
  const mobs=visible().filter(c=>c.monster&&gameConfigTables.secretRealm.monsters.some((m:any)=>m.id===c.monster&&!m.boss));
  assert.equal(mobs.length,2);
  for(const mob of mobs) {
    const costs=service.view(state).cells.find((c:any)=>c.col===mob.col&&c.row===mob.row).enemy.costs;
    submitMonster(mob.col,mob.row,costs);recallAll();
  }
  assert.equal(service.view(state).remaining_mobs,0);
  const boss=visible().find(c=>c.monster===`boss_${stage+1}`);assert.ok(boss);
  const costs=service.view(state).cells.find((c:any)=>c.monster===boss.monster).enemy.costs;
  submitMonster(boss.col,boss.row,costs);
  assert.equal(p().stage,stage+1);recallAll();
  console.log(`SECRET_REALM_STAGE_OK: ${stage+1}, ${orders} orders, ${merges} merges, ${requests} actions`);
}
assert.equal(p().completed,true);
assert.ok(p().stash.some(i=>i.id==="stamina_2")&&p().stash.some(i=>i.id==="stone_2"));
console.log(`SECRET_REALM_PROGRESSION_OK: ${orders} orders, ${merges} merges, ${requests} actions, zero merge rewards lost`);
