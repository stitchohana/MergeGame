import type { GameState } from "../storage/interface";
export type PurchaseResource = "stamina" | "qi";
export interface ResourcePurchaseProgress {
    period_key: string;
    stamina: number;
    qi: number;
}
export interface ResourcePurchaseReceipt {
    request_id: string;
    signature: string;
    resource: PurchaseResource;
    cost: number;
    amount: number;
}
export declare class ResourcePurchaseService {
    private addStamina;
    private baseCost;
    private increment;
    private amount;
    private resetHour;
    constructor(config: any, addStamina: (state: GameState, amount: number, now: number) => void);
    periodKey(now?: number): string;
    offers(state: GameState, now?: number): {
        period_key: string;
        reset_hour: number;
        cost_increment: number;
        stamina: {
            purchase_count: number;
            cost: number;
            amount: number;
        };
        qi: {
            purchase_count: number;
            cost: number;
            amount: number;
        };
    };
    buy(state: GameState, resource: PurchaseResource, expectedCount: number, period: string, requestId: string, now?: number): {
        ok: false;
        reason: string;
        already_purchased?: undefined;
        resource?: undefined;
        cost?: undefined;
        amount?: undefined;
    } | {
        ok: true;
        already_purchased: boolean;
        resource: PurchaseResource;
        cost: number;
        amount: number;
        reason?: undefined;
    };
}
