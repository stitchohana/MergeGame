import type { ActivityDef, GameState, RewardConfig } from "../storage/interface";

export interface CollectionDef { collection_id: number; activity_id: number; name: string }
export interface CardSetDef { set_id: number; collection_id: number; name: string; rewards: RewardConfig }
export interface CardDef { card_id: number; set_id: number; name: string; star: number; icon: string }
export interface PackDef { pack_id: number; collection_id: number; name: string; star: number; icon: string; card_count: number; normal_weights: number[] }
export interface SourceReward { collection_id: number; source_type: "quest" | "order" | "circulation"; source_id?: number; min_value: number; pack_id: number; count: number; enabled: boolean }
export interface CardCollectionConfig { collections: CollectionDef[]; card_sets: CardSetDef[]; cards: CardDef[]; packs: PackDef[]; source_rewards: SourceReward[] }
export interface DrawnCard { card_id: number; star: number; is_new: boolean; count: number }
export interface CardOperationResult { ok: true; collection_id: number; pack_id?: number; set_id?: number; cards?: DrawnCard[]; rewards?: RewardConfig }
export interface CollectionProgress {
  packs: Record<number, number>;
  cards: Record<number, number>;
  claimed_sets: number[];
  opened_count: number;
  last_open?: CardOperationResult;
  recent_operations: { request_id: string; signature: string; result: CardOperationResult }[];
}
type Failure = { ok: false; reason: string };
const positive = (value: number) => Number.isSafeInteger(value) && value > 0;

