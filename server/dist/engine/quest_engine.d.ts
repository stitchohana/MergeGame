import { GameState, RewardConfig } from "../storage/interface";
import { GameEngine } from "./game_engine";
interface QuestDef {
    id: number;
    type: number;
    name: string;
    description: string;
    target_count: number;
    rewards: RewardConfig | number;
    auto_reward: boolean;
    reset_cycle?: number;
}
export declare class QuestEngine {
    private quests;
    constructor(data: any);
    private loadQuests;
    getQuestDefs(): QuestDef[];
    getResolvedQuestDefs(engine: GameEngine): any[];
    checkAndResetQuests(state: GameState, resetHour: number): boolean;
    initQuestProgress(state: GameState): boolean;
    incrementQuestProgress(state: GameState, type: number, count: number, engine: GameEngine): void;
    claimQuestReward(state: GameState, questId: number, engine: GameEngine): {
        ok: true;
        rewards: RewardConfig | number;
    } | {
        ok: false;
        reason: string;
    };
    claimPendingReward(state: GameState, uid: number, engine: GameEngine): {
        ok: true;
        col: number;
        row: number;
    } | {
        ok: false;
        reason: string;
    };
}
export {};
