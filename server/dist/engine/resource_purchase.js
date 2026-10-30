"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ResourcePurchaseService = void 0;
class ResourcePurchaseService {
    addStamina;
    baseCost;
    increment;
    amount;
    resetHour;
    constructor(config, addStamina) {
        this.addStamina = addStamina;
        const positive = (value, fallback) => {
            const parsed = Number(value);
            return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
        };
        this.baseCost = positive(config?.resource_purchase?.base_cost, 100);
        this.increment = positive(config?.resource_purchase?.cost_increment, 100);
        this.amount = positive(config?.resource_purchase?.amount, 100);
        const hour = Number(config?.reset_hour ?? 5);
        this.resetHour = Number.isInteger(hour) && hour >= 0 && hour <= 23 ? hour : 5;
    }
    periodKey(now = Date.now()) {
        return new Date(now + (8 - this.resetHour) * 3600000).toISOString().slice(0, 10);
    }
    offers(state, now = Date.now()) {
        const period = this.periodKey(now);
        const progress = state.resource_purchase_progress;
        const count = (resource) => progress?.period_key === period
            && Number.isSafeInteger(progress[resource]) && progress[resource] >= 0 ? progress[resource] : 0;
        const offer = (resource) => ({
            purchase_count: count(resource),
            cost: this.baseCost + count(resource) * this.increment,
            amount: this.amount,
        });
        return { period_key: period, reset_hour: this.resetHour, cost_increment: this.increment,
            stamina: offer("stamina"), qi: offer("qi") };
    }
    buy(state, resource, expectedCount, period, requestId, now = Date.now()) {
        if ((resource !== "stamina" && resource !== "qi") || !Number.isSafeInteger(expectedCount) || expectedCount < 0
            || typeof period !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(period)
            || typeof requestId !== "string" || !requestId.trim() || requestId.length > 100) {
            return { ok: false, reason: "invalid_params" };
        }
        const signature = JSON.stringify([resource, expectedCount, period]);
        const previous = (state.resource_purchase_operations ?? []).find(receipt => receipt.request_id === requestId);
        if (previous) {
            if (previous.signature !== signature)
                return { ok: false, reason: "state_conflict" };
            return { ok: true, already_purchased: true, resource, cost: previous.cost, amount: previous.amount };
        }
        const offers = this.offers(state, now);
        const quote = offers[resource];
        if (period !== offers.period_key || expectedCount !== quote.purchase_count) {
            return { ok: false, reason: "state_conflict" };
        }
        if (!Number.isSafeInteger(quote.cost) || !Number.isSafeInteger(quote.purchase_count + 1)) {
            return { ok: false, reason: "invalid_price" };
        }
        if (state.spirit_stones < quote.cost)
            return { ok: false, reason: "insufficient_stones" };
        const balance = resource === "stamina" ? state.stamina : state.cultivation.current_qi;
        if (!Number.isSafeInteger(balance + quote.amount))
            return { ok: false, reason: "invalid_balance" };
        state.spirit_stones -= quote.cost;
        if (resource === "stamina")
            this.addStamina(state, quote.amount, now);
        else
            state.cultivation.current_qi += quote.amount;
        state.resource_purchase_progress = { period_key: offers.period_key,
            stamina: offers.stamina.purchase_count, qi: offers.qi.purchase_count,
            [resource]: quote.purchase_count + 1 };
        state.resource_purchase_operations = [...(state.resource_purchase_operations ?? []),
            { request_id: requestId, signature, resource, cost: quote.cost, amount: quote.amount }].slice(-32);
        state.version += 1;
        return { ok: true, already_purchased: false, resource, cost: quote.cost, amount: quote.amount };
    }
}
exports.ResourcePurchaseService = ResourcePurchaseService;
