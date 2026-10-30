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

type Item = { id: number; name: string; type: number; value?: number };
type Recipe = { result: number; ingredients: number[] };

export class ShopService {
  readonly purchaseLimit = 5;
  readonly refreshInterval = 4 * 60 * 60 * 1000;
  readonly refreshCost: number;
  private readonly baseItems: Array<{ id: number; price: number }>;

  constructor(config: any, private readonly item: (id: number) => Item | null,
    private readonly recipes: Recipe[]) {
    this.refreshCost = Number.isSafeInteger(Number(config?.refresh_cost)) && Number(config.refresh_cost) > 0
      ? Number(config.refresh_cost) : 100;
    this.baseItems = (config?.items ?? []).filter((offer: any) =>
      Number.isSafeInteger(offer.id) && Number.isSafeInteger(offer.price) && offer.price > 0);
  }

  private allowed(id: number): boolean {
    const def = this.item(id);
    return !!def && def.type !== 4 && !this.recipes.some(recipe => recipe.result === id);
  }

  private rebuild(state: GameState, nextRefreshAt: number): void {
    const required = new Set<number>();
    const visit = (id: number, visiting = new Set<number>()): void => {
      if (!this.item(id) || visiting.has(id)) return;
      const recipes = this.recipes.filter(recipe => recipe.result === id);
      if (recipes.length > 0) {
        const path = new Set(visiting).add(id);
        for (const recipe of recipes) for (const ingredient of recipe.ingredients) visit(ingredient, path);
      } else if (this.allowed(id)) required.add(id);
    };
    for (const order of state.meridian_acupoints ?? []) {
      if (order.completed) continue;
      const ids: number[] = (order as any).item_ids;
      for (const id of ids) visit(Number(id));
    }
    // The shop table supplies prices, not extra merchandise unrelated to orders.
    const configuredPrices = new Map(this.baseItems.map(offer => [offer.id, offer.price]));
    const prices = new Map<number, number>();
    for (const id of required) {
      prices.set(id, configuredPrices.get(id) ?? Math.max(1, Math.ceil(Number(this.item(id)?.value) || 1)));
    }
    const items = [...prices].map(([id, price]) => ({ id, price, purchased: 0, order_required: required.has(id) }));
    items.sort((a, b) => Number(b.order_required) - Number(a.order_required) || a.id - b.id);
    state.shop = { revision: (state.shop?.revision ?? 0) + 1, next_refresh_at: nextRefreshAt, items };
    state.version++;
  }

  ensure(state: GameState, now = Date.now()): boolean {
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

  view(state: GameState, now = Date.now()) {
    this.ensure(state, now);
    const shop = state.shop!;
    return {
      revision: shop.revision, next_refresh_at: shop.next_refresh_at,
      remaining_seconds: Math.max(0, Math.ceil((shop.next_refresh_at - now) / 1000)),
      refresh_cost: this.refreshCost, purchase_limit: this.purchaseLimit,
      items: shop.items.map(offer => ({ ...offer, name: this.item(offer.id)!.name,
        purchase_limit: this.purchaseLimit, remaining: Math.max(0, this.purchaseLimit - offer.purchased) })),
    };
  }

  refresh(state: GameState, expectedRevision: number, now = Date.now()) {
    this.ensure(state, now);
    if (state.shop!.revision !== expectedRevision) return { ok: false as const, reason: "shop_changed" };
    if (state.spirit_stones < this.refreshCost) return { ok: false as const, reason: "insufficient_stones" };
    state.spirit_stones -= this.refreshCost;
    this.rebuild(state, now + this.refreshInterval);
    return { ok: true as const };
  }
}
