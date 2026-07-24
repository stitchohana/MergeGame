import { GameState, GridItem, CultivationData, RewardConfig, BattleMonster } from "../storage/interface";
import { QuestEngine } from "./quest_engine";
import { ActivityEngine } from "./activity_engine";
import { GameConfigTables } from "./config_tables";
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
    spawns?: {
        id: number;
        weight: number;
    }[];
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
    breakthrough_reward_id?: number;
}
interface CultivationConfig {
    stages: StageDef[];
}
export declare enum TableState {
    IDLE = 0,
    HAS_ITEMS = 1,
    CRAFTING = 2,
    READY = 3
}
export declare class GameEngine {
    readonly GRID_COLS = 7;
    readonly GRID_ROWS = 9;
    readonly MAX_CELLS = 63;
    private itemsById;
    private itemsByTypeLevel;
    private recipes;
    private recipesByTable;
    private cultivation;
    get cultivationStages(): StageDef[];
    private initialSetups;
    staminaConfig: {
        max: number;
        spawnCost: number;
        regenInterval: number;
        regenAmount: number;
    };
    questResetHour: number;
    private shopConfig;
    private meridianThresholds;
    private maps;
    private monsters;
    private rewardsTable;
    private homeMeridianDefs;
    questEngine: QuestEngine;
    activityEngine: ActivityEngine;
    constructor(configTables: GameConfigTables);
    private loadConfigs;
    private loadGameConfig;
    private loadShopConfig;
    getSellPrice(itemId: number): number;
    getBuyPrice(itemId: number): number;
    getShopItems(): any[];
    private loadItems;
    private loadRecipes;
    private loadCultivation;
    private loadMeridians;
    private loadExpedition;
    private loadRewards;
    getRewardConfig(rewardId: number): RewardConfig | undefined;
    private loadHomeMeridians;
    getHomeMeridianDefs(): any[];
    lightHomeAcupoint(state: GameState, stageIndex: number, acupointIndex: number): {
        ok: true;
        circulation_completed: boolean;
        cultivation: any;
        spirit_stones: number;
        stamina: number;
        pending_rewards: any[];
        home_meridian_progress: any[];
    } | {
        ok: false;
        reason: string;
    };
    gmActivateHomeAcupoints(state: GameState, amount: number): {
        activated: number;
        completed_stages: number;
    };
    getMonster(id: number): any;
    generateMeridianRequirements(state: GameState): {
        acupoints: any[];
    };
    private _scaleRewardConfig;
    private _findMeridianThreshold;
    private _genOneAcupoint;
    private loadInitialSetup;
    getItemData(id: number): ItemDef | null;
    getItemByLevel(type: number, level: number, groupId?: number): ItemDef | null;
    getNextLevel(type: number, level: number, groupId?: number): ItemDef | null;
    rollSpawn(launcherId: number): ItemDef | null;
    getRecipesForTable(tableId: number): RecipeDef[];
    getCultivationConfig(): CultivationConfig | null;
    getInitialSetup(boardType?: number): {
        id: number;
        col: number;
        row: number;
    }[];
    getMaxCharges(itemId: number): number;
    _nextUid(state: GameState): number;
    getRechargeTime(itemId: number): number;
    isInBounds(col: number, row: number): boolean;
    tickStamina(state: GameState): void;
    getRegenRemainingMs(state: GameState): number;
    private isLauncher;
    enrichGridWithRechargeRemaining(grid: any[]): void;
    tickLauncherRecharge(state: GameState): void;
    posKey(col: number, row: number): string;
    getNeighbors(col: number, row: number): [number, number][];
    findNearestEmpty(grid: Map<string, GridItem>, startCol: number, startRow: number): {
        col: number;
        row: number;
    } | null;
    findEmptyPos(grid: GridItem[]): {
        col: number;
        row: number;
    } | null;
    findEmptyByRow(grid: Map<string, GridItem>): {
        col: number;
        row: number;
    } | null;
    applyRewards(state: GameState, rewards: RewardConfig | number): RewardConfig;
    createInitialState(boardType?: number): GameState;
    switchBoard(state: GameState, boardType: string, battleMapId?: number, battleStage?: number): {
        ok: true;
        newVersion: number;
    } | {
        ok: false;
        reason: string;
    };
    private _buildInitialGrid;
    buildGridMap(grid: GridItem[]): Map<string, GridItem>;
    private gridToMap;
    countItems(grid: GridItem[]): number;
    isGridFull(grid: GridItem[]): boolean;
    validateMerge(state: GameState, fromCol: number, fromRow: number, toCol: number, toRow: number): {
        valid: true;
        resultItem: ItemDef;
        fromItem: GridItem;
        toItem: GridItem;
    } | {
        valid: false;
        reason: string;
    };
    executeMerge(state: GameState, fromCol: number, fromRow: number, toCol: number, toRow: number): {
        ok: true;
        newVersion: number;
        resultUid: number;
        resultId: number;
        fromCol: number;
        fromRow: number;
        toCol: number;
        toRow: number;
    } | {
        ok: false;
        reason: string;
    };
    executeSpawn(state: GameState, launcherCol: number, launcherRow: number): {
        ok: true;
        spawnedUid: number;
        spawnedId: number;
        spawnedName: string;
        targetCol: number;
        targetRow: number;
        newVersion: number;
        charges: number;
        maxCharges: number;
        rechargeTime: number;
    } | {
        ok: false;
        reason: string;
    };
    executeMove(state: GameState, fromCol: number, fromRow: number, toCol: number, toRow: number): {
        ok: true;
        newVersion: number;
    } | {
        ok: false;
        reason: string;
    };
    removeIngredientFromTable(state: GameState, tableCol: number, tableRow: number, ingredientId: number, targetCol: number, targetRow: number): {
        ok: true;
        removed_id: number;
        removed_uid: number;
        table_col: number;
        table_row: number;
        target_col: number;
        target_row: number;
        newVersion: number;
    } | {
        ok: false;
        reason: string;
    };
    validateCraftStart(state: GameState, tableCol: number, tableRow: number): {
        valid: true;
        recipe: RecipeDef;
    } | {
        valid: false;
        reason: string;
    };
    executeCraftStart(state: GameState, tableCol: number, tableRow: number): {
        ok: true;
        newVersion: number;
        recipe: RecipeDef;
    } | {
        ok: false;
        reason: string;
    };
    executeCraftRetrieve(state: GameState, tableCol: number, tableRow: number): {
        ok: true;
        resultUid: number;
        resultId: number;
        newVersion: number;
    } | {
        ok: false;
        reason: string;
    };
    addIngredientToTable(state: GameState, tableCol: number, tableRow: number, ingredientId: number, fromCol: number, fromRow: number): {
        ok: true;
        matched: boolean;
        newVersion: number;
    } | {
        ok: false;
        reason: string;
    };
    private matchRecipe;
    getStageBreakthroughPill(level: number): number;
    getStageBreakthroughReward(level: number): number;
    getExpToNextLevel(level: number): number;
    isMaxCultivation(level: number): boolean;
    needsBreakthroughPill(level: number): boolean;
    isBreakthroughReady(level: number, exp: number): boolean;
    getRequiredBreakthroughPill(level: number, exp: number): number;
    executeTryBreakthrough(state: GameState, pillId: number, uid: number, level: number, exp: number): {
        ok: true;
        newCultivation: CultivationData;
        rewards: RewardConfig;
    } | {
        ok: false;
        reason: string;
    };
    tickCraftingState(state: GameState): boolean;
    consumeExpPill(state: GameState, pillId: number, uid: number): {
        ok: true;
        cultivation: CultivationData;
    } | {
        ok: false;
        reason: string;
    };
    pouchDeposit(state: GameState, uid: number): {
        ok: true;
        pouch: number[];
    } | {
        ok: false;
        reason: string;
    };
    pouchWithdraw(state: GameState, itemId: number, col: number, row: number): {
        ok: true;
        pouch: number[];
        col: number;
        row: number;
    } | {
        ok: false;
        reason: string;
    };
    initBattleMonsters(state: GameState): void;
    private _buildMonsterList;
    battleHeal(state: GameState, itemId: number, uid: number, effectId: number): {
        ok: true;
        newVersion: number;
        grid: GridItem[];
    } | {
        ok: false;
        reason: string;
    };
    battleAttack(state: GameState, itemId: number, effectId: number, uid: number, col: number, row: number): {
        ok: true;
        grid: GridItem[];
        monsters: BattleMonster[];
        stage_complete: boolean;
        loot: number[];
    } | {
        ok: false;
        reason: string;
    };
    consumeStaminaPill(state: GameState, pillId: number, uid: number): {
        ok: true;
        stamina: number;
        max_stamina: number;
    } | {
        ok: false;
        reason: string;
    };
    _addExp(c: CultivationData, amount: number): void;
    pushAndPlace(state: GameState, fromCol: number, fromRow: number, toCol: number, toRow: number): {
        ok: true;
        newVersion: number;
        pushed_col: number;
        pushed_row: number;
        from_col: number;
        from_row: number;
        to_col: number;
        to_row: number;
    } | {
        ok: false;
        reason: string;
    };
    completeMeridianAcupoint(state: GameState, index: number, itemIds: number[]): {
        ok: true;
        newVersion: number;
        meridian_acupoints: any[];
        qi_gained: number;
        qi_full: boolean;
        grid: any[];
        cultivation: any;
        spirit_stones: number;
        stamina: number;
    } | {
        ok: false;
        reason: string;
    };
    initStorage(item: GridItem): void;
    depositItem(state: GameState, storageCol: number, storageRow: number, uid: number, fromCol: number, fromRow: number): {
        ok: true;
        newVersion: number;
    } | {
        ok: false;
        reason: string;
    };
    withdrawItem(state: GameState, storageCol: number, storageRow: number, uid: number, targetCol: number, targetRow: number): {
        ok: true;
        newVersion: number;
        uid: number;
        col: number;
        row: number;
    } | {
        ok: false;
        reason: string;
    };
    sellItem(state: GameState, uid: number): {
        ok: true;
        stones: number;
    } | {
        ok: false;
        reason: string;
    };
    buyItem(state: GameState, itemId: number, targetCol: number, targetRow: number): {
        ok: true;
        uid: number;
        stones: number;
    } | {
        ok: false;
        reason: string;
    };
    getGridHash(state: GameState): number;
}
export {};
