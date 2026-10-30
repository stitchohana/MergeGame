import type { ActivityDef, GameState, IStorage, RewardConfig } from "../storage/interface";
export interface DuelSettings {
    target_points: number;
    order_points_ratio: number;
    win_stamina: number;
    win_points: number;
    matchmaking_seconds: number;
    bot_min_seconds: number;
    bot_max_seconds: number;
    bot_order_value: number;
}
export interface DuelTier {
    tier: number;
    required_points: number;
    stamina: number;
    spirit_stones: number;
}
interface DuelMatch {
    id: string;
    players: string[];
    started_at: number;
    points: Record<string, number>;
    bot_interval_ms: number;
    winner?: string;
    ended_at?: number;
}
interface DuelTicket {
    realm: number;
    queued_at: number;
    match_id?: string;
}
export interface DuelRegistry {
    event_id: string;
    revision: number;
    tickets: Record<string, DuelTicket>;
    matches: Record<string, DuelMatch>;
}
export interface DuelProgress {
    event_id: string;
    round: number;
    victory_points: number;
    claimed_tiers: number[];
    status: "resting" | "matching" | "playing" | "lost";
    match_id?: string;
    order_points: number;
    last_order_at: number;
    last_result?: {
        match_id: string;
        won: boolean;
        my_points: number;
        opponent_points: number;
        stamina: number;
        victory_points: number;
    };
}
/** Orders are persisted before publication. Registry CAS chooses one winner; player CAS pays it once. */
export declare class OrderDuelService {
    readonly activity: ActivityDef | undefined;
    readonly settings: DuelSettings;
    readonly tiers: DuelTier[];
    readonly eventId: string;
    constructor(activities: ActivityDef[], data: any);
    active(now?: number): boolean;
    progress(state: GameState): DuelProgress;
    orderPoints(value: number): number;
    awardOrderPoints(state: GameState, value: number, now?: number): void;
    private update;
    private botPoints;
    /** Match only explicit entrants. A ticket remains until its durable settlement is acknowledged. */
    refresh(storage: IStorage, userId: string, state: GameState, apply: (r: RewardConfig) => unknown, now?: number): Promise<Record<string, any>>;
    start(storage: IStorage, userId: string, state: GameState, expectedRound: number, apply: (r: RewardConfig) => unknown, now?: number): Promise<Record<string, any>>;
    rest(storage: IStorage, userId: string, state: GameState, expectedRound: number): Promise<{
        active: boolean;
        activity_id: number | undefined;
        server_now: number;
        registry_revision: number;
        settings: DuelSettings;
        rewards: DuelTier[];
        queued_at: number;
        opponent: {
            name: string;
            bot: boolean;
            points: number;
        } | null;
        my_points: number;
        event_id: string;
        round: number;
        victory_points: number;
        claimed_tiers: number[];
        status: "resting" | "matching" | "playing" | "lost";
        match_id?: string;
        order_points: number;
        last_order_at: number;
        last_result?: {
            match_id: string;
            won: boolean;
            my_points: number;
            opponent_points: number;
            stamina: number;
            victory_points: number;
        };
    } | {
        error: string;
    }>;
    claim(storage: IStorage, userId: string, state: GameState, tier: number, apply: (r: RewardConfig) => unknown): Promise<{
        active: boolean;
        activity_id: number | undefined;
        server_now: number;
        registry_revision: number;
        settings: DuelSettings;
        rewards: DuelTier[];
        queued_at: number;
        opponent: {
            name: string;
            bot: boolean;
            points: number;
        } | null;
        my_points: number;
        event_id: string;
        round: number;
        victory_points: number;
        claimed_tiers: number[];
        status: "resting" | "matching" | "playing" | "lost";
        match_id?: string;
        order_points: number;
        last_order_at: number;
        last_result?: {
            match_id: string;
            won: boolean;
            my_points: number;
            opponent_points: number;
            stamina: number;
            victory_points: number;
        };
    } | {
        error: string;
    }>;
    private view;
}
export {};
