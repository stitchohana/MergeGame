import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { submitRealmMonster } from "./secret_realm_test_utils";

const engine=new GameEngine(gameConfigTables),service=engine.secretRealmService;
function swordDrops(level:number) {
  if(level<5)return [];
  const tier=Math.floor((level-5)/2)+1;
  return Array.from({length:Math.min(2,tier)},(_,i)=>({id:`sword_${Math.max(1,tier-1)+i}`,count:1,immovable:true}));
}
// Enforce the cap across every matching rule, counting quantities, not entries.
for(const overlap of [false,true]) {
  const config=structuredClone(gameConfigTables.secretRealm);
  if(overlap)config.merge_drops.push({min_level:7,max_level:8,drops:[{id:"sword_1",count:1,immovable:true}]});
  else config.merge_drops.find((r:any)=>r.drops.some((d:any)=>d.id==="sword_1"))!.drops[0].count=3;
  assert.throws(()=>new GameEngine({...gameConfigTables,secretRealm:config}),/invalid_secret_realm_config/);
}
function fixture(stashSource=false,emptyCount=0,sourceLevel=4) {
  const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
  const p=state.secret_realm!;
  for(const c of p.cells.filter(c=>c.row<8)) {
    c.fog=false;delete c.monster;c.item={uid:engine._nextUid(state),id:"sword_1",immovable:true};
  }
  const target=p.cells.find(c=>c.col===2&&c.row===2)!;
  target.item!.id=`sword_${sourceLevel}`;
  const source=p.cells.find(c=>c.col===0&&c.row===0)!;
  const item={uid:engine._nextUid(state),id:`sword_${sourceLevel}`,immovable:false};
  if(stashSource)p.stash.push(item);else source.item=item;
  for(const c of p.cells.filter(c=>c.row<8&&c!==target&&c!==source).slice(0,emptyCount))delete c.item;
  const body={action:stashSource?"place":"move",uid:item.uid,col:2,row:2,period:p.period,version:p.version,request_id:"space-test"};
  return {state,body,source,target};
}
// Exercise actual merges across all output levels: both drops start at level 5.
for(let level=2;level<=12;level++) {
  const tier=level>=5?Math.floor((level-5)/2)+1:0;
  const {state,body}=fixture(false,Math.max(1,Math.min(2,tier)),level-1);
  const oldUids=new Set(state.secret_realm!.cells.flatMap(c=>c.item?[c.item.uid]:[]));
  assert.deepEqual(service.previewMerge(state,body).lost_drops,[]);
  assert.equal(service.transact(state,body).ok,true);
  const cells=state.secret_realm!.cells;
  assert.equal(cells.find(c=>c.col===2&&c.row===2)!.item!.id,`sword_${level}`);
  const qi=cells.flatMap(c=>c.row<8&&c.item?.id.startsWith("qi_")?[c.item]:[]);
  assert.equal(qi.length,level>=5?1:0,`output level ${level} qi drops`);
  if(level>=5)assert.equal(qi[0].id,`qi_${Math.floor((level-5)/2)+1}`);
  assert.ok(qi.every(i=>!i.immovable));
  const source=cells.find(c=>c.col===0&&c.row===0)!;
  if(level<5)assert.equal(source.item,undefined,`level ${level} produces no drops`);
  const extra=cells.find(c=>c.col===1&&c.row===0)!;
  if(level<5)assert.equal(extra.item,undefined);
  else {
    const swords=cells.flatMap(c=>c.row<8&&c.item?.id.startsWith("sword_")&&c.item.immovable&&!oldUids.has(c.item.uid)?[c.item]:[]).sort((a,b)=>a.uid-b.uid);
    assert.deepEqual(swords.map(i=>({id:i.id,immovable:i.immovable})),swordDrops(level).map(({id,immovable})=>({id,immovable})));
    assert.ok(swords.length<=2,"each merge drops at most two swords in total");
  }
}
// Every tier reports the correct lost rewards and leaves an unconfirmed merge atomic.
for(let level=5;level<=12;level++) {
  const {state,body}=fixture(true,0,level-1),before=structuredClone(state);
  assert.deepEqual(service.previewMerge(state,body).lost_drops,[
    {id:`qi_${Math.floor((level-5)/2)+1}`,count:1,immovable:false},
    ...swordDrops(level),
  ]);
  assert.deepEqual(state,before);
  assert.equal(service.transact(state,body).reason,"merge_reward_overflow");
  assert.deepEqual(state,before);
  assert.equal(service.transact(state,{...body,accept_reward_loss:true}).ok,true);
  assert.equal(state.secret_realm!.cells.find(c=>c.col===2&&c.row===2)!.item!.id,`sword_${level}`);
  assert.equal(state.secret_realm!.stash.length,0);
  assert.ok(!state.secret_realm!.cells.some(c=>c.row<8&&c.item?.id.startsWith("qi_")),"confirmed lost rewards are not granted");
}
// A released source fits the qi; all fixed swords in the tier are lost.
for(let level=5;level<=12;level++) {
  const {state,body}=fixture(false,0,level-1);
  const preview=service.previewMerge(state,body);
  assert.deepEqual(preview.lost_drops,swordDrops(level));
  assert.equal(service.transact(state,{...body,accept_reward_loss:true}).ok,true);
  assert.equal(state.secret_realm!.cells.find(c=>c.col===0&&c.row===0)!.item!.id,`qi_${Math.floor((level-5)/2)+1}`);
}
// Partial space keeps qi then low swords; only the remaining higher swords are lost.
{
  const {state,body}=fixture(true,2,10),before=structuredClone(state);
  const preview=service.previewMerge(state,body);
  assert.equal(preview.free_cells,2);
  assert.deepEqual(preview.lost_drops,[{id:"sword_4",count:1,immovable:true}]);
  assert.equal(service.transact(state,body).reason,"merge_reward_overflow");
  assert.deepEqual(state,before,"cancelled rewards consume nothing");
  assert.equal(service.transact(state,{...body,accept_reward_loss:true}).ok,true);
  const p=state.secret_realm!;
  assert.equal(p.cells.find(c=>c.col===2&&c.row===0)!.item!.id,"qi_4");
  assert.deepEqual({id:p.cells.find(c=>c.col===1&&c.row===0)!.item!.id,immovable:p.cells.find(c=>c.col===1&&c.row===0)!.item!.immovable},{id:"sword_3",immovable:true});
  assert.equal(p.stash.length,0,"overflow does not enter stash");
  const after=structuredClone(state);
  assert.equal(service.transact(state,{...body,accept_reward_loss:true}).replayed,true);
  assert.deepEqual(state,after,"retries do not grant rewards twice");
}
// A full-board stash merge to level 2/3/4 needs no reward-loss confirmation.
for(let level=2;level<=4;level++) {
  const {state,body}=fixture(true,0,level-1);
  assert.deepEqual(service.previewMerge(state,body).lost_drops,[]);
  assert.equal(service.transact(state,body).ok,true);
  assert.equal(state.secret_realm!.stash.length,0);
}
// Full board: a board merge frees one source cell, so only the second drop is lost.
{
  const {state,body}=fixture();const before=structuredClone(state);
  const preview=service.previewMerge(state,body);
  assert.equal(preview.free_cells,1);
  assert.deepEqual(preview.lost_drops,[{id:"sword_1",count:1,immovable:true}]);
  assert.deepEqual(state,before,"preview is read-only, including UIDs/versions/receipts");
  assert.equal(service.transact(state,body).reason,"merge_reward_overflow");
  assert.deepEqual(state,before,"unconfirmed overflow consumes nothing");
  assert.equal(service.transact(state,{...body,accept_reward_loss:true}).ok,true);
  assert.equal(state.secret_realm!.cells.find(c=>c.col===2&&c.row===2)!.item!.id,"sword_5");
  assert.equal(state.secret_realm!.cells.find(c=>c.col===0&&c.row===0)!.item!.id,"qi_1");
  assert.equal(state.secret_realm!.stash.length,0,"lost drops never move to stash");
  const after=structuredClone(state);
  assert.equal(service.transact(state,{...body,accept_reward_loss:true}).replayed,true);
  assert.deepEqual(state,after);
  assert.equal(service.transact(state,body).reason,"state_conflict","confirmation flag is signed");
  assert.deepEqual([state.stamina,state.spirit_stones],[before.stamina,before.spirit_stones]);
}
// Supply from stash frees no board cell. Both drops are lost unless space exists.
for(const count of [0,1,2]) {
  const {state,body}=fixture(true,count);
  const preview=service.previewMerge(state,body);
  assert.equal(preview.free_cells,count);
  assert.equal(preview.lost_drops.reduce((n:number,d:any)=>n+d.count,0),Math.max(0,2-count));
  assert.equal(service.transact(state,{...body,accept_reward_loss:true}).ok,true);
  assert.equal(state.secret_realm!.stash.length,0);
}
// Existing empty plus released source provides exactly two cells: no confirmation.
{
  const {state,body}=fixture(false,1);
  assert.deepEqual(service.previewMerge(state,body).lost_drops,[]);
  assert.equal(service.transact(state,body).ok,true);
}
// A hidden empty four-neighbor becomes available after this merge; diagonal stays hidden.
{
  const {state,body}=fixture();const p=state.secret_realm!;
  const neighbor=p.cells.find(c=>c.col===2&&c.row===3)!;neighbor.fog=true;delete neighbor.item;
  const diagonal=p.cells.find(c=>c.col===3&&c.row===3)!;diagonal.fog=true;delete diagonal.item;
  assert.deepEqual(service.previewMerge(state,body).lost_drops,[]);
  assert.equal(service.transact(state,body).ok,true);
  assert.equal(state.secret_realm!.cells.find(c=>c.col===3&&c.row===3)!.fog,true);
}
// Preview approval expires on any intervening action; type coercion never approves.
{
  const {state,body}=fixture();
  service.previewMerge(state,body);service.awardOrder(state);
  const before=structuredClone(state);
  assert.equal(service.transact(state,{...body,accept_reward_loss:true}).reason,"state_conflict");
  assert.equal(service.transact(state,{...body,version:state.secret_realm!.version,accept_reward_loss:"true"}).reason,"invalid_params");
  assert.deepEqual(state,before);
}
const levels:Array<{row:number;level:number}>=gameConfigTables.secretRealm.layout.filter((c:any)=>c.id.startsWith("sword_")&&c.immovable).map((c:any)=>({row:c.row,level:Number(c.id.split('_')[1])}));
assert.ok(new Set(levels.map(c=>c.level)).size>1);
for(const a of levels)for(const b of levels)if(a.row<b.row)assert.ok(a.level<=b.level);