export class CardCollectionService {
  readonly config: CardCollectionConfig;
  constructor(data: unknown, private activities: ActivityDef[], private random: () => number = Math.random) {
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
    for (const c of collections) require(this.activities.some(a => a.id === c.activity_id), "unknown activity");
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
      require(["quest", "order", "circulation"].includes(r.source_type) && typeof r.enabled === "boolean", "invalid source");
      require(packs.some(p => p.pack_id === r.pack_id && p.collection_id === r.collection_id) && positive(r.count), "invalid source pack");
      require(Number.isSafeInteger(r.min_value) && r.min_value >= 0 && (r.source_id === undefined || Number.isSafeInteger(r.source_id) && r.source_id >= 0), "invalid source threshold");
      const key = `${r.collection_id}:${r.source_type}:${r.source_id ?? "*"}:${r.min_value}`;
      require(!rules.has(key), "duplicate source rule"); rules.add(key);
    }
  }

  isActive(id: number, now = Date.now()): boolean {
    const collection = this.config.collections.find(c => c.collection_id === id);
    const a = this.activities.find(a => a.id === collection?.activity_id);
    return !!a && a.enabled !== false && (!a.start_time || now >= Date.parse(a.start_time)) && (!a.end_time || now < Date.parse(a.end_time));
  }

  ensureProgress(state: GameState): Record<number, CollectionProgress> {
    state.card_collection_progress ??= {};
    for (const c of this.config.collections) state.card_collection_progress[c.collection_id] ??= { packs: {}, cards: {}, claimed_sets: [], opened_count: 0, recent_operations: [] };
    return state.card_collection_progress;
  }

  publicProgress(state: GameState) {
    return Object.fromEntries(Object.entries(this.ensureProgress(state)).map(([id, p]) => [id, { revision: state.storage_revision ?? 0, packs: p.packs, cards: p.cards, claimed_sets: p.claimed_sets, opened_count: p.opened_count, last_open: p.last_open }]));
  }

  awardSource(state: GameState, source: SourceReward["source_type"], sourceId: number, value: number): void {
    for (const c of this.config.collections) {
      if (!this.isActive(c.collection_id)) continue;
      const rules = this.config.source_rewards.filter(r => r.collection_id === c.collection_id && r.source_type === source && r.min_value <= value);
      const specific = rules.filter(r => r.source_id === sourceId);
      const rule = (specific.length ? specific : rules.filter(r => r.source_id === undefined)).sort((a, b) => b.min_value - a.min_value)[0];
      if (!rule || !rule.enabled) continue;
      const p = this.ensureProgress(state)[c.collection_id];
      p.packs[rule.pack_id] = (p.packs[rule.pack_id] ?? 0) + rule.count;
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

  private replay(p: CollectionProgress, requestId: string, signature: string): CardOperationResult | Failure | undefined {
    const previous = p.recent_operations.find(r => r.request_id === requestId);
    return previous ? (previous.signature === signature ? structuredClone(previous.result) : { ok: false, reason: "request_mismatch" }) : undefined;
  }

  private remember(p: CollectionProgress, requestId: string, signature: string, result: CardOperationResult): CardOperationResult {
    p.recent_operations.push({ request_id: requestId, signature, result: structuredClone(result) });
    p.recent_operations = p.recent_operations.slice(-32);
    return result;
  }

  open(state: GameState, collectionId: number, packId: number, requestId: string, expectedOpened: number): CardOperationResult | Failure {
    if (!requestId || requestId.length > 100 || !Number.isSafeInteger(expectedOpened) || expectedOpened < 0) return { ok: false, reason: "invalid_params" };
    const pack = this.config.packs.find(p => p.pack_id === packId && p.collection_id === collectionId);
    if (!pack) return { ok: false, reason: "pack_not_found" };
    const p = this.ensureProgress(state)[collectionId];
    const signature = `open:${packId}:${expectedOpened}`;
    const replay = this.replay(p, requestId, signature);
    if (replay) return replay;
    if (!this.isActive(collectionId)) return { ok: false, reason: "activity_inactive" };
    if (expectedOpened !== p.opened_count) return { ok: false, reason: "state_conflict" };
    if (!(p.packs[packId] > 0)) return { ok: false, reason: "insufficient_packs" };
    // Draw everything before mutating inventory. The first slot is EXACTLY the pack's star.
    const drawn: CardDef[] = [];
    for (let i = 0; i < pack.card_count; i++) {
      let star = pack.star;
      if (i > 0) {
        let ticket = this.roll() * pack.normal_weights.reduce((a, b) => a + b, 0);
        star = 5;
        for (let j = 0; j < 5; j++) { ticket -= pack.normal_weights[j]; if (ticket < 0) { star = j + 1; break; } }
      }
      const pool = this.pool(collectionId, star);
      drawn.push(pool[Math.floor(this.roll() * pool.length)]);
    }
    const cards = drawn.map(card => {
      const count = (p.cards[card.card_id] ?? 0) + 1;
      p.cards[card.card_id] = count;
      return { card_id: card.card_id, star: card.star, is_new: count === 1, count };
    });
    p.packs[packId]--; p.opened_count++; state.version++;
    p.last_open = { ok: true, collection_id: collectionId, pack_id: packId, cards };
    return this.remember(p, requestId, signature, p.last_open);
  }

  claim(state: GameState, collectionId: number, setId: number, requestId: string, apply: (reward: RewardConfig) => RewardConfig): CardOperationResult | Failure {
    if (!requestId || requestId.length > 100) return { ok: false, reason: "invalid_params" };
    const set = this.config.card_sets.find(s => s.set_id === setId && s.collection_id === collectionId);
    if (!set) return { ok: false, reason: "set_not_found" };
    const p = this.ensureProgress(state)[collectionId];
    const signature = `claim:${setId}`;
    const replay = this.replay(p, requestId, signature);
    if (replay) return replay;
    if (!this.isActive(collectionId)) return { ok: false, reason: "activity_inactive" };
    if (p.claimed_sets.includes(setId)) return { ok: false, reason: "already_claimed" };
    if (!this.config.cards.filter(c => c.set_id === setId).every(c => p.cards[c.card_id] > 0)) return { ok: false, reason: "set_incomplete" };
    const rewards = apply(set.rewards);
    p.claimed_sets.push(setId); state.version++;
    return this.remember(p, requestId, signature, { ok: true, collection_id: collectionId, set_id: setId, rewards });
  }
}
