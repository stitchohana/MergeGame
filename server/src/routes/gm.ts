import { Router, WorkerRequest as Request, WorkerResponse as Response } from "../worker/http";
import { GameState, IStorage } from "../storage/interface";
import { GameEngine, TableState } from "../engine/game_engine";
import { createAuthRequired } from "../middleware/auth";
import { enqueue } from "./queue";

export type GrantCurrentOrderItemsResult = {
  grantedCount: number;
  itemCounts: Record<string, number>;
  mainGrid: GameState["grid"];
  error?: "no_order_items" | "grid_full";
  requiredCount?: number;
  availableSlots?: number;
};

export type RefreshAllOrdersResult = {
  acupoints: any[];
  refreshedCount: number;
  preservedBreakthrough: boolean;
  fixedOrdersPreserved: boolean;
};

export function grantCurrentOrderItems(state: GameState, engine: GameEngine): GrantCurrentOrderItemsResult {
  const itemCounts: Record<string, number> = {};
  const orderItems: Array<{ id: number; name: string }> = [];

  for (const order of state.meridian_acupoints || []) {
    if ((order as any)?.completed === true || !Array.isArray((order as any)?.item_ids)) continue;
    for (const rawItemId of (order as any).item_ids) {
      const itemId = Number(rawItemId);
      if (!Number.isInteger(itemId)) continue;
      const itemDef = engine.getItemData(itemId);
      if (!itemDef) continue;
      orderItems.push({ id: itemId, name: itemDef.name ?? `#${itemId}` });
      itemCounts[String(itemId)] = (itemCounts[String(itemId)] || 0) + 1;
    }
  }

  const mainGrid = state.board_type === 1 && Array.isArray(state.saved_grid)
    ? state.saved_grid
    : state.grid;
  if (orderItems.length === 0) {
    return { grantedCount: 0, itemCounts, mainGrid, error: "no_order_items" };
  }

  // Place the whole batch atomically. A failed GM request must not leave only
  // part of the order requirements on the board.
  const availableSlots = Math.max(0, engine.MAX_CELLS - mainGrid.length);
  if (availableSlots < orderItems.length) {
    return {
      grantedCount: 0,
      itemCounts: {},
      mainGrid,
      error: "grid_full",
      requiredCount: orderItems.length,
      availableSlots,
    };
  }

  const placementGrid = mainGrid.map(item => ({
    uid: item.uid,
    id: item.id,
    col: item.col,
    row: item.row,
  }));
  const positions: Array<{ col: number; row: number }> = [];
  for (const _item of orderItems) {
    const empty = engine.findEmptyPos(placementGrid);
    if (!empty) {
      return {
        grantedCount: 0,
        itemCounts: {},
        mainGrid,
        error: "grid_full",
        requiredCount: orderItems.length,
        availableSlots: positions.length,
      };
    }
    positions.push(empty);
    placementGrid.push({ id: 0, col: empty.col, row: empty.row });
  }

  for (let index = 0; index < orderItems.length; index += 1) {
    const orderItem = orderItems[index];
    const position = positions[index];
    const itemDef = engine.getItemData(orderItem.id)!;
    const gridItem: any = {
      uid: engine._nextUid(state),
      id: orderItem.id,
      col: position.col,
      row: position.row,
    };
    if (engine.isLauncher(itemDef)) {
      gridItem.charges = engine.getMaxCharges(orderItem.id);
      gridItem.last_charge_time = Date.now();
    }
    mainGrid.push(gridItem);
    engine.registerProductionUnlock(state, orderItem.id);
    engine.recordItemDiscovery(state, orderItem.id);
  }

  state.version += 1;
  return { grantedCount: orderItems.length, itemCounts, mainGrid };
}

export function refreshAllOrders(state: GameState, engine: GameEngine): RefreshAllOrdersResult {
  return engine.refreshMeridianRequirements(state);
}

export function clearBoardItems(state: GameState, engine: GameEngine): number {
  let removedCount = 0;
  // The active board and cached boards can share an array. Process each once
  // and retain its identity so every reference sees the same cleared state.
  const grids = new Set([state.grid, state.saved_grid, state.battle_grid]);
  for (const grid of grids) {
    if (!grid) continue;
    for (let index = grid.length - 1; index >= 0; index -= 1) {
      const definition = engine.getItemData(grid[index].id);
      if (definition && (definition.type === 1 || definition.type === 2
        || (definition.spawns?.length ?? 0) > 0 || (definition.max_charges ?? 0) > 0)) continue;
      grid.splice(index, 1);
      removedCount += 1;
    }
  }
  if (removedCount > 0) state.version += 1;
  return removedCount;
}

