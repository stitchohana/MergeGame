import type { ActivityDef, GameState, RewardConfig } from "../storage/interface";
export interface WeeklyTaskProgress {
    period_key: string;
    points: number;
    scored_quest_ids: number[];
    claimed_stages: number[];
}
interface WeeklyDefinition {
    activity_id: number;
    points_per_task: number;
    daily_quests: number[][];
    milestones: {
        stage: number;
        required_points: number;
        rewards: RewardConfig;
    }[];
}
export declare class WeeklyTaskService {
    private readonly activities;
    private readonly resetHour;
    readonly definitions: WeeklyDefinition[];
    constructor(data: any, activities: ActivityDef[], resetHour: number, quests: any[]);
    periodKey(now?: number): string;
    ensureProgress(state: GameState): boolean;
    questPoints(questId: number): number;
    awardTaskReward(state: GameState, questId: number): void;
    claim(state: GameState, activityId: number, stage: number, periodKey: string, apply: (rewards: RewardConfig) => RewardConfig): {
        ok: true;
        rewards: RewardConfig;
    } | {
        ok: false;
        reason: string;
    };
    publicProgress(state: GameState): Record<number, WeeklyTaskProgress>;
    private active;
}
export {};
