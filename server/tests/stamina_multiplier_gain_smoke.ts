import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { signToken } from "../src/middleware/auth";
import { createGameRouter } from "../src/routes/game";
import { createGMRouter } from "../src/routes/gm";
import { GameState, IStorage, LeaderboardEntry, User } from "../src/storage/interface";
import { gameConfigTables } from "../src/worker/config_data";
import { Router, WorkerRequest, WorkerResponse } from "../src/worker/http";

class MemoryStorage implements IStorage {
  state: GameState;

  constructor(state: GameState) { this.state = structuredClone(state); }
  async findUser(_deviceId: string): Promise<User | null> { return null; }
  async createUser(_deviceId: string): Promise<User> { throw new Error("unused"); }
  async loadState(_userId: string): Promise<GameState | null> { return structuredClone(this.state); }
  async saveState(_userId: string, state: GameState): Promise<void> { this.state = structuredClone(state); }
  async getLeaderboard(_limit: number): Promise<LeaderboardEntry[]> { return []; }
}

async function main(): Promise<void> {
  const tables: any = structuredClone(gameConfigTables);
  const activity = tables.activities.activities.find((entry: any) => entry.id === 4);
  activity.enabled = true;
  activity.start_time = "2020-01-01T00:00:00Z";
  activity.end_time = "2999-01-01T00:00:00Z";
  const engine = new GameEngine(tables);
  const state = engine.createInitialState();
  state.stamina = 190;
  state.battle_pass_progress = {
    4: { points: 10, premium_unlocked: false, free_claimed_levels: [], premium_claimed_levels: [] },
  };
  const storage = new MemoryStorage(state);
  const secret = "stamina-gain-smoke-secret";
  const token = await signToken({ userId: "stamina-user", deviceId: "stamina-device" }, secret);
  const gameRouter = createGameRouter(storage, engine, secret);
  const gmRouter = createGMRouter(storage, engine, secret, "test-gm-key");

  async function request(router: Router, path: string, body: Record<string, unknown>): Promise<{ status: number; data: any }> {
    const req: WorkerRequest = {
      method: "POST", path, headers: { authorization: `Bearer ${token}` }, body, query: {},
    };
    const res = new WorkerResponse();
    assert.equal(await router.handle(req, res), true);
    const response = res.toResponse();
    return { status: response.status, data: await response.json() };
  }

  const claim = await request(gameRouter, "/battle_pass/claim", { activity_id: 4, level: 1, track: "free" });
  assert.equal(claim.status, 200);
  assert.equal(claim.data.stamina, 200);
  assert.equal(claim.data.stamina_multiplier_max, 2);
  assert.ok(claim.data.stamina_multiplier_expires_at > Date.now());
  assert.equal(storage.state.stamina_multiplier_max, 2);

  const gmIncrease = await request(gmRouter, "/exec", {
    gm_key: "test-gm-key", cmd: "set_stamina", amount: 400,
  });
  assert.equal(gmIncrease.status, 200);
  assert.equal(gmIncrease.data.stamina, 400);
  assert.equal(gmIncrease.data.stamina_multiplier_max, 4);
  assert.equal(storage.state.stamina, 400);
  assert.equal(storage.state.stamina_multiplier_max, 4);

  const expiresAt = storage.state.stamina_multiplier_expires_at;
  const gmDecrease = await request(gmRouter, "/exec", {
    gm_key: "test-gm-key", cmd: "set_stamina", amount: 100,
  });
  assert.equal(gmDecrease.status, 200);
  assert.equal(gmDecrease.data.stamina, 100);
  assert.equal(storage.state.stamina_multiplier_expires_at, expiresAt);
  console.log("stamina_multiplier_gain_smoke: ok");
}

void main();
