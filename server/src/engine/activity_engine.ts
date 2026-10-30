import { GameState, ActivityDef, ActivityCycle, GridItem, RewardConfig } from "../storage/interface";
import type { GameEngine } from "./game_engine";
import { getResetPeriod } from "./reset_period";
import { activitiesUnlocked } from "./activity_access";

export class ActivityEngine {
  private activities: ActivityDef[] = [];
  private weeklyTasks = new Map<number, number[][]>();

  constructor(activitiesData: any, weeklyTasksData: any) {
    this.loadActivities(activitiesData);
    this.loadWeeklyTasks(weeklyTasksData);
  }

  private loadActivities(data: any): void {
    try {
      this.activities = data.activities || [];
      console.log(`[activity] Loaded ${this.activities.length} activities`);
    } catch { /* optional */ }
  }

  private loadWeeklyTasks(data: any): void {
    try {
      for (const wt of data.weekly_tasks || []) {
        this.weeklyTasks.set(wt.activity_id, wt.daily_quests);
      }
      console.log(`[activity] Loaded ${this.weeklyTasks.size} weekly task sets`);
    } catch { /* optional */ }
  }

  getActivities(): ActivityDef[] { return this.activities; }

  hasWeeklyTasks(activityId: number): boolean {
    return this.weeklyTasks.has(activityId);
  }

  getCurrentDay(activityId: number, resetHour: number): number {
    const quests = this.weeklyTasks.get(activityId);
    if (!quests) return 0;
    return Math.min(getResetPeriod(Date.now(), resetHour).weekday, quests.length - 1);
  }

  isActive(a: ActivityDef): boolean {
    if (a.enabled === false) return false;
    if (a.cycle === ActivityCycle.ONCE) {
      const now = Date.now();
      if (a.start_time) {
        const st = new Date(a.start_time).getTime();
        if (now < st) return false;
      }
      if (a.end_time) {
        const et = new Date(a.end_time).getTime();
        if (now >= et) return false;
      }
      return true;
    }
    return true; // daily/weekly/monthly always active
  }

  getDailyQuestIds(activityId: number, day: number): number[] {
    const quests = this.weeklyTasks.get(activityId);
    if (!quests || day < 0 || day >= quests.length) return [];
    return quests[day];
  }

  initProgress(state: GameState): void {
    if (!activitiesUnlocked(state)) return;
    state.activity_progress = state.activity_progress || {};
    for (const a of this.activities) {
      if (!state.activity_progress[a.id]) {
        state.activity_progress[a.id] = { completed: false, claimed: false, last_reset: 0 };
      }
    }
  }

  recordOrderSupplyAction(state: GameState, itemId: number, availableBefore = 0): void {
    if (!activitiesUnlocked(state)) return;
    const matching = (state.meridian_acupoints ?? []).flatMap(order => {
      if (order.completed || (order as any).breakthrough_order) return [];
      const ids = order.item_ids;
      const required = ids.filter(id => id === itemId).length;
      return required > 0 ? [{ order, required }] : [];
    });
    if (!matching.length) return;
    // Completion belongs to an order slot, and survives supply claims and
    // moving/selling its product. Existing inventory covers slots without points.
    let credited = 0;
    for (const { order, required } of matching) {
      order.order_supply_completed_counts ??= {};
      const count = Math.min(required, Math.max(0, order.order_supply_completed_counts[itemId] ?? 0));
      order.order_supply_completed_counts[itemId] = count;
      credited += count;
    }
    let existing = Math.max(0, availableBefore - credited);
    for (const { order, required } of matching) {
      const counts = order.order_supply_completed_counts!;
      const covered = Math.min(existing, required - counts[itemId]);
      counts[itemId] += covered;
      existing -= covered;
    }
    const slot = matching.find(({ order, required }) => order.order_supply_completed_counts![itemId] < required);
    if (!slot) return;
    slot.order.order_supply_completed_counts![itemId]++;
    this.initProgress(state);
    for (const activity of this.activities) {
      if (activity.widget !== "OrderSupply" || !this.isActive(activity)) continue;
      const progress = state.activity_progress![activity.id];
      const target = this.orderSupplyCount(activity, "target_count", 5);
      progress.current_count = Math.min(target, (progress.current_count ?? 0) + 1);
      progress.completed = progress.current_count >= target;
    }
  }