export function mergeAllBoardItems(state: GameState, engine: GameEngine): number {
  const grid = state.grid;
  let mergedCount = 0;
  while (true) {
    // Full tables and ongoing/finished crafts own items that executeMerge
    // would discard. Leave them intact, even if another empty table matches.
    const candidates = grid.filter(item => {
      const definition = engine.getItemData(item.id);
      return definition && engine.isInBounds(item.col, item.row)
        && engine.getNextLevel(definition.type, definition.level, definition.group_id)
        && !(item.storage?.items?.length)
        && !(item.craft?._craft_stored?.length)
        && item.craft?._craft_state !== TableState.CRAFTING
        && item.craft?._craft_state !== TableState.READY;
    });
    let pair: [typeof grid[number], typeof grid[number]] | undefined;
    for (const source of candidates) {
      // Locked tutorial items can be merge targets, but cannot be dragged.
      if (source.immovable) continue;
      const target = candidates.find(item => item !== source && item.id === source.id
        && engine.validateMerge(state, source.col, source.row, item.col, item.row).valid);
      if (target) { pair = [source, target]; break; }
    }
    if (!pair) break;
    const [source, target] = pair;
    const result = engine.executeMerge(state, source.col, source.row, target.col, target.row);
    if (!result.ok) throw new Error(`GM board merge failed: ${result.reason}`);
    // executeMerge replaces state.grid. Preserve aliases to cached boards.
    grid.splice(0, grid.length, ...state.grid);
    state.grid = grid;
    mergedCount += 1;
  }
  return mergedCount;
}

