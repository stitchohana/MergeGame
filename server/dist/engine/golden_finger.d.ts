import type { GameState } from "../storage/interface";
import type { GameEngine } from "./game_engine";
export interface ArtifactDef {
    id: string;
    name: string;
    unlock_level: number;
    unlock_label: string;
    daily_free: number;
    daily_buy_limit: number;
    base_cost: number;
    cost_increment: number;
    description: string;
}
export interface GoldenFingerState {
    progress: Record<string, {
        period: string;
        free_used: number;
        bought: number;
        paid_used: number;
    }>;
    receipts: Array<{
        request_id: string;
        signature: string;
        result: Record<string, unknown>;
    }>;
    rewind?: {
        at: number;
        label: string;
        version: number;
        before: Record<string, unknown>;
        after: string;
    };
}
type Selection = {
    artifact: string;
    mode?: string;
    uids?: number[];
    target_id?: number;
    uid?: number;
};
export declare class GoldenFingerService {
    private engine;
    readonly artifacts: ArtifactDef[];
    private realms;
    readonly resetHour: number;
    readonly rewindSeconds: number;
    constructor(config: any, engine: GameEngine);
    private progress;
    private data;
    levelCap(state: GameState): number;
    private plain;
    materialPool(state: GameState): import("./game_engine").ItemDef[];
    private fingerprint;
    snapshot(state: GameState): Record<string, unknown>;
    capture(state: GameState, before: Record<string, unknown>, label: string, now?: number): void;
    private rewindValid;
    view(state: GameState, now?: number): {
        period_key: string;
        reset_hour: number;
        next_reset_at: number;
        level_cap: number;
        rewind: {
            available: boolean;
            label: string;
            expires_at: number;
        };
        artifacts: {
            unlocked: boolean;
            free_remaining: number;
            paid_remaining: number;
            remaining: number;
            purchase_count: number;
            purchases_remaining: number;
            next_cost: number;
            id: string;
            name: string;
            unlock_level: number;
            unlock_label: string;
            daily_free: number;
            daily_buy_limit: number;
            base_cost: number;
            cost_increment: number;
            description: string;
        }[];
    };
    preview(state: GameState, selection: Selection, now?: number): any;
    transact(state: GameState, action: string, body: any, now?: number): any;
    quoteKey(preview: any): any;
}
export {};
