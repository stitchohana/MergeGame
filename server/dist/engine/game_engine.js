"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GameEngine = exports.TableState = void 0;
const interface_1 = require("../storage/interface");
const quest_engine_1 = require("./quest_engine");
const activity_engine_1 = require("./activity_engine");
const activity_settings_1 = require("./activity_settings");
const golden_finger_1 = require("./golden_finger");
const secret_realm_1 = require("./secret_realm");
const grid_search_1 = require("./grid_search");
const spawn_rng_1 = require("./spawn_rng");
const card_collection_1 = require("./card_collection");
const stair_climb_1 = require("./stair_climb");
const order_duel_1 = require("./order_duel");
const battle_pass_1 = require("./battle_pass");
const resource_purchase_1 = require("./resource_purchase");
const shop_1 = require("./shop");
const activity_access_1 = require("./activity_access");
const weekly_tasks_1 = require("./weekly_tasks");
// --- Item Table (enum variants for lookups) ---
var TableState;
(function (TableState) {
    TableState[TableState["IDLE"] = 0] = "IDLE";
    TableState[TableState["HAS_ITEMS"] = 1] = "HAS_ITEMS";
    TableState[TableState["CRAFTING"] = 2] = "CRAFTING";
    TableState[TableState["READY"] = 3] = "READY";
})(TableState || (exports.TableState = TableState = {}));
// --- Game Engine ---
class GameEngine {
    GRID_COLS = 7;
    GRID_ROWS = 9;
    MAX_CELLS = 63;
    itemsById = new Map();
    itemsByTypeLevel = new Map();
    recipes = [];
    recipesByTable = new Map();
    cultivation = null;
    get cultivationStages() { return this.cultivation?.stages ?? []; }
    initialSetups = new Map();
    staminaConfig = {
        max: 100,
        spawnCost: 10,
        regenInterval: 120,
        regenAmount: 1,
        multiplierThresholdBase: 100,
        multiplierDuration: 3600,
    };
    speedupConfig = { craftStoneCostPerMinute: 1, launcherStoneCostPerMinute: 1 };
    questResetHour = 0;
    orderRecipeProductProbability = 0.8;
    pouchConfig = { initialSlots: 7, unlockCostBase: 100, unlockCostIncrement: 50 };
    shopConfig = { shopItems: [], sellPrices: {}, buyPrices: {} };
    meridianThresholds = [];
    meridianOrderLevelRanges = [];
    maps = new Map();
    monsters = new Map();
    rewardsTable = new Map();
    homeMeridianDefs = [];
    questEngine;
    weeklyTaskService;
    activityEngine;
    battlePassService;
    cardCollectionService;
    stairClimbService;
    orderDuelService;
    resourcePurchaseService;
    shopService;
    goldenFingerService;
    secretRealmService;
    getAllItemDefs() { return [...this.itemsById.values()]; }
    constructor(configTables) {
        this.loadConfigs(configTables);
        this.shopService = new shop_1.ShopService(configTables.shop, id => this.getItemData(id), this.recipes);
        this.resourcePurchaseService = new resource_purchase_1.ResourcePurchaseService(configTables.gameConfig, (state, amount, now) => { this.addStamina(state, amount, now); });
        this.questEngine = new quest_engine_1.QuestEngine(configTables.quests);
        this.activityEngine = new activity_engine_1.ActivityEngine((0, activity_settings_1.resolveActivitySettings)(configTables.activities, configTables.stairClimb, configTables.orderSupply), configTables.weeklyTasks);
        this.weeklyTaskService = new weekly_tasks_1.WeeklyTaskService(configTables.weeklyTasks, this.activityEngine.getActivities(), this.questResetHour, this.questEngine.getQuestDefs());
        this.battlePassService = new battle_pass_1.BattlePassService(configTables.battlePass, configTables.activities, configTables.tokens, configTables.gameConfig);
        this.cardCollectionService = new card_collection_1.CardCollectionService(configTables.cardCollection, this.activityEngine.getActivities(), undefined, (state, rewards) => this.applyRewards(state, rewards));
        this.cardCollectionService.bindPackItems([...this.itemsById.values()]);
        this.stairClimbService = new stair_climb_1.StairClimbService(this.activityEngine.getActivities(), this.cultivationStages);
        this.orderDuelService = new order_duel_1.OrderDuelService(this.activityEngine.getActivities(), configTables.orderDuel);
        this.loadRewards(configTables.rewards);
        this.loadHomeMeridians(configTables.homeMeridians);
        this.goldenFingerService = new golden_finger_1.GoldenFingerService(configTables.goldenFinger, this);
        this.secretRealmService = new secret_realm_1.SecretRealmService(configTables.secretRealm, this);
    }
    // --- Config loading ---
    loadConfigs(configTables) {
        this.loadItems(configTables.items);
        this.loadCultivation(configTables.cultivation);
        this.loadInitialSetup(configTables.initialSetup);
        this.loadRecipes(configTables.recipes);
        this.loadGameConfig(configTables.gameConfig);
        this.loadShopConfig(configTables.shop);
        this.loadMeridians(configTables.meridians);
        this.loadExpedition(configTables.expedition);
        console.log(`[engine] Configs loaded: ${this.itemsById.size} items, ${this.recipes.length} recipes, ${this.cultivation?.stages.length ?? 0} stages, ${this.meridianThresholds.length} meridian thresholds, ${this.maps.size} maps, ${this.monsters.size} monsters`);
    }
    loadGameConfig(data) {
        try {
            const s = data.stamina;
            if (s) {
                this.staminaConfig = {
                    max: s.max ?? 100,
                    spawnCost: s.spawn_cost ?? 10,
                    regenInterval: s.regen_interval ?? 120,
                    regenAmount: s.regen_amount ?? 1,
                    multiplierThresholdBase: Math.max(1, Number(s.multiplier_threshold_base ?? 100)),
                    multiplierDuration: Math.max(1, Number(s.multiplier_duration ?? 3600)),
                };
                console.log(`[engine] Stamina config: max=${this.staminaConfig.max} cost=${this.staminaConfig.spawnCost} regen=${this.staminaConfig.regenAmount}/${this.staminaConfig.regenInterval}s`);
            }
            this.questResetHour = data.reset_hour ?? 0;
            const pouch = data.pouch ?? {};
            const positiveInteger = (value, fallback) => {
                const parsed = Number(value);
                return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
            };
            this.pouchConfig = {
                initialSlots: positiveInteger(pouch.initial_slots, 7),
                unlockCostBase: positiveInteger(pouch.unlock_cost_base, 100),
                unlockCostIncrement: positiveInteger(pouch.unlock_cost_increment, 50),
            };
            const recipeProductProbability = Number(data.orders?.recipe_product_probability ?? 0.8);
            this.orderRecipeProductProbability = Number.isFinite(recipeProductProbability)
                ? Math.min(1, Math.max(0, recipeProductProbability))
                : 0.8;
            const craftSpeedupRate = Number(data.craft_speedup_stone_cost_per_minute ?? 1);
            const launcherSpeedupRate = Number(data.launcher_speedup_stone_cost_per_minute ?? 1);
            this.speedupConfig = {
                craftStoneCostPerMinute: Number.isFinite(craftSpeedupRate) ? Math.max(0, craftSpeedupRate) : 1,
                launcherStoneCostPerMinute: Number.isFinite(launcherSpeedupRate) ? Math.max(0, launcherSpeedupRate) : 1,
            };
            if (this.questResetHour > 0) {
                console.log(`[engine] Daily reset hour: ${this.questResetHour}`);
            }
        }
        catch { /* ignore */ }
    }
    loadShopConfig(data) {
        try {
            this.shopConfig = {
                shopItems: data.items ?? [],
                sellPrices: {},
                buyPrices: {},
            };
            for (const s of this.shopConfig.shopItems) {
                this.shopConfig.buyPrices[String(s.id)] = s.price;
            }
            console.log(`[engine] Shop config: ${this.shopConfig.shopItems.length} items`);
        }
        catch { /* ignore */ }
    }
    getSellPrice(itemId) {
        return this.getItemData(itemId)?.sell_price ?? 0;
    }
    getBuyPrice(itemId) {
        return this.shopConfig.buyPrices[String(itemId)] ?? 0;
    }
    getShopItems() {
        return this.shopConfig.shopItems;
    }
    loadItems(data) {
        const categories = ["regular", "launcher", "crafting", "effect"];
        const typeMap = { regular: 0, launcher: 1, crafting: 2, effect: 5 };
        for (const cat of categories) {
            for (const item of data[cat] || []) {
                const configuredType = Number(item.type);
                item.type = cat === "regular" && configuredType === 4
                    ? 4
                    : typeMap[cat];
                this.itemsById.set(item.id, item);
                if (!this.itemsByTypeLevel.has(item.type)) {
                    this.itemsByTypeLevel.set(item.type, new Map());
                }
                const byLevel = this.itemsByTypeLevel.get(item.type);
                if (!byLevel.has(item.level)) {
                    byLevel.set(item.level, []);
                }
                byLevel.get(item.level).push(item);
            }
        }
    }
    loadRecipes(data) {
        this.recipes = data.recipes || [];
        const launcherIds = new Set();
        for (const item of this.itemsById.values()) {
            if (item.type === 1)
                launcherIds.add(Number(item.id));
        }
        const invalidLauncherIngredients = [];
        for (const recipe of this.recipes) {
            const ingredients = Array.isArray(recipe.ingredients)
                ? recipe.ingredients
                : [];
            for (const ingredient of ingredients) {
                const ingredientId = Number(ingredient);
                if (!launcherIds.has(ingredientId))
                    continue;
                invalidLauncherIngredients.push(`recipe ${recipe.id} ${recipe.name ?? ""} ingredient ${ingredientId}`.trim());
            }
        }
        if (invalidLauncherIngredients.length > 0) {
            throw new Error("Recipe ingredients cannot contain launcher items: "
                + invalidLauncherIngredients.join("; "));
        }
        this.recipesByTable.clear();
        for (const recipe of this.recipes) {
            for (const [, item] of this.itemsById) {
                const recipeIds = item.recipes || [];
                if (recipeIds.includes(recipe.id)) {
                    if (!this.recipesByTable.has(item.id)) {
                        this.recipesByTable.set(item.id, []);
                    }
                    this.recipesByTable.get(item.id).push(recipe);
                }
            }
        }
    }
    loadCultivation(data) {
        this.cultivation = data;
    }
    loadMeridians(data) {
        try {
            this.meridianThresholds = data.thresholds || [];
            const configuredRanges = Array.isArray(data.order_level_ranges)
                ? data.order_level_ranges
                : [];
            this.meridianOrderLevelRanges = configuredRanges
                .map((entry) => ({
                cultivation_min: Number(entry.cultivation_min),
                cultivation_max: Number(entry.cultivation_max),
                regular_min: Number(entry.items_regular?.[0]),
                regular_max: Number(entry.items_regular?.[1]),
                byproduct_min: Number(entry.items_byproduct?.[0] ?? entry.items_recipe_product?.[0]),
                byproduct_max: Number(entry.items_byproduct?.[1] ?? entry.items_recipe_product?.[1]),
                recipe_product_min: Number(entry.items_recipe_product?.[0]),
                recipe_product_max: Number(entry.items_recipe_product?.[1]),
            }))
                .filter((entry) => Number.isInteger(entry.cultivation_min)
                && Number.isInteger(entry.cultivation_max)
                && entry.cultivation_min <= entry.cultivation_max
                && Number.isInteger(entry.regular_min)
                && Number.isInteger(entry.regular_max)
                && Number.isInteger(entry.byproduct_min)
                && Number.isInteger(entry.byproduct_max)
                && Number.isInteger(entry.recipe_product_min)
                && Number.isInteger(entry.recipe_product_max));
        }
        catch { /* optional */ }
    }
    loadExpedition(data) {
        try {
            const maps = data.maps ?? [];
            for (const m of maps)
                this.maps.set(m.id, m);
            const monsters = data.monsters ?? [];
            for (const mo of monsters)
                this.monsters.set(mo.id, mo);
        }
        catch { /* optional */ }
    }
    loadRewards(data) {
        try {
            const rewards = data.rewards || {};
            for (const key of Object.keys(rewards)) {
                this.rewardsTable.set(Number(key), rewards[key]);
            }
            console.log(`[engine] Loaded ${this.rewardsTable.size} reward configs`);
        }
        catch { /* rewards.json optional */ }
    }
    getRewardConfig(rewardId) {
        return this.rewardsTable.get(rewardId);
    }
    loadHomeMeridians(data) {
        try {
            this.homeMeridianDefs = Array.isArray(data.stages) ? data.stages : [];
            console.log(`[engine] Loaded ${this.homeMeridianDefs.length} home meridian stages`);
        }
        catch { /* optional */ }
    }
    _copyRewardConfig(rewards) {
        const resolved = typeof rewards === "number"
            ? (this.rewardsTable.get(rewards) || {})
            : rewards;
        return {
            tokens: (resolved.tokens || []).map(token => ({ ...token })),
            items: (resolved.items || []).map(item => ({ ...item })),
        };
    }
    getHomeMeridianDefs() {
        return this.homeMeridianDefs.map(s => ({
            ...s,
            circulation_reward: typeof s.circulation_reward === "number"
                ? (this.rewardsTable.get(s.circulation_reward) ?? s.circulation_reward)
                : s.circulation_reward,
        }));
    }
    _getAcupointReward(def, _acupointIndex) {
        return {
            tokens: [{ token: interface_1.TokenType.STAMINA, amount: 15 }],
            items: [],
        };
    }
    applyHomeCirculationReward(state, stageIndex) {
        const def = this.homeMeridianDefs[stageIndex];
        const reward = this._copyRewardConfig(def.circulation_reward ?? {});
        const ownerLevel = Number(def.cultivation_level ?? 0);
        // GM advancement can leave earlier circulations unclaimed. Their EXP
        // belongs to the previous level; facilities and other rewards remain valid.
        if (ownerLevel > 0 && ownerLevel !== state.cultivation.current_level) {
            reward.tokens = (reward.tokens ?? []).filter(t => t.token !== interface_1.TokenType.EXP);
        }
        return this.applyRewards(state, reward);
    }
    _maxUnlockedHomeStageIndex(cultivationLevel) {
        let maxIndex = -1;
        for (let index = 0; index < this.homeMeridianDefs.length; index += 1) {
            const configuredLevel = Number(this.homeMeridianDefs[index]?.cultivation_level ?? 0);
            if (configuredLevel > 0) {
                if (configuredLevel <= cultivationLevel)
                    maxIndex = index;
                continue;
            }
            throw new Error("home_meridian_missing_cultivation_level");
        }
        return maxIndex;
    }
    hasReadyHomeMeridianCirculation(state) {
        const progressList = Array.isArray(state.home_meridian_progress)
            ? state.home_meridian_progress
            : [];
        const maxStageIndex = this._maxUnlockedHomeStageIndex(state.cultivation.current_level);
        return progressList.some(progress => {
            const stageIndex = Number(progress?.stage ?? -1);
            if (!Number.isInteger(stageIndex) || stageIndex < 0 || stageIndex > maxStageIndex) {
                return false;
            }
            if (progress.circulation_completed === true)
                return false;
            const def = this.homeMeridianDefs[stageIndex];
            const acupointCount = Number(def?.acupoints ?? 0);
            if (!Number.isInteger(acupointCount) || acupointCount <= 0)
                return false;
            const lit = Array.isArray(progress.lit) ? progress.lit : [];
            for (let index = 0; index < acupointCount; index += 1) {
                if (!Boolean(lit[index]))
                    return false;
            }
            return true;
        });
    }
    lightHomeAcupoint(state, stageIndex, acupointIndex) {
        if (this.isBreakthroughReady(state.cultivation.current_level, state.cultivation.current_exp)) {
            return { ok: false, reason: "breakthrough_needed" };
        }
        if (stageIndex < 0 || stageIndex >= this.homeMeridianDefs.length) {
            return { ok: false, reason: "invalid_stage" };
        }
        if (stageIndex > this._maxUnlockedHomeStageIndex(state.cultivation.current_level)) {
            return { ok: false, reason: "stage_locked" };
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
        stageProgress.lit = Array.from({ length: def.acupoints }, (_value, index) => Boolean(stageProgress.lit[index]));
        if (stageProgress.lit[acupointIndex]) {
            return { ok: false, reason: "already_lit" };
        }
        if (stageProgress.circulation_completed) {
            return { ok: false, reason: "circulation_completed" };
        }
        const nextAcupointIndex = stageProgress.lit.findIndex(isLit => !isLit);
        if (acupointIndex !== nextAcupointIndex) {
            return { ok: false, reason: "out_of_order" };
        }
        // Check qi
        const qiCost = def.qi_cost ?? 10;
        if (state.cultivation.current_qi < qiCost) {
            return { ok: false, reason: "insufficient_qi" };
        }
        // Deduct qi
        state.cultivation.current_qi -= qiCost;
        // Light acupoint
        stageProgress.lit[acupointIndex] = true;
        // Acupoint reward
        let rewardsApplied = { tokens: [], items: [] };
        const acupointReward = this._getAcupointReward(def, acupointIndex);
        if (acupointReward) {
            const r = this.applyRewards(state, acupointReward);
            rewardsApplied.tokens.push(...(r.tokens || []));
            rewardsApplied.items.push(...(r.items || []));
        }
        // Lighting the final node only makes the circulation ready. The actual
        // circulation reward is granted by runHomeMeridianCirculation after the
        // player explicitly presses the run button.
        const allLit = stageProgress.lit.every(l => l);
        state.version += 1;
        return {
            ok: true,
            circulation_completed: Boolean(stageProgress.circulation_completed),
            circulation_ready: allLit && !stageProgress.circulation_completed,
            rewards: rewardsApplied,
            cultivation: state.cultivation,
            spirit_stones: state.spirit_stones,
            stamina: state.stamina,
            pending_rewards: state.pending_rewards,
            home_meridian_progress: state.home_meridian_progress,
            meridian_acupoints: state.meridian_acupoints || [],
        };
    }
    runHomeMeridianCirculation(state, stageIndex) {
        if (stageIndex < 0 || stageIndex >= this.homeMeridianDefs.length) {
            return { ok: false, reason: "invalid_stage" };
        }
        if (stageIndex > this._maxUnlockedHomeStageIndex(state.cultivation.current_level)) {
            return { ok: false, reason: "stage_locked" };
        }
        const def = this.homeMeridianDefs[stageIndex];
        state.home_meridian_progress = state.home_meridian_progress || [];
        let stageProgress = state.home_meridian_progress.find(progress => progress.stage === stageIndex);
        if (!stageProgress) {
            return { ok: false, reason: "circulation_not_ready" };
        }
        stageProgress.lit = Array.from({ length: def.acupoints }, (_value, index) => Boolean(stageProgress.lit[index]));
        if (stageProgress.circulation_completed) {
            return { ok: false, reason: "circulation_completed" };
        }
        if (!stageProgress.lit.every(isLit => isLit)) {
            return { ok: false, reason: "circulation_not_ready" };
        }
        const rewardsApplied = this.applyHomeCirculationReward(state, stageIndex);
        const launchersRefreshed = this.refreshBoardLaunchers(state);
        stageProgress.circulation_completed = true;
        this.syncBreakthroughOrder(state);
        // Reveal the next fixed onboarding wave only after the explicit run
        // action has completed the current circulation.
        const meridianThreshold = this._findMeridianThreshold(state.cultivation.current_level);
        state.meridian_fixed_wave_pending = false;
        this._tryRevealFixedOrders(state, meridianThreshold);
        state.version += 1;
        return {
            ok: true,
            circulation_completed: true,
            circulation_ready: false,
            rewards: rewardsApplied,
            cultivation: state.cultivation,
            spirit_stones: state.spirit_stones,
            stamina: state.stamina,
            pending_rewards: state.pending_rewards,
            home_meridian_progress: state.home_meridian_progress,
            meridian_acupoints: state.meridian_acupoints || [],
            grid: state.grid,
            launchers_refreshed: launchersRefreshed,
        };
    }
    refreshBoardLaunchers(state) {
        let refreshed = 0;
        for (const item of state.grid || []) {
            const itemDef = this.getItemData(item.id);
            if (!itemDef || !this.isLauncher(itemDef))
                continue;
            item.charges = itemDef.max_charges ?? 3;
            delete item.last_charge_time;
            delete item._recharge_remaining;
            refreshed += 1;
        }
        return refreshed;
    }
    gmActivateHomeAcupoints(state, amount) {
        const requestedAmount = Math.max(0, amount);
        let activated = 0;
        let completedStages = 0;
        state.home_meridian_progress = state.home_meridian_progress || [];
        // Preserve normal activation rewards, while letting the GM command bypass qi costs.
        const maxStageIndex = this._maxUnlockedHomeStageIndex(state.cultivation.current_level);
        for (let stageIndex = 0; stageIndex < this.homeMeridianDefs.length && stageIndex <= maxStageIndex && activated < requestedAmount; stageIndex++) {
            const def = this.homeMeridianDefs[stageIndex];
            let stageProgress = state.home_meridian_progress.find(progress => progress.stage === stageIndex);
            if (!stageProgress) {
                stageProgress = { stage: stageIndex, lit: new Array(def.acupoints).fill(false), circulation_completed: false };
                state.home_meridian_progress.push(stageProgress);
            }
            const normalizedProgress = stageProgress;
            normalizedProgress.lit = Array.from({ length: def.acupoints }, (_value, acupointIndex) => Boolean(normalizedProgress.lit[acupointIndex]));
            if (normalizedProgress.circulation_completed) {
                continue;
            }
            for (let acupointIndex = 0; acupointIndex < def.acupoints && activated < requestedAmount; acupointIndex++) {
                if (normalizedProgress.lit[acupointIndex]) {
                    continue;
                }
                normalizedProgress.lit[acupointIndex] = true;
                activated += 1;
                const acupointReward = this._getAcupointReward(def, acupointIndex);
                if (acupointReward) {
                    this.applyRewards(state, acupointReward);
                }
            }
            if (normalizedProgress.lit.every(isLit => isLit)) {
                normalizedProgress.circulation_completed = true;
                completedStages += 1;
                this.applyHomeCirculationReward(state, stageIndex);
            }
        }
        if (activated > 0) {
            const meridianThreshold = this._findMeridianThreshold(state.cultivation.current_level);
            this._tryRevealFixedOrders(state, meridianThreshold);
            state.version += 1;
        }
        return { activated, completed_stages: completedStages };
    }
    getMonster(id) {
        return this.monsters.get(id) ?? null;
    }
    generateMeridianRequirements(state) {
        if (this.syncBreakthroughOrder(state)) {
            return { acupoints: state.meridian_acupoints || [] };
        }
        const thresholds = this.meridianThresholds;
        if (!thresholds.length)
            return { acupoints: [] };
        const stageLevel = state.cultivation.current_level;
        const t = this._findMeridianThreshold(stageLevel) ?? thresholds[0];
        const foundIdx = thresholds.indexOf(t);
        const orderCount = t.order_count ?? t.acupoints ?? 3;
        const fixedOrderWaves = this._getFixedOrderWaves(t);
        const previousThresholdIdx = Number(state.meridian_threshold_idx ?? -1);
        if (previousThresholdIdx !== foundIdx) {
            // A cursor belongs to one threshold.  Do not let a completed wave from
            // an earlier cultivation stage skip fixed orders in a later one.
            state.meridian_fixed_order_cursor = 0;
            state.meridian_fixed_wave_pending = false;
            state.meridian_acupoints = [];
        }
        state.meridian_threshold_idx = foundIdx;
        if (Array.isArray(state.meridian_acupoints) && state.meridian_acupoints.length > 0) {
            return { acupoints: state.meridian_acupoints };
        }
        if (fixedOrderWaves.length > 0) {
            if (state.meridian_fixed_wave_pending === true)
                return { acupoints: [] };
            this._tryRevealFixedOrders(state, t);
            return { acupoints: state.meridian_acupoints || [] };
        }
        const weightedPool = this.getUnlockedOrderPoolWithWeights(state);
        const pool = weightedPool.ids;
        const typeMin = t.count_min ?? 1;
        const typeMax = t.count_max ?? 3;
        if (pool.length === 0) {
            state.meridian_acupoints = [];
            return { acupoints: [] };
        }
        const acupoints = this._generateRandomMeridianBatch(pool, weightedPool.weights, orderCount, typeMin, typeMax, t.acupoint_rewards);
        state.meridian_acupoints = acupoints;
        return { acupoints };
    }
    /**
     * Force a GM refresh of the active order list.
     *
     * Normal generation intentionally keeps an existing list.  A GM refresh
     * clears random orders before generating them again, while fixed onboarding
     * waves are rebuilt from the currently visible orders so the wave cursor is
     * never advanced or skipped.  Breakthrough requirements always win over a
     * refresh and are kept authoritative.
     */
    refreshMeridianRequirements(state) {
        const currentOrders = Array.isArray(state.meridian_acupoints)
            ? state.meridian_acupoints
            : [];
        const breakthroughRequired = !this.hasReadyHomeMeridianCirculation(state)
            && this.getRequiredBreakthroughItems(state.cultivation.current_level, state.cultivation.current_exp).length > 0;
        if (breakthroughRequired) {
            this.syncBreakthroughOrder(state);
            const acupoints = state.meridian_acupoints || [];
            state.version += 1;
            return {
                acupoints,
                refreshedCount: 0,
                preservedBreakthrough: true,
                fixedOrdersPreserved: false,
            };
        }
        const threshold = this._findMeridianThreshold(state.cultivation.current_level);
        const thresholdIdx = this.meridianThresholds.indexOf(threshold);
        const thresholdChanged = thresholdIdx >= 0
            && Number(state.meridian_threshold_idx ?? -1) !== thresholdIdx;
        const fixedOrderWaves = this._getFixedOrderWaves(threshold);
        if (fixedOrderWaves.length > 0 && !thresholdChanged) {
            const activeFixedOrders = currentOrders.filter((order) => order?.completed !== true && order?.breakthrough_order !== true);
            if (activeFixedOrders.length > 0) {
                // The fixed-order cursor points past the whole visible wave.  Reusing
                // generateMeridianRequirements after clearing it would therefore skip
                // to the next wave, so rebuild the same visible orders explicitly.
                const rawCursor = Number(state.meridian_fixed_order_cursor ?? 0);
                const cursor = Number.isFinite(rawCursor) ? Math.max(0, Math.floor(rawCursor)) : 0;
                let waveStart = 0;
                let activeWave = null;
                for (const wave of fixedOrderWaves) {
                    const waveEnd = waveStart + wave.length;
                    if (cursor > waveStart && cursor <= waveEnd) {
                        activeWave = wave;
                        break;
                    }
                    waveStart = waveEnd;
                }
                const itemIdsOf = (order) => {
                    const configuredIds = Array.isArray(order)
                        ? order
                        : (order?.item_id !== undefined ? [order.item_id] : order?.item_ids);
                    return Array.isArray(configuredIds)
                        ? configuredIds.map((id) => Number(id)).filter((id) => Number.isInteger(id))
                        : [];
                };
                const canReuseLatestConfig = activeWave !== null && activeFixedOrders.every((order) => activeWave.some((fixedOrder) => JSON.stringify(itemIdsOf(fixedOrder)) === JSON.stringify(itemIdsOf(order))));
                const usedConfigIndexes = new Set();
                state.meridian_acupoints = activeFixedOrders.map((order) => {
                    // Match by item IDs so completing fixed orders out of sequence does
                    // not make refresh re-introduce an already completed order.
                    let sourceOrder = order;
                    if (canReuseLatestConfig) {
                        const matchingIndex = activeWave.findIndex((fixedOrder, index) => !usedConfigIndexes.has(index)
                            && JSON.stringify(itemIdsOf(fixedOrder)) === JSON.stringify(itemIdsOf(order)));
                        if (matchingIndex >= 0) {
                            usedConfigIndexes.add(matchingIndex);
                            sourceOrder = activeWave[matchingIndex];
                        }
                    }
                    const refreshed = this._genFixedAcupoint(sourceOrder);
                    if (order.order_supply_completed_counts) {
                        refreshed.order_supply_completed_counts = { ...order.order_supply_completed_counts };
                    }
                    if (!refreshed.fixed_order_rewards && threshold?.acupoint_rewards && refreshed.total_value > 0) {
                        refreshed.rewards = this._scaleRewardConfig(threshold.acupoint_rewards, refreshed.total_value);
                    }
                    return refreshed;
                });
                state.version += 1;
                return {
                    acupoints: state.meridian_acupoints,
                    refreshedCount: state.meridian_acupoints.length,
                    preservedBreakthrough: false,
                    fixedOrdersPreserved: true,
                };
            }
        }
        // Random orders (or a newly entered threshold) can safely be regenerated
        // through the regular path.  It also reveals the next fixed wave when the
        // previous one has been fully completed.
        state.meridian_acupoints = [];
        const result = this.generateMeridianRequirements(state);
        state.version += 1;
        return {
            acupoints: result.acupoints,
            refreshedCount: result.acupoints.length,
            preservedBreakthrough: false,
            fixedOrdersPreserved: false,
        };
    }
    _getFixedOrderWaves(threshold) {
        const configured = threshold?.fixed_orders;
        if (!Array.isArray(configured) || configured.length === 0)
            return [];
        // The nested form is an array of waves, each containing fixed-order
        // objects.  Keep it intact so multi-item orders and per-order rewards work.
        const isNestedWaveConfig = configured.some((entry) => Array.isArray(entry)
            && entry.some((order) => Array.isArray(order)
                || (order !== null && typeof order === "object")));
        if (isNestedWaveConfig) {
            return configured
                .filter((entry) => Array.isArray(entry))
                .filter((wave) => wave.length > 0)
                .map((wave) => wave.filter((order) => order !== null && order !== undefined));
        }
        // The compact form is an array of wave objects such as
        // {"item_ids": [5003, 5004, 6001]}.  Each ID is one order in that wave.
        // Treat every such object as a wave, including single-ID waves, so the
        // compact format remains unambiguous.
        const groupedWaveConfig = configured.every((entry) => entry !== null
            && typeof entry === "object"
            && !Array.isArray(entry)
            && Array.isArray(entry.item_ids));
        if (groupedWaveConfig) {
            return configured
                .map((waveConfig) => {
                const itemIds = Array.isArray(waveConfig.item_ids) ? waveConfig.item_ids : [];
                return itemIds.map((itemId) => ({
                    item_id: itemId,
                    ...(waveConfig.rewards !== undefined ? { rewards: waveConfig.rewards } : {}),
                }));
            })
                .filter((wave) => wave.length > 0);
        }
        throw new Error("invalid_fixed_order_waves");
    }
    _tryRevealFixedOrders(state, threshold) {
        const fixedOrderWaves = this._getFixedOrderWaves(threshold);
        if (fixedOrderWaves.length === 0)
            return false;
        state.meridian_acupoints = Array.isArray(state.meridian_acupoints) ? state.meridian_acupoints : [];
        if (state.meridian_acupoints.length > 0)
            return false;
        const rawCursor = Number(state.meridian_fixed_order_cursor ?? 0);
        const cursor = Number.isFinite(rawCursor) ? Math.max(0, Math.floor(rawCursor)) : 0;
        let waveStart = 0;
        for (const wave of fixedOrderWaves) {
            const waveEnd = waveStart + wave.length;
            if (cursor < waveEnd) {
                const offset = Math.max(0, cursor - waveStart);
                const templateRewards = threshold?.acupoint_rewards;
                state.meridian_acupoints = wave.slice(offset).map((fixedOrder) => {
                    const order = this._genFixedAcupoint(fixedOrder);
                    if (!order.fixed_order_rewards && templateRewards && order.total_value > 0) {
                        order.rewards = this._scaleRewardConfig(templateRewards, order.total_value);
                    }
                    return order;
                });
                state.meridian_fixed_order_cursor = waveEnd;
                return state.meridian_acupoints.length > 0;
            }
            waveStart = waveEnd;
        }
        return false;
    }
    _scaleRewardConfig(rewards, multiplier) {
        const base = typeof rewards === "number"
            ? (this.rewardsTable.get(rewards) ?? { tokens: [], items: [] })
            : rewards;
        return {
            tokens: (base.tokens || []).map(t => ({ token: t.token, amount: t.amount * multiplier })),
            items: (base.items || []).map(i => ({ id: i.id, count: i.count * multiplier })),
        };
    }
    _findMeridianThreshold(stageLevel) {
        for (const t of this.meridianThresholds) {
            if (t.stage === stageLevel)
                return t;
        }
        return this.meridianThresholds[0] ?? null;
    }
    _generateRandomMeridianBatch(pool, weights, orderCount, typeMin, typeMax, templateRewards) {
        const acupoints = [];
        const availablePool = [...pool];
        for (let i = 0; i < orderCount; i++) {
            const remainingOrders = orderCount - i - 1;
            const maxTypes = Math.min(typeMax, Math.max(0, availablePool.length - remainingOrders));
            const minTypes = Math.min(typeMin, maxTypes);
            const order = this._genOneAcupoint(availablePool, minTypes, maxTypes, weights);
            const selectedIds = new Set(order.item_ids.map((itemId) => Number(itemId)));
            for (let poolIndex = availablePool.length - 1; poolIndex >= 0; poolIndex--) {
                if (selectedIds.has(availablePool[poolIndex]))
                    availablePool.splice(poolIndex, 1);
            }
            if (templateRewards && order.total_value > 0) {
                order.rewards = this._scaleRewardConfig(templateRewards, order.total_value);
            }
            acupoints.push(order);
        }
        acupoints.sort((left, right) => Number(left.total_value ?? 0) - Number(right.total_value ?? 0));
        return acupoints;
    }
    _genOneAcupoint(pool, typeMin, typeMax, weights) {
        const numTypes = typeMin + Math.floor(Math.random() * (typeMax - typeMin + 1));
        const pickedIds = [];
        const names = [];
        const items = [];
        let totalValue = 0;
        const available = [...pool];
        for (let j = 0; j < numTypes && available.length > 0; j++) {
            const recipeProducts = available.filter(itemId => this.getItemData(itemId)?.type === 4);
            const ordinaryItems = available.filter(itemId => this.getItemData(itemId)?.type !== 4);
            // Select the category first so its probability is independent of pool
            // size and source weights. Exhausted categories fall back to the other.
            const candidates = recipeProducts.length > 0 && ordinaryItems.length > 0
                ? (Math.random() < this.orderRecipeProductProbability ? recipeProducts : ordinaryItems)
                : available;
            const availableWeights = candidates.map(itemId => {
                const weight = Number(weights?.get(itemId) ?? 1);
                return Number.isFinite(weight) && weight > 0 ? weight : 1;
            });
            const totalWeight = availableWeights.reduce((sum, weight) => sum + weight, 0);
            let roll = Math.random() * totalWeight;
            let idx = candidates.length - 1;
            for (let candidateIndex = 0; candidateIndex < candidates.length; candidateIndex++) {
                roll -= availableWeights[candidateIndex];
                if (roll < 0) {
                    idx = candidateIndex;
                    break;
                }
            }
            const itemId = candidates[idx];
            available.splice(available.indexOf(itemId), 1);
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
    _genFixedAcupoint(fixedOrder) {
        // A fixed order normally contains one item, so config can use the clearer
        // singular item_id; multi-item definitions use item_ids.
        let configuredIds;
        if (Array.isArray(fixedOrder)) {
            configuredIds = fixedOrder;
        }
        else if (fixedOrder?.item_id !== undefined && fixedOrder?.item_id !== null) {
            configuredIds = [fixedOrder.item_id];
        }
        else {
            configuredIds = fixedOrder?.item_ids;
        }
        const itemIds = Array.isArray(configuredIds)
            ? configuredIds.map((id) => Number(id)).filter((id) => Number.isInteger(id))
            : [];
        const names = [];
        const items = [];
        let totalValue = 0;
        for (const itemId of itemIds) {
            const itemData = this.getItemData(itemId);
            const name = itemData?.name ?? `#${itemId}`;
            const value = itemData?.value ?? 0;
            totalValue += value;
            names.push(name);
            items.push({ item_id: itemId, name, value });
        }
        const rewards = fixedOrder?.rewards
            ? this._copyRewardConfig(fixedOrder.rewards)
            : undefined;
        return {
            item_ids: itemIds,
            name: names.join(", "),
            items,
            completed: false,
            total_value: totalValue,
            ...(rewards ? { rewards, fixed_order_rewards: true } : {}),
        };
    }
    isOrderCandidate(itemDef, cultivationLevel, source) {
        if (!itemDef)
            return false;
        if (source === "items_recipe_product" && itemDef.type !== 4)
            return false;
        if (source !== "items_recipe_product" && itemDef.type !== 0)
            return false;
        if (itemDef.level === null || itemDef.level === undefined)
            return false;
        const itemLevel = Number(itemDef.level);
        if (!Number.isFinite(itemLevel))
            return false;
        const levelRange = this.meridianOrderLevelRanges.find((range) => cultivationLevel >= range.cultivation_min && cultivationLevel <= range.cultivation_max);
        if (!levelRange)
            return true;
        if (source === "items_regular") {
            return itemLevel >= levelRange.regular_min && itemLevel <= levelRange.regular_max;
        }
        if (source === "items_byproduct") {
            return itemLevel >= levelRange.byproduct_min && itemLevel <= levelRange.byproduct_max;
        }
        if (source === "items_recipe_product") {
            return itemLevel >= levelRange.recipe_product_min && itemLevel <= levelRange.recipe_product_max;
        }
        return false;
    }
    registerProductionUnlock(state, itemId) {
        const itemDef = this.getItemData(itemId);
        if (!itemDef || (!this.isLauncher(itemDef) && itemDef.type !== 2))
            return false;
        if (state.unlocked_production_item_ids.includes(itemId))
            return false;
        state.unlocked_production_item_ids.push(itemId);
        state.unlocked_production_item_ids.sort((a, b) => a - b);
        return true;
    }
    /** All confirmed acquisitions share the same persisted discovery history. */
    recordItemDiscovery(state, itemId) {
        if (!Number.isInteger(itemId) || itemId <= 0 || !this.getItemData(itemId))
            return false;
        if (state.crafted_item_ids.includes(itemId))
            return false;
        state.crafted_item_ids.push(itemId);
        return true;
    }
    claimItemCatalogReward(state, itemId) {
        if (!Number.isSafeInteger(itemId) || itemId <= 0 || !this.getItemData(itemId)) {
            return { ok: false, reason: "item_not_found" };
        }
        if (!state.crafted_item_ids?.includes(itemId))
            return { ok: false, reason: "item_locked" };
        const claimed = state.item_catalog_claimed_ids;
        if (claimed.includes(itemId))
            return { ok: true, already_claimed: true, reward_stamina: 0 };
        this.addStamina(state, 1);
        state.item_catalog_claimed_ids = [...claimed, itemId].sort((a, b) => a - b);
        return { ok: true, already_claimed: false, reward_stamina: 1 };
    }
    getUnlockedOrderPool(state) {
        return this.getUnlockedOrderPoolWithWeights(state).ids;
    }
    getUnlockedOrderPoolWithWeights(state) {
        const obtainableIds = new Set();
        const regularIds = new Set();
        const byproductIds = new Set();
        const recipeProductIds = new Set();
        const availableRecipes = new Map();
        const sourceWeights = new Map();
        const cultivationLevel = Number(state.cultivation?.current_level ?? 1);
        const addSpawnMergeChain = (itemId, sourceIds, chainWeight) => {
            let changed = false;
            let itemDef = this.getItemData(itemId);
            const visitedIds = new Set();
            while (itemDef && !visitedIds.has(itemDef.id)) {
                visitedIds.add(itemDef.id);
                if (!obtainableIds.has(itemDef.id)) {
                    obtainableIds.add(itemDef.id);
                    changed = true;
                }
                sourceIds.add(itemDef.id);
                const previousWeight = sourceWeights.get(itemDef.id) ?? 0;
                sourceWeights.set(itemDef.id, previousWeight + Math.max(0, chainWeight));
                itemDef = this.getNextLevel(itemDef.type, itemDef.level, itemDef.group_id);
            }
            return changed;
        };
        const getSpawnChainKey = (itemId) => {
            const itemDef = this.getItemData(itemId);
            return itemDef && Number.isInteger(itemDef.group_id)
                ? `group:${itemDef.group_id}`
                : `item:${itemId}`;
        };
        // Owned facilities can produce new orders after being withdrawn from the
        // pouch. Historical facilities that were sold/consumed remain excluded.
        const productionIds = [...new Set(this.getInventoryItems(state)
                .map(item => Number(item.id))
                .filter((itemId) => {
                const production = this.getItemData(itemId);
                return !!production && (this.isLauncher(production) || production.type === 2);
            }))];
        for (const productionId of productionIds) {
            const production = this.getItemData(productionId);
            if (!production)
                continue;
            if (this.isLauncher(production)) {
                const spawnWeightsByChain = new Map();
                const spawnByChain = new Map();
                for (const spawn of production.spawns || []) {
                    const chainKey = getSpawnChainKey(spawn.id);
                    const weight = Number(spawn.weight);
                    spawnWeightsByChain.set(chainKey, (spawnWeightsByChain.get(chainKey) ?? 0) + (Number.isFinite(weight) ? Math.max(0, weight) : 0));
                    if (!spawnByChain.has(chainKey))
                        spawnByChain.set(chainKey, spawn.id);
                }
                const highestChainWeight = Math.max(0, ...spawnWeightsByChain.values());
                const byproductChainKeys = new Set([...spawnWeightsByChain]
                    .filter(([, totalWeight]) => totalWeight < highestChainWeight)
                    .map(([chainKey]) => chainKey));
                const totalSpawnWeight = [...spawnWeightsByChain.values()].reduce((sum, weight) => sum + weight, 0);
                for (const [chainKey, chainWeight] of spawnWeightsByChain) {
                    const spawnId = spawnByChain.get(chainKey);
                    if (spawnId === undefined)
                        continue;
                    const sourceIds = byproductChainKeys.has(chainKey)
                        ? byproductIds
                        : regularIds;
                    const normalizedWeight = totalSpawnWeight > 0 ? chainWeight / totalSpawnWeight : 1;
                    addSpawnMergeChain(spawnId, sourceIds, normalizedWeight);
                }
                for (const spawnId of production.fixed_spawns || []) {
                    const chainKey = getSpawnChainKey(spawnId);
                    const sourceIds = byproductChainKeys.has(chainKey)
                        ? byproductIds
                        : regularIds;
                    // Fixed spawns are guaranteed outputs rather than weighted rolls;
                    // keep them eligible with a small, neutral contribution.
                    addSpawnMergeChain(spawnId, sourceIds, 1);
                }
            }
            if (production.type === 2) {
                for (const recipe of this.getRecipesForTable(production.id)) {
                    availableRecipes.set(recipe.id, recipe);
                }
            }
        }
        // Resolve recipes as a dependency graph. A product is available only when
        // its table is on the board and every ingredient can already be produced.
        // Repeating to a fixed point supports recipes that consume other products;
        // cycles without a producible input never become available.
        let addedRecipeProduct = true;
        while (addedRecipeProduct) {
            addedRecipeProduct = false;
            for (const recipe of availableRecipes.values()) {
                if (recipe.ingredients.every((ingredientId) => obtainableIds.has(ingredientId))) {
                    if (!obtainableIds.has(recipe.result)) {
                        obtainableIds.add(recipe.result);
                        addedRecipeProduct = true;
                    }
                    recipeProductIds.add(recipe.result);
                    const ingredientWeights = recipe.ingredients.map((ingredientId) => sourceWeights.get(ingredientId) ?? 0);
                    if (ingredientWeights.length > 0 && ingredientWeights.every(weight => weight > 0)) {
                        // A crafted result cannot be more likely than its least likely
                        // required material. This keeps recipe orders tied to the
                        // launcher probability of their dependency chain.
                        sourceWeights.set(recipe.result, Math.min(...ingredientWeights));
                    }
                }
            }
        }
        const orderIds = new Set();
        const addSourceCandidates = (sourceIds, source) => {
            for (const itemId of sourceIds) {
                if (this.isOrderCandidate(this.getItemData(itemId), cultivationLevel, source)) {
                    orderIds.add(itemId);
                }
            }
        };
        addSourceCandidates(regularIds, "items_regular");
        addSourceCandidates(byproductIds, "items_byproduct");
        addSourceCandidates(recipeProductIds, "items_recipe_product");
        const ids = [...orderIds].sort((a, b) => a - b);
        const weights = new Map();
        for (const itemId of ids) {
            const weight = sourceWeights.get(itemId) ?? 0;
            weights.set(itemId, weight > 0 ? weight : 1);
        }
        return { ids, weights };
    }
    loadInitialSetup(data) {
        if (!data.main || !Array.isArray(data.main.items))
            throw new Error("invalid_initial_setup");
        for (const key of ["main", "battle"]) {
            if (data[key])
                this.initialSetups.set(key === "battle" ? 1 : 0, data[key].items);
        }
    }
    // --- Config queries ---
    getItemData(id) {
        return this.itemsById.get(id) ?? null;
    }
    getItemByLevel(type, level, groupId = 0) {
        const byLevel = this.itemsByTypeLevel.get(type);
        if (!byLevel)
            return null;
        const items = byLevel.get(level) || [];
        if (items.length === 0)
            return null;
        if (groupId === 0)
            return items[0];
        return items.find((i) => i.group_id === groupId) ?? null;
    }
    getNextLevel(type, level, groupId = 0) {
        return this.getItemByLevel(type, level + 1, groupId);
    }
    rollSpawn(launcherId) {
        const data = this.getItemData(launcherId);
        if (!data?.spawns || data.spawns.length === 0)
            return null;
        const totalWeight = data.spawns.reduce((sum, s) => sum + s.weight, 0);
        let roll = Math.floor(Math.random() * totalWeight);
        for (const s of data.spawns) {
            roll -= s.weight;
            if (roll < 0)
                return this.getItemData(s.id);
        }
        return this.getItemData(data.spawns[data.spawns.length - 1].id);
    }
    getRecipesForTable(tableId) {
        return this.recipesByTable.get(tableId) || [];
    }
    getOrderSupplyMaterialLevel(cultivationLevel) {
        const level = Math.max(1, Math.floor(Number(cultivationLevel) || 1));
        // Each realm has three phases. Supply uses the corresponding basic
        // material tier: 练气 1–3, 筑基 5–7, 金丹 9–11, 元婴 13–15.
        // 练气有九层，按前三层、 中三层、后三层对应前中后期；
        // 后续境界各有前中后三期，分别使用 5–7、9–11、13–15 级材料。
        if (level <= 9)
            return 1 + Math.floor((level - 1) / 3);
        if (level <= 12)
            return 5 + (level - 10);
        if (level <= 15)
            return 9 + (level - 13);
        return Math.min(16, 13 + Math.max(0, level - 16));
    }
    getOrderSupplyMaterials(itemId, cultivationLevel = 1, limitToRequiredLevel = true) {
        const materials = new Set();
        const visiting = new Set();
        const targetLevel = this.getOrderSupplyMaterialLevel(cultivationLevel);
        const visit = (id) => {
            const item = this.getItemData(id);
            if (!item || visiting.has(id))
                return;
            const recipe = this.recipes.find(candidate => candidate.result === id);
            if (recipe) {
                visiting.add(id);
                for (const ingredientId of recipe.ingredients)
                    visit(ingredientId);
                visiting.delete(id);
                return;
            }
            if (item.type !== 0)
                return;
            // Higher-tier materials cannot be split back into a lower-level requirement.
            // Apply the cap to recipe leaves as well as directly requested materials.
            const materialLevel = limitToRequiredLevel ? Math.min(targetLevel, item.level) : targetLevel;
            const base = this.getItemByLevel(0, materialLevel, item.group_id);
            if (base && !this.recipes.some(candidate => candidate.result === base.id))
                materials.add(base.id);
        };
        visit(itemId);
        return [...materials];
    }
    countOrderSupplyAvailableItems(state, itemId) {
        let count = 0;
        for (const item of state.grid) {
            if (!item.immovable && item.id === itemId)
                count++;
            count += (item.storage?.items ?? []).filter(stored => stored.id === itemId).length;
            if (this.getItemData(item.id)?.type !== 2 || !item.craft)
                continue;
            const craft = item.craft;
            if ([TableState.CRAFTING, TableState.READY].includes(craft._craft_state)) {
                if (Number(craft._craft_result_id || craft._craft_recipe?.result || 0) === itemId)
                    count++;
            }
            else {
                count += (craft._craft_stored ?? []).filter(stored => Number(stored.id) === itemId).length;
            }
        }
        count += (state.pouch ?? []).filter(item => this.getStoredItemId(item) === itemId).length;
        count += (state.pending_rewards).filter(item => item.kind !== "card_pack" && item.id === itemId).length;
        return count;
    }
    getMissingOrderSupplyMaterials(state) {
        const targets = new Map();
        for (const order of state.meridian_acupoints ?? []) {
            if (order.completed || order.breakthrough_order)
                continue;
            const ids = order.item_ids;
            for (const id of ids)
                targets.set(id, (targets.get(id) ?? 0) + 1);
        }
        const available = new Map();
        const addAvailable = (id) => {
            if (this.getItemData(id))
                available.set(id, (available.get(id) ?? 0) + 1);
        };
        for (const item of this.getInventoryItems(state)) {
            if (!item.immovable)
                addAvailable(item.id);
            for (const stored of item.storage?.items ?? [])
                addAvailable(stored.id);
            const craft = item.craft;
            if (this.getItemData(item.id)?.type !== 2 || !craft)
                continue;
            if ([TableState.CRAFTING, TableState.READY].includes(craft._craft_state)) {
                addAvailable(Number(craft._craft_result_id || craft._craft_recipe?.result || 0));
            }
            else {
                for (const stored of craft._craft_stored ?? [])
                    addAvailable(Number(stored.id));
            }
        }
        for (const reward of state.pending_rewards) {
            if (reward.kind !== "card_pack")
                addAvailable(reward.id);
        }
        // Reserve existing order products before expanding recipes. Aggregate
        // ordinary demands so one inventory item cannot satisfy two orders.
        const ordinary = new Map();
        const expand = (id, count, visiting) => {
            if (count <= 0 || visiting.has(id))
                return;
            const item = this.getItemData(id);
            if (!item)
                return;
            const recipe = this.recipes.find(candidate => candidate.result === id);
            if (!recipe) {
                if (item.type === 0)
                    ordinary.set(id, (ordinary.get(id) ?? 0) + count);
                return;
            }
            const missing = this.consumeAvailableOrderItems(available, id, count);
            visiting.add(id);
            for (const ingredient of recipe.ingredients)
                expand(ingredient, missing, visiting);
            visiting.delete(id);
        };
        const remaining = new Map();
        for (const [id, count] of targets) {
            remaining.set(id, this.consumeAvailableOrderItems(available, id, count));
        }
        for (const [id, count] of remaining)
            expand(id, count, new Set());
        const deficits = new Set();
        const consumeMaterial = (id, count) => {
            const missing = this.consumeAvailableOrderItems(available, id, count);
            if (missing <= 0)
                return false;
            const item = this.getItemData(id);
            const previous = item.level > 1 ? this.getItemByLevel(0, item.level - 1, item.group_id) : null;
            if (previous && !this.recipes.some(recipe => recipe.result === previous.id)) {
                return consumeMaterial(previous.id, missing * 2);
            }
            return true;
        };
        const demands = [...ordinary].sort(([a], [b]) => this.getItemData(b).level - this.getItemData(a).level);
        for (const [id, count] of demands) {
            if (consumeMaterial(id, count))
                deficits.add(id);
        }
        // Keep the original missing requirement's level; recursive inventory checks
        // reach level one even when the actual order needs a higher-level material.
        return [...new Set([...ordinary.keys()].filter(id => deficits.has(id))
                .flatMap(id => this.getOrderSupplyMaterials(id, state.cultivation.current_level)))];
    }
    getCultivationConfig() {
        return this.cultivation;
    }
    getInitialSetup(boardType = 0) {
        return this.initialSetups.get(boardType) ?? [];
    }
    getMaxCharges(itemId) {
        return this.getItemData(itemId)?.max_charges ?? 3;
    }
    getCultivationStaminaMultiplierCap(state) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return 1;
        const currentLevel = Math.max(1, Number(state.cultivation?.current_level ?? 1));
        const realmCaps = [
            { realm: "元婴", cap: 32 },
            { realm: "金丹", cap: 16 },
            { realm: "筑基", cap: 8 },
        ];
        for (const { realm, cap } of realmCaps) {
            const realmStart = this.cultivationStages.findIndex(stage => stage.name.startsWith(realm));
            if (realmStart >= 0 && currentLevel >= realmStart + 1)
                return cap;
        }
        return 4;
    }
    getStaminaMultiplierState(state, now = Date.now()) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return { maxMultiplier: 1, expiresAt: 0, remainingSeconds: 0 };
        const expiresAt = Math.max(0, Number(state.stamina_multiplier_expires_at ?? 0));
        const configuredMax = Math.max(1, Number(state.stamina_multiplier_max ?? 1));
        const isActive = expiresAt > now && this.isPowerOfTwo(configuredMax);
        const realmCap = this.getCultivationStaminaMultiplierCap(state);
        return {
            maxMultiplier: isActive ? Math.min(configuredMax, realmCap) : 1,
            expiresAt: isActive ? expiresAt : 0,
            remainingSeconds: isActive ? Math.max(0, Math.ceil((expiresAt - now) / 1000)) : 0,
        };
    }
    tickStaminaMultiplier(state, now = Date.now()) {
        const current = this.getStaminaMultiplierState(state, now);
        if (current.maxMultiplier > 1) {
            const changed = Number(state.stamina_multiplier_max ?? 1) !== current.maxMultiplier;
            state.stamina_multiplier_max = current.maxMultiplier;
            return changed;
        }
        const changed = Number(state.stamina_multiplier_max ?? 1) !== 1
            || Number(state.stamina_multiplier_expires_at ?? 0) !== 0;
        state.stamina_multiplier_max = 1;
        state.stamina_multiplier_expires_at = 0;
        return changed;
    }
    addStamina(state, amount, now = Date.now()) {
        if (!Number.isFinite(amount) || amount <= 0)
            return this.getStaminaMultiplierState(state, now);
        state.stamina += amount;
        return this.refreshStaminaMultiplierFromBalance(state, now);
    }
    refreshStaminaMultiplierFromBalance(state, now = Date.now()) {
        if (!(0, activity_access_1.activitiesUnlocked)(state)) {
            this.tickStaminaMultiplier(state, now);
            return this.getStaminaMultiplierState(state, now);
        }
        const triggered = Math.min(this.getTriggeredStaminaMultiplier(state.stamina), this.getCultivationStaminaMultiplierCap(state));
        if (triggered > 1) {
            const active = this.getStaminaMultiplierState(state, now);
            state.stamina_multiplier_max = Math.max(active.maxMultiplier, triggered);
            state.stamina_multiplier_expires_at = now + this.staminaConfig.multiplierDuration * 1000;
        }
        return this.getStaminaMultiplierState(state, now);
    }
    getLauncherSafeStaminaMultiplier(launcherId) {
        const launcher = this.getItemData(launcherId);
        if (!launcher || !this.isLauncher(launcher))
            return 1;
        const outputIds = [
            ...(launcher.spawns ?? []).map(spawn => spawn.id),
            ...(launcher.fixed_spawns ?? []),
        ];
        if (outputIds.length === 0)
            return 1;
        let safeSteps = Number.MAX_SAFE_INTEGER;
        for (const outputId of outputIds) {
            const output = this.getItemData(outputId);
            if (!output)
                return 1;
            let steps = 0;
            while (this.getItemByLevel(output.type, output.level + steps + 1, output.group_id))
                steps += 1;
            safeSteps = Math.min(safeSteps, steps);
        }
        return 2 ** Math.min(30, Math.max(0, safeSteps));
    }
    getTriggeredStaminaMultiplier(stamina) {
        let multiplier = 1;
        while (multiplier < 2 ** 30) {
            const next = multiplier * 2;
            if (stamina < this.staminaConfig.multiplierThresholdBase * next)
                break;
            multiplier = next;
        }
        return multiplier;
    }
    isPowerOfTwo(value) {
        return Number.isInteger(value) && value >= 1 && Math.log2(value) % 1 === 0;
    }
    upgradeSpawnResult(base, multiplier) {
        const levelGain = Math.log2(multiplier);
        if (!Number.isInteger(levelGain) || levelGain < 0)
            return null;
        return this.getItemByLevel(base.type, base.level + levelGain, base.group_id);
    }
    getOutstandingOrderItemCounts(state) {
        const orderTargets = new Map();
        for (const order of state.meridian_acupoints ?? []) {
            if (order?.completed === true)
                continue;
            const configuredIds = order.item_ids;
            for (const entry of configuredIds) {
                const itemId = entry;
                const count = 1;
                if (!Number.isSafeInteger(itemId) || !Number.isSafeInteger(count) || count <= 0)
                    continue;
                if (itemId > 0)
                    orderTargets.set(itemId, (orderTargets.get(itemId) ?? 0) + count);
            }
        }
        const available = new Map();
        const requiredRecipeIds = new Set();
        const visitedProducts = new Set();
        const collectRecipes = (itemId) => {
            if (visitedProducts.has(itemId))
                return;
            visitedProducts.add(itemId);
            for (const recipe of this.recipes.filter(recipe => recipe.result === itemId)) {
                requiredRecipeIds.add(recipe.id);
                for (const ingredientId of recipe.ingredients)
                    collectRecipes(ingredientId);
            }
        };
        for (const itemId of orderTargets.keys())
            collectRecipes(itemId);
        const addAvailable = (itemId) => {
            if (itemId > 0)
                available.set(itemId, (available.get(itemId) ?? 0) + 1);
        };
        for (const gridItem of this.getInventoryItems(state)) {
            const itemDef = this.getItemData(gridItem.id);
            if (itemDef?.type !== 2) {
                if (gridItem.immovable !== true)
                    addAvailable(gridItem.id);
                continue;
            }
            if (this.tableSupportsOrderMaterials(gridItem, requiredRecipeIds)) {
                for (const stored of gridItem.craft?._craft_stored ?? []) {
                    addAvailable(Number(stored?.id ?? 0));
                }
            }
            const craftState = gridItem.craft?._craft_state;
            if (craftState !== TableState.CRAFTING && craftState !== TableState.READY)
                continue;
            addAvailable(Number(gridItem.craft?._craft_result_id
                || gridItem.craft?._craft_recipe?.result
                || 0));
        }
        const outstanding = new Map();
        for (const [itemId, requiredCount] of orderTargets) {
            this.addRecipeMaterialRequirements(itemId, requiredCount, outstanding, available, new Set());
        }
        return outstanding;
    }
    tableSupportsOrderMaterials(table, requiredRecipeIds) {
        const storedCounts = new Map();
        for (const stored of table.craft?._craft_stored ?? []) {
            storedCounts.set(stored.id, (storedCounts.get(stored.id) ?? 0) + 1);
        }
        const state = table.craft?._craft_state;
        const activeRecipe = table.craft?._craft_recipe;
        return this.getRecipesForTable(table.id).some(recipe => {
            if (!requiredRecipeIds.has(recipe.id))
                return false;
            if ((state === TableState.CRAFTING || state === TableState.READY)
                && (activeRecipe?.id ? activeRecipe.id !== recipe.id : activeRecipe?.result !== recipe.result)) {
                return false;
            }
            const ingredientCounts = new Map();
            for (const id of recipe.ingredients)
                ingredientCounts.set(id, (ingredientCounts.get(id) ?? 0) + 1);
            return [...storedCounts].every(([id, count]) => count <= (ingredientCounts.get(id) ?? 0));
        });
    }
    consumeAvailableOrderItems(available, itemId, count) {
        const consumed = Math.min(count, available.get(itemId) ?? 0);
        if (consumed <= 0)
            return count;
        const left = (available.get(itemId) ?? 0) - consumed;
        if (left > 0)
            available.set(itemId, left);
        else
            available.delete(itemId);
        return count - consumed;
    }
    addRecipeMaterialRequirements(itemId, count, requirements, available, visiting) {
        if (itemId <= 0 || count <= 0)
            return;
        const missingCount = this.consumeAvailableOrderItems(available, itemId, count);
        if (missingCount <= 0)
            return;
        const recipe = this.recipes.find(candidate => candidate.result === itemId);
        if (!recipe || visiting.has(itemId)) {
            requirements.set(itemId, (requirements.get(itemId) ?? 0) + missingCount);
            return;
        }
        visiting.add(itemId);
        for (const ingredientId of recipe.ingredients) {
            this.addRecipeMaterialRequirements(ingredientId, missingCount, requirements, available, visiting);
        }
        visiting.delete(itemId);
    }
    getOrderPrioritySpawnPlan(state, base, boosted, requestedMultiplier, maxStaminaUnits, launcherData) {
        if (requestedMultiplier <= 1 || boosted.level <= base.level) {
            return {
                output: { item: boosted, staminaUnits: requestedMultiplier },
                orderPriority: false,
            };
        }
        const spawnSources = this.getLauncherSpawnSources(launcherData);
        const candidates = [];
        for (const [itemId, count] of this.getOutstandingOrderItemCounts(state)) {
            if (count <= 0)
                continue;
            const candidate = this.getItemData(itemId);
            if (!candidate)
                continue;
            const staminaUnits = this.getOrderCandidateMultiplier(candidate, base, boosted.level, requestedMultiplier, spawnSources);
            if (staminaUnits > 0) {
                candidates.push({
                    item: candidate,
                    count,
                    staminaUnits,
                });
            }
        }
        candidates.sort((a, b) => a.item.level - b.item.level || a.item.id - b.item.id);
        for (const candidate of candidates) {
            if (candidate.staminaUnits <= Math.min(requestedMultiplier, Math.max(0, maxStaminaUnits))) {
                return {
                    output: { item: candidate.item, staminaUnits: candidate.staminaUnits },
                    orderPriority: true,
                };
            }
        }
        return {
            output: { item: boosted, staminaUnits: requestedMultiplier },
            orderPriority: false,
        };
    }
    getLauncherSpawnSources(launcherData) {
        if (!launcherData)
            return [];
        const sourceIds = [
            ...(launcherData.spawns ?? []).map(spawn => spawn.id),
            ...(launcherData.fixed_spawns ?? []),
        ];
        return sourceIds
            .map(id => this.getItemData(id))
            .filter((item) => Boolean(item));
    }
    getOrderCandidateMultiplier(candidate, base, boostedLevel, requestedMultiplier, spawnSources) {
        if (spawnSources.length > 0) {
            let bestMultiplier = 0;
            for (const source of spawnSources) {
                if (source.type !== candidate.type || source.group_id !== candidate.group_id)
                    continue;
                let candidateMultiplier = 0;
                if (candidate.id === source.id) {
                    candidateMultiplier = 1;
                }
                else if (candidate.level > source.level) {
                    candidateMultiplier = 2 ** (candidate.level - source.level);
                    if (candidateMultiplier > requestedMultiplier)
                        continue;
                    if (this.upgradeSpawnResult(source, candidateMultiplier)?.id !== candidate.id)
                        continue;
                }
                if (candidateMultiplier > 0
                    && (bestMultiplier === 0 || candidateMultiplier < bestMultiplier)) {
                    bestMultiplier = candidateMultiplier;
                }
            }
            if (bestMultiplier > 0 && bestMultiplier < requestedMultiplier)
                return bestMultiplier;
            // Preserve the historical same-chain fallback for launchers whose
            // runtime table only exposes a higher-level roll (for example a
            // breakthrough book launcher). Cross-group candidates still require an
            // explicit source in the launcher table.
            if (candidate.type === base.type
                && candidate.group_id === base.group_id
                && candidate.level < boostedLevel) {
                return candidate.level <= base.level
                    ? 1
                    : 2 ** (candidate.level - base.level);
            }
            return 0;
        }
        if (candidate.type !== base.type
            || candidate.group_id !== base.group_id
            || candidate.level >= boostedLevel)
            return 0;
        const reachable = this.getItemByLevel(base.type, candidate.level, base.group_id);
        if (reachable?.id !== candidate.id)
            return 0;
        return candidate.level <= base.level
            ? 1
            : 2 ** (candidate.level - base.level);
    }
    _nextUid(state) {
        state.uid_counter = state.uid_counter + 1;
        return state.uid_counter;
    }
    getRechargeTime(itemId) {
        return this.getItemData(itemId)?.recharge_time ?? 60;
    }
    // --- Grid helpers ---
    isInBounds(col, row) {
        return col >= 0 && col < this.GRID_COLS && row >= 0 && row < this.GRID_ROWS;
    }
    // Settle elapsed time on the server, including time while the client was closed.
    // Return whether the recovered balance/anchor needs to be persisted.
    tickStamina(state, now = Date.now()) {
        if (state.stamina >= this.staminaConfig.max) {
            state.last_stamina_tick = now;
            return false;
        }
        const intervalMs = this.staminaConfig.regenInterval * 1000;
        if (!Number.isFinite(state.last_stamina_tick) || state.last_stamina_tick > now) {
            state.last_stamina_tick = now;
            return true;
        }
        if (intervalMs <= 0 || this.staminaConfig.regenAmount <= 0)
            return false;
        const ticks = Math.floor((now - state.last_stamina_tick) / intervalMs);
        if (ticks <= 0)
            return false;
        const amount = Math.min(this.staminaConfig.max - state.stamina, ticks * this.staminaConfig.regenAmount);
        this.addStamina(state, amount, now);
        // Keep the partial interval below cap; time spent at cap cannot be banked.
        state.last_stamina_tick = state.stamina >= this.staminaConfig.max
            ? now : state.last_stamina_tick + ticks * intervalMs;
        return true;
    }
    getRegenRemainingMs(state, now = Date.now()) {
        if (state.stamina >= this.staminaConfig.max)
            return 0;
        const nextTick = state.last_stamina_tick + this.staminaConfig.regenInterval * 1000;
        return Math.max(0, nextTick - now);
    }
    isLauncher(itemDef) {
        if (!itemDef)
            return false;
        const spawns = itemDef.spawns;
        const maxCharges = itemDef.max_charges ?? 0;
        return (spawns && spawns.length > 0) || maxCharges > 0;
    }
    enrichGridWithRechargeRemaining(grid) {
        const now = Date.now();
        for (const item of grid) {
            const itemDef = this.getItemData(item.id);
            if (!this.isLauncher(itemDef))
                continue;
            delete item._recharge_remaining;
            const rt = itemDef.recharge_time ?? 0;
            if (rt <= 0)
                continue;
            const maxC = itemDef.max_charges ?? 3;
            const charges = item.charges ?? maxC;
            if (charges >= maxC)
                continue;
            const lct = item.last_charge_time ?? now;
            const elapsed = (now - lct) / 1000;
            if (elapsed < rt) {
                item._recharge_remaining = (rt - elapsed) * 1000;
            }
        }
    }
    tickLauncherRecharge(state) {
        const now = Date.now();
        for (const item of this.getInventoryItems(state)) {
            const itemDef = this.getItemData(item.id);
            if (!this.isLauncher(itemDef))
                continue;
            const rechargeTime = itemDef.recharge_time ?? 0;
            if (rechargeTime <= 0)
                continue;
            const maxC = itemDef.max_charges ?? 3;
            const charges = item.charges ?? maxC;
            if (charges >= maxC)
                continue;
            const lastTime = item.last_charge_time ?? now;
            const elapsed = (now - lastTime) / 1000;
            if (elapsed < rechargeTime)
                continue;
            item.charges = maxC;
            item.last_charge_time = now;
            console.log(`[engine] launcher recharge: #${item.id} at (${item.col},${item.row}) 0->${maxC} (rechargeTime=${rechargeTime}s)`);
        }
    }
    posKey(col, row) {
        return `${col},${row}`;
    }
    getNeighbors(col, row) {
        const result = [];
        const candidates = [
            [col + 1, row],
            [col - 1, row],
            [col, row + 1],
            [col, row - 1],
        ];
        for (const [c, r] of candidates) {
            if (this.isInBounds(c, r))
                result.push([c, r]);
        }
        return result;
    }
    findNearestEmpty(grid, startCol, startRow) {
        return (0, grid_search_1.findNearestEmptyCell)(this.GRID_COLS, this.GRID_ROWS, startCol, startRow, (col, row) => !grid.has(this.posKey(col, row)));
    }
    findEmptyPos(grid) {
        const occupied = new Set();
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
    findEmptyByRow(grid) {
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
    applyRewards(state, rewards) {
        const result = { tokens: [], items: [] };
        let expChanged = false;
        // Resolve reward ID to config
        if (typeof rewards === "number") {
            const resolved = this.rewardsTable.get(rewards);
            if (!resolved) {
                console.log(`[reward] unknown reward id: ${rewards}`);
                return result;
            }
            rewards = resolved;
        }
        // Activity currencies and card packs are disabled during the novice period.
        if (!(0, activity_access_1.activitiesUnlocked)(state)) {
            const activityTokens = new Set(this.battlePassService.getDefinitions().map(pass => pass.points_token_id));
            rewards = {
                tokens: (rewards.tokens ?? []).filter(t => !activityTokens.has(t.token)),
                items: (rewards.items ?? []).filter(ri => {
                    const item = this.getItemData(ri.id);
                    return !(item?.type === 5 && item.effect_type === card_collection_1.CardCollectionService.EFFECT_TYPE);
                }),
            };
        }
        // Validate configured pack counts before crediting any part of the reward.
        for (const ri of rewards.items ?? []) {
            const item = this.getItemData(ri.id);
            if (item?.type === 5 && item.effect_type === card_collection_1.CardCollectionService.EFFECT_TYPE && (!Number.isSafeInteger(ri.count) || ri.count < 0)) {
                throw new Error(`card_collection: invalid reward count for item ${ri.id}`);
            }
            if (item?.type === 5 && item.effect_type === card_collection_1.CardCollectionService.EFFECT_TYPE && !this.cardCollectionService.config.packs.some(pack => pack.pack_id === item.effect_value)) {
                throw new Error(`card_collection: unknown pack ${item.effect_value} for item ${ri.id}`);
            }
        }
        // Token rewards — directly credited
        if (rewards.tokens) {
            for (const t of rewards.tokens) {
                switch (t.token) {
                    case interface_1.TokenType.SPIRIT_STONES:
                        state.spirit_stones += t.amount;
                        console.log(`[reward] +${t.amount} spirit_stones (total: ${state.spirit_stones})`);
                        break;
                    case interface_1.TokenType.QI:
                        state.cultivation.current_qi += t.amount;
                        console.log(`[reward] +${t.amount} qi (total: ${state.cultivation.current_qi}/${state.cultivation.max_qi})`);
                        break;
                    case interface_1.TokenType.STAMINA:
                        this.addStamina(state, t.amount);
                        console.log(`[reward] +${t.amount} stamina (total: ${state.stamina})`);
                        break;
                    case interface_1.TokenType.EXP:
                        this._addExp(state.cultivation, t.amount);
                        expChanged = true;
                        console.log(`[reward] +${t.amount} exp (total: ${state.cultivation.current_exp})`);
                        break;
                    default:
                        console.log(`[reward] unknown token type: ${t.token}`);
                }
                result.tokens.push({ token: t.token, amount: t.amount });
            }
        }
        // Item rewards -> pending_rewards
        if (rewards.items) {
            for (const ri of rewards.items) {
                const itemData = this.getItemData(ri.id);
                const name = itemData?.name ?? `#${ri.id}`;
                if (itemData?.type === 5 && itemData.effect_type === card_collection_1.CardCollectionService.EFFECT_TYPE) {
                    if (ri.count > 0)
                        this.cardCollectionService.awardPack(state, itemData.effect_value, ri.count);
                    result.items.push({ id: ri.id, count: ri.count });
                    continue;
                }
                this.registerProductionUnlock(state, ri.id);
                if (ri.count > 0)
                    this.recordItemDiscovery(state, ri.id);
                for (let i = 0; i < ri.count; i++) {
                    state.pending_rewards.push({
                        uid: this._nextUid(state),
                        id: ri.id,
                        name,
                    });
                }
                result.items.push({ id: ri.id, count: ri.count });
                console.log(`[reward] +${ri.count}x ${name} -> pending_rewards`);
            }
        }
        if (expChanged) {
            this.syncBreakthroughOrder(state);
        }
        return result;
    }
    // --- State initialization ---
    createInitialState(boardType = 0) {
        const now = Date.now();
        const state = {
            storage_revision: 0,
            grid: [],
            pouch: [],
            pouch_capacity: this.pouchConfig.initialSlots,
            pouch_unlock_count: 0,
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
            stamina_multiplier_max: 1,
            stamina_multiplier_expires_at: 0,
            spirit_stones: 0,
            version: 0,
            board_type: boardType,
            uid_counter: 0,
            pending_rewards: [],
            battle_pass_progress: {},
            spawn_seed: this.createSpawnSeed(),
            spawn_sequence: 0,
            spawn_history: [],
            item_catalog_claimed_ids: [],
            crafted_item_ids: [],
            unlocked_production_item_ids: [],
        };
        const setup = this.getInitialSetup(boardType);
        const itemNames = [];
        for (const entry of setup) {
            const itemDef = this.getItemData(entry.id);
            if (itemDef) {
                state.uid_counter = state.uid_counter + 1;
                const gitem = { uid: state.uid_counter, id: entry.id, col: entry.col, row: entry.row };
                if (entry.immovable)
                    gitem.immovable = true;
                if (this.isLauncher(itemDef)) {
                    gitem.charges = this.getMaxCharges(entry.id);
                    gitem.last_charge_time = now;
                }
                state.grid.push(gitem);
                this.registerProductionUnlock(state, entry.id);
                this.recordItemDiscovery(state, entry.id);
                itemNames.push(`${itemDef.name}(#${entry.id})@(${entry.col},${entry.row})${gitem.immovable ? " [immovable]" : ""}`);
            }
        }
        console.log(`[engine] createInitialState(${boardType}): ${state.grid.length} items — ${itemNames.join(", ")}`);
        return state;
    }
    createSpawnSeed() {
        return Math.floor(Math.random() * 0xffffffff) + 1;
    }
    switchBoard(state, boardType, battleMapId, battleStage) {
        if (boardType === state.board_type) {
            state.version += 1;
            return { ok: true, newVersion: state.version };
        }
        if (boardType === 1) {
            if (battleMapId !== undefined)
                state.battle_map_id = battleMapId;
            if (battleStage !== undefined)
                state.battle_stage = battleStage;
            state.saved_grid = state.grid;
            if (state.battle_grid) {
                state.grid = state.battle_grid;
                state.battle_grid = undefined;
                console.log(`[engine] board switched to battle: restored ${state.grid.length} battle items, saved ${state.saved_grid.length} main items | v${state.version}`);
            }
            else {
                state.grid = this._buildInitialGrid(1, state);
                console.log(`[engine] board switched to battle: new battle grid ${state.grid.length} items, saved ${state.saved_grid.length} main items | v${state.version}`);
            }
            state.board_type = 1;
        }
        else {
            state.battle_grid = state.grid;
            state.grid = state.saved_grid
                ? state.saved_grid
                : this._buildInitialGrid(0, state);
            state.saved_grid = undefined;
            state.board_type = 0;
            console.log(`[engine] board switched to main: restored ${state.grid.length} main items, saved ${state.battle_grid.length} battle items | v${state.version}`);
        }
        state.version += 1;
        return { ok: true, newVersion: state.version };
    }
    _buildInitialGrid(boardType, state) {
        const setup = this.getInitialSetup(boardType);
        const now = Date.now();
        const grid = [];
        for (const entry of setup) {
            const itemDef = this.getItemData(entry.id);
            if (itemDef) {
                state.uid_counter = state.uid_counter + 1;
                const gitem = { uid: state.uid_counter, id: entry.id, col: entry.col, row: entry.row };
                if (entry.immovable)
                    gitem.immovable = true;
                if (this.isLauncher(itemDef)) {
                    gitem.charges = this.getMaxCharges(entry.id);
                    gitem.last_charge_time = now;
                }
                grid.push(gitem);
                this.registerProductionUnlock(state, entry.id);
                this.recordItemDiscovery(state, entry.id);
            }
        }
        return grid;
    }
    // --- Grid helpers ---
    buildGridMap(grid) {
        const map = new Map();
        for (const item of grid) {
            map.set(this.posKey(item.col, item.row), item);
        }
        return map;
    }
    gridToMap(grid) {
        return this.buildGridMap(grid);
    }
    countItems(grid) {
        return grid.length;
    }
    isGridFull(grid) {
        return grid.length >= this.MAX_CELLS;
    }
    // --- Merge validation & execution ---
    validateMerge(state, fromCol, fromRow, toCol, toRow) {
        const map = this.gridToMap(state.grid);
        const fromKey = this.posKey(fromCol, fromRow);
        const toKey = this.posKey(toCol, toRow);
        let itemA;
        let itemB;
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
            itemA = state.grid.find((g) => g.id === itemB.id && this.posKey(g.col, g.row) !== toKey);
        }
        if (!itemB && itemA) {
            itemB = state.grid.find((g) => g.id === itemA.id && this.posKey(g.col, g.row) !== fromKey);
        }
        if (!itemA)
            return { valid: false, reason: "source_item_not_found" };
        if (!itemB)
            return { valid: false, reason: "target_item_not_found" };
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
        const hasCraftMaterials = (item, itemDef) => itemDef.type === 2 && (item.craft?._craft_stored?.length ?? 0) > 0;
        if (hasCraftMaterials(itemA, dataA) || hasCraftMaterials(itemB, dataB)) {
            console.log(`[engine] merge rejected: crafting table contains materials | from=(${itemA.col},${itemA.row}) to=(${itemB.col},${itemB.row})`);
            return { valid: false, reason: "craft_table_has_materials" };
        }
        return {
            valid: true,
            resultItem: nextItem,
            fromItem: itemA,
            toItem: itemB,
        };
    }
    executeMerge(state, fromCol, fromRow, toCol, toRow) {
        const result = this.validateMerge(state, fromCol, fromRow, toCol, toRow);
        if (!result.valid) {
            console.log(`[engine] merge rejected: ${result.reason} | from=(${fromCol},${fromRow}) to=(${toCol},${toRow})`);
            return { ok: false, reason: result.reason };
        }
        const supplyAvailableBefore = this.countOrderSupplyAvailableItems(state, result.resultItem.id);
        const rewindBefore = this.goldenFingerService.snapshot(state);
        const actualFromKey = this.posKey(result.fromItem.col, result.fromItem.row);
        const actualToKey = this.posKey(result.toItem.col, result.toItem.row);
        const fromId = result.fromItem.id;
        // Remove both items using their actual positions from the server's grid
        state.grid = state.grid.filter((item) => this.posKey(item.col, item.row) !== actualFromKey &&
            this.posKey(item.col, item.row) !== actualToKey);
        // Add merged item at the target position (where itemB was)
        const mergedItem = { uid: this._nextUid(state), id: result.resultItem.id, col: result.toItem.col, row: result.toItem.row };
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
        this.registerProductionUnlock(state, mergedItem.id);
        this.recordItemDiscovery(state, mergedItem.id);
        state.version += 1;
        const mergedName = result.resultItem.name;
        const fromItem = this.getItemData(fromId);
        const fromName = fromItem?.name ?? `#${fromId}`;
        console.log(`[engine] merge: ${fromName}x2 -> ${mergedName} | grid=${state.grid.length}/63 | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.MERGE, 1, this);
        this.activityEngine.recordOrderSupplyAction(state, mergedItem.id, supplyAvailableBefore);
        this.goldenFingerService.capture(state, rewindBefore, "合并");
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
    executeSpawn(state, launcherCol, launcherRow, expectedSequence, requestedMultiplier = 1) {
        const sequence = state.spawn_sequence;
        const rewindBefore = this.goldenFingerService.snapshot(state);
        if (expectedSequence !== undefined && expectedSequence !== sequence) {
            return { ok: false, reason: "spawn_sequence_mismatch" };
        }
        const map = this.gridToMap(state.grid);
        const launcherKey = this.posKey(launcherCol, launcherRow);
        const launcherItem = map.get(launcherKey);
        if (!launcherItem)
            return { ok: false, reason: "launcher_not_found" };
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
        const isBattle = state.board_type === 1;
        if (!this.isPowerOfTwo(requestedMultiplier)) {
            return { ok: false, reason: "invalid_stamina_multiplier" };
        }
        if ((isBattle || launcherData.no_cost) && requestedMultiplier !== 1) {
            return { ok: false, reason: "stamina_multiplier_not_applicable" };
        }
        if (!isBattle && !launcherData.no_cost) {
            const boost = this.getStaminaMultiplierState(state);
            if (requestedMultiplier > boost.maxMultiplier) {
                return { ok: false, reason: "stamina_multiplier_not_active" };
            }
            if (requestedMultiplier > this.getLauncherSafeStaminaMultiplier(launcherItem.id)) {
                return { ok: false, reason: "stamina_multiplier_above_launcher_cap" };
            }
        }
        // Determine rolled ID: fixed spawns or random weighted
        let rolledId;
        const fixedSpawns = launcherData.fixed_spawns;
        if (fixedSpawns && fixedSpawns.length > 0) {
            const usedCount = maxC - charges; // times already used
            if (usedCount >= fixedSpawns.length) {
                return { ok: false, reason: "no_more_fixed_spawns" };
            }
            rolledId = fixedSpawns[usedCount];
        }
        else {
            const spawns = launcherData.spawns;
            if (!spawns || !spawns.length)
                return { ok: false, reason: "no_spawns" };
            const totalWeight = spawns.reduce((sum, s) => sum + s.weight, 0);
            let roll = (0, spawn_rng_1.deterministicSpawnRoll)(state.spawn_seed, sequence, launcherItem.uid ?? 0, totalWeight);
            rolledId = spawns[0].id;
            for (const s of spawns) {
                if (roll < s.weight) {
                    rolledId = s.id;
                    break;
                }
                roll -= s.weight;
            }
        }
        const baseSpawnResult = this.getItemData(rolledId);
        if (!baseSpawnResult)
            return { ok: false, reason: "spawn_failed" };
        const boostedSpawnResult = this.upgradeSpawnResult(baseSpawnResult, requestedMultiplier);
        if (!boostedSpawnResult)
            return { ok: false, reason: "stamina_multiplier_above_output_cap" };
        const baseStaminaCost = this.staminaConfig.spawnCost;
        const maxStaminaUnits = !isBattle && !launcherData.no_cost
            ? Math.floor(state.stamina / baseStaminaCost)
            : requestedMultiplier;
        const spawnPlan = this.getOrderPrioritySpawnPlan(state, baseSpawnResult, boostedSpawnResult, requestedMultiplier, maxStaminaUnits, launcherData);
        const target = this.findNearestEmpty(map, launcherCol, launcherRow);
        if (!target)
            return { ok: false, reason: "no_empty_cell" };
        const spentStaminaUnits = spawnPlan.output.staminaUnits;
        // Cost check: order-priority output charges only its represented multiplier.
        const requestedStaminaCost = !isBattle && !launcherData.no_cost
            ? this.staminaConfig.spawnCost * requestedMultiplier
            : 0;
        const staminaCost = !isBattle && !launcherData.no_cost
            ? baseStaminaCost * spentStaminaUnits
            : 0;
        const staminaRefund = requestedStaminaCost - staminaCost;
        if (!launcherData.no_cost) {
            if (isBattle) {
                if (state.cultivation.current_qi < 1) {
                    return { ok: false, reason: "insufficient_qi" };
                }
            }
            else {
                if (state.stamina < staminaCost) {
                    return { ok: false, reason: "insufficient_stamina" };
                }
            }
        }
        // Deduct cost (skip for no_cost launchers)
        if (!launcherData.no_cost) {
            if (isBattle) {
                state.cultivation.current_qi = Math.max(0, state.cultivation.current_qi - 1);
            }
            else {
                state.stamina = Math.max(0, state.stamina - staminaCost);
            }
        }
        launcherItem.charges = charges - 1;
        launcherItem.last_charge_time = Date.now();
        // Remove launcher if charges depleted and no recharge
        if (launcherItem.charges <= 0 && (launcherData.recharge_time ?? -1) <= 0) {
            state.grid = state.grid.filter((g) => !(g.col === launcherCol && g.row === launcherRow));
            console.log(`[engine] launcher #${launcherItem.id} at (${launcherCol},${launcherRow}) depleted and removed`);
        }
        const spawnResult = spawnPlan.output.item;
        const newItem = {
            uid: this._nextUid(state),
            id: spawnResult.id,
            col: target.col,
            row: target.row,
        };
        if (spawnResult.type === 1 || this.isLauncher(spawnResult)) {
            newItem.charges = this.getMaxCharges(spawnResult.id);
            newItem.last_charge_time = Date.now();
        }
        if (launcherData.effect_type === 7) {
            const stage = this.cultivationStages[state.cultivation.current_level - 1];
            const stageAtk = stage?.atk ?? 0;
            newItem.atk_base = stageAtk + (launcherData.value ?? 0);
        }
        const supplyAvailableBefore = this.countOrderSupplyAvailableItems(state, newItem.id);
        state.grid.push(newItem);
        this.registerProductionUnlock(state, newItem.id);
        this.recordItemDiscovery(state, newItem.id);
        const spawnedItems = [{
                uid: newItem.uid ?? 0,
                id: spawnResult.id,
                name: spawnResult.name,
                targetCol: target.col,
                targetRow: target.row,
                atkBase: newItem.atk_base ?? 0,
                staminaUnits: spawnPlan.output.staminaUnits,
            }];
        state.spawn_sequence = sequence + 1;
        state.version += 1;
        const firstSpawn = spawnedItems[0];
        console.log(`[engine] spawn: launcher #${launcherItem.id} -> ${spawnedItems.map(item => `${item.name}(#${item.id})`).join(", ")} | units=${spentStaminaUnits}/${requestedMultiplier} refund=${staminaRefund} order_priority=${spawnPlan.orderPriority} | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.SPAWN, spawnedItems.length, this);
        this.activityEngine.recordOrderSupplyAction(state, newItem.id, supplyAvailableBefore);
        this.goldenFingerService.capture(state, rewindBefore, "生成");
        return {
            ok: true,
            spawnedUid: firstSpawn.uid,
            spawnedId: firstSpawn.id,
            spawnedName: firstSpawn.name,
            targetCol: firstSpawn.targetCol,
            targetRow: firstSpawn.targetRow,
            newVersion: state.version,
            charges: launcherItem.charges,
            maxCharges: this.getMaxCharges(launcherItem.id),
            rechargeTime: launcherData.recharge_time ?? 0,
            atkBase: firstSpawn.atkBase,
            sequenceUsed: sequence,
            spawnSequence: state.spawn_sequence,
            staminaMultiplier: spentStaminaUnits,
            requestedStaminaMultiplier: requestedMultiplier,
            staminaCost,
            staminaRefund,
            orderPriority: spawnPlan.orderPriority,
            spawnedItems,
        };
    }
    // --- Move item (for pushing items around) ---
    executeMove(state, fromCol, fromRow, toCol, toRow) {
        const fromKey = this.posKey(fromCol, fromRow);
        const toKey = this.posKey(toCol, toRow);
        if (fromCol === toCol && fromRow === toRow) {
            return { ok: false, reason: "same_position" };
        }
        const existsAtTarget = state.grid.some((item) => this.posKey(item.col, item.row) === toKey);
        if (existsAtTarget) {
            return { ok: false, reason: "target_occupied" };
        }
        const targetItem = state.grid.find((item) => this.posKey(item.col, item.row) === fromKey);
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
    removeIngredientFromTable(state, tableCol, tableRow, ingredientId, targetCol, targetRow) {
        const tableItem = state.grid.find((item) => item.col === tableCol && item.row === tableRow);
        if (!tableItem?.craft)
            return { ok: false, reason: "table_not_found" };
        const craft = tableItem.craft;
        if (craft._craft_state === TableState.CRAFTING || craft._craft_state === TableState.READY) {
            return { ok: false, reason: "busy" };
        }
        const stored = craft._craft_stored;
        const idx = stored.findIndex((s) => s.id === ingredientId);
        if (idx < 0)
            return { ok: false, reason: "ingredient_not_in_table" };
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
        craft._craft_recipe = matched ?? {};
        if (craft._craft_stored.length === 0) {
            // Removing the last ingredient leaves an empty table. Keep the state
            // consistent with the stored materials so clients do not render the
            // HAS_ITEMS badge after the authoritative sync.
            craft._craft_state = TableState.IDLE;
            craft._craft_recipe = {};
        }
        else {
            craft._craft_state = TableState.HAS_ITEMS;
        }
        return { ok: true, removed_id: ingredientId, removed_uid: newUid, table_col: tableCol, table_row: tableRow, target_col: targetCol, target_row: targetRow, newVersion: state.version };
    }
    // --- Crafting ---
    validateCraftStart(state, tableCol, tableRow) {
        let tableItem = state.grid.find((item) => item.col === tableCol && item.row === tableRow);
        // If not at the expected position, search whole grid for a table with craft data
        if (!tableItem) {
            tableItem = state.grid.find((item) => item.craft && item.craft._craft_state === TableState.HAS_ITEMS) ?? undefined;
        }
        if (!tableItem) {
            console.log(`[engine] craft start rejected: table_not_found at (${tableCol},${tableRow}), grid has ${state.grid.length} items, tables with craft: ${state.grid.filter(i => i.craft).length}`);
            return { valid: false, reason: "table_not_found" };
        }
        const craft = tableItem.craft;
        if (!craft)
            return { valid: false, reason: "no_ingredients" };
        if (craft._craft_state === TableState.CRAFTING) {
            return { valid: false, reason: "already_crafting" };
        }
        if (craft._craft_state === TableState.READY) {
            return { valid: false, reason: "result_ready_retrieve_first" };
        }
        const recipe = craft._craft_recipe;
        if (!recipe || !recipe.id)
            return { valid: false, reason: "no_matching_recipe" };
        return { valid: true, recipe };
    }
    executeCraftStart(state, tableCol, tableRow) {
        const validation = this.validateCraftStart(state, tableCol, tableRow);
        if (!validation.valid)
            return { ok: false, reason: validation.reason };
        // Use the table found by validateCraftStart (may be at different position via fallback)
        let tableItem = state.grid.find((item) => item.col === tableCol && item.row === tableRow);
        if (!tableItem) {
            tableItem = state.grid.find((item) => item.craft && item.craft._craft_state === TableState.HAS_ITEMS);
        }
        if (!tableItem?.craft)
            return { ok: false, reason: "table_not_found" };
        const craft = tableItem.craft;
        const supplyAvailableBefore = this.countOrderSupplyAvailableItems(state, validation.recipe.result);
        craft._craft_state = TableState.CRAFTING;
        craft._craft_progress = 0;
        craft._craft_stored = [];
        craft._craft_result_id = validation.recipe.result;
        craft._craft_start_time = Date.now();
        state.version += 1;
        this.activityEngine.recordOrderSupplyAction(state, validation.recipe.result, supplyAvailableBefore);
        const resultItem = this.getItemData(validation.recipe.result);
        const resultName = resultItem?.name ?? `#${validation.recipe.result}`;
        console.log(`[engine] craft start: "${validation.recipe.name}" -> ${resultName} | time=${validation.recipe.craft_time}s | v${state.version}`);
        return { ok: true, newVersion: state.version, recipe: validation.recipe };
    }
    finishBoardCrafting(state) {
        let completed = 0;
        for (const item of state.grid) {
            const craft = item.craft;
            if (this.getItemData(item.id)?.type !== 2 || craft?._craft_state !== TableState.CRAFTING)
                continue;
            if (!this.getItemData(craft._craft_result_id))
                continue;
            craft._craft_state = TableState.READY;
            craft._craft_progress = 1;
            completed++;
        }
        return completed;
    }
    executeCraftSpeedup(state, tableCol, tableRow) {
        const tableItem = state.grid.find((item) => item.col === tableCol && item.row === tableRow);
        if (!tableItem?.craft)
            return { ok: false, reason: "table_not_found" };
        const craft = tableItem.craft;
        if (craft._craft_state !== TableState.CRAFTING) {
            return { ok: false, reason: "not_crafting" };
        }
        const recipe = craft._craft_recipe;
        const craftTimeMs = Math.max(0, Number(recipe?.craft_time ?? 0) * 1000);
        if (craftTimeMs <= 0)
            return { ok: false, reason: "invalid_craft_time" };
        const elapsedMs = Math.max(0, Date.now() - (craft._craft_start_time ?? Date.now()));
        const remainingMs = Math.max(0, craftTimeMs - elapsedMs);
        const remainingSeconds = Math.ceil(remainingMs / 1000);
        const billedMinutes = Math.ceil(remainingSeconds / 60);
        const cost = Math.ceil(billedMinutes * this.speedupConfig.craftStoneCostPerMinute);
        if (state.spirit_stones < cost) {
            return {
                ok: false,
                reason: "insufficient_stones",
                cost,
                remainingSeconds,
                spiritStones: state.spirit_stones,
            };
        }
        state.spirit_stones -= cost;
        craft._craft_state = TableState.READY;
        craft._craft_progress = 1;
        state.version += 1;
        return { ok: true, cost, remainingSeconds, newVersion: state.version };
    }
    executeLauncherSpeedup(state, launcherUid) {
        const launcherItem = state.grid.find((item) => item.uid === launcherUid);
        if (!launcherItem)
            return { ok: false, reason: "launcher_not_found" };
        const launcherDef = this.getItemData(launcherItem.id);
        if (!this.isLauncher(launcherDef))
            return { ok: false, reason: "not_launcher" };
        const rechargeTimeMs = Math.max(0, Number(launcherDef?.recharge_time ?? 0) * 1000);
        const maxCharges = Math.max(0, Number(launcherDef?.max_charges ?? 3));
        const charges = Number(launcherItem.charges ?? maxCharges);
        if (rechargeTimeMs <= 0 || charges >= maxCharges) {
            return { ok: false, reason: "not_recharging" };
        }
        const elapsedMs = Math.max(0, Date.now() - (launcherItem.last_charge_time ?? Date.now()));
        const remainingMs = Math.max(0, rechargeTimeMs - elapsedMs);
        const remainingSeconds = Math.ceil(remainingMs / 1000);
        const billedMinutes = Math.ceil(remainingSeconds / 60);
        const cost = Math.ceil(billedMinutes * this.speedupConfig.launcherStoneCostPerMinute);
        if (state.spirit_stones < cost) {
            return {
                ok: false,
                reason: "insufficient_stones",
                cost,
                remainingSeconds,
                spiritStones: state.spirit_stones,
            };
        }
        state.spirit_stones -= cost;
        launcherItem.charges = maxCharges;
        launcherItem.last_charge_time = Date.now();
        state.version += 1;
        return { ok: true, cost, remainingSeconds, charges: maxCharges, maxCharges, newVersion: state.version };
    }
    executeCraftRetrieve(state, tableCol, tableRow) {
        let tableItem = state.grid.find((item) => item.col === tableCol && item.row === tableRow);
        // Fallback: search whole grid for a table with craft data
        if (!tableItem?.craft) {
            tableItem = state.grid.find((item) => item.craft && (item.craft._craft_state === TableState.CRAFTING || item.craft._craft_state === TableState.READY));
        }
        if (!tableItem?.craft)
            return { ok: false, reason: "table_not_found" };
        const craft = tableItem.craft;
        if (craft._craft_state !== TableState.CRAFTING && craft._craft_state !== TableState.READY) {
            return { ok: false, reason: "not_crafting" };
        }
        // Check if enough time has elapsed (server-authoritative timer)
        if (craft._craft_state === TableState.CRAFTING) {
            const recipe = craft._craft_recipe;
            const craftTime = (recipe?.craft_time ?? 0) * 1000;
            const startTime = craft._craft_start_time ?? 0;
            const elapsed = Date.now() - startTime;
            if (elapsed < craftTime) {
                const remaining = Math.ceil((craftTime - elapsed) / 1000);
                return { ok: false, reason: `crafting_not_done remaining=${remaining}s` };
            }
        }
        const resultId = craft._craft_result_id;
        if (resultId <= 0)
            return { ok: false, reason: "no_result" };
        // Place result item on grid near the table
        const map = this.gridToMap(state.grid);
        const target = this.findNearestEmpty(map, tableItem.col, tableItem.row);
        // A failed retrieval must preserve the completed craft, UID sequence and
        // quest progress so the player can retry after freeing a cell.
        if (!target)
            return { ok: false, reason: "no_empty_cell" };
        const craftUid = this._nextUid(state);
        state.grid.push({ uid: craftUid, id: resultId, col: target.col, row: target.row });
        this.registerProductionUnlock(state, resultId);
        this.recordItemDiscovery(state, resultId);
        // Clear craft state
        delete tableItem.craft;
        state.version += 1;
        const retrievedItem = this.getItemData(resultId);
        const retrievedName = retrievedItem?.name ?? `#${resultId}`;
        console.log(`[engine] craft retrieve: -> ${retrievedName} uid=${craftUid} at (${target?.col ?? -1},${target?.row ?? -1}) | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.CRAFT, 1, this);
        return { ok: true, resultUid: craftUid, resultId, newVersion: state.version };
    }
    addIngredientToTable(state, tableCol, tableRow, ingredientId, fromCol, fromRow) {
        if (!this.isInBounds(fromCol, fromRow))
            return { ok: false, reason: "source_out_of_bounds" };
        if (!this.isInBounds(tableCol, tableRow))
            return { ok: false, reason: "table_out_of_bounds" };
        // Remove ingredient from grid (quantity conservation)
        const fromKey = this.posKey(fromCol, fromRow);
        const gridItem = state.grid.find((item) => this.posKey(item.col, item.row) === fromKey);
        if (!gridItem)
            return { ok: false, reason: "ingredient_not_found" };
        if (gridItem.id !== ingredientId)
            return { ok: false, reason: "ingredient_id_mismatch" };
        state.grid = state.grid.filter((item) => this.posKey(item.col, item.row) !== fromKey);
        const ingName = this.getItemData(ingredientId)?.name ?? ("#" + ingredientId);
        console.log(`[engine] craft add: removed ${ingName} from grid (${fromCol},${fromRow})`);
        const tableItem = state.grid.find((item) => item.col === tableCol && item.row === tableRow);
        if (!tableItem)
            return { ok: false, reason: "table_not_found" };
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
        if (!ingredientData)
            return { ok: false, reason: "invalid_ingredient" };
        craft._craft_stored.push({ id: ingredientId });
        craft._craft_state = TableState.HAS_ITEMS;
        // Check recipe match
        const allowedRecipes = this.getRecipesForTable(tableItem.id);
        const matched = this.matchRecipe(craft._craft_stored, allowedRecipes);
        if (matched) {
            craft._craft_recipe = matched;
            console.log(`[engine] craft add: #${ingredientId} -> recipe matched "${matched.name}" | stored=${craft._craft_stored.length}`);
        }
        else {
            craft._craft_recipe = {};
            console.log(`[engine] craft add: #${ingredientId} -> no match yet | stored=${craft._craft_stored.length}`);
        }
        state.version += 1;
        return { ok: true, matched: !!matched, newVersion: state.version };
    }
    matchRecipe(stored, recipes) {
        const storedCounts = new Map();
        for (const item of stored) {
            const id = item.id;
            storedCounts.set(id, (storedCounts.get(id) || 0) + 1);
        }
        for (const recipe of recipes) {
            const totalRequired = recipe.ingredients.length;
            if (stored.length !== totalRequired)
                continue;
            let match = true;
            // Count required occurrences of each ingredient
            const requiredCounts = new Map();
            for (const id of recipe.ingredients) {
                requiredCounts.set(id, (requiredCounts.get(id) || 0) + 1);
            }
            for (const [id, count] of requiredCounts) {
                if ((storedCounts.get(id) || 0) !== count) {
                    match = false;
                    break;
                }
            }
            if (match)
                return recipe;
        }
        return null;
    }
    // --- Cultivation ---
    /** Physical instances owned on the active board or in the shared pouch.
     * Keep references so timers update stored instances as well. Nested materials
     * are prediction inputs only and cannot be submitted directly as order items.
     */
    getInventoryItems(state) {
        const seen = new Set();
        const result = [];
        for (const raw of [...(state.grid ?? []), ...(state.pouch ?? [])]) {
            const item = raw;
            if (item.uid && seen.has(item.uid))
                continue;
            if (item.uid)
                seen.add(item.uid);
            result.push(item);
        }
        return result;
    }
    getStoredItemId(entry) {
        if (!entry || typeof entry !== "object")
            return 0;
        return Number(entry.id ?? 0);
    }
    getStageBreakthroughItems(level) {
        if (!this.cultivation)
            return [];
        const stages = this.cultivation.stages;
        if (!stages || level < 1 || level > stages.length)
            return [];
        const configured = stages[level - 1]?.breakthrough_items;
        if (!Array.isArray(configured))
            return [];
        return configured.flatMap((entry) => {
            const itemId = Number(entry?.item_id ?? 0);
            const count = Number(entry?.count ?? 0);
            if (!Number.isInteger(itemId) || itemId <= 0 || !Number.isInteger(count) || count <= 0)
                return [];
            return [{ item_id: itemId, count }];
        });
    }
    getStageBreakthroughReward(level) {
        if (!this.cultivation)
            return 0;
        const stages = this.cultivation.stages;
        if (!stages || level < 1 || level > stages.length)
            return 0;
        return stages[level - 1]?.breakthrough_reward_id ?? 0;
    }
    getExpToNextLevel(level) {
        if (!this.cultivation)
            return 999999;
        const stages = this.cultivation.stages;
        if (!stages || level < 1 || level > stages.length)
            return 999999;
        return stages[level - 1].exp;
    }
    isMaxCultivation(level) {
        if (!this.cultivation)
            return true;
        return level >= this.cultivation.stages.length;
    }
    needsBreakthroughItems(level) {
        if (!this.cultivation)
            return false;
        if (this.isMaxCultivation(level))
            return false;
        return this.getStageBreakthroughItems(level).length > 0;
    }
    isBreakthroughReady(level, exp) {
        if (!this.cultivation)
            return false;
        if (this.isMaxCultivation(level))
            return false;
        if (level > this.cultivation.stages.length)
            return false;
        return exp >= this.getExpToNextLevel(level);
    }
    getRequiredBreakthroughItems(level, exp) {
        if (!this.isBreakthroughReady(level, exp))
            return [];
        return this.getStageBreakthroughItems(level);
    }
    syncBreakthroughOrder(state) {
        if (this.hasReadyHomeMeridianCirculation(state))
            return false;
        const level = state.cultivation.current_level;
        const requirements = this.getRequiredBreakthroughItems(level, state.cultivation.current_exp);
        if (requirements.length === 0)
            return false;
        const itemIds = requirements.flatMap(requirement => new Array(requirement.count).fill(requirement.item_id));
        const currentOrders = Array.isArray(state.meridian_acupoints) ? state.meridian_acupoints : [];
        const currentOrder = currentOrders.length === 1 ? currentOrders[0] : null;
        const alreadyCurrent = currentOrder?.breakthrough_order === true
            && Number(currentOrder.breakthrough_level) === level
            && JSON.stringify(currentOrder.item_ids) === JSON.stringify(itemIds);
        if (alreadyCurrent)
            return false;
        state.meridian_acupoints = [{
                ...this._genFixedAcupoint(itemIds),
                breakthrough_order: true,
                breakthrough_level: level,
            }];
        console.log(`[engine] breakthrough ready at level ${level}; replaced all meridian orders with requirements ${JSON.stringify(itemIds)}`);
        return true;
    }
    finishBreakthrough(state, level, requiredCounts) {
        if (!this.cultivation)
            return { ok: false, reason: "no_config" };
        const nextLevel = level + 1;
        if (nextLevel > this.cultivation.stages.length)
            return { ok: false, reason: "max_level" };
        const nextStage = this.cultivation.stages[nextLevel - 1];
        const newMaxQi = nextStage?.max_qi ?? (state.cultivation.max_qi + 50);
        const newCultivation = {
            current_level: nextLevel,
            current_exp: 0,
            total_exp: state.cultivation.total_exp,
            current_qi: Math.min(state.cultivation.current_qi, newMaxQi),
            max_qi: newMaxQi,
            last_tick_time: state.cultivation.last_tick_time,
        };
        state.cultivation = newCultivation;
        this.weeklyTaskService.ensureProgress(state);
        state.meridian_acupoints = [];
        const rewardId = this.getStageBreakthroughReward(level);
        const rewards = rewardId > 0 ? this.applyRewards(state, rewardId) : { tokens: [], items: [] };
        this.generateMeridianRequirements(state);
        state.version += 1;
        const stageName = nextStage?.name ?? `stage_${nextLevel}`;
        console.log(`[engine] breakthrough: -> ${stageName} | consumed=${JSON.stringify([...requiredCounts])} | qi=${newCultivation.max_qi} | v${state.version}`);
        // The breakthrough that exits the novice phase is itself a novice action;
        // subsequent breakthroughs are tracked normally.
        if (level >= 2)
            this.questEngine.incrementQuestProgress(state, interface_1.QuestType.BREAKTHROUGH, 1, this);
        return { ok: true, newCultivation, rewards };
    }
    executeTryBreakthrough(state, uid, level, exp) {
        console.log(`[engine] tryBreakthrough: uid=${uid} level=${level} exp=${exp}`);
        if (!this.isBreakthroughReady(level, exp)) {
            console.log(`[engine] tryBreakthrough: not ready (need exp=${this.getExpToNextLevel(level)} have=${exp})`);
            return { ok: false, reason: "not_ready" };
        }
        if (this.hasReadyHomeMeridianCirculation(state)) {
            return { ok: false, reason: "circulation_pending" };
        }
        if (!this.cultivation)
            return { ok: false, reason: "no_config" };
        const requiredCounts = new Map();
        for (const requirement of this.getRequiredBreakthroughItems(level, exp)) {
            requiredCounts.set(requirement.item_id, (requiredCounts.get(requirement.item_id) ?? 0) + requirement.count);
        }
        const availableCounts = new Map();
        for (const item of state.grid) {
            availableCounts.set(item.id, (availableCounts.get(item.id) ?? 0) + 1);
        }
        for (const entry of state.pouch) {
            const itemId = this.getStoredItemId(entry);
            if (itemId > 0) {
                availableCounts.set(itemId, (availableCounts.get(itemId) ?? 0) + 1);
            }
        }
        const missing = [];
        for (const [itemId, requiredCount] of requiredCounts) {
            const available = availableCounts.get(itemId) ?? 0;
            if (available < requiredCount) {
                missing.push({ item_id: itemId, required: requiredCount, available });
            }
        }
        if (missing.length > 0) {
            console.log(`[engine] breakthrough blocked: missing=${JSON.stringify(missing)}`);
            return { ok: false, reason: "breakthrough_items_insufficient", missing };
        }
        const remainingCounts = new Map(requiredCounts);
        for (let index = state.pouch.length - 1; index >= 0; index -= 1) {
            const itemId = this.getStoredItemId(state.pouch[index]);
            const remaining = remainingCounts.get(itemId) ?? 0;
            if (remaining <= 0)
                continue;
            state.pouch.splice(index, 1);
            remainingCounts.set(itemId, remaining - 1);
        }
        for (let index = state.grid.length - 1; index >= 0; index -= 1) {
            const itemId = state.grid[index].id;
            const remaining = remainingCounts.get(itemId) ?? 0;
            if (remaining <= 0)
                continue;
            state.grid.splice(index, 1);
            remainingCounts.set(itemId, remaining - 1);
        }
        return this.finishBreakthrough(state, level, requiredCounts);
    }
    tickCraftingState(state) {
        const now = Date.now();
        let changed = false;
        for (const item of this.getInventoryItems(state)) {
            if (!item.craft || item.craft._craft_state !== TableState.CRAFTING)
                continue;
            const recipe = item.craft._craft_recipe;
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
    consumeExpPill(state, pillId, uid) {
        const pillData = this.getItemData(pillId);
        if (!pillData)
            return { ok: false, reason: "invalid_pill" };
        if (!pillData.effect_type || pillData.effect_type !== 3)
            return { ok: false, reason: "invalid_effect" };
        const expGain = pillData.effect_value ?? 0;
        if (expGain <= 0)
            return { ok: false, reason: "no_exp_gain" };
        // Remove pill from grid
        const pillIdx = state.grid.findIndex(g => g.uid === uid);
        if (pillIdx >= 0) {
            state.grid.splice(pillIdx, 1);
            console.log(`[engine]   exp pill #${pillId} removed, uid=${uid}`);
        }
        this._addExp(state.cultivation, expGain);
        this.syncBreakthroughOrder(state);
        state.version += 1;
        const pillName = pillData.name;
        console.log(`[engine] consume exp pill: ${pillName} | exp +${expGain} | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.ANY_ITEM_CONSUME, 1, this);
        return { ok: true, cultivation: state.cultivation };
    }
    getPouchState(state) {
        return {
            pouch_capacity: state.pouch_capacity,
            pouch_next_unlock_cost: this.pouchConfig.unlockCostBase + state.pouch_unlock_count * this.pouchConfig.unlockCostIncrement,
        };
    }
    pouchUnlock(state, expectedCapacity) {
        const info = this.getPouchState(state);
        if (expectedCapacity !== info.pouch_capacity)
            return { ok: false, reason: "state_conflict" };
        const cost = info.pouch_next_unlock_cost;
        if (!Number.isSafeInteger(cost) || !Number.isSafeInteger(info.pouch_capacity + 1)) {
            return { ok: false, reason: "pouch_limit_reached" };
        }
        if (state.spirit_stones < cost)
            return { ok: false, reason: "insufficient_stones" };
        state.spirit_stones -= cost;
        state.pouch_capacity += 1;
        state.pouch_unlock_count += 1;
        state.version += 1;
        return { ok: true, cost };
    }
    pouchDeposit(state, uid) {
        const idx = state.grid.findIndex((g) => g.uid === uid);
        if (idx < 0)
            return { ok: false, reason: "item_not_found" };
        if (state.pouch.length >= this.getPouchState(state).pouch_capacity)
            return { ok: false, reason: "pouch_full" };
        const { col: _col, row: _row, ...stored } = state.grid[idx];
        const itemId = stored.id;
        state.grid.splice(idx, 1);
        state.pouch.push({ ...stored, uid });
        state.version += 1;
        console.log(`[engine] pouch deposit: #${itemId} (uid=${uid}) | pouch=${state.pouch.length} items | v${state.version}`);
        return { ok: true, pouch: state.pouch };
    }
    pouchWithdraw(state, uid, col, row) {
        const idx = state.pouch.findIndex((p) => p.uid === uid);
        if (idx < 0)
            return { ok: false, reason: "item_not_in_pouch" };
        if (!this.isInBounds(col, row))
            return { ok: false, reason: "invalid_position" };
        if (state.grid.some((g) => g.col === col && g.row === row))
            return { ok: false, reason: "cell_occupied" };
        const entry = state.pouch[idx];
        const itemId = entry.id;
        state.pouch.splice(idx, 1);
        const item = { ...entry, col, row };
        state.grid.push(item);
        state.version += 1;
        console.log(`[engine] pouch withdraw: #${itemId} uid=${entry.uid} at (${col},${row}) | pouch=${state.pouch.length} items | v${state.version}`);
        return { ok: true, pouch: state.pouch, item, col, row };
    }
    initBattleMonsters(state) {
        if (!state.battle_monsters || state.battle_monsters.length > 0)
            return;
        state.battle_monsters = this._buildMonsterList(state.battle_map_id ?? 1, state.battle_stage ?? 0);
        console.log(`[engine] init battle monsters: ${state.battle_monsters.length} monsters`);
    }
    _buildMonsterList(mapId, stage) {
        const map = this.maps.get(mapId);
        if (!map)
            return [];
        const stages = map.stages ?? [];
        if (stage >= stages.length)
            return [];
        const stageData = stages[stage];
        const result = [];
        const monsters = stageData.monsters ?? [];
        for (const entry of monsters) {
            const mdata = this.getMonster(entry.monster_id);
            if (!mdata)
                continue;
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
    battleHeal(state, itemId, uid, effectId) {
        const idx = state.grid.findIndex(g => g.uid === uid);
        if (idx < 0)
            return { ok: false, reason: "item_not_found" };
        const item = state.grid[idx];
        if (item.id !== itemId)
            return { ok: false, reason: "item_id_mismatch" };
        state.grid.splice(idx, 1);
        state.version += 1;
        console.log(`[engine] battle heal: #${itemId} consumed, uid=${uid}`);
        return { ok: true, newVersion: state.version, grid: state.grid };
    }
    battleAttack(state, itemId, effectId, uid, col, row) {
        const itemDef = this.getItemData(itemId);
        if (!itemDef || !itemDef.effect_type || itemDef.effect_type !== 1)
            return { ok: false, reason: "invalid_effect" };
        // Remove used item from grid (prefer uid match, fall back to pos+id)
        const idx = state.grid.findIndex((g) => g.uid === uid);
        if (idx < 0)
            return { ok: false, reason: "item_not_found" };
        const removedItem = state.grid.splice(idx, 1)[0];
        if (!removedItem.atk_base) {
            state.grid.push(removedItem);
            return { ok: false, reason: "no_atk_base" };
        }
        const dmg = removedItem.atk_base * (itemDef.effect_value ?? 1);
        if (dmg <= 0)
            return { ok: false, reason: "no_damage" };
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
        if (!state.battle_monsters[mIdx].accept_effect_types.includes(itemDef.effect_type ?? 0)) {
            state.grid.push(removedItem);
            return { ok: false, reason: "effect_not_accepted" };
        }
        // Apply damage
        state.battle_monsters[mIdx].hp = Math.max(0, state.battle_monsters[mIdx].hp - dmg);
        const monsterName = state.battle_monsters[mIdx].name;
        const killed = state.battle_monsters[mIdx].hp <= 0;
        const loot = [];
        if (killed) {
            // Drop loot based on monster
            const mdata = this.getMonster(state.battle_monsters[mIdx].monster_id);
            if (mdata?.loot?.length) {
                for (const lootId of mdata.loot) {
                    const emptyPos = this.findEmptyPos(state.grid);
                    if (emptyPos) {
                        state.grid.push({ uid: this._nextUid(state), id: lootId, col: emptyPos.col, row: emptyPos.row });
                        this.registerProductionUnlock(state, lootId);
                        this.recordItemDiscovery(state, lootId);
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
                    const stages = map.stages ?? [];
                    if ((state.battle_stage ?? 0) < stages.length) {
                        state.battle_monsters = this._buildMonsterList(state.battle_map_id ?? 1, state.battle_stage ?? 0);
                    }
                    else {
                        state.battle_monsters = [];
                    }
                }
            }
            state.version += 1;
            console.log(`[engine] battle attack: ${monsterName} killed by #${itemId} | loot=${loot.join(",")} | stage_complete=${stageComplete} | v${state.version}`);
            this.questEngine.incrementQuestProgress(state, interface_1.QuestType.BATTLE_ATTACK, 1, this);
            if (stageComplete) {
                this.questEngine.incrementQuestProgress(state, interface_1.QuestType.BATTLE_CLEAR, 1, this);
            }
            return { ok: true, grid: state.grid, monsters: state.battle_monsters, stage_complete: stageComplete, loot };
        }
        state.version += 1;
        console.log(`[engine] battle attack: ${monsterName} took ${dmg} dmg (${state.battle_monsters[mIdx].hp}/${state.battle_monsters[mIdx].max_hp}) | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.BATTLE_ATTACK, 1, this);
        return { ok: true, grid: state.grid, monsters: state.battle_monsters, stage_complete: false, loot: [] };
    }
    consumeStaminaPill(state, pillId, uid) {
        const pillData = this.getItemData(pillId);
        if (!pillData)
            return { ok: false, reason: "invalid_pill" };
        if (!pillData.effect_type || pillData.effect_type !== 4)
            return { ok: false, reason: "invalid_effect" };
        const amount = pillData.effect_value ?? 0;
        if (amount <= 0)
            return { ok: false, reason: "no_stamina_gain" };
        console.log(`[engine] consume stamina pill: #${pillId} "${pillData.name}" (uid=${uid}) | grid=${state.grid.length} items`);
        console.log(`[engine]   grid uids: [${state.grid.map(g => `${g.id}(${g.col},${g.row}):uid=${g.uid}`).join(", ")}]`);
        let idx = state.grid.findIndex((g) => g.uid === uid);
        if (idx < 0) {
            console.log(`[engine]   uid=${uid} NOT found!`);
            return { ok: false, reason: "item_not_found" };
        }
        state.grid.splice(idx, 1);
        console.log(`[engine]   removed from grid at idx=${idx}`);
        this.addStamina(state, amount);
        state.last_stamina_tick = Date.now();
        state.version += 1;
        console.log(`[engine] consume stamina pill: #${pillId} (uid=${uid}) | stamina +${amount} total=${state.stamina} | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.ANY_ITEM_CONSUME, 1, this);
        return { ok: true, stamina: state.stamina, max_stamina: this.staminaConfig.max };
    }
    consumeSpiritStoneItem(state, itemId, uid) {
        const itemData = this.getItemData(itemId);
        if (!itemData)
            return { ok: false, reason: "invalid_item" };
        if (itemData.effect_type !== 8)
            return { ok: false, reason: "invalid_effect" };
        const amount = Number(itemData.effect_value ?? 0);
        if (!Number.isInteger(amount) || amount <= 0) {
            return { ok: false, reason: "no_spirit_stone_gain" };
        }
        const itemIndex = state.grid.findIndex(item => item.uid === uid && item.id === itemId);
        if (itemIndex < 0)
            return { ok: false, reason: "item_not_found" };
        state.grid.splice(itemIndex, 1);
        state.spirit_stones += amount;
        state.version += 1;
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.ANY_ITEM_CONSUME, 1, this);
        console.log(`[engine] consume spirit stone item: #${itemId} uid=${uid} +${amount} stones (total=${state.spirit_stones}) | v${state.version}`);
        return { ok: true, spiritStones: state.spirit_stones, amount };
    }
    _addExp(c, amount) {
        if (amount <= 0)
            return;
        if (!this.cultivation)
            return;
        if (this.isMaxCultivation(c.current_level))
            return;
        const expNeeded = this.getExpToNextLevel(c.current_level);
        c.current_exp = Math.min(c.current_exp + amount, expNeeded);
        c.total_exp += amount;
    }
    pushAndPlace(state, fromCol, fromRow, toCol, toRow) {
        if (!this.isInBounds(fromCol, fromRow))
            return { ok: false, reason: "source_out_of_bounds" };
        if (!this.isInBounds(toCol, toRow))
            return { ok: false, reason: "target_out_of_bounds" };
        const fromKey = this.posKey(fromCol, fromRow);
        const toKey = this.posKey(toCol, toRow);
        console.log(`[engine] pushAndPlace: from=(${fromCol},${fromRow}) to=(${toCol},${toRow}) v=${state.version}`);
        const fromItem = state.grid.find(i => this.posKey(i.col, i.row) === fromKey);
        const toItem = state.grid.find(i => this.posKey(i.col, i.row) === toKey);
        if (!fromItem) {
            console.log("[engine] pushAndPlace: source_item_not_found");
            return { ok: false, reason: "source_item_not_found" };
        }
        if (!toItem) {
            console.log("[engine] pushAndPlace: target_item_not_found");
            return { ok: false, reason: "target_item_not_found" };
        }
        if (fromCol === toCol && fromRow === toRow)
            return { ok: false, reason: "same_position" };
        if (toItem.immovable) {
            console.log("[engine] pushAndPlace: target_immovable");
            return { ok: false, reason: "target_immovable" };
        }
        // Find nearest empty cell. If grid is full, allow using the source position.
        const map = this.gridToMap(state.grid);
        let empty = this.findNearestEmpty(map, toCol, toRow);
        if (!empty) {
            map.delete(fromKey);
            empty = this.findNearestEmpty(map, toCol, toRow);
        }
        if (!empty)
            return { ok: false, reason: "no_empty_cell" };
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
    completeMeridianAcupoint(state, index, itemIds, requestId = "") {
        if (!state.meridian_acupoints || index < 0 || index >= state.meridian_acupoints.length) {
            return { ok: false, reason: "invalid_index" };
        }
        if (!Number.isInteger(index))
            return { ok: false, reason: "invalid_index" };
        if (requestId && state.card_collection_order_requests?.includes(requestId))
            return { ok: false, reason: "already_completed" };
        const req = state.meridian_acupoints[index];
        if (req.completed)
            return { ok: false, reason: "already_completed" };
        if (req.breakthrough_order === true) {
            return { ok: false, reason: "breakthrough_confirmation_required" };
        }
        const requiredIds = [...req.item_ids];
        requiredIds.sort((a, b) => a - b);
        if (requiredIds.length === 0 || itemIds.length !== requiredIds.length || [...itemIds].sort((a, b) => a - b).some((id, i) => id !== requiredIds[i])) {
            return { ok: false, reason: "invalid_order_items" };
        }
        const toRemove = [];
        const pouchToRemove = [];
        const consumedUids = new Set();
        for (const reqItemId of itemIds) {
            const gridIndex = state.grid.findIndex((item, i) => !toRemove.includes(i) && item.id === reqItemId && item.immovable !== true
                && (!item.uid || !consumedUids.has(item.uid)));
            if (gridIndex >= 0) {
                toRemove.push(gridIndex);
                if (state.grid[gridIndex].uid)
                    consumedUids.add(state.grid[gridIndex].uid);
                continue;
            }
            const pouchIndex = (state.pouch ?? []).findIndex((entry, i) => !pouchToRemove.includes(i) && this.getStoredItemId(entry) === reqItemId
                && entry.immovable !== true && !consumedUids.has(entry.uid));
            if (pouchIndex < 0)
                return { ok: false, reason: "insufficient_items" };
            pouchToRemove.push(pouchIndex);
            const stored = state.pouch[pouchIndex];
            consumedUids.add(stored.uid);
        }
        if (state.cultivation.current_qi >= state.cultivation.max_qi) {
            return { ok: false, reason: "qi_full" };
        }
        // Remove consumed items
        for (const idx of toRemove.sort((a, b) => b - a)) {
            state.grid.splice(idx, 1);
        }
        for (const idx of pouchToRemove.sort((a, b) => b - a))
            state.pouch.splice(idx, 1);
        req.completed = true;
        state.version += 1;
        // Order reward — scale by total item value
        const threshold = this.meridianThresholds[state.meridian_threshold_idx ?? 0];
        const totalValue = req.total_value ?? 0;
        let qiGained = 0;
        let qiFull = false;
        let rewardsApplied = { tokens: [], items: [] };
        let orderRewards = req.fixed_order_rewards
            ? this._copyRewardConfig(req.rewards || {})
            : (totalValue > 0 && threshold?.acupoint_rewards
                ? this._scaleRewardConfig(threshold.acupoint_rewards, totalValue)
                : undefined);
        const cardPackReward = (0, activity_access_1.activitiesUnlocked)(state)
            ? this.cardCollectionService.getSourceRewardConfig("order", 0, totalValue) : {};
        if (cardPackReward.items?.length) {
            orderRewards ??= { tokens: [], items: [] };
            orderRewards.items ??= [];
            orderRewards.items.push(...cardPackReward.items);
        }
        if (orderRewards) {
            const qiBefore = state.cultivation.current_qi;
            const r = this.applyRewards(state, orderRewards);
            rewardsApplied.tokens.push(...(r.tokens || []));
            rewardsApplied.items.push(...(r.items || []));
            qiGained = state.cultivation.current_qi - qiBefore;
            qiFull = state.cultivation.current_qi >= state.cultivation.max_qi && qiBefore < state.cultivation.max_qi;
        }
        // Fixed onboarding orders are revealed one configured wave at a time.
        state.meridian_acupoints.splice(index, 1);
        const newThreshold = this._findMeridianThreshold(state.cultivation.current_level);
        const fixedOrderWaves = this._getFixedOrderWaves(newThreshold);
        if (fixedOrderWaves.length === 0) {
            if (state.meridian_acupoints.length === 0) {
                // Random orders are a batch: do not replace an order until every
                // configured order in the current batch has been completed.
                const launchersRefreshed = this.refreshBoardLaunchers(state);
                const weightedPool = this.getUnlockedOrderPoolWithWeights(state);
                const orderCount = Math.max(0, Math.floor(Number(newThreshold?.order_count ?? newThreshold?.acupoints ?? 0)));
                if (weightedPool.ids.length > 0 && orderCount > 0) {
                    const newTypeMin = newThreshold?.count_min ?? 1;
                    const newTypeMax = newThreshold?.count_max ?? 3;
                    state.meridian_acupoints = this._generateRandomMeridianBatch(weightedPool.ids, weightedPool.weights, orderCount, newTypeMin, newTypeMax, newThreshold?.acupoint_rewards);
                    console.log(`[engine] meridian random batch completed; refreshed ${state.meridian_acupoints.length} orders and ${launchersRefreshed} launchers`);
                }
                else {
                    console.log(`[engine] meridian random batch completed; no craftable replacement available (launchers_refreshed=${launchersRefreshed})`);
                }
            }
            else {
                console.log(`[engine] meridian order #${index} completed; ${state.meridian_acupoints.length} random orders remain in batch`);
            }
        }
        else {
            // Fixed onboarding orders advance only after the player runs a complete
            // home-meridian circulation. Keep the list empty until that explicit
            // circulation action reveals the next configured wave.
            if (state.meridian_acupoints.length === 0) {
                state.meridian_fixed_wave_pending = true;
            }
            console.log(`[engine] meridian fixed order #${index} completed, next wave deferred until circulation`);
        }
        this.battlePassService.awardOrderPoints(state, totalValue, requestId);
        this.secretRealmService.awardOrder(state);
        this.orderDuelService.awardOrderPoints(state, requiredIds.reduce((sum, id) => sum + (this.getItemData(id)?.value ?? 0), 0));
        this.stairClimbService.awardOrderPoints(state, requiredIds.reduce((sum, id) => sum + (this.getItemData(id)?.value ?? 0), 0));
        if (requestId)
            state.card_collection_order_requests = [...(state.card_collection_order_requests ?? []), requestId].slice(-128);
        return { ok: true, newVersion: state.version, meridian_acupoints: state.meridian_acupoints, rewards: rewardsApplied, qi_gained: qiGained, qi_full: qiFull, grid: state.grid, pouch: state.pouch, ...this.getPouchState(state), cultivation: state.cultivation, spirit_stones: state.spirit_stones, stamina: state.stamina, battle_pass_progress: this.battlePassService.ensureProgress(state) };
    }
    // --- Storage ---
    initStorage(item) {
        if (!item.storage) {
            const itemDef = this.getItemData(item.id);
            item.storage = { items: [], max_slots: itemDef?.storage_slots ?? 20 };
        }
    }
    depositItem(state, storageCol, storageRow, uid, fromCol, fromRow) {
        if (!this.isInBounds(fromCol, fromRow))
            return { ok: false, reason: "from_out_of_bounds" };
        if (!this.isInBounds(storageCol, storageRow))
            return { ok: false, reason: "storage_out_of_bounds" };
        const fromKey = this.posKey(fromCol, fromRow);
        const sourceItem = state.grid.find(i => this.posKey(i.col, i.row) === fromKey);
        if (!sourceItem)
            return { ok: false, reason: "item_not_found" };
        const storageItem = state.grid.find(i => i.col === storageCol && i.row === storageRow);
        if (!storageItem)
            return { ok: false, reason: "storage_not_found" };
        this.initStorage(storageItem);
        const s = storageItem.storage;
        if (s.items.length >= s.max_slots)
            return { ok: false, reason: "storage_full" };
        // Remove from grid
        state.grid = state.grid.filter(i => this.posKey(i.col, i.row) !== fromKey);
        // Add to storage (no stacking — one slot per item)
        s.items.push({ uid: sourceItem.uid, id: sourceItem.id });
        state.version += 1;
        console.log(`[engine] deposit: #${sourceItem.id} uid=${sourceItem.uid} -> storage at (${storageCol},${storageRow}) | slots=${s.items.length}/${s.max_slots}`);
        return { ok: true, newVersion: state.version };
    }
    withdrawItem(state, storageCol, storageRow, uid, targetCol, targetRow) {
        if (!this.isInBounds(storageCol, storageRow))
            return { ok: false, reason: "storage_out_of_bounds" };
        if (!this.isInBounds(targetCol, targetRow))
            return { ok: false, reason: "target_out_of_bounds" };
        const storageItem = state.grid.find(i => i.col === storageCol && i.row === storageRow);
        if (!storageItem?.storage)
            return { ok: false, reason: "storage_not_found" };
        const targetKey = this.posKey(targetCol, targetRow);
        if (state.grid.some(i => this.posKey(i.col, i.row) === targetKey))
            return { ok: false, reason: "target_occupied" };
        const idx = storageItem.storage.items.findIndex(s => s.uid === uid);
        if (idx < 0)
            return { ok: false, reason: "item_not_in_storage" };
        const entry = storageItem.storage.items[idx];
        storageItem.storage.items.splice(idx, 1);
        state.grid.push({ uid: entry.uid, id: entry.id, col: targetCol, row: targetRow });
        state.version += 1;
        const itemName = this.getItemData(entry.id)?.name ?? ("#" + entry.id);
        console.log(`[engine] withdraw: ${itemName} uid=${entry.uid} from storage at (${storageCol},${storageRow}) -> (${targetCol},${targetRow})`);
        return { ok: true, newVersion: state.version, uid: entry.uid, col: targetCol, row: targetRow };
    }
    // --- Shop ---
    sellItem(state, uid) {
        const rewindBefore = this.goldenFingerService.snapshot(state);
        const item = state.grid.find(i => i.uid === uid);
        if (!item)
            return { ok: false, reason: "item_not_found" };
        const itemId = item.id;
        const data = this.getItemData(item.id);
        if (!data)
            return { ok: false, reason: "item_data_not_found" };
        if (data.type === 2 || this.isLauncher(data)) {
            return { ok: false, reason: "cannot_sell" };
        }
        const price = this.getSellPrice(item.id);
        if (price <= 0)
            return { ok: false, reason: "cannot_sell" };
        state.grid = state.grid.filter(i => i.uid !== uid);
        state.spirit_stones += price;
        state.version += 1;
        const itemName = data.name ?? ("#" + item.id);
        console.log(`[engine] sell: ${itemName} (uid=${uid}) -> +${price} stones | total=${state.spirit_stones}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.SELL, 1, this);
        this.goldenFingerService.capture(state, rewindBefore, "出售");
        return { ok: true, stones: state.spirit_stones };
    }
    buyItem(state, itemId, targetCol, targetRow, expectedRevision, now = Date.now()) {
        this.shopService.ensure(state, now);
        if (expectedRevision !== undefined && state.shop.revision !== expectedRevision)
            return { ok: false, reason: "shop_changed" };
        const offer = state.shop.items.find(item => item.id === itemId);
        if (!offer)
            return { ok: false, reason: "not_in_shop" };
        if (offer.purchased >= this.shopService.purchaseLimit)
            return { ok: false, reason: "purchase_limit_reached" };
        if (!Number.isSafeInteger(targetCol) || !Number.isSafeInteger(targetRow))
            return { ok: false, reason: "out_of_bounds" };
        if (!this.isInBounds(targetCol, targetRow))
            return { ok: false, reason: "out_of_bounds" };
        const targetKey = this.posKey(targetCol, targetRow);
        if (state.grid.some(i => this.posKey(i.col, i.row) === targetKey))
            return { ok: false, reason: "target_occupied" };
        const price = offer.price;
        if (price <= 0)
            return { ok: false, reason: "cannot_buy" };
        if (state.spirit_stones < price)
            return { ok: false, reason: "insufficient_stones" };
        const itemData = this.getItemData(itemId);
        if (!itemData)
            return { ok: false, reason: "item_data_not_found" };
        state.spirit_stones -= price;
        offer.purchased++;
        const buyUid = this._nextUid(state);
        state.grid.push({ uid: buyUid, id: itemId, col: targetCol, row: targetRow });
        this.registerProductionUnlock(state, itemId);
        this.recordItemDiscovery(state, itemId);
        state.version += 1;
        console.log(`[engine] buy: ${itemData.name} at (${targetCol},${targetRow}) -> -${price} stones | total=${state.spirit_stones}`);
        return { ok: true, uid: buyUid, stones: state.spirit_stones };
    }
    getGridHash(state) {
        // Simple hash of grid layout for client-side integrity checks
        let hash = 0;
        const sorted = [...state.grid].sort((a, b) => {
            if (a.col !== b.col)
                return a.col - b.col;
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
exports.GameEngine = GameEngine;
