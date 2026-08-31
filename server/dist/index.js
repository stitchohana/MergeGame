"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const express_rate_limit_1 = __importDefault(require("express-rate-limit"));
const config_1 = require("./config");
const memory_1 = require("./storage/memory");
const json_file_1 = require("./storage/json_file");
const game_engine_1 = require("./engine/game_engine");
const auth_1 = require("./routes/auth");
const game_1 = require("./routes/game");
const cultivation_1 = require("./routes/cultivation");
const gm_1 = require("./routes/gm");
const config_data_1 = require("./worker/config_data");
const http_1 = require("./worker/http");
class ExpressWorkerResponse extends http_1.WorkerResponse {
    expressResponse;
    constructor(expressResponse) {
        super();
        this.expressResponse = expressResponse;
    }
    status(code) {
        this.statusCode = code;
        this.expressResponse.status(code);
        return this;
    }
    header(name, value) {
        this.expressResponse.setHeader(name, value);
        return this;
    }
    json(value) {
        this.headersSent = true;
        this.expressResponse.status(this.statusCode).json(value);
        return this;
    }
    sendStatus(code) {
        this.status(code);
        this.headersSent = true;
        this.expressResponse.sendStatus(code);
        return this;
    }
}
function toWorkerRequest(req) {
    const headers = {};
    for (const [name, value] of Object.entries(req.headers)) {
        headers[name.toLowerCase()] = Array.isArray(value) ? value.join(", ") : value;
    }
    const query = {};
    for (const [name, value] of Object.entries(req.query)) {
        query[name] = typeof value === "string"
            ? value
            : Array.isArray(value) && typeof value[0] === "string" ? value[0] : undefined;
    }
    return {
        method: req.method,
        path: req.path,
        headers,
        body: req.body ?? {},
        query,
    };
}
function mountRouter(app, prefix, router) {
    app.use(prefix, async (req, res, next) => {
        try {
            const handled = await router.handle(toWorkerRequest(req), new ExpressWorkerResponse(res));
            if (!handled && !res.headersSent)
                next();
        }
        catch (error) {
            next(error);
        }
    });
}
function createStorage() {
    switch (config_1.config.dbType) {
        case "memory":
            console.log("[server] Using memory storage");
            return new memory_1.MemoryStorage();
        case "json_file":
        default:
            console.log(`[server] Using JSON file storage: ${config_1.config.jsonDbPath}`);
            return new json_file_1.JsonFileStorage(config_1.config.jsonDbPath);
    }
}
function main() {
    const app = (0, express_1.default)();
    // Request logger
    app.use((req, res, next) => {
        const start = Date.now();
        res.on("finish", () => {
            const ms = Date.now() - start;
            console.log(`[http] ${req.method} ${req.path} -> ${res.statusCode} (${ms}ms)`);
        });
        next();
    });
    // Middleware
    app.use(express_1.default.json({ limit: "200kb" }));
    // CORS — allow Godot client (no Origin header) and browser requests from localhost
    const corsOrigin = process.env.CORS_ORIGIN || "";
    app.use((_req, res, next) => {
        const origin = _req.headers.origin;
        if (origin) {
            if (origin.startsWith("http://localhost") || origin.startsWith("http://127.0.0.1") || origin === corsOrigin) {
                res.header("Access-Control-Allow-Origin", origin);
            }
        }
        res.header("Access-Control-Allow-Headers", "Authorization, Content-Type");
        res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        if (_req.method === "OPTIONS") {
            res.sendStatus(200);
            return;
        }
        next();
    });
    // Rate limiting
    const generalLimiter = (0, express_rate_limit_1.default)({
        windowMs: 60 * 1000,
        max: 120,
        standardHeaders: true,
        legacyHeaders: false,
        message: { error: "too_many_requests" }
    });
    const mutationLimiter = (0, express_rate_limit_1.default)({
        windowMs: 60 * 1000,
        max: 60,
        standardHeaders: true,
        legacyHeaders: false,
        message: { error: "too_many_requests" }
    });
    app.use("/api/", generalLimiter);
    // Dependencies
    const storage = createStorage();
    const engine = new game_engine_1.GameEngine(config_data_1.gameConfigTables);
    console.log("[server] Game engine loaded");
    console.log(`[server] Grid: ${engine.GRID_COLS}x${engine.GRID_ROWS}`);
    console.log(`[server] Initial setup: ${engine.getInitialSetup().length} items`);
    // Routes
    mountRouter(app, "/api/auth", (0, auth_1.createAuthRouter)(storage, config_1.config.jwtSecret));
    mountRouter(app, "/api/game", (0, game_1.createGameRouter)(storage, engine, config_1.config.jwtSecret));
    mountRouter(app, "/api/cultivation", (0, cultivation_1.createCultivationRouter)(storage, engine, config_1.config.jwtSecret));
    mountRouter(app, "/api/gm", (0, gm_1.createGMRouter)(storage, engine, config_1.config.jwtSecret, process.env.GM_KEY || ""));
    // Health check
    app.get("/api/health", (_req, res) => {
        res.json({ status: "ok" });
    });
    // Start
    app.listen(config_1.config.port, () => {
        console.log(`[server] MergeGame server listening on http://localhost:${config_1.config.port}`);
        console.log(`[server] Endpoints:`);
        console.log(`  POST /api/auth/login`);
        console.log(`  GET  /api/game/state`);
        console.log(`  POST /api/game/merge`);
        console.log(`  POST /api/game/spawn`);
        console.log(`  POST /api/game/craft/add`);
        console.log(`  POST /api/game/craft/start`);
        console.log(`  POST /api/game/craft/retrieve`);
        console.log(`  POST /api/game/cultivate`);
        console.log(`  POST /api/cultivation/consume-exp`);
        console.log(`  POST /api/cultivation/consume-stamina`);
        console.log(`  POST /api/cultivation/breakthrough`);
        console.log(`  GET  /api/game/leaderboard`);
    });
}
main();
