import type { ActivityDef, GameState, IStorage, RewardConfig } from "../storage/interface";
import { activitiesUnlocked } from "./activity_access";

export interface DuelSettings {
  target_points: number; order_points_ratio: number; win_stamina: number; win_points: number;
  matchmaking_seconds: number; bot_min_seconds: number; bot_max_seconds: number; bot_order_value: number;
}
export interface DuelTier { tier: number; required_points: number; stamina: number; spirit_stones: number }
interface DuelMatch {
  id: string; players: string[]; started_at: number; points: Record<string, number>;
  bot_interval_ms: number; winner?: string; ended_at?: number;
}
interface DuelTicket { realm: number; queued_at: number; match_id?: string }
export interface DuelRegistry {
  event_id: string; revision: number; tickets: Record<string, DuelTicket>; matches: Record<string, DuelMatch>;
}
export interface DuelProgress {
  event_id: string; round: number; victory_points: number; claimed_tiers: number[];
  status: "resting" | "matching" | "playing" | "lost";
  match_id?: string; order_points: number; last_order_at: number;
  last_result?: { match_id: string; won: boolean; my_points: number; opponent_points: number; stamina: number; victory_points: number };
}

/** Orders are persisted before publication. Registry CAS chooses one winner; player CAS pays it once. */
export class OrderDuelService {
  readonly activity: ActivityDef | undefined;
  readonly settings: DuelSettings;
  readonly tiers: DuelTier[];
  readonly eventId: string;

  constructor(activities: ActivityDef[], data: any) {
    this.activity = activities.find(a => a.widget === "OrderDuel");
    this.settings = data?.settings?.find((s: any) => s.activity_id === this.activity?.id);
    this.tiers = (data?.rewards ?? []).filter((r: any) => r.activity_id === this.activity?.id);
    this.eventId = `duel:${this.activity?.id}:${this.activity?.start_time ?? "permanent"}`;
    if (!this.activity) return;
    if (activities.filter(a => a.widget === "OrderDuel").length !== 1 || data?.settings?.length !== 1 || !this.settings ||
      ![this.settings.target_points, this.settings.win_points, this.settings.matchmaking_seconds,
        this.settings.bot_min_seconds, this.settings.bot_max_seconds].every(v => Number.isSafeInteger(v) && v > 0) ||
      !Number.isSafeInteger(this.settings.win_stamina) || this.settings.win_stamina < 0 ||
      ![this.settings.order_points_ratio, this.settings.bot_order_value].every(v => Number.isFinite(v) && v > 0) ||
      this.settings.bot_max_seconds < this.settings.bot_min_seconds) throw new Error("invalid_order_duel_settings");
    if (this.tiers.length !== 10 || data.rewards.length !== 10 || this.tiers.some((r, i) => r.tier !== i + 1 ||
      ![r.required_points, r.stamina, r.spirit_stones].every(Number.isSafeInteger) || r.required_points <= (this.tiers[i - 1]?.required_points ?? 0) ||
      r.stamina < 0 || r.spirit_stones < 0 || r.stamina + r.spirit_stones <= 0)) throw new Error("invalid_order_duel_rewards");
    for (const value of [this.activity.start_time, this.activity.end_time]) {
      if (value && !Number.isFinite(Date.parse(value))) throw new Error("invalid_order_duel_dates");
    }
    if (this.activity.start_time && this.activity.end_time && Date.parse(this.activity.start_time) >= Date.parse(this.activity.end_time)) throw new Error("invalid_order_duel_dates");
  }

  active(now = Date.now()): boolean {
    return !!this.activity && this.activity.enabled !== false && (!this.activity.start_time || now >= Date.parse(this.activity.start_time)) &&
      (!this.activity.end_time || now < Date.parse(this.activity.end_time));
  }

  progress(state: GameState): DuelProgress {
    if (state.order_duel_progress?.event_id !== this.eventId) {
      state.order_duel_progress = { event_id: this.eventId, round: 0, victory_points: 0, claimed_tiers: [],
        status: "resting", order_points: 0, last_order_at: 0 };
    }
    return state.order_duel_progress;
  }

  orderPoints(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.max(1, Math.floor(value * this.settings.order_points_ratio + 1e-9)) : 0;
  }

  awardOrderPoints(state: GameState, value: number, now = Date.now()): void {
    if (!activitiesUnlocked(state) || !this.active(now)) return;
    const p = this.progress(state);
    if (p.status !== "playing" || !p.match_id) return;
    p.order_points = Math.min(this.settings.target_points, p.order_points + this.orderPoints(value));
    p.last_order_at = now;
  }

