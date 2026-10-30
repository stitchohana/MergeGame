import { GameState, RewardConfig, ResetCycle, QuestProgress, PendingReward } from "../storage/interface";
import { GameEngine } from "./game_engine";
import { getResetPeriod } from "./reset_period";
import { activitiesUnlocked } from "./activity_access";

interface QuestDef {
  id: number;
  type: number;
  name: string;
  description: string;
  target_count: number;
  rewards: RewardConfig | number;
  auto_reward: boolean;
  reset_cycle?: number;  // ResetCycle enum: 0=never, 1=daily, 2=weekly
}

export class QuestEngine {
  private quests: QuestDef[] = [];
  constructor(data: any) {
    this.loadQuests(data);
  }

  private loadQuests(data: any): void {
    try {
      this.quests = data.quests || [];
      console.log(`[quest] Loaded ${this.quests.length} quests`);
    } catch { /* quests.json optional */ }
  }

  getQuestDefs(): QuestDef[] {
    return this.quests;
  }

  getResolvedQuestDefs(engine: GameEngine): any[] {
    return this.quests.map(q => ({
      id: q.id,
      type: q.type,
      name: q.name,
      description: q.description,
      target_count: q.target_count,
      auto_reward: q.auto_reward,
      reset_cycle: q.reset_cycle ?? ResetCycle.NEVER,
      weekly_points: engine.weeklyTaskService.questPoints(q.id),
      rewards: typeof q.rewards === "number" ? engine.getRewardConfig(q.rewards) ?? q.rewards : q.rewards
      }));
  }

  checkAndResetQuests(state: GameState, resetHour: number): boolean {
    if (!activitiesUnlocked(state)) return false;
    const now = Date.now();
    const lastReset = state.quest_last_reset ?? 0;
    if (lastReset <= 0) return false;

    const last = getResetPeriod(lastReset, resetHour);
    const current = getResetPeriod(now, resetHour);
    const resetDaily = current.day > last.day;
    const resetWeekly = current.week > last.week;
    if (!resetDaily && !resetWeekly) return false;

    for (const q of this.quests) {
      if (!q.reset_cycle || q.reset_cycle === ResetCycle.NEVER) continue;
      if (q.reset_cycle === ResetCycle.DAILY && !resetDaily) continue;
      if (q.reset_cycle === ResetCycle.WEEKLY && !resetWeekly) continue;
      const p = state.quest_progress?.[q.id];
      if (p) {
        p.current_count = 0;
        p.completed = false;
        p.claimed = false;
        console.log(`[quest] #${q.id} "${q.name}" reset (cycle=${q.reset_cycle})`);
      }
    }

    state.quest_last_reset = now;
    return true; // The period timestamp changed, even if progress was absent.
  }

  initQuestProgress(state: GameState): boolean {
    if (!activitiesUnlocked(state)) return false;
    if (state.quest_progress) return false;
    state.quest_progress = Object.fromEntries(this.quests.map(q => [q.id, {
      current_count: 0, completed: false, claimed: false,
    }]));
    state.quest_last_reset = Date.now();
    return true;
  }

  incrementQuestProgress(
    state: GameState,
    type: number,
    count: number,
    engine: GameEngine
  ): void {
    if (!activitiesUnlocked(state)) return;
    this.initQuestProgress(state);
    this.checkAndResetQuests(state, engine.questResetHour);
    engine.weeklyTaskService.ensureProgress(state);
    for (const q of this.quests) {
      if (q.type !== type) continue;
      const p = state.quest_progress![q.id];
      if (p.completed || p.claimed) continue;
      p.current_count = Math.min(p.current_count + count, q.target_count);
      if (p.current_count >= q.target_count) {
        p.completed = true;
        console.log(`[quest] #${q.id} "${q.name}" completed`);
        if (q.auto_reward) {
          engine.applyRewards(state, q.rewards);
          p.claimed = true;
          engine.weeklyTaskService.awardTaskReward(state, q.id);
          console.log(`[quest] #${q.id} auto-reward distributed`);
        }
      }
    }
  }

  claimQuestReward(state: GameState, questId: number, engine: GameEngine):
    { ok: true; rewards: RewardConfig | number } | { ok: false; reason: string }
  {
    if (!activitiesUnlocked(state)) return { ok: false, reason: "activity_locked" };
    const q = this.quests.find(q => q.id === questId);
    if (!q) return { ok: false, reason: "quest_not_found" };
    this.checkAndResetQuests(state, engine.questResetHour);
    const p = state.quest_progress?.[questId];
    if (!p) return { ok: false, reason: "quest_not_started" };
    if (!p.completed) return { ok: false, reason: "quest_not_completed" };
    if (p.claimed) return { ok: false, reason: "already_claimed" };
    if (q.auto_reward) return { ok: false, reason: "auto_reward_quest" };

    engine.applyRewards(state, q.rewards);
    p.claimed = true;
    engine.weeklyTaskService.awardTaskReward(state, q.id);
    console.log(`[quest] #${q.id} "${q.name}" claimed`);
    return { ok: true, rewards: q.rewards };
  }

  claimPendingReward(state: GameState, uid: number, engine: GameEngine):
    { ok: true; col: number; row: number } | { ok: false; reason: string }
  {
    const idx = state.pending_rewards.findIndex(r => r.uid === uid);
    if (idx < 0) return { ok: false, reason: "reward_not_found" };

    if (state.pending_rewards[idx].kind === "card_pack") return { ok: false, reason: "card_pack_open_required" };

    // Server finds empty cell
    const map = engine.buildGridMap(state.grid);
    const target = engine.findEmptyByRow(map);
    if (!target) return { ok: false, reason: "board_full" };

    const reward = state.pending_rewards[idx];
    state.pending_rewards.splice(idx, 1);
    state.grid.push({ uid: reward.uid, id: reward.id, col: target.col, row: target.row });    console.log(`[quest] claim pending reward: ${reward.name} uid=${uid} -> (${target.col},${target.row})`);
    return { ok: true, col: target.col, row: target.row };
  }
}
