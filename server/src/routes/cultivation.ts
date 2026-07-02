import { Router, Request, Response } from "express";
import { IStorage } from "../storage/interface";
import { authRequired } from "../middleware/auth";
import { GameEngine } from "../engine/game_engine";

// Per-user operation queue — sequential execution per user
const userQueues = new Map<string, Promise<void>>();

function enqueue(userId: string, fn: () => Promise<void>): Promise<void> {
  const prev = userQueues.get(userId) ?? Promise.resolve();
  const next = prev.then(fn, fn);
  userQueues.set(userId, next);
  return next;
}

function op(handler: (req: Request, res: Response, userId: string) => Promise<void>) {
  return async (req: Request, res: Response): Promise<void> => {
    try {
      const userId = req.auth!.userId;
      await enqueue(userId, () => handler(req, res, userId));
    } catch (err) {
      console.error("[cult] op error:", err);
      if (!res.headersSent) res.status(500).json({ error: "internal_error" });
    }
  };
}

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


  // POST /api/cultivation/consume-exp
  router.post("/consume-exp", op(async (req, res, userId) => {
    const { pill_id, uid } = req.body;
    if (typeof pill_id !== "number" || typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.consumeExpPill(state, pill_id, uid);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: state.version, cultivation: state.cultivation });
  }));

  // POST /api/cultivation/consume-stamina
  router.post("/consume-stamina", op(async (req, res, userId) => {
    const { pill_id, uid } = req.body;
    if (typeof pill_id !== "number" || typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.consumeStaminaPill(state, pill_id, uid);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: state.version, stamina: result.stamina, max_stamina: result.max_stamina });
  }));

  // POST /api/cultivation/breakthrough
  router.post("/breakthrough", op(async (req, res, userId) => {
    const { pill_id, uid } = req.body;
    if (typeof pill_id !== "number" || typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeTryBreakthrough(
      state, pill_id, uid,
      state.cultivation.current_level,
      state.cultivation.current_exp
    );
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({ ok: true, new_version: state.version, cultivation: state.cultivation });
  }));

  return router;
}
