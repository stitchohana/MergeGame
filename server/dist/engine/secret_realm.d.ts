import type { GameState } from "../storage/interface";
import type { GameEngine } from "./game_engine";
export interface RealmItem {
    uid: number;
    id: string;
    immovable: boolean;
}
export interface RealmCell {
    col: number;
    row: number;
    fog: boolean;
    item?: RealmItem;
    monster?: string;
    submitted?: Record<string, number>;
}
export interface RealmDropEffect {
    item: RealmItem;
    col?: number;
    row?: number;
    stash?: boolean;
}
export interface RealmActionEffects {
    request_id: string;
    kind: "merge" | "fight";
    col: number;
    row: number;
    submitted?: Record<string, number>;
    defeated?: boolean;
    drops: RealmDropEffect[];
}
export interface RealmProgress {
    period: string;
    version: number;
    stage: number;
    start_row: number;
    completed: boolean;
    cells: RealmCell[];
    stash: RealmItem[];
    receipts: Array<{
        request_id: string;
        signature: string;
        effects?: RealmActionEffects;
    }>;
}
interface ItemDef {
    id: string;
    chain: string;
    level: number;
    name: string;
    value: number;
}
interface Drop {
    id: string;
    count: number;
    immovable: boolean;
}
interface RealmConfig {
    settings: {
        activity_id: number;
        period: string;
        cols: number;
        rows: number;
        advance: number;
    }[];
    items: ItemDef[];
    layout: Array<{
        col: number;
        row: number;
        fog: boolean;
        id: string;
        immovable: boolean;
        monster: string;
    }>;
    stages: Array<{
        boss: string;
        name: string;
    }>;
    merge_drops: Array<{
        min_level: number;
        max_level: number;
        drops: Drop[];
    }>;
    order_supply: Drop[];
    order_supply_realms: Array<{
        cultivation_min: number;
        cultivation_max: number;
        drops: Drop[];
    }>;
}
export declare class SecretRealmService {
    private engine;
    readonly config?: RealmConfig;
    private defs;
    private monsters;
    private bossFogStages;
    constructor(raw: any, engine: GameEngine);
    available(state: GameState): boolean;
    initialize(state: GameState): boolean;
    private setViewport;
    private visible;
    private remainingMobs;
    private bossFogLocked;
    private unlockBossFog;
    private definition;
    view(state: GameState): any;
    private inventory;
    private grant;
    awardOrder(state: GameState): void;
    transact(state: GameState, body: any): any;
    gmGrantSwords(state: GameState, level: unknown, amount: unknown): any;
    previewMerge(state: GameState, body: any): any;
    private applyAction;
}
export {};
