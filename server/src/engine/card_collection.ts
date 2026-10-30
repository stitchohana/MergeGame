import type { ActivityDef, GameState, RewardConfig } from "../storage/interface";
import { activitiesUnlocked } from "./activity_access";

export interface CollectionDef { collection_id: number; activity_id: number; name: string; duplicate_points_by_star?: number[]; exchange_pack_id?: number; exchange_cost?: number }
export interface CardSetDef { set_id: number; collection_id: number; name: string; rewards: RewardConfig }
export interface CardDef { card_id: number; set_id: number; name: string; star: number; icon: string }
export interface PackDef { pack_id: number; collection_id: number; name: string; star: number; icon: string; card_count: number; normal_weights: number[] }
export interface SourceReward { collection_id: number; source_type: "order" | "circulation"; source_id?: number; min_value: number; pack_id: number; count: number; enabled: boolean }
export interface CardCollectionConfig { collections: CollectionDef[]; card_sets: CardSetDef[]; cards: CardDef[]; packs: PackDef[]; source_rewards: SourceReward[] }
export interface DrawnCard { card_id: number; star: number; is_new: boolean; count: number; gained?: number; duplicate_points?: number }
export interface CardOperationResult { ok: true; collection_id: number; pack_id?: number; set_id?: number; cards?: DrawnCard[]; rewards?: RewardConfig; opened_packs?: number; completed_sets?: { collection_id: number; set_id: number }[]; duplicate_points_gained?: number; exchanged?: boolean; points_spent?: number }
export interface CollectionProgress {
  cards: Record<number, number>;
  claimed_sets: number[];
  opened_count: number;
  duplicate_points: number;
  total_duplicate_points: number;
  exchange_count: number;
  last_open?: CardOperationResult;
}
type Failure = { ok: false; reason: string };
const positive = (value: number) => Number.isSafeInteger(value) && value > 0;

export class CardCollectionService {
  readonly config: CardCollectionConfig;
  private packItems = new Map<number, { id: number; name: string; icon: string }>();
  static readonly EFFECT_TYPE = 9;
  constructor(data: unknown, private activities: ActivityDef[], private random: () => number = Math.random,
    private applySetRewards?: (state: GameState, rewards: RewardConfig) => RewardConfig) {
    this.config = structuredClone((data ?? { collections: [], card_sets: [], cards: [], packs: [], source_rewards: [] }) as CardCollectionConfig);
    this.validate();
  }

  private validate(): void {
    const { collections, card_sets, cards, packs, source_rewards } = this.config;
    const require = (ok: boolean, message: string) => { if (!ok) throw new Error(`card_collection: ${message}`); };
    for (const [rows, key] of [[collections, "collection_id"], [card_sets, "set_id"], [cards, "card_id"], [packs, "pack_id"]] as const) {
      const ids = rows.map(row => (row as unknown as Record<string, number>)[key]);
      require(ids.every(positive) && new Set(ids).size === ids.length, `invalid/duplicate ${key}`);
    }
    for (const c of collections) {
      require(this.activities.some(a => a.id === c.activity_id), "unknown activity");
      c.duplicate_points_by_star ??= [1, 2, 3, 4, 5];
      require(Array.isArray(c.duplicate_points_by_star) && c.duplicate_points_by_star.length === 5 && c.duplicate_points_by_star.every(positive), "invalid duplicate points");
      c.exchange_cost ??= 200;
      c.exchange_pack_id ??= packs.find(p => p.collection_id === c.collection_id && p.star === 5)?.pack_id;
      require(positive(c.exchange_cost), "invalid exchange cost");
      if (c.exchange_pack_id !== undefined) require(packs.some(p => p.pack_id === c.exchange_pack_id && p.collection_id === c.collection_id && p.star === 5), "invalid exchange pack");
    }
    for (const s of card_sets) {
      require(collections.some(c => c.collection_id === s.collection_id), "unknown collection");
      require(cards.some(c => c.set_id === s.set_id), "empty set");
      require(!!s.rewards?.tokens?.length && !s.rewards.items?.length && s.rewards.tokens.every(t => [1, 3].includes(t.token) && positive(t.amount)), "invalid set rewards");
    }
    for (const c of cards) require(card_sets.some(s => s.set_id === c.set_id) && positive(c.star) && c.star <= 5, "invalid card");
    for (const p of packs) {
      require(collections.some(c => c.collection_id === p.collection_id), "unknown pack collection");
      require(positive(p.star) && p.star <= 5 && positive(p.card_count) && p.card_count <= 100, "invalid pack");
      require(this.pool(p.collection_id, p.star).length > 0, "empty guaranteed pool");
      if (p.card_count > 1) {
        require(Array.isArray(p.normal_weights) && p.normal_weights.length === 5 && p.normal_weights.every(w => Number.isFinite(w) && w >= 0) && Number.isFinite(p.normal_weights.reduce((a, b) => a + b, 0)) && p.normal_weights.reduce((a, b) => a + b, 0) > 0, "invalid weights");
        p.normal_weights.forEach((w, index) => require(w === 0 || this.pool(p.collection_id, index + 1).length > 0, "empty weighted pool"));
      }
    }
    const rules = new Set<string>();
    for (const r of source_rewards) {
      require(["order", "circulation"].includes(r.source_type) && typeof r.enabled === "boolean", "invalid source");
      require(packs.some(p => p.pack_id === r.pack_id && p.collection_id === r.collection_id) && positive(r.count), "invalid source pack");
      require(Number.isSafeInteger(r.min_value) && r.min_value >= 0 && (r.source_id === undefined || Number.isSafeInteger(r.source_id) && r.source_id >= 0), "invalid source threshold");
      const key = `${r.collection_id}:${r.source_type}:${r.source_id ?? "*"}:${r.min_value}`;
      require(!rules.has(key), "duplicate source rule"); rules.add(key);
    }
  }

