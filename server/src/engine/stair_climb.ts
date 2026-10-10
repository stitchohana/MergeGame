import type { ActivityDef, GameState, IStorage, RewardConfig } from "../storage/interface";

export interface StairClimbReward { min_rank: number; max_rank: number; stamina: number; spirit_stones: number }
export interface StairClimbScore {
  group_id: string;
  points: number;
  reached_at: number;
  settlement?: { rank: number; reward: StairClimbReward; settled_at: number };
}
export type StairClimbProgress = Record<string, StairClimbScore>;
interface Member { id: string; name: string; bot: boolean; interval_ms: number }
export interface StairClimbRow { name: string; bot: boolean; points: number; rank: number; member_index: number; reached_at: number }
export interface StairClimbGroup {
  id: string;
  realm: number;
  joined_at: number;
  members: Member[];
  final_rows?: StairClimbRow[];
  paid_members?: string[];
}
export interface StairClimbRegistry { event_id: string; revision: number; groups: StairClimbGroup[] }
interface Settings { group_size: number; order_points_ratio: number; bot_order_value: number; bot_min_minutes: number; bot_max_minutes: number; rewards: StairClimbReward[] }

/** Shared groups live in storage; no process-local membership or client-supplied points. */
export class StairClimbService {
  readonly activity: ActivityDef | undefined;
  readonly config: Settings;
  readonly start: number;
  readonly end: number;
  readonly eventId: string;
  readonly settlementDelayMs = 30_000;

  constructor(activities: ActivityDef[], private readonly stages: { name: string }[]) {
    this.activity = activities.find(a => a.widget === "StairClimb");
    this.config = this.activity?.config as unknown as Settings;
    this.start = Date.parse(this.activity?.start_time ?? "");
    this.end = Date.parse(this.activity?.end_time ?? "");
    this.eventId = `${this.activity?.id}:${this.start}`;
    if (this.activity && (!Number.isFinite(this.start) || !Number.isFinite(this.end) || this.end <= this.start ||
      this.config?.group_size !== 20 || !Number.isFinite(this.config.order_points_ratio) || this.config.order_points_ratio <= 0 || !Number.isFinite(this.config.bot_order_value) || this.config.bot_order_value <= 0 ||
      !Number.isFinite(this.config.bot_min_minutes) || this.config.bot_min_minutes <= 0 ||
      !Number.isFinite(this.config.bot_max_minutes) || this.config.bot_max_minutes < this.config.bot_min_minutes)) throw new Error("invalid_stair_climb_config");
    if (this.activity) {
      for (let rank = 1; rank <= 20; rank++) {
        const rewards = this.config.rewards?.filter(r => rank >= r.min_rank && rank <= r.max_rank) ?? [];
        if (rewards.length !== 1 || [rewards[0].stamina, rewards[0].spirit_stones].some(n => !Number.isSafeInteger(n) || n < 0)) throw new Error("invalid_stair_climb_rewards");
      }
    }
  }

  isActive(now = Date.now()): boolean { return !!this.activity && this.activity.enabled !== false && now >= this.start && now < this.end; }
  score(state: GameState): StairClimbScore | undefined { return state.stair_climb_progress?.[this.eventId]; }
  reward(rank: number): StairClimbReward { return this.config.rewards.find(r => rank >= r.min_rank && rank <= r.max_rank)!; }

