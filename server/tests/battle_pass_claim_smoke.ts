import assert from "node:assert/strict";
import { signToken } from "../src/middleware/auth";
import { GameEngine } from "../src/engine/game_engine";
import { GameState, IStorage, LeaderboardEntry, User } from "../src/storage/interface";
import { gameConfigTables } from "../src/worker/config_data";
import { Router, WorkerRequest, WorkerResponse } from "../src/worker/http";
import { createGameRouter } from "../src/routes/game";

class MemoryStorage implements IStorage {
  state: GameState;
  failNextSave = false;

  constructor(state: GameState) { this.state = structuredClone(state); }
  async findUser(_deviceId: string): Promise<User | null> { return null; }
  async createUser(_deviceId: string): Promise<User> { throw new Error("unused"); }
  async loadState(_userId: string): Promise<GameState | null> { return structuredClone(this.state); }
  async saveState(_userId: string, state: GameState): Promise<void> {
    if (this.failNextSave) { this.failNextSave = false; throw new Error("save_failed"); }
    this.state = structuredClone(state);
  }
  async getLeaderboard(_limit: number): Promise<LeaderboardEntry[]> { return []; }
}

const tables: any = structuredClone(gameConfigTables);
const activity = tables.activities.activities.find((entry: any) => entry.id === 4);
activity.enabled = true;
activity.start_time = "2026-09-22T00:00:00Z";
activity.end_time = "2999-01-01T00:00:00Z";
const engine = new GameEngine(tables);
const state = engine.createInitialState();
state.spirit_stones = 800;
state.stamina = 40;
state.battle_pass_progress = {
  4: { points: 500, premium_unlocked: false, free_claimed_levels: [], premium_claimed_levels: [] },
};
const storage = new MemoryStorage(state);
const secret = "battle-pass-smoke-secret";
const router: Router = createGameRouter(storage, engine, secret);

async function main(): Promise<void> {
const token = await signToken({ userId: "battle-pass-user", deviceId: "battle-pass-device" }, secret);

async function request(path: string, body: Record<string, unknown>, method = "POST"): Promise<{ status: number; data: any }> {
  const req: WorkerRequest = {
    method,
    path,
    headers: { authorization: "Bearer " + token },
    body,
    query: {},
  };
  const res = new WorkerResponse();
  assert.equal(await router.handle(req, res), true);
  const response = res.toResponse();
  return { status: response.status, data: await response.json() };
}

const premiumLocked = await request("/battle_pass/claim", { activity_id: 4, level: 1, track: "premium" });
assert.equal(premiumLocked.status, 400);
assert.equal(premiumLocked.data.error, "premium_not_unlocked");

const unlocked = await request("/battle_pass/unlock", { activity_id: 4 });
assert.equal(unlocked.status, 200);
assert.equal(unlocked.data.spirit_stones, 300);
const repeatedUnlock = await request("/battle_pass/unlock", { activity_id: 4 });
assert.equal(repeatedUnlock.status, 200);
assert.equal(repeatedUnlock.data.spirit_stones, 300);

storage.failNextSave = true;
const failedSave = await request("/battle_pass/claim", { activity_id: 4, level: 1, track: "free" });
assert.equal(failedSave.status, 500);
assert.deepEqual(storage.state.battle_pass_progress?.[4].free_claimed_levels, []);
assert.equal(storage.state.stamina, 40);

const freeClaim = await request("/battle_pass/claim", { activity_id: 4, level: 1, track: "free" });
assert.equal(freeClaim.status, 200);
assert.equal(storage.state.stamina, 50);
const duplicateClaim = await request("/battle_pass/claim", { activity_id: 4, level: 1, track: "free" });
assert.equal(duplicateClaim.status, 400);
assert.equal(duplicateClaim.data.error, "already_claimed");
assert.equal(storage.state.stamina, 50);

const premiumClaim = await request("/battle_pass/claim", { activity_id: 4, level: 1, track: "premium" });
assert.equal(premiumClaim.status, 200);
assert.equal(premiumClaim.data.battle_pass_progress[4].premium_claimed_levels.includes(1), true);
assert.equal(storage.state.stamina, 60);
assert.equal(storage.state.battle_pass_progress?.[4].premium_claimed_levels.includes(1), true);

activity.end_time = "2026-09-22T00:00:00Z";
storage.failNextSave = true;
const failedSettlement = await request("/state", {}, "GET");
assert.equal(failedSettlement.status, 500);
assert.equal(storage.state.battle_pass_progress?.[4].free_claimed_levels.length, 1);
const settled = await request("/state", {}, "GET");
assert.equal(settled.status, 200);
assert.equal(storage.state.battle_pass_progress?.[4].free_claimed_levels.length, 50);
assert.equal(storage.state.battle_pass_progress?.[4].premium_claimed_levels.length, 50);
const staminaAfterSettlement = storage.state.stamina;
const settlementRetry = await request("/state", {}, "GET");
assert.equal(settlementRetry.status, 200);
assert.equal(storage.state.stamina, staminaAfterSettlement);
console.log("battle_pass_claim_smoke: ok");
}

void main();
