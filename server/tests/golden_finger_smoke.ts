import assert from "node:assert/strict";
import { GameEngine, TableState } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";
import type { GameState } from "../src/storage/interface";

async function main() {
  const engine = new GameEngine(gameConfigTables);
  const service = engine.goldenFingerService;
  const state = engine.createInitialState();
  const now = Date.parse("2026-10-23T04:59:59+08:00");
  const atReset = now + 1000;
  const materialLaunchers = engine.getAllItemDefs().filter(i => i.level === 1 && i.spawns?.some(s => engine.getItemData(s.id)?.type === 0));
  state.grid = materialLaunchers.map((i, index) => ({ id: i.id, uid: engine._nextUid(state), col: index % 7, row: Math.floor(index / 7), charges: i.max_charges, last_charge_time: Date.now() }));
  const viewAt = (level: number) => { state.cultivation.current_level = level; return service.view(state, now); };
  for (const [level, unlocked] of [[1, 0], [2, 1], [3, 1], [4, 2], [5, 2], [6, 3], [19, 3], [20, 3]]) {
    assert.equal(viewAt(level).artifacts.filter(a => a.unlocked).length, unlocked);
  }
  assert.equal(service.levelCap(state), 16, "final configured cultivation stage remains usable");
  state.cultivation.current_level = 6;
  const pool = service.materialPool(state);
  assert.ok(pool.some(i => i.id === 1001), "regular grass available from sources");
  function add(id: number) {
    const occupied = new Map(state.grid.map(i => [engine.posKey(i.col, i.row), i]));
    const pos = engine.findNearestEmpty(occupied, 5, 8)!;
    const item = { id, uid: engine._nextUid(state), ...pos }; state.grid.push(item); return item.uid;
  }
  function body(selection: any, timestamp = now) {
    const preview = service.preview(state, selection, timestamp);
    assert.equal(preview.ok, true, JSON.stringify(preview));
    return { ...selection, request_id: `use-${state.version}-${Math.random()}`, period_key: service.view(state, timestamp).period_key,
      version: state.version, quote: service.quoteKey(preview) };
  }
  let uid = add(1001);
  const use = body({ artifact: "basin", uids: [uid] });
  const original = structuredClone(state);
  const basinResult = service.transact(state, "use", use, now);
  assert.equal(basinResult.ok, true);
  assert.ok(!state.grid.some(i => i.uid === uid));
  assert.equal(state.grid.filter(i => i.id === 1004).length, 2);
  assert.equal(state.pending_rewards.length, original.pending_rewards.length);
  assert.equal(basinResult.spawned_items.length, 2);
  assert.equal(basinResult.pending_rewards_added, 0);
  assert.equal(new Set(state.grid.map(i => i.uid)).size, state.grid.length);
  assert.equal(new Set(state.grid.map(i => `${i.col},${i.row}`)).size, state.grid.length);
  assert.ok(state.grid.some(i => i.id === 1004 && i.col === 5 && i.row === 8), "freed input cell is reused");
  assert.equal(service.view(state, now).artifacts[0].remaining, 0);
  const saved = structuredClone(state);
  assert.equal(service.transact(state, "use", use, atReset).replayed, true);
  assert.deepEqual(state, saved);
  assert.equal(service.transact(state, "use", { ...use, artifact: "furnace" }, now).reason, "state_conflict");
  assert.equal(service.view(state, atReset).artifacts[0].remaining, 1);
  assert.equal(service.preview(state, { artifact: "basin", uids: [add(1004)] }, now).ok, false);
  assert.equal(service.preview(state, { artifact: "basin", uids: [uid] }, now).ok, false);
  const protect = add(1001); state.grid.find(i => i.uid === protect)!.immovable = true;
  assert.equal(service.preview(state, { artifact: "basin", uids: [protect] }, now).ok, false);
  assert.equal(service.preview(state, { artifact: "basin", uids: [protect, protect] }, now).ok, false);

  // Cross-chain exchange; no implicit material consumption on failure.
  const target = pool.find(i => i.group_id !== 1 && i.level === 1)!;
  assert.ok(target);
  uid = add(1001);
  const furnaceSource = state.grid.find(i => i.uid === uid)!;
  const furnace = body({ artifact: "furnace", uids: [uid], target_id: target.id });
  const furnaceResult = service.transact(state, "use", furnace, now);
  assert.equal(furnaceResult.ok, true);
  assert.equal(furnaceResult.spawned_items[0].id, target.id);
  assert.deepEqual([furnaceResult.spawned_items[0].col, furnaceResult.spawned_items[0].row], [furnaceSource.col, furnaceSource.row]);
  assert.equal(furnaceResult.pending_rewards_added, 0);
  const afterFurnace = structuredClone(state);
  assert.equal(service.transact(state, "use", furnace, now).replayed, true);
  assert.deepEqual(state, afterFurnace);
  const furnaceInput = add(1001);
  assert.equal(service.preview(state, { artifact: "furnace", uids: [furnaceInput], target_id: 1004 }, now).reason, "same_level_other_item");
  assert.equal(service.preview(state, { artifact: "furnace", uids: [furnaceInput], target_id: 1001 }, now).reason, "same_level_other_item");
  assert.equal(service.preview(state, { artifact: "furnace", uids: [furnaceInput, add(1001)], target_id: target.id }, now).reason, "invalid_materials");
  const lockedPool = structuredClone(state);
  lockedPool.grid = [{ id: 1001, uid: 99901, col: 0, row: 0 }];
  lockedPool.unlocked_production_item_ids = [materialLaunchers.find(i => i.spawns?.some(s => engine.getItemData(s.id)?.group_id === 1))!.id];
  const lockedTarget = pool.find(i => i.level === 1 && !service.materialPool(lockedPool).some(allowed => allowed.id === i.id))!;
  assert.ok(lockedTarget, "test requires a material from another locked source");
  assert.equal(service.preview(lockedPool, { artifact: "furnace", uids: [99901], target_id: lockedTarget.id }, now).reason, "invalid_target");
  assert.equal(service.preview(state, { artifact: "furnace", uids: [protect], target_id: 1701 }, now).ok, false);

  // Pricing and quota are independent; stale prices and cross-day quotes cannot debit.
  state.spirit_stones = 10000000;
  const buy = (id: string, timestamp = now) => {
    const v = service.view(state, timestamp), a = v.artifacts.find(a => a.id === id)!;
    return { artifact: id, period_key: v.period_key, version: state.version, request_id: `buy-${state.version}`,
      expected_cost: a.next_cost, expected_purchase_count: a.purchase_count };
  };
  const first = buy("basin");
  assert.equal(service.transact(state, "buy", first, now).ok, true);
  const balance = state.spirit_stones;
  assert.equal(service.transact(state, "buy", first, now).replayed, true);
  assert.equal(state.spirit_stones, balance);
  assert.equal(service.transact(state, "buy", buy("basin"), now).ok, true);
  assert.equal(service.transact(state, "buy", buy("basin"), now).reason, "daily_limit");
  assert.equal(service.view(state, now).artifacts[1].purchase_count, 0);
  assert.equal(service.transact(state, "buy", buy("furnace"), atReset).reason, "state_conflict");
  state.cultivation.current_level = 11;
  assert.ok(service.view(state, now).artifacts[0].next_cost > 4000);
  state.cultivation.current_level = 6;

  // Time-sand acceleration leaves result unclaimed, does not charge stones, and shares quota.
  const table = engine.getAllItemDefs().find(i => i.type === 2)!;
  const tableUid = add(table.id);
  const craftItem = state.grid.find(i => i.uid === tableUid)!;
  craftItem.craft = { _craft_init: true, _craft_state: TableState.CRAFTING, _craft_stored: [], _craft_recipe: { craft_time: 600 },
    _craft_progress: 0, _craft_result_id: 1001, _craft_start_time: now };
  const sand = body({ artifact: "sand", mode: "accelerate", uid: tableUid });
  const stones = state.spirit_stones;
  assert.equal(service.transact(state, "use", sand, now).ok, true);
  assert.equal(craftItem.craft._craft_state, TableState.READY);
  assert.equal(state.spirit_stones, stones);
  assert.equal(service.view(state, now).artifacts[2].remaining, 0);
  assert.equal(service.transact(state, "buy", buy("sand"), now).ok, true);

  // Undo restores only action effects and cannot restore time-sand quota or random sequence.
  const saleUid = add(1002);
  const beforeSale = structuredClone(state.grid);
  const saleStones = state.spirit_stones;
  assert.equal(engine.sellItem(state, saleUid).ok, true);
  const realNow = Date.now();
  assert.equal(service.view(state, realNow).rewind.available, true);
  const sequence = state.spawn_sequence;
  const counter = state.uid_counter;
  const rewind = body({ artifact: "sand", mode: "rewind" }, realNow);
  assert.equal(service.transact(state, "use", rewind, realNow).ok, true);
  assert.deepEqual(state.grid, beforeSale);
  assert.equal(state.spirit_stones, saleStones);
  assert.equal(state.spawn_sequence, sequence);
  assert.equal(state.uid_counter, counter);
  assert.equal(service.view(state, realNow).rewind.available, false);
  assert.equal(service.transact(state, "use", rewind, realNow).replayed, true);
  engine.sellItem(state, saleUid);
  assert.equal(service.view(state, Date.now() + 61000).rewind.available, false);
  state.version++;
  assert.equal(service.preview(state, { artifact: "sand", mode: "rewind" }).ok, false);

  // Exercise real merge/spawn snapshots, including quest rewards, discovery, cooldown and stamina.
  const fresh = () => {
    const s = engine.createInitialState();
    s.cultivation.current_level = 6;
    s.grid = [{ id: 11001, uid: engine._nextUid(s), col: 0, row: 0,
      charges: engine.getItemData(11001)!.max_charges, last_charge_time: Date.now() }];
    return s;
  };
  const useOn = (s: GameState, selection: any) => {
    const preview = service.preview(s, selection);
    assert.equal(preview.ok, true, JSON.stringify(preview));
    return service.transact(s, "use", { ...selection, request_id: `extra-${s.version}`,
      version: s.version, period_key: service.view(s).period_key, quote: service.quoteKey(preview) });
  };
  for (const action of ["merge", "spawn", "sell"]) {
    const s = fresh();
    s.grid.push({ id: 1001, uid: engine._nextUid(s), col: 1, row: 0 },
      { id: 1001, uid: engine._nextUid(s), col: 2, row: 0 });
    const before = service.snapshot(s);
    if (action === "merge") assert.equal(engine.executeMerge(s, 1, 0, 2, 0).ok, true);
    else if (action === "sell") assert.equal(engine.sellItem(s, s.grid[1].uid!).ok, true);
    else {
      const spawn = engine.executeSpawn(s, 0, 0);
      assert.equal(spawn.ok, true);
      if (!spawn.ok) throw Error(spawn.reason);
      s.spawn_history = [{ request_id: "rewound-spawn", result: spawn }];
    }
    const counterAfter = s.uid_counter;
    const entropyAfter = s.spawn_sequence;
    assert.equal(useOn(s, { artifact: "sand", mode: "rewind" }).ok, true);
    assert.deepEqual(service.snapshot(s), before, `${action}: dependent state and rewards restored together`);
    assert.equal(s.uid_counter, counterAfter);
    assert.equal(s.spawn_sequence, entropyAfter);
    if (action === "spawn") assert.equal(s.spawn_history![0].result.reverted, true);
  }
  const launcherState = fresh();
  launcherState.grid[0].charges = 0;
  assert.equal(useOn(launcherState, { artifact: "sand", mode: "accelerate", uid: launcherState.grid[0].uid }).ok, true);
  assert.equal(launcherState.grid[0].charges, engine.getItemData(11001)!.max_charges);
  const full = fresh();
  for (let index = 1; index < 63; index++) full.grid.push({ id: 5001, uid: engine._nextUid(full), col: index % 7, row: Math.floor(index / 7) });
  assert.equal(useOn(full, { artifact: "basin", uids: [full.grid[1].uid] }).ok, true);
  assert.equal(full.pending_rewards.filter(i => i.id === 5004).length, 1, "full board sends only overflow to pending rewards");
  assert.equal(full.grid.filter(i => i.id === 5004).length, 1, "consumed input frees one cell even on full board");
  assert.equal(full.grid.length, 63);
  const furnaceFull = structuredClone(full);
  furnaceFull.unlocked_production_item_ids = materialLaunchers.map(i => i.id);
  const fullSource = furnaceFull.grid.find(i => i.id === 5001)!;
  const fullTarget = service.materialPool(furnaceFull).find(i => i.level === 1 && i.id !== 5001)!;
  const fullPendingCount = furnaceFull.pending_rewards.length;
  const fullFurnace = useOn(furnaceFull, { artifact: "furnace", uids: [fullSource.uid], target_id: fullTarget.id });
  assert.equal(fullFurnace.spawned_items.length, 1);
  assert.deepEqual([fullFurnace.spawned_items[0].col, fullFurnace.spawned_items[0].row], [fullSource.col, fullSource.row]);
  assert.equal(furnaceFull.grid.length, 63);
  assert.equal(furnaceFull.pending_rewards.length, fullPendingCount);
  const singleSpace = fresh();
  for (let index = 1; index < 62; index++) singleSpace.grid.push({ id: 5001, uid: engine._nextUid(singleSpace), col: index % 7, row: Math.floor(index / 7) });
  const partialDelivery = useOn(singleSpace, { artifact: "basin", uids: [singleSpace.grid[1].uid] });
  assert.equal(partialDelivery.spawned_items.length, 2, "one initial gap plus freed input cell fits both outputs");
  assert.equal(partialDelivery.pending_rewards_added, 0);
  assert.equal(singleSpace.grid.length, 63);
  assert.equal(new Set(singleSpace.grid.map(i => `${i.col},${i.row}`)).size, 63);
  const empty = fresh();
  empty.grid = [{ id: 5001, uid: engine._nextUid(empty), col: 3, row: 4 }];
  empty.unlocked_production_item_ids = [11001];
  const emptyDelivery = useOn(empty, { artifact: "basin", uids: [empty.grid[0].uid] });
  assert.equal(emptyDelivery.spawned_items.length, 2);
  assert.equal(empty.grid.length, 2);
  assert.equal(empty.pending_rewards.length, 0);
  const poor = fresh();
  poor.spirit_stones = 0;
  const offer = service.view(poor).artifacts[0];
  const poorBody = { artifact: "basin", version: poor.version, period_key: service.view(poor).period_key,
    request_id: "poor", expected_cost: offer.next_cost, expected_purchase_count: 0 };
  const poorBefore = structuredClone(poor);
  assert.equal(service.transact(poor, "buy", poorBody).reason, "insufficient_stones");
  assert.deepEqual(poor, poorBefore);
  poor.cultivation.current_level = 1;
  assert.equal(service.transact(poor, "buy", poorBody).reason, "artifact_locked");

  // Real authenticated routes, persistent rollback and simultaneous request replay.
  class TestStorage extends MemoryStorage {
    fail = false;
    override async saveState(id: string, s: GameState) { if (this.fail) { this.fail = false; throw Error("save_failed"); } await super.saveState(id, s); }
  }
  const storage = new TestStorage();
  original.cultivation.current_level = 6;
  original.spirit_stones = 1000000;
  original.grid.push({ id: 1002, uid: engine._nextUid(original), col: 4, row: 8 });
  await storage.saveState("artifacts", original);
  const router = createGameRouter(storage, engine, "artifact-secret");
  const token = await signToken({ userId: "artifacts", deviceId: "artifact-device" }, "artifact-secret");
  const request = async (path: string, requestBody: any = {}, method = "POST") => {
    const response = new WorkerResponse();
    await router.handle({ method, path, body: requestBody, headers: { authorization: `Bearer ${token}` }, query: {} }, response);
    return { status: response.statusCode, data: await response.toResponse().json() as any };
  };
  const selection = { artifact: "basin", uids: [use.uids[0]] };
  const quote = await request("/golden_finger/preview", selection);
  assert.equal(quote.status, 200);
  const routedUse = { ...selection, quote: quote.data.quote, version: quote.data.version,
    period_key: quote.data.golden_finger.period_key, request_id: "routed-use" };
  const beforeFailure = await storage.loadState("artifacts");
  storage.fail = true;
  assert.equal((await request("/golden_finger/use", routedUse)).status, 500);
  assert.deepEqual(await storage.loadState("artifacts"), beforeFailure);
  const concurrent = await Promise.all([request("/golden_finger/use", routedUse), request("/golden_finger/use", routedUse)]);
  assert.deepEqual(concurrent.map(r => r.status), [200, 200]);
  assert.equal(concurrent[1].data.replayed, true);
  assert.equal(concurrent[1].data.grid.filter((r: any) => r.id === 1004).length, 2);
  assert.deepEqual(concurrent[0].data.spawned_items, concurrent[1].data.spawned_items, "retries return the same destination UIDs");
  assert.equal((await request("/golden_finger/use", { ...routedUse, request_id: "stale" })).status, 409);
  const sale = (await storage.loadState("artifacts"))!.grid.find(i => i.id === 1002 || i.id === 1004);
  if (sale) {
    assert.equal((await request("/shop/sell", { uid: sale.uid })).status, 200);
    const info = await request("/golden_finger", {}, "GET");
    assert.equal(info.data.golden_finger.rewind.available, true, "route round trip retains usable rewind");
    const undo = await request("/golden_finger/preview", { artifact: "sand", mode: "rewind" });
    assert.equal(undo.status, 200);
    const undoBody = { artifact: "sand", mode: "rewind", quote: undo.data.quote, version: undo.data.version,
      period_key: undo.data.golden_finger.period_key, request_id: "routed-undo" };
    assert.equal((await request("/golden_finger/use", undoBody)).status, 200);
    assert.ok((await storage.loadState("artifacts"))!.grid.some(i => i.uid === sale.uid));
  }
  console.log("GOLDEN_FINGER_SMOKE_OK unlock caps cross-chain quota reset replay rollback shared-time undo routes");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
