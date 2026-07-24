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
        grid: [],
        pouch: [],
        cultivation: { ...defaultCultivation },
        stamina: 100,
        max_stamina: 100,
        last_stamina_tick: now,
        spirit_stones: 0,
        pending_rewards: []
    };
}
class MemoryStorage {
    users = new Map();
    states = new Map();
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
        return this.states.get(userId) ?? null;
    }
    async saveState(userId, state) {
        this.states.set(userId, state);
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
