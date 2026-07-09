import * as fs from "fs";
import * as path from "path";
import { IStorage, User, GameState, LeaderboardEntry } from "./interface";
import { defaultGameState } from "./memory";

export class JsonFileStorage implements IStorage {
  private dir: string;
  private usersFile: string;
  private statesDir: string;

  constructor(dir: string) {
    this.dir = dir;
    this.usersFile = path.join(dir, "users.json");
    this.statesDir = path.join(dir, "states");
    fs.mkdirSync(this.statesDir, { recursive: true });
  }

  private readUsers(): Map<string, User> {
    const map = new Map<string, User>();
    try {
      if (fs.existsSync(this.usersFile)) {
        const data = JSON.parse(fs.readFileSync(this.usersFile, "utf-8"));
        for (const u of data.users || []) {
          map.set(u.userId, u);
        }
      }
    } catch { /* ignore */ }
    return map;
  }

  private writeUsers(map: Map<string, User>): void {
    fs.writeFileSync(this.usersFile, JSON.stringify({ users: [...map.values()] }, null, 2));
  }

  private statePath(userId: string): string {
    return path.join(this.statesDir, `${userId}.json`);
  }

  async findUser(deviceId: string): Promise<User | null> {
    const users = this.readUsers();
    for (const u of users.values()) {
      if (u.deviceId === deviceId) return u;
    }
    return null;
  }

  async createUser(deviceId: string): Promise<User> {
    const users = this.readUsers();
    const user: User = {
      userId: `u_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      deviceId,
      createdAt: new Date().toISOString()
      };
    users.set(user.userId, user);
    this.writeUsers(users);
    return user;
  }

  async loadState(userId: string): Promise<GameState | null> {
    try {
      const filePath = this.statePath(userId);
      if (fs.existsSync(filePath)) {
        return JSON.parse(fs.readFileSync(filePath, "utf-8"));
      }
    } catch { /* ignore */ }
    return null;
  }

  async saveState(userId: string, state: GameState): Promise<void> {
    fs.writeFileSync(this.statePath(userId), JSON.stringify(state, null, 2));
  }

  async getLeaderboard(limit: number): Promise<LeaderboardEntry[]> {
    const users = this.readUsers();
    const entries: LeaderboardEntry[] = [];
    for (const [userId, user] of users) {
      const state = await this.loadState(userId);
      if (state) {
        entries.push({
          userId,
          deviceId: user.deviceId,
          updatedAt: new Date().toISOString()
      });
      }
    }
    return entries.slice(0, limit);
  }
}