  async enroll(storage: IStorage, userId: string, state: GameState, now = Date.now()): Promise<boolean> {
    if (!this.isActive(now) || this.score(state)) return false;
    for (let attempt = 0; attempt < 8; attempt++) {
      const registry = await storage.loadStairClimb(this.eventId) ?? { event_id: this.eventId, revision: 0, groups: [] };
      let group = registry.groups.find(g => g.members.some(m => !m.bot && m.id === userId));
      if (!group) {
        const realm = state.cultivation.current_level;
        const assigned = new Set(registry.groups.flatMap(g => g.members.filter(m => !m.bot).map(m => m.id)));
        const candidates = (await storage.listStairClimbCandidates(realm)).filter(id => id !== userId && !assigned.has(id));
        this.shuffle(candidates);
        const players = [userId, ...candidates.slice(0, this.config.group_size - 1)];
        this.shuffle(players);
        const members: Member[] = players.map((id, i) => ({ id, name: `道友${String(i + 1).padStart(2, "0")}`, bot: false, interval_ms: 0 }));
        const botNames = ["青竹", "云岫", "听雨", "长庚", "霜华", "玄微", "清风", "望舒", "明月", "流霞", "松声", "太初", "灵犀", "紫宸", "星河", "扶摇", "寒山", "沧浪", "归云"];
        this.shuffle(botNames);
        while (members.length < this.config.group_size) {
          const i = members.length;
          members.push({ id: `bot:${i}`, name: botNames[i - players.length], bot: true,
            interval_ms: Math.round((this.config.bot_min_minutes + Math.random() * (this.config.bot_max_minutes - this.config.bot_min_minutes)) * 60_000) });
        }
        this.shuffle(members);
        group = { id: crypto.randomUUID(), realm, joined_at: now, members };
        registry.groups.push(group);
        try { await storage.saveStairClimb(registry); }
        catch (error) { if (error instanceof Error && error.message === "state_conflict") continue; throw error; }
      }
      state.stair_climb_progress ??= {};
      state.stair_climb_progress[this.eventId] = { group_id: group.id, points: 0, reached_at: group.joined_at };
      return true;
    }
    throw new Error("state_conflict");
  }

  awardOrderPoints(state: GameState, orderValue: number, now = Date.now()): boolean {
    const score = this.score(state);
    if (!this.isActive(now) || !score || score.settlement) return false;
    const gained = this.orderPoints(orderValue);
    if (gained <= 0) return false;
    score.points += gained;
    score.reached_at = now;
    return true;
  }

  orderPoints(orderValue: number): number {
    if (!Number.isFinite(orderValue) || orderValue <= 0) return 0;
    return Math.max(1, Math.floor(orderValue * this.config.order_points_ratio + 1e-9));
  }

  private shuffle<T>(values: T[]): void {
    for (let i = values.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [values[i], values[j]] = [values[j], values[i]];
    }
  }

  async rows(storage: IStorage, group: StairClimbGroup, now = Date.now()): Promise<StairClimbRow[]> {
    if (group.final_rows) return group.final_rows;
    const rows = await Promise.all(group.members.map(async (m, member_index) => {
      let points = 0;
      let reached_at = group.joined_at;
      if (m.bot) {
        const orders = Math.floor(Math.max(0, Math.min(now, this.end) - group.joined_at) / m.interval_ms);
        points = orders * this.orderPoints(this.config.bot_order_value);
        reached_at += orders * m.interval_ms;
      } else {
        const state = await storage.loadState(m.id);
        const score = state && this.score(state);
        if (score?.group_id === group.id) { points = score.points; reached_at = score.reached_at; }
      }
      return { name: m.name, bot: m.bot, points, reached_at, member_index, rank: 0 };
    }));
    rows.sort((a, b) => b.points - a.points || a.reached_at - b.reached_at || a.member_index - b.member_index);
    return rows.map((row, i) => ({ ...row, rank: i + 1 }));
  }

  private async frozenGroup(storage: IStorage, groupId: string, now: number): Promise<StairClimbGroup | undefined> {
    for (let attempt = 0; attempt < 8; attempt++) {
      const registry = await storage.loadStairClimb(this.eventId);
      const group = registry?.groups.find(g => g.id === groupId);
      if (!registry || !group || group.final_rows || now < this.end + this.settlementDelayMs) return group;
      group.final_rows = await this.rows(storage, group, now);
      try { await storage.saveStairClimb(registry); return group; }
      catch (error) { if (error instanceof Error && error.message === "state_conflict") continue; throw error; }
    }
    throw new Error("state_conflict");
  }

