import { GameState, IStorage, LeaderboardEntry, User } from "./interface";
import type { StairClimbRegistry } from "../engine/stair_climb";
import type { DuelRegistry } from "../engine/order_duel";
export declare class D1Storage implements IStorage {
    private readonly db;
    loadOrderDuel(eventId: string): Promise<DuelRegistry | null>;
    saveOrderDuel(registry: DuelRegistry): Promise<void>;
    constructor(db: D1Database);
    listStairClimbCandidates(level: number): Promise<string[]>;
    loadStairClimb(eventId: string): Promise<StairClimbRegistry | null>;
    saveStairClimb(registry: StairClimbRegistry): Promise<void>;
    findUser(deviceId: string): Promise<User | null>;
    createUser(deviceId: string): Promise<User>;
    loadState(userId: string): Promise<GameState | null>;
    saveState(userId: string, state: GameState): Promise<void>;
    getLeaderboard(limit: number): Promise<LeaderboardEntry[]>;
}
