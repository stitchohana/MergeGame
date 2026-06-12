import * as fs from "fs";
import * as path from "path";
import { GameState, GridItem, CultivationData } from "../storage/interface";

// --- Config types ---

interface ItemDef {
  id: number;
  level: number;
  name: string;
  icon: string;
  group_id: number;
  merge_score: number;
  describe: string;
  type: string;
  spawns?: { id: number; weight: number }[];
  pill_type?: string;
  exp_gain?: number;
  buff_duration?: number;
  buff_multiplier?: number;
  recipes?: number[];
}

interface RecipeDef {
  id: number;
  name: string;
  ingredients: { id: number; count: number }[];
  result: number;
  craft_time: number;
  crafting_level: number;
}

interface RealmDef {
  id: number;
  name: string;
  levels: number;
  base_exp: number;
  growth: number;
  qi_bonus: number;
  breakthrough_pill: number;
}

interface CultivationConfig {
  passive_exp_per_second: number;
  initial_qi: number;
  qi_recovery_per_level: number;
  qi_breakthrough_bonus: number;
  realms: RealmDef[];
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
  private initialSetup: { id: number; col: number; row: number }[] = [];

  constructor(configDir: string) {
    this.loadConfigs(configDir);
  }

  // --- Config loading ---

  private loadConfigs(configDir: string): void {
    this.loadItems(path.join(configDir, "items.json"));
    this.loadCultivation(path.join(configDir, "cultivation.json"));
    this.loadInitialSetup(path.join(configDir, "initial_setup.json"));
    console.log(`[engine] Configs loaded: ${this.itemsById.size} items, ${this.recipes.length} recipes, ${this.cultivation?.realms.length ?? 0} realms`);
  }