function scatterFixture(startRow=0) {
  const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
  state.secret_realm!.start_row=startRow;
  for(const c of state.secret_realm!.cells) { c.fog=false;delete c.item;delete c.monster; }
  const at=(col:number,row:number)=>state.secret_realm!.cells.find(c=>c.col===col&&c.row===row)!;
  const put=(col:number,row:number,id:string,immovable=false)=>at(col,row).item={uid:engine._nextUid(state),id,immovable};
  return {state,at,put};
}
// Merge rewards spread from the OUTPUT, skip occupied/hidden cells, then expand diagonally.
// Reordered save arrays must give exactly the same destinations.
for(const reverse of [false,true]) {
  const {state,at,put}=scatterFixture();
  put(3,5,"sword_10",true);const source=put(0,0,"sword_10");
  const blocker=put(3,4,"sword_1",true);at(2,4).fog=true;at(4,5).monster="mob_1";
  const p=state.secret_realm!;
  if(reverse)p.cells.reverse();
  const body={action:"move",uid:source.uid,col:3,row:5,period:p.period,version:p.version,request_id:"scatter-merge"};
  const before=structuredClone(state);
  assert.deepEqual(service.previewMerge(state,body).lost_drops,[]);
  assert.deepEqual(state,before);
  assert.equal(service.transact(state,body).ok,true);
  const placed=(col:number,row:number)=>state.secret_realm!.cells.find(c=>c.col===col&&c.row===row)!;
  for(const [col,row,id] of [[2,5,"qi_4"],[3,6,"sword_3"],[4,4,"sword_4"]] as const) {
    assert.equal(placed(col,row).item!.id,id,`${id} lands near merge output`);
  }
  assert.deepEqual(placed(3,4).item,blocker);
  assert.equal(placed(2,4).fog,true);assert.equal(placed(2,4).item,undefined);
  assert.equal(placed(4,5).monster,"mob_1");
  assert.equal(placed(0,0).item,undefined,"distant released source is not preferred");
  assert.equal(placed(2,6).item,undefined,"no third sword drop");
  assert.equal(placed(4,6).item,undefined,"no fourth sword drop");
  const saved=structuredClone(state);
  assert.equal(service.transact(state,body).replayed,true);assert.deepEqual(state,saved);
}
// Mobs and advancing/final Bosses all scatter from their original location.
for(const monsterId of ["mob_1","boss_1","boss_6"]) {
  const start=monsterId==="boss_6"?20:0;
  const {state,at,put}=scatterFixture(start),p=state.secret_realm!;
  p.stage=monsterId==="boss_6"?5:0;
  at(4,start+6).monster=monsterId;
  at(4,start+5).fog=true;
  // A fixed item blocks Boss reward scatter without violating the mob prerequisite.
  if(monsterId.startsWith("boss_"))put(5,start+6,"sword_1",true);
  else at(5,start+6).monster="mob_2";
  const monster=gameConfigTables.secretRealm.monsters.find((m:any)=>m.id===monsterId)!;
  for(const cost of monster.costs)for(let n=0;n<cost.count;n++)p.stash.push({uid:engine._nextUid(state),id:cost.id,immovable:false});
  const balances=[state.stamina,state.spirit_stones];
  const body=submitRealmMonster(engine,state,4,start+6,`scatter-${monsterId}`);
  const cells=state.secret_realm!.cells;
  const expected=monster.drops.flatMap((d:any)=>Array(d.count).fill(d.id));
  const spots=[[4,start+6],[3,start+6],[4,start+7],[3,start+5]];
  assert.deepEqual(spots.map(([col,row])=>cells.find(c=>c.col===col&&c.row===row)!.item!.id),expected);
  assert.ok(!cells.find(c=>c.col===0&&c.row===start)!.item,"far empty cell is left alone");
  assert.equal(cells.find(c=>c.col===4&&c.row===start+5)!.fog,true);
  const blocker=cells.find(c=>c.col===5&&c.row===start+6)!;
  if(monsterId.startsWith("boss_"))assert.equal(blocker.item!.id,"sword_1");
  else assert.equal(blocker.monster,"mob_2");
  assert.deepEqual([state.stamina,state.spirit_stones],balances,"physical rewards never credit resources");
  const saved=structuredClone(state);
  assert.equal(service.transact(state,body).replayed,true);assert.deepEqual(state,saved);
}
// At the viewport corner, scatter stays on-screen; combat overflow still enters stash.
{
  const {state,at,put}=scatterFixture();
  for(const c of state.secret_realm!.cells.filter(c=>c.row<8))put(c.col,c.row,"sword_1",true);
  delete at(5,7).item;at(5,7).monster="mob_1";
  delete at(0,0).item;
  const p=state.secret_realm!;
  for(const id of ["sword_4","qi_3"])p.stash.push({uid:engine._nextUid(state),id,immovable:false});
  submitRealmMonster(engine,state,5,7,"scatter-edge");
  const after=state.secret_realm!;
  assert.equal(after.cells.find(c=>c.col===5&&c.row===7)!.item!.id,"stamina_1");
  assert.equal(after.cells.find(c=>c.col===0&&c.row===0)!.item!.id,"stamina_1");
  assert.deepEqual(after.stash.map(i=>i.id),["stone_1","stone_1"]);
  assert.ok(after.cells.filter(c=>c.row>=8).every(c=>!c.item),"offscreen empty cells receive no rewards");
}
console.log("SECRET_REALM_MERGE_SPACE_SMOKE_OK");
