import { Router, Request, Response } from "express";
import { IStorage } from "../storage/interface";
import { authRequired } from "../middleware/auth";
import { GameEngine, TableState } from "../engine/game_engine";

export function createGameRouter(storage: IStorage, engine: GameEngine): Router {
  const router = Router();

  // All game routes require auth
  router.use(authRequired);

  async function getOrCreateState(userId: string) {
    let state = await storage.loadState(userId);
    if (!state) {
      state = engine.createInitialState();
      await storage.saveState(userId, state);
      console.log(`[game] new player ${userId}, init with ${state.grid.length} items | v0`);
    }
    return state;
  }

  // GET /api/game/state — fetch current game state
  router.get("/state", async (req: Request, res: Response) => {
    try {
      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      res.json({
        score: state.score,
        high_score: state.high_score,
        grid: state.grid,
        cultivation: state.cultivation,
        version: state.version,
      });
    } catch (err) {
      console.error("[game] state error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/merge — execute a merge
  router.post("/merge", async (req: Request, res: Response) => {
    try {
      const { from, to, version } = req.body;

      if (
        !Array.isArray(from) || from.length !== 2 ||
        !Array.isArray(to) || to.length !== 2 ||
        typeof version !== "number"
      ) {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const [fromCol, fromRow] = from;
      const [toCol, toRow] = to;

      // Allow out-of-bounds positions — engine will fall back to searching by item ID
      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        console.log(`[game] merge: version conflict client=${version} server=${state.version}`);
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      const result = engine.executeMerge(state, fromCol, fromRow, toCol, toRow);

      if (!result.ok) {
        console.log(`[game] merge: rejected (${result.reason})`);
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);
      console.log(`[game] merge: ok, grid=${state.grid.length} items, saved`);

      res.json({
        ok: true,
        new_score: result.newScore,
        new_version: result.newVersion,
        result_id: result.resultId,
        grid: state.grid,
      });
    } catch (err) {
      console.error("[game] merge error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/spawn — launch an item from a launcher
  router.post("/spawn", async (req: Request, res: Response) => {
    try {
      const { launcher_pos, version } = req.body;

      if (
        !Array.isArray(launcher_pos) || launcher_pos.length !== 2 ||
        typeof version !== "number"
      ) {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const [launcherCol, launcherRow] = launcher_pos;

      if (!GameEngine.isInBounds(launcherCol, launcherRow)) {
        res.status(400).json({ error: "out_of_bounds" });
        return;
      }

      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        console.log(`[game] spawn: version conflict client=${version} server=${state.version}`);
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      const result = engine.executeSpawn(state, launcherCol, launcherRow);

      if (!result.ok) {
        console.log(`[game] spawn: rejected (${result.reason})`);
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);
      console.log(`[game] spawn: ok, saved`);

      res.json({
        ok: true,
        spawned_id: result.spawnedId,
        target_col: result.targetCol,
        target_row: result.targetRow,
        new_version: result.newVersion,
        grid: state.grid,
      });
    } catch (err) {
      console.error("[game] spawn error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/craft/add — add ingredient to crafting table
  router.post("/craft/add", async (req: Request, res: Response) => {
    try {
      const { table_col, table_row, ingredient_id, version } = req.body;

      if (
        typeof table_col !== "number" || typeof table_row !== "number" ||
        typeof ingredient_id !== "number" || typeof version !== "number"
      ) {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        console.log(`[game] craft/add: version conflict client=${version} server=${state.version}`);
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      const result = engine.addIngredientToTable(state, table_col, table_row, ingredient_id);

      if (!result.ok) {
        console.log(`[game] craft/add: rejected (${result.reason})`);
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);
      console.log(`[game] craft/add: ok, matched=${result.matched}, saved`);

      res.json({
        ok: true,
        matched: result.matched,
        new_version: result.newVersion,
      });
    } catch (err) {
      console.error("[game] craft/add error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/craft/start — start crafting
  router.post("/craft/start", async (req: Request, res: Response) => {
    try {
      const { table_col, table_row, version } = req.body;

      if (
        typeof table_col !== "number" || typeof table_row !== "number" ||
        typeof version !== "number"
      ) {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        console.log(`[game] craft/start: version conflict`);
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      const result = engine.executeCraftStart(state, table_col, table_row);

      if (!result.ok) {
        console.log(`[game] craft/start: rejected (${result.reason})`);
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);
      console.log(`[game] craft/start: ok, saved`);

      res.json({
        ok: true,
        new_version: result.newVersion,
        recipe_id: result.recipe.id,
        craft_time: result.recipe.craft_time,
      });
    } catch (err) {
      console.error("[game] craft/start error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/craft/retrieve — retrieve crafting result
  router.post("/craft/retrieve", async (req: Request, res: Response) => {
    try {
      const { table_col, table_row, version } = req.body;

      if (
        typeof table_col !== "number" || typeof table_row !== "number" ||
        typeof version !== "number"
      ) {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        console.log(`[game] craft/retrieve: version conflict`);
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      const result = engine.executeCraftRetrieve(state, table_col, table_row);

      if (!result.ok) {
        console.log(`[game] craft/retrieve: rejected (${result.reason})`);
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);
      console.log(`[game] craft/retrieve: ok, saved`);

      res.json({
        ok: true,
        result_id: result.resultId,
        new_version: result.newVersion,
      });
    } catch (err) {
      console.error("[game] craft/retrieve error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/cultivate/tick — advance cultivation timer
  router.post("/cultivate/tick", async (req: Request, res: Response) => {
    try {
      const { version } = req.body;

      if (typeof version !== "number") {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      engine.tickCultivation(state);
      await storage.saveState(userId, state);

      res.json({
        ok: true,
        new_version: state.version,
        cultivation: state.cultivation,
      });
    } catch (err) {
      console.error("[game] cultivate/tick error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/cultivate/consume — consume a cultivation pill
  router.post("/cultivate/consume", async (req: Request, res: Response) => {
    try {
      const { pill_id, version } = req.body;

      if (typeof pill_id !== "number" || typeof version !== "number") {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      const result = engine.consumePill(state, pill_id);

      if (!result.ok) {
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);

      res.json({
        ok: true,
        new_version: state.version,
        cultivation: state.cultivation,
      });
    } catch (err) {
      console.error("[game] cultivate/consume error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/cultivate/breakthrough — attempt breakthrough
  router.post("/cultivate/breakthrough", async (req: Request, res: Response) => {
    try {
      const { pill_id, version } = req.body;

      if (typeof pill_id !== "number" || typeof version !== "number") {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      const result = engine.executeTryBreakthrough(
        state,
        pill_id,
        state.cultivation.current_realm_id,
        state.cultivation.current_level,
        state.cultivation.current_exp
      );

      if (!result.ok) {
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);

      res.json({
        ok: true,
        new_version: state.version,
        cultivation: state.cultivation,
      });
    } catch (err) {
      console.error("[game] cultivate/breakthrough error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/game/move — move an item to an empty cell
  router.post("/move", async (req: Request, res: Response) => {
    try {
      const { from, to, version } = req.body;

      if (
        !Array.isArray(from) || from.length !== 2 ||
        !Array.isArray(to) || to.length !== 2 ||
        typeof version !== "number"
      ) {
        res.status(400).json({ error: "invalid_params" });
        return;
      }

      const [fromCol, fromRow] = from;
      const [toCol, toRow] = to;

      const userId = req.auth!.userId;
      const state = await getOrCreateState(userId);

      if (state.version !== version) {
        console.log(`[game] move: version conflict client=${version} server=${state.version}`);
        res.status(409).json({ error: "version_mismatch", server_version: state.version });
        return;
      }

      const result = engine.executeMove(state, fromCol, fromRow, toCol, toRow);

      if (!result.ok) {
        console.log(`[game] move: rejected (${result.reason})`);
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);
      console.log(`[game] move: (${fromCol},${fromRow}) -> (${toCol},${toRow}) ok, saved`);

      res.json({
        ok: true,
        new_version: result.newVersion,
      });
    } catch (err) {
      console.error("[game] move error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // GET /api/leaderboard
  router.get("/leaderboard", async (_req: Request, res: Response) => {
    try {
      const limit = Math.min(
        parseInt(_req.query.limit as string) || 50,
        100
      );
      const entries = await storage.getLeaderboard(limit);
      res.json({ entries });
    } catch (err) {
      console.error("[game] leaderboard error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  return router;
}
