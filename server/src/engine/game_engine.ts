import * as fs from "fs";
import * as path from "path";
import { GameState, GridItem, CultivationData, QuestType, TokenType, RewardConfig, BattleMonster } from "../storage/interface";
import { QuestEngine } from "./quest_engine";
import { ActivityEngine } from "./activity_engine";

// --- Config types ---

interface ItemDef {
  id: number;
  level: number;
  name: string;
  icon: string;
  group_id: number;
  describe: string;
  type: number;
  value?: number;
  sell_price?: number;
  spawns?: { id: number; weight: number }[];
  effect_type?: number;
  effect_value?: number;
  atk?: number;
  recipes?: number[];
  max_charges?: number;
  recharge_time?: number;
  storage_slots?: number;
}

interface RecipeDef {
  id: number;
  name: string;
  ingredients: number[];
  result: number;
  craft_time: number;
  crafting_level: number;
  rewards?: RewardConfig;
}

interface StageDef {
  name: string;
  exp: number;
  max_qi: number;
  breakthrough_pill?: number;
}

interface CultivationConfig {
  stages: StageDef[];
}

// --- Item Table (enum variants for lookups) ---

export enum TableState {
  IDLE = 0,
  HAS_ITEMS = 1,
  CRAFTING = 2,
  READY = 3,
}

// --- Game Engine ---

export class GameEngine {
  readonly GRID_COLS = 7;
  readonly GRID_ROWS = 9;
  readonly MAX_CELLS = 63;

  private itemsById = new Map<number, ItemDef>();
  private itemsByTypeLevel = new Map<string, Map<number, ItemDef[]>>();
  private recipes: RecipeDef[] = [];
  private recipesByTable = new Map<number, RecipeDef[]>();
  private cultivation: CultivationConfig | null = null;

  get cultivationStages() { return this.cultivation?.stages ?? []; }
  private initialSetups = new Map<string, { id: number; col: number; row: number }[]>();
  staminaConfig = { max: 100, spawnCost: 10, regenInterval: 120, regenAmount: 1 };
  questResetHour = 0;
  private shopConfig = { shopItems: [] as any[], sellPrices: {} as Record<string, number>, buyPrices: {} as Record<string, number> };


  private meridianThresholds: any[] = [];
  private maps = new Map<number, any>();
  private monsters = new Map<number, any>();
  private rewardsTable = new Map<number, RewardConfig>();
  private homeMeridianDefs: any[] = [];
  questEngine: QuestEngine;
  activityEngine: ActivityEngine;

  constructor(configDir: string) {
    this.loadConfigs(configDir);
    this.questEngine = new QuestEngine(configDir);
    this.activityEngine = new ActivityEngine(configDir);
    this.loadRewards(path.join(configDir, "json_output", "rewards.json"));
    this.loadHomeMeridians(path.join(configDir, "json_output", "home_meridians.json"));
  }

  // --- Config loading ---

  private loadConfigs(configDir: string): void {
    this.loadItems(path.join(configDir, "json_output", "items.json"));
    this.loadCultivation(path.join(configDir, "json_output", "cultivation.json"));
    this.loadInitialSetup(path.join(configDir, "json_output", "initial_setup.json"));
    this.loadRecipes(path.join(configDir, "json_output", "recipes.json"));
    this.loadGameConfig(path.join(configDir, "json_output", "game_config.json"));
    this.loadShopConfig(path.join(configDir, "json_output", "shop.json"));
    this.loadMeridians(path.join(configDir, "json_output", "meridians.json"));
    this.loadExpedition(path.join(configDir, "json_output", "expedition.json"));
    console.log(`[engine] Configs loaded: ${this.itemsById.size} items, ${this.recipes.length} recipes, ${this.cultivation?.stages.length ?? 0} stages, ${this.meridianThresholds.length} meridian thresholds, ${this.maps.size} maps, ${this.monsters.size} monsters`);
  }

