import express from "express";
import * as path from "path";
import { config } from "./config";
import { IStorage } from "./storage/interface";
import { MemoryStorage } from "./storage/memory";
import { JsonFileStorage } from "./storage/json_file";
import { GameEngine } from "./engine/game_engine";
import { createCultivationRouter } from "./routes/cultivation";

function createStorage(): IStorage {
  switch (config.dbType) {
    case "memory":
      console.log("[cult-server] Using memory storage");
      return new MemoryStorage();
    case "json_file":
    default:
      console.log(`[cult-server] Using JSON file storage: ${config.jsonDbPath}`);
      return new JsonFileStorage(config.jsonDbPath);
  }
}

function main(): void {
  const app = express();
  const port = parseInt(process.env.CULT_PORT || "3001", 10);

  app.use(express.json({ limit: "200kb" }));

  app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    if (req.method === "OPTIONS") { res.sendStatus(200); return; }
    next();
  });

  app.use((req, res, next) => {
    const start = Date.now();
    res.on("finish", () => {
      console.log(`[http] ${req.method} ${req.path} -> ${res.statusCode} (${Date.now() - start}ms)`);
    });
    next();
  });

  const storage = createStorage();
  const engine = new GameEngine(path.resolve(__dirname, "../../config"));

  console.log("[cult-server] Cultivation engine loaded");
  console.log(`[cult-server] Realms: ${engine.getCultivationConfig()?.realms.length ?? 0}`);

  app.use("/api/cultivation", createCultivationRouter(storage, engine));

  app.get("/api/health", (_req, res) => res.json({ status: "ok" }));

  app.listen(port, () => {
    console.log(`[cult-server] Listening on http://localhost:${port}`);
    console.log(`  POST /api/cultivation/tick`);
    console.log(`  POST /api/cultivation/consume`);
    console.log(`  POST /api/cultivation/breakthrough`);
  });
}

main();
