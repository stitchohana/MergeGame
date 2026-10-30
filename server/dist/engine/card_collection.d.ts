import type { ActivityDef, GameState, RewardConfig } from "../storage/interface";
export interface CollectionDef {
    collection_id: number;
    activity_id: number;
    name: string;
    duplicate_points_by_star?: number[];
    exchange_pack_id?: number;
    exchange_cost?: number;
}
export interface CardSetDef {
    set_id: number;
    collection_id: number;
    name: string;
    rewards: RewardConfig;
}
export interface CardDef {
    card_id: number;
    set_id: number;
    name: string;
    star: number;
    icon: string;
}
export interface PackDef {
    pack_id: number;
    collection_id: number;
    name: string;
    star: number;
    icon: string;
    card_count: number;
    normal_weights: number[];
}
export interface SourceReward {
    collection_id: number;
    source_type: "order" | "circulation";
    source_id?: number;
    min_value: number;
    pack_id: number;
    count: number;
    enabled: boolean;
}
export interface CardCollectionConfig {
    collections: CollectionDef[];
    card_sets: CardSetDef[];
    cards: CardDef[];
    packs: PackDef[];
    source_rewards: SourceReward[];
}
export interface DrawnCard {
    card_id: number;
    star: number;
    is_new: boolean;
    count: number;
    gained?: number;
    duplicate_points?: number;
}
export interface CardOperationResult {
    ok: true;
    collection_id: number;
    pack_id?: number;
    set_id?: number;
    cards?: DrawnCard[];
    rewards?: RewardConfig;
    opened_packs?: number;
    completed_sets?: {
        collection_id: number;
        set_id: number;
    }[];
    duplicate_points_gained?: number;
    exchanged?: boolean;
    points_spent?: number;
}
export interface CollectionProgress {
    cards: Record<number, number>;
    claimed_sets: number[];
    opened_count: number;
    duplicate_points: number;
    total_duplicate_points: number;
    exchange_count: number;
    last_open?: CardOperationResult;
}
type Failure = {
    ok: false;
    reason: string;
};
export declare class CardCollectionService {
    private activities;
    private random;
    private applySetRewards?;
    readonly config: CardCollectionConfig;
    private packItems;
    static readonly EFFECT_TYPE = 9;
    constructor(data: unknown, activities: ActivityDef[], random?: () => number, applySetRewards?: ((state: GameState, rewards: RewardConfig) => RewardConfig) | undefined);
    private validate;
    bindPackItems(items: {
        id: number;
        name: string;
        icon: string;
        type: number;
        effect_type?: number;
        effect_value?: number;
    }[]): void;
    getSourceRewardConfig(source: SourceReward["source_type"], sourceId: number, value: number): RewardConfig;
    private sourceRules;
    awardPack(state: GameState, packId: number, count: number): void;
    isActive(id: number, now?: number): boolean;
    ensureProgress(state: GameState): Record<number, CollectionProgress>;
    publicProgress(state: GameState): {
        [k: string]: {
            revision: number;
            cards: Record<number, number>;
            claimed_sets: number[];
            opened_count: number;
            last_open: CardOperationResult | undefined;
            duplicate_points: number;
            total_duplicate_points: number;
            exchange_count: number;
        };
    };
    awardSource(state: GameState, source: SourceReward["source_type"], sourceId: number, value: number): void;
    private pool;
    private roll;
    private drawPack;
    openPending(state: GameState, collectionId: number, selectedUid: number, openAll: boolean, requestId: string, expectedOpened: number): CardOperationResult | Failure;
    exchange(state: GameState, collectionId: number, requestId: string, expectedExchange: number): CardOperationResult | Failure;
}
export {};
