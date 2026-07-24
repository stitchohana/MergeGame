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
        try {
            if (fs.existsSync(this.usersFile)) {
                const data = JSON.parse(fs.readFileSync(this.usersFile, "utf-8"));
                for (const u of data.users || []) {
                    map.set(u.userId, u);
                }
            }
        }
        catch { /* ignore */ }
        return map;
    }
    writeUsers(map) {
        fs.writeFileSync(this.usersFile, JSON.stringify({ users: [...map.values()] }, null, 2));
    }
    statePath(userId) {
        return path.join(this.statesDir, `${userId}.json`);
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
        try {
            const filePath = this.statePath(userId);
            if (fs.existsSync(filePath)) {
                return JSON.parse(fs.readFileSync(filePath, "utf-8"));
            }
        }
        catch { /* ignore */ }
        return null;
    }
    async saveState(userId, state) {
        fs.writeFileSync(this.statePath(userId), JSON.stringify(state, null, 2));
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
