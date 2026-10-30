import assert from "node:assert/strict";
import type { GameEngine } from "../src/engine/game_engine";
import type { GameState } from "../src/storage/interface";

// Submit supplied instances through actual board placement and per-item actions.
// The callback lets recovery tests inspect state immediately before the final item.
export function submitRealmMonster(engine: GameEngine, state: GameState, col: number, row: number,
  prefix: string, beforeFinal?: (body: any) => void): any {
  const service=engine.secretRealmService,p=()=>state.secret_realm!;
  const target=service.view(state).cells.find((c:any)=>c.col===col&&c.row===row);
  const items:string[]=target.enemy.costs.flatMap((c:any)=>Array(c.count-(target.submitted?.[c.id]??0)).fill(c.id));
  let serial=0,last:any;
  for(const [index,id] of items.entries()) {
    const visible=p().cells.filter(c=>c.row>=p().start_row&&c.row<p().start_row+8&&!c.fog);
    let source=visible.find(c=>c.item?.id===id&&!c.item.immovable);
    if(!source) {
      const item=p().stash.find(i=>i.id===id&&!i.immovable);
      let slot=visible.find(c=>!c.item&&!c.monster);
      if(!slot) {
        const recall=visible.find(c=>c.item&&!c.item.immovable);
        assert.ok(recall,"an unlocked item can be recalled to make submission space");
        assert.equal(service.transact(state,{action:"recall",uid:recall.item!.uid,
          period:p().period,version:p().version,request_id:`${prefix}-recall-${++serial}`}).ok,true);
        slot=p().cells.find(c=>c.col===recall.col&&c.row===recall.row)!;
      }
      assert.ok(item&&slot,`board space and supplied ${id} for ${prefix}`);
      assert.equal(service.transact(state,{action:"place",uid:item.uid,col:slot.col,row:slot.row,
        period:p().period,version:p().version,request_id:`${prefix}-place-${++serial}`}).ok,true);
      source=p().cells.find(c=>c.col===slot.col&&c.row===slot.row)!;
    }
    last={action:"fight",uid:source.item!.uid,col,row,period:p().period,version:p().version,request_id:`${prefix}-submit-${++serial}`};
    if(index===items.length-1)beforeFinal?.(last);
    assert.equal(service.transact(state,last).ok,true,JSON.stringify(last));
  }
  return last;
}
