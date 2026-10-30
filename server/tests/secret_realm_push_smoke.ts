import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";

const engine=new GameEngine(gameConfigTables),service=engine.secretRealmService;
function fixture(start=0) {
  const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
  const p=state.secret_realm!;p.start_row=start;
  for(const cell of p.cells) {
    cell.fog=false;delete cell.monster;
    cell.item={uid:engine._nextUid(state),id:"sword_1",immovable:true};
  }
  const at=(x:number,y:number)=>p.cells.find(c=>c.col===x&&c.row===start+7-y)!;
  at(0,0).item!.immovable=false;at(2,3).item!.id="qi_1";at(2,3).item!.immovable=false;
  const body=()=>({action:"move",uid:at(0,0).item!.uid,col:2,row:start+4,
    period:p.period,version:p.version,request_id:`push-${start}`});
  return {state,p,at,body};
}
for(const start of [0,4,20])for(const reverse of [false,true]) {
  for(const [holes,expected] of [
    [[[3,3],[1,3],[2,4],[2,2]],[3,3]],
    [[[1,3],[2,4],[2,2]],[1,3]],
    [[[2,4],[2,2]],[2,4]],
    [[[5,7]],[5,7]], // Even a distant existing empty precedes the freed source.
    [[],[0,0]],
  ] as Array<[number[][],number[]]>) {
    const {state,p,at,body}=fixture(start);
    for(const [x,y] of holes)delete at(x,y).item;
    if(reverse)p.cells.reverse();
    const source=structuredClone(at(0,0).item!),target=structuredClone(at(2,3).item!);
    const before=structuredClone(state),request=body();
    assert.equal(service.previewMerge(state,request).ok,false);assert.deepEqual(state,before);
    // Compare against the real main-board push using identical screen occupancy.
    const main=engine.createInitialState();main.grid=[];
    for(let y=0;y<engine.GRID_ROWS;y++)for(let x=0;x<engine.GRID_COLS;x++) {
      if(holes.some(([hx,hy])=>hx===x&&hy===y))continue;
      main.grid.push({uid:engine._nextUid(main),id:x===2&&y===3?2001:1001,col:x,row:y,immovable:!(x===0&&y===0||x===2&&y===3)});
    }
    const mainResult=engine.pushAndPlace(main,0,0,2,3);assert.equal(mainResult.ok,true);
    if(mainResult.ok)assert.deepEqual([mainResult.pushed_col,mainResult.pushed_row],expected);
    assert.equal(service.transact(state,request).ok,true);
    const after=state.secret_realm!,dest=after.cells.find(c=>c.col===expected[0]&&c.row===start+7-expected[1])!;
    assert.deepEqual(dest.item,target);
    assert.deepEqual(after.cells.find(c=>c.col===2&&c.row===start+4)!.item,source);
    if(holes.length)assert.equal(after.cells.find(c=>c.col===0&&c.row===start+7)!.item,undefined);
    assert.deepEqual(after.cells.map(c=>[c.col,c.row,c.fog]),before.secret_realm!.cells.map(c=>[c.col,c.row,c.fog]));
    const oldUids=before.secret_realm!.cells.flatMap(c=>c.item?[c.item.uid]:[]).sort((a,b)=>a-b);
    assert.deepEqual(after.cells.flatMap(c=>c.item?[c.item.uid]:[]).sort((a,b)=>a-b),oldUids,"push never merges, drops or allocates instances");
    assert.equal(after.version,before.secret_realm!.version+1);
    assert.deepEqual(after.stash,before.secret_realm!.stash);
    const saved=structuredClone(state);assert.equal(service.transact(state,request).replayed,true);assert.deepEqual(state,saved);
  }
}
// Hidden cells, monsters and offscreen empties cannot receive a displaced item.
{
  const {state,p,at,body}=fixture();
  delete at(3,3).item;at(3,3).fog=true;
  delete at(1,3).item;at(1,3).monster="mob_1";
  delete at(2,4).item;delete at(2,2).item;
  delete p.cells.find(c=>c.col===2&&c.row===8)!.item;
  assert.equal(service.transact(state,body()).ok,true);
  const after=state.secret_realm!;
  assert.equal(after.cells.find(c=>c.col===2&&c.row===3)!.item!.id,"qi_1","down on screen precedes up");
  assert.equal(after.cells.find(c=>c.col===3&&c.row===4)!.fog,true);
  assert.equal(after.cells.find(c=>c.col===1&&c.row===4)!.monster,"mob_1");
}
// Max-level movable pairs push; fixed pairs merge only when an upgrade exists.
for(const id of ["sword_12","qi_6","stamina_3","stone_3"]) {
  const {state,at,body}=fixture();at(0,0).item!.id=id;at(2,3).item!.id=id;
  const source=at(0,0).item!.uid,target=at(2,3).item!.uid;
  assert.equal(service.transact(state,body()).ok,true);
  assert.equal(state.secret_realm!.cells.find(c=>c.col===0&&c.row===7)!.item!.uid,target);
  assert.equal(state.secret_realm!.cells.find(c=>c.col===2&&c.row===4)!.item!.uid,source);
}
for(const fixedSource of [false,true]) {
  const {state,at,body}=fixture();
  at(fixedSource?0:2,fixedSource?0:3).item!.immovable=true;
  const before=structuredClone(state);assert.equal(service.transact(state,body()).reason,"item_locked");assert.deepEqual(state,before);
}
{
  const {state,at,body}=fixture();at(2,3).item!.id="sword_1";at(2,3).item!.immovable=true;
  at(3,3).fog=true;
  assert.equal(service.transact(state,body()).ok,true);
  const target=state.secret_realm!.cells.find(c=>c.col===2&&c.row===4)!;
  assert.equal(target.item!.id,"sword_2");assert.equal(target.item!.immovable,false);
  assert.equal(state.secret_realm!.cells.find(c=>c.col===3&&c.row===4)!.fog,false);
}
console.log("SECRET_REALM_PUSH_SMOKE_OK: main-board parity, BFS ties, existing space, full swap, max pairs, locks, merge priority, replay");
