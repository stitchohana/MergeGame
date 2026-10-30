import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import type { GameState } from "../src/storage/interface";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

class TestStorage extends MemoryStorage {
  fail = false;
  override async saveState(id: string, state: GameState) {
    if (this.fail) { this.fail = false; throw new Error("save_failed"); }
    return super.saveState(id, state);
  }
}

async function main() {
  const realNow = Date.now, log = console.log;
  let now = Date.parse("2026-10-28T12:00:00+08:00");
  Date.now = () => now; console.log = () => {};
  try {
    const engine = new GameEngine(gameConfigTables);
    const state = engine.createInitialState();
    assert.equal(engine.weeklyTaskService.ensureProgress(state), false);
    assert.equal(state.weekly_task_progress, undefined);
    assert.equal(engine.weeklyTaskService.claim(state, 3, 1, "2026-10-26", r => engine.applyRewards(state, r)).ok, false);
    state.cultivation.current_level = 2;
    engine.questEngine.initQuestProgress(state);
    assert.equal(engine.weeklyTaskService.ensureProgress(state), true);
    const progress = state.weekly_task_progress![3];
    assert.equal(progress.points, 0);
    // Completed tasks wait for reward collection before granting points.
    engine.questEngine.incrementQuestProgress(state, 1, 1, engine);
    assert.equal(progress.points, 0);
    engine.questEngine.incrementQuestProgress(state, 1, 99, engine);
    assert.equal(progress.points, 0);
    assert.equal(engine.questEngine.claimQuestReward(state, 1001, engine).ok, true);
    assert.equal(progress.points, 10, "collecting a task reward grants its points");
    assert.equal(engine.questEngine.claimQuestReward(state, 1001, engine).ok, false);
    engine.questEngine.incrementQuestProgress(state, 1, 99, engine);
    assert.equal(progress.points, 10, "repeat claims and completion events cannot grant points twice");
    for (const id of [1006, 1011, 1016, 1021, 1026, 1031]) assert.equal(engine.questEngine.claimQuestReward(state, id, engine).ok, true);
    assert.equal(progress.points, 70);
    const snapshot = structuredClone(state);
    const claim = (stage: number, key = progress.period_key) => engine.weeklyTaskService.claim(state, 3, stage, key, r => engine.applyRewards(state, r));
    assert.deepEqual(claim(2), {ok:false,reason:"insufficient_points"});
    assert.deepEqual(state, snapshot);
    assert.deepEqual(claim(1,"2026-10-19"), {ok:false,reason:"state_conflict"});
    const stamina = state.stamina;
    assert.equal(claim(1).ok,true);
    assert.equal(state.stamina,stamina+30);
    assert.equal(progress.points,70);
    assert.deepEqual(claim(1),{ok:false,reason:"already_claimed"});
    for (const type of [2,3,4,5]) engine.questEngine.incrementQuestProgress(state,type,99,engine);
    assert.equal(progress.points,70,"uncollected task rewards grant no points");
    for (const id of gameConfigTables.weeklyTasks.weekly_tasks[0].daily_quests.flat()) {
      if (!state.quest_progress![id].claimed) assert.equal(engine.questEngine.claimQuestReward(state,id,engine).ok,true);
    }
    assert.equal(progress.points,350);
    assert.equal(new Set(progress.scored_quest_ids).size,35);
    const staminaBeforeStages=state.stamina;
    const packsBeforeStages=state.pending_rewards.filter(r=>r.kind==="card_pack" && [1702,1703].includes(r.id)).length;
    for (const stage of [4,2,3]) assert.equal(claim(stage).ok,true, "stages can be claimed in any order");
    assert.deepEqual(progress.claimed_stages,[1,4,2,3]);
    assert.equal(state.stamina,staminaBeforeStages+60);
    assert.equal(state.pending_rewards.filter(r=>r.kind==="card_pack" && [1702,1703].includes(r.id)).length,packsBeforeStages+2);
    const priorPeriod = progress.period_key;
    now=Date.parse("2026-11-02T05:00:00+08:00");
    engine.questEngine.checkAndResetQuests(state,engine.questResetHour);
    engine.weeklyTaskService.ensureProgress(state);
    assert.deepEqual(state.weekly_task_progress![3],{period_key:"2026-11-02",points:0,scored_quest_ids:[],claimed_stages:[]});
    assert.deepEqual(claim(1,priorPeriod),{ok:false,reason:"state_conflict"});
    engine.questEngine.incrementQuestProgress(state,1,99,engine);
    assert.equal(state.weekly_task_progress![3].points,0);
    for (const id of [1001,1006,1011,1016,1021,1026,1031]) assert.equal(engine.questEngine.claimQuestReward(state,id,engine).ok,true);
    assert.equal(state.weekly_task_progress![3].points,70);
    engine.questEngine.incrementQuestProgress(state,2,99,engine);

    const storage=new TestStorage();
    await storage.saveState("weekly-points",state);
    const token=await signToken({userId:"weekly-points",deviceId:"weekly-points"},"weekly-secret");
    const request=async(path:string,body:any={},method="POST")=>{
      const router=createGameRouter(storage,engine,"weekly-secret");
      const res=new WorkerResponse();
      await router.handle({method,path,body,headers:{authorization:`Bearer ${token}`},query:{}},res);
      return {status:res.statusCode,data:await res.toResponse().json() as any};
    };
    const view=await request("/state",{},"GET");
    assert.equal(view.data.weekly_task_defs[0].milestones.length,4);
    assert.equal(view.data.weekly_task_progress[3].points,70);
    // Task rewards, points, and claimed status commit together, including retries.
    const beforeTask=(await storage.loadState("weekly-points"))!;
    storage.fail=true;
    assert.equal((await request("/quest_claim",{quest_id:1002})).status,500);
    assert.deepEqual(await storage.loadState("weekly-points"),beforeTask,"failed task persistence rolls back points and rewards");
    const taskClaims=await Promise.all([request("/quest_claim",{quest_id:1002}),request("/quest_claim",{quest_id:1002})]);
    assert.deepEqual(taskClaims.map(r=>r.status),[200,400]);
    assert.equal(taskClaims[0].data.weekly_task_progress[3].points,80);
    assert.equal(taskClaims[0].data.quest_progress[1002].claimed,true);
    assert.equal(taskClaims[0].data.stamina,beforeTask.stamina+10);
    assert.equal(taskClaims[1].data.error,"already_claimed");
    assert.equal((await request("/state",{},"GET")).data.weekly_task_progress[3].points,80);
    const body={activity_id:3,stage:1,period_key:"2026-11-02"};
    for(const invalid of [{...body,stage:0},{...body,stage:1.5},{...body,period_key:undefined},{...body,activity_id:"3"}]) {
      assert.equal((await request("/weekly_tasks/claim",invalid)).status,400);
    }
    const before=(await storage.loadState("weekly-points"))!;
    storage.fail=true;
    assert.equal((await request("/weekly_tasks/claim",body)).status,500);
    assert.deepEqual(await storage.loadState("weekly-points"),before,"failed persistence cannot partially grant");
    const concurrent=await Promise.all([request("/weekly_tasks/claim",body),request("/weekly_tasks/claim",body)]);
    assert.deepEqual(concurrent.map(r=>r.status),[200,400]);
    assert.equal(concurrent[1].data.error,"already_claimed");
    assert.equal(concurrent[0].data.stamina,before.stamina+30);
    assert.equal((await request("/state",{},"GET")).data.weekly_task_progress[3].claimed_stages[0],1);
    now=Date.parse("2026-11-09T05:00:00+08:00");
    assert.equal((await request("/weekly_tasks/claim",body)).status,409);
    assert.equal((await storage.loadState("weekly-points"))!.weekly_task_progress![3].points,0);
    assert.equal((await request("/quest_claim",{quest_id:1007})).data.error,"quest_not_completed");
    assert.equal((await storage.loadState("weekly-points"))!.weekly_task_progress![3].points,0);

    // Automatic reward tasks grant points when their rewards are delivered too.
    const autoTables=structuredClone(gameConfigTables);
    autoTables.quests.quests.find(q=>q.id===1001)!.auto_reward=true;
    const autoEngine=new GameEngine(autoTables);
    const autoState=autoEngine.createInitialState();autoState.cultivation.current_level=2;
    autoEngine.questEngine.incrementQuestProgress(autoState,1,1,autoEngine);
    assert.equal(autoState.quest_progress![1001].claimed,true);
    assert.equal(autoState.weekly_task_progress![3].points,10);
    assert.equal(autoState.pending_rewards.filter(r=>r.kind==="card_pack").length,1);
    autoEngine.questEngine.incrementQuestProgress(autoState,1,99,autoEngine);
    assert.equal(autoState.weekly_task_progress![3].points,10);

    // First unlock starts with zero points, without converting prior completions.
    const fresh=engine.createInitialState();fresh.cultivation.current_level=2;
    engine.questEngine.initQuestProgress(fresh);
    fresh.quest_progress![1001]={current_count:1,completed:true,claimed:true};
    engine.weeklyTaskService.ensureProgress(fresh);
    assert.equal(fresh.weekly_task_progress![3].points,0);
    log("WEEKLY_TASK_POINTS_SMOKE_OK task_claim auto_reward milestones duplicates rollback concurrency persistence reset unlock");
  } finally {Date.now=realNow;console.log=log;}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
