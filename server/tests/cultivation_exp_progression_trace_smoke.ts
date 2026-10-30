import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { createCultivationRouter } from "../src/routes/cultivation";
import { WorkerResponse, Router } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

async function main() {
  const engine = new GameEngine(gameConfigTables);
  const storage = new MemoryStorage();
  const secret = "exp-progression-test";
  const token = await signToken({ userId: "exp-test", deviceId: "test" }, secret);
  const game = createGameRouter(storage, engine, secret);
  const cultivation = createCultivationRouter(storage, engine, secret);
  const definitions = engine.getHomeMeridianDefs();
  const state = engine.createInitialState();
  state.cultivation.current_level = 4;
  state.home_meridian_progress = definitions.flatMap((def, stage) => def.cultivation_level < 4
    ? [{ stage, lit: Array(def.acupoints).fill(true), circulation_completed: true }] : []);
  await storage.saveState("exp-test", state);
  async function request(router: Router, method: string, path: string, body = {}, expectedStatus = 200) {
    const response = new WorkerResponse();
    await router.handle({ method, path, body, headers: { authorization: `Bearer ${token}` }, query: {} }, response);
    const data: any = await response.toResponse().json();
    assert.equal(response.statusCode, expectedStatus, `${path}: ${JSON.stringify(data)}`);
    return data;
  }

  // Exercise the real light/run/load/breakthrough routes across Qi layers 3-5,
  // retaining progress from the previous level and reloading after each operation.
  for (const level of [4, 5, 6]) {
    let expectedExp = 0;
    const stages = definitions.map((def, stage) => ({ def, stage })).filter(s => s.def.cultivation_level === level);
    for (const { def, stage } of stages) {
      const saved = (await storage.loadState("exp-test"))!;
      saved.cultivation.max_qi = gameConfigTables.cultivation.stages[level - 1].max_qi;
      saved.cultivation.current_qi = saved.cultivation.max_qi;
      await storage.saveState("exp-test", saved);
      for (let index = 0; index < def.acupoints; index++) {
        const lit = await request(game, "POST", "/home_meridian/light", { stage, index });
        assert.equal(lit.cultivation.current_exp, expectedExp, "lighting a node must not award EXP");
      }
      assert.equal((await request(game, "GET", "/state")).cultivation.current_exp, expectedExp);
      const run = await request(game, "POST", "/home_meridian/run", { stage });
      expectedExp += def.circulation_reward.tokens.filter((t: any) => t.token === 4)
        .reduce((sum: number, t: any) => sum + t.amount, 0);
      assert.equal(run.cultivation.current_exp, expectedExp);
      assert.equal((await request(game, "GET", "/state")).cultivation.current_exp, expectedExp);
      const duplicate = await request(game, "POST", "/home_meridian/run", { stage }, 400);
      assert.equal(duplicate.error, "circulation_completed");
      assert.equal((await storage.loadState("exp-test"))!.cultivation.current_exp, expectedExp);
    }
    assert.equal(expectedExp, engine.getExpToNextLevel(level));
    const saved = (await storage.loadState("exp-test"))!;
    for (const item of engine.getStageBreakthroughItems(level)) {
      for (let index = 0; index < item.count; index++) saved.pouch.push({ id: item.item_id, uid: engine._nextUid(saved) });
    }
    await storage.saveState("exp-test", saved);
    const broken = await request(cultivation, "POST", "/breakthrough", { uid: 0 });
    assert.equal(broken.cultivation.current_level, level + 1);
    assert.equal(broken.cultivation.current_exp, 0, "breakthrough must reset EXP");
    assert.equal((await request(game, "GET", "/state")).cultivation.current_exp, 0);
  }

  // Five completed Qi layer-5 circulations and the sixth lit but unclaimed.
  // Reading preserves EXP; only running the remaining circulation awards it.
  const reported = engine.createInitialState();
  reported.cultivation.current_level = 6;
  reported.cultivation.current_exp = 227;
  reported.cultivation.total_exp = 638;
  reported.home_meridian_progress = definitions.flatMap((def, stage) => stage <= 25
    ? [{ stage, lit: Array(def.acupoints).fill(true), circulation_completed: stage < 25 }] : []);
  reported.storage_revision = (await storage.loadState("exp-test"))!.storage_revision;
  await storage.saveState("exp-test", reported);
  assert.equal((await request(game, "GET", "/state")).cultivation.current_exp, 227);
  assert.equal((await request(game, "POST", "/home_meridian/run", { stage: 25 })).cultivation.current_exp, 231);
  assert.equal((await request(game, "GET", "/state")).cultivation.current_exp, 231);
  assert.equal((await request(cultivation, "POST", "/breakthrough", { uid: 0 })).cultivation.current_level, 7);
  console.log("CULTIVATION_EXP_PROGRESSION_TRACE_SMOKE_OK");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
