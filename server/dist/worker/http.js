"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Router = exports.WorkerResponse = void 0;
class WorkerResponse {
    statusCode = 200;
    headersSent = false;
    payload = null;
    headers = new Headers({ "Content-Type": "application/json; charset=utf-8" });
    status(code) { this.statusCode = code; return this; }
    header(name, value) { this.headers.set(name, value); return this; }
    json(value) {
        this.payload = JSON.stringify(value);
        this.headersSent = true;
        return this;
    }
    sendStatus(code) { return this.status(code).json({ status: code }); }
    toResponse() { return new Response(this.payload ?? "", { status: this.statusCode, headers: this.headers }); }
}
exports.WorkerResponse = WorkerResponse;
class Router {
    middleware = [];
    routes = [];
    use(handler) { this.middleware.push(handler); }
    get(path, handler) { this.routes.push({ method: "GET", path, handlers: [handler] }); }
    post(path, handler) { this.routes.push({ method: "POST", path, handlers: [handler] }); }
    async handle(req, res) {
        const route = this.routes.find((item) => item.method === req.method && item.path === req.path);
        if (!route)
            return false;
        const handlers = [...this.middleware, ...route.handlers];
        const dispatch = async (index) => {
            if (index >= handlers.length || res.headersSent)
                return;
            let advanced = false;
            await handlers[index](req, res, async () => { advanced = true; await dispatch(index + 1); });
            if (advanced)
                return;
        };
        await dispatch(0);
        return true;
    }
}
exports.Router = Router;
