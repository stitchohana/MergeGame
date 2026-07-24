export interface WorkerRequest {
	method: string;
	path: string;
	headers: Record<string, string | undefined>;
	body: any;
	query: Record<string, string | undefined>;
	auth?: { userId: string; deviceId: string };
}

export class WorkerResponse {
	statusCode = 200;
	headersSent = false;
	private payload: string | null = null;
	private headers = new Headers({ "Content-Type": "application/json; charset=utf-8" });

	status(code: number): this { this.statusCode = code; return this; }
	header(name: string, value: string): this { this.headers.set(name, value); return this; }
	json(value: unknown): this {
		this.payload = JSON.stringify(value);
		this.headersSent = true;
		return this;
	}
	sendStatus(code: number): this { return this.status(code).json({ status: code }); }
	toResponse(): Response { return new Response(this.payload ?? "", { status: this.statusCode, headers: this.headers }); }
}

export type NextFunction = () => Promise<void>;
export type Handler = (req: WorkerRequest, res: WorkerResponse, next: NextFunction) => void | Promise<void>;

export class Router {
	private middleware: Handler[] = [];
	private routes: Array<{ method: string; path: string; handlers: Handler[] }> = [];

	use(handler: Handler): void { this.middleware.push(handler); }
	get(path: string, handler: Handler): void { this.routes.push({ method: "GET", path, handlers: [handler] }); }
	post(path: string, handler: Handler): void { this.routes.push({ method: "POST", path, handlers: [handler] }); }

	async handle(req: WorkerRequest, res: WorkerResponse): Promise<boolean> {
		const route = this.routes.find((item) => item.method === req.method && item.path === req.path);
		if (!route) return false;
		const handlers = [...this.middleware, ...route.handlers];
		const dispatch = async (index: number): Promise<void> => {
			if (index >= handlers.length || res.headersSent) return;
			let advanced = false;
			await handlers[index](req, res, async () => { advanced = true; await dispatch(index + 1); });
			if (advanced) return;
		};
		await dispatch(0);
		return true;
	}
}
