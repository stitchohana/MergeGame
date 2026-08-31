export interface Env {
    DB: D1Database;
    JWT_SECRET: string;
    GM_KEY?: string;
    CORS_ORIGIN?: string;
    MAINTENANCE_MODE?: string;
}
declare const _default: {
    fetch(request: Request, env: Env): Promise<Response>;
};
export default _default;
