import * as fs from "fs";
import * as path from "path";
import { IStorage, User, GameState, LeaderboardEntry } from "./interface";
import { defaultGameState } from "./memory";
import type { StairClimbRegistry } from "../engine/stair_climb";
import type { DuelRegistry } from "../engine/order_duel";

export class JsonFileStorage implements IStorage {
  async loadOrderDuel(eventId: string): Promise<DuelRegistry | null> {
    const file = path.join(this.dir, `order-duel-${encodeURIComponent(eventId)}.json`);
    return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
  }

  async saveOrderDuel(registry: DuelRegistry): Promise<void> {
    const file = path.join(this.dir, `order-duel-${encodeURIComponent(registry.event_id)}.json`);
    const saved = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
    if ((saved?.revision ?? 0) !== registry.revision) throw new Error("state_conflict");
    const next = { ...registry, revision: registry.revision + 1 };
    fs.writeFileSync(file + ".tmp", JSON.stringify(next));
    fs.renameSync(file + ".tmp", file);
    registry.revision = next.revision;
  }
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
    if (fs.existsSync(this.usersFile)) {
      const data = JSON.parse(fs.readFileSync(this.usersFile, "utf-8"));
      for (const u of data.users) map.set(u.userId, u);
    }
    return map;
  }

  private writeUsers(map: Map<string, User>): void {
    fs.writeFileSync(this.usersFile, JSON.stringify({ users: [...map.values()] }, null, 2));
  }

  private statePath(userId: string): string {
    return path.join(this.statesDir, `${userId}.json`);
  }

  private stairClimbPath(eventId: string): string {
    return path.join(this.dir, `stair-climb-${encodeURIComponent(eventId)}.json`);
  }

  async listStairClimbCandidates(level: number): Promise<string[]> {
    const ids: string[] = [];
    for (const userId of this.readUsers().keys()) {
      const state = await this.loadState(userId);
      if (state?.cultivation.current_level === level) ids.push(userId);
    }
    return ids;
  }

  async loadStairClimb(eventId: string): Promise<StairClimbRegistry | null> {
    const file = this.stairClimbPath(eventId);
    return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
  }

  async saveStairClimb(registry: StairClimbRegistry): Promise<void> {
    // No await between read/check/rename: atomic relative to the local Node process.
    const file = this.stairClimbPath(registry.event_id);
    const saved = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
    if ((saved?.revision ?? 0) !== registry.revision) throw new Error("state_conflict");
    const next = { ...registry, revision: registry.revision + 1 };
    fs.writeFileSync(file + ".tmp", JSON.stringify(next));
    fs.renameSync(file + ".tmp", file);
    registry.revision = next.revision;
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
    const filePath = this.statePath(userId);
    return fs.existsSync(filePath) ? JSON.parse(fs.readFileSync(filePath, "utf-8")) : null;
  }

  async saveState(userId: string, state: GameState): Promise<void> {
    const file = this.statePath(userId);
    const revision = state.storage_revision;
    // The local server serializes player operations; keep the same revision contract as D1.
    const stored = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
    if ((stored ? stored.storage_revision : 0) !== revision) throw new Error("state_conflict");
    const pending = file + ".tmp";
    fs.writeFileSync(pending, JSON.stringify({ ...state, storage_revision: revision + 1 }, null, 2));
    fs.renameSync(pending, file);
    state.storage_revision = revision + 1;
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
