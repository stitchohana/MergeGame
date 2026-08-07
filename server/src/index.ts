import express from "express";
import rateLimit from "express-rate-limit";
import type { Application, NextFunction as ExpressNextFunction, Request as ExpressRequest, Response as ExpressResponse } from "express";
import * as path from "path";
import { config } from "./config";
import { IStorage } from "./storage/interface";
import { MemoryStorage } from "./storage/memory";
import { JsonFileStorage } from "./storage/json_file";
import { GameEngine } from "./engine/game_engine";
import { createAuthRouter } from "./routes/auth";
import { createGameRouter } from "./routes/game";
import { createCultivationRouter } from "./routes/cultivation";
import { createGMRouter } from "./routes/gm";
import { gameConfigTables } from "./worker/config_data";
import { Router, WorkerResponse, type WorkerRequest } from "./worker/http";

class ExpressWorkerResponse extends WorkerResponse {
  constructor(private readonly expressResponse: ExpressResponse) {
    super();
  }

  override status(code: number): this {
    this.statusCode = code;
    this.expressResponse.status(code);
    return this;
  }

  override header(name: string, value: string): this {
    this.expressResponse.setHeader(name, value);
    return this;
  }

  override json(value: unknown): this {
    this.headersSent = true;
    this.expressResponse.status(this.statusCode).json(value);
    return this;
  }

  override sendStatus(code: number): this {
    this.status(code);
    this.headersSent = true;
    this.expressResponse.sendStatus(code);
    return this;
  }
}

function toWorkerRequest(req: ExpressRequest): WorkerRequest {
  const headers: Record<string, string | undefined> = {};
  for (const [name, value] of Object.entries(req.headers)) {
    headers[name.toLowerCase()] = Array.isArray(value) ? value.join(", ") : value;
  }

  const query: Record<string, string | undefined> = {};
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

function mountRouter(app: Application, prefix: string, router: Router): void {
  app.use(prefix, async (req: ExpressRequest, res: ExpressResponse, next: ExpressNextFunction) => {
    try {
      const handled = await router.handle(toWorkerRequest(req), new ExpressWorkerResponse(res));
      if (!handled && !res.headersSent) next();
    } catch (error) {
      next(error);
    }
  });
}

function createStorage(): IStorage {
  switch (config.dbType) {
    case "memory":
      console.log("[server] Using memory storage");
      return new MemoryStorage();
    case "json_file":
    default:
      console.log(`[server] Using JSON file storage: ${config.jsonDbPath}`);
      return new JsonFileStorage(config.jsonDbPath);
  }
}

function main(): void {
  const app = express();

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
  app.use(express.json({ limit: "200kb" }));

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
  const generalLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 120,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: "too_many_requests" }
      });

  const mutationLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 60,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: "too_many_requests" }
      });

  app.use("/api/", generalLimiter);

  // Dependencies
  const storage = createStorage();
  const engine = new GameEngine(gameConfigTables);

  console.log("[server] Game engine loaded");
  console.log(`[server] Grid: ${engine.GRID_COLS}x${engine.GRID_ROWS}`);
  console.log(`[server] Initial setup: ${engine.getInitialSetup().length} items`);

  // Routes
  mountRouter(app, "/api/auth", createAuthRouter(storage, config.jwtSecret));
  mountRouter(app, "/api/game", createGameRouter(storage, engine, config.jwtSecret));
  mountRouter(app, "/api/cultivation", createCultivationRouter(storage, engine, config.jwtSecret));
  mountRouter(app, "/api/gm", createGMRouter(storage, engine, config.jwtSecret, process.env.GM_KEY || ""));

  // Health check
  app.get("/api/health", (_req, res) => {
    res.json({ status: "ok" });
  });

  // Start
  app.listen(config.port, () => {
    console.log(`[server] MergeGame server listening on http://localhost:${config.port}`);
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
