import { IStorage, User, GameState, LeaderboardEntry } from "./interface";

const defaultCultivation = {
  current_realm_id: 0,
  current_level: 1,
  current_exp: 0,
  total_exp: 0,
  current_qi: 100,
  max_qi: 100,
  buffs: [],
  last_tick_time: Date.now(),
};

export function defaultGameState(): GameState {
  const now = Date.now();
  return {
    score: 0,
    high_score: 0,
    grid: [],
    cultivation: { ...defaultCultivation },
    stamina: 100,
    max_stamina: 100,
    last_stamina_tick: now,
    spirit_stones: 0,
    version: 0,
  };
}

export class MemoryStorage implements IStorage {
  private users = new Map<string, User>();
  private states = new Map<string, GameState>();

  async findUser(deviceId: string): Promise<User | null> {
    for (const u of this.users.values()) {
      if (u.deviceId === deviceId) return u;
    }
    return null;
  }

  async createUser(deviceId: string): Promise<User> {
    const user: User = {
      userId: `u_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      deviceId,
      createdAt: new Date().toISOString(),
    };
    this.users.set(user.userId, user);
    return user;
  }

  async loadState(userId: string): Promise<GameState | null> {
    return this.states.get(userId) ?? null;
  }

  async saveState(userId: string, state: GameState): Promise<void> {
    this.states.set(userId, state);
  }

  async getLeaderboard(limit: number): Promise<LeaderboardEntry[]> {
    const entries: LeaderboardEntry[] = [];
    for (const [userId, state] of this.states) {
      const user = this.users.get(userId);
      entries.push({
        userId,
        deviceId: user?.deviceId ?? "unknown",
        score: state.high_score,
        updatedAt: new Date().toISOString(),
      });
    }
    entries.sort((a, b) => b.score - a.score);
    return entries.slice(0, limit);
  }
}