export function claimAllPendingItems(state: GameState, engine: GameEngine): {
  claimedCount: number;
  remainingCount: number;
  skippedCount: number;
} {
  const pending = Array.isArray(state.pending_rewards) ? state.pending_rewards : [];
  const itemUids = pending.filter(reward => reward.kind !== "card_pack").map(reward => reward.uid);
  let claimedCount = 0;
  let skippedCount = 0;
  for (const uid of itemUids) {
    const result = engine.questEngine.claimPendingReward(state, uid, engine);
    if (result.ok) claimedCount += 1;
    else skippedCount += 1;
    if (!result.ok && result.reason === "board_full") break;
  }
  if (claimedCount > 0) state.version += 1;
  return {
    claimedCount,
    remainingCount: state.pending_rewards.filter(reward => reward.kind !== "card_pack").length,
    skippedCount,
  };
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
      const { cmd, amount, item_id, col, row, level } = req.body;

      // Use shared queue to prevent race conditions with game ops
      await enqueue(userId, async () => {
        const state = await storage.loadState(userId);
        if (!state) { res.status(404).json({ error: "user_not_found" }); return; }

        const knownItemIds = new Set(state.crafted_item_ids);

        engine.tickStamina(state);
        engine.tickLauncherRecharge(state);

        let msg = "ok";
        let gmResult: Record<string, unknown> = {};

        switch (cmd) {
          case "add_exp": {
            const amt = parseInt(amount, 10);
            if (isNaN(amt) || amt <= 0) { res.status(400).json({ error: "invalid_amount" }); return; }
            engine._addExp(state.cultivation, amt);
            engine.syncBreakthroughOrder(state);
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
          case "add_battle_pass_points": {
            const amt = amount;
            if (!Number.isSafeInteger(amt) || amt <= 0) { res.status(400).json({ error: "invalid_amount" }); return; }
            const passes = engine.battlePassService.getDefinitions();
            if (passes.length !== 1) { res.status(400).json({ error: "battle_pass_not_configured" }); return; }
            const activityId = passes[0].activity_id;
            const progress = engine.battlePassService.ensureProgress(state);
            const total = progress[activityId].points + amt;
            if (!Number.isSafeInteger(total)) { res.status(400).json({ error: "invalid_amount" }); return; }
            progress[activityId].points = total;
            gmResult = { battle_pass_progress: progress };
            msg = `Battle pass ${activityId} points now: ${total}`;
            break;
          }
          case "set_stamina": {
            const amt = parseInt(amount, 10);
            if (!Number.isSafeInteger(amt) || amt < 0) { res.status(400).json({ error: "invalid_amount" }); return; }
            if (amt > state.stamina) engine.addStamina(state, amt - state.stamina);
            else state.stamina = amt;
            const multiplier = engine.getStaminaMultiplierState(state);
            gmResult = {
              stamina: state.stamina,
              stamina_multiplier_max: multiplier.maxMultiplier,
              stamina_multiplier_expires_at: multiplier.expiresAt,
            };
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
            engine.registerProductionUnlock(state, iid);
            engine.recordItemDiscovery(state, iid);
            msg = `Added #${iid} at (${emptyCol},${emptyRow}) uid=${uid}`;
            break;
          }
          case "add_secret_realm_swords": {
            const result = engine.secretRealmService.gmGrantSwords(state, level, amount);
            if (!result.ok) { res.status(400).json({ error: result.reason }); return; }
            gmResult = { granted_count: result.granted_count, sword_level: result.sword_level,
              secret_realm: engine.secretRealmService.view(state) };
            msg = `已添加 ${amount} 把 ${level} 级飞剑到秘境暂存`;
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
          case "clear_board_items": {
            const removedCount = clearBoardItems(state, engine);
            gmResult = { removed_count: removedCount };
            msg = `已清理所有棋盘共 ${removedCount} 件物品，保留发射器和制作台`;
            break;
          }
          case "merge_all_board_items": {
            const mergedCount = mergeAllBoardItems(state, engine);
            gmResult = { merged_count: mergedCount, remaining_count: state.grid.length, grid: state.grid };
            msg = `当前棋盘已合成 ${mergedCount} 次，剩余 ${state.grid.length} 件物品`;
            break;
          }
          case "claim_all_pending_items": {
            const result = claimAllPendingItems(state, engine);
            gmResult = {
              claimed_count: result.claimedCount,
              remaining_count: result.remainingCount,
              skipped_count: result.skippedCount,
              grid: state.grid,
              pending_rewards: state.pending_rewards,
            };
            msg = `已领取 ${result.claimedCount} 件暂存物品，剩余 ${result.remainingCount} 件`;
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
            if (result.error) {
              res.status(400).json({
                error: result.error,
                required_count: result.requiredCount,
                available_slots: result.availableSlots,
              });
              return;
            }
            gmResult = {
              granted_count: result.grantedCount,
              granted_items: result.itemCounts,
              main_grid: result.mainGrid,
            };
            msg = `Granted ${result.grantedCount} current order items to main grid`;
            break;
          }
          case "refresh_orders":
          case "refresh_all_orders": {
            const result = refreshAllOrders(state, engine);
            gmResult = {
              meridian_acupoints: result.acupoints,
              threshold_idx: state.meridian_threshold_idx,
              refreshed_count: result.refreshedCount,
              preserved_breakthrough: result.preservedBreakthrough,
              fixed_orders_preserved: result.fixedOrdersPreserved,
            };
            if (result.preservedBreakthrough) {
              msg = "Breakthrough order is active; orders were not refreshed";
            } else if (result.fixedOrdersPreserved) {
              msg = `Refreshed ${result.refreshedCount} fixed orders without advancing the wave`;
            } else {
              msg = `Refreshed ${result.refreshedCount} orders`;
            }
            break;
          }
          default:
            res.status(400).json({ error: "unknown_cmd", cmds: ["add_exp","add_stones","add_battle_pass_points","set_stamina","set_qi","levelup","breakthrough","add_item","add_secret_realm_swords","reset_launcher_cd","clear_grid","clear_board_items","merge_all_board_items","claim_all_pending_items","activate_home_acupoints","grant_order_items","refresh_orders","refresh_all_orders"] });
            return;
        }

        const newlyDiscoveredItemIds = state.crafted_item_ids.filter(id => !knownItemIds.has(id));
        await storage.saveState(userId, state);
        console.log(`[gm] ${userId}: ${cmd} — ${msg}`);
        res.json({ ok: true, msg, storage_revision: state.storage_revision, newly_discovered_item_ids: newlyDiscoveredItemIds, ...gmResult });
      });
    } catch (e: any) {
      console.error("[gm] error:", e);
      if (!res.headersSent) res.status(500).json({ error: "internal_error" });
    }
  });

  return router;
}
