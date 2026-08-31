import { Router, WorkerRequest as Request, WorkerResponse as Response } from "../worker/http";
import { IStorage } from "../storage/interface";
import { createAuthRequired } from "../middleware/auth";
import { GameEngine } from "../engine/game_engine";
import { enqueue } from "./queue";


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

export function createCultivationRouter(storage: IStorage, engine: GameEngine, jwtSecret: string): Router {
  const router = new Router();
  router.use(createAuthRequired(jwtSecret));

  async function getOrCreateState(userId: string) {
    let state = await storage.loadState(userId);
    if (!state) {
      state = engine.createInitialState();
      await storage.saveState(userId, state);
      console.log(`[cult] new player ${userId}, init with ${state.grid.length} items`);
    } else {
      engine.tickStamina(state);
      engine.tickLauncherRecharge(state);
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
    res.json({
      ok: true,
      cultivation: state.cultivation,
      quest_progress: state.quest_progress,
      meridian_acupoints: state.meridian_acupoints || [],
    });
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
    res.json({ ok: true, stamina: result.stamina, max_stamina: result.max_stamina, quest_progress: state.quest_progress });
  }));

  // POST /api/cultivation/consume-spirit-stone
  router.post("/consume-spirit-stone", op(async (req, res, userId) => {
    const { item_id, uid } = req.body;
    if (typeof item_id !== "number" || typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.consumeSpiritStoneItem(state, item_id, uid);
    if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
    await storage.saveState(userId, state);
    res.json({
      ok: true,
      amount: result.amount,
      spirit_stones: result.spiritStones,
      quest_progress: state.quest_progress,
    });
  }));

  // POST /api/cultivation/breakthrough
  router.post("/breakthrough", op(async (req, res, userId) => {
    const { uid } = req.body;
    if (typeof uid !== "number") {
      res.status(400).json({ error: "invalid_params" }); return;
    }
    const state = await getOrCreateState(userId);
    const result = engine.executeTryBreakthrough(
      state, uid,
      state.cultivation.current_level,
      state.cultivation.current_exp
    );
    if (!result.ok) {
      res.status(400).json({ error: result.reason, missing: result.missing ?? [] }); return;
    }
    await storage.saveState(userId, state);
    res.json({
      ok: true,
      grid: state.grid,
      pouch: state.pouch,
      cultivation: state.cultivation,
      rewards: result.rewards,
      spirit_stones: state.spirit_stones,
      stamina: state.stamina,
      pending_rewards: state.pending_rewards,
      quest_progress: state.quest_progress,
      meridian_acupoints: state.meridian_acupoints || [],
    });
  }));

  return router;
}
