"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const game_engine_1 = require("../engine/game_engine");
const auth_1 = require("../routes/auth");
const cultivation_1 = require("../routes/cultivation");
const game_1 = require("../routes/game");
const gm_1 = require("../routes/gm");
const d1_1 = require("../storage/d1");
const http_1 = require("./http");
const config_data_1 = require("./config_data");
const engine = new game_engine_1.GameEngine(config_data_1.gameConfigTables);
function allowedOrigin(request, configuredOrigin) {
    const origin = request.headers.get("Origin");
    if (!origin)
        return null;
    if (origin.startsWith("http://localhost") || origin.startsWith("http://127.0.0.1") || origin === configuredOrigin) {
        return origin;
    }
    return null;
}
async function parseBody(request) {
    if (request.method !== "POST")
        return {};
    const contentType = request.headers.get("Content-Type") || "";
    if (!contentType.includes("application/json"))
        return {};
    const contentLength = Number(request.headers.get("Content-Length") || "0");
    if (contentLength > 200 * 1024)
        throw new Error("body_too_large");
    return request.json();
}
function requestFor(path, request, body) {
    const url = new URL(request.url);
    const headers = {};
    request.headers.forEach((value, name) => { headers[name.toLowerCase()] = value; });
    const query = {};
    url.searchParams.forEach((value, key) => { query[key] = value; });
    return { method: request.method, path, headers, body, query };
}
function mountedRouter(pathname, storage, env) {
    if (pathname.startsWith("/api/auth/"))
        return { router: (0, auth_1.createAuthRouter)(storage, env.JWT_SECRET), routePath: pathname.slice("/api/auth".length) };
    if (pathname.startsWith("/api/game/"))
        return { router: (0, game_1.createGameRouter)(storage, engine, env.JWT_SECRET), routePath: pathname.slice("/api/game".length) };
    if (pathname.startsWith("/api/cultivation/"))
        return { router: (0, cultivation_1.createCultivationRouter)(storage, engine, env.JWT_SECRET), routePath: pathname.slice("/api/cultivation".length) };
    if (pathname.startsWith("/api/gm/"))
        return { router: (0, gm_1.createGMRouter)(storage, engine, env.JWT_SECRET, env.GM_KEY || ""), routePath: pathname.slice("/api/gm".length) };
    return null;
}
exports.default = {
    async fetch(request, env) {
        const corsOrigin = allowedOrigin(request, env.CORS_ORIGIN);
        if (request.method === "OPTIONS") {
            const headers = new Headers({
                "Access-Control-Allow-Headers": "Authorization, Content-Type",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            });
            if (corsOrigin)
                headers.set("Access-Control-Allow-Origin", corsOrigin);
            return new Response(null, { status: 204, headers });
        }
        const url = new URL(request.url);
        const res = new http_1.WorkerResponse();
        res.header("Access-Control-Allow-Headers", "Authorization, Content-Type");
        res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        if (corsOrigin)
            res.header("Access-Control-Allow-Origin", corsOrigin);
        if (url.pathname === "/api/health" && request.method === "GET") {
            return res.json({ status: "ok", maintenance: env.MAINTENANCE_MODE === "true" }).toResponse();
        }
        if (env.MAINTENANCE_MODE === "true") {
            res.header("Retry-After", "30");
            return res.status(503).json({ error: "maintenance" }).toResponse();
        }
        if (!env.JWT_SECRET) {
            return res.status(500).json({ error: "server_misconfigured" }).toResponse();
        }
        let body;
        try {
            body = await parseBody(request);
        }
        catch {
            return res.status(400).json({ error: "invalid_json" }).toResponse();
        }
        const storage = new d1_1.D1Storage(env.DB);
        const mounted = mountedRouter(url.pathname, storage, env);
        if (!mounted)
            return res.status(404).json({ error: "not_found" }).toResponse();
        try {
            const handled = await mounted.router.handle(requestFor(mounted.routePath, request, body), res);
            if (!handled)
                return res.status(404).json({ error: "not_found" }).toResponse();
            return res.toResponse();
        }
        catch (error) {
            console.error("[worker] unhandled request error", error);
            return res.status(500).json({ error: "internal_error" }).toResponse();
        }
    },
};