  private loadItems(filePath: string): void {
    const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    const categories = ["regular", "launcher", "crafting"] as const;

    for (const cat of categories) {
      for (const item of data[cat] || []) {
        item.type = cat;
        this.itemsById.set(item.id, item);

        if (!this.itemsByTypeLevel.has(cat)) {
          this.itemsByTypeLevel.set(cat, new Map());
        }
        const byLevel = this.itemsByTypeLevel.get(cat)!;
        if (!byLevel.has(item.level)) {
          byLevel.set(item.level, []);
        }
        byLevel.get(item.level)!.push(item);
      }
    }

    this.recipes = data.recipes || [];
    this.recipesByTable.clear();
    for (const recipe of this.recipes) {
      // Index recipes by crafting table items that can use them
      for (const cat of categories) {
        for (const item of data[cat] || []) {
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
  }

  private loadCultivation(filePath: string): void {
    this.cultivation = JSON.parse(fs.readFileSync(filePath, "utf-8"));
  }

  private loadInitialSetup(filePath: string): void {
    const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    this.initialSetup = data.items || [];
  }

  // --- Config queries ---

  getItemData(id: number): ItemDef | null {
    return this.itemsById.get(id) ?? null;
  }

  getItemByLevel(type: string, level: number, groupId = 0): ItemDef | null {
    const byLevel = this.itemsByTypeLevel.get(type);
    if (!byLevel) return null;
    const items = byLevel.get(level) || [];
    if (items.length === 0) return null;
    if (groupId === 0) return items[0];
    return items.find((i) => i.group_id === groupId) ?? null;
  }

  getNextLevel(type: string, level: number, groupId = 0): ItemDef | null {
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

  getInitialSetup() {
    return this.initialSetup;
  }

  // --- Grid helpers ---

  static isInBounds(col: number, row: number): boolean {
    return col >= 0 && col < 7 && row >= 0 && row < 9;
  }

  static posKey(col: number, row: number): string {
    return `${col},${row}`;
  }

  static getNeighbors(col: number, row: number): [number, number][] {
    const result: [number, number][] = [];
    const candidates: [number, number][] = [
      [col + 1, row],
      [col - 1, row],
      [col, row + 1],
      [col, row - 1],
    ];
    for (const [c, r] of candidates) {
      if (GameEngine.isInBounds(c, r)) result.push([c, r]);
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
    visited.add(GameEngine.posKey(startCol, startRow));

    while (queue.length > 0) {
      const [c, r] = queue.shift()!;
      const key = GameEngine.posKey(c, r);
      if (!grid.has(key)) return { col: c, row: r };

      for (const [nc, nr] of GameEngine.getNeighbors(c, r)) {
        const nk = GameEngine.posKey(nc, nr);
        if (!visited.has(nk)) {
          visited.add(nk);
          queue.push([nc, nr]);
        }
      }
    }
    return null;
  }

  // --- State initialization ---

  createInitialState(): GameState {
    const state: GameState = {
      score: 0,
      high_score: 0,
      grid: [],
      cultivation: {
        current_realm_id: 0,
        current_level: 1,
        current_exp: 0,
        total_exp: 0,
        current_qi: this.cultivation?.initial_qi ?? 100,
        max_qi: this.cultivation?.initial_qi ?? 100,
        buffs: [],
        last_tick_time: Date.now(),
      },
      version: 0,
    };

    for (const entry of this.initialSetup) {
      const item = this.getItemData(entry.id);
      if (item) {
        state.grid.push({ id: entry.id, col: entry.col, row: entry.row });
      }
    }
    return state;
  }

  // --- Grid helpers ---

  private buildGridMap(grid: GridItem[]): Map<string, GridItem> {
    const map = new Map<string, GridItem>();
    for (const item of grid) {
      map.set(GameEngine.posKey(item.col, item.row), item);
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
  ): { valid: true; resultItem: ItemDef; scoreGain: number; fromItem: GridItem; toItem: GridItem } | { valid: false; reason: string } {
    const map = this.gridToMap(state.grid);
    const fromKey = GameEngine.posKey(fromCol, fromRow);
    const toKey = GameEngine.posKey(toCol, toRow);

    let itemA: GridItem | undefined;
    let itemB: GridItem | undefined;

    // Try exact position lookup first (skip if out of bounds)
    if (GameEngine.isInBounds(fromCol, fromRow)) {
      itemA = map.get(fromKey);
    }
    if (GameEngine.isInBounds(toCol, toRow)) {
      itemB = map.get(toKey);
    }

    // If either not found, search full grid by item ID
    // (handles position drift and out-of-bounds positions from client)
    if (!itemA && itemB) {
      itemA = state.grid.find((g) => g.id === itemB!.id && GameEngine.posKey(g.col, g.row) !== toKey);
    }
    if (!itemB && itemA) {
      itemB = state.grid.find((g) => g.id === itemA!.id && GameEngine.posKey(g.col, g.row) !== fromKey);
    }
    // If still no match and we don't have either, search all items by finding pairs
    if (!itemA && !itemB) {
      // Client sent bad positions — find any two identical items
      const byId = new Map<number, GridItem[]>();
      for (const g of state.grid) {
        if (!byId.has(g.id)) byId.set(g.id, []);
        byId.get(g.id)!.push(g);
      }
      for (const [, list] of byId) {
        if (list.length >= 2) {
          itemA = list[0];
          itemB = list[1];
          break;
        }
      }
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
      scoreGain: nextItem.merge_score,
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
  ): { ok: true; newScore: number; newVersion: number; resultId: number } | { ok: false; reason: string } {
    const result = this.validateMerge(state, fromCol, fromRow, toCol, toRow);
    if (!result.valid) {
      return { ok: false, reason: result.reason };
    }

    const actualFromKey = GameEngine.posKey(result.fromItem.col, result.fromItem.row);
    const actualToKey = GameEngine.posKey(result.toItem.col, result.toItem.row);
    const fromId = result.fromItem.id;

    // Remove both items using their actual positions from the server's grid
    state.grid = state.grid.filter(
      (item) =>
        GameEngine.posKey(item.col, item.row) !== actualFromKey &&
        GameEngine.posKey(item.col, item.row) !== actualToKey
    );

    // Add merged item at the target position (where itemB was)
    state.grid.push({
      id: result.resultItem.id,
      col: result.toItem.col,
      row: result.toItem.row,
    });

    state.score += result.scoreGain;
    if (state.score > state.high_score) {
      state.high_score = state.score;
    }
    state.version += 1;

    const mergedName = result.resultItem.name;
    const fromItem = this.getItemData(fromId);
    const fromName = fromItem?.name ?? `#${fromId}`;
    console.log(`[engine] merge: ${fromName}x2 -> ${mergedName} | score +${result.scoreGain} (total=${state.score}) | v${state.version}`);

    return {
      ok: true,
      newScore: state.score,
      newVersion: state.version,
      resultId: result.resultItem.id,
    };
  }

  // --- Launcher spawn ---

  executeSpawn(
    state: GameState,
    launcherCol: number,
    launcherRow: number
  ): { ok: true; spawnedId: number; targetCol: number; targetRow: number; newVersion: number }
    | { ok: false; reason: string } {
    const map = this.gridToMap(state.grid);
    const launcherKey = GameEngine.posKey(launcherCol, launcherRow);
    const launcherItem = map.get(launcherKey);

    if (!launcherItem) return { ok: false, reason: "launcher_not_found" };

    const launcherData = this.getItemData(launcherItem.id);
    if (!launcherData || launcherData.type !== "launcher") {
      return { ok: false, reason: "not_a_launcher" };
    }

    const spawnResult = this.rollSpawn(launcherItem.id);
    if (!spawnResult) return { ok: false, reason: "spawn_failed" };

    const target = this.findNearestEmpty(map, launcherCol, launcherRow);
    if (!target) return { ok: false, reason: "no_empty_cell" };

    state.grid.push({
      id: spawnResult.id,
      col: target.col,
      row: target.row,
    });
    state.version += 1;

    console.log(`[engine] spawn: launcher #${launcherItem.id} -> ${spawnResult.name} at (${target.col},${target.row}) | v${state.version}`);

    return {
      ok: true,
      spawnedId: spawnResult.id,
      targetCol: target.col,
      targetRow: target.row,
      newVersion: state.version,
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
    const fromKey = GameEngine.posKey(fromCol, fromRow);
    const toKey = GameEngine.posKey(toCol, toRow);

    if (fromCol === toCol && fromRow === toRow) {
      return { ok: false, reason: "same_position" };
    }

    const existsAtTarget = state.grid.some(
      (item) => GameEngine.posKey(item.col, item.row) === toKey
    );
    if (existsAtTarget) {
      return { ok: false, reason: "target_occupied" };
    }

    const targetItem = state.grid.find(
      (item) => GameEngine.posKey(item.col, item.row) === fromKey
    );
    if (!targetItem) {
      return { ok: false, reason: "source_item_not_found" };
    }

    const itemName = this.getItemData(targetItem.id)?.name ?? ("#" + targetItem.id);
    console.log(`[engine] move: ${itemName} (${fromCol},${fromRow}) -> (${toCol},${toRow}) | v${state.version + 1}`);

    targetItem.col = toCol;
    targetItem.row = toRow;
    state.version += 1;

    return { ok: true, newVersion: state.version };
  }

  // --- Crafting ---

  validateCraftStart(
    state: GameState,
    tableCol: number,
    tableRow: number
  ): { valid: true; recipe: RecipeDef } | { valid: false; reason: string } {
    const tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    );
    if (!tableItem) return { valid: false, reason: "table_not_found" };

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

    const tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    )!;
    const craft = tableItem.craft!;

    craft._craft_state = TableState.CRAFTING;
    craft._craft_progress = 0;
    craft._craft_stored = [];
    craft._craft_result_id = validation.recipe.result;
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
  ): { ok: true; resultId: number; newVersion: number } | { ok: false; reason: string } {
    const tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    );
    if (!tableItem?.craft) return { ok: false, reason: "table_not_found" };

    const craft = tableItem.craft;
    if (craft._craft_state !== TableState.CRAFTING && craft._craft_state !== TableState.READY) {
      return { ok: false, reason: "not_crafting" };
    }

    const resultId = craft._craft_result_id;
    if (resultId <= 0) return { ok: false, reason: "no_result" };

    // Clear craft state
    delete tableItem.craft;
    state.version += 1;

    const retrievedItem = this.getItemData(resultId);
    const retrievedName = retrievedItem?.name ?? `#${resultId}`;
    console.log(`[engine] craft retrieve: -> ${retrievedName} | v${state.version}`);

    return { ok: true, resultId, newVersion: state.version };
  }

  addIngredientToTable(
    state: GameState,
    tableCol: number,
    tableRow: number,
    ingredientId: number
  ): { ok: true; matched: boolean; newVersion: number } | { ok: false; reason: string } {
    const tableItem = state.grid.find(
      (item) => item.col === tableCol && item.row === tableRow
    );

    if (!tableItem) return { ok: false, reason: "table_not_found" };

    const tableData = this.getItemData(tableItem.id);
    if (!tableData || tableData.type !== "crafting") {
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
      const totalRequired = recipe.ingredients.reduce((sum, ing) => sum + ing.count, 0);
      if (stored.length !== totalRequired) continue;

      let match = true;
      for (const { id, count } of recipe.ingredients) {
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

  getExpToNextLevel(currentRealmId: number, currentLevel: number): number {
    if (!this.cultivation) return 999999;
    const realm = this.cultivation.realms[currentRealmId];
    if (!realm) return 999999;
    const level = Math.min(currentLevel + 1, realm.levels);
    return Math.floor(realm.base_exp * Math.pow(realm.growth, level - 1));
  }

  getMaxLevelForRealm(realmId: number): number {
    if (!this.cultivation) return 1;
    return this.cultivation.realms[realmId]?.levels ?? 1;
  }

  isMaxCultivation(realmId: number, level: number): boolean {
    if (!this.cultivation) return true;
    return (
      realmId >= this.cultivation.realms.length - 1 &&
      level >= this.getMaxLevelForRealm(realmId)
    );
  }

  needsBreakthroughPill(realmId: number, level: number): boolean {
    if (!this.cultivation) return false;
    if (this.isMaxCultivation(realmId, level)) return false;
    const maxLv = this.getMaxLevelForRealm(realmId);
    if (level < maxLv) return false;
    const realm = this.cultivation.realms[realmId];
    return (realm?.breakthrough_pill ?? 0) > 0;
  }

  isBreakthroughReady(
    realmId: number,
    level: number,
    exp: number
  ): boolean {
    if (!this.cultivation) return false;
    if (this.isMaxCultivation(realmId, level)) return false;
    const realm = this.cultivation.realms[realmId];
    if (!realm) return false;
    const maxLv = realm.levels;
    return level >= maxLv && exp >= this.getExpToNextLevel(realmId, level);
  }

  getRequiredBreakthroughPill(realmId: number, level: number, exp: number): number {
    if (!this.isBreakthroughReady(realmId, level, exp)) return 0;
    const realm = this.cultivation!.realms[realmId];
    return realm?.breakthrough_pill ?? 0;
  }

  executeTryBreakthrough(
    state: GameState,
    pillId: number,
    realmId: number,
    level: number,
    exp: number
  ): { ok: true; newCultivation: CultivationData } | { ok: false; reason: string } {
    if (!this.isBreakthroughReady(realmId, level, exp)) {
      return { ok: false, reason: "not_ready" };
    }
    const required = this.getRequiredBreakthroughPill(realmId, level, exp);
    if (required <= 0 || pillId !== required) {
      return { ok: false, reason: "wrong_pill" };
    }
    if (!this.cultivation) return { ok: false, reason: "no_config" };

    const newCultivation: CultivationData = {
      current_realm_id: realmId + 1,
      current_level: 1,
      current_exp: 0,
      total_exp: state.cultivation.total_exp,
      current_qi: Math.min(
        state.cultivation.current_qi + this.cultivation.qi_recovery_per_level,
        state.cultivation.max_qi + this.cultivation.qi_breakthrough_bonus
      ),
      max_qi: state.cultivation.max_qi + this.cultivation.qi_breakthrough_bonus,
      buffs: state.cultivation.buffs,
      last_tick_time: state.cultivation.last_tick_time,
    };

    state.cultivation = newCultivation;
    state.version += 1;

    const newRealm = this.cultivation?.realms[newCultivation.current_realm_id];
    const realmName = newRealm?.name ?? `realm_${newCultivation.current_realm_id}`;
    console.log(`[engine] breakthrough: -> ${realmName} | qi=${newCultivation.max_qi} | v${state.version}`);

    return { ok: true, newCultivation };
  }

  // --- Cultivation tick & pill ---

  tickCultivation(state: GameState): void {
    const c = state.cultivation;
    const now = Date.now();
    const elapsed = Math.floor((now - c.last_tick_time) / 1000);
    if (elapsed <= 0 || !this.cultivation) return;

    // Tick buffs
    this._tickBuffs(c, elapsed);

    // Passive EXP gain
    if (!this.isMaxCultivation(c.current_realm_id, c.current_level)) {
      if (this.needsBreakthroughPill(c.current_realm_id, c.current_level)) {
        const realm = this.cultivation.realms[c.current_realm_id];
        const pillId = realm?.breakthrough_pill ?? 0;
        const pillData = this.getItemData(pillId);
        const pillName = pillData?.name ?? `#${pillId}`;
        console.log(`[engine] cultivation tick: blocked — needs ${pillName} to breakthrough from ${realm?.name} Lv${c.current_level}`);
      } else {
        const baseExp = this.cultivation.passive_exp_per_second;
        const mult = this._getExpMultiplier(c);
        const gained = Math.ceil(baseExp * elapsed * mult);
        if (gained > 0) {
          this._addExp(c, gained);
          const realmName = this.cultivation.realms[c.current_realm_id]?.name ?? "?";
          console.log(`[engine] cultivation tick: +${gained}exp (${elapsed}s x${baseExp}/s x${mult}) | ${realmName} Lv${c.current_level} exp=${c.current_exp}/${this.getExpToNextLevel(c.current_realm_id, c.current_level)}`);
        }
      }
    } else {
      console.log(`[engine] cultivation tick: max cultivation reached`);
    }

    c.last_tick_time = now;
    state.version += 1;
  }

  consumePill(
    state: GameState,
    pillId: number
  ): { ok: true; cultivation: CultivationData } | { ok: false; reason: string } {
    // Tick first to apply elapsed time
    this.tickCultivation(state);

    const pillData = this.getItemData(pillId);
    if (!pillData) return { ok: false, reason: "invalid_pill" };
    if (pillData.pill_type !== "cultivation") return { ok: false, reason: "not_cultivation_pill" };

    const c = state.cultivation;

    // Apply instant EXP
    const expGain: number = pillData.exp_gain ?? 0;
    if (expGain > 0) {
      this._addExp(c, expGain);
    }

    // Apply buff
    const duration: number = pillData.buff_duration ?? 0;
    const multiplier: number = pillData.buff_multiplier ?? 1.0;
    if (duration > 0) {
      c.buffs.push({
        pill_id: pillId,
        name: pillData.name,
        duration: duration,
        remaining: duration,
        multiplier: multiplier,
      });
    }

    const pillName = pillData.name;
    console.log(`[engine] consume pill: ${pillName} | exp +${expGain} | buff x${multiplier} ${duration}s | realm=${c.current_realm_id} lv=${c.current_level}`);

    state.version += 1;
    return { ok: true, cultivation: c };
  }

  private _tickBuffs(c: CultivationData, seconds: number): void {
    let changed = false;
    let i = 0;
    while (i < c.buffs.length) {
      const b = c.buffs[i] as any;
      b.remaining -= seconds;
      if (b.remaining <= 0) {
        c.buffs.splice(i, 1);
        changed = true;
      } else {
        i++;
      }
    }
    if (changed) {
      console.log(`[engine] buff expired, ${c.buffs.length} remaining`);
    }
  }

  private _getExpMultiplier(c: CultivationData): number {
    let mult = 1.0;
    for (const b of c.buffs) {
      mult = Math.max(mult, (b as any).multiplier ?? 1.0);
    }
    return mult;
  }

  private _addExp(c: CultivationData, amount: number): void {
    if (amount <= 0) return;
    if (!this.cultivation) return;
    if (this.isMaxCultivation(c.current_realm_id, c.current_level)) return;
    if (this.needsBreakthroughPill(c.current_realm_id, c.current_level)) return;

    c.current_exp += amount;
    c.total_exp += amount;

    const maxRealms = this.cultivation.realms.length;
    while (c.current_exp >= this.getExpToNextLevel(c.current_realm_id, c.current_level)) {
      if (this.isMaxCultivation(c.current_realm_id, c.current_level)) break;

      c.current_exp -= this.getExpToNextLevel(c.current_realm_id, c.current_level);
      c.current_level += 1;

      const maxLv = this.getMaxLevelForRealm(c.current_realm_id);
      if (c.current_level > maxLv) {
        // Breakthrough check
        const realm = this.cultivation.realms[c.current_realm_id];
        if ((realm?.breakthrough_pill ?? 0) > 0) {
          // Needs pill — stop here
          c.current_level = maxLv;
          c.current_exp = this.getExpToNextLevel(c.current_realm_id, c.current_level);
          break;
        }
        // Auto breakthrough (凡人 -> 练气)
        c.current_level = 1;
        c.current_realm_id += 1;
        if (c.current_realm_id >= maxRealms) break;
        c.max_qi += this.cultivation.qi_breakthrough_bonus;
        c.current_qi = Math.min(c.current_qi + this.cultivation.qi_recovery_per_level, c.max_qi);
        const newRealm = this.cultivation.realms[c.current_realm_id];
        console.log(`[engine] breakthrough: -> ${newRealm.name} | qi=${c.max_qi}`);
        break;
      }

      c.current_qi = Math.min(c.current_qi + this.cultivation.qi_recovery_per_level, c.max_qi);
      const realmName = this.cultivation.realms[c.current_realm_id]?.name ?? "?";
      console.log(`[engine] level up: ${realmName} Lv${c.current_level}`);
    }
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
