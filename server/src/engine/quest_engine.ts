import * as fs from "fs";
import * as path from "path";
import { GameState, RewardConfig, QuestProgress, PendingReward } from "../storage/interface";
import { GameEngine } from "./game_engine";

interface QuestDef {
  id: number;
  type: number;
  name: string;
  description: string;
  target_count: number;
  rewards: RewardConfig | number;
  auto_reward: boolean;
}

export class QuestEngine {
  private quests: QuestDef[] = [];
  lastAppliedRewards: RewardConfig | null = null;

  constructor(configDir: string) {
    this.loadQuests(configDir);
  }

  private loadQuests(configDir: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(configDir, "quests.json"), "utf-8"));
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
      rewards: typeof q.rewards === "number" ? engine.getRewardConfig(q.rewards) ?? q.rewards : q.rewards,
    }));
  }

  initQuestProgress(state: GameState): void {
    if (state.quests_initialized) return;
    state.quest_progress = {};
    for (const q of this.quests) {
      state.quest_progress[q.id] = { current_count: 0, completed: false, claimed: false };
    }
    state.quests_initialized = true;
    state.pending_rewards = state.pending_rewards || [];
  }

  incrementQuestProgress(
    state: GameState,
    type: number,
    count: number,
    engine: GameEngine
  ): void {
    this.initQuestProgress(state);
    this.lastAppliedRewards = null;
    for (const q of this.quests) {
      if (q.type !== type) continue;
      const p = state.quest_progress![q.id];
      if (p.completed || p.claimed) continue;
      p.current_count = Math.min(p.current_count + count, q.target_count);
      if (p.current_count >= q.target_count) {
        p.completed = true;
        console.log(`[quest] #${q.id} "${q.name}" completed`);
        if (q.auto_reward) {
          const applied = engine.applyRewards(state, q.rewards);
          this.lastAppliedRewards = applied;
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

    const applied = engine.applyRewards(state, q.rewards);
    this.lastAppliedRewards = applied;
    p.claimed = true;
    console.log(`[quest] #${q.id} "${q.name}" claimed`);
    return { ok: true, rewards: q.rewards };
  }

  claimPendingReward(state: GameState, uid: number, col: number, row: number, engine: GameEngine):
    { ok: true } | { ok: false; reason: string }
  {
    state.pending_rewards = state.pending_rewards || [];
    const idx = state.pending_rewards.findIndex(r => r.uid === uid);
    if (idx < 0) return { ok: false, reason: "reward_not_found" };
    if (!engine.isInBounds(col, row)) return { ok: false, reason: "invalid_position" };
    const key = engine.posKey(col, row);
    if (state.grid.some(g => engine.posKey(g.col, g.row) === key)) return { ok: false, reason: "target_occupied" };

    const reward = state.pending_rewards[idx];
    state.pending_rewards.splice(idx, 1);
    state.grid.push({ uid: engine._nextUid(state), id: reward.id, col, row });
    state.version += 1;
    console.log(`[quest] claim pending reward: ${reward.name} uid=${uid} -> (${col},${row})`);
    return { ok: true };
  }
}