  private async update(storage: IStorage, mutate: (r: DuelRegistry) => void | Promise<void>): Promise<DuelRegistry> {
    for (let attempt = 0; attempt < 8; attempt++) {
      const r = await storage.loadOrderDuel(this.eventId) ?? { event_id: this.eventId, revision: 0, tickets: {}, matches: {} };
      const before = JSON.stringify(r);
      await mutate(r);
      if (before === JSON.stringify(r)) return r;
      try { await storage.saveOrderDuel(r); return r; }
      catch (e) { if (!(e instanceof Error && e.message === "state_conflict")) throw e; }
    }
    throw new Error("state_conflict");
  }

  private botPoints(match: DuelMatch, now: number): number {
    return Math.min(this.settings.target_points, Math.floor(Math.max(0, now - match.started_at) / match.bot_interval_ms) * this.orderPoints(this.settings.bot_order_value));
  }

  /** Match only explicit entrants. A ticket remains until its durable settlement is acknowledged. */
  async refresh(storage: IStorage, userId: string, state: GameState, apply: (r: RewardConfig) => unknown, now = Date.now()): Promise<Record<string, any>> {
    if (!activitiesUnlocked(state) || !this.activity) return { status: "locked" };
    const p = this.progress(state);
    const before = JSON.stringify(p);
    const active = this.active(now);
    let registry = await this.update(storage, async r => {
      let ticket = r.tickets[userId];
      // A saved payout is acknowledged on retry, even if the prior request failed after saving it.
      if (ticket?.match_id && p.last_result?.match_id === ticket.match_id) {
        const finished = r.matches[ticket.match_id];
        delete r.tickets[userId];
        if (p.last_result.won && active) r.tickets[userId] = { realm: state.cultivation.current_level, queued_at: now };
        if (finished && finished.players.every(id => id.startsWith("bot:") || r.tickets[id]?.match_id !== finished.id)) delete r.matches[finished.id];
        ticket = r.tickets[userId];
      }
      if (!active) {
        if (!ticket?.match_id) { delete r.tickets[userId]; return; }
      }
      if (!ticket && p.status === "matching") {
        ticket = r.tickets[userId] = { realm: state.cultivation.current_level, queued_at: now };
      }
      if (!ticket) return;
      if (!ticket.match_id) {
        const waitMs = this.settings.matchmaking_seconds * 1000;
        const candidates = now - ticket.queued_at < waitMs ? Object.keys(r.tickets).filter(id => id !== userId &&
          !r.tickets[id].match_id && r.tickets[id].realm === ticket.realm && now - r.tickets[id].queued_at < waitMs) : [];
        const other = candidates[Math.floor(Math.random() * candidates.length)];
        if (other || now - ticket.queued_at >= this.settings.matchmaking_seconds * 1000) {
          const id = crypto.randomUUID();
          const players = [userId, other ?? `bot:${id}`];
          const started = other ? now : ticket.queued_at + this.settings.matchmaking_seconds * 1000;
          r.matches[id] = { id, players, started_at: started, points: Object.fromEntries(players.map(id => [id, 0])),
            bot_interval_ms: Math.round((this.settings.bot_min_seconds + Math.random() * (this.settings.bot_max_seconds - this.settings.bot_min_seconds)) * 1000) };
          ticket.match_id = id;
          if (other) r.tickets[other].match_id = id;
        }
      }
      if (!ticket.match_id) return;
      const match = r.matches[ticket.match_id];
      if (!match || match.winner) return;
      // Recover both durable outboxes, including an opponent whose publication response was lost.
      const reached: { id: string; at: number }[] = [];
      for (const id of match.players.filter(id => !id.startsWith("bot:"))) {
        const player = id === userId ? p : (await storage.loadState(id))?.order_duel_progress;
        if (player?.event_id === this.eventId && player.match_id === match.id) {
          match.points[id] = Math.max(match.points[id], player.order_points);
          if (match.points[id] >= this.settings.target_points) reached.push({ id, at: player.last_order_at });
        }
      }
      const bot = match.players.find(id => id.startsWith("bot:"));
      if (bot) {
        const cutoff = this.activity?.end_time ? Math.min(now, Date.parse(this.activity.end_time)) : now;
        if (active || (this.activity?.enabled !== false && this.activity?.end_time && now >= Date.parse(this.activity.end_time))) {
          match.points[bot] = this.botPoints(match, cutoff);
        }
        const botFinish = match.started_at + Math.ceil(this.settings.target_points / this.orderPoints(this.settings.bot_order_value)) * match.bot_interval_ms;
        if (match.points[bot] >= this.settings.target_points) reached.push({ id: bot, at: botFinish });
      }
      reached.sort((a, b) => a.at - b.at || match.players.indexOf(a.id) - match.players.indexOf(b.id));
      if (reached.length) { match.winner = reached[0].id; match.ended_at = reached[0].at; }
      if (!active && !match.winner) {
        delete r.tickets[userId];
        if (match.players.every(id => id.startsWith("bot:") || r.tickets[id]?.match_id !== match.id)) delete r.matches[match.id];
      }
    });
    let ticket = registry.tickets[userId];
    let match = ticket?.match_id ? registry.matches[ticket.match_id] : undefined;
    if (match?.winner && p.last_result?.match_id !== match.id) {
      const won = match.winner === userId;
      const opponent = match.players.find(id => id !== userId)!;
      p.last_result = { match_id: match.id, won, my_points: match.points[userId], opponent_points: match.points[opponent],
        stamina: won ? this.settings.win_stamina : 0, victory_points: won ? this.settings.win_points : 0 };
      p.status = won && active ? "matching" : won ? "resting" : "lost";
      p.victory_points += p.last_result.victory_points;
      if (won && active) p.round++;
      p.match_id = undefined; p.order_points = 0;
      if (won) apply({ tokens: [{ token: 3, amount: this.settings.win_stamina }] });
      // Balance and receipt are one CAS write. Registry acknowledgement must follow it.
      await storage.saveState(userId, state);
      return this.refresh(storage, userId, state, apply, now);
    }
    if (ticket) {
      if (p.match_id !== ticket.match_id) { p.order_points = 0; p.last_order_at = 0; }
      p.match_id = ticket.match_id;
      p.status = match ? "playing" : "matching";
    } else if (p.status !== "lost") { p.status = "resting"; p.match_id = undefined; p.order_points = 0; }
    if (before !== JSON.stringify(p)) await storage.saveState(userId, state);
    return this.view(state, registry, userId, now);
  }

