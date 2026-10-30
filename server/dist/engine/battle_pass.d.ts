import { BattlePassProgress, GameState, RewardConfig } from "../storage/interface";
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
type BattlePassResponse = {
    ok: true;
    progress: Record<number, BattlePassProgress>;
    rewards?: RewardConfig;
} | {
    ok: false;
    reason: string;
};
export declare class BattlePassService {
    private readonly passes;
    private readonly activities;
    private readonly premiumUnlockCost;
    private readonly pointsPerValue;
    constructor(config: any, activitiesData: any, tokensData: any, gameConfig: any);
    private validateRewards;
    getDefinitions(): BattlePassDefinition[];
    getDefinition(activityId: number): BattlePassDefinition | undefined;
    getPeriodKey(now?: number): string;
    private isMonthly;
    ensureProgress(state: GameState, now?: number): Record<number, BattlePassProgress>;
    isActive(activityId: number, now?: number): boolean;
    awardOrderPoints(state: GameState, totalValue: number, requestId?: string, now?: number): boolean;
    unlock(state: GameState, activityId: number, now?: number): BattlePassResponse;
    claim(state: GameState, activityId: number, level: number, track: string, applyRewards: (rewards: RewardConfig) => RewardConfig, now?: number): BattlePassResponse;
    settleExpired(state: GameState, applyRewards: (rewards: RewardConfig) => RewardConfig, now?: number): boolean;
}
export {};
