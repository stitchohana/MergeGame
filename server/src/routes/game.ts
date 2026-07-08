import { Router, Request, Response } from "express";
import { IStorage } from "../storage/interface";
import { authRequired } from "../middleware/auth";
import { GameEngine, TableState } from "../engine/game_engine";

// Per-user operation queue — sequential execution per user
const userQueues = new Map<string, Promise<void>>();

function enqueue(userId: string, fn: () => Promise<void>): Promise<void> {
  const prev = userQueues.get(userId) ?? Promise.resolve();
  const next = prev.then(fn, fn);
  userQueues.set(userId, next);
  return next;
}

// Operation wrapper: validates params, queues user op, handles errors
function op(handler: (req: Request, res: Response, userId: string) => Promise<void>) {
  return async (req: Request, res: Response): Promise<void> => {
    try {
      const userId = req.auth!.userId;
      await enqueue(userId, () => handler(req, res, userId));
    } catch (err) {
      console.error("[game] op error:", err);
      if (!res.headersSent) res.status(500).json({ error: "internal_error" });
    }
  };
}

export function createGameRouter(storage: IStorage, engine: GameEngine): Router {
  const router = Router();

  router.use(authRequired);

  async function getOrCreateState(userId: string) {
    let state = await storage.loadState(userId);
    if (!state) {
      state = engine.createInitialState();
      await storage.saveState(userId, state);
      console.log(`[game] new player ${userId}, init with ${state.grid.length} items | v0`);
    } else {
      const oldVer = state.version;
      // Migrate: add pouch if missing (old saves)
      if (!state.pouch) {
        state.pouch = [];
      }
      // Migrate: backfill uid for items without uid
      // Migrate: add pending_rewards if missing
      if (!state.pending_rewards) {
        state.pending_rewards = [];
      }
      if (!state.uid_counter) {
        state.uid_counter = 0;
      }
      for (const item of state.grid) {
        if (!item.uid) {
          state.uid_counter += 1;
          item.uid = state.uid_counter;
        }
      }
      // Migrate: convert old cultivation (current_realm_id + current_level) to flat current_level
      if (state.cultivation && typeof (state.cultivation as any).current_realm_id === "number") {
        const oldRealm = (state.cultivation as any).current_realm_id;
        const oldLv = state.cultivation.current_level;
        const realmOffsets = [0, 1, 10, 13, 16, 19, 22, 25, 28];
        const newLevel = (realmOffsets[oldRealm] ?? 0) + oldLv;
        console.log(`[game] migrating cultivation: realm=${oldRealm} lv=${oldLv} -> flat level=${newLevel}`);
        state.cultivation.current_level = newLevel;
        delete (state.cultivation as any).current_realm_id;
        state.version += 1;
      }

      // Re-initialize if grid is empty (stale save)
      if (!state.grid || state.grid.length === 0) {
        const init = engine.createInitialState();
        state.grid = init.grid;
        state.version += 1;
        await storage.saveState(userId, state);
        console.log(`[game] re-initialized empty grid for ${userId}: ${state.grid.length} items`);
      }
      if (state.version !== oldVer) {
        await storage.saveState(userId, state);
      }
      if (engine.tickCraftingState(state)) {
        await storage.saveState(userId, state);
      }
      engine.tickStamina(state);
      engine.tickLauncherRecharge(state);
    }
    return state;
  }

  function buildStateResponse(state: any, engine: GameEngine, regenRemainingMs: number) {
    return {
      grid: state.grid,
      main_grid: state.saved_grid ?? state.grid,
      battle_grid: (state.saved_grid ? state.grid : (state.battle_grid?.length ? state.battle_grid : engine.createInitialState("battle").grid)),
      pouch: state.pouch,
      cultivation: state.cultivation,
      stamina: state.stamina,
      max_stamina: state.max_stamina,
      spirit_stones: state.spirit_stones,
      version: state.version,
      regen_remaining_ms: regenRemainingMs,
      battle_map_id: state.battle_map_id,
      battle_stage: state.battle_stage,
      meridian_acupoints: state.meridian_acupoints,
      meridian_circulations: state.meridian_circulations,
      meridian_threshold_idx: state.meridian_threshold_idx,
      quest_progress: state.quest_progress,
      quest_defs: engine.questEngine.getResolvedQuestDefs(engine), home_meridian_defs: engine.getHomeMeridianDefs(),
      activity_defs: engine.activityEngine.getActivities().map(a => ({ ...a, active: engine.activityEngine.isActive(a) })),
      activity_progress: state.activity_progress,
      activity_current_day: engine.activityEngine.getCurrentDay(3, engine.questResetHour),
      pending_rewards: state.pending_rewards, home_meridian_progress: state.home_meridian_progress,
    };
  }

  // GET /api/game/state
  router.get("/state", async (req: Request, res: Response) => {
    try {
      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);
      // Restore main grid if returning from battle after reconnect
      if (state.saved_grid && state.saved_grid.length > 0) {
        state.grid = state.saved_grid;
        state.saved_grid = undefined;
        state.version += 1;
        await storage.saveState(userId, state);
        console.log(`[game] restored main grid for ${userId}: ${state.grid.length} items`);
      }
      const regenRemainingMs = engine.getRegenRemainingMs(state);
      // Add recharge remaining time to launcher items
      const now = Date.now();
      for (const item of state.grid) {
        const itemDef = engine.getItemData(item.id);
        if (!itemDef || itemDef.type !== "launcher") continue;
        const rt = itemDef.recharge_time ?? 0;
        if (rt <= 0) continue;
        const maxC = itemDef.max_charges ?? 3;
        const charges = item.charges ?? maxC;
        if (charges >= maxC) continue;
        const lct = item.last_charge_time ?? now;
        const elapsed = (now - lct) / 1000;
        if (elapsed < rt) {
          (item as any)._recharge_remaining = (rt - elapsed) * 1000;
        }
      }
      console.log(`[game] state response: grid=${state.grid.length} items, first uid=${state.grid[0]?.uid ?? "missing"}`);
      engine.questEngine.initQuestProgress(state);
      const questResetOccurred = engine.questEngine.checkAndResetQuests(state, engine.questResetHour);
      engine.activityEngine.initProgress(state);
      engine.activityEngine.checkAndReset(state, engine.questResetHour);
      if (questResetOccurred) {
        try {
          await storage.saveState(userId, state);
        } catch (e) {
          console.error("[game] failed to save state after quest reset:", e);
        }
      }
      res.json(buildStateResponse(state, engine, regenRemainingMs));
    } catch (err) {
      console.error("[game] state error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/merge
  router.post("/merge", op(async (req, res, userId) => {
    const { from, to, version } = req.body;
    if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2 || typeof version !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeMerge(state, from[0], from[1], to[0], to[1]);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: result.newVersion, result_uid: result.resultUid, result_id: result.resultId, from_col: result.fromCol, from_row: result.fromRow, to_col: result.toCol, to_row: result.toRow, regen_remaining_ms: engine.getRegenRemainingMs(state), quest_progress: state.quest_progress });
  }));

  // POST /api/game/spawn
  router.post("/spawn", op(async (req, res, userId) => {
    const { launcher_pos } = req.body;
    if (!Array.isArray(launcher_pos) || launcher_pos.length !== 2) {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    if (!engine.isInBounds(launcher_pos[0], launcher_pos[1])) {
      res.status(400).json({ error: "out_of_bounds" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeSpawn(state, launcher_pos[0], launcher_pos[1]);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, spawned_uid: result.spawnedUid, spawned_id: result.spawnedId, spawned_name: result.spawnedName, target_col: result.targetCol, target_row: result.targetRow, new_version: result.newVersion, stamina: state.stamina, max_stamina: state.max_stamina, charges: result.charges, max_charges: result.maxCharges, recharge_time: result.rechargeTime, cultivation: state.cultivation, regen_remaining_ms: engine.getRegenRemainingMs(state), quest_progress: state.quest_progress });
  }));

  // POST /api/game/craft/add
  router.post("/craft/add", op(async (req, res, userId) => {
    const { table_col, table_row, ingredient_id, from_col, from_row, version } = req.body;
    if (typeof table_col !== "number" || typeof table_row !== "number" || typeof ingredient_id !== "number" || typeof from_col !== "number" || typeof from_row !== "number" || typeof version !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.addIngredientToTable(state, table_col, table_row, ingredient_id, from_col, from_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, matched: result.matched, new_version: result.newVersion });
  }));

  // POST /api/game/craft/start
  router.post("/craft/start", op(async (req, res, userId) => {
    const { table_col, table_row, version } = req.body;
    if (typeof table_col !== "number" || typeof table_row !== "number" || typeof version !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeCraftStart(state, table_col, table_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: result.newVersion, recipe_id: result.recipe.id, craft_time: result.recipe.craft_time });
  }));

  // POST /api/game/craft/retrieve
  router.post("/craft/retrieve", op(async (req, res, userId) => {
    const { table_col, table_row, version } = req.body;
    if (typeof table_col !== "number" || typeof table_row !== "number" || typeof version !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeCraftRetrieve(state, table_col, table_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, result_uid: result.resultUid, result_id: result.resultId, new_version: result.newVersion, quest_progress: state.quest_progress });
  }));


  // POST /api/game/craft/remove
  router.post("/craft/remove", op(async (req, res, userId) => {
    const { table_col, table_row, ingredient_id, target_col, target_row } = req.body;
    if (typeof table_col !== "number" || typeof table_row !== "number" || typeof ingredient_id !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.removeIngredientFromTable(state, table_col, table_row, ingredient_id, target_col, target_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: result.newVersion, grid: state.grid });
  }));

  // POST /api/game/push_place
  router.post("/push_place", op(async (req, res, userId) => {
    const { from, to, version } = req.body;
    if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2 || typeof version !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    console.log(`[game] push_place: from=(${from[0]},${from[1]}) to=(${to[0]},${to[1]}) v=${version}`);
    const result = engine.pushAndPlace(state, from[0], from[1], to[0], to[1]);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: result.newVersion, pushed_col: result.pushed_col, pushed_row: result.pushed_row, from_col: result.from_col, from_row: result.from_row, to_col: result.to_col, to_row: result.to_row });
  }));

  // POST /api/game/move
  router.post("/move", op(async (req, res, userId) => {
    const { from, to, version } = req.body;
    if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2 || typeof version !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeMove(state, from[0], from[1], to[0], to[1]);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: result.newVersion, grid: state.grid });
  }));

  // POST /api/game/shop/sell
  router.post("/shop/sell", op(async (req, res, userId) => {
    const { uid } = req.body;
    if (typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.sellItem(state, uid);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, spirit_stones: result.stones, quest_progress: state.quest_progress });
  }));

  // POST /api/game/shop/buy
  router.post("/shop/buy", op(async (req, res, userId) => {
    const { item_id, target_col, target_row } = req.body;
    if (typeof item_id !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.buyItem(state, item_id, target_col, target_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, uid: result.uid, spirit_stones: result.stones });
  }));

  // GET /api/game/shop/items
  router.get("/shop/items", async (req: Request, res: Response) => {
    try {
      const items = engine.getShopItems().map((s: any) => ({
        id: s.id,
        name: engine.getItemData(s.id)?.name ?? ("#" + s.id),
        price: s.price,
      }));
      res.json({ items });
    } catch (err) {
      console.error("[game] shop items error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/storage/deposit
  router.post("/storage/deposit", op(async (req, res, userId) => {
    const { storage_col, storage_row, item_id, from_col, from_row } = req.body;
    if (typeof storage_col !== "number" || typeof storage_row !== "number" || typeof item_id !== "number" || typeof from_col !== "number" || typeof from_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.depositItem(state, storage_col, storage_row, item_id, from_col, from_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: result.newVersion, grid: state.grid });
  }));

  // POST /api/game/storage/withdraw
  router.post("/storage/withdraw", op(async (req, res, userId) => {
    const { storage_col, storage_row, item_id, target_col, target_row } = req.body;
    if (typeof storage_col !== "number" || typeof storage_row !== "number" || typeof item_id !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.withdrawItem(state, storage_col, storage_row, item_id, target_col, target_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    const storageItem = state.grid.find(i => i.col === storage_col && i.row === storage_row);
    res.json({ ok: true, new_version: result.newVersion, storage: storageItem?.storage ?? null });
  }));

  // POST /api/game/meridian/refresh
  router.post("/meridian/refresh", op(async (req, res, userId) => {
    const state = await getOrCreateState(userId);
    const result = engine.generateMeridianRequirements(state);
    state.version += 1;
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: state.version, acupoints: result.acupoints, threshold_idx: state.meridian_threshold_idx });
  }));

  // POST /api/game/meridian/complete
  router.post("/meridian/complete", op(async (req, res, userId) => {
    const { index, item_ids } = req.body;
    if (typeof index !== "number" || !Array.isArray(item_ids)) {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.completeMeridianAcupoint(state, index, item_ids);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ...result, quest_progress: state.quest_progress });
  }));

  // POST /api/game/board/switch
  router.post("/board/switch", op(async (req, res, userId) => {
    const { board_type } = req.body;
    if (typeof board_type !== "string") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    // Clean up crafting state before switching (clear table states from grid)
    for (const item of state.grid) {
      delete (item as any)._craft_state;
      delete (item as any)._craft_stored;
      delete (item as any)._craft_recipe;
      delete (item as any)._craft_start_time;
      delete (item as any)._craft_duration;
      delete (item as any).storage;
    }
    const result = engine.switchBoard(state, board_type, req.body.map_id, req.body.stage);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    if (board_type === "battle") engine.initBattleMonsters(state);
    res.json({ ok: true, new_version: result.newVersion, board_type: board_type, grid: state.grid, monsters: state.battle_monsters, battle_map_id: state.battle_map_id, battle_stage: state.battle_stage });
  }));

  // POST /api/game/pouch/deposit
  router.post("/pouch/deposit", op(async (req, res, userId) => {
    const { uid } = req.body;
    if (typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.pouchDeposit(state, uid);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: state.version, pouch: result.pouch });
  }));

  // POST /api/game/pouch/withdraw
  router.post("/pouch/withdraw", op(async (req, res, userId) => {
    const { item_id, target_col, target_row } = req.body;
    if (typeof item_id !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.pouchWithdraw(state, item_id, target_col, target_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: state.version, pouch: result.pouch, target_col, target_row });
  }));

  // POST /api/battle/attack
  router.post("/battle/heal", op(async (req, res, userId) => {
    const { item_id, effect_id, uid } = req.body;
    if (typeof item_id !== "number" || typeof effect_id !== "number" || typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.battleHeal(state, item_id, uid, effect_id);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: result.newVersion, grid: result.grid });
  }));

  router.post("/battle/attack", op(async (req, res, userId) => {
    const { item_id, effect_id, col, row } = req.body;
    if (typeof item_id !== "number" || typeof effect_id !== "number" || typeof col !== "number" || typeof row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.battleAttack(state, item_id, effect_id, col, row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: state.version, grid: result.grid, monsters: result.monsters, stage_complete: result.stage_complete, loot: result.loot, battle_stage: state.battle_stage, quest_progress: state.quest_progress, rewards_applied: engine.questEngine.lastAppliedRewards, pending_rewards: state.pending_rewards });
  }));

  // POST /api/game/quest_claim
  router.post("/quest_claim", op(async (req, res, userId) => {
    const { quest_id } = req.body;
    if (typeof quest_id !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.questEngine.claimQuestReward(state, quest_id, engine);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, quest_id, rewards: result.rewards, cultivation: state.cultivation, spirit_stones: state.spirit_stones, stamina: state.stamina, grid: state.grid, pouch: state.pouch, quest_progress: state.quest_progress, rewards_applied: engine.questEngine.lastAppliedRewards, pending_rewards: state.pending_rewards });
  }));

  // POST /api/game/claim_pending_reward
  router.post("/claim_pending_reward", op(async (req, res, userId) => {
    const { uid } = req.body;
    if (typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.questEngine.claimPendingReward(state, uid, engine);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, col: result.col, row: result.row, grid: state.grid, pending_rewards: state.pending_rewards, new_version: state.version });
  }));

  // POST /api/game/home_meridian/light
  router.post("/home_meridian/light", op(async (req, res, userId) => {
    const { stage, index } = req.body;
    if (typeof stage !== "number" || typeof index !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.lightHomeAcupoint(state, stage, index);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json(result);
  }));

  // GET /api/leaderboard
  router.get("/leaderboard", async (_req: Request, res: Response) => {
    try {
      const limit = Math.min(parseInt(_req.query.limit as string) || 50, 100);
      const entries = await storage.getLeaderboard(limit);
      res.json({ entries });
    } catch (err) {
      console.error("[game] leaderboard error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  return router;
}
