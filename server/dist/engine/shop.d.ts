import type { GameState } from "../storage/interface";
export interface ShopOffer {
    id: number;
    price: number;
    purchased: number;
    order_required: boolean;
}
export interface ShopProgress {
    revision: number;
    next_refresh_at: number;
    items: ShopOffer[];
}
type Item = {
    id: number;
    name: string;
    type: number;
    value?: number;
};
type Recipe = {
    result: number;
    ingredients: number[];
};
export declare class ShopService {
    private readonly item;
    private readonly recipes;
    readonly purchaseLimit = 5;
    readonly refreshInterval: number;
    readonly refreshCost: number;
    private readonly baseItems;
    constructor(config: any, item: (id: number) => Item | null, recipes: Recipe[]);
    private allowed;
    private rebuild;
    ensure(state: GameState, now?: number): boolean;
    view(state: GameState, now?: number): {
        revision: number;
        next_refresh_at: number;
        remaining_seconds: number;
        refresh_cost: number;
        purchase_limit: number;
        items: {
            name: string;
            purchase_limit: number;
            remaining: number;
            id: number;
            price: number;
            purchased: number;
            order_required: boolean;
        }[];
    };
    refresh(state: GameState, expectedRevision: number, now?: number): {
        ok: false;
        reason: string;
    } | {
        ok: true;
        reason?: undefined;
    };
}
export {};
