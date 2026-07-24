import { GameState, IStorage, LeaderboardEntry, User } from "./interface";
export declare class D1Storage implements IStorage {
    private readonly db;
    constructor(db: D1Database);
    findUser(deviceId: string): Promise<User | null>;
    createUser(deviceId: string): Promise<User>;
    loadState(userId: string): Promise<GameState | null>;
    saveState(userId: string, state: GameState): Promise<void>;
    getLeaderboard(limit: number): Promise<LeaderboardEntry[]>;
}
