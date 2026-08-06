import { Router, WorkerRequest as Request, WorkerResponse as Response } from "../worker/http";
import { IStorage } from "../storage/interface";
import { createAuthRequired } from "../middleware/auth";
import { GameEngine, TableState } from "../engine/game_engine";
import { enqueue } from "./queue";

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

export function createGameRouter(storage: IStorage, engine: GameEngine, jwtSecret: string): Router {
  const router = new Router();

  router.use(createAuthRequired(jwtSecret));

  async function getOrCreateState(userId: string) {
    let state = await storage.loadState(userId);
    if (!state) {
      state = engine.createInitialState();
      await storage.saveState(userId, state);
      console.log(`[game] new player ${userId}, init with ${state.grid.length} items | v0`);
    } else {
      let stateMigrated = false;
      if (!Number.isInteger(state.spawn_seed) || (state.spawn_seed ?? 0) <= 0) {
        state.spawn_seed = engine.createSpawnSeed();
        stateMigrated = true;
      }
      if (!Number.isInteger(state.spawn_sequence) || (state.spawn_sequence ?? 0) < 0) {
        state.spawn_sequence = 0;
        stateMigrated = true;
      }
      if (!Array.isArray(state.spawn_history)) {
        state.spawn_history = [];
        stateMigrated = true;
      }
      if (!Array.isArray(state.crafted_item_ids)) {
        state.crafted_item_ids = [];
        stateMigrated = true;
      }
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
      // Migrate: backfill uid in pouch items (old format: number[])
      if (state.pouch.length > 0 && typeof state.pouch[0] === "number") {
        const newPouch: any[] = [];
        for (const id of state.pouch as unknown as number[]) {
          state.uid_counter = (state.uid_counter ?? 0) + 1;
          newPouch.push({ uid: state.uid_counter, id });
        }
        state.pouch = newPouch as any;
      }
      // Migrate: backfill uid in craft_stored items (old format: {id} without uid)
      for (const item of state.grid) {
        if (item.craft?._craft_stored) {
          for (const s of item.craft._craft_stored) {
            if (!(s as any).uid) {
              state.uid_counter = (state.uid_counter ?? 0) + 1;
              (s as any).uid = state.uid_counter;
            }
          }
        }
        // Migrate: backfill uid in storage items (old format: {id} without uid)
        if (item.storage?.items) {
          for (const s of item.storage.items) {
            if (!(s as any).uid) {
              state.uid_counter = (state.uid_counter ?? 0) + 1;
              (s as any).uid = state.uid_counter;
            }
          }
        }
      }
      for (const item of state.grid) {
        if (!item.uid) {
          state.uid_counter = (state.uid_counter ?? 0) + 1;
          item.uid = state.uid_counter;
        }
      }
      // Backfill uids for saved grids too
      for (const grid of [state.saved_grid, state.battle_grid]) {
        if (grid) {
          for (const item of grid) {
            if (!item.uid) {
              state.uid_counter = (state.uid_counter ?? 0) + 1;
              item.uid = state.uid_counter;
            }
            if (item.craft?._craft_stored) {
              for (const s of item.craft._craft_stored) {
                if (!(s as any).uid) {
                  state.uid_counter = (state.uid_counter ?? 0) + 1;
                  (s as any).uid = state.uid_counter;
                }
              }
            }
            if (item.storage?.items) {
              for (const s of item.storage.items) {
                if (!(s as any).uid) {
                  state.uid_counter = (state.uid_counter ?? 0) + 1;
                  (s as any).uid = state.uid_counter;
                }
              }
            }
          }
        }
      }
      // Migrate: board_type string -> int (0=main, 1=battle)
      if (typeof state.board_type === "string") {
        state.board_type = state.board_type === "battle" ? 1 : 0;
      }
      // Migrate: convert old cultivation (current_realm_id + current_level) to flat current_level
      if (state.cultivation && typeof (state.cultivation as any).current_realm_id === "number") {
        const oldRealm = (state.cultivation as any).current_realm_id;
        const oldLv = state.cultivation.current_level;
        const realmOffsets = [0, 1, 10, 13, 16, 19, 22, 25, 28];
        const newLevel = (realmOffsets[oldRealm] ?? 0) + oldLv;
        console.log(`[game] migrating cultivation: realm=${oldRealm} lv=${oldLv} -> flat level=${newLevel}`);
        state.cultivation.current_level = newLevel;
        delete (state.cultivation as any).current_realm_id;      }

      // Re-initialize if grid is empty (stale save)
      if (!state.grid || state.grid.length === 0) {
        const bt = state.board_type ?? 0;
        state.grid = engine.createInitialState(bt).grid;
        await storage.saveState(userId, state);
        console.log(`[game] re-initialized empty grid for ${userId} (board_type=${bt}): ${state.grid.length} items`);
      }
            if (engine.tickCraftingState(state)) {
        await storage.saveState(userId, state);
      }
      engine.tickStamina(state);
      engine.tickLauncherRecharge(state);
      if (stateMigrated) {
        await storage.saveState(userId, state);
      }
    }
    return state;
  }

  function buildStateResponse(state: any, engine: GameEngine, regenRemainingMs: number) {
    const isBattle = state.board_type === 1;
    const mainGrid = isBattle ? (state.saved_grid?.length ? state.saved_grid : engine.createInitialState(0).grid) : state.grid;
    const battleGrid = isBattle ? state.grid : (state.battle_grid?.length ? state.battle_grid : []);
    console.log(`[game] buildStateResponse: board_type=${state.board_type} isBattle=${isBattle} saved_grid=${state.saved_grid?.length ?? 0} battle_grid_cache=${state.battle_grid?.length ?? 0} mainGrid=${mainGrid.length} battleGrid=${battleGrid.length} grid=${state.grid.length}`);
    return {
      grid: state.grid,
      main_grid: mainGrid,
      battle_grid: battleGrid,
      pouch: state.pouch,
      cultivation: state.cultivation,
      stamina: state.stamina,
      max_stamina: state.max_stamina,
      spirit_stones: state.spirit_stones,
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
      spawn_seed: state.spawn_seed,
      spawn_sequence: state.spawn_sequence,
      crafted_item_ids: state.crafted_item_ids,
      activity_current_day: (() => {
        const active = engine.activityEngine.getActivities().find((a: any) => engine.activityEngine.isActive(a) && engine.activityEngine.hasWeeklyTasks(a.id));
        return active ? engine.activityEngine.getCurrentDay(active.id, engine.questResetHour) : 0;
      })(),
      pending_rewards: state.pending_rewards, home_meridian_progress: state.home_meridian_progress
      };
  }

  // GET /api/game/state
  router.get("/state", async (req: Request, res: Response) => {
    try {
      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);
      // Restore main grid if returning from battle after reconnect, unless still on battle board
      if (state.board_type !== 1 && state.saved_grid && state.saved_grid.length > 0) {
        state.grid = state.saved_grid;
        state.saved_grid = undefined;        await storage.saveState(userId, state);
        console.log(`[game] restored main grid for ${userId}: ${state.grid.length} items`);
      }
      const regenRemainingMs = engine.getRegenRemainingMs(state);
      engine.enrichGridWithRechargeRemaining(state.grid);
      console.log(`[game] state response: grid=${state.grid.length} items, first uid=${state.grid[0]?.uid ?? "missing"}`);
      const questInitModified = engine.questEngine.initQuestProgress(state);
      const questResetOccurred = engine.questEngine.checkAndResetQuests(state, engine.questResetHour);
      engine.activityEngine.initProgress(state);
      engine.activityEngine.checkAndReset(state, engine.questResetHour);
      if (questInitModified || questResetOccurred) {
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
    const { from, to } = req.body;
    if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2) {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeMerge(state, from[0], from[1], to[0], to[1]);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, result_uid: result.resultUid, result_id: result.resultId, atk_base: result.atkBase ?? 0, from_col: result.fromCol, from_row: result.fromRow, to_col: result.toCol, to_row: result.toRow, regen_remaining_ms: engine.getRegenRemainingMs(state), quest_progress: state.quest_progress, crafted_item_ids: state.crafted_item_ids });
  }));

  // POST /api/game/actions/batch
  router.post("/actions/batch", op(async (req, res, userId) => {
    const { operations } = req.body;
    if (!Array.isArray(operations) || operations.length < 1 || operations.length > 32) {
      res.status(400).json({ error: "invalid_operations" }); return;
    }
    const state = await getOrCreateState(userId);
    const workingState = structuredClone(state);
    const results: any[] = [];

    for (let index = 0; index < operations.length; index++) {
      const operation = operations[index];
      const from = operation?.from;
      const to = operation?.to;
      if (!operation || !["move", "merge", "push_place"].includes(operation.type)
        || !Array.isArray(from) || from.length !== 2
        || !Array.isArray(to) || to.length !== 2
        || !from.every(Number.isInteger) || !to.every(Number.isInteger)) {
        res.status(400).json({ error: "invalid_operation", failed_index: index, grid: state.grid }); return;
      }

      if (operation.type === "move") {
        const result = engine.executeMove(workingState, from[0], from[1], to[0], to[1]);
        if (!result.ok) {
          res.status(409).json({ error: result.reason, failed_index: index, grid: state.grid }); return;
        }
        results.push({ type: "move", from, to, new_version: result.newVersion });
        continue;
      }

      if (operation.type === "push_place") {
        const result = engine.pushAndPlace(workingState, from[0], from[1], to[0], to[1]);
        if (!result.ok) {
          res.status(409).json({ error: result.reason, failed_index: index, grid: state.grid }); return;
        }
        results.push({
          type: "push_place",
          from,
          to,
          pushed_col: result.pushed_col,
          pushed_row: result.pushed_row,
          new_version: result.newVersion,
        });
        continue;
      }

      const result = engine.executeMerge(workingState, from[0], from[1], to[0], to[1]);
      if (!result.ok) {
        res.status(409).json({ error: result.reason, failed_index: index, grid: state.grid }); return;
      }
      results.push({
        type: "merge",
        from,
        to,
        result_uid: result.resultUid,
        result_id: result.resultId,
        atk_base: result.atkBase ?? 0,
        new_version: result.newVersion,
      });
    }

    await storage.saveState(userId, workingState);
    res.json({
      ok: true,
      results,
      grid: workingState.grid,
      stamina: workingState.stamina,
      cultivation: workingState.cultivation,
      regen_remaining_ms: engine.getRegenRemainingMs(workingState),
      quest_progress: workingState.quest_progress,
      crafted_item_ids: workingState.crafted_item_ids,
    });
  }));

  // POST /api/game/spawn
  router.post("/spawn", op(async (req, res, userId) => {
    const { launcher_pos, request_id, expected_sequence, predicted_id, predicted_target } = req.body;
    if (!Array.isArray(launcher_pos) || launcher_pos.length !== 2) {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    if (!engine.isInBounds(launcher_pos[0], launcher_pos[1])) {
      res.status(400).json({ error: "out_of_bounds" }); return;
    }
    if (request_id !== undefined && (typeof request_id !== "string" || !/^[A-Za-z0-9._:-]{1,96}$/.test(request_id))) {
      res.status(400).json({ error: "invalid_request_id" }); return;
    }
    if (expected_sequence !== undefined && (!Number.isInteger(expected_sequence) || expected_sequence < 0)) {
      res.status(400).json({ error: "invalid_spawn_sequence" }); return;
    }
    const state = await getOrCreateState(userId);
    const cached = request_id ? state.spawn_history?.find(entry => entry.request_id === request_id) : undefined;
    const result: any = cached?.result ?? engine.executeSpawn(state, launcher_pos[0], launcher_pos[1], expected_sequence);
    if (!result.ok) {
      res.status(result.reason === "spawn_sequence_mismatch" ? 409 : 400).json({
        error: result.reason,
        request_id,
        spawn_seed: state.spawn_seed,
        spawn_sequence: state.spawn_sequence,
      });
      return;
    }
    if (!cached && request_id) {
      state.spawn_history = state.spawn_history ?? [];
      state.spawn_history.push({ request_id, result: { ...result } });
      if (state.spawn_history.length > 32) state.spawn_history.splice(0, state.spawn_history.length - 32);
    }
    const hasPrediction = Number.isInteger(predicted_id)
      && Array.isArray(predicted_target)
      && predicted_target.length === 2;
    const predictionMatches = !hasPrediction || (
      predicted_id === result.spawnedId
      && predicted_target[0] === result.targetCol
      && predicted_target[1] === result.targetRow
    );
    await storage.saveState(userId, state);
    res.json({
      ok: true,
      request_id,
      replayed: Boolean(cached),
      prediction_matches: predictionMatches,
      spawned_uid: result.spawnedUid,
      spawned_id: result.spawnedId,
      spawned_name: result.spawnedName,
      target_col: result.targetCol,
      target_row: result.targetRow,
      stamina: state.stamina,
      max_stamina: state.max_stamina,
      charges: result.charges,
      max_charges: result.maxCharges,
      recharge_time: result.rechargeTime,
      atk_base: result.atkBase,
      cultivation: state.cultivation,
      regen_remaining_ms: engine.getRegenRemainingMs(state),
      quest_progress: state.quest_progress,
      spawn_seed: state.spawn_seed,
      spawn_sequence: state.spawn_sequence,
      sequence_used: result.sequenceUsed,
      ...(predictionMatches ? {} : { grid: state.grid }),
    });
  }));

  // POST /api/game/craft/add
  router.post("/craft/add", op(async (req, res, userId) => {
    const { table_col, table_row, ingredient_id, from_col, from_row } = req.body;
    if (typeof table_col !== "number" || typeof table_row !== "number" || typeof ingredient_id !== "number" || typeof from_col !== "number" || typeof from_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.addIngredientToTable(state, table_col, table_row, ingredient_id, from_col, from_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, matched: result.matched });
  }));

  // POST /api/game/craft/start
  router.post("/craft/start", op(async (req, res, userId) => {
    const { table_col, table_row } = req.body;
    if (typeof table_col !== "number" || typeof table_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeCraftStart(state, table_col, table_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, recipe_id: result.recipe.id, craft_time: result.recipe.craft_time });
  }));

  // POST /api/game/craft/retrieve
  router.post("/craft/retrieve", op(async (req, res, userId) => {
    const { table_col, table_row } = req.body;
    if (typeof table_col !== "number" || typeof table_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeCraftRetrieve(state, table_col, table_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, result_uid: result.resultUid, result_id: result.resultId, quest_progress: state.quest_progress });
  }));


  // POST /api/game/craft/remove
  router.post("/craft/remove", op(async (req, res, userId) => {
    const { table_col, table_row, uid, target_col, target_row } = req.body;
    if (typeof table_col !== "number" || typeof table_row !== "number" || typeof uid !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.removeIngredientFromTable(state, table_col, table_row, uid, target_col, target_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    engine.enrichGridWithRechargeRemaining(state.grid);
    res.json({ ok: true, removed_id: result.removed_id, removed_uid: result.removed_uid, table_col: result.table_col, table_row: result.table_row, target_col: result.target_col, target_row: result.target_row, grid: state.grid });
  }));

  // POST /api/game/push_place
  router.post("/push_place", op(async (req, res, userId) => {
    const { from, to } = req.body;
    if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2) {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    console.log(`[game] push_place: from=(${from[0]},${from[1]}) to=(${to[0]},${to[1]})`);
    const result = engine.pushAndPlace(state, from[0], from[1], to[0], to[1]);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, pushed_col: result.pushed_col, pushed_row: result.pushed_row, from_col: result.from_col, from_row: result.from_row, to_col: result.to_col, to_row: result.to_row });
  }));

  // POST /api/game/move
  router.post("/move", op(async (req, res, userId) => {
    const { from, to } = req.body;
    if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2) {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeMove(state, from[0], from[1], to[0], to[1]);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, grid: state.grid });
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
        price: s.price
      }));
      res.json({ items });
    } catch (err) {
      console.error("[game] shop items error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/storage/deposit
  router.post("/storage/deposit", op(async (req, res, userId) => {
    const { storage_col, storage_row, uid, from_col, from_row } = req.body;
    if (typeof storage_col !== "number" || typeof storage_row !== "number" || typeof uid !== "number" || typeof from_col !== "number" || typeof from_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.depositItem(state, storage_col, storage_row, uid, from_col, from_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    engine.enrichGridWithRechargeRemaining(state.grid);
    res.json({ ok: true, grid: state.grid });
  }));

  // POST /api/game/storage/withdraw
  router.post("/storage/withdraw", op(async (req, res, userId) => {
    const { storage_col, storage_row, uid, target_col, target_row } = req.body;
    if (typeof storage_col !== "number" || typeof storage_row !== "number" || typeof uid !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.withdrawItem(state, storage_col, storage_row, uid, target_col, target_row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    const storageItem = state.grid.find(i => i.col === storage_col && i.row === storage_row);
    engine.enrichGridWithRechargeRemaining(state.grid);
    res.json({ ok: true, storage: storageItem?.storage ?? null, uid: result.uid, col: result.col, row: result.row });
  }));

  // POST /api/game/meridian/refresh
  router.post("/meridian/refresh", op(async (req, res, userId) => {
    const state = await getOrCreateState(userId);
    const result = engine.generateMeridianRequirements(state);    await storage.saveState(userId, state);
    res.json({ ok: true, acupoints: result.acupoints, threshold_idx: state.meridian_threshold_idx });
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
    if (typeof board_type !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.switchBoard(state, board_type, req.body.map_id, req.body.stage);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    if (board_type === 1) engine.initBattleMonsters(state);
    engine.enrichGridWithRechargeRemaining(state.grid);
    res.json({ ok: true, board_type: board_type, grid: state.grid, monsters: state.battle_monsters, battle_map_id: state.battle_map_id, battle_stage: state.battle_stage });
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
    res.json({ ok: true, pouch: result.pouch });
  }));

  // POST /api/game/pouch/withdraw
  router.post("/pouch/withdraw", op(async (req, res, userId) => {
    const { uid } = req.body;
    if (typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const pouchEntry = state.pouch.find((p: any) => p.uid === uid);
    if (!pouchEntry) { res.status(400).json({ error: "item_not_in_pouch" }); return; }
    const empty = engine.findEmptyPos(state.grid);
    if (!empty) { res.status(400).json({ error: "grid_full" }); return; }
    const result = engine.pouchWithdraw(state, pouchEntry.id, empty.col, empty.row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, pouch: result.pouch, col: result.col, row: result.row });
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
    res.json({ ok: true, grid: result.grid });
  }));

  router.post("/battle/attack", op(async (req, res, userId) => {
    const { item_id, effect_id, uid, col, row } = req.body;
    if (typeof item_id !== "number" || typeof effect_id !== "number" || typeof uid !== "number" || typeof col !== "number" || typeof row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.battleAttack(state, item_id, effect_id, uid, col, row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, grid: result.grid, monsters: result.monsters, stage_complete: result.stage_complete, loot: result.loot, battle_stage: state.battle_stage, quest_progress: state.quest_progress, cultivation: state.cultivation, spirit_stones: state.spirit_stones, stamina: state.stamina, pending_rewards: state.pending_rewards });
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
    engine.enrichGridWithRechargeRemaining(state.grid);
    res.json({ ok: true, quest_id, rewards: result.rewards, cultivation: state.cultivation, spirit_stones: state.spirit_stones, stamina: state.stamina, grid: state.grid, pouch: state.pouch, quest_progress: state.quest_progress, pending_rewards: state.pending_rewards });
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
    engine.enrichGridWithRechargeRemaining(state.grid);
    res.json({ ok: true, col: result.col, row: result.row, grid: state.grid, pending_rewards: state.pending_rewards, });
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
