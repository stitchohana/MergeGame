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
      // Offline cultivation tick — applies EXP for elapsed time since last_tick_time
      const oldVer = state.version;
      engine.tickCultivation(state);
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
      res.json({ score: state.score, high_score: state.high_score, grid: state.grid, cultivation: state.cultivation, stamina: state.stamina, max_stamina: state.max_stamina, version: state.version });
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
    res.json({ ok: true, new_score: result.newScore, new_version: result.newVersion, result_id: result.resultId });
  }));

  // POST /api/game/spawn
  router.post("/spawn", op(async (req, res, userId) => {
    const { launcher_pos, rolled_id } = req.body;
    if (!Array.isArray(launcher_pos) || launcher_pos.length !== 2 || typeof rolled_id !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    if (!engine.isInBounds(launcher_pos[0], launcher_pos[1])) {
      res.status(400).json({ error: "out_of_bounds" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeSpawn(state, launcher_pos[0], launcher_pos[1], rolled_id);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, spawned_id: result.spawnedId, target_col: result.targetCol, target_row: result.targetRow, new_version: result.newVersion, stamina: state.stamina, max_stamina: state.max_stamina, charges: result.charges, max_charges: result.maxCharges });
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
    res.json({ ok: true, result_id: result.resultId, new_version: result.newVersion, grid: state.grid });
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
    res.json({ ok: true, new_version: result.newVersion });
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
    res.json({ ok: true, new_version: result.newVersion });
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
