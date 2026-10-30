import assert from "node:assert/strict";
import { GameEngine, TableState } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { GameState } from "../src/storage/interface";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

class TestStorage extends MemoryStorage {
  fail = false;
  override async saveState(id: string, state: GameState): Promise<void> {
    if (this.fail) { this.fail = false; throw new Error("save_failed"); }
    await super.saveState(id, state);
  }
}

async function main() {
  const config = gameConfigTables;
  const engine = new GameEngine(config);
  assert.equal(engine.getOrderSupplyMaterialLevel(1), 1);
  assert.equal(engine.getOrderSupplyMaterialLevel(3), 1);
  assert.equal(engine.getOrderSupplyMaterialLevel(4), 2);
  assert.equal(engine.getOrderSupplyMaterialLevel(6), 2);
  assert.equal(engine.getOrderSupplyMaterialLevel(7), 3);
  assert.equal(engine.getOrderSupplyMaterialLevel(9), 3);
  assert.equal(engine.getOrderSupplyMaterialLevel(10), 5);
  assert.equal(engine.getOrderSupplyMaterialLevel(11), 6);
  assert.equal(engine.getOrderSupplyMaterialLevel(12), 7);
  assert.equal(engine.getOrderSupplyMaterialLevel(13), 9);
  assert.equal(engine.getOrderSupplyMaterialLevel(15), 11);
  assert.equal(engine.getOrderSupplyMaterialLevel(16), 13);
  assert.equal(engine.getOrderSupplyMaterialLevel(18), 15);
  assert.deepEqual(engine.getOrderSupplyMaterials(5006, 1), [5001]);
  assert.deepEqual(engine.getOrderSupplyMaterials(5006, 4), [5002]);
  assert.deepEqual(engine.getOrderSupplyMaterials(5006, 10), [5005]);
  assert.deepEqual(engine.getOrderSupplyMaterials(5001, 4), [5001]);
  assert.deepEqual(engine.getOrderSupplyMaterials(5002, 4), [5002]);
  assert.deepEqual(engine.getOrderSupplyMaterials(27001, 4), [5001, 9001]);
  // Supply resolves high-level items and crafted products into level-one merge materials.
  const claimMaterials = (rewardEngine: GameEngine, itemIds: number[], gridIds: number[] = [],
    setup: (state: GameState) => void = () => {}) => {
    const rewardState = rewardEngine.createInitialState(); rewardState.cultivation.current_level = 2;
    rewardState.meridian_acupoints = [{ item_id: itemIds[0], name: "materials", count: itemIds.length,
      item_ids: itemIds, completed: false } as any];
    rewardState.grid = gridIds.map((id, col) => ({ id, uid: rewardEngine._nextUid(rewardState), col, row: 0 }));
    rewardEngine.activityEngine.initProgress(rewardState);
    rewardState.activity_progress![7].current_count = 5;
    setup(rewardState);
    const claim = rewardEngine.activityEngine.claimOrderSupply(rewardState, 7, 0, rewardEngine);
    assert.equal(claim.ok, true);
    if (!claim.ok) throw new Error(claim.reason);
    assert.equal(rewardState.activity_progress![7].current_count, 0);
    assert.ok(claim.spawned_items.every(item => {
      const def = rewardEngine.getItemData(item.id)!;
      return def.type === 0 && def.level <= rewardEngine.getOrderSupplyMaterialLevel(rewardState.cultivation.current_level);
    }));
    return claim.spawned_items.map(item => item.id);
  };
  assert.deepEqual(claimMaterials(engine, [5006]), [5001, 5001, 5001]);
  // A realm's supply tier must never upgrade a lower-level order requirement.
  const midRealm = (s: GameState) => { s.cultivation.current_level = 4; };
  assert.deepEqual(claimMaterials(engine, [5001], [], midRealm), [5001, 5001, 5001]);
  assert.deepEqual(claimMaterials(engine, [5001], [5001], midRealm), [5001, 5001, 5001]);
  assert.deepEqual(claimMaterials(engine, [5002], [], midRealm), [5002, 5002, 5002]);
  assert.deepEqual(claimMaterials(engine, [5001, 5002], [5002], midRealm), [5001, 5001, 5001]);
  assert.deepEqual(claimMaterials(engine, [5001, 5002], [5001], midRealm), [5002, 5002, 5002]);
  assert.deepEqual(claimMaterials(engine, [27001], [5001], midRealm), [9001, 9001, 9001]);
  assert.deepEqual(claimMaterials(engine, [27002], [5001, 5001], midRealm), [9002, 9002, 9002]);
  assert.deepEqual(claimMaterials(engine, [27001], [27001], midRealm), [5001, 9001, 5001]);
  assert.deepEqual(claimMaterials(engine, [27001], [5001, 9001], midRealm), [5001, 9001, 5001]);
  assert.deepEqual(claimMaterials(engine, [27004]), [5001, 1001, 9001]);
  assert.deepEqual(claimMaterials(engine, [27004], [27004]), [5001, 1001, 9001]);
  assert.deepEqual(claimMaterials(engine, [27004, 1006], [27004]), [1001, 1001, 1001]);
  const nested = new GameEngine({ ...config, recipes: { recipes: config.recipes.recipes.map(recipe =>
    recipe.result === 27004 ? { ...recipe, ingredients: [27001, 1002, 9003] } : recipe) } });
  assert.deepEqual(claimMaterials(nested, [27004]), [5001, 9001, 1001]);
  // Enough rice (including lower-level merge inputs) means only water is supplied.
  assert.deepEqual(claimMaterials(engine, [27001], [5001]), [9001, 9001, 9001]);
  assert.deepEqual(claimMaterials(engine, [27002], [5001, 5001]), [9001, 9001, 9001]);
  assert.deepEqual(claimMaterials(engine, [27002], [5001]), [5001, 9001, 5001]);
  // One item cannot satisfy two products or a product plus a direct material order.
  assert.deepEqual(claimMaterials(engine, [27001, 27001], [5001]), [5001, 9001, 5001]);
  assert.deepEqual(claimMaterials(engine, [27001, 5001], [5001]), [5001, 9001, 5001]);
  assert.deepEqual(claimMaterials(engine, [27001, 9001], [5001, 9001]), [9001, 9001, 9001]);
  // Ordinary inventory in pouches, pending rewards and storage also fills a shortage.
  assert.deepEqual(claimMaterials(engine, [27001], [], s => { s.pouch = [{ id: 5001, uid: engine._nextUid(s) }]; }), [9001, 9001, 9001]);
  assert.deepEqual(claimMaterials(engine, [27001], [], s => { s.pending_rewards = [{ id: 5001, uid: engine._nextUid(s), name: "rice" }]; }), [9001, 9001, 9001]);
  assert.deepEqual(claimMaterials(engine, [27001], [5001], s => { s.grid[0].immovable = true; }), [5001, 9001, 5001]);
  assert.deepEqual(claimMaterials(engine, [27001], [17001], s => {
    s.grid[0].storage = { items: [{ id: 5001 }], max_slots: 1 };
  }), [9001, 9001, 9001]);
  const testRecipe = config.recipes.recipes[0];
  const setCraft = (s: GameState, state: TableState) => {
    s.grid[0].craft = { _craft_init: true, _craft_state: state, _craft_stored: [{ id: 5001 }],
      _craft_recipe: testRecipe, _craft_progress: 0, _craft_result_id: testRecipe.result, _craft_start_time: Date.now() };
  };
  assert.deepEqual(claimMaterials(engine, [27001], [17001], s => setCraft(s, TableState.HAS_ITEMS)), [9001, 9001, 9001]);
  for (const state of [TableState.CRAFTING, TableState.READY]) {
    // A finished/in-progress product covers its order; consumed craft inputs are not reusable.
    assert.deepEqual(claimMaterials(engine, [27001, 1006], [17001], s => setCraft(s, state)), [1001, 1001, 1001]);
    assert.deepEqual(claimMaterials(engine, [27001, 5001], [17001], s => setCraft(s, state)), [5001, 5001, 5001]);
  }
  // When every recipe input is sufficient, fall back to the current order chains.
  assert.deepEqual(claimMaterials(engine, [27002], [5001, 5001, 9001, 9001]), [5001, 9001, 5001]);
  assert.deepEqual(claimMaterials(engine, [27004], [5004, 1002]), [9001, 9001, 9001]);
  assert.deepEqual(claimMaterials(engine, [27004], [5004, 1002], s => { s.cultivation.current_level = 11; }), [9003, 9003, 9003]);
  assert.deepEqual(claimMaterials(nested, [27004], [5001, 1002]), [9001, 9001, 9001]);
  const shortageState = engine.createInitialState(); shortageState.cultivation.current_level = 2;
  shortageState.grid = [{ id: 5001, uid: 1000, col: 0, row: 0 }];
  shortageState.meridian_acupoints = [
    { item_ids: [27001], name: "live", completed: false },
    { item_ids: [1006], name: "submitted", completed: true },
    { item_ids: [5001], name: "breakthrough", completed: false, breakthrough_order: true } as any,
  ];
  const beforeShortage = structuredClone(shortageState);
  assert.deepEqual(engine.getMissingOrderSupplyMaterials(shortageState), [9001]);
  assert.deepEqual(shortageState, beforeShortage, "shortage calculation must not consume saved inventory");
  for (const cultivationLevel of [2, 4, 11]) {
    const fallback = engine.createInitialState(); fallback.cultivation.current_level = 2;
    fallback.cultivation.current_level = cultivationLevel;
    fallback.meridian_acupoints = [];
    engine.activityEngine.initProgress(fallback);
    engine.activityEngine.initProgress(fallback);
    fallback.activity_progress![7].current_count = 5;
    const fallbackClaim = engine.activityEngine.claimOrderSupply(fallback, 7, 0, engine);
    assert.equal(fallbackClaim.ok, true);
    if (fallbackClaim.ok) assert.ok(fallbackClaim.spawned_items.every(item => {
      const def = engine.getItemData(item.id)!;
      return def.type === 0 && def.level === engine.getOrderSupplyMaterialLevel(cultivationLevel);
    }));
  }
  const state = engine.createInitialState(); state.cultivation.current_level = 2;
  assert.equal(engine.activityEngine.isActive(engine.activityEngine.getActivities().find(a => a.id === 7)!), true);
  assert.equal(engine.completeMeridianAcupoint(state, 999, [5001]).ok, false);
  assert.equal(state.activity_progress?.[7]?.current_count ?? 0, 0);
  for (let i = 0; i < 6; i++) {
    state.meridian_acupoints = [{ item_ids: [5001], name: "test", completed: false }];
    state.cultivation.current_qi = 0;
    state.grid = [{ id: 5001, uid: engine._nextUid(state), col: 0, row: 0 }];
    assert.equal(engine.completeMeridianAcupoint(state, 0, [5001], `supply-order-${i}`).ok, true);
    assert.equal(state.activity_progress?.[7]?.current_count ?? 0, 0);
    assert.equal(engine.completeMeridianAcupoint(state, 0, [5001], `supply-order-${i}`).ok, false);
    assert.equal(state.activity_progress?.[7]?.current_count ?? 0, 0);
  }
  for (let i = 0; i < 6; i++) {
    state.meridian_acupoints = [{ item_ids: [5002], name: "test", completed: false }];
    state.grid = [0, 1].map(col => ({ id: 5001, uid: engine._nextUid(state), col, row: 0 }));
    assert.equal(engine.executeMerge(state, 0, 0, 1, 0).ok, true);
    assert.equal(state.activity_progress![7].current_count, Math.min(5, i + 1));
  }
  engine.activityEngine.checkAndReset(state, 0);
  assert.equal(state.activity_progress![7].current_count, 5);
  // Reward the missing high-level material's base, rather than the order item itself.
  state.meridian_acupoints = [{ item_id: 1001, name: "next", count: 1, completed: false, item_ids: [1001, 5006] } as any];
  state.grid = [{ id: 1001, uid: engine._nextUid(state), col: 0, row: 0 }];
  const storage = new TestStorage();
  await storage.saveState("supply", state);
  const router = createGameRouter(storage, engine, "supply-test-secret");
  const token = await signToken({ userId: "supply", deviceId: "supply-test" }, "supply-test-secret");
  async function request(path: string, body: unknown, method = "POST") {
    const response = new WorkerResponse();
    await router.handle({ method, path, body, headers: { authorization: `Bearer ${token}` }, query: {} }, response);
    return { status: response.statusCode, data: await response.toResponse().json() as any };
  }
  const path = "/activity/order_supply/claim";
  const body = { activity_id: 7, expected_claim_count: 0 };
  assert.equal((await request(path, { ...body, activity_id: "7" })).data.error, "invalid_params");
  assert.equal((await request(path, { ...body, expected_claim_count: -1 })).data.error, "invalid_params");
  assert.equal((await request(path, { ...body, activity_id: 3 })).data.error, "invalid_activity");
  storage.fail = true;
  assert.equal((await request(path, body)).status, 500);
  assert.equal((await storage.loadState("supply"))!.activity_progress![7].current_count, 5);
  assert.deepEqual((await storage.loadState("supply"))!.grid, state.grid);
  const claims = await Promise.all([request(path, body), request(path, body)]);
  assert.equal(claims.filter(claim => claim.status === 200).length, 1);
  assert.equal(claims.filter(claim => claim.data.error === "already_claimed").length, 1);
  const successfulClaim = claims.find(claim => claim.status === 200)!;
  assert.equal(successfulClaim.data.spawned_items.length, 3);
  assert.ok(successfulClaim.data.spawned_items.every((item: any) => item.id === 5001));
  let reloaded = (await storage.loadState("supply"))!;
  assert.equal(reloaded.grid.length, 4);
  assert.equal(new Set(reloaded.grid.map(i => `${i.col},${i.row}`)).size, 4);
  assert.equal(new Set(reloaded.grid.map(i => i.uid)).size, 4);
  assert.equal(reloaded.activity_progress![7].current_count, 0);
  assert.equal(reloaded.activity_progress![7].claim_count, 1);
  assert.deepEqual(reloaded.pending_rewards, state.pending_rewards);
  assert.equal((await request(path, { ...body, expected_claim_count: 1 })).data.error, "activity_not_completed");
  assert.equal((await request("/state", {}, "GET")).data.activity_progress[7].current_count, 0);
  reloaded = (await storage.loadState("supply"))!;

  reloaded.activity_progress![7].current_count = 5;
  const originalPending = structuredClone(reloaded.pending_rewards);
  reloaded.grid = Array.from({ length: 63 }, (_, i) => ({ id: 1001, uid: engine._nextUid(reloaded), col: i % 7, row: Math.floor(i / 7) }));
  await storage.saveState("supply", reloaded);
  const overflowClaim = await request(path, { ...body, expected_claim_count: 1 });
  assert.equal(overflowClaim.status, 200);
  assert.equal(overflowClaim.data.spawned_items.length, 0);
  assert.equal(overflowClaim.data.pending_rewards_added, 3);
  assert.deepEqual(overflowClaim.data.rewards.items, [{ id: 5001, count: 3 }]);
  assert.equal(overflowClaim.data.pending_rewards.length, originalPending.length + 3);
  reloaded = (await storage.loadState("supply"))!;
  assert.equal(reloaded.activity_progress![7].current_count, 0);
  assert.equal(reloaded.grid.length, 63);
  assert.equal(reloaded.pending_rewards.length, originalPending.length + 3);
  assert.deepEqual(reloaded.pending_rewards.slice(0, originalPending.length), originalPending);
  assert.equal((await request(path, { ...body, expected_claim_count: 1 })).data.error, "already_claimed");
  reloaded.grid.pop();
  reloaded.board_type = 1;
  await storage.saveState("supply", reloaded);
  assert.equal((await request(path, { ...body, expected_claim_count: 1 })).data.error, "main_board_required");
  reloaded = (await storage.loadState("supply"))!;
  reloaded.board_type = 0;
  reloaded.activity_progress![7].current_count = 5;
  await storage.saveState("supply", reloaded);
  assert.equal((await request(path, body)).data.error, "already_claimed");
  const partialClaim = await request(path, { ...body, expected_claim_count: 2 });
  assert.equal(partialClaim.status, 200);
  assert.equal(partialClaim.data.spawned_items.length, 1);
  assert.equal(partialClaim.data.pending_rewards_added, 2);
  assert.equal(partialClaim.data.pending_rewards.length, originalPending.length + 5);
  assert.equal((await storage.loadState("supply"))!.activity_progress![7].current_count, 0);

  reloaded = (await storage.loadState("supply"))!;
  const storedMaterial = reloaded.pending_rewards[originalPending.length];
  assert.equal(storedMaterial.id, 5001);
  assert.equal(storedMaterial.name, engine.getItemData(5001)!.name);
  assert.equal(new Set([...reloaded.grid, ...reloaded.pending_rewards].map(item => item.uid)).size,
    reloaded.grid.length + reloaded.pending_rewards.length);
  assert.equal((await request("/claim_pending_reward", { uid: storedMaterial.uid })).data.error, "board_full");
  reloaded.grid.pop();
  await storage.saveState("supply", reloaded);
  const retrieval = await request("/claim_pending_reward", { uid: storedMaterial.uid });
  assert.equal(retrieval.status, 200);
  assert.ok(retrieval.data.grid.some((item: any) => item.uid === storedMaterial.uid && item.id === storedMaterial.id));
  assert.ok(!retrieval.data.pending_rewards.some((item: any) => item.uid === storedMaterial.uid));
  assert.equal((await request("/claim_pending_reward", { uid: storedMaterial.uid })).data.error, "reward_not_found");

  // Claim completes all in-progress tables atomically, without retrieving their output.
  reloaded = (await storage.loadState("supply"))!;
  reloaded.meridian_acupoints = [{ item_ids: [5001], name: "test", completed: false }];
  reloaded.activity_progress![7].current_count = 5;
  const recipe = config.recipes.recipes[0];
  const craftStates = [TableState.CRAFTING, TableState.CRAFTING, TableState.HAS_ITEMS, TableState.READY];
  reloaded.grid = craftStates.map((craftState, col) => ({ id: 17001, uid: engine._nextUid(reloaded), col, row: 0,
    craft: { _craft_init: true, _craft_state: craftState, _craft_stored: [], _craft_recipe: recipe,
      _craft_progress: craftState === TableState.READY ? 1 : 0, _craft_result_id: recipe.result, _craft_start_time: Date.now() } }));
  await storage.saveState("supply", reloaded);
  const craftingBody = { ...body, expected_claim_count: 3 };
  await request("/state", {}, "GET");
  reloaded = (await storage.loadState("supply"))!;
  storage.fail = true;
  assert.equal((await request(path, craftingBody)).status, 500);
  assert.deepEqual((await storage.loadState("supply"))!.grid, reloaded.grid);
  const finished = await request(path, craftingBody);
  assert.equal(finished.status, 200);
  assert.equal(finished.data.crafts_completed, 2);
  assert.deepEqual(finished.data.grid.slice(0, 4).map((item: any) => item.craft._craft_state),
    [TableState.READY, TableState.READY, TableState.HAS_ITEMS, TableState.READY]);
  assert.equal(finished.data.grid[0].craft._craft_progress, 1);
  assert.deepEqual(finished.data.grid[0].craft._craft_recipe, recipe);
  assert.equal(finished.data.grid[0].craft._craft_result_id, recipe.result);
  assert.equal(finished.data.activity_progress[7].current_count, 0);
  assert.equal((await storage.loadState("supply"))!.spirit_stones, reloaded.spirit_stones);
  assert.equal((await request(path, craftingBody)).data.error, "already_claimed");
  const retrievedCraft = await request("/craft/retrieve", { table_col: 0, table_row: 0 });
  assert.equal(retrievedCraft.status, 200);
  assert.equal(retrievedCraft.data.result_id, recipe.result);
  assert.equal((await storage.loadState("supply"))!.activity_progress![7].current_count, 0);

  const disabled = new GameEngine({ ...config, activities: { activities: gameConfigTables.activities.activities.map(activity => ({ ...activity, enabled: activity.id === 7 ? false : activity.enabled })) } });
  const inactive = disabled.createInitialState(); inactive.cultivation.current_level = 2;
  inactive.meridian_acupoints = [{ item_ids: [5001], name: "test", completed: false }];
  disabled.activityEngine.recordOrderSupplyAction(inactive, 5001);
  assert.equal(inactive.activity_progress?.[7]?.current_count ?? 0, 0);
  assert.equal(disabled.activityEngine.claimOrderSupply(inactive, 7, 0, disabled).ok, false);
  console.log("order_supply_smoke: ok");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
