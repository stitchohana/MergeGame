import { GameState, ActivityDef } from "../storage/interface";
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
    checkAndReset(state: GameState, resetHour: number): void;
    private isNewPeriod;
}
