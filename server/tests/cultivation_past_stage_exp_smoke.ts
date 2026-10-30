import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGMRouter } from "../src/routes/gm";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

async function main() {
  const engine = new GameEngine(gameConfigTables);
  const defs = engine.getHomeMeridianDefs();
  // Reproduce the supplied trace: GM advances before any mortal circulation,
  // then activates four nodes at a time. Old rewards must not enter level 2.
  const storage = new MemoryStorage();
  await storage.saveState("past-stage", engine.createInitialState());
  const secret = "past-stage-test";
  const token = await signToken({ userId: "past-stage", deviceId: "test" }, secret);
  const router = createGMRouter(storage, engine, secret, "test-key");
  async function gm(cmd: string, amount = 1) {
    const response = new WorkerResponse();
    await router.handle({ method: "POST", path: "/exec", headers: { authorization: `Bearer ${token}` },
      body: { cmd, amount, gm_key: "test-key" }, query: {} }, response);
    assert.equal(response.statusCode, 200);
    return (await storage.loadState("past-stage"))!;
  }
  await gm("levelup");
  assert.equal((await gm("activate_home_acupoints", 4)).cultivation.current_exp, 0);
  assert.equal((await gm("activate_home_acupoints", 4)).cultivation.current_exp, 0);
  assert.equal((await gm("activate_home_acupoints", 4)).cultivation.current_exp, 16);
  assert.equal((await gm("activate_home_acupoints", 4)).cultivation.current_exp, 32);
  assert.equal((await gm("activate_home_acupoints", 4)).cultivation.current_exp, 48);

  // These precise mixtures reproduced 127/128 and 227/228 before the fix.
  for (const [level, oldCount, currentCount, expected] of [[5, 2, 4, 84], [6, 3, 5, 165]]) {
    const state = engine.createInitialState();
    state.cultivation.current_level = level;
    const all = defs.map((def, stage) => ({ def, stage }));
    const oldStages = all.filter(s => s.def.cultivation_level === level - 1).slice(-oldCount);
    const currentStages = all.filter(s => s.def.cultivation_level === level).slice(0, currentCount);
    for (const { def, stage } of [...oldStages, ...currentStages]) {
      state.home_meridian_progress ??= [];
      state.home_meridian_progress.push({ stage, lit: Array(def.acupoints).fill(true), circulation_completed: false });
      assert.equal(engine.runHomeMeridianCirculation(state, stage).ok, true);
    }
    assert.equal(state.cultivation.current_exp, expected);
    assert.equal(state.cultivation.total_exp, expected);
  }

  // Check both the normal run button and GM completion, including old
  // layer-4 circulations whose last three rewards total the observed 64.
  for (const level of [5, 6]) {
    for (const mode of ["normal", "gm"]) {
      const state = engine.createInitialState();
      state.cultivation.current_level = level;
      const past = defs.map((def, stage) => ({ def, stage })).filter(s => s.def.cultivation_level < level);
      state.home_meridian_progress = past.map(({ def, stage }) => ({
        stage, lit: Array(def.acupoints).fill(true), circulation_completed: stage !== past.at(-1)!.stage,
      }));
      const stage = past.at(-1)!.stage;
      const totalBefore = state.cultivation.total_exp;
      if (mode === "normal") {
        const result = engine.runHomeMeridianCirculation(state, stage);
        assert.equal(result.ok, true);
        if (!result.ok) throw new Error(result.reason);
        assert.equal(result.rewards.tokens?.some(t => t.token === 4), false);
        assert.ok(result.rewards.items?.length, "old facility rewards must remain claimable");
      } else {
        engine.gmActivateHomeAcupoints(state, 1);
      }
      assert.equal(state.cultivation.current_exp, 0, `${mode}: old stage must not grant current-level EXP`);
      assert.equal(state.cultivation.total_exp, totalBefore);
      assert.equal(state.home_meridian_progress.find(p => p.stage === stage)?.circulation_completed, true);
    }
  }
  console.log("CULTIVATION_PAST_STAGE_EXP_SMOKE_OK");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