  private loadGameConfig(filePath: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      const s = data.stamina;
      if (s) {
        this.staminaConfig = {
          max: s.max ?? 100,
          spawnCost: s.spawn_cost ?? 10,
          regenInterval: s.regen_interval ?? 120,
          regenAmount: s.regen_amount ?? 1,
        };
        console.log(`[engine] Stamina config: max=${this.staminaConfig.max} cost=${this.staminaConfig.spawnCost} regen=${this.staminaConfig.regenAmount}/${this.staminaConfig.regenInterval}s`);
      }
      this.questResetHour = data.reset_hour ?? 0;
      if (this.questResetHour > 0) {
        console.log(`[engine] Daily reset hour: ${this.questResetHour}`);
      }
    } catch { /* ignore */ }
  }

  private loadShopConfig(filePath: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      this.shopConfig = {
        shopItems: data.items ?? [],
        sellPrices: {} as Record<string, number>,
        buyPrices: {} as Record<string, number>,
      };
      for (const s of this.shopConfig.shopItems) {
        this.shopConfig.buyPrices[String(s.id)] = s.price;
      }
      console.log(`[engine] Shop config: ${this.shopConfig.shopItems.length} items`);
    } catch { /* ignore */ }
  }

  getSellPrice(itemId: number): number {
    return this.getItemData(itemId)?.sell_price ?? 0;
  }

  getBuyPrice(itemId: number): number {
    return this.shopConfig.buyPrices[String(itemId)] ?? 0;
  }

  getShopItems(): any[] {
    return this.shopConfig.shopItems;
  }

  private loadItems(filePath: string): void {
    const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    const categories = ["regular", "launcher", "crafting", "effect"] as const;
    const typeMap: Record<string, number> = { regular: 0, launcher: 1, crafting: 2, effect: 5 };

    for (const cat of categories) {
      for (const item of data[cat] || []) {
        item.type = typeMap[cat];
        this.itemsById.set(item.id, item);

        if (!this.itemsByTypeLevel.has(item.type)) {
          this.itemsByTypeLevel.set(item.type, new Map());
        }
        const byLevel = this.itemsByTypeLevel.get(item.type)!;
        if (!byLevel.has(item.level)) {
          byLevel.set(item.level, []);
        }
        byLevel.get(item.level)!.push(item);
      }
    }
  }

  private loadRecipes(filePath: string): void {
    const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    this.recipes = data.recipes || [];
    this.recipesByTable.clear();
    for (const recipe of this.recipes) {
      for (const [, item] of this.itemsById) {
        const recipeIds: number[] = item.recipes || [];
        if (recipeIds.includes(recipe.id)) {
          if (!this.recipesByTable.has(item.id)) {
            this.recipesByTable.set(item.id, []);
          }
          this.recipesByTable.get(item.id)!.push(recipe);
        }
      }
    }
  }

  private loadCultivation(filePath: string): void {
    this.cultivation = JSON.parse(fs.readFileSync(filePath, "utf-8"));
  }



  private loadMeridians(filePath: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      this.meridianThresholds = data.thresholds || [];
    } catch { /* optional */ }
  }

  private loadExpedition(filePath: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      const maps = data.maps as any[] ?? [];
      for (const m of maps) this.maps.set(m.id, m);
      const monsters = data.monsters as any[] ?? [];
      for (const mo of monsters) this.monsters.set(mo.id, mo);
    } catch { /* optional */ }
  }

  private loadRewards(filePath: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      const rewards = data.rewards || {};
      for (const key of Object.keys(rewards)) {
        this.rewardsTable.set(Number(key), rewards[key] as RewardConfig);
      }
      console.log(`[engine] Loaded ${this.rewardsTable.size} reward configs`);
    } catch { /* rewards.json optional */ }
  }

  getRewardConfig(rewardId: number): RewardConfig | undefined {
    return this.rewardsTable.get(rewardId);
  }

  private loadHomeMeridians(filePath: string): void {
    try {
      const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      this.homeMeridianDefs = data.stages || [];
      console.log(`[engine] Loaded ${this.homeMeridianDefs.length} home meridian stages`);
    } catch { /* optional */ }
  }

  getHomeMeridianDefs(): any[] {
    return this.homeMeridianDefs.map(s => ({
      ...s,
      acupoint_rewards: typeof s.acupoint_rewards === "number" ? (this.rewardsTable.get(s.acupoint_rewards) ?? s.acupoint_rewards) : s.acupoint_rewards,
      circulation_rewards: typeof s.circulation_rewards === "number" ? (this.rewardsTable.get(s.circulation_rewards) ?? s.circulation_rewards) : s.circulation_rewards,
    }));
  }

  lightHomeAcupoint(state: GameState, stageIndex: number, acupointIndex: number):
    { ok: true; circulation_completed: boolean; cultivation: any; spirit_stones: number; stamina: number; pending_rewards: any[]; home_meridian_progress: any[] }
    | { ok: false; reason: string }
  {
    if (this.isBreakthroughReady(state.cultivation.current_level, state.cultivation.current_exp)) {
      return { ok: false, reason: "breakthrough_needed" };
    }
    if (stageIndex < 0 || stageIndex >= this.homeMeridianDefs.length) {
      return { ok: false, reason: "invalid_stage" };
    }
    const def = this.homeMeridianDefs[stageIndex];
    if (acupointIndex < 0 || acupointIndex >= def.acupoints) {
      return { ok: false, reason: "invalid_acupoint" };
    }

    // Init progress
    state.home_meridian_progress = state.home_meridian_progress || [];
    let stageProgress = state.home_meridian_progress.find(p => p.stage === stageIndex);
    if (!stageProgress) {
      stageProgress = { stage: stageIndex, lit: new Array(def.acupoints).fill(false), circulation_completed: false };
      state.home_meridian_progress.push(stageProgress);
    }
    if (stageProgress.lit[acupointIndex]) {
      return { ok: false, reason: "already_lit" };
    }
    if (stageProgress.circulation_completed) {
      return { ok: false, reason: "circulation_completed" };
    }

    // Check qi
    const qiCost: number = def.qi_cost ?? 10;
    if (state.cultivation.current_qi < qiCost) {
      return { ok: false, reason: "insufficient_qi" };
    }

    // Deduct qi
    state.cultivation.current_qi -= qiCost;

    // Light acupoint
    stageProgress.lit[acupointIndex] = true;

    // Acupoint reward
    let rewardsApplied: RewardConfig = { tokens: [], items: [] };
    if (def.acupoint_rewards) {
      const r = this.applyRewards(state, def.acupoint_rewards);
      rewardsApplied.tokens!.push(...(r.tokens || []));
      rewardsApplied.items!.push(...(r.items || []));
    }

    // Check circulation completion
    const allLit = stageProgress.lit.every(l => l);
    if (allLit) {
      stageProgress.circulation_completed = true;
      if (def.circulation_rewards) {
        const r = this.applyRewards(state, def.circulation_rewards);
        rewardsApplied.tokens!.push(...(r.tokens || []));
        rewardsApplied.items!.push(...(r.items || []));
      }
    }

    state.version += 1;
    return {
      ok: true,
      circulation_completed: allLit,
      cultivation: state.cultivation,
      spirit_stones: state.spirit_stones,
      stamina: state.stamina,
      pending_rewards: state.pending_rewards,
      home_meridian_progress: state.home_meridian_progress,
    };
  }

  getMonster(id: number): any {
    return this.monsters.get(id) ?? null;
  }

  generateMeridianRequirements(state: GameState): { acupoints: any[] } {
    const thresholds = this.meridianThresholds;
    if (!thresholds.length) return { acupoints: [] };

    const stageLevel = state.cultivation.current_level;
    const t = this._findMeridianThreshold(stageLevel) ?? thresholds[0];
    const foundIdx = thresholds.indexOf(t);
    const orderCount: number = t.order_count ?? t.acupoints ?? 3;
    const pool: number[] = t.item_pool ?? [];
    const typeMin: number = t.count_min ?? 1;
    const typeMax: number = t.count_max ?? 3;

    state.meridian_threshold_idx = foundIdx;
    const acupoints: any[] = [];
    for (let i = 0; i < orderCount; i++) {
      const order = this._genOneAcupoint(pool, typeMin, typeMax);
      if (order.total_value > 0) {
        Object.assign(order, this._buildMeridianOrderReward(t, order.total_value, state));
      }
      acupoints.push(order);
    }
    state.meridian_acupoints = acupoints;
    return { acupoints };
  }

  private _buildMeridianOrderReward(threshold: any, totalValue: number, state: GameState): any {
    const qiPerValue: number = Number(threshold?.qi_per_value ?? 1);
    const baseQi: number = Math.max(0, Math.round(totalValue * qiPerValue));
    const activityBonusRate: number = Math.max(0, Number(state.activity_reward_bonuses?.order_qi ?? 0));
    const activityBonusQi: number = Math.round(baseQi * activityBonusRate);
    return {
      rewards: { tokens: [{ token: TokenType.QI, amount: baseQi + activityBonusQi }], items: [] },
      base_qi: baseQi,
      activity_bonus_qi: activityBonusQi,
    };
  }

  private _scaleRewardConfig(rewards: RewardConfig | number, multiplier: number): RewardConfig {
    const base: RewardConfig = typeof rewards === "number"
      ? (this.rewardsTable.get(rewards) ?? { tokens: [], items: [] })
      : rewards;
    return {
      tokens: (base.tokens || []).map(t => ({ token: t.token, amount: t.amount * multiplier })),
      items: (base.items || []).map(i => ({ id: i.id, count: i.count * multiplier })),
    };
  }

  private _findMeridianThreshold(stageLevel: number): any {
    for (const t of this.meridianThresholds) {
      if (t.stage === stageLevel) return t;
    }
    return this.meridianThresholds[0] ?? null;
  }

  private _genOneAcupoint(pool: number[], typeMin: number, typeMax: number): any {
    const numTypes = typeMin + Math.floor(Math.random() * (typeMax - typeMin + 1));
    const pickedIds: number[] = [];
    const names: string[] = [];
    const items: any[] = [];
    let totalValue = 0;
    const available = [...pool];
    for (let j = 0; j < numTypes && available.length > 0; j++) {
      const idx = Math.floor(Math.random() * available.length);
      const itemId = available[idx];
      available.splice(idx, 1);
      const itemData = this.getItemData(itemId);
      const name = itemData?.name ?? `#${itemId}`;
      const value = itemData?.value ?? 0;
      totalValue += value;
      pickedIds.push(itemId);
      names.push(name);
      items.push({ item_id: itemId, name, value });
    }
    return { item_ids: pickedIds, name: names.join(", "), items, completed: false, total_value: totalValue };
  }

  private loadInitialSetup(filePath: string): void {
    const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    // Support both old flat format and new board-type format
    if (data.items) {
      this.initialSetups.set(0, data.items);
    } else {
      for (const key of Object.keys(data)) {
        const boardKey: number = key === "battle" ? 1 : 0;
        this.initialSetups.set(boardKey, data[key].items || []);
      }
    }
  }

  // --- Config queries ---

  getItemData(id: number): ItemDef | null {
    return this.itemsById.get(id) ?? null;
  }

  getItemByLevel(type: number, level: number, groupId = 0): ItemDef | null {
    const byLevel = this.itemsByTypeLevel.get(type);
    if (!byLevel) return null;
    const items = byLevel.get(level) || [];
    if (items.length === 0) return null;
    if (groupId === 0) return items[0];
    return items.find((i) => i.group_id === groupId) ?? null;
  }

  getNextLevel(type: number, level: number, groupId = 0): ItemDef | null {
    return this.getItemByLevel(type, level + 1, groupId);
  }

  rollSpawn(launcherId: number): ItemDef | null {
    const data = this.getItemData(launcherId);
    if (!data?.spawns || data.spawns.length === 0) return null;

    const totalWeight = data.spawns.reduce((sum, s) => sum + s.weight, 0);
    let roll = Math.floor(Math.random() * totalWeight);
    for (const s of data.spawns) {
      roll -= s.weight;
      if (roll < 0) return this.getItemData(s.id);
    }
    return this.getItemData(data.spawns[data.spawns.length - 1].id);
  }

  getRecipesForTable(tableId: number): RecipeDef[] {
    return this.recipesByTable.get(tableId) || [];
  }

  getCultivationConfig(): CultivationConfig | null {
    return this.cultivation;
  }

  getInitialSetup(boardType: number = 0) {
    return this.initialSetups.get(boardType) ?? [];
  }

  getMaxCharges(itemId: number): number {
    return this.getItemData(itemId)?.max_charges ?? 3;
  }

  _nextUid(state: GameState): number {
    state.uid_counter = (state.uid_counter ?? 0) + 1;
    return state.uid_counter!;
  }

  getRechargeTime(itemId: number): number {
    return this.getItemData(itemId)?.recharge_time ?? 60;
  }

  // --- Grid helpers ---

  isInBounds(col: number, row: number): boolean {
    return col >= 0 && col < this.GRID_COLS && row >= 0 && row < this.GRID_ROWS;
  }

  tickStamina(state: GameState): void {
    const now = Date.now();
    if (state.stamina >= this.staminaConfig.max) {
      state.last_stamina_tick = now;
      return;
    }
    const intervalMs = this.staminaConfig.regenInterval * 1000;
    while (now - state.last_stamina_tick >= intervalMs) {
      if (state.stamina >= this.staminaConfig.max) {
        state.last_stamina_tick = now;
        break;
      }
      state.stamina += this.staminaConfig.regenAmount;
      state.last_stamina_tick += intervalMs;
    }
    state.stamina = Math.min(state.stamina, this.staminaConfig.max);
  }

  getRegenRemainingMs(state: GameState): number {
    const nextTick = state.last_stamina_tick + this.staminaConfig.regenInterval * 1000;
    return Math.max(0, nextTick - Date.now());
  }

  private isLauncher(itemDef: ItemDef | null): boolean {
    if (!itemDef) return false;
    const spawns = itemDef.spawns;
    const maxCharges = itemDef.max_charges ?? 0;
    return (spawns && spawns.length > 0) || maxCharges > 0;
  }

  enrichGridWithRechargeRemaining(grid: any[]): void {
    const now = Date.now();
    for (const item of grid) {
      const itemDef = this.getItemData(item.id);
      if (!this.isLauncher(itemDef)) continue;
      const rt = itemDef.recharge_time ?? 0;
      if (rt <= 0) continue;
      const maxC = itemDef.max_charges ?? 3;
      const charges = item.charges ?? maxC;
      if (charges >= maxC) continue;
      const lct = item.last_charge_time ?? now;
      const elapsed = (now - lct) / 1000;
      if (elapsed < rt) {
        (item as any)._recharge_remaining = (rt - elapsed) * 1000;
      }
    }
  }

  tickLauncherRecharge(state: GameState): void {
    const now = Date.now();
    for (const item of state.grid) {
      const itemDef = this.getItemData(item.id);
      if (!this.isLauncher(itemDef)) continue;
      const rechargeTime = itemDef.recharge_time ?? 0;
      if (rechargeTime <= 0) continue;
      const maxC = itemDef.max_charges ?? 3;
      const charges = item.charges ?? maxC;
      if (charges >= maxC) continue;
      const lastTime = item.last_charge_time ?? now;
      const elapsed = (now - lastTime) / 1000;
      if (elapsed < rechargeTime) continue;
      item.charges = maxC;
      item.last_charge_time = now;
      console.log(`[engine] launcher recharge: #${item.id} at (${item.col},${item.row}) 0->${maxC} (rechargeTime=${rechargeTime}s)`);
    }
  }

  posKey(col: number, row: number): string {
    return `${col},${row}`;
  }

  getNeighbors(col: number, row: number): [number, number][] {
    const result: [number, number][] = [];
    const candidates: [number, number][] = [
      [col + 1, row],
      [col - 1, row],
      [col, row + 1],
      [col, row - 1],
    ];
    for (const [c, r] of candidates) {
      if (this.isInBounds(c, r)) result.push([c, r]);
    }
    return result;
  }

  findNearestEmpty(
    grid: Map<string, GridItem>,
    startCol: number,
    startRow: number
  ): { col: number; row: number } | null {
    const visited = new Set<string>();
    const queue: [number, number][] = [[startCol, startRow]];
    visited.add(this.posKey(startCol, startRow));

    while (queue.length > 0) {
      const [c, r] = queue.shift()!;
      const key = this.posKey(c, r);
      if (!grid.has(key)) return { col: c, row: r };

      for (const [nc, nr] of this.getNeighbors(c, r)) {
        const nk = this.posKey(nc, nr);
        if (!visited.has(nk)) {
          visited.add(nk);
          queue.push([nc, nr]);
        }
      }
    }
    return null;
  }

  findEmptyPos(grid: GridItem[]): { col: number; row: number } | null {
    const occupied = new Set<string>();
    for (const g of grid) {
      occupied.add(this.posKey(g.col, g.row));
    }
    for (let row = 0; row < this.GRID_ROWS; row++) {
      for (let col = 0; col < this.GRID_COLS; col++) {
        if (!occupied.has(this.posKey(col, row))) {
          return { col, row };
        }
      }
    }
    return null;
  }

  findEmptyByRow(grid: Map<string, GridItem>): { col: number; row: number } | null {
    for (let row = 0; row < this.GRID_ROWS; row++) {
      for (let col = 0; col < this.GRID_COLS; col++) {
        if (!grid.has(this.posKey(col, row))) {
          return { col, row };
        }
      }
    }
    return null;
  }

  // --- Generic reward distribution ---

  applyRewards(state: GameState, rewards: RewardConfig | number): RewardConfig {
    const result: RewardConfig = { tokens: [], items: [] };

    // Resolve reward ID to config
    if (typeof rewards === "number") {
      const resolved = this.rewardsTable.get(rewards);
      if (!resolved) {
        console.log(`[reward] unknown reward id: ${rewards}`);
        return result;
      }
      rewards = resolved;
    }

    // Token rewards — directly credited
    if (rewards.tokens) {
      for (const t of rewards.tokens) {
        switch (t.token) {
          case TokenType.SPIRIT_STONES:
            state.spirit_stones += t.amount;
            console.log(`[reward] +${t.amount} spirit_stones (total: ${state.spirit_stones})`);
            break;
          case TokenType.QI:
            state.cultivation.current_qi = Math.min(state.cultivation.max_qi, state.cultivation.current_qi + t.amount);
            console.log(`[reward] +${t.amount} qi (total: ${state.cultivation.current_qi}/${state.cultivation.max_qi})`);
            break;
          case TokenType.STAMINA:
            state.stamina += t.amount;
            console.log(`[reward] +${t.amount} stamina (total: ${state.stamina})`);
            break;
          case TokenType.EXP:
            this._addExp(state.cultivation, t.amount);
            console.log(`[reward] +${t.amount} exp (total: ${state.cultivation.current_exp})`);
            break;
          default:
            console.log(`[reward] unknown token type: ${t.token}`);
        }
        result.tokens!.push({ token: t.token, amount: t.amount });
      }
    }

    // Item rewards -> pending_rewards
    if (rewards.items) {
      state.pending_rewards = state.pending_rewards || [];
      for (const ri of rewards.items) {
        const itemData = this.getItemData(ri.id);
        const name = itemData?.name ?? `#${ri.id}`;
        for (let i = 0; i < ri.count; i++) {
          state.pending_rewards.push({
            uid: this._nextUid(state),
            id: ri.id,
            name,
          });
        }
        result.items!.push({ id: ri.id, count: ri.count });
        console.log(`[reward] +${ri.count}x ${name} -> pending_rewards`);
      }
    }

    return result;
  }

  // --- State initialization ---

  createInitialState(boardType: number = 0): GameState {
    const now = Date.now();
    const state: GameState = {
      grid: [],
      pouch: [],
      cultivation: {
        current_level: 1,
        current_exp: 0,
        total_exp: 0,
        current_qi: 0,
        max_qi: this.cultivation?.stages[0]?.max_qi ?? 100,
        last_tick_time: now,
      },
      stamina: 100,
      max_stamina: 100,
      last_stamina_tick: now,
      spirit_stones: 0,
      version: 0,
      board_type: boardType,
      uid_counter: 0,
      pending_rewards: [],
    };

    const setup = this.getInitialSetup(boardType);
    const itemNames: string[] = [];
    for (const entry of setup) {
      const itemDef = this.getItemData(entry.id);
      if (itemDef) {
        state.uid_counter = (state.uid_counter ?? 0) + 1;
        const gitem: GridItem = { uid: state.uid_counter, id: entry.id, col: entry.col, row: entry.row };
        if ((entry as any).immovable) gitem.immovable = true;
        if (this.isLauncher(itemDef)) {
          gitem.charges = this.getMaxCharges(entry.id);
          gitem.last_charge_time = now;
        }
        state.grid.push(gitem);
        itemNames.push(`${itemDef.name}(#${entry.id})@(${entry.col},${entry.row})${gitem.immovable ? " [immovable]" : ""}`);
      }
    }
    console.log(`[engine] createInitialState(${boardType}): ${state.grid.length} items — ${itemNames.join(", ")}`);
    return state;
  }


  switchBoard(state: GameState, boardType: string, battleMapId?: number, battleStage?: number): { ok: true; newVersion: number } | { ok: false; reason: string } {
    if (boardType === state.board_type) {
      state.version += 1;
      return { ok: true, newVersion: state.version };
    }

    if (boardType === 1) {
      if (battleMapId !== undefined) state.battle_map_id = battleMapId;
      if (battleStage !== undefined) state.battle_stage = battleStage;
      state.saved_grid = state.grid;
      if (state.battle_grid && state.battle_grid.length > 0) {
        state.grid = state.battle_grid;
        state.battle_grid = undefined;
        console.log(`[engine] board switched to battle: restored ${state.grid.length} battle items, saved ${state.saved_grid.length} main items | v${state.version}`);
      } else {
        state.grid = this._buildInitialGrid(1, state);
        console.log(`[engine] board switched to battle: new battle grid ${state.grid.length} items, saved ${state.saved_grid.length} main items | v${state.version}`);
      }
      state.board_type = 1;
    } else {
      state.battle_grid = state.grid;
      state.grid = state.saved_grid && state.saved_grid.length > 0
        ? state.saved_grid
        : this._buildInitialGrid(0, state);
      state.saved_grid = undefined;
      state.board_type = 0;
      console.log(`[engine] board switched to main: restored ${state.grid.length} main items, saved ${state.battle_grid.length} battle items | v${state.version}`);
    }
    state.version += 1;
    return { ok: true, newVersion: state.version };
  }

  private _buildInitialGrid(boardType: number, state: GameState): GridItem[] {
    const setup = this.getInitialSetup(boardType);
    const now = Date.now();
    const grid: GridItem[] = [];
    for (const entry of setup) {
      const itemDef = this.getItemData(entry.id);
      if (itemDef) {
        state.uid_counter = (state.uid_counter ?? 0) + 1;
        const gitem: GridItem = { uid: state.uid_counter, id: entry.id, col: entry.col, row: entry.row };
        if ((entry as any).immovable) gitem.immovable = true;
        if (this.isLauncher(itemDef)) {
          gitem.charges = this.getMaxCharges(entry.id);
          gitem.last_charge_time = now;
        }
        grid.push(gitem);
      }
    }
    return grid;
  }

  // --- Grid helpers ---

  buildGridMap(grid: GridItem[]): Map<string, GridItem> {
    const map = new Map<string, GridItem>();
    for (const item of grid) {
      map.set(this.posKey(item.col, item.row), item);
    }
    return map;
  }

  private gridToMap(grid: GridItem[]): Map<string, GridItem> {
    return this.buildGridMap(grid);
  }

  countItems(grid: GridItem[]): number {
    return grid.length;
  }

  isGridFull(grid: GridItem[]): boolean {
    return grid.length >= this.MAX_CELLS;
  }

  // --- Merge validation & execution ---

  validateMerge(
    state: GameState,
    fromCol: number,
    fromRow: number,
    toCol: number,
    toRow: number
  ): { valid: true; resultItem: ItemDef; fromItem: GridItem; toItem: GridItem } | { valid: false; reason: string } {
    const map = this.gridToMap(state.grid);
    const fromKey = this.posKey(fromCol, fromRow);
    const toKey = this.posKey(toCol, toRow);

    let itemA: GridItem | undefined;
    let itemB: GridItem | undefined;

    // Try exact position lookup first (skip if out of bounds)
    if (this.isInBounds(fromCol, fromRow)) {
      itemA = map.get(fromKey);
    }
    if (this.isInBounds(toCol, toRow)) {
      itemB = map.get(toKey);
    }

    // If either not found, search full grid by item ID
    // (handles position drift and out-of-bounds positions from client)
    if (!itemA && itemB) {
      itemA = state.grid.find((g) => g.id === itemB!.id && this.posKey(g.col, g.row) !== toKey);
    }
    if (!itemB && itemA) {
      itemB = state.grid.find((g) => g.id === itemA!.id && this.posKey(g.col, g.row) !== fromKey);
    }
    if (!itemA) return { valid: false, reason: "source_item_not_found" };
    if (!itemB) return { valid: false, reason: "target_item_not_found" };

    const dataA = this.getItemData(itemA.id);
    const dataB = this.getItemData(itemB.id);

    if (!dataA || !dataB) {
      return { valid: false, reason: "item_data_not_found" };
    }

    if (dataA.group_id !== dataB.group_id) {
      console.log(`[engine] merge rejected: group_id mismatch #${dataA.id}(gid=${dataA.group_id}) vs #${dataB.id}(gid=${dataB.group_id})`);
      console.log(`[engine] group_id_mismatch: client expects #${dataA.id}(gid=${dataA.group_id}) and #${dataB.id}(gid=${dataB.group_id})`);
      console.log(`[engine]   server grid at merge positions: from=(${fromCol},${fromRow}) id=${itemA.id} to=(${toCol},${toRow}) id=${itemB.id}`);
      console.log(`[engine]   full grid: [${state.grid.map(g => `${g.id}(${g.col},${g.row}):uid=${g.uid}`).join(", ")}]`);
      return { valid: false, reason: "group_id_mismatch" };
    }
    if (dataA.id !== dataB.id) {
      console.log(`[engine] merge rejected: item_id mismatch #${dataA.id} vs #${dataB.id}`);
      return { valid: false, reason: "item_id_mismatch" };
    }

    const nextItem = this.getNextLevel(dataA.type, dataA.level, dataA.group_id);
    if (!nextItem) {
      console.log(`[engine] merge rejected: #${dataA.id} already max level (level=${dataA.level})`);
      return { valid: false, reason: "already_max_level" };
    }

    return {
      valid: true,
      resultItem: nextItem,
      fromItem: itemA,
      toItem: itemB,
    };
  }

  executeMerge(
    state: GameState,
    fromCol: number,
    fromRow: number,
    toCol: number,
    toRow: number
  ): { ok: true; newVersion: number; resultUid: number; resultId: number; fromCol: number; fromRow: number; toCol: number; toRow: number } | { ok: false; reason: string } {
    const result = this.validateMerge(state, fromCol, fromRow, toCol, toRow);
    if (!result.valid) {
      console.log(`[engine] merge rejected: ${result.reason} | from=(${fromCol},${fromRow}) to=(${toCol},${toRow})`);
      return { ok: false, reason: result.reason };
    }

    const actualFromKey = this.posKey(result.fromItem.col, result.fromItem.row);
    const actualToKey = this.posKey(result.toItem.col, result.toItem.row);
    const fromId = result.fromItem.id;

    // Remove both items using their actual positions from the server's grid
    state.grid = state.grid.filter(
      (item) =>
        this.posKey(item.col, item.row) !== actualFromKey &&
        this.posKey(item.col, item.row) !== actualToKey
    );

    // Add merged item at the target position (where itemB was)
    const mergedItem: GridItem = { uid: this._nextUid(state), id: result.resultItem.id, col: result.toItem.col, row: result.toItem.row };
    if (result.resultItem.type === 1 || this.isLauncher(result.resultItem)) {
      mergedItem.charges = this.getMaxCharges(result.resultItem.id);
      mergedItem.last_charge_time = Date.now();
    }
    const fromAtk = result.fromItem.atk_base ?? 0;
    const toAtk = result.toItem.atk_base ?? 0;
    if (fromAtk > 0 || toAtk > 0) {
      mergedItem.atk_base = fromAtk + toAtk;
    }
    state.grid.push(mergedItem);

    state.version += 1;

    const mergedName = result.resultItem.name;
    const fromItem = this.getItemData(fromId);
    const fromName = fromItem?.name ?? `#${fromId}`;
    console.log(`[engine] merge: ${fromName}x2 -> ${mergedName} | grid=${state.grid.length}/63 | v${state.version}`);

    this.questEngine.incrementQuestProgress(state, QuestType.MERGE, 1, this);

    return {
      ok: true,
      newVersion: state.version,
      resultUid: mergedItem.uid ?? 0,
      resultId: result.resultItem.id,
      atkBase: mergedItem.atk_base ?? 0,
      fromCol: result.fromItem.col,
      fromRow: result.fromItem.row,
      toCol: result.toItem.col,
      toRow: result.toItem.row,
    };
  }

  // --- Launcher spawn ---

  executeSpawn(
    state: GameState,
    launcherCol: number,
    launcherRow: number
  ): { ok: true; spawnedUid: number; spawnedId: number; spawnedName: string; targetCol: number; targetRow: number; newVersion: number; charges: number; maxCharges: number; rechargeTime: number }
    | { ok: false; reason: string } {
    const map = this.gridToMap(state.grid);
    const launcherKey = this.posKey(launcherCol, launcherRow);
    const launcherItem = map.get(launcherKey);

    if (!launcherItem) return { ok: false, reason: "launcher_not_found" };

    const launcherData = this.getItemData(launcherItem.id);
    if (!launcherData || !this.isLauncher(launcherData)) {
      return { ok: false, reason: "not_a_launcher" };
    }

    // Launcher charges check
    const maxC = launcherData.max_charges ?? 3;
    const charges = launcherItem.charges ?? maxC;
    if (charges <= 0) {
      return { ok: false, reason: "no_charges" };
    }

    // Determine rolled ID: fixed spawns or random weighted
    let rolledId: number;
    const fixedSpawns = launcherData.fixed_spawns as number[] | undefined;
    if (fixedSpawns && fixedSpawns.length > 0) {
      const usedCount = maxC - charges; // times already used
      if (usedCount >= fixedSpawns.length) {
        return { ok: false, reason: "no_more_fixed_spawns" };
      }
      rolledId = fixedSpawns[usedCount];
    } else {
      const spawns = launcherData.spawns;
      if (!spawns || !spawns.length) return { ok: false, reason: "no_spawns" };
      const totalWeight: number = spawns.reduce((sum: number, s: any) => sum + s.weight, 0);
      let roll = Math.random() * totalWeight;
      rolledId = spawns[0].id;
      for (const s of spawns) {
        roll -= s.weight;
        if (roll <= 0) { rolledId = s.id; break; }
      }
    }

    // Cost check: skip for no_cost launchers, else qi/stamina
    const isBattle = state.board_type === 1;
    if (!launcherData.no_cost) {
      if (isBattle) {
        if (state.cultivation.current_qi < 1) {
          return { ok: false, reason: "insufficient_qi" };
        }
      } else {
        if (state.stamina < this.staminaConfig.spawnCost) {
          return { ok: false, reason: "insufficient_stamina" };
        }
      }
    }

    const spawnResult = this.getItemData(rolledId);
    if (!spawnResult) return { ok: false, reason: "spawn_failed" };

    const target = this.findNearestEmpty(map, launcherCol, launcherRow);
    if (!target) return { ok: false, reason: "no_empty_cell" };
    // Double-check: ensure the cell is truly empty in the grid array
    const targetKey = this.posKey(target.col, target.row);
    if (state.grid.some(g => this.posKey(g.col, g.row) === targetKey)) {
      console.log(`[engine] spawn: target (${target.col},${target.row}) already occupied! Grid has ${state.grid.length} items:`);
      state.grid.forEach(g => console.log(`  #${g.id} uid=${g.uid} at (${g.col},${g.row})`));
      return { ok: false, reason: "no_empty_cell" };
    }

    // Deduct cost (skip for no_cost launchers)
    if (!launcherData.no_cost) {
      if (isBattle) {
        state.cultivation.current_qi = Math.max(0, state.cultivation.current_qi - 1);
      } else {
        state.stamina = Math.max(0, state.stamina - this.staminaConfig.spawnCost);
      }
    }
    launcherItem.charges = charges - 1;
    launcherItem.last_charge_time = Date.now();

    // Remove launcher if charges depleted and no recharge
    if (launcherItem.charges <= 0 && (launcherData.recharge_time ?? -1) <= 0) {
      state.grid = state.grid.filter(
        (g) => !(g.col === launcherCol && g.row === launcherRow)
      );
      console.log(`[engine] launcher #${launcherItem.id} at (${launcherCol},${launcherRow}) depleted and removed`);
    }

    const newItem: GridItem = { uid: this._nextUid(state), id: spawnResult.id, col: target.col, row: target.row };
    if (spawnResult.type === 1 || this.isLauncher(spawnResult)) {
      newItem.charges = this.getMaxCharges(spawnResult.id);
      newItem.last_charge_time = Date.now();
    }
    if (launcherData.effect_type === 7) {
      const stage = this.cultivationStages[state.cultivation.current_level - 1];
      const stageAtk = (stage as any)?.atk ?? 0;
      newItem.atk_base = stageAtk + (launcherData.value ?? 0);
      console.log(`[engine] spawn: atk_base=${newItem.atk_base} (stageAtk=${stageAtk} + swordValue=${launcherData.value}) effect_type=${launcherData.effect_type}`);
    } else {
      console.log(`[engine] spawn: launcher #${launcherItem.id} effect_type=${launcherData.effect_type} — NOT atk boost`);
    }
    state.grid.push(newItem);
    state.version += 1;

    console.log(`[engine] spawn: launcher #${launcherItem.id} -> ${spawnResult.name}(#${spawnResult.id}) at (${target.col},${target.row}) | effect_value=${spawnResult.effect_value} atk_base=${newItem.atk_base ?? 0} | v${state.version}`);

    this.questEngine.incrementQuestProgress(state, QuestType.SPAWN, 1, this);

    return {
      ok: true,
      spawnedUid: newItem.uid ?? 0,
      spawnedId: spawnResult.id,
      spawnedName: spawnResult.name,
      targetCol: target.col,
      targetRow: target.row,
      newVersion: state.version,
      charges: launcherItem.charges,
      maxCharges: this.getMaxCharges(launcherItem.id),
      rechargeTime: launcherData.recharge_time ?? 0,
      atkBase: newItem.atk_base ?? 0,
    };
  }

  // --- Move item (for pushing items around) ---

  executeMove(
    state: GameState,
    fromCol: number,
    fromRow: number,
    toCol: number,
    toRow: number
  ): { ok: true; newVersion: number } | { ok: false; reason: string } {
    const fromKey = this.posKey(fromCol, fromRow);
    const toKey = this.posKey(toCol, toRow);

    if (fromCol === toCol && fromRow === toRow) {
      return { ok: false, reason: "same_position" };
    }

    const existsAtTarget = state.grid.some(
      (item) => this.posKey(item.col, item.row) === toKey
    );
    if (existsAtTarget) {
      return { ok: false, reason: "target_occupied" };
    }

    const targetItem = state.grid.find(
      (item) => this.posKey(item.col, item.row) === fromKey
    );
    if (!targetItem) {
      return { ok: false, reason: "source_item_not_found" };
    }

    if (targetItem.immovable) {
      return { ok: false, reason: "item_immovable" };
    }

    const itemName = this.getItemData(targetItem.id)?.name ?? ("#" + targetItem.id);
    console.log(`[engine] move: ${itemName} (${fromCol},${fromRow}) -> (${toCol},${toRow}) | v${state.version + 1}`);

    targetItem.col = toCol;
    targetItem.row = toRow;
    state.version += 1;

    return { ok: true, newVersion: state.version };
  }

  removeIngredientFromTable(
    state: GameState,
    tableCol: number,
    tableRow: number,
    ingredientId: number,
    targetCol: number,
    targetRow: number
  ): { ok: true; removed_id: number; removed_uid: number; table_col: number; table_row: number; target_col: number; target_row: number; newVersion: number } | { ok: false; reason: string } {
    const tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    );
    if (!tableItem?.craft) return { ok: false, reason: "table_not_found" };

    const craft = tableItem.craft;
    if (craft._craft_state === TableState.CRAFTING || craft._craft_state === TableState.READY) {
      return { ok: false, reason: "busy" };
    }

    const stored: Record<string, unknown>[] = craft._craft_stored;
    const idx = stored.findIndex((s: any) => s.id === ingredientId);
    if (idx < 0) return { ok: false, reason: "ingredient_not_in_table" };

    const removed = stored[idx];
    stored.splice(idx, 1);

    const ingName = this.getItemData(ingredientId)?.name ?? ("#" + ingredientId);
    console.log(`[engine] craft remove: ${ingName} from table -> grid (${targetCol},${targetRow}) | stored=${stored.length}`);

    if (!this.isInBounds(targetCol, targetRow)) {
      return { ok: false, reason: "target_out_of_bounds" };
    }
    const targetKey = this.posKey(targetCol, targetRow);
    if (state.grid.some((item) => this.posKey(item.col, item.row) === targetKey)) {
      return { ok: false, reason: "target_occupied" };
    }

    var newUid = this._nextUid(state);
    state.grid.push({ uid: newUid, id: ingredientId, col: targetCol, row: targetRow });
    state.version += 1;

    // Re-check recipe after removal
    const allowedRecipes = this.getRecipesForTable(tableItem.id);
    const matched = this.matchRecipe(craft._craft_stored, allowedRecipes);
    craft._craft_recipe = (matched as unknown as Record<string, unknown>) ?? {};

    return { ok: true, removed_id: ingredientId, removed_uid: newUid, table_col: tableCol, table_row: tableRow, target_col: targetCol, target_row: targetRow, newVersion: state.version };
  }

  // --- Crafting ---

  validateCraftStart(
    state: GameState,
    tableCol: number,
    tableRow: number
  ): { valid: true; recipe: RecipeDef } | { valid: false; reason: string } {
    let tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    );
    // If not at the expected position, search whole grid for a table with craft data
    if (!tableItem) {
      tableItem = state.grid.find((item) => item.craft && item.craft._craft_state === TableState.HAS_ITEMS) ?? undefined;
    }
    if (!tableItem) {
      console.log(`[engine] craft start rejected: table_not_found at (${tableCol},${tableRow}), grid has ${state.grid.length} items, tables with craft: ${state.grid.filter(i => i.craft).length}`);
      return { valid: false, reason: "table_not_found" };
    }

    const craft = tableItem.craft;
    if (!craft) return { valid: false, reason: "no_ingredients" };
    if (craft._craft_state === TableState.CRAFTING) {
      return { valid: false, reason: "already_crafting" };
    }
    if (craft._craft_state === TableState.READY) {
      return { valid: false, reason: "result_ready_retrieve_first" };
    }

    const recipe = craft._craft_recipe as unknown as RecipeDef | undefined;
    if (!recipe || !recipe.id) return { valid: false, reason: "no_matching_recipe" };

    return { valid: true, recipe };
  }

  executeCraftStart(
    state: GameState,
    tableCol: number,
    tableRow: number
  ): { ok: true; newVersion: number; recipe: RecipeDef } | { ok: false; reason: string } {
    const validation = this.validateCraftStart(state, tableCol, tableRow);
    if (!validation.valid) return { ok: false, reason: validation.reason };

    // Use the table found by validateCraftStart (may be at different position via fallback)
    let tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    );
    if (!tableItem) {
      tableItem = state.grid.find((item) => item.craft && item.craft._craft_state === TableState.HAS_ITEMS);
    }
    if (!tableItem?.craft) return { ok: false, reason: "table_not_found" };
    const craft = tableItem.craft;

    craft._craft_state = TableState.CRAFTING;
    craft._craft_progress = 0;
    craft._craft_stored = [];
    craft._craft_result_id = validation.recipe.result;
    craft._craft_start_time = Date.now();
    state.version += 1;

    const resultItem = this.getItemData(validation.recipe.result);
    const resultName = resultItem?.name ?? `#${validation.recipe.result}`;
    console.log(`[engine] craft start: "${validation.recipe.name}" -> ${resultName} | time=${validation.recipe.craft_time}s | v${state.version}`);

    return { ok: true, newVersion: state.version, recipe: validation.recipe };
  }

  executeCraftRetrieve(
    state: GameState,
    tableCol: number,
    tableRow: number
  ): { ok: true; resultUid: number; resultId: number; newVersion: number } | { ok: false; reason: string } {
    let tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    );
    // Fallback: search whole grid for a table with craft data
    if (!tableItem?.craft) {
      tableItem = state.grid.find((item) => item.craft && (item.craft._craft_state === TableState.CRAFTING || item.craft._craft_state === TableState.READY));
    }
    if (!tableItem?.craft) return { ok: false, reason: "table_not_found" };

    const craft = tableItem.craft;
    if (craft._craft_state !== TableState.CRAFTING && craft._craft_state !== TableState.READY) {
      return { ok: false, reason: "not_crafting" };
    }

    // Check if enough time has elapsed (server-authoritative timer)
    if (craft._craft_state === TableState.CRAFTING) {
      const recipe = craft._craft_recipe as unknown as RecipeDef | undefined;
      const craftTime = (recipe?.craft_time ?? 0) * 1000;
      const startTime = craft._craft_start_time ?? 0;
      const elapsed = Date.now() - startTime;
      if (elapsed < craftTime) {
        const remaining = Math.ceil((craftTime - elapsed) / 1000);
        return { ok: false, reason: `crafting_not_done remaining=${remaining}s` };
      }
    }

    const resultId = craft._craft_result_id;
    if (resultId <= 0) return { ok: false, reason: "no_result" };

    // Place result item on grid near the table
    const map = this.gridToMap(state.grid);
    const target = this.findNearestEmpty(map, tableItem.col, tableItem.row);
    const craftUid = this._nextUid(state);
    if (target) {
      state.grid.push({ uid: craftUid, id: resultId, col: target.col, row: target.row });
    }

    // Clear craft state
    delete tableItem.craft;
    state.version += 1;

    const retrievedItem = this.getItemData(resultId);
    const retrievedName = retrievedItem?.name ?? `#${resultId}`;
    console.log(`[engine] craft retrieve: -> ${retrievedName} uid=${craftUid} at (${target?.col ?? -1},${target?.row ?? -1}) | v${state.version}`);

    this.questEngine.incrementQuestProgress(state, QuestType.CRAFT, 1, this);

    return { ok: true, resultUid: craftUid, resultId, newVersion: state.version };
  }

  addIngredientToTable(
    state: GameState,
    tableCol: number,
    tableRow: number,
    ingredientId: number,
    fromCol: number,
    fromRow: number
  ): { ok: true; matched: boolean; newVersion: number } | { ok: false; reason: string } {
    if (!this.isInBounds(fromCol, fromRow)) return { ok: false, reason: "source_out_of_bounds" };
    if (!this.isInBounds(tableCol, tableRow)) return { ok: false, reason: "table_out_of_bounds" };
    // Remove ingredient from grid (quantity conservation)
    const fromKey = this.posKey(fromCol, fromRow);
    const gridItem = state.grid.find(
      (item) => this.posKey(item.col, item.row) === fromKey
    );
    if (!gridItem) return { ok: false, reason: "ingredient_not_found" };
    if (gridItem.id !== ingredientId) return { ok: false, reason: "ingredient_id_mismatch" };

    state.grid = state.grid.filter(
      (item) => this.posKey(item.col, item.row) !== fromKey
    );
    const ingName = this.getItemData(ingredientId)?.name ?? ("#" + ingredientId);
    console.log(`[engine] craft add: removed ${ingName} from grid (${fromCol},${fromRow})`);

    const tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    );

    if (!tableItem) return { ok: false, reason: "table_not_found" };

    const tableData = this.getItemData(tableItem.id);
    if (!tableData || tableData.type !== 2) {
      return { ok: false, reason: "not_a_crafting_table" };
    }

    // Initialize craft data if needed
    if (!tableItem.craft) {
      tableItem.craft = {
        _craft_init: true,
        _craft_state: TableState.IDLE,
        _craft_stored: [],
        _craft_recipe: {},
        _craft_progress: 0,
        _craft_result_id: -1,
        _craft_start_time: 0,
      };
    }

    const craft = tableItem.craft;
    if (craft._craft_state === TableState.CRAFTING || craft._craft_state === TableState.READY) {
      return { ok: false, reason: "busy" };
    }

    const ingredientData = this.getItemData(ingredientId);
    if (!ingredientData) return { ok: false, reason: "invalid_ingredient" };

    craft._craft_stored.push({ id: ingredientId } as Record<string, unknown>);
    craft._craft_state = TableState.HAS_ITEMS;

    // Check recipe match
    const allowedRecipes = this.getRecipesForTable(tableItem.id);
    const matched = this.matchRecipe(craft._craft_stored, allowedRecipes);
    if (matched) {
      craft._craft_recipe = matched as unknown as Record<string, unknown>;
      console.log(`[engine] craft add: #${ingredientId} -> recipe matched "${matched.name}" | stored=${craft._craft_stored.length}`);
    } else {
      craft._craft_recipe = {};
      console.log(`[engine] craft add: #${ingredientId} -> no match yet | stored=${craft._craft_stored.length}`);
    }

    state.version += 1;
    return { ok: true, matched: !!matched, newVersion: state.version };
  }

  private matchRecipe(
    stored: Record<string, unknown>[],
    recipes: RecipeDef[]
  ): RecipeDef | null {
    const storedCounts = new Map<number, number>();
    for (const item of stored) {
      const id = item.id as number;
      storedCounts.set(id, (storedCounts.get(id) || 0) + 1);
    }

    for (const recipe of recipes) {
      const totalRequired = recipe.ingredients.length;
      if (stored.length !== totalRequired) continue;

      let match = true;
      // Count required occurrences of each ingredient
      const requiredCounts = new Map<number, number>();
      for (const id of recipe.ingredients) {
        requiredCounts.set(id, (requiredCounts.get(id) || 0) + 1);
      }
      for (const [id, count] of requiredCounts) {
        if ((storedCounts.get(id) || 0) !== count) {
          match = false;
          break;
        }
      }
      if (match) return recipe;
    }
    return null;
  }

  // --- Cultivation ---

  getStageBreakthroughPill(level: number): number {
    if (!this.cultivation) return 0;
    const stages = this.cultivation.stages;
    if (!stages || level < 1 || level > stages.length) return 0;
    return stages[level - 1]?.breakthrough_pill ?? 0;
  }

  getExpToNextLevel(level: number): number {
    if (!this.cultivation) return 999999;
    const stages = this.cultivation.stages;
    if (!stages || level < 1 || level > stages.length) return 999999;
    return stages[level - 1].exp;
  }

  isMaxCultivation(level: number): boolean {
    if (!this.cultivation) return true;
    return level >= this.cultivation.stages.length;
  }

  needsBreakthroughPill(level: number): boolean {
    if (!this.cultivation) return false;
    if (this.isMaxCultivation(level)) return false;
    return this.getStageBreakthroughPill(level) > 0;
  }

  isBreakthroughReady(level: number, exp: number): boolean {
    if (!this.cultivation) return false;
    if (this.isMaxCultivation(level)) return false;
    if (level > this.cultivation.stages.length) return false;
    if (exp < this.getExpToNextLevel(level)) return false;
    const pill = this.getStageBreakthroughPill(level);
    return pill > 0 || level < this.cultivation.stages.length;
  }

  getRequiredBreakthroughPill(level: number, exp: number): number {
    if (!this.isBreakthroughReady(level, exp)) return 0;
    return this.getStageBreakthroughPill(level);
  }

  executeTryBreakthrough(
    state: GameState,
    pillId: number,
    uid: number,
    level: number,
    exp: number
  ): { ok: true; newCultivation: CultivationData } | { ok: false; reason: string } {
    console.log(`[engine] tryBreakthrough: pill=${pillId} uid=${uid} level=${level} exp=${exp}`);
    if (!this.isBreakthroughReady(level, exp)) {
      console.log(`[engine] tryBreakthrough: not ready (need exp=${this.getExpToNextLevel(level)} have=${exp})`);
      return { ok: false, reason: "not_ready" };
    }
    const required = this.getRequiredBreakthroughPill(level, exp);
    if (required > 0 && pillId !== required) {
      console.log(`[engine] tryBreakthrough: wrong pill (need=${required} got=${pillId})`);
      return { ok: false, reason: "wrong_pill" };
    }
    if (!this.cultivation) return { ok: false, reason: "no_config" };

    // Find and remove the pill (only if required)
    if (required > 0) {
      if (uid > 0) {
      const pillIdx = state.grid.findIndex(g => g.uid === uid);
      if (pillIdx >= 0) {
        state.grid.splice(pillIdx, 1);
        console.log(`[engine]   breakthrough pill #${pillId} removed from grid, uid=${uid}`);
      } else {
        console.log(`[engine]   breakthrough: uid=${uid} NOT FOUND in grid`);
        return { ok: false, reason: "pill_not_found" };
      }
    } else {
      // uid=0: search pouch first, then grid
      const pouchIdx = state.pouch.findIndex((p: any) => p.id === pillId);
      if (pouchIdx >= 0) {
        state.pouch.splice(pouchIdx, 1);
        console.log(`[engine]   breakthrough pill #${pillId} removed from pouch`);
      } else {
        const gridIdx = state.grid.findIndex(g => g.id === pillId);
        if (gridIdx >= 0) {
          state.grid.splice(gridIdx, 1);
          console.log(`[engine]   breakthrough pill #${pillId} removed from grid`);
        } else {
          console.log(`[engine]   breakthrough: pill #${pillId} not found in pouch or grid`);
          return { ok: false, reason: "pill_not_found" };
        }
      }
    }
    }

    const newLevel = level + 1;
    if (newLevel > (this.cultivation.stages.length)) return { ok: false, reason: "max_level" };
    const nextStage = this.cultivation.stages[newLevel - 1];
    const newMaxQi: number = nextStage?.max_qi ?? (state.cultivation.max_qi + 50);
    const newCultivation: CultivationData = {
      current_level: newLevel,
      current_exp: 0,
      total_exp: state.cultivation.total_exp,
      current_qi: Math.min(state.cultivation.current_qi, newMaxQi),
      max_qi: newMaxQi,
      last_tick_time: state.cultivation.last_tick_time,
    };

    state.cultivation = newCultivation;
    state.version += 1;

    const stageName = nextStage?.name ?? `stage_${newLevel}`;
    console.log(`[engine] breakthrough: -> ${stageName} | qi=${newCultivation.max_qi} | v${state.version}`);

    this.questEngine.incrementQuestProgress(state, QuestType.BREAKTHROUGH, 1, this);

    return { ok: true, newCultivation };
  }


  tickCraftingState(state: GameState): boolean {
    const now = Date.now();
    let changed = false;
    for (const item of state.grid) {
      if (!item.craft || item.craft._craft_state !== TableState.CRAFTING) continue;
      const recipe = item.craft._craft_recipe as unknown as RecipeDef | undefined;
      const craftTime = ((recipe?.craft_time ?? 0) * 1000);
      const startTime = item.craft._craft_start_time ?? 0;
      if (now - startTime >= craftTime) {
        item.craft._craft_state = TableState.READY;
        item.craft._craft_progress = 1.0;
        changed = true;
        const resultItem = this.getItemData(item.craft._craft_result_id);
        const resultName = resultItem?.name ?? ("#" + item.craft._craft_result_id);
        console.log(`[engine] craft ready: ${resultName} | table at (${item.col},${item.row})`);
      }
    }
    return changed;
  }

  consumeExpPill(
    state: GameState,
    pillId: number,
    uid: number
  ): { ok: true; cultivation: CultivationData } | { ok: false; reason: string } {
    const pillData = this.getItemData(pillId);
    if (!pillData) return { ok: false, reason: "invalid_pill" };

    if (!pillData.effect_type || pillData.effect_type !== 3) return { ok: false, reason: "invalid_effect" };

    const expGain: number = pillData.effect_value ?? 0;
    if (expGain <= 0) return { ok: false, reason: "no_exp_gain" };

    // Remove pill from grid
    const pillIdx = state.grid.findIndex(g => g.uid === uid);
    if (pillIdx >= 0) {
      state.grid.splice(pillIdx, 1);
      console.log(`[engine]   exp pill #${pillId} removed, uid=${uid}`);
    }

    this._addExp(state.cultivation, expGain);
    state.version += 1;

    const pillName = pillData.name;
    console.log(`[engine] consume exp pill: ${pillName} | exp +${expGain} | v${state.version}`);

    this.questEngine.incrementQuestProgress(state, QuestType.ANY_ITEM_CONSUME, 1, this);

    return { ok: true, cultivation: state.cultivation };
  }

  pouchDeposit(
    state: GameState,
    uid: number
  ): { ok: true; pouch: number[] } | { ok: false; reason: string } {
    const idx = state.grid.findIndex((g) => g.uid === uid);
    if (idx < 0) return { ok: false, reason: "item_not_found" };
    const itemId = state.grid[idx].id;
    state.grid.splice(idx, 1);
    state.pouch.push({ uid, id: itemId });
    state.version += 1;
    console.log(`[engine] pouch deposit: #${itemId} (uid=${uid}) | pouch=${state.pouch.length} items | v${state.version}`);
    return { ok: true, pouch: state.pouch };
  }

  pouchWithdraw(
    state: GameState,
    itemId: number,
    col: number,
    row: number
  ): { ok: true; pouch: number[]; col: number; row: number } | { ok: false; reason: string } {
    const idx = state.pouch.findIndex((p: any) => p.id === itemId);
    if (idx < 0) return { ok: false, reason: "item_not_in_pouch" };
    if (!this.isInBounds(col, row)) return { ok: false, reason: "invalid_position" };
    if (state.grid.some((g) => g.col === col && g.row === row)) return { ok: false, reason: "cell_occupied" };
    const entry = state.pouch[idx];
    state.pouch.splice(idx, 1);
    state.grid.push({ uid: entry.uid, id: itemId, col, row });
    state.version += 1;
    console.log(`[engine] pouch withdraw: #${itemId} uid=${entry.uid} at (${col},${row}) | pouch=${state.pouch.length} items | v${state.version}`);
    return { ok: true, pouch: state.pouch, col, row };
  }

  initBattleMonsters(state: GameState): void {
    if (!state.battle_monsters || state.battle_monsters.length > 0) return;
    state.battle_monsters = this._buildMonsterList(state.battle_map_id ?? 1, state.battle_stage ?? 0);
    console.log(`[engine] init battle monsters: ${state.battle_monsters.length} monsters`);
  }

  private _buildMonsterList(mapId: number, stage: number): BattleMonster[] {
    const map = this.maps.get(mapId);
    if (!map) return [];
    const stages = map.stages as any[] ?? [];
    if (stage >= stages.length) return [];
    const stageData = stages[stage];
    const result: BattleMonster[] = [];
    const monsters = stageData.monsters as any[] ?? [];
    for (const entry of monsters) {
      const mdata = this.getMonster(entry.monster_id);
      if (!mdata) continue;
      for (let i = 0; i < (entry.count ?? 1); i++) {
        result.push({
          monster_id: entry.monster_id,
          name: mdata.name,
          hp: mdata.hp,
          max_hp: mdata.hp,
          atk: mdata.atk ?? 0,
          accept_effect_types: mdata.accept_effect_types ?? [],
        });
      }
    }
    const boss = stageData.boss;
    if (boss) {
      const bdata = this.getMonster(boss.monster_id);
      if (bdata) {
        result.push({
          monster_id: boss.monster_id,
          name: "[Boss]" + bdata.name,
          hp: bdata.hp,
          max_hp: bdata.hp,
          atk: bdata.atk ?? 0,
          accept_effect_types: bdata.accept_effect_types ?? [],
          is_boss: true,
        });
      }
    }
    return result;
  }

  battleHeal(state: GameState, itemId: number, uid: number, effectId: number): { ok: true; newVersion: number; grid: GridItem[] } | { ok: false; reason: string } {
    const idx = state.grid.findIndex(g => g.uid === uid);
    if (idx < 0) return { ok: false, reason: "item_not_found" };
    const item = state.grid[idx];
    if (item.id !== itemId) return { ok: false, reason: "item_id_mismatch" };
    state.grid.splice(idx, 1);
    state.version += 1;
    console.log(`[engine] battle heal: #${itemId} consumed, uid=${uid}`);
    return { ok: true, newVersion: state.version, grid: state.grid };
  }

  battleAttack(
    state: GameState,
    itemId: number,
    effectId: number,
    uid: number,
    col: number,
    row: number
  ): { ok: true; grid: GridItem[]; monsters: BattleMonster[]; stage_complete: boolean; loot: number[] } | { ok: false; reason: string } {
    const itemDef = this.getItemData(itemId);
    if (!itemDef || !itemDef.effect_type || itemDef.effect_type !== 1) return { ok: false, reason: "invalid_effect" };

    // Remove used item from grid (prefer uid match, fall back to pos+id)
    const idx = state.grid.findIndex((g) => g.uid === uid);
    if (idx < 0) return { ok: false, reason: "item_not_found" };
    const removedItem = state.grid.splice(idx, 1)[0];

    if (!removedItem.atk_base) {
      state.grid.push(removedItem);
      return { ok: false, reason: "no_atk_base" };
    }
    const dmg = removedItem.atk_base * (itemDef.effect_value ?? 1);
    if (dmg <= 0) return { ok: false, reason: "no_damage" };

    // Init monsters if needed
    if (!state.battle_monsters || state.battle_monsters.length === 0) {
      state.battle_monsters = this._buildMonsterList(state.battle_map_id ?? 1, state.battle_stage ?? 0);
    }

    // Find first alive monster
    const mIdx = state.battle_monsters.findIndex((m) => m.hp > 0);
    if (mIdx < 0) {
      state.grid.push(removedItem);
      return { ok: false, reason: "no_alive_monster" };
    }

    // Check effect compatibility using item's effect_type
    if (!(state.battle_monsters[mIdx].accept_effect_types as number[]).includes(itemDef.effect_type ?? 0)) {
      state.grid.push(removedItem);
      return { ok: false, reason: "effect_not_accepted" };
    }

    // Apply damage
    state.battle_monsters[mIdx].hp = Math.max(0, state.battle_monsters[mIdx].hp - dmg);
    const monsterName = state.battle_monsters[mIdx].name;
    const killed = state.battle_monsters[mIdx].hp <= 0;
    const loot: number[] = [];

    if (killed) {
      // Drop loot based on monster
      const mdata = this.getMonster(state.battle_monsters[mIdx].monster_id);
      if (mdata?.loot?.length) {
        for (const lootId of mdata.loot) {
          const emptyPos = this.findEmptyPos(state.grid);
          if (emptyPos) {
            state.grid.push({ uid: this._nextUid(state), id: lootId, col: emptyPos.col, row: emptyPos.row });
            loot.push(lootId);
          }
        }
      }
      // Check if all monsters in current stage are dead
      const allDead = state.battle_monsters.every((m) => m.hp <= 0);
      let stageComplete = false;
      if (allDead) {
        state.battle_stage = (state.battle_stage ?? 0) + 1;
        stageComplete = true;
        // Build next stage monsters
        const map = this.maps.get(state.battle_map_id ?? 1);
        if (map) {
          const stages = map.stages as any[] ?? [];
          if ((state.battle_stage ?? 0) < stages.length) {
            state.battle_monsters = this._buildMonsterList(state.battle_map_id ?? 1, state.battle_stage ?? 0);
          } else {
            state.battle_monsters = [];
          }
        }
      }
      state.version += 1;
      console.log(`[engine] battle attack: ${monsterName} killed by #${itemId} | loot=${loot.join(",")} | stage_complete=${stageComplete} | v${state.version}`);

      this.questEngine.incrementQuestProgress(state, QuestType.BATTLE_ATTACK, 1, this);
      if (stageComplete) {
        this.questEngine.incrementQuestProgress(state, QuestType.BATTLE_CLEAR, 1, this);
      }

      return { ok: true, grid: state.grid, monsters: state.battle_monsters, stage_complete: stageComplete, loot };
    }

    state.version += 1;
    console.log(`[engine] battle attack: ${monsterName} took ${dmg} dmg (${state.battle_monsters[mIdx].hp}/${state.battle_monsters[mIdx].max_hp}) | v${state.version}`);

    this.questEngine.incrementQuestProgress(state, QuestType.BATTLE_ATTACK, 1, this);
    return { ok: true, grid: state.grid, monsters: state.battle_monsters, stage_complete: false, loot: [] };
  }

  consumeStaminaPill(
    state: GameState,
    pillId: number,
    uid: number
  ): { ok: true; stamina: number; max_stamina: number } | { ok: false; reason: string } {
    const pillData = this.getItemData(pillId);
    if (!pillData) return { ok: false, reason: "invalid_pill" };
    if (!pillData.effect_type || pillData.effect_type !== 4) return { ok: false, reason: "invalid_effect" };
    const amount: number = pillData.effect_value ?? 0;
    if (amount <= 0) return { ok: false, reason: "no_stamina_gain" };
    console.log(`[engine] consume stamina pill: #${pillId} "${pillData.name}" (uid=${uid}) | grid=${state.grid.length} items`);
    console.log(`[engine]   grid uids: [${state.grid.map(g => `${g.id}(${g.col},${g.row}):uid=${g.uid}`).join(", ")}]`);
    let idx = state.grid.findIndex((g) => g.uid === uid);
    if (idx < 0) {
      console.log(`[engine]   uid=${uid} NOT found!`);
      return { ok: false, reason: "item_not_found" };
    }
    state.grid.splice(idx, 1);
    console.log(`[engine]   removed from grid at idx=${idx}`);
    state.stamina += amount;
    state.last_stamina_tick = Date.now();
    state.version += 1;
    console.log(`[engine] consume stamina pill: #${pillId} (uid=${uid}) | stamina +${amount} total=${state.stamina} | v${state.version}`);

    this.questEngine.incrementQuestProgress(state, QuestType.ANY_ITEM_CONSUME, 1, this);

    return { ok: true, stamina: state.stamina, max_stamina: this.staminaConfig.max };
  }

  _addExp(c: CultivationData, amount: number): void {
    if (amount <= 0) return;
    if (!this.cultivation) return;
    if (this.isMaxCultivation(c.current_level)) return;

    c.current_exp += amount;
    c.total_exp += amount;

    const maxLevel = this.cultivation.stages.length;
    while (c.current_exp >= this.getExpToNextLevel(c.current_level)) {
      if (this.isMaxCultivation(c.current_level)) break;
      if (this.needsBreakthroughPill(c.current_level)) {
        c.current_exp = this.getExpToNextLevel(c.current_level);
        break;
      }

      c.current_exp -= this.getExpToNextLevel(c.current_level);
      c.current_level += 1;
      if (c.current_level > maxLevel) break;

      const newStage = this.cultivation.stages[c.current_level - 1];
      c.max_qi = newStage?.max_qi ?? c.max_qi;
      c.current_qi = Math.min(c.current_qi, c.max_qi);
      console.log(`[engine] level up: ${newStage?.name ?? "?"} | qi=${c.max_qi}`);
    }
  }

  pushAndPlace(state: GameState, fromCol: number, fromRow: number, toCol: number, toRow: number): { ok: true; newVersion: number; pushed_col: number; pushed_row: number; from_col: number; from_row: number; to_col: number; to_row: number } | { ok: false; reason: string } {
    if (!this.isInBounds(fromCol, fromRow)) return { ok: false, reason: "source_out_of_bounds" };
    if (!this.isInBounds(toCol, toRow)) return { ok: false, reason: "target_out_of_bounds" };
    const fromKey = this.posKey(fromCol, fromRow);
    const toKey = this.posKey(toCol, toRow);
    console.log(`[engine] pushAndPlace: from=(${fromCol},${fromRow}) to=(${toCol},${toRow}) v=${state.version}`);
    const fromItem = state.grid.find(i => this.posKey(i.col, i.row) === fromKey);
    const toItem = state.grid.find(i => this.posKey(i.col, i.row) === toKey);
    if (!fromItem) { console.log("[engine] pushAndPlace: source_item_not_found"); return { ok: false, reason: "source_item_not_found" }; }
    if (!toItem) { console.log("[engine] pushAndPlace: target_item_not_found"); return { ok: false, reason: "target_item_not_found" }; }
    if (fromCol === toCol && fromRow === toRow) return { ok: false, reason: "same_position" };
    if (toItem.immovable) { console.log("[engine] pushAndPlace: target_immovable"); return { ok: false, reason: "target_immovable" }; }

    // Find nearest empty cell. If grid is full, allow using the source position.
    const map = this.gridToMap(state.grid);
    let empty = this.findNearestEmpty(map, toCol, toRow);
    if (!empty) {
      map.delete(fromKey);
      empty = this.findNearestEmpty(map, toCol, toRow);
    }
    if (!empty) return { ok: false, reason: "no_empty_cell" };

    // Move target item to empty cell
    toItem.col = empty.col;
    toItem.row = empty.row;
    // Move dragged item to target position
    fromItem.col = toCol;
    fromItem.row = toRow;
    state.version += 1;

    const pushedCol = empty.col;
    const pushedRow = empty.row;
    console.log(`[engine] pushAndPlace: #${fromItem.id} (${fromCol},${fromRow})->(${toCol},${toRow}), #${toItem.id} (${toCol},${toRow})->(${pushedCol},${pushedRow})`);
    return { ok: true, newVersion: state.version, pushed_col: pushedCol, pushed_row: pushedRow, from_col: fromCol, from_row: fromRow, to_col: toCol, to_row: toRow };
  }

  // --- Meridian ---

  completeMeridianAcupoint(state: GameState, index: number, itemIds: number[]): { ok: true; newVersion: number; meridian_acupoints: any[]; qi_gained: number; qi_full: boolean; grid: any[]; cultivation: any; spirit_stones: number; stamina: number } | { ok: false; reason: string } {
    if (!state.meridian_acupoints || index < 0 || index >= state.meridian_acupoints.length) {
      return { ok: false, reason: "invalid_index" };
    }
    const req = state.meridian_acupoints[index];
    if (req.completed) return { ok: false, reason: "already_completed" };
    // Consume one of each required item from grid
    const toRemove: number[] = [];
    for (const reqItemId of itemIds) {
      let found = false;
      for (let i = 0; i < state.grid.length; i++) {
        if (!toRemove.includes(i) && state.grid[i].id === reqItemId) {
          toRemove.push(i);
          found = true;
          break;
        }
      }
      if (!found) return { ok: false, reason: "insufficient_items" };
    }

    // Check if qi is capped before removing items
    if (state.cultivation.current_qi >= state.cultivation.max_qi) {
      return { ok: false, reason: "qi_full" };
    }

    // Remove consumed items
    for (const idx of toRemove.sort((a: number, b: number) => b - a)) {
      state.grid.splice(idx, 1);
    }

    req.completed = true;
    state.version += 1;

    // Order reward — scale by total item value
    const threshold = this.meridianThresholds[state.meridian_threshold_idx ?? 0];
    const totalValue: number = (req as any).total_value ?? 0;
    let qiGained = 0;
    let qiFull = false;
    let rewardsApplied: RewardConfig = { tokens: [], items: [] };
    if (totalValue > 0 && threshold) {
      const orderReward = this._buildMeridianOrderReward(threshold, totalValue, state);
      const qiBefore = state.cultivation.current_qi;
      const r = this.applyRewards(state, orderReward.rewards);
      rewardsApplied.tokens!.push(...(r.tokens || []));
      rewardsApplied.items!.push(...(r.items || []));
      qiGained = state.cultivation.current_qi - qiBefore;
      qiFull = state.cultivation.current_qi >= state.cultivation.max_qi && qiBefore < state.cultivation.max_qi;
    }

    // Remove completed order, generate replacement using current stage
    state.meridian_acupoints.splice(index, 1);
    const newThreshold = this._findMeridianThreshold(state.cultivation.current_level);
    const newPool: number[] = newThreshold?.item_pool ?? [];
    const newTypeMin: number = newThreshold?.count_min ?? 1;
    const newTypeMax: number = newThreshold?.count_max ?? 3;
    const newOrder = this._genOneAcupoint(newPool, newTypeMin, newTypeMax);
    if (newThreshold && newOrder.total_value > 0) {
      Object.assign(newOrder, this._buildMeridianOrderReward(newThreshold, newOrder.total_value, state));
    }
    state.meridian_acupoints.push(newOrder);
    console.log(`[engine] meridian order #${index} completed, new order generated`);

    return { ok: true, newVersion: state.version, meridian_acupoints: state.meridian_acupoints, qi_gained: qiGained, qi_full: qiFull, grid: state.grid, cultivation: state.cultivation, spirit_stones: state.spirit_stones, stamina: state.stamina };
  }

  // --- Storage ---

  initStorage(item: GridItem): void {
    if (!item.storage) {
      const itemDef = this.getItemData(item.id);
      item.storage = { items: [], max_slots: itemDef?.storage_slots ?? 20 };
    }
  }

  depositItem(state: GameState, storageCol: number, storageRow: number, uid: number, fromCol: number, fromRow: number): { ok: true; newVersion: number } | { ok: false; reason: string } {
    if (!this.isInBounds(fromCol, fromRow)) return { ok: false, reason: "from_out_of_bounds" };
    if (!this.isInBounds(storageCol, storageRow)) return { ok: false, reason: "storage_out_of_bounds" };
    const fromKey = this.posKey(fromCol, fromRow);
    const sourceItem = state.grid.find(i => this.posKey(i.col, i.row) === fromKey);
    if (!sourceItem) return { ok: false, reason: "item_not_found" };

    const storageItem = state.grid.find(i => i.col === storageCol && i.row === storageRow);
    if (!storageItem) return { ok: false, reason: "storage_not_found" };

    this.initStorage(storageItem);
    const s = storageItem.storage!;

    if (s.items.length >= s.max_slots) return { ok: false, reason: "storage_full" };

    // Remove from grid
    state.grid = state.grid.filter(i => this.posKey(i.col, i.row) !== fromKey);

    // Add to storage (no stacking — one slot per item)
    s.items.push({ uid: sourceItem.uid, id: sourceItem.id });

    state.version += 1;
    console.log(`[engine] deposit: #${sourceItem.id} uid=${sourceItem.uid} -> storage at (${storageCol},${storageRow}) | slots=${s.items.length}/${s.max_slots}`);
    return { ok: true, newVersion: state.version };
  }

  withdrawItem(state: GameState, storageCol: number, storageRow: number, uid: number, targetCol: number, targetRow: number): { ok: true; newVersion: number; uid: number; col: number; row: number } | { ok: false; reason: string } {
    if (!this.isInBounds(storageCol, storageRow)) return { ok: false, reason: "storage_out_of_bounds" };
    if (!this.isInBounds(targetCol, targetRow)) return { ok: false, reason: "target_out_of_bounds" };
    const storageItem = state.grid.find(i => i.col === storageCol && i.row === storageRow);
    if (!storageItem?.storage) return { ok: false, reason: "storage_not_found" };

    const targetKey = this.posKey(targetCol, targetRow);
    if (state.grid.some(i => this.posKey(i.col, i.row) === targetKey)) return { ok: false, reason: "target_occupied" };

    const idx = storageItem.storage.items.findIndex(s => s.uid === uid);
    if (idx < 0) return { ok: false, reason: "item_not_in_storage" };

    const entry = storageItem.storage.items[idx];
    storageItem.storage.items.splice(idx, 1);

    state.grid.push({ uid: entry.uid, id: entry.id, col: targetCol, row: targetRow });
    state.version += 1;

    const itemName = this.getItemData(entry.id)?.name ?? ("#" + entry.id);
    console.log(`[engine] withdraw: ${itemName} uid=${entry.uid} from storage at (${storageCol},${storageRow}) -> (${targetCol},${targetRow})`);
    return { ok: true, newVersion: state.version, uid: entry.uid, col: targetCol, row: targetRow };
  }

  // --- Shop ---

  sellItem(state: GameState, uid: number): { ok: true; stones: number } | { ok: false; reason: string } {
    const item = state.grid.find(i => i.uid === uid);
    if (!item) return { ok: false, reason: "item_not_found" };
    const itemId = item.id;

    const data = this.getItemData(item.id);
    if (!data) return { ok: false, reason: "item_data_not_found" };

    if (data.type === 2 || this.isLauncher(data)) {
      return { ok: false, reason: "cannot_sell" };
    }

    const price = this.getSellPrice(item.id);
    if (price <= 0) return { ok: false, reason: "cannot_sell" };

    state.grid = state.grid.filter(i => i.uid !== uid);
    state.spirit_stones += price;
    state.version += 1;

    const itemName = data.name ?? ("#" + item.id);
    console.log(`[engine] sell: ${itemName} (uid=${uid}) -> +${price} stones | total=${state.spirit_stones}`);

    this.questEngine.incrementQuestProgress(state, QuestType.SELL, 1, this);

    return { ok: true, stones: state.spirit_stones };
  }

  buyItem(state: GameState, itemId: number, targetCol: number, targetRow: number): { ok: true; uid: number; stones: number } | { ok: false; reason: string } {
    if (!this.isInBounds(targetCol, targetRow)) return { ok: false, reason: "out_of_bounds" };
    const targetKey = this.posKey(targetCol, targetRow);
    if (state.grid.some(i => this.posKey(i.col, i.row) === targetKey)) return { ok: false, reason: "target_occupied" };

    const price = this.getBuyPrice(itemId);
    if (price <= 0) return { ok: false, reason: "cannot_buy" };

    if (!this.shopConfig.shopItems.some((s: any) => s.id === itemId)) return { ok: false, reason: "not_in_shop" };

    if (state.spirit_stones < price) return { ok: false, reason: "insufficient_stones" };

    const itemData = this.getItemData(itemId);
    if (!itemData) return { ok: false, reason: "item_data_not_found" };

    state.spirit_stones -= price;
    const buyUid = this._nextUid(state);
    state.grid.push({ uid: buyUid, id: itemId, col: targetCol, row: targetRow });
    state.version += 1;

    console.log(`[engine] buy: ${itemData.name} at (${targetCol},${targetRow}) -> -${price} stones | total=${state.spirit_stones}`);
    return { ok: true, uid: buyUid, stones: state.spirit_stones };
  }

  getGridHash(state: GameState): number {
    // Simple hash of grid layout for client-side integrity checks
    let hash = 0;
    const sorted = [...state.grid].sort((a, b) => {
      if (a.col !== b.col) return a.col - b.col;
      return a.row - b.row;
    });
    for (const item of sorted) {
      hash = ((hash << 5) - hash + item.id) | 0;
      hash = ((hash << 5) - hash + item.col) | 0;
      hash = ((hash << 5) - hash + item.row) | 0;
    }
    return hash;
  }
}
