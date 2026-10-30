import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import type { GameState } from "../src/storage/interface";
import { createGameRouter } from "../src/routes/game";
import { createCultivationRouter } from "../src/routes/cultivation";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

class TestStorage extends MemoryStorage {
  fail = false;
  override async saveState(id: string, state: GameState) {
    if (this.fail) { this.fail = false; throw new Error("save_failed"); }
    await super.saveState(id, state);
  }
}

async function main() {
  const realNow = Date.now;
  let now = realNow();
  Date.now = () => now;
  try {
    const engine = new GameEngine(gameConfigTables);
    const state = engine.createInitialState();
    const start = now;
    state.stamina = 60;
    assert.equal(engine.tickStamina(state, start + 119_999), false);
    assert.equal(state.stamina, 60);
    assert.equal(engine.tickStamina(state, start + 120_000), true);
    assert.equal(state.stamina, 61);
    assert.equal(engine.tickStamina(state, start + 660_000), true);
    assert.equal(state.stamina, 65, "11 minutes offline restores five points");
    assert.equal(engine.getRegenRemainingMs(state, start + 660_000), 60_000);
    assert.equal(engine.tickStamina(state, start + 660_000), false);
    assert.equal(state.stamina, 65, "repeated settlement does not grant again");
    assert.equal(engine.tickStamina(state, start + 720_000), true);
    assert.equal(state.stamina, 66, "partial interval survives a settlement");
    engine.tickStamina(state, start + 10 * 365 * 86400_000);
    assert.equal(state.stamina, 100);
    assert.equal(engine.getRegenRemainingMs(state, start + 10 * 365 * 86400_000), 0);
    state.stamina = 200;
    engine.tickStamina(state, start + 11 * 365 * 86400_000);
    assert.equal(state.stamina, 200, "paid stamina above cap is preserved");
    state.stamina = 99;
    assert.equal(engine.tickStamina(state, state.last_stamina_tick + 119_999), false,
      "time at cap does not bank recovery");

    const storage = new TestStorage();
    const saved = engine.createInitialState();
    saved.stamina = 60;
    saved.last_stamina_tick = start - 210_000;
    await storage.saveState("offline", saved);
    const token = await signToken({ userId: "offline", deviceId: "offline-device" }, "offline-secret");
    const router = createGameRouter(storage, engine, "offline-secret");
    const cultRouter = createCultivationRouter(storage, engine, "offline-secret");
    const request = async (path: string, method = "GET", target = router, body: any = {}) => {
      const response = new WorkerResponse();
      await target.handle({ method, path, body, headers: { authorization: "Bearer " + token }, query: {} }, response);
      return { status: response.statusCode, data: await response.toResponse().json() as any };
    };
    const login = await request("/state");
    assert.equal(login.status, 200);
    assert.equal(login.data.stamina, 61);
    assert.equal(login.data.regen_remaining_ms, 30_000);
    assert.equal((await storage.loadState("offline"))!.stamina, 61, "login recovery is persisted");
    assert.equal((await request("/state")).data.stamina, 61, "relogin keeps the recovered point");
    now += 30_000;
    const refresh = await request("/stamina/refresh", "POST");
    assert.equal(refresh.status, 200);
    assert.equal(refresh.data.stamina, 62);
    assert.equal(refresh.data.regen_remaining_ms, 120_000);
    assert.equal((await storage.loadState("offline"))!.stamina, 62);
    assert.equal((await request("/state")).data.stamina, 62, "online recovery survives relogin");
    const snapshot = await storage.loadState("offline");
    now += 120_000;
    storage.fail = true;
    assert.equal((await request("/stamina/refresh", "POST")).status, 500);
    assert.deepEqual(await storage.loadState("offline"), snapshot, "failed save cannot partially grant");
    assert.equal((await request("/stamina/refresh", "POST")).data.stamina, 63);
    assert.equal((await request("/stamina/refresh", "POST")).data.stamina, 63);
    now += 120_000;
    assert.equal((await request("/consume-exp", "POST", cultRouter, { pill_id: -1, uid: -1 })).status, 400);
    assert.equal((await storage.loadState("offline"))!.stamina, 64, "cultivation settles recovery too");
    assert.equal((await request("/state")).data.stamina, 64);
    console.log("OFFLINE_STAMINA_SMOKE_OK interval remainder cap offline relogin persistence rollback cultivation");
  } finally {
    Date.now = realNow;
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
