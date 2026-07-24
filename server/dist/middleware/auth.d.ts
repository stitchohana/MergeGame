import { NextFunction, WorkerRequest as Request, WorkerResponse as Response } from "../worker/http";
export interface AuthPayload {
    userId: string;
    deviceId: string;
}
export declare function createAuthRequired(jwtSecret: string): (req: Request, res: Response, next: NextFunction) => Promise<void>;
export declare function signToken(payload: AuthPayload, jwtSecret: string): Promise<string>;
