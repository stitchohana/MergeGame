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
    }
    return state;
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
      res.json({ grid: state.grid, cultivation: state.cultivation, stamina: state.stamina, max_stamina: state.max_stamina, spirit_stones: state.spirit_stones, version: state.version, meridian_acupoints: state.meridian_acupoints, meridian_circulations: state.meridian_circulations, meridian_threshold_idx: state.meridian_threshold_idx });
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
    res.json({ ok: true, new_version: result.newVersion, result_id: result.resultId, from_col: result.fromCol, from_row: result.fromRow, to_col: result.toCol, to_row: result.toRow });
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
    res.json({ ok: true, spawned_id: result.spawnedId, spawned_name: result.spawnedName, target_col: result.targetCol, target_row: result.targetRow, new_version: result.newVersion, stamina: state.stamina, max_stamina: state.max_stamina, charges: result.charges, max_charges: result.maxCharges });
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
    res.json({ ok: true, result_id: result.resultId, new_version: result.newVersion });
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
    const { col, row } = req.body;
    if (typeof col !== "number" || typeof row !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.sellItem(state, col, row);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, spirit_stones: result.stones });
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
    res.json({ ok: true, spirit_stones: result.stones });
  }));

  // GET /api/game/shop/items
  router.get("/shop/items", async (req: Request, res: Response) => {
    try {
      const items = engine.getShopItems().map(id => ({
        id,
        name: engine.getItemData(id)?.name ?? ("#" + id),
        price: engine.getBuyPrice(id),
      })).filter(i => i.price > 0);
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
    res.json({ ok: true, new_version: state.version, acupoints: result.acupoints, threshold_idx: state.meridian_threshold_idx, complete_exp: result.complete_exp });
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
    res.json(result);
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
    const result = engine.switchBoard(state, board_type);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: result.newVersion, grid: state.grid });
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