  bindPackItems(items: { id: number; name: string; icon: string; type: number; effect_type?: number; effect_value?: number }[]): void {
    const mapping = new Map<number, { id: number; name: string; icon: string }>();
    for (const item of items) {
      if (item.type !== 5 || item.effect_type !== CardCollectionService.EFFECT_TYPE) continue;
      const packId = item.effect_value!;
      if (!this.config.packs.some(p => p.pack_id === packId) || mapping.has(packId)) {
        throw new Error(`card_collection: invalid/duplicate pack effect item ${item.id}`);
      }
      mapping.set(packId, item);
    }
    for (const pack of this.config.packs) {
      if (!mapping.has(pack.pack_id)) throw new Error(`card_collection: missing effect item for pack ${pack.pack_id}`);
    }
    this.packItems = mapping;
  }

  getSourceRewardConfig(source: SourceReward["source_type"], sourceId: number, value: number): RewardConfig {
    return { items: this.sourceRules(source, sourceId, value).map(rule => ({
      id: this.packItems.get(rule.pack_id)?.id ?? rule.pack_id,
      count: rule.count,
    })) };
  }

  private sourceRules(source: SourceReward["source_type"], sourceId: number, value: number): SourceReward[] {
    const selected: SourceReward[] = [];
    for (const collection of this.config.collections) {
      if (!this.isActive(collection.collection_id)) continue;
      const rules = this.config.source_rewards.filter(rule =>
        rule.collection_id === collection.collection_id && rule.source_type === source && rule.min_value <= value,
      );
      const specific = rules.filter(rule => rule.source_id === sourceId);
      const rule = (specific.length ? specific : rules.filter(rule => rule.source_id === undefined))
        .sort((a, b) => b.min_value - a.min_value)[0];
      if (rule?.enabled) selected.push(rule);
    }
    return selected;
  }

  awardPack(state: GameState, packId: number, count: number): void {
    if (!activitiesUnlocked(state)) return;
    const pack = this.config.packs.find(p => p.pack_id === packId);
    if (!pack || !positive(count)) throw new Error("card_collection: invalid pack reward");
    const item = this.packItems.get(packId);
    for (let i = 0; i < count; i++) {
      state.uid_counter = state.uid_counter + 1;
      state.pending_rewards.push({ uid: state.uid_counter, id: item?.id ?? pack.pack_id, name: item?.name ?? pack.name, kind: "card_pack", collection_id: pack.collection_id, pack_id: packId, icon: item?.icon || pack.icon });
    }
  }

  isActive(id: number, now = Date.now()): boolean {
    const collection = this.config.collections.find(c => c.collection_id === id);
    const a = this.activities.find(a => a.id === collection?.activity_id);
    return !!a && a.enabled !== false && (!a.start_time || now >= Date.parse(a.start_time)) && (!a.end_time || now < Date.parse(a.end_time));
  }

  ensureProgress(state: GameState): Record<number, CollectionProgress> {
    state.card_collection_progress ??= {};
    for (const c of this.config.collections) state.card_collection_progress[c.collection_id] ??= { cards: {}, claimed_sets: [], opened_count: 0, duplicate_points: 0, total_duplicate_points: 0, exchange_count: 0 };
    return state.card_collection_progress;
  }

