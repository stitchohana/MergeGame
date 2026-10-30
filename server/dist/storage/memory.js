"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MemoryStorage = void 0;
exports.defaultGameState = defaultGameState;
const defaultCultivation = {
    current_level: 1,
    current_exp: 0,
    total_exp: 0,
    current_qi: 0,
    max_qi: 100,
    last_tick_time: Date.now()
};
function defaultGameState() {
    const now = Date.now();
    return {
        storage_revision: 0,
        grid: [],
        pouch_capacity: 7,
        pouch_unlock_count: 0,
        board_type: 0,
        uid_counter: 0,
        stamina_multiplier_max: 1,
        stamina_multiplier_expires_at: 0,
        spawn_seed: 1,
        spawn_sequence: 0,
        spawn_history: [],
        unlocked_production_item_ids: [],
        item_catalog_claimed_ids: [],
        pouch: [],
        cultivation: { ...defaultCultivation },
        stamina: 100,
        max_stamina: 100,
        last_stamina_tick: now,
        spirit_stones: 0,
        pending_rewards: [],
        version: 0,
        crafted_item_ids: []
    };
}
class MemoryStorage {
    duels = new Map();
    async loadOrderDuel(eventId) {
        return structuredClone(this.duels.get(eventId) ?? null);
    }
    async saveOrderDuel(registry) {
        if ((this.duels.get(registry.event_id)?.revision ?? 0) !== registry.revision)
            throw new Error("state_conflict");
        registry.revision++;
        this.duels.set(registry.event_id, structuredClone(registry));
    }
    users = new Map();
    states = new Map();
    stairClimb = new Map();
    async listStairClimbCandidates(level) {
        return [...this.states].filter(([, state]) => state.cultivation.current_level === level).map(([id]) => id);
    }
    async loadStairClimb(eventId) {
        return structuredClone(this.stairClimb.get(eventId) ?? null);
    }
    async saveStairClimb(registry) {
        if ((this.stairClimb.get(registry.event_id)?.revision ?? 0) !== registry.revision)
            throw new Error("state_conflict");
        registry.revision++;
        this.stairClimb.set(registry.event_id, structuredClone(registry));
    }
    async findUser(deviceId) {
        for (const u of this.users.values()) {
            if (u.deviceId === deviceId)
                return u;
        }
        return null;
    }
    async createUser(deviceId) {
        const user = {
            userId: `u_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
            deviceId,
            createdAt: new Date().toISOString()
        };
        this.users.set(user.userId, user);
        return user;
    }
    async loadState(userId) {
        return structuredClone(this.states.get(userId) ?? null);
    }
    async saveState(userId, state) {
        const revision = state.storage_revision;
        if ((this.states.has(userId) ? this.states.get(userId).storage_revision : 0) !== revision)
            throw new Error("state_conflict");
        state.storage_revision = revision + 1;
        this.states.set(userId, structuredClone(state));
    }
    async getLeaderboard(limit) {
        const entries = [];
        for (const [userId, state] of this.states) {
            const user = this.users.get(userId);
            entries.push({
                userId,
                deviceId: user?.deviceId ?? "unknown",
                updatedAt: new Date().toISOString()
            });
        }
        return entries.slice(0, limit);
    }
}
exports.MemoryStorage = MemoryStorage;
