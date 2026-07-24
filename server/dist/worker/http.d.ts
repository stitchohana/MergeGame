export interface WorkerRequest {
    method: string;
    path: string;
    headers: Record<string, string | undefined>;
    body: any;
    query: Record<string, string | undefined>;
    auth?: {
        userId: string;
        deviceId: string;
    };
}
export declare class WorkerResponse {
    statusCode: number;
    headersSent: boolean;
    private payload;
    private headers;
    status(code: number): this;
    header(name: string, value: string): this;
    json(value: unknown): this;
    sendStatus(code: number): this;
    toResponse(): Response;
}
export type NextFunction = () => Promise<void>;
export type Handler = (req: WorkerRequest, res: WorkerResponse, next?: NextFunction) => void | Promise<void>;
export declare class Router {
    private middleware;
    private routes;
    use(handler: Handler): void;
    get(path: string, handler: Handler): void;
    post(path: string, handler: Handler): void;
    handle(req: WorkerRequest, res: WorkerResponse): Promise<boolean>;
}
