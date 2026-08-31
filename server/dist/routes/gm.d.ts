import { Router } from "../worker/http";
import { GameState, IStorage } from "../storage/interface";
import { GameEngine } from "../engine/game_engine";
export type GrantCurrentOrderItemsResult = {
    grantedCount: number;
    itemCounts: Record<string, number>;
    mainGrid: GameState["grid"];
    error?: "no_order_items" | "grid_full";
    requiredCount?: number;
    availableSlots?: number;
};
export declare function grantCurrentOrderItems(state: GameState, engine: GameEngine): GrantCurrentOrderItemsResult;
export declare function createGMRouter(storage: IStorage, engine: GameEngine, jwtSecret: string, gmKey: string): Router;