  publicProgress(state: GameState) {
    if (!activitiesUnlocked(state)) return {};
    return Object.fromEntries(Object.entries(this.ensureProgress(state)).map(([id, p]) => [id, { revision: state.storage_revision, cards: p.cards, claimed_sets: p.claimed_sets, opened_count: p.opened_count, last_open: p.last_open, duplicate_points: p.duplicate_points, total_duplicate_points: p.total_duplicate_points, exchange_count: p.exchange_count }]));
  }

  awardSource(state: GameState, source: SourceReward["source_type"], sourceId: number, value: number): void {
    if (!activitiesUnlocked(state)) return;
    for (const rule of this.sourceRules(source, sourceId, value)) {
      this.awardPack(state, rule.pack_id, rule.count);
    }
  }

  private pool(collectionId: number, star: number): CardDef[] {
    const sets = this.config.card_sets.filter(s => s.collection_id === collectionId).map(s => s.set_id);
    return this.config.cards.filter(c => c.star === star && sets.includes(c.set_id));
  }

  private roll(): number {
    const value = this.random();
    if (!Number.isFinite(value) || value < 0 || value >= 1) throw new Error("invalid_random_value");
    return value;
  }

  private drawPack(collectionId: number, pack: PackDef, p: CollectionProgress): DrawnCard[] {
    const drawn: CardDef[] = [];
    for (let i = 0; i < pack.card_count; i++) {
      // First slot guarantees exactly the pack star, regardless of normal slot weights.
      let star = pack.star;
      if (i > 0) {
        let ticket = this.roll() * pack.normal_weights.reduce((a, b) => a + b, 0);
        star = 5;
        for (let j = 0; j < 5; j++) { ticket -= pack.normal_weights[j]; if (ticket < 0) { star = j + 1; break; } }
      }
      const pool = this.pool(collectionId, star);
      drawn.push(pool[Math.floor(this.roll() * pool.length)]);
    }
    return drawn.map(card => {
      const count = (p.cards[card.card_id] ?? 0) + 1;
      const points = count > 1 ? this.config.collections.find(c => c.collection_id === collectionId)!.duplicate_points_by_star![card.star - 1] : 0;
      p.duplicate_points += points;
      p.total_duplicate_points += points;
      p.cards[card.card_id] = count;
      return { card_id: card.card_id, star: card.star, is_new: count === 1, count, duplicate_points: points };
    });
  }