  /** Caller persists currency and settlement marker in the same version-checked save. */
  async settlePlayer(storage: IStorage, userId: string, state: GameState, apply: (r: RewardConfig) => unknown, now = Date.now(), frozen?: StairClimbGroup): Promise<boolean> {
    if (!this.activity || now < this.end + this.settlementDelayMs || this.score(state)?.settlement) return false;
    const registry = frozen ? null : await storage.loadStairClimb(this.eventId);
    const enrolled = frozen ?? registry?.groups.find(g => g.members.some(m => !m.bot && m.id === userId));
    if (!enrolled) return false;
    const group = frozen ?? await this.frozenGroup(storage, enrolled.id, now);
    if (!group?.final_rows) return false;
    const index = group.members.findIndex(m => !m.bot && m.id === userId);
    const row = group.final_rows.find(r => r.member_index === index);
    if (!row) return false;
    const reward = this.reward(row.rank);
    apply({ tokens: [{ token: 3, amount: reward.stamina }, { token: 1, amount: reward.spirit_stones }] });
    state.stair_climb_progress ??= {};
    state.stair_climb_progress[this.eventId] ??= { group_id: group.id, points: row.points, reached_at: row.reached_at };
    state.stair_climb_progress[this.eventId].settlement = { rank: row.rank, reward: { ...reward }, settled_at: now };
    return true;
  }

  async view(storage: IStorage, userId: string, state: GameState, now = Date.now()) {
    if (!this.activity) return { status: "unavailable", rows: [] };
    const registry = await storage.loadStairClimb(this.eventId);
    const group = registry?.groups.find(g => g.members.some(m => !m.bot && m.id === userId));
    const rows = group ? await this.rows(storage, group, now) : [];
    const mine = group?.members.findIndex(m => !m.bot && m.id === userId) ?? -1;
    return {
      activity_id: this.activity.id, event_id: this.eventId, server_now: now, start_time: this.start, end_time: this.end,
      status: now < this.start ? "upcoming" : now < this.end ? (this.isActive(now) ? "active" : "disabled") : group?.final_rows ? "ended" : "settling",
      group_id: group?.id ?? "", realm_name: this.stages[(group?.realm ?? state.cultivation.current_level) - 1]?.name ?? "未知境界",
      order_points_ratio: this.config.order_points_ratio, rewards: this.config.rewards,
      rows: rows.map(r => ({ ...r, is_self: r.member_index === mine })),
      my_rank: rows.find(r => r.member_index === mine)?.rank ?? 0,
      my_points: this.score(state)?.points ?? 0, settlement: this.score(state)?.settlement ?? null,
    };
  }

  /** Five recipients per tick keeps D1 work bounded; retries resume unpaid members. */
  async settleBatch(storage: IStorage, apply: (s: GameState, r: RewardConfig) => unknown, now = Date.now()): Promise<void> {
    if (!this.activity || now < this.end + this.settlementDelayMs) return;
    let registry = await storage.loadStairClimb(this.eventId);
    const pending = registry?.groups.find(g => g.members.some(m => !m.bot && !g.paid_members?.includes(m.id)));
    if (!pending) return;
    const group = await this.frozenGroup(storage, pending.id, now);
    if (!group?.final_rows) return;
    const paid: string[] = [];
    for (const member of group.members.filter(m => !m.bot && !group.paid_members?.includes(m.id)).slice(0, 5)) {
      const state = await storage.loadState(member.id);
      if (!state) continue;
      try {
        if (await this.settlePlayer(storage, member.id, state, r => apply(state, r), now, group)) await storage.saveState(member.id, state);
        paid.push(member.id);
      } catch (error) { if (!(error instanceof Error && error.message === "state_conflict")) throw error; }
    }
    registry = await storage.loadStairClimb(this.eventId);
    const savedGroup = registry?.groups.find(g => g.id === group.id);
    if (registry && savedGroup && paid.length) {
      savedGroup.paid_members = [...new Set([...(savedGroup.paid_members ?? []), ...paid])];
      try { await storage.saveStairClimb(registry); }
      catch (error) { if (!(error instanceof Error && error.message === "state_conflict")) throw error; }
    }
  }
}
