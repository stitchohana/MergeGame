import * as fs from "fs";
import * as path from "path";
import { GameState, RewardConfig, ResetCycle, QuestProgress, PendingReward } from "../storage/interface";
import { GameEngine } from "./game_engine";

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
  constructor(configDir: string) {
    this.loadQuests(configDir);
  }

  private loadQuests(configDir: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(configDir, "json_output", "quests.json"), "utf-8"));
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
      rewards: typeof q.rewards === "number" ? engine.getRewardConfig(q.rewards) ?? q.rewards : q.rewards
      }));
  }

  checkAndResetQuests(state: GameState, resetHour: number): boolean {
    const now = Date.now();
    const lastReset = state.quest_last_reset ?? 0;
    if (lastReset <= 0) {
      state.quest_last_reset = now;
      return false;
    }

    // Adjust both timestamps by resetHour: a day starts at resetHour, not midnight
    const adjustMs = resetHour * 3600000;
    const lastAdjusted = new Date(lastReset - adjustMs);
    const nowAdjusted = new Date(now - adjustMs);

    let resetDaily = false;
    let resetWeekly = false;

    // Daily: different adjusted day
    if (lastAdjusted.getFullYear() !== nowAdjusted.getFullYear() ||
        lastAdjusted.getMonth() !== nowAdjusted.getMonth() ||
        lastAdjusted.getDate() !== nowAdjusted.getDate()) {
      resetDaily = true;
    }

    // Weekly: different ISO week (week containing Jan 4)
    // getDay() returns 0=Sun..6=Sat, converted to 1=Mon..7=Sun via `|| 7`.
    const getISOWeek = (d: Date) => {
      const dayOfWeek = d.getDay() || 7; // Mon=1..Sun=7
      const jan4 = new Date(d.getFullYear(), 0, 4);
      const jan4Day = jan4.getDay() || 7;
      const daysSinceJan4 = (d.getTime() - jan4.getTime()) / 86400000;
      return Math.floor((daysSinceJan4 + jan4Day + 3) / 7);
    };
    if (lastAdjusted.getFullYear() !== nowAdjusted.getFullYear() ||
        getISOWeek(lastAdjusted) !== getISOWeek(nowAdjusted)) {
      resetWeekly = true;
    }

    let didReset = false;
    for (const q of this.quests) {
      if (!q.reset_cycle || q.reset_cycle === ResetCycle.NEVER) continue;
      if (q.reset_cycle === ResetCycle.DAILY && !resetDaily) continue;
      if (q.reset_cycle === ResetCycle.WEEKLY && !resetWeekly) continue;
      const p = state.quest_progress?.[q.id];
      if (p) {
        p.current_count = 0;
        p.completed = false;
        p.claimed = false;
        didReset = true;
        console.log(`[quest] #${q.id} "${q.name}" reset (cycle=${q.reset_cycle})`);
      }
    }

    state.quest_last_reset = now;
    return didReset;
  }

  initQuestProgress(state: GameState): boolean {
    state.quest_progress = state.quest_progress || {};
    let modified = false;
    state.pending_rewards = state.pending_rewards || [];
    // Lazily add missing quest entries (supports new quests added to config later)
    for (const q of this.quests) {
      // One-time migration: if quest is no longer auto_reward, reset claimed state
      if (!state.quests_initialized && !q.auto_reward && state.quest_progress[q.id]?.claimed) {
        state.quest_progress[q.id].claimed = false;
        modified = true;
        console.log(`[quest] #${q.id} migrated: auto_reward disabled, reset claimed`);
      }
      if (!state.quest_progress[q.id]) {
        state.quest_progress[q.id] = { current_count: 0, completed: false, claimed: false };
        modified = true;
      }
    }
    if (!state.quests_initialized) { state.quests_initialized = true; return true; }
    return false;
  }

  incrementQuestProgress(
    state: GameState,
    type: number,
    count: number,
    engine: GameEngine
  ): void {
    this.initQuestProgress(state);
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
          console.log(`[quest] #${q.id} auto-reward distributed`);
        }
      }
    }
  }

  claimQuestReward(state: GameState, questId: number, engine: GameEngine):
    { ok: true; rewards: RewardConfig | number } | { ok: false; reason: string }
  {
    const q = this.quests.find(q => q.id === questId);
    if (!q) return { ok: false, reason: "quest_not_found" };
    const p = state.quest_progress?.[questId];
    if (!p) return { ok: false, reason: "quest_not_started" };
    if (!p.completed) return { ok: false, reason: "quest_not_completed" };
    if (p.claimed) return { ok: false, reason: "already_claimed" };
    if (q.auto_reward) return { ok: false, reason: "auto_reward_quest" };

    engine.applyRewards(state, q.rewards);
    p.claimed = true;
    console.log(`[quest] #${q.id} "${q.name}" claimed`);
    return { ok: true, rewards: q.rewards };
  }

  claimPendingReward(state: GameState, uid: number, engine: GameEngine):
    { ok: true; col: number; row: number } | { ok: false; reason: string }
  {
    state.pending_rewards = state.pending_rewards || [];
    const idx = state.pending_rewards.findIndex(r => r.uid === uid);
    if (idx < 0) return { ok: false, reason: "reward_not_found" };

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