  claimOrderSupply(state: GameState, activityId: number, expectedClaimCount: number, engine: GameEngine):
    { ok: true; rewards: RewardConfig; spawned_items: GridItem[]; pending_rewards_added: number; crafts_completed: number } | { ok: false; reason: string }
  {
    if (!activitiesUnlocked(state)) return { ok: false, reason: "activity_locked" };
    const activity = this.activities.find(a => a.id === activityId && a.widget === "OrderSupply");
    if (!activity) return { ok: false, reason: "invalid_activity" };
    if (!this.isActive(activity)) return { ok: false, reason: "activity_inactive" };
    if (state.board_type === 1) return { ok: false, reason: "main_board_required" };
    this.initProgress(state);
    const progress = state.activity_progress![activityId];
    if ((progress.claim_count ?? 0) !== expectedClaimCount) return { ok: false, reason: "already_claimed" };
    const target = this.orderSupplyCount(activity, "target_count", 5);
    if ((progress.current_count ?? 0) < target) return { ok: false, reason: "activity_not_completed" };
    const rewardCount = this.orderSupplyCount(activity, "reward_count", 3);
    const grid = engine.buildGridMap(state.grid);
    const positions: { col: number; row: number }[] = [];
    for (let i = 0; i < rewardCount; i++) {
      const pos = engine.findEmptyByRow(grid);
      if (!pos) break;
      positions.push(pos);
      grid.set(engine.posKey(pos.col, pos.row), { id: 0, ...pos });
    }

    // Prefer material shortages after accounting for recipes and usable inventory.
    const required: number[] = [];
    for (const order of state.meridian_acupoints ?? []) {
      if (order.completed || (order as any).breakthrough_order) continue;
      const ids = order.item_ids;
      required.push(...ids.filter(id => [0, 4].includes(engine.getItemData(id)?.type ?? -1)));
    }
    const cultivationLevel = Number(state.cultivation?.current_level ?? 1);
    let candidates = engine.getMissingOrderSupplyMaterials(state);
    if (!candidates.length) candidates = [...new Set(required.flatMap(id => engine.getOrderSupplyMaterials(id, cultivationLevel)))];
    if (!candidates.length) candidates = [...new Set(engine.getUnlockedOrderPool(state)
      .flatMap(id => engine.getOrderSupplyMaterials(id, cultivationLevel, false)))];
    if (!candidates.length) return { ok: false, reason: "no_order_materials" };
    const rewards: RewardConfig = { items: [] };
    const spawned: GridItem[] = [];
    let pendingRewardsAdded = 0;
    for (let i = 0; i < rewardCount; i++) {
      const id = candidates[i % candidates.length];
      engine.recordItemDiscovery(state, id);
      const reward = rewards.items!.find(entry => entry.id === id);
      if (reward) reward.count++;
      else rewards.items!.push({ id, count: 1 });
      if (i < positions.length) {
        const item: GridItem = { id, uid: engine._nextUid(state), ...positions[i] };
        spawned.push(item);
      } else {
        const itemData = engine.getItemData(id);
        state.pending_rewards.push({ uid: engine._nextUid(state), id, name: itemData?.name ?? `#${id}` });
        pendingRewardsAdded++;
      }
    }
    const craftsCompleted = engine.finishBoardCrafting(state);
    state.grid.push(...spawned);
    state.version++;
    progress.current_count = 0;
    progress.completed = false;
    progress.claimed = false;
    progress.claim_count = expectedClaimCount + 1;
    return { ok: true, rewards, spawned_items: spawned, pending_rewards_added: pendingRewardsAdded, crafts_completed: craftsCompleted };
  }

  private orderSupplyCount(activity: ActivityDef, key: string, fallback: number): number {
    const value = Number(activity.config?.[key] ?? fallback);
    return Number.isSafeInteger(value) && value > 0 ? value : fallback;
  }

  checkAndReset(state: GameState, resetHour: number): void {
    if (!activitiesUnlocked(state)) return;
    const now = Date.now();
    state.activity_progress = state.activity_progress || {};
    for (const a of this.activities) {
      const p = state.activity_progress![a.id];
      if (!p) continue;
      if (a.cycle === ActivityCycle.ONCE) {
        // Check if one-time activity is active based on start/end time
        const start = a.start_time ? new Date(a.start_time).getTime() : 0;
        const end = a.end_time ? new Date(a.end_time).getTime() : Infinity;
        if (now < start || now > end) continue; // not active
        // One-time: never reset, just check if completed
        continue;
      }
      if (a.cycle === ActivityCycle.DAILY) {
        if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "day")) continue;
        p.completed = false;
        p.claimed = false;
        p.last_reset = now;
      } else if (a.cycle === ActivityCycle.WEEKLY) {
        if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "week")) continue;
        p.completed = false;
        p.claimed = false;
        p.last_reset = now;
      } else if (a.cycle === ActivityCycle.MONTHLY) {
        if (!this.isNewPeriod(p.last_reset ?? 0, now, resetHour, "month")) continue;
        p.completed = false;
        p.claimed = false;
        p.last_reset = now;
      }
    }
  }

  private isNewPeriod(lastTime: number, now: number, resetHour: number, period: string): boolean {
    if (lastTime <= 0) return true;
    const last = getResetPeriod(lastTime, resetHour);
    const cur = getResetPeriod(now, resetHour);
    if (period === "day") {
      return cur.day > last.day;
    }
    if (period === "week") {
      return cur.week > last.week;
    }
    if (period === "month") {
      return cur.month > last.month;
    }
    return false;
  }
}
