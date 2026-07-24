import { GameState, IStorage, LeaderboardEntry, User } from "./interface";

type UserRow = { user_id: string; device_id: string; created_at: string };
type StateRow = { state_json: string };

export class D1Storage implements IStorage {
	constructor(private readonly db: D1Database) {}

	async findUser(deviceId: string): Promise<User | null> {
		const row = await this.db.prepare("SELECT user_id, device_id, created_at FROM users WHERE device_id = ? LIMIT 1").bind(deviceId).first<UserRow>();
		return row ? { userId: row.user_id, deviceId: row.device_id, createdAt: row.created_at } : null;
	}

	async createUser(deviceId: string): Promise<User> {
		const user: User = { userId: crypto.randomUUID(), deviceId, createdAt: new Date().toISOString() };
		await this.db.prepare("INSERT INTO users (user_id, device_id, created_at) VALUES (?, ?, ?)").bind(user.userId, user.deviceId, user.createdAt).run();
		return user;
	}

	async loadState(userId: string): Promise<GameState | null> {
		const row = await this.db.prepare("SELECT state_json FROM game_states WHERE user_id = ? LIMIT 1").bind(userId).first<StateRow>();
		return row ? JSON.parse(row.state_json) as GameState : null;
	}

	async saveState(userId: string, state: GameState): Promise<void> {
		await this.db.prepare(
			"INSERT INTO game_states (user_id, state_json, updated_at) VALUES (?, ?, unixepoch()) ON CONFLICT(user_id) DO UPDATE SET state_json = excluded.state_json, updated_at = excluded.updated_at"
		).bind(userId, JSON.stringify(state)).run();
	}

	async getLeaderboard(limit: number): Promise<LeaderboardEntry[]> {
		const result = await this.db.prepare(
			"SELECT u.user_id, u.device_id, datetime(s.updated_at, 'unixepoch') AS updated_at FROM users u JOIN game_states s ON s.user_id = u.user_id ORDER BY s.updated_at DESC LIMIT ?"
		).bind(limit).all<{ user_id: string; device_id: string; updated_at: string }>();
		return result.results.map((row) => ({ userId: row.user_id, deviceId: row.device_id, updatedAt: row.updated_at }));
	}
}
