import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { JsonFileStorage } from "../src/storage/json_file";
import { createGameRouter } from "../src/routes/game";
import { signToken } from "../src/middleware/auth";
import { WorkerResponse } from "../src/worker/http";

async function main() {
  const realNow = Date.now;
  Date.now = () => Date.parse("2026-10-28T12:00:00+08:00");
  try {
    const engine = new GameEngine(gameConfigTables);
    const state = engine.createInitialState();
    assert.equal(state.storage_revision, 0);
    assert.ok(state.spawn_seed! > 0);
    assert.equal(state.spawn_sequence, 0);
    assert.deepEqual(state.item_catalog_claimed_ids, []);
    assert.ok(state.grid.every(item => item.uid! > 0));
    assert.ok(state.unlocked_production_item_ids!.includes(11001));
    assert.ok(state.crafted_item_ids.includes(11001));

    state.cultivation.current_level = 6;
    state.cultivation.current_exp = 227;
    state.cultivation.total_exp = 638;
    state.home_meridian_progress = engine.getHomeMeridianDefs().flatMap((def, stage) =>
      def.cultivation_level <= 6 ? [{ stage, lit: Array(def.acupoints).fill(true), circulation_completed: true }] : []);
    state.grid = [];
    state.pouch = [{ uid: 76, id: 17001 }];
    state.pouch_capacity = 7;
    state.uid_counter = 77;
    state.pending_rewards = [{ uid: 77, id: 12001, name: "pending" }];
    state.crafted_item_ids = [];
    state.unlocked_production_item_ids = [];
    state.meridian_acupoints = [{ item_ids: [5001], name: "saved order", completed: false }];
    state.meridian_fixed_order_cursor = 3;
    engine.questEngine.initQuestProgress(state);
    state.quest_progress![1001] = { current_count: 99, completed: true, claimed: true };
    const cards = engine.cardCollectionService.ensureProgress(state)[1];
    assert.deepEqual(Object.keys(cards).sort(), ["cards", "claimed_sets", "duplicate_points", "exchange_count", "opened_count", "total_duplicate_points"]);
    assert.equal(engine.secretRealmService.initialize(state), true);
    state.secret_realm!.cells.pop();
    state.secret_realm!.completed = true;
    const realm = structuredClone(state.secret_realm);
    const selected = (s: typeof state) => ({
      exp: s.cultivation.current_exp, total: s.cultivation.total_exp,
      grid: s.grid, pouch: s.pouch, capacity: s.pouch_capacity,
      uid: s.uid_counter, pending: s.pending_rewards,
      discoveries: s.crafted_item_ids, production: s.unlocked_production_item_ids,
      orders: s.meridian_acupoints, cursor: s.meridian_fixed_order_cursor,
      quest: s.quest_progress![1001], realm: s.secret_realm,
    });
    const before = structuredClone(selected(state));
    const storage = new MemoryStorage();
    await storage.saveState("current", state);
    const token = await signToken({ userId: "current", deviceId: "current" }, "current-test");
    const router = createGameRouter(storage, engine, "current-test");
    for (let i = 0; i < 2; i++) {
      const res = new WorkerResponse();
      await router.handle({ method: "GET", path: "/state", body: {}, query: {}, headers: { authorization: `Bearer ${token}` } }, res);
      assert.equal(res.statusCode, 200);
      assert.deepEqual(selected((await storage.loadState("current"))!), before);
    }
    assert.equal(engine.secretRealmService.initialize(state), false);
    assert.deepEqual(state.secret_realm, realm);
    assert.equal(engine.questEngine.initQuestProgress(state), false);
    assert.equal(state.quest_progress![1001].claimed, true);

    const db = new DatabaseSync(":memory:");
    try {
      const schema = readFileSync("schema.sql", "utf8");
      db.exec(schema);
      db.exec(schema);
      assert.deepEqual(db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").all().map(row => row.name),
        ["game_states", "order_duel_events", "stair_climb_events", "users"]);
      assert.throws(() => db.prepare("INSERT INTO game_states VALUES (?, ?, ?)").run("unknown", "{}", 0), /FOREIGN KEY/);
    } finally { db.close(); }

    const dir = mkdtempSync(join(tmpdir(), "mergegame-current-schema-"));
    try {
      const files = new JsonFileStorage(dir);
      assert.equal(await files.loadState("missing"), null);
      writeFileSync(join(dir, "states", "broken.json"), "invalid JSON");
      await assert.rejects(files.loadState("broken"), SyntaxError);
    } finally { rmSync(dir, { recursive: true, force: true }); }
    console.log("CURRENT_STATE_NO_MIGRATIONS_SMOKE_OK");
  } finally { Date.now = realNow; }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
