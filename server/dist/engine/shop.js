"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ShopService = void 0;
class ShopService {
    item;
    recipes;
    purchaseLimit = 5;
    refreshInterval = 4 * 60 * 60 * 1000;
    refreshCost;
    baseItems;
    constructor(config, item, recipes) {
        this.item = item;
        this.recipes = recipes;
        this.refreshCost = Number.isSafeInteger(Number(config?.refresh_cost)) && Number(config.refresh_cost) > 0
            ? Number(config.refresh_cost) : 100;
        this.baseItems = (config?.items ?? []).filter((offer) => Number.isSafeInteger(offer.id) && Number.isSafeInteger(offer.price) && offer.price > 0);
    }
    allowed(id) {
        const def = this.item(id);
        return !!def && def.type !== 4 && !this.recipes.some(recipe => recipe.result === id);
    }
    rebuild(state, nextRefreshAt) {
        const required = new Set();
        const visit = (id, visiting = new Set()) => {
            if (!this.item(id) || visiting.has(id))
                return;
            const recipes = this.recipes.filter(recipe => recipe.result === id);
            if (recipes.length > 0) {
                const path = new Set(visiting).add(id);
                for (const recipe of recipes)
                    for (const ingredient of recipe.ingredients)
                        visit(ingredient, path);
            }
            else if (this.allowed(id))
                required.add(id);
        };
        for (const order of state.meridian_acupoints ?? []) {
            if (order.completed)
                continue;
            const ids = order.item_ids;
            for (const id of ids)
                visit(Number(id));
        }
        // The shop table supplies prices, not extra merchandise unrelated to orders.
        const configuredPrices = new Map(this.baseItems.map(offer => [offer.id, offer.price]));
        const prices = new Map();
        for (const id of required) {
            prices.set(id, configuredPrices.get(id) ?? Math.max(1, Math.ceil(Number(this.item(id)?.value) || 1)));
        }
        const items = [...prices].map(([id, price]) => ({ id, price, purchased: 0, order_required: required.has(id) }));
        items.sort((a, b) => Number(b.order_required) - Number(a.order_required) || a.id - b.id);
        state.shop = { revision: (state.shop?.revision ?? 0) + 1, next_refresh_at: nextRefreshAt, items };
        state.version++;
    }
    ensure(state, now = Date.now()) {
        const shop = state.shop;
        if (!shop) {
            this.rebuild(state, now + this.refreshInterval);
            return true;
        }
        if (now >= shop.next_refresh_at) {
            const elapsed = Math.floor((now - shop.next_refresh_at) / this.refreshInterval) + 1;
            this.rebuild(state, shop.next_refresh_at + elapsed * this.refreshInterval);
            return true;
        }
        return false;
    }
    view(state, now = Date.now()) {
        this.ensure(state, now);
        const shop = state.shop;
        return {
            revision: shop.revision, next_refresh_at: shop.next_refresh_at,
            remaining_seconds: Math.max(0, Math.ceil((shop.next_refresh_at - now) / 1000)),
            refresh_cost: this.refreshCost, purchase_limit: this.purchaseLimit,
            items: shop.items.map(offer => ({ ...offer, name: this.item(offer.id).name,
                purchase_limit: this.purchaseLimit, remaining: Math.max(0, this.purchaseLimit - offer.purchased) })),
        };
    }
    refresh(state, expectedRevision, now = Date.now()) {
        this.ensure(state, now);
        if (state.shop.revision !== expectedRevision)
            return { ok: false, reason: "shop_changed" };
        if (state.spirit_stones < this.refreshCost)
            return { ok: false, reason: "insufficient_stones" };
        state.spirit_stones -= this.refreshCost;
        this.rebuild(state, now + this.refreshInterval);
        return { ok: true };
    }
}
exports.ShopService = ShopService;
