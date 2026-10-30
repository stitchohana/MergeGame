"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.D1Storage = void 0;
class D1Storage {
    db;
    async loadOrderDuel(eventId) {
        const row = await this.db.prepare("SELECT registry_json FROM order_duel_events WHERE event_id = ?").bind(eventId).first();
        return row ? JSON.parse(row.registry_json) : null;
    }
    async saveOrderDuel(registry) {
        const next = { ...registry, revision: registry.revision + 1 };
        const result = await this.db.prepare("INSERT INTO order_duel_events (event_id, revision, registry_json) VALUES (?, ?, ?) ON CONFLICT(event_id) DO UPDATE SET revision = excluded.revision, registry_json = excluded.registry_json WHERE order_duel_events.revision = ?")
            .bind(registry.event_id, next.revision, JSON.stringify(next), registry.revision).run();
        if (result.meta.changes !== 1)
            throw new Error("state_conflict");
        registry.revision = next.revision;
    }
    constructor(db) {
        this.db = db;
    }
    async listStairClimbCandidates(level) {
        const result = await this.db.prepare("SELECT user_id FROM game_states WHERE json_extract(state_json, '$.cultivation.current_level') = ?").bind(level).all();
        return result.results.map(row => row.user_id);
    }
    async loadStairClimb(eventId) {
        const row = await this.db.prepare("SELECT registry_json FROM stair_climb_events WHERE event_id = ?").bind(eventId).first();
        return row ? JSON.parse(row.registry_json) : null;
    }
    async saveStairClimb(registry) {
        const next = { ...registry, revision: registry.revision + 1 };
        const result = await this.db.prepare("INSERT INTO stair_climb_events (event_id, revision, registry_json) VALUES (?, ?, ?) ON CONFLICT(event_id) DO UPDATE SET revision = excluded.revision, registry_json = excluded.registry_json WHERE stair_climb_events.revision = ?")
            .bind(registry.event_id, next.revision, JSON.stringify(next), registry.revision).run();
        if (result.meta.changes !== 1)
            throw new Error("state_conflict");
        registry.revision = next.revision;
    }
    async findUser(deviceId) {
        const row = await this.db.prepare("SELECT user_id, device_id, created_at FROM users WHERE device_id = ? LIMIT 1").bind(deviceId).first();
        return row ? { userId: row.user_id, deviceId: row.device_id, createdAt: row.created_at } : null;
    }
    async createUser(deviceId) {
        const user = { userId: crypto.randomUUID(), deviceId, createdAt: new Date().toISOString() };
        await this.db.prepare("INSERT INTO users (user_id, device_id, created_at) VALUES (?, ?, ?)").bind(user.userId, user.deviceId, user.createdAt).run();
        return user;
    }
    async loadState(userId) {
        const row = await this.db.prepare("SELECT state_json FROM game_states WHERE user_id = ? LIMIT 1").bind(userId).first();
        return row ? JSON.parse(row.state_json) : null;
    }
    async saveState(userId, state) {
        // Compare the persisted revision. All writers
        // use this path, so a concurrent Worker cannot overwrite a committed opening.
        const revision = state.storage_revision;
        const result = await this.db.prepare("INSERT INTO game_states (user_id, state_json, updated_at) VALUES (?, ?, unixepoch()) ON CONFLICT(user_id) DO UPDATE SET state_json = excluded.state_json, updated_at = excluded.updated_at WHERE json_extract(game_states.state_json, '$.storage_revision') = ?").bind(userId, JSON.stringify({ ...state, storage_revision: revision + 1 }), revision).run();
        if (result.meta.changes !== 1)
            throw new Error("state_conflict");
        state.storage_revision = revision + 1;
    }
    async getLeaderboard(limit) {
        const result = await this.db.prepare("SELECT u.user_id, u.device_id, datetime(s.updated_at, 'unixepoch') AS updated_at FROM users u JOIN game_states s ON s.user_id = u.user_id ORDER BY s.updated_at DESC LIMIT ?").bind(limit).all();
        return result.results.map((row) => ({ userId: row.user_id, deviceId: row.device_id, updatedAt: row.updated_at }));
    }
}
exports.D1Storage = D1Storage;