  async start(storage: IStorage, userId: string, state: GameState, expectedRound: number, apply: (r: RewardConfig) => unknown, now = Date.now()) {
    if (!activitiesUnlocked(state) || !this.active(now)) return { error: "activity_inactive" };
    const p = this.progress(state);
    if (p.round !== expectedRound) return { error: "state_conflict" };
    if (p.status === "resting" || p.status === "lost") {
      p.round++; p.status = "matching";
      await storage.saveState(userId, state);
    }
    return this.refresh(storage, userId, state, apply, now);
  }

  async rest(storage: IStorage, userId: string, state: GameState, expectedRound: number) {
    if (!activitiesUnlocked(state) || !this.activity) return { error: "activity_inactive" };
    const p = this.progress(state);
    if (p.round !== expectedRound || !["lost", "resting"].includes(p.status)) return { error: "state_conflict" };
    p.status = "resting";
    await storage.saveState(userId, state);
    return this.view(state, await storage.loadOrderDuel(this.eventId), userId);
  }

  async claim(storage: IStorage, userId: string, state: GameState, tier: number, apply: (r: RewardConfig) => unknown) {
    if (!activitiesUnlocked(state) || !this.activity) return { error: "activity_inactive" };
    const p = this.progress(state), reward = this.tiers.find(r => r.tier === tier);
    if (!reward) return { error: "invalid_params" };
    if (p.victory_points < reward.required_points) return { error: "insufficient_points" };
    if (!p.claimed_tiers.includes(tier)) {
      apply({ tokens: [{ token: 3, amount: reward.stamina }, { token: 1, amount: reward.spirit_stones }] });
      p.claimed_tiers.push(tier);
      await storage.saveState(userId, state);
    }
    return this.view(state, await storage.loadOrderDuel(this.eventId), userId);
  }

  private view(state: GameState, registry: DuelRegistry | null, userId: string, now = Date.now()) {
    const p = this.progress(state), ticket = registry?.tickets[userId];
    const m = ticket?.match_id ? registry?.matches[ticket.match_id] : undefined;
    const other = m?.players.find(id => id !== userId);
    return { ...p, active: this.active(now), activity_id: this.activity?.id, server_now: now,
      registry_revision: registry?.revision ?? 0,
      settings: this.settings, rewards: this.tiers, queued_at: ticket?.queued_at ?? 0,
      opponent: other ? { name: other.startsWith("bot:") ? "云岫 · 机器人" : "对战道友", bot: other.startsWith("bot:"), points: m!.points[other] } : null,
      my_points: m?.points[userId] ?? 0 };
  }
}
