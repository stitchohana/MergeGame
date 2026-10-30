import type { ActivityDef, GameState, IStorage, RewardConfig } from "../storage/interface";
export interface StairClimbReward {
    min_rank: number;
    max_rank: number;
    stamina: number;
    spirit_stones: number;
}
export interface StairClimbScore {
    group_id: string;
    points: number;
    reached_at: number;
    settlement?: {
        rank: number;
        reward: StairClimbReward;
        settled_at: number;
    };
}
export type StairClimbProgress = Record<string, StairClimbScore>;
interface Member {
    id: string;
    name: string;
    bot: boolean;
    interval_ms: number;
}
export interface StairClimbRow {
    name: string;
    bot: boolean;
    points: number;
    rank: number;
    member_index: number;
    reached_at: number;
}
export interface StairClimbGroup {
    id: string;
    realm: number;
    joined_at: number;
    members: Member[];
    final_rows?: StairClimbRow[];
    paid_members?: string[];
}
export interface StairClimbRegistry {
    event_id: string;
    revision: number;
    groups: StairClimbGroup[];
}
interface Settings {
    group_size: number;
    order_points_ratio: number;
    bot_order_value: number;
    bot_min_minutes: number;
    bot_max_minutes: number;
    rewards: StairClimbReward[];
}
/** Shared groups live in storage; no process-local membership or client-supplied points. */
export declare class StairClimbService {
    private readonly stages;
    readonly activity: ActivityDef | undefined;
    readonly config: Settings;
    readonly start: number;
    readonly end: number;
    readonly eventId: string;
    readonly settlementDelayMs = 30000;
    constructor(activities: ActivityDef[], stages: {
        name: string;
    }[]);
    isActive(now?: number): boolean;
    score(state: GameState): StairClimbScore | undefined;
    reward(rank: number): StairClimbReward;
    enroll(storage: IStorage, userId: string, state: GameState, now?: number): Promise<boolean>;
    awardOrderPoints(state: GameState, orderValue: number, now?: number): boolean;
    orderPoints(orderValue: number): number;
    private shuffle;
    rows(storage: IStorage, group: StairClimbGroup, now?: number): Promise<StairClimbRow[]>;
    private frozenGroup;
    /** Caller persists currency and settlement marker in the same version-checked save. */
    settlePlayer(storage: IStorage, userId: string, state: GameState, apply: (r: RewardConfig) => unknown, now?: number, frozen?: StairClimbGroup): Promise<boolean>;
    view(storage: IStorage, userId: string, state: GameState, now?: number): Promise<{
        status: string;
        rows: never[];
        activity_id?: undefined;
        event_id?: undefined;
        server_now?: undefined;
        start_time?: undefined;
        end_time?: undefined;
        group_id?: undefined;
        realm_name?: undefined;
        order_points_ratio?: undefined;
        rewards?: undefined;
        my_rank?: undefined;
        my_points?: undefined;
        settlement?: undefined;
    } | {
        activity_id: number;
        event_id: string;
        server_now: number;
        start_time: number;
        end_time: number;
        status: string;
        group_id: string;
        realm_name: string;
        order_points_ratio: number;
        rewards: StairClimbReward[];
        rows: {
            is_self: boolean;
            name: string;
            bot: boolean;
            points: number;
            rank: number;
            member_index: number;
            reached_at: number;
        }[];
        my_rank: number;
        my_points: number;
        settlement: {
            rank: number;
            reward: StairClimbReward;
            settled_at: number;
        } | null;
    }>;
    /** Five recipients per tick keeps D1 work bounded; retries resume unpaid members. */
    settleBatch(storage: IStorage, apply: (s: GameState, r: RewardConfig) => unknown, now?: number): Promise<void>;
}
export {};
