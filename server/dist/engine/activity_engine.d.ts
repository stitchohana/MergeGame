import { GameState, ActivityDef, GridItem, RewardConfig } from "../storage/interface";
import type { GameEngine } from "./game_engine";
export declare class ActivityEngine {
    private activities;
    private weeklyTasks;
    constructor(activitiesData: any, weeklyTasksData: any);
    private loadActivities;
    private loadWeeklyTasks;
    getActivities(): ActivityDef[];
    hasWeeklyTasks(activityId: number): boolean;
    getCurrentDay(activityId: number, resetHour: number): number;
    isActive(a: ActivityDef): boolean;
    getDailyQuestIds(activityId: number, day: number): number[];
    initProgress(state: GameState): void;
    recordOrderSupplyAction(state: GameState, itemId: number, availableBefore?: number): void;
    claimOrderSupply(state: GameState, activityId: number, expectedClaimCount: number, engine: GameEngine): {
        ok: true;
        rewards: RewardConfig;
        spawned_items: GridItem[];
        pending_rewards_added: number;
        crafts_completed: number;
    } | {
        ok: false;
        reason: string;
    };
    private orderSupplyCount;
    checkAndReset(state: GameState, resetHour: number): void;
    private isNewPeriod;
}
