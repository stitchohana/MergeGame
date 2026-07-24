import { GameEngine } from "../engine/game_engine";
import { createAuthRouter } from "../routes/auth";
import { createCultivationRouter } from "../routes/cultivation";
import { createGameRouter } from "../routes/game";
import { createGMRouter } from "../routes/gm";
import { D1Storage } from "../storage/d1";
import { Router, WorkerRequest, WorkerResponse } from "./http";
import { gameConfigTables } from "./config_data";

export interface Env {
	DB: D1Database;
	JWT_SECRET: string;
	GM_KEY?: string;
	CORS_ORIGIN?: string;
	MAINTENANCE_MODE?: string;
}

const engine = new GameEngine(gameConfigTables);

function allowedOrigin(request: Request, configuredOrigin?: string): string | null {
	const origin = request.headers.get("Origin");
	if (!origin) return null;
	if (origin.startsWith("http://localhost") || origin.startsWith("http://127.0.0.1") || origin === configuredOrigin) {
		return origin;
	}
	return null;
}

async function parseBody(request: Request): Promise<unknown> {
	if (request.method !== "POST") return {};
	const contentType = request.headers.get("Content-Type") || "";
	if (!contentType.includes("application/json")) return {};
	const contentLength = Number(request.headers.get("Content-Length") || "0");
	if (contentLength > 200 * 1024) throw new Error("body_too_large");
	return request.json();
}

function requestFor(path: string, request: Request, body: unknown): WorkerRequest {
	const url = new URL(request.url);
	const headers: Record<string, string | undefined> = {};
	request.headers.forEach((value, name) => { headers[name.toLowerCase()] = value; });
	const query: Record<string, string | undefined> = {};
	url.searchParams.forEach((value, key) => { query[key] = value; });
	return { method: request.method, path, headers, body, query };
}

function mountedRouter(pathname: string, storage: D1Storage, env: Env): { router: Router; routePath: string } | null {
	if (pathname.startsWith("/api/auth/")) return { router: createAuthRouter(storage, env.JWT_SECRET), routePath: pathname.slice("/api/auth".length) };
	if (pathname.startsWith("/api/game/")) return { router: createGameRouter(storage, engine, env.JWT_SECRET), routePath: pathname.slice("/api/game".length) };
	if (pathname.startsWith("/api/cultivation/")) return { router: createCultivationRouter(storage, engine, env.JWT_SECRET), routePath: pathname.slice("/api/cultivation".length) };
	if (pathname.startsWith("/api/gm/")) return { router: createGMRouter(storage, engine, env.JWT_SECRET, env.GM_KEY || ""), routePath: pathname.slice("/api/gm".length) };
	return null;
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const corsOrigin = allowedOrigin(request, env.CORS_ORIGIN);
		if (request.method === "OPTIONS") {
			const headers = new Headers({
				"Access-Control-Allow-Headers": "Authorization, Content-Type",
				"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
			});
			if (corsOrigin) headers.set("Access-Control-Allow-Origin", corsOrigin);
			return new Response(null, { status: 204, headers });
		}

		const url = new URL(request.url);
		const res = new WorkerResponse();
		res.header("Access-Control-Allow-Headers", "Authorization, Content-Type");
		res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
		if (corsOrigin) res.header("Access-Control-Allow-Origin", corsOrigin);

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

		let body: unknown;
		try {
			body = await parseBody(request);
		} catch {
			return res.status(400).json({ error: "invalid_json" }).toResponse();
		}
		const storage = new D1Storage(env.DB);
		const mounted = mountedRouter(url.pathname, storage, env);
		if (!mounted) return res.status(404).json({ error: "not_found" }).toResponse();

		try {
			const handled = await mounted.router.handle(requestFor(mounted.routePath, request, body), res);
			if (!handled) return res.status(404).json({ error: "not_found" }).toResponse();
			return res.toResponse();
		} catch (error) {
			console.error("[worker] unhandled request error", error);
			return res.status(500).json({ error: "internal_error" }).toResponse();
		}
	},
};
