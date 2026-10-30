import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";
import type { GameState } from "../src/storage/interface";
import { submitRealmMonster } from "./secret_realm_test_utils";

async function main() {
  const engine = new GameEngine(gameConfigTables), service = engine.secretRealmService;
  const s = engine.createInitialState();
  assert.equal(service.initialize(s), false);
  s.cultivation.current_level = 2;
  const main = structuredClone(s.grid);
  assert.equal(service.initialize(s), true);
  assert.equal(service.initialize(s), false);
  assert.equal(service.view(s).cells.length, 48);
  assert.equal(s.secret_realm!.cells.filter(c => !c.item?.immovable && c.item).length, 3);
  // All five advances reveal the incoming frontier and recover only disappearing rows.
  {
    const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
    const progress=()=>state.secret_realm!;
    for(const c of progress().cells) {
      c.fog=false;
      // This fixture isolates viewport recovery after clearing the mobs.
      if(c.monster?.startsWith("mob_"))delete c.monster;
      if(c.item) {
        c.item.id=c.col%2===0?"qi_2":"sword_2";
        c.item.immovable=c.col<3;
      }
    }
    for(const row of [0,4])progress().cells.find(c=>c.row===row&&c.col===4)!.fog=true;
    for(let stage=0;stage<gameConfigTables.secretRealm.stages.length;stage++) {
      const definition=gameConfigTables.secretRealm.monsters.find((m:any)=>m.id===`boss_${stage+1}`)!;
      for(const cost of definition.costs)for(let n=0;n<cost.count;n++)progress().stash.push({uid:engine._nextUid(state),id:cost.id,immovable:false});
      // Distinguish the incoming area's bottom row from the viewport's bottom row.
      if(stage<gameConfigTables.secretRealm.stages.length-1)
        for(const c of progress().cells)
          if([progress().start_row+4,progress().start_row+8,progress().start_row+9].includes(c.row))c.fog=true;
      const boss=progress().cells.find(c=>c.monster===`boss_${stage+1}`)!;
      // Keep one revealed workspace cell for the per-item board submissions.
      const staging=progress().cells.find(c=>c.col===0&&c.row===progress().start_row)!;
      delete staging.item;staging.fog=false;
      let before=structuredClone(progress());
      const body=submitRealmMonster(engine,state,boss.col,boss.row,`viewport-${stage}`,()=>{before=structuredClone(progress());});
      const after=progress();
      assert.equal(after.start_row,stage<gameConfigTables.secretRealm.stages.length-1?before.start_row+4:before.start_row);
      for(const c of before.cells) {
        const next=after.cells.find(n=>n.col===c.col&&n.row===c.row)!;
        const revealed=after.start_row>before.start_row&&c.row===before.start_row+8;
        assert.equal(next.fog,revealed?false:c.fog,"advancing reveals only the incoming area's bottom row");
      }
      if(after.start_row>before.start_row) {
        const bottom=service.view(state).cells.filter((c:any)=>c.row===before.start_row+8);
        assert.equal(bottom.length,6);
        assert.ok(bottom.every((c:any)=>!c.fog),"all six incoming frontier cells are immediately revealed without a merge");
      }
      const recovered:number[]=[];
      for(const c of before.cells)if(c.item) {
        const next=after.cells.find(n=>n.col===c.col&&n.row===c.row)!;
        if(c.item.uid===body.uid) {
          assert.ok(![...after.stash,...after.cells.flatMap(n=>n.item?[n.item]:[])].some(i=>i.uid===body.uid));
          continue;
        }
        const leaving=c.row>=before.start_row&&c.row<before.start_row+8&&c.row<after.start_row;
        if(leaving) {
          assert.equal(next.item,undefined);
          const stored=after.stash.find(i=>i.uid===c.item!.uid);
          assert.deepEqual(stored,c.fog?undefined:{...c.item,immovable:false},"outgoing revealed items unlock when recovered into stash");
          if(!c.fog)recovered.push(c.item.uid);
        } else {
          assert.deepEqual(next.item,c.item,"retained and future cells preserve UID, item and lock");
          assert.ok(!after.stash.some(i=>i.uid===c.item!.uid));
        }
      }
      const originalUids=new Set(before.cells.flatMap(c=>c.item?[c.item.uid]:[]));
      assert.deepEqual(after.stash.filter(i=>originalUids.has(i.uid)).map(i=>i.uid).sort((a,b)=>a-b),recovered.sort((a,b)=>a-b));
      const all=[...after.stash,...after.cells.flatMap(c=>c.item?[c.item]:[])];
      assert.equal(new Set(all.map(i=>i.uid)).size,all.length,"recovery never duplicates an instance");
      const saved=structuredClone(state);
      assert.equal(service.transact(state,body).replayed,true);
      assert.deepEqual(state,saved);
      if(after.start_row>before.start_row)for(const id of ["sword_2","qi_2"]) {
        const fixed=before.cells.find(c=>c.item?.id===id&&c.item.immovable&&!c.fog&&c.row>=before.start_row&&c.row<after.start_row)!;
        assert.ok(fixed,"a fixed item of each chain leaves the viewport");
        const mobility=structuredClone(state), mp=mobility.secret_realm!;
        const item=mp.stash.find(i=>i.uid===fixed.item!.uid)!;
        assert.equal(item.immovable,false);
        for(const col of [0,1,2]) {
          const slot=mp.cells.find(c=>c.col===col&&c.row===mp.start_row)!;
          slot.fog=false;delete slot.monster;delete slot.item;
          if(col===2)slot.item={uid:engine._nextUid(mobility),id,immovable:true};
        }
        const use=(action:string,col:number)=>service.transact(mobility,{action,col,row:mp.start_row,uid:item.uid,
          period:mp.period,version:mobility.secret_realm!.version,request_id:`recovered-${stage}-${id}-${action}-${col}`});
        assert.equal(use("place",0).ok,true,"recovered items can be placed");
        assert.equal(use("move",1).ok,true,"recovered fixed items can be dragged after placement");
        assert.equal(use("move",2).ok,true,"recovered fixed items can act as merge sources");
        const merged=mobility.secret_realm!.cells.find(c=>c.col===2&&c.row===mp.start_row)!.item!;
        assert.equal(merged.id,id==="sword_2"?"sword_3":"qi_3");assert.equal(merged.immovable,false);
      }
    }
  }
  // Shipped fixed qi is hidden until an adjacent merge, then unlocks by merging.
  {
    const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
    const progress=()=>state.secret_realm!;
    const at=(col:number,row:number)=>progress().cells.find(c=>c.col===col&&c.row===row)!;
    let request=0;
    const action=(kind:string,fields:any)=>service.transact(state,{action:kind,period:progress().period,version:progress().version,request_id:`fixed-qi-${++request}`,...fields});
    const hidden=service.view(state).cells.find((c:any)=>c.col===0&&c.row===3);
    assert.deepEqual(Object.keys(hidden).sort(),["col","fog","row"]);
    assert.equal(action("move",{uid:at(0,0).item!.uid,col:0,row:1}).ok,true);
    assert.equal(action("move",{uid:at(0,1).item!.uid,col:0,row:2}).ok,true);
    const fixed=at(0,3).item!;
    assert.equal(at(0,3).fog,false);assert.equal(fixed.id,"qi_1");assert.equal(fixed.immovable,true);
    const before=structuredClone(state);
    assert.equal(action("move",{uid:fixed.uid,col:0,row:0}).reason,"item_locked");
    assert.equal(action("recall",{uid:fixed.uid}).reason,"item_locked");
    assert.deepEqual(state,before);
    assert.equal(service.view(state).inventory.qi_1,undefined,"fixed qi cannot pay monster costs");
    const supply={uid:engine._nextUid(state),id:"qi_1",immovable:false};progress().stash.push(supply);
    assert.equal(action("place",{uid:supply.uid,col:0,row:3}).ok,true);
    assert.equal(at(0,3).item!.id,"qi_2");assert.equal(at(0,3).item!.immovable,false);
    assert.equal(action("move",{uid:at(0,3).item!.uid,col:0,row:1}).ok,true);
  }
  const p = () => s.secret_realm!;
  let request = 0;
  const body = (action: string, more: any = {}) => ({ action, period: p().period, version: p().version, request_id: `realm-${++request}`, ...more });
  const act = (action: string, more: any = {}) => service.transact(s, body(action, {accept_reward_loss:true,...more}));
  const cell = (col: number, row: number) => p().cells.find(c => c.col === col && c.row === row)!;
  const unchanged = (action: string, more: any) => { const before = structuredClone(s); assert.equal(act(action, more).ok, false); assert.deepEqual(s, before); };
  unchanged("move", { uid: cell(5, 0).item!.uid, col: 4, row: 0 });
  unchanged("move", { uid: cell(0, 0).item!.uid, col: 0, row: 3 });
  assert.equal(act("move", { uid: cell(0, 0).item!.uid, col: 0, row: 1 }).ok, true);
  assert.equal(cell(0, 1).item!.id, "sword_2");
  assert.equal(cell(0, 1).item!.immovable, false);
  assert.ok(!p().cells.some(c => c.item?.id === "qi_1" && !c.item.immovable), "low-level swords produce no qi");
  // Target-cardinal reveal, including edge boundaries; source and diagonals do not reveal.
  for (const c of p().cells) c.fog = true;
  cell(2, 1).fog = cell(2, 2).fog = false;
  cell(2, 1).item!.immovable = false;
  cell(2, 1).item!.id = cell(2, 2).item!.id;
  assert.equal(act("move", { uid: cell(2, 1).item!.uid, col: 2, row: 2 }).ok, true);
  for (const [x,y] of [[1,2],[3,2],[2,1],[2,3]]) assert.equal(cell(x,y).fog, false);
  assert.equal(cell(1,3).fog, true);
  assert.equal(cell(1,1).fog, true);
  const hidden = service.view(s).cells.find((c: any) => c.col === 1 && c.row === 3);
  assert.deepEqual(Object.keys(hidden).sort(), ["col", "fog", "row"]);
  const put = (id: string, immovable = false) => { const i = { uid: engine._nextUid(s), id, immovable }; p().stash.push(i); return i; };
  const occupy = (x: number, y: number, id: string, immovable = false) => { const c = cell(x,y); c.fog = false; delete c.monster; c.item = { uid: engine._nextUid(s), id, immovable }; return c.item.uid; };
  unchanged("use", { uid: put("stamina_1").uid });
  const stamina = s.stamina;
  const reward = put("stamina_2"), use = body("use", { uid: reward.uid });
  assert.equal(service.transact(s, use).ok, true);
  assert.ok(s.stamina > stamina);
  const afterUse = structuredClone(s);
  assert.equal(service.transact(s, use).replayed, true);
  assert.deepEqual(s, afterUse);
  assert.equal(service.transact(s, { ...use, uid: reward.uid + 1 }).reason, "state_conflict");
  for (const chain of ["sword", "qi", "stamina", "stone"]) {
    const cap = chain === "sword" ? 12 : chain === "qi" ? 6 : 3;
    const uid = occupy(0,1,`${chain}_${cap}`); occupy(0,2,`${chain}_${cap}`);
    assert.equal(act("move",{uid,col:0,row:2}).ok,true,"max-level unlocked pairs push instead of merging");
  }
  // Every chain reveals cardinal fog and never grants currency during merging.
  for (const chain of ["sword", "qi", "stamina", "stone"]) {
    for (const c of p().cells) c.fog=true;
    const uid=occupy(1,1,`${chain}_1`);occupy(2,2,`${chain}_1`);
    const balances=[s.stamina,s.spirit_stones];
    assert.equal(act("move",{uid,col:2,row:2}).ok,true);
    assert.equal(cell(2,2).item!.id,`${chain}_2`);
    assert.equal(cell(1,2).fog,false);assert.equal(cell(2,3).fog,false);
    assert.equal(cell(3,3).fog,true);assert.equal(cell(0,1).fog,true);
    assert.deepEqual([s.stamina,s.spirit_stones],balances);
  }
  // Recall and placement preserve identity and lock status and do not reveal fog.
  const recalled=occupy(0,1,"qi_2");
  assert.equal(act("recall",{uid:recalled}).ok,true);
  assert.ok(!cell(0,1).item);
  const fogBefore=p().cells.map(c=>c.fog);
  assert.equal(act("place",{uid:recalled,col:0,row:1}).ok,true);
  assert.equal(cell(0,1).item!.uid,recalled);
  assert.deepEqual(p().cells.map(c=>c.fog),fogBefore);
  assert.equal(act("recall",{uid:recalled}).ok,true);
  const fixedSupply=put("sword_1",true);
  assert.equal(act("place",{uid:fixedSupply.uid,col:0,row:1}).ok,true);
  unchanged("recall",{uid:fixedSupply.uid});
  // Supply dragged from stash merges exactly like an unlocked board source.
  for (const chain of ["sword", "qi", "stamina", "stone"]) {
    const uid=put(`${chain}_1`).uid;
    occupy(0,1,`${chain}_1`,["sword","qi"].includes(chain));
    assert.equal(act("place",{uid,col:0,row:1}).ok,true);
    assert.equal(cell(0,1).item!.id,`${chain}_2`);
    assert.equal(cell(0,1).item!.immovable,false);
    assert.ok(!p().stash.some(i=>i.uid===uid));
  }
  const lockedSource=put("sword_1",true).uid;
  occupy(0,1,"sword_1",true);
  unchanged("place",{uid:lockedSource,col:0,row:1});
  unchanged("place",{uid:put("qi_1").uid,col:0,row:1});
  occupy(0,1,"qi_6");
  unchanged("place",{uid:put("qi_6").uid,col:0,row:1});
  // Full-board merge drops fill the source cell and discard confirmed overflow.
  for (const c of p().cells.filter(c => c.row < 8)) { c.fog = false; delete c.monster; c.item = { uid: engine._nextUid(s), id:"sword_1", immovable:true }; }
  const uid = occupy(0,0,"sword_4"); occupy(0,1,"sword_4",true);
  const stashBefore = p().stash.length;
  assert.equal(act("move", { uid, col:0,row:1 }).ok,true);
  assert.equal(p().stash.length,stashBefore);
  assert.ok([...p().stash,...p().cells.flatMap(c=>c.item?[c.item]:[])].some(i=>i.id==="sword_1"&&i.immovable));
  // Combat: no currency is awarded before reward items are merged and used.
  delete cell(1,4).item; cell(1,4).monster="mob_1"; cell(1,4).fog=false;
  unchanged("fight", { col:1,row:4 });
  put("sword_4"); put("qi_3");
  delete cell(0,0).item;
  const stones=s.spirit_stones, energy=s.stamina;
  submitRealmMonster(engine,s,1,4,"combat-mob");
  assert.equal(s.spirit_stones,stones); assert.equal(s.stamina,energy);
  assert.ok([...p().stash,...p().cells.flatMap(c=>c.item?[c.item]:[])].some(i=>i.id==="stone_1"));
  // Hidden inventory and locked swords never satisfy costs.
  p().stash=p().stash.filter(i=>!["sword_7","qi_6"].includes(i.id));
  for(const c of p().cells)if(c.item&&["sword_7","qi_6"].includes(c.item.id))delete c.item;
  delete cell(3,6).item; cell(3,6).monster="boss_1"; cell(3,6).fog=false;
  occupy(5,5,"sword_7",true); occupy(5,6,"qi_6"); cell(5,6).fog=true;
  unchanged("fight",{col:3,row:6});
  put("sword_7"); put("qi_6");
  const rescued=cell(5,0).item!; cell(4,0).fog=true; const hiddenUid=cell(4,0).item!.uid;
  submitRealmMonster(engine,s,3,6,"combat-boss-1");
  assert.equal(p().start_row,4); assert.equal(p().stage,1);
  assert.ok(p().stash.some(i=>i.uid===rescued.uid&&!i.immovable));
  assert.ok(!p().stash.some(i=>i.uid===hiddenUid));
  assert.equal(service.view(s).cells.length,48);
  for (let n=2;n<=gameConfigTables.secretRealm.stages.length;n++) {
    for(const c of p().cells)if(c.monster?.startsWith("mob_")&&c.row>=p().start_row&&c.row<p().start_row+8)delete c.monster;
    const boss = cell(3,2+n*4); boss.fog=false;
    const monster=gameConfigTables.secretRealm.monsters.find((m:any)=>m.id===`boss_${n}`)!;
    for(const cost of monster.costs)for(let count=0;count<cost.count;count++)put(cost.id);
    submitRealmMonster(engine,s,3,boss.row,`combat-boss-${n}`);
  }
  assert.equal(p().completed,true);
  const count=p().stash.length; service.awardOrder(s); assert.equal(p().stash.length,count);
  assert.deepEqual(s.grid,main,"realm never mutates the main board");
  // Successful main-board orders only; no battle-board or failed-order supply.
  const orderState=engine.createInitialState();orderState.cultivation.current_level=2;
  orderState.meridian_acupoints=[{item_ids:[1001],fixed_order_rewards:true,rewards:{}}] as any;
  orderState.grid=[{id:1001,uid:engine._nextUid(orderState),col:0,row:0}];
  assert.equal(engine.completeMeridianAcupoint(orderState,99,[1001],"bad").ok,false);
  assert.equal(orderState.secret_realm,undefined);
  assert.equal(engine.completeMeridianAcupoint(orderState,0,[1001],"valid-order").ok,true);
  assert.equal(orderState.secret_realm!.stash.length,3);
  const orderProgress=structuredClone(orderState.secret_realm);
  assert.equal(engine.completeMeridianAcupoint(orderState,0,[1001],"valid-order").ok,false);
  assert.deepEqual(orderState.secret_realm,orderProgress);
  orderState.board_type=1;
  service.awardOrder(orderState);
  assert.deepEqual(orderState.secret_realm,orderProgress);
  // Order supply uses the current cultivation at settlement, including realm boundaries.
  {
    const state = engine.createInitialState();
    for (let level = 2; level <= engine.cultivationStages.length; level++) {
      state.cultivation.current_level = level;
      state.meridian_acupoints = [{item_ids:[1001],fixed_order_rewards:true,rewards:{}}] as any;
      state.grid = [{id:1001,uid:engine._nextUid(state),col:0,row:0}];
      const before = structuredClone(state.secret_realm);
      assert.equal(engine.completeMeridianAcupoint(state,99,[1001],`supply-failed-${level}`).ok,false);
      assert.deepEqual(state.secret_realm,before);
      const start = state.secret_realm?.stash.length ?? 0;
      assert.equal(engine.completeMeridianAcupoint(state,0,[1001],`supply-${level}`).ok,true);
      const granted = state.secret_realm!.stash.slice(start);
      const cap = level >= 17 && level <= 19 ? 4 : level >= 14 && level <= 16 ? 3 : level >= 11 && level <= 13 ? 2 : 0;
      const expected = cap ? Array.from({length:cap},(_,i)=>Array(3).fill(`sword_${i+1}`)).flat() : ["sword_1","sword_1","sword_1"];
      assert.deepEqual(granted.map(i=>i.id),expected,engine.cultivationStages[level-1].name);
      assert.ok(granted.every(i=>!i.immovable));
      const all = [...state.secret_realm!.stash,...state.secret_realm!.cells.flatMap(c=>c.item?[c.item]:[])];
      assert.equal(new Set(all.map(i=>i.uid)).size,all.length);
      const settled = structuredClone(state.secret_realm);
      assert.equal(engine.completeMeridianAcupoint(state,0,[1001],`supply-${level}`).ok,false);
      assert.deepEqual(state.secret_realm,settled);
      state.board_type = 1; service.awardOrder(state);
      assert.deepEqual(state.secret_realm,settled);
      state.board_type = 0; state.secret_realm!.completed = true;
      const completed = structuredClone(state.secret_realm);
      service.awardOrder(state); assert.deepEqual(state.secret_realm,completed);
      state.secret_realm!.completed = false;
    }
    for (const edit of [
      (c:any)=>c.order_supply_realms[0].cultivation_min=0,
      (c:any)=>c.order_supply_realms[1].cultivation_min=13,
      (c:any)=>c.order_supply_realms[0].drops[0].immovable=true,
      (c:any)=>c.order_supply_realms[0].drops[0].id="qi_1",
      (c:any)=>c.order_supply_realms[0].drops=[],
    ]) {
      const config = structuredClone(gameConfigTables); edit(config.secretRealm);
      assert.throws(()=>new GameEngine(config),/invalid_secret_realm_config/);
    }
  }
  // Per-instance submissions persist independently for identical monsters.
  {
    const state=engine.createInitialState();state.cultivation.current_level=2;service.initialize(state);
    const p=()=>state.secret_realm!;
    const at=(col:number,row:number)=>p().cells.find(c=>c.col===col&&c.row===row)!;
    at(1,4).fog=false;at(4,4).fog=false;
    const putSource=(id:string,immovable=false)=>{
      at(0,0).fog=false;at(0,0).item={uid:engine._nextUid(state),id,immovable};return at(0,0).item!.uid;
    };
    let serial=0;
    const submit=(uid:number,col=1,row=4)=>({action:"fight",uid,col,row,period:p().period,version:p().version,request_id:`single-${++serial}`});
    const reject=(body:any,reason:string)=>{
      const before=structuredClone(state);assert.equal(service.transact(state,body).reason,reason);assert.deepEqual(state,before);
    };
    reject(submit(putSource("sword_3")),"wrong_submission");
    reject(submit(putSource("stone_2")),"wrong_submission");
    reject(submit(putSource("sword_4",true)),"item_locked");
    const hiddenUid=putSource("sword_4");at(0,0).fog=true;
    reject(submit(hiddenUid),"invalid_source");at(0,0).fog=false;
    const offscreen=at(0,8);offscreen.fog=false;
    reject(submit(offscreen.item!.uid),"invalid_source");
    const stored={uid:engine._nextUid(state),id:"sword_4",immovable:false};p().stash.push(stored);
    reject(submit(stored.uid),"invalid_source");
    const balances=[state.stamina,state.spirit_stones];
    const first=submit(hiddenUid);assert.equal(service.transact(state,first).ok,true);
    assert.equal(at(0,0).item,undefined);assert.equal(at(1,4).monster,"mob_1");
    assert.deepEqual(at(1,4).submitted,{sword_4:1});assert.equal(at(4,4).submitted,undefined);
    assert.equal(p().stage,0);assert.equal(p().start_row,0);
    assert.ok(!p().cells.some(c=>c.item?.id.startsWith("stamina_")||c.item?.id.startsWith("stone_")),"partial delivery gives no rewards");
    const after=structuredClone(state);assert.equal(service.transact(state,first).replayed,true);assert.deepEqual(state,after);
    reject({...first,uid:stored.uid},"state_conflict");
    reject(submit(putSource("sword_4")),"requirement_filled");
    const storage=new MemoryStorage();await storage.saveState("partial-realm",state);
    const restored=(await storage.loadState("partial-realm"))!;
    assert.equal(service.initialize(restored),false);
    const progressView=service.view(restored).cells.find((c:any)=>c.col===1&&c.row===4);
    assert.deepEqual(progressView.submitted,{sword_4:1});
    const freshEngine=new GameEngine(gameConfigTables);
    const restoredSource=restored.secret_realm!.cells.find(c=>c.col===0&&c.row===0)!;
    restoredSource.item={uid:freshEngine._nextUid(restored),id:"qi_3",immovable:false};
    const last={...submit(restoredSource.item.uid),version:restored.secret_realm!.version};
    assert.equal(freshEngine.secretRealmService.transact(restored,last).ok,true);
    const defeated=restored.secret_realm!.cells.find(c=>c.col===1&&c.row===4)!;
    assert.equal(defeated.monster,undefined);assert.equal(defeated.submitted,undefined);
    assert.equal(restored.secret_realm!.cells.find(c=>c.col===4&&c.row===4)!.monster,"mob_1");
    assert.deepEqual([restored.stamina,restored.spirit_stones],balances);
    const completed=structuredClone(restored);assert.equal(service.transact(restored,last).replayed,true);assert.deepEqual(restored,completed);
  }
  // Persistence, concurrency and retry through the actual auth/router stack.
  class FailingStorage extends MemoryStorage { fail=false; async saveState(id:string,state:GameState) { if(this.fail){this.fail=false;throw Error("test_save_failure");} return super.saveState(id,state); } }
  const storage=new FailingStorage(), user="realm-test";
  const initial=engine.createInitialState();initial.cultivation.current_level=2;
  service.initialize(initial);initial.secret_realm!.stash.push({uid:engine._nextUid(initial),id:"stone_2",immovable:false});
  const gatedBoss=initial.secret_realm!.cells.find(c=>c.monster==="boss_1")!;gatedBoss.fog=false;
  for(const id of ["sword_7","qi_6"])initial.secret_realm!.stash.push({uid:engine._nextUid(initial),id,immovable:false});
  await storage.saveState(user,initial);
  const router=createGameRouter(storage,engine,"test-secret"),token=await signToken({userId:user,deviceId:"test"},"test-secret");
  async function send(payload:any) { const response=new WorkerResponse();await router.handle({method:"POST",path:"/secret_realm/action",body:payload,headers:{authorization:`Bearer ${token}`},query:{}},response);return {status:response.statusCode,data:await response.toResponse().json() as any}; }
  const warm = new WorkerResponse();
  await router.handle({method:"GET",path:"/secret_realm",body:{},headers:{authorization:`Bearer ${token}`},query:{}},warm);
  assert.equal(warm.statusCode,200);
  const beforeGate=await storage.loadState(user);
  const denied=await send({action:"fight",col:gatedBoss.col,row:gatedBoss.row,version:0,period:initial.secret_realm!.period,request_id:"http-boss-gate"});
  assert.equal(denied.status,400);assert.equal(denied.data.error,"mobs_remaining");
  assert.deepEqual(await storage.loadState(user),beforeGate,"blocked HTTP Boss challenge never saves or consumes supplies");
  // Actual preview route is read-only, including persistent revision/receipts.
  const previewState=await storage.loadState(user);
  const mergePreview=new WorkerResponse();
  await router.handle({method:"POST",path:"/secret_realm/merge_preview",body:{action:"move",uid:initial.secret_realm!.cells.find(c=>c.col===0&&c.row===0)!.item!.uid,
    col:0,row:1,version:0,period:initial.secret_realm!.period,request_id:"http-preview"},headers:{authorization:`Bearer ${token}`},query:{}},mergePreview);
  assert.equal(mergePreview.statusCode,200);
  const previewData=await mergePreview.toResponse().json() as any;
  assert.deepEqual(previewData.lost_drops,[]);
  assert.equal(previewData.request_id,"http-preview");
  assert.deepEqual(await storage.loadState(user),previewState);
  const payload={action:"use",uid:initial.secret_realm!.stash[0].uid,version:0,period:initial.secret_realm!.period,request_id:"save-retry"};
  storage.fail=true;
  const savedBefore=await storage.loadState(user);
  assert.equal((await send(payload)).status,500);
  const failed=await storage.loadState(user);
  assert.deepEqual(failed!.secret_realm,savedBefore!.secret_realm);
  assert.equal(failed!.spirit_stones,savedBefore!.spirit_stones);
  const replies=await Promise.all([send(payload),send(payload)]);
  assert.ok(replies.every(r=>r.status===200),JSON.stringify(replies));
  assert.equal((await storage.loadState(user))!.spirit_stones,initial.spirit_stones+30);
  assert.equal(replies.filter(r=>r.data.replayed).length,1);
  // Save failure and concurrent retries also preserve partial deliveries exactly once.
  const combatState=(await storage.loadState(user))!;
  const combatSource=combatState.secret_realm!.cells.find(c=>c.col===0&&c.row===0)!;
  combatSource.item={uid:engine._nextUid(combatState),id:"sword_4",immovable:false};
  combatState.secret_realm!.cells.find(c=>c.col===1&&c.row===4)!.fog=false;
  await storage.saveState(user,combatState);
  const delivery={action:"fight",uid:combatSource.item.uid,col:1,row:4,version:combatState.secret_realm!.version,
    period:combatState.secret_realm!.period,request_id:"http-single-delivery"};
  const beforeDelivery=await storage.loadState(user);storage.fail=true;
  assert.equal((await send(delivery)).status,500);assert.deepEqual(await storage.loadState(user),beforeDelivery);
  const delivered=await Promise.all([send(delivery),send(delivery)]);
  assert.ok(delivered.every(r=>r.status===200));assert.equal(delivered.filter(r=>r.data.replayed).length,1);
  const persisted=(await storage.loadState(user))!;
  const partial=persisted.secret_realm!.cells.find(c=>c.col===1&&c.row===4)!;
  assert.deepEqual(partial.submitted,{sword_4:1});assert.equal(partial.monster,"mob_1");
  assert.equal(persisted.secret_realm!.cells.find(c=>c.col===0&&c.row===0)!.item,undefined);
  assert.deepEqual(delivered[0].data.secret_realm.cells.find((c:any)=>c.col===1&&c.row===4).submitted,{sword_4:1});
  const invalid=structuredClone(gameConfigTables) as any; invalid.secretRealm.items[0].level=99;
  assert.throws(()=>new GameEngine(invalid),/invalid_secret_realm_config/);
  console.log("secret_realm_smoke: PASS");
}
main().catch(err=>{console.error(err);process.exitCode=1;});
