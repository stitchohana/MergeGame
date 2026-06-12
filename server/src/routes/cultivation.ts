import { Router, Request, Response } from "express";
import { IStorage } from "../storage/interface";
import { authRequired } from "../middleware/auth";
import { GameEngine } from "../engine/game_engine";

export function createCultivationRouter(storage: IStorage, engine: GameEngine): Router {
  const router = Router();
  router.use(authRequired);

  async function getOrCreateState(userId: string) {
    let state = await storage.loadState(userId);
    if (!state) {
      state = engine.createInitialState();
      await storage.saveState(userId, state);
      console.log(`[cult] new player ${userId}, init with ${state.grid.length} items`);
    } else {
      if (engine.tickCraftingState(state)) {
        await storage.saveState(userId, state);
      }
    }
    return state;
  }

  // POST /api/cultivation/tick
  router.post("/tick", async (req: Request, res: Response) => {
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

      res.json({ ok: true, new_version: state.version, cultivation: state.cultivation });
    } catch (err) {
      console.error("[cult] tick error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/cultivation/consume
  router.post("/consume", async (req: Request, res: Response) => {
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
      res.json({ ok: true, new_version: state.version, cultivation: state.cultivation });
    } catch (err) {
      console.error("[cult] consume error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  // POST /api/cultivation/breakthrough
  router.post("/breakthrough", async (req: Request, res: Response) => {
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
        state, pill_id,
        state.cultivation.current_realm_id,
        state.cultivation.current_level,
        state.cultivation.current_exp
      );

      if (!result.ok) {
        res.status(400).json({ error: result.reason });
        return;
      }

      await storage.saveState(userId, state);
      res.json({ ok: true, new_version: state.version, cultivation: state.cultivation });
    } catch (err) {
      console.error("[cult] breakthrough error:", err);
      res.status(500).json({ error: "internal_error" });
    }
  });

  return router;
}
