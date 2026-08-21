import { Router, WorkerRequest as Request, WorkerResponse as Response } from "../worker/http";
import { GameState, IStorage } from "../storage/interface";
import { GameEngine } from "../engine/game_engine";
import { createAuthRequired } from "../middleware/auth";
import { enqueue } from "./queue";

export function grantCurrentOrderItems(state: GameState, engine: GameEngine): { grantedCount: number; itemCounts: Record<string, number> } {
  state.pending_rewards = state.pending_rewards || [];
  const itemCounts: Record<string, number> = {};
  let grantedCount = 0;

  for (const order of state.meridian_acupoints || []) {
    if ((order as any)?.completed === true || !Array.isArray((order as any)?.item_ids)) continue;
    for (const rawItemId of (order as any).item_ids) {
      const itemId = Number(rawItemId);
      if (!Number.isInteger(itemId)) continue;
      const itemDef = engine.getItemData(itemId);
      if (!itemDef) continue;
      state.pending_rewards.push({
        uid: engine._nextUid(state),
        id: itemId,
        name: itemDef.name ?? `#${itemId}`,
      });
      itemCounts[String(itemId)] = (itemCounts[String(itemId)] || 0) + 1;
      grantedCount += 1;
    }
  }

  return { grantedCount, itemCounts };
}

