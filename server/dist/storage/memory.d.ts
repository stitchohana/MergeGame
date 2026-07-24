import { IStorage, User, GameState, LeaderboardEntry } from "./interface";
export declare function defaultGameState(): GameState;
export declare class MemoryStorage implements IStorage {
    private users;
    private states;
    findUser(deviceId: string): Promise<User | null>;
    createUser(deviceId: string): Promise<User>;
    loadState(userId: string): Promise<GameState | null>;
    saveState(userId: string, state: GameState): Promise<void>;
    getLeaderboard(limit: number): Promise<LeaderboardEntry[]>;
}
