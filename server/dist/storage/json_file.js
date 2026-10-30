"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.JsonFileStorage = void 0;
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
class JsonFileStorage {
    async loadOrderDuel(eventId) {
        const file = path.join(this.dir, `order-duel-${encodeURIComponent(eventId)}.json`);
        return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
    }
    async saveOrderDuel(registry) {
        const file = path.join(this.dir, `order-duel-${encodeURIComponent(registry.event_id)}.json`);
        const saved = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
        if ((saved?.revision ?? 0) !== registry.revision)
            throw new Error("state_conflict");
        const next = { ...registry, revision: registry.revision + 1 };
        fs.writeFileSync(file + ".tmp", JSON.stringify(next));
        fs.renameSync(file + ".tmp", file);
        registry.revision = next.revision;
    }
    dir;
    usersFile;
    statesDir;
    constructor(dir) {
        this.dir = dir;
        this.usersFile = path.join(dir, "users.json");
        this.statesDir = path.join(dir, "states");
        fs.mkdirSync(this.statesDir, { recursive: true });
    }
    readUsers() {
        const map = new Map();
        if (fs.existsSync(this.usersFile)) {
            const data = JSON.parse(fs.readFileSync(this.usersFile, "utf-8"));
            for (const u of data.users)
                map.set(u.userId, u);
        }
        return map;
    }
    writeUsers(map) {
        fs.writeFileSync(this.usersFile, JSON.stringify({ users: [...map.values()] }, null, 2));
    }
    statePath(userId) {
        return path.join(this.statesDir, `${userId}.json`);
    }
    stairClimbPath(eventId) {
        return path.join(this.dir, `stair-climb-${encodeURIComponent(eventId)}.json`);
    }
    async listStairClimbCandidates(level) {
        const ids = [];
        for (const userId of this.readUsers().keys()) {
            const state = await this.loadState(userId);
            if (state?.cultivation.current_level === level)
                ids.push(userId);
        }
        return ids;
    }
    async loadStairClimb(eventId) {
        const file = this.stairClimbPath(eventId);
        return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
    }
    async saveStairClimb(registry) {
        // No await between read/check/rename: atomic relative to the local Node process.
        const file = this.stairClimbPath(registry.event_id);
        const saved = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
        if ((saved?.revision ?? 0) !== registry.revision)
            throw new Error("state_conflict");
        const next = { ...registry, revision: registry.revision + 1 };
        fs.writeFileSync(file + ".tmp", JSON.stringify(next));
        fs.renameSync(file + ".tmp", file);
        registry.revision = next.revision;
    }
    async findUser(deviceId) {
        const users = this.readUsers();
        for (const u of users.values()) {
            if (u.deviceId === deviceId)
                return u;
        }
        return null;
    }
    async createUser(deviceId) {
        const users = this.readUsers();
        const user = {
            userId: `u_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
            deviceId,
            createdAt: new Date().toISOString()
        };
        users.set(user.userId, user);
        this.writeUsers(users);
        return user;
    }
    async loadState(userId) {
        const filePath = this.statePath(userId);
        return fs.existsSync(filePath) ? JSON.parse(fs.readFileSync(filePath, "utf-8")) : null;
    }
    async saveState(userId, state) {
        const file = this.statePath(userId);
        const revision = state.storage_revision;
        // The local server serializes player operations; keep the same revision contract as D1.
        const stored = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
        if ((stored ? stored.storage_revision : 0) !== revision)
            throw new Error("state_conflict");
        const pending = file + ".tmp";
        fs.writeFileSync(pending, JSON.stringify({ ...state, storage_revision: revision + 1 }, null, 2));
        fs.renameSync(pending, file);
        state.storage_revision = revision + 1;
    }
    async getLeaderboard(limit) {
        const users = this.readUsers();
        const entries = [];
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
exports.JsonFileStorage = JsonFileStorage;
