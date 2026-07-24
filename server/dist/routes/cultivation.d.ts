import { Router } from "../worker/http";
import { IStorage } from "../storage/interface";
import { GameEngine } from "../engine/game_engine";
export declare function createCultivationRouter(storage: IStorage, engine: GameEngine, jwtSecret: string): Router;