export function createGMRouter(storage: IStorage, engine: GameEngine, jwtSecret: string, gmKey: string): Router {
  const router = new Router();

  // If GM_KEY is not configured, disable the GM endpoint entirely
  if (!gmKey) {
    console.log("[gm] GM_KEY not set — GM endpoints disabled");
    router.use(createAuthRequired(jwtSecret));
    router.post("/exec", (_req: Request, res: Response) => {
      res.status(404).json({ error: "not_found" });
    });
    return router;
  }

  router.use(createAuthRequired(jwtSecret));

  // POST /api/gm/exec
  router.post("/exec", async (req: Request, res: Response) => {
    try {
      if (req.body.gm_key !== gmKey) {
        res.status(403).json({ error: "forbidden" });
        return;
      }

      const userId = req.auth!.userId;
      const { cmd, amount, item_id, col, row } = req.body;

      // Use shared queue to prevent race conditions with game ops
      await enqueue(userId, async () => {
        const state = await storage.loadState(userId);
        if (!state) { res.status(404).json({ error: "user_not_found" }); return; }

        engine.tickStamina(state);
        engine.tickLauncherRecharge(state);

        let msg = "ok";
        let gmResult: Record<string, unknown> = {};

        switch (cmd) {
          case "add_exp": {
            const amt = parseInt(amount, 10);
            if (isNaN(amt) || amt <= 0) { res.status(400).json({ error: "invalid_amount" }); return; }
            engine._addExp(state.cultivation, amt);
            msg = `Added ${amt} exp, now level=${state.cultivation.current_level} exp=${state.cultivation.current_exp}`;
            break;
          }
          case "add_stones": {
            const amt = parseInt(amount, 10);
            if (isNaN(amt)) { res.status(400).json({ error: "invalid_amount" }); return; }
            state.spirit_stones += amt;
            msg = `Stones now: ${state.spirit_stones}`;
            break;
          }
          case "set_stamina": {
            const amt = parseInt(amount, 10);
            if (isNaN(amt) || amt < 0) { res.status(400).json({ error: "invalid_amount" }); return; }
            state.stamina = Math.min(amt, engine.staminaConfig.max);
            msg = `Stamina set to ${state.stamina}`;
            break;
          }
          case "set_qi": {
            const amt = parseInt(amount, 10);
            if (isNaN(amt) || amt < 0) { res.status(400).json({ error: "invalid_amount" }); return; }
            state.cultivation.current_qi = Math.min(amt, state.cultivation.max_qi);
            msg = `Qi set to ${state.cultivation.current_qi}/${state.cultivation.max_qi}`;
            break;
          }
          case "levelup": {
            const c = state.cultivation;
            const maxLevel = engine.cultivationStages.length;
            if (c.current_level >= maxLevel) { res.status(400).json({ error: "already_max" }); return; }
            c.current_level += 1;
            const s = engine.cultivationStages[c.current_level - 1];
            c.max_qi = s?.max_qi ?? c.max_qi;
            c.current_qi = c.max_qi;
            c.current_exp = 0;
            msg = `Level up: ${engine.cultivationStages[c.current_level - 1]?.name}`;
            break;
          }
          case "breakthrough": {
            const c = state.cultivation;
            const maxLevel = engine.cultivationStages.length;
            if (c.current_level >= maxLevel) { res.status(400).json({ error: "already_max" }); return; }
            c.current_level += 1;
            const s = engine.cultivationStages[c.current_level - 1];
            c.max_qi = s?.max_qi ?? c.max_qi;
            c.current_qi = c.max_qi;
            c.current_exp = 0;
            msg = `Breakthrough: ${s?.name}`;
            break;
          }
          case "add_item": {
            const iid = parseInt(item_id, 10);
            if (isNaN(iid)) { res.status(400).json({ error: "invalid_item_id" }); return; }
            const itemDef = engine.getItemData(iid);
            if (!itemDef) { res.status(400).json({ error: "item_not_found" }); return; }
            let emptyCol = -1, emptyRow = -1;
            for (let r = 0; r < engine.GRID_ROWS && emptyCol < 0; r++) {
              for (let c = 0; c < engine.GRID_COLS && emptyCol < 0; c++) {
                if (!state.grid.some(g => g.col === c && g.row === r)) {
                  emptyCol = c; emptyRow = r;
                }
              }
            }
            if (emptyCol < 0) { res.status(400).json({ error: "grid_full" }); return; }
            const uid = engine._nextUid(state);
            const gitem: any = { uid, id: iid, col: emptyCol, row: emptyRow };
            if (engine.isLauncher(itemDef)) {
              gitem.charges = engine.getMaxCharges(iid);
              gitem.last_charge_time = Date.now();
            }
            state.grid.push(gitem);
            msg = `Added #${iid} at (${emptyCol},${emptyRow}) uid=${uid}`;
            break;
          }
          case "reset_launcher_cd": {
            const now = Date.now();
            for (const item of state.grid) {
              const def = engine.getItemData(item.id);
              if (def?.type === 1) {
                item.charges = engine.getMaxCharges(item.id);
                item.last_charge_time = now;
              }
            }
            msg = "All launcher cooldowns reset";
            break;
          }
          case "clear_grid": {
            state.grid = [];
            msg = "Grid cleared";
            break;
          }
          case "activate_home_acupoints": {
            const amt = parseInt(amount, 10);
            if (isNaN(amt) || amt <= 0) { res.status(400).json({ error: "invalid_amount" }); return; }
            const result = engine.gmActivateHomeAcupoints(state, amt);
            msg = `Activated ${result.activated} home acupoints, completed ${result.completed_stages} stages`;
            break;
          }
          case "grant_order_items": {
            const result = grantCurrentOrderItems(state, engine);
            if (result.grantedCount === 0) { res.status(400).json({ error: "no_order_items" }); return; }
            gmResult = { granted_count: result.grantedCount, granted_items: result.itemCounts };
            msg = `Granted ${result.grantedCount} current order items to pending rewards`;
            break;
          }
          default:
            res.status(400).json({ error: "unknown_cmd", cmds: ["add_exp","add_stones","set_stamina","set_qi","levelup","breakthrough","add_item","reset_launcher_cd","clear_grid","activate_home_acupoints","grant_order_items"] });
            return;
        }

        await storage.saveState(userId, state);
        console.log(`[gm] ${userId}: ${cmd} — ${msg}`);
        res.json({ ok: true, msg, ...gmResult });
      });
    } catch (e: any) {
      console.error("[gm] error:", e);
      if (!res.headersSent) res.status(500).json({ error: "internal_error" });
    }
  });

  return router;
}
