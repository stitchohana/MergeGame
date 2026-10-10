import { GameState, IStorage, LeaderboardEntry, User } from "./interface";
import type { StairClimbRegistry } from "../engine/stair_climb";

type UserRow = { user_id: string; device_id: string; created_at: string };
type StateRow = { state_json: string };

export class D1Storage implements IStorage {
	constructor(private readonly db: D1Database) {}

	async listStairClimbCandidates(level: number): Promise<string[]> {
		const result = await this.db.prepare("SELECT user_id FROM game_states WHERE json_extract(state_json, '$.cultivation.current_level') = ?").bind(level).all<{ user_id: string }>();
		return result.results.map(row => row.user_id);
	}

	async loadStairClimb(eventId: string): Promise<StairClimbRegistry | null> {
		const row = await this.db.prepare("SELECT registry_json FROM stair_climb_events WHERE event_id = ?").bind(eventId).first<{ registry_json: string }>();
		return row ? JSON.parse(row.registry_json) : null;
	}

	async saveStairClimb(registry: StairClimbRegistry): Promise<void> {
		const next = { ...registry, revision: registry.revision + 1 };
		const result = await this.db.prepare("INSERT INTO stair_climb_events (event_id, revision, registry_json) VALUES (?, ?, ?) ON CONFLICT(event_id) DO UPDATE SET revision = excluded.revision, registry_json = excluded.registry_json WHERE stair_climb_events.revision = ?")
			.bind(registry.event_id, next.revision, JSON.stringify(next), registry.revision).run();
		if (result.meta.changes !== 1) throw new Error("state_conflict");
		registry.revision = next.revision;
	}

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
		// Compare the persisted revision, including legacy rows without one. All writers
		// use this path, so a concurrent Worker cannot overwrite a committed opening.
		const revision = state.storage_revision ?? 0;
		const result = await this.db.prepare(
			"INSERT INTO game_states (user_id, state_json, updated_at) VALUES (?, ?, unixepoch()) ON CONFLICT(user_id) DO UPDATE SET state_json = excluded.state_json, updated_at = excluded.updated_at WHERE COALESCE(json_extract(game_states.state_json, '$.storage_revision'), 0) = ?"
		).bind(userId, JSON.stringify({ ...state, storage_revision: revision + 1 }), revision).run();
		if (result.meta.changes !== 1) throw new Error("state_conflict");
		state.storage_revision = revision + 1;
	}

	async getLeaderboard(limit: number): Promise<LeaderboardEntry[]> {
		const result = await this.db.prepare(
			"SELECT u.user_id, u.device_id, datetime(s.updated_at, 'unixepoch') AS updated_at FROM users u JOIN game_states s ON s.user_id = u.user_id ORDER BY s.updated_at DESC LIMIT ?"
		).bind(limit).all<{ user_id: string; device_id: string; updated_at: string }>();
		return result.results.map((row) => ({ userId: row.user_id, deviceId: row.device_id, updatedAt: row.updated_at }));
	}
}
