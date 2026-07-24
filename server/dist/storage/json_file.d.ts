import { IStorage, User, GameState, LeaderboardEntry } from "./interface";
export declare class JsonFileStorage implements IStorage {
    private dir;
    private usersFile;
    private statesDir;
    constructor(dir: string);
    private readUsers;
    private writeUsers;
    private statePath;
    findUser(deviceId: string): Promise<User | null>;
    createUser(deviceId: string): Promise<User>;
    loadState(userId: string): Promise<GameState | null>;
    saveState(userId: string, state: GameState): Promise<void>;
    getLeaderboard(limit: number): Promise<LeaderboardEntry[]>;
}
