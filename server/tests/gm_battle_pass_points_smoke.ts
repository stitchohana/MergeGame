import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { signToken } from "../src/middleware/auth";
import { createGMRouter } from "../src/routes/gm";
import { GameState, IStorage, LeaderboardEntry, User } from "../src/storage/interface";
import { gameConfigTables } from "../src/worker/config_data";
import { WorkerRequest, WorkerResponse } from "../src/worker/http";

class MemoryStorage implements IStorage {
  state: GameState;
  saves = 0;

  constructor(state: GameState) { this.state = structuredClone(state); }
  async findUser(_deviceId: string): Promise<User | null> { return null; }
  async createUser(_deviceId: string): Promise<User> { throw new Error("unused"); }
  async loadState(_userId: string): Promise<GameState | null> { return structuredClone(this.state); }
  async saveState(_userId: string, state: GameState): Promise<void> {
    this.state = structuredClone(state);
    this.saves += 1;
  }
  async getLeaderboard(_limit: number): Promise<LeaderboardEntry[]> { return []; }
}

async function main(): Promise<void> {
  const engine = new GameEngine(gameConfigTables);
  const state = engine.createInitialState();
  state.battle_pass_progress = {
    4: { points: 10, premium_unlocked: true, free_claimed_levels: [1], premium_claimed_levels: [] },
  };
  const storage = new MemoryStorage(state);
  const secret = "gm-battle-pass-smoke-secret";
  const router = createGMRouter(storage, engine, secret, "test-gm-key");
  const token = await signToken({ userId: "gm-user", deviceId: "gm-device" }, secret);

  async function request(amount: unknown): Promise<{ status: number; data: any }> {
    const req: WorkerRequest = {
      method: "POST",
      path: "/exec",
      headers: { authorization: `Bearer ${token}` },
      body: { gm_key: "test-gm-key", cmd: "add_battle_pass_points", amount },
      query: {},
    };
    const res = new WorkerResponse();
    assert.equal(await router.handle(req, res), true);
    const response = res.toResponse();
    return { status: response.status, data: await response.json() };
  }

  const added = await request(25);
  assert.equal(added.status, 200);
  assert.equal(added.data.battle_pass_progress[4].points, 35);
  assert.equal(storage.state.battle_pass_progress?.[4].points, 35);
  assert.equal(storage.state.battle_pass_progress?.[4].premium_unlocked, true);
  assert.deepEqual(storage.state.battle_pass_progress?.[4].free_claimed_levels, [1]);
  assert.equal(storage.saves, 1);

  for (const invalidAmount of [0, -1, 1.5, "12", true, Number.MAX_SAFE_INTEGER]) {
    const rejected = await request(invalidAmount);
    assert.equal(rejected.status, 400);
    assert.equal(rejected.data.error, "invalid_amount");
  }
  assert.equal(storage.state.battle_pass_progress?.[4].points, 35);
  assert.equal(storage.saves, 1);
  console.log("gm_battle_pass_points_smoke: ok");
}

void main();
