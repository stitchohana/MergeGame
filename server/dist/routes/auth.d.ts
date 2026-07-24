import { Router } from "../worker/http";
import { IStorage } from "../storage/interface";
export declare function createAuthRouter(storage: IStorage, jwtSecret: string): Router;
