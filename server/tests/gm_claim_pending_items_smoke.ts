import assert from "node:assert/strict";
import { GameEngine } from "../src/engine/game_engine";
import { signToken } from "../src/middleware/auth";
import { claimAllPendingItems, createGMRouter } from "../src/routes/gm";
import { GameState, LeaderboardEntry, User } from "../src/storage/interface";
import { MemoryStorage as SharedStorage } from "../src/storage/memory";
import { gameConfigTables } from "../src/worker/config_data";
import { WorkerRequest, WorkerResponse } from "../src/worker/http";

class MemoryStorage extends SharedStorage {
  state: GameState;
  constructor(state: GameState) { super(); this.state = structuredClone(state); }
  async findUser(_deviceId: string): Promise<User | null> { return null; }
  async createUser(_deviceId: string): Promise<User> { throw new Error("unused"); }
  async loadState(_userId: string): Promise<GameState | null> { return structuredClone(this.state); }
  async saveState(_userId: string, state: GameState): Promise<void> { this.state = structuredClone(state); }
  async getLeaderboard(_limit: number): Promise<LeaderboardEntry[]> { return []; }
}

const engine = new GameEngine(gameConfigTables);

function makeState(): GameState {
  const state = engine.createInitialState();
  state.grid = [{ uid: 100, id: 11001, col: 0, row: 0 }];
  state.pending_rewards = [
    { uid: 201, id: 5001, name: "露芽米" },
    { uid: 202, id: 5002, name: "青禾米" },
    { uid: 203, id: 1705, name: "卡包", kind: "card_pack", pack_id: 5 },
  ];
  return state;
}

async function main(): Promise<void> {
  const state = makeState();
  const beforeVersion = state.version;
  const result = claimAllPendingItems(state, engine);
  assert.equal(result.claimedCount, 2);
  assert.equal(result.remainingCount, 0);
  assert.equal(result.skippedCount, 0);
  assert.deepEqual(state.grid.map(item => item.uid), [100, 201, 202]);
  assert.deepEqual(state.pending_rewards.map(item => item.uid), [203]);
  assert.equal(state.version, beforeVersion + 1);

  const full = makeState();
  full.grid = Array.from({ length: engine.MAX_CELLS }, (_, index) => ({
    uid: 300 + index, id: 11001, col: index % engine.GRID_COLS, row: Math.floor(index / engine.GRID_COLS),
  }));
  const fullResult = claimAllPendingItems(full, engine);
  assert.equal(fullResult.claimedCount, 0);
  assert.equal(fullResult.remainingCount, 2);
  assert.equal(fullResult.skippedCount, 1);

  // A pack at the front must not block ordinary items behind it. Fill the
  // last free slot, then retry without duplicating the item already claimed.
  full.grid.pop();
  const pack = full.pending_rewards.pop()!;
  full.pending_rewards.unshift(pack);
  assert.equal(claimAllPendingItems(full, engine).claimedCount, 1);
  assert.deepEqual(full.pending_rewards.map(item => item.uid), [203, 202]);
  assert.equal(full.grid.filter(item => item.uid === 201).length, 1);
  assert.equal(claimAllPendingItems(full, engine).claimedCount, 0);
  full.grid.shift();
  assert.equal(claimAllPendingItems(full, engine).claimedCount, 1);
  assert.deepEqual(full.pending_rewards.map(item => item.uid), [203]);
  assert.equal(claimAllPendingItems(full, engine).claimedCount, 0);

  const storage = new MemoryStorage(makeState());
  const secret = "gm-claim-pending-items-secret";
  const router = createGMRouter(storage, engine, secret, "test-key");
  const token = await signToken({ userId: "claim-user", deviceId: "claim-device" }, secret);
  const req: WorkerRequest = { method: "POST", path: "/exec", headers: { authorization: `Bearer ${token}` },
    body: { gm_key: "test-key", cmd: "claim_all_pending_items" }, query: {} };
  const response = new WorkerResponse();
  assert.equal(await router.handle(req, response), true);
  const output = response.toResponse();
  assert.equal(output.status, 200);
  const data: any = await output.json();
  assert.equal(data.claimed_count, 2);
  assert.equal(data.remaining_count, 0);
  assert.deepEqual((await storage.loadState("claim-user"))!.pending_rewards.map(item => item.uid), [203]);
  console.log("GM_CLAIM_PENDING_ITEMS_SMOKE_OK claim_all card_pack_preserved board_full partial retry api_persistence");
}

void main();