  openPending(state: GameState, collectionId: number, selectedUid: number, openAll: boolean, requestId: string, expectedOpened: number): CardOperationResult | Failure {
    if (!activitiesUnlocked(state)) return { ok: false, reason: "activity_locked" };
    if (!requestId?.trim() || requestId.length > 100 || !positive(selectedUid) || !Number.isSafeInteger(expectedOpened) || expectedOpened < 0) return { ok: false, reason: "invalid_params" };
    const p = this.ensureProgress(state)[collectionId];
    if (!p) return { ok: false, reason: "pack_not_found" };
    const signature = `pending-open:${collectionId}:${selectedUid}:${openAll}:${expectedOpened}`;
    const receipts = state.card_pack_operations ?? [];
    const previous = receipts.find(r => r.request_id === requestId);
    if (previous) return previous.signature === signature ? structuredClone(previous.result) : { ok: false, reason: "request_mismatch" };
    if (expectedOpened !== p.opened_count) return { ok: false, reason: "state_conflict" };
    const pending = state.pending_rewards;
    // Even all-open is anchored to the selected UID, so an evicted retry cannot spend newly awarded packs.
    if (!pending.some(r => r.kind === "card_pack" && r.uid === selectedUid && r.collection_id === collectionId)) return { ok: false, reason: "pack_not_found" };
    const candidates = pending.filter(r => r.kind === "card_pack" && (openAll || r.uid === selectedUid));
    const packs: PackDef[] = [];
    for (const reward of candidates) {
      const pack = this.config.packs.find(item => item.collection_id === reward.collection_id && item.pack_id === reward.pack_id);
      if (!pack) return { ok: false, reason: "pack_not_found" };
      if (!this.isActive(pack.collection_id)) return { ok: false, reason: "activity_inactive" };
      packs.push(pack);
    }
    // Work on a copy until every draw succeeds. Neither invalid data nor RNG failure can partially consume rewards.
    const progress = structuredClone(state.card_collection_progress!);
    const aggregated = new Map<number, DrawnCard>();
    packs.forEach(pack => {
      const current = progress[pack.collection_id];
      const cards = this.drawPack(pack.collection_id, pack, current);
      for (const card of cards) {
        const prior = aggregated.get(card.card_id);
        aggregated.set(card.card_id, { ...card, gained: (prior?.gained ?? 0) + 1, is_new: card.is_new || !!prior?.is_new, duplicate_points: (prior?.duplicate_points ?? 0) + (card.duplicate_points ?? 0) });
      }
      current.opened_count++;
    });
    const completedSets = this.config.card_sets.filter(set => {
      const current = progress[set.collection_id];
      return this.isActive(set.collection_id) && !current.claimed_sets.includes(set.set_id)
        && this.config.cards.filter(card => card.set_id === set.set_id).every(card => current.cards[card.card_id] > 0);
    });
    const tokens = new Map<number, number>();
    for (const set of completedSets) {
      for (const token of set.rewards.tokens ?? []) tokens.set(token.token, (tokens.get(token.token) ?? 0) + token.amount);
      progress[set.collection_id].claimed_sets.push(set.set_id);
    }
    let rewardedState: GameState | undefined;
    let rewards: RewardConfig | undefined;
    if (completedSets.length) {
      if (!this.applySetRewards) throw new Error("card_collection: missing set reward handler");
      // Reward failures must leave the original cards, packs and currencies intact.
      rewardedState = structuredClone(state);
      rewardedState.card_collection_progress = progress;
      rewards = this.applySetRewards(rewardedState, { tokens: [...tokens].map(([token, amount]) => ({ token, amount })) });
    }
    const result: CardOperationResult = { ok: true, collection_id: collectionId, pack_id: packs.length === 1 ? packs[0].pack_id : undefined, cards: [...aggregated.values()], opened_packs: packs.length,
      duplicate_points_gained: [...aggregated.values()].reduce((sum, card) => sum + (card.duplicate_points ?? 0), 0),
      ...(completedSets.length ? { rewards, completed_sets: completedSets.map(set => ({ collection_id: set.collection_id, set_id: set.set_id })) } : {}) };
    for (const pack of packs) progress[pack.collection_id].last_open = result;
    if (rewardedState) {
      const originalProgress = state.card_collection_progress!;
      Object.assign(state, rewardedState);
      state.card_collection_progress = originalProgress;
    }
    const remove = new Set(candidates.map(r => r.uid));
    state.pending_rewards = pending.filter(r => !remove.has(r.uid));
    // Preserve progress object references used by other engine services.
    for (const [id, updated] of Object.entries(progress)) Object.assign(state.card_collection_progress![Number(id)], updated);
    state.card_pack_operations = [...receipts, { request_id: requestId, signature, result: structuredClone(result) }].slice(-32);
    state.version++;
    return result;
  }

  exchange(state: GameState, collectionId: number, requestId: string, expectedExchange: number): CardOperationResult | Failure {
    if (!activitiesUnlocked(state)) return { ok: false, reason: "activity_locked" };
    if (!positive(collectionId) || !requestId?.trim() || requestId.length > 100 || !Number.isSafeInteger(expectedExchange) || expectedExchange < 0) return { ok: false, reason: "invalid_params" };
    const collection = this.config.collections.find(c => c.collection_id === collectionId);
    if (!collection?.exchange_pack_id) return { ok: false, reason: "exchange_unavailable" };
    const p = this.ensureProgress(state)[collectionId];
    const signature = `exchange:${collectionId}:${expectedExchange}`;
    const receipts = state.card_pack_operations ?? [];
    const previous = receipts.find(r => r.request_id === requestId);
    if (previous) return previous.signature === signature ? structuredClone(previous.result) : { ok: false, reason: "request_mismatch" };
    if (!this.isActive(collectionId)) return { ok: false, reason: "activity_inactive" };
    if (expectedExchange !== p.exchange_count) return { ok: false, reason: "state_conflict" };
    const cost = collection.exchange_cost!;
    if (p.duplicate_points! < cost) return { ok: false, reason: "insufficient_points" };
    // Queue insertion, points and replay marker commit together; awarding failure leaves the original intact.
    const working = structuredClone(state);
    const next = working.card_collection_progress![collectionId];
    next.duplicate_points! -= cost;
    next.exchange_count!++;
    this.awardPack(working, collection.exchange_pack_id, 1);
    const result: CardOperationResult = { ok: true, collection_id: collectionId, pack_id: collection.exchange_pack_id, exchanged: true, points_spent: cost };
    working.card_pack_operations = [...receipts, { request_id: requestId, signature, result: structuredClone(result) }].slice(-32);
    working.version++;
    const originalProgress = state.card_collection_progress!;
    Object.assign(p, next);
    Object.assign(state, working);
    state.card_collection_progress = originalProgress;
    return result;
  }
}
