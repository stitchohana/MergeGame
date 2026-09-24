import { ActivityDef, BattlePassProgress, GameState, RewardConfig } from "../storage/interface";

export interface BattlePassTier {
  level: number;
  required_points: number;
  free_rewards: RewardConfig;
  premium_rewards: RewardConfig;
}

export interface BattlePassDefinition {
  activity_id: number;
  points_token_id: number;
  tiers: BattlePassTier[];
}

type BattlePassResponse = { ok: true; progress: Record<number, BattlePassProgress>; rewards?: RewardConfig } | { ok: false; reason: string };

const newProgress = (): BattlePassProgress => ({
  points: 0,
  premium_unlocked: false,
  free_claimed_levels: [],
  premium_claimed_levels: [],
});

export class BattlePassService {
  private readonly passes = new Map<number, BattlePassDefinition>();
  private readonly activities = new Map<number, ActivityDef>();
  private readonly premiumUnlockCost: number;
  private readonly pointsPerValue: number;

  constructor(config: any, activitiesData: any, tokensData: any, gameConfig: any) {
    this.premiumUnlockCost = Number(gameConfig?.battle_pass?.premium_unlock_cost);
    this.pointsPerValue = Number(gameConfig?.battle_pass?.points_per_value);
    if (!Number.isInteger(this.premiumUnlockCost) || this.premiumUnlockCost < 0) {
      throw new Error("battle_pass_invalid_unlock_cost");
    }
    if (!Number.isFinite(this.pointsPerValue) || this.pointsPerValue <= 0) {
      throw new Error("battle_pass_invalid_points_per_value");
    }
    const activities: ActivityDef[] = Array.isArray(activitiesData?.activities) ? activitiesData.activities : [];
    const tokens: Array<{ id: number }> = Array.isArray(tokensData?.tokens) ? tokensData.tokens : [];
    const tokenIds = new Set(tokens.map(token => Number(token.id)));
    for (const activity of activities) this.activities.set(Number(activity.id), activity);

    const definitions: BattlePassDefinition[] = Array.isArray(config?.passes) ? config.passes : [];
    if (definitions.length > 1) throw new Error("battle_pass_only_one_enabled_pass_supported");
    for (const definition of definitions) {
      if (!Number.isInteger(definition.activity_id) || this.passes.has(definition.activity_id)) {
        throw new Error("battle_pass_invalid_or_duplicate_activity_id");
      }
      const activity = this.activities.get(definition.activity_id);
      if (!activity) throw new Error("battle_pass_activity_not_found");
      if ((definition as any).start_time !== undefined || (definition as any).end_time !== undefined) {
        throw new Error("battle_pass_time_must_come_from_activity");
      }
      if (!tokenIds.has(definition.points_token_id)) throw new Error("battle_pass_points_token_not_found");
      if (activity.enabled === true) {
        const start = activity.start_time ? Date.parse(activity.start_time) : Number.NaN;
        const end = activity.end_time ? Date.parse(activity.end_time) : Number.NaN;
        if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end) {
          throw new Error("battle_pass_enabled_activity_requires_valid_dates");
        }
      }
      if (!Array.isArray(definition.tiers) || definition.tiers.length === 0) {
        throw new Error("battle_pass_tiers_required");
      }
      let previousLevel = 0;
      let previousPoints = -1;
      for (const tier of definition.tiers) {
        if (!Number.isInteger(tier.level) || tier.level <= previousLevel
          || !Number.isInteger(tier.required_points) || tier.required_points < 0
          || tier.required_points < previousPoints) {
          throw new Error("battle_pass_invalid_tier_order");
        }
        this.validateRewards(tier.free_rewards, tokenIds);
        this.validateRewards(tier.premium_rewards, tokenIds);
        previousLevel = tier.level;
        previousPoints = tier.required_points;
      }
      this.passes.set(definition.activity_id, definition);
    }
  }

  private validateRewards(rewards: RewardConfig, tokenIds: Set<number>): void {
    if (!rewards || typeof rewards !== "object") throw new Error("battle_pass_invalid_rewards");
    for (const token of rewards.tokens ?? []) {
      if (!tokenIds.has(token.token) || !Number.isFinite(token.amount) || token.amount < 0) {
        throw new Error("battle_pass_invalid_token_reward");
      }
    }
    for (const item of rewards.items ?? []) {
      if (!Number.isInteger(item.id) || item.id <= 0 || !Number.isInteger(item.count) || item.count < 0) {
        throw new Error("battle_pass_invalid_item_reward");
      }
    }
  }

  getDefinitions(): BattlePassDefinition[] {
    return [...this.passes.values()];
  }

  getDefinition(activityId: number): BattlePassDefinition | undefined {
    return this.passes.get(activityId);
  }

  ensureProgress(state: GameState): Record<number, BattlePassProgress> {
    state.battle_pass_progress ??= {};
    for (const activityId of this.passes.keys()) {
      const current = state.battle_pass_progress[activityId];
      if (!current) state.battle_pass_progress[activityId] = newProgress();
      else {
        current.points = Math.max(0, Math.floor(Number(current.points) || 0));
        current.premium_unlocked = current.premium_unlocked === true;
        current.free_claimed_levels = Array.isArray(current.free_claimed_levels) ? current.free_claimed_levels : [];
        current.premium_claimed_levels = Array.isArray(current.premium_claimed_levels) ? current.premium_claimed_levels : [];
      }
    }
    return state.battle_pass_progress;
  }

  isActive(activityId: number, now = Date.now()): boolean {
    const activity = this.activities.get(activityId);
    if (!activity || activity.enabled !== true) return false;
    const start = Date.parse(activity.start_time ?? "");
    const end = Date.parse(activity.end_time ?? "");
    return Number.isFinite(start) && Number.isFinite(end) && now >= start && now < end;
  }

  awardOrderPoints(state: GameState, totalValue: number, requestId = "", now = Date.now()): boolean {
    state.battle_pass_order_requests ??= [];
    if (requestId && state.battle_pass_order_requests.includes(requestId)) return false;
    if (requestId) {
      state.battle_pass_order_requests.push(requestId);
      if (state.battle_pass_order_requests.length > 1000) state.battle_pass_order_requests.splice(0, state.battle_pass_order_requests.length - 1000);
    }
    if (!Number.isFinite(totalValue) || totalValue <= 0) return false;
    let changed = false;
    const progress = this.ensureProgress(state);
    for (const pass of this.passes.values()) {
      if (!this.isActive(pass.activity_id, now)) continue;
      const points = Math.floor(totalValue * this.pointsPerValue);
      if (points <= 0) continue;
      progress[pass.activity_id].points += points;
      changed = true;
    }
    return changed;
  }

  unlock(state: GameState, activityId: number, now = Date.now()): BattlePassResponse {
    const pass = this.passes.get(activityId);
    if (!pass) return { ok: false, reason: "invalid_activity" };
    if (!this.isActive(activityId, now)) return { ok: false, reason: "activity_inactive" };
    const progress = this.ensureProgress(state)[activityId];
    if (progress.premium_unlocked) return { ok: true, progress: this.ensureProgress(state) };
    if (state.spirit_stones < this.premiumUnlockCost) return { ok: false, reason: "insufficient_spirit_stones" };
    state.spirit_stones -= this.premiumUnlockCost;
    progress.premium_unlocked = true;
    return { ok: true, progress: this.ensureProgress(state) };
  }

  claim(
    state: GameState,
    activityId: number,
    level: number,
    track: string,
    applyRewards: (rewards: RewardConfig) => RewardConfig,
    now = Date.now(),
  ): BattlePassResponse {
    const pass = this.passes.get(activityId);
    if (!pass) return { ok: false, reason: "invalid_activity" };
    if (!this.isActive(activityId, now)) return { ok: false, reason: "activity_inactive" };
    if (track !== "free" && track !== "premium") return { ok: false, reason: "invalid_track" };
    const tier = pass.tiers.find(entry => entry.level === level);
    if (!tier) return { ok: false, reason: "invalid_level" };
    const progress = this.ensureProgress(state)[activityId];
    if (progress.points < tier.required_points) return { ok: false, reason: "insufficient_points" };
    if (track === "premium" && !progress.premium_unlocked) return { ok: false, reason: "premium_not_unlocked" };
    const claimed = track === "free" ? progress.free_claimed_levels : progress.premium_claimed_levels;
    if (claimed.includes(level)) return { ok: false, reason: "already_claimed" };
    const rewards = applyRewards(track === "free" ? tier.free_rewards : tier.premium_rewards);
    claimed.push(level);
    return { ok: true, progress: this.ensureProgress(state), rewards };
  }

  settleExpired(state: GameState, applyRewards: (rewards: RewardConfig) => RewardConfig, now = Date.now()): boolean {
    let changed = false;
    const progress = this.ensureProgress(state);
    for (const pass of this.passes.values()) {
      const activity = this.activities.get(pass.activity_id);
      const end = activity?.end_time ? Date.parse(activity.end_time) : Number.NaN;
      if (activity?.enabled !== true || !Number.isFinite(end) || now < end) continue;
      const passProgress = progress[pass.activity_id];
      for (const tier of pass.tiers) {
        if (passProgress.points < tier.required_points) continue;
        if (!passProgress.free_claimed_levels.includes(tier.level)) {
          applyRewards(tier.free_rewards);
          passProgress.free_claimed_levels.push(tier.level);
          changed = true;
        }
        if (passProgress.premium_unlocked && !passProgress.premium_claimed_levels.includes(tier.level)) {
          applyRewards(tier.premium_rewards);
          passProgress.premium_claimed_levels.push(tier.level);
          changed = true;
        }
      }
    }
    return changed;
  }

}
