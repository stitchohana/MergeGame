"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GameEngine = exports.TableState = void 0;
const interface_1 = require("../storage/interface");
const quest_engine_1 = require("./quest_engine");
const activity_engine_1 = require("./activity_engine");
const spawn_rng_1 = require("./spawn_rng");
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
    staminaConfig = { max: 100, spawnCost: 10, regenInterval: 120, regenAmount: 1 };
    speedupConfig = { craftStoneCostPerMinute: 1, launcherStoneCostPerMinute: 1 };
    questResetHour = 0;
    shopConfig = { shopItems: [], sellPrices: {}, buyPrices: {} };
    meridianThresholds = [];
    meridianOrderLevelRanges = [];
    maps = new Map();
    monsters = new Map();
    rewardsTable = new Map();
    homeMeridianDefs = [];
    questEngine;
    activityEngine;
    constructor(configTables) {
        this.loadConfigs(configTables);
        this.questEngine = new quest_engine_1.QuestEngine(configTables.quests);
        this.activityEngine = new activity_engine_1.ActivityEngine(configTables.activities, configTables.weeklyTasks);
        this.loadRewards(configTables.rewards);
        this.loadHomeMeridians(configTables.homeMeridians);
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
                };
                console.log(`[engine] Stamina config: max=${this.staminaConfig.max} cost=${this.staminaConfig.spawnCost} regen=${this.staminaConfig.regenAmount}/${this.staminaConfig.regenInterval}s`);
            }
            this.questResetHour = data.reset_hour ?? 0;
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
        const exp = Math.max(0, Number(def.acupoint_exp ?? 0));
        return {
            tokens: [
                { token: interface_1.TokenType.EXP, amount: exp },
                { token: interface_1.TokenType.STAMINA, amount: 15 },
            ],
            items: [],
        };
    }
    _maxUnlockedHomeStageIndex(cultivationLevel) {
        if (cultivationLevel <= 1)
            return 0;
        if (cultivationLevel <= 10)
            return cultivationLevel - 1;
        return 9 + (cultivationLevel - 10) * 10;
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
        // Check circulation completion
        const allLit = stageProgress.lit.every(l => l);
        if (allLit) {
            stageProgress.circulation_completed = true;
            if (def.circulation_reward) {
                const r = this.applyRewards(state, def.circulation_reward);
                rewardsApplied.tokens.push(...(r.tokens || []));
                rewardsApplied.items.push(...(r.items || []));
            }
        }
        const meridianThreshold = this._findMeridianThreshold(state.cultivation.current_level);
        this._tryRevealFixedOrders(state, meridianThreshold);
        state.version += 1;
        return {
            ok: true,
            circulation_completed: allLit,
            cultivation: state.cultivation,
            spirit_stones: state.spirit_stones,
            stamina: state.stamina,
            pending_rewards: state.pending_rewards,
            home_meridian_progress: state.home_meridian_progress,
            meridian_acupoints: state.meridian_acupoints || [],
        };
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
                if (def.circulation_reward) {
                    this.applyRewards(state, def.circulation_reward);
                }
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
            state.meridian_acupoints = [];
        }
        state.meridian_threshold_idx = foundIdx;
        if (Array.isArray(state.meridian_acupoints) && state.meridian_acupoints.length > 0) {
            return { acupoints: state.meridian_acupoints };
        }
        if (fixedOrderWaves.length > 0) {
            this._tryRevealFixedOrders(state, t);
            return { acupoints: state.meridian_acupoints || [] };
        }
        const pool = this.getUnlockedOrderPool(state);
        const typeMin = t.count_min ?? 1;
        const typeMax = t.count_max ?? 3;
        if (pool.length === 0) {
            state.meridian_acupoints = [];
            return { acupoints: [] };
        }
        const templateRewards = t.acupoint_rewards;
        const acupoints = [];
        for (let i = 0; i < orderCount; i++) {
            const order = this._genOneAcupoint(pool, typeMin, typeMax);
            if (!order.fixed_order_rewards && templateRewards && order.total_value > 0) {
                order.rewards = this._scaleRewardConfig(templateRewards, order.total_value);
            }
            acupoints.push(order);
        }
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
        const breakthroughRequired = this.getRequiredBreakthroughItems(state.cultivation.current_level, state.cultivation.current_exp).length > 0;
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
                    // not make refresh re-introduce an already completed order.  If an
                    // old save no longer matches the latest config, keep its current
                    // order rather than guessing a wave position.
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
        // A historical flat array is still interpreted as one wave.
        return [configured.filter((order) => order !== null && order !== undefined)];
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
    _genOneAcupoint(pool, typeMin, typeMax) {
        const numTypes = typeMin + Math.floor(Math.random() * (typeMax - typeMin + 1));
        const pickedIds = [];
        const names = [];
        const items = [];
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
    _genFixedAcupoint(fixedOrder) {
        // A fixed order normally contains one item, so config can use the clearer
        // singular item_id.  Keep item_ids/array forms for multi-item and legacy data.
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
        state.unlocked_production_item_ids = state.unlocked_production_item_ids || [];
        if (state.unlocked_production_item_ids.includes(itemId))
            return false;
        state.unlocked_production_item_ids.push(itemId);
        state.unlocked_production_item_ids.sort((a, b) => a - b);
        return true;
    }
    /** Backfill the unlock history for old saves and initialize new saves. */
    initializeProductionUnlocks(state) {
        const previousIds = Array.isArray(state.unlocked_production_item_ids)
            ? state.unlocked_production_item_ids
            : [];
        const normalizedIds = [...new Set(previousIds.filter((id) => Number.isInteger(id)))];
        let changed = !Array.isArray(state.unlocked_production_item_ids) || normalizedIds.length !== previousIds.length;
        state.unlocked_production_item_ids = normalizedIds;
        const grids = [];
        if (Array.isArray(state.grid))
            grids.push(state.grid);
        if (state.saved_grid)
            grids.push(state.saved_grid);
        if (state.battle_grid)
            grids.push(state.battle_grid);
        for (const grid of grids) {
            for (const item of grid) {
                changed = this.registerProductionUnlock(state, item.id) || changed;
                for (const stored of item.craft?._craft_stored || []) {
                    changed = this.registerProductionUnlock(state, Number(stored.id ?? 0)) || changed;
                }
                for (const stored of item.storage?.items || []) {
                    changed = this.registerProductionUnlock(state, Number(stored.id ?? 0)) || changed;
                }
            }
        }
        for (const reward of state.pending_rewards || []) {
            changed = this.registerProductionUnlock(state, reward.id) || changed;
        }
        for (const entry of (state.pouch || [])) {
            const itemId = typeof entry === "number"
                ? entry
                : Number(entry.id ?? 0);
            if (itemId > 0)
                changed = this.registerProductionUnlock(state, itemId) || changed;
        }
        return changed;
    }
    getUnlockedOrderPool(state) {
        const obtainableIds = new Set();
        const regularIds = new Set();
        const byproductIds = new Set();
        const recipeProductIds = new Set();
        const availableRecipes = new Map();
        const cultivationLevel = Number(state.cultivation?.current_level ?? 1);
        const addSpawnMergeChain = (itemId, sourceIds) => {
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
        // Random orders must be producible by facilities currently on the active
        // board. Historical unlocks are intentionally excluded: a facility that
        // was merged, sold, or moved off the board cannot produce new orders.
        const productionIds = [...new Set((state.grid || [])
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
                for (const spawn of production.spawns || []) {
                    const chainKey = getSpawnChainKey(spawn.id);
                    spawnWeightsByChain.set(chainKey, (spawnWeightsByChain.get(chainKey) ?? 0) + Number(spawn.weight));
                }
                const highestChainWeight = Math.max(0, ...spawnWeightsByChain.values());
                const byproductChainKeys = new Set([...spawnWeightsByChain]
                    .filter(([, totalWeight]) => totalWeight < highestChainWeight)
                    .map(([chainKey]) => chainKey));
                for (const spawn of production.spawns || []) {
                    const sourceIds = byproductChainKeys.has(getSpawnChainKey(spawn.id))
                        ? byproductIds
                        : regularIds;
                    addSpawnMergeChain(spawn.id, sourceIds);
                }
                for (const spawnId of production.fixed_spawns || []) {
                    const sourceIds = byproductChainKeys.has(getSpawnChainKey(spawnId))
                        ? byproductIds
                        : regularIds;
                    addSpawnMergeChain(spawnId, sourceIds);
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
        return [...orderIds].sort((a, b) => a - b);
    }
    repairInvalidMeridianOrders(state) {
        if (this.getRequiredBreakthroughItems(state.cultivation.current_level, state.cultivation.current_exp).length > 0) {
            return this.syncBreakthroughOrder(state);
        }
        if (!Array.isArray(state.meridian_acupoints) || state.meridian_acupoints.length === 0)
            return false;
        const threshold = this._findMeridianThreshold(state.cultivation.current_level);
        if (this._getFixedOrderWaves(threshold).length > 0)
            return false;
        const pool = this.getUnlockedOrderPool(state);
        if (pool.length === 0) {
            state.meridian_acupoints = [];
            console.log("[engine] Cleared random meridian orders because the active board has no craftable candidates");
            return true;
        }
        const allowedIds = new Set(pool);
        const hasInvalidOrder = state.meridian_acupoints.some((order) => !Array.isArray(order?.item_ids)
            || order.item_ids.some((itemId) => !allowedIds.has(Number(itemId))));
        if (!hasInvalidOrder)
            return false;
        this.generateMeridianRequirements(state);
        console.log("[engine] Replaced meridian orders containing items outside the current stage pool");
        return true;
    }
    loadInitialSetup(data) {
        // Support both old flat format and new board-type format
        if (data.items) {
            this.initialSetups.set(0, data.items);
        }
        else {
            for (const key of Object.keys(data)) {
                const boardKey = key === "battle" ? 1 : 0;
                this.initialSetups.set(boardKey, data[key].items || []);
            }
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
    getCultivationConfig() {
        return this.cultivation;
    }
    getInitialSetup(boardType = 0) {
        return this.initialSetups.get(boardType) ?? [];
    }
    getMaxCharges(itemId) {
        return this.getItemData(itemId)?.max_charges ?? 3;
    }
    _nextUid(state) {
        state.uid_counter = (state.uid_counter ?? 0) + 1;
        return state.uid_counter;
    }
    getRechargeTime(itemId) {
        return this.getItemData(itemId)?.recharge_time ?? 60;
    }
    // --- Grid helpers ---
    isInBounds(col, row) {
        return col >= 0 && col < this.GRID_COLS && row >= 0 && row < this.GRID_ROWS;
    }
    tickStamina(state) {
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
    getRegenRemainingMs(state) {
        const nextTick = state.last_stamina_tick + this.staminaConfig.regenInterval * 1000;
        return Math.max(0, nextTick - Date.now());
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
        for (const item of state.grid) {
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
        const visited = new Set();
        const queue = [[startCol, startRow]];
        visited.add(this.posKey(startCol, startRow));
        while (queue.length > 0) {
            const [c, r] = queue.shift();
            const key = this.posKey(c, r);
            if (!grid.has(key))
                return { col: c, row: r };
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
                        state.stamina += t.amount;
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
            state.pending_rewards = state.pending_rewards || [];
            for (const ri of rewards.items) {
                const itemData = this.getItemData(ri.id);
                const name = itemData?.name ?? `#${ri.id}`;
                this.registerProductionUnlock(state, ri.id);
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
            spawn_seed: this.createSpawnSeed(),
            spawn_sequence: 0,
            spawn_history: [],
            crafted_item_ids: [],
            unlocked_production_item_ids: [],
        };
        const setup = this.getInitialSetup(boardType);
        const itemNames = [];
        for (const entry of setup) {
            const itemDef = this.getItemData(entry.id);
            if (itemDef) {
                state.uid_counter = (state.uid_counter ?? 0) + 1;
                const gitem = { uid: state.uid_counter, id: entry.id, col: entry.col, row: entry.row };
                if (entry.immovable)
                    gitem.immovable = true;
                if (this.isLauncher(itemDef)) {
                    gitem.charges = this.getMaxCharges(entry.id);
                    gitem.last_charge_time = now;
                }
                state.grid.push(gitem);
                this.registerProductionUnlock(state, entry.id);
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
            if (state.battle_grid && state.battle_grid.length > 0) {
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
    _buildInitialGrid(boardType, state) {
        const setup = this.getInitialSetup(boardType);
        const now = Date.now();
        const grid = [];
        for (const entry of setup) {
            const itemDef = this.getItemData(entry.id);
            if (itemDef) {
                state.uid_counter = (state.uid_counter ?? 0) + 1;
                const gitem = { uid: state.uid_counter, id: entry.id, col: entry.col, row: entry.row };
                if (entry.immovable)
                    gitem.immovable = true;
                if (this.isLauncher(itemDef)) {
                    gitem.charges = this.getMaxCharges(entry.id);
                    gitem.last_charge_time = now;
                }
                grid.push(gitem);
                this.registerProductionUnlock(state, entry.id);
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
        state.crafted_item_ids ??= [];
        if (!state.crafted_item_ids.includes(mergedItem.id)) {
            state.crafted_item_ids.push(mergedItem.id);
        }
        state.version += 1;
        const mergedName = result.resultItem.name;
        const fromItem = this.getItemData(fromId);
        const fromName = fromItem?.name ?? `#${fromId}`;
        console.log(`[engine] merge: ${fromName}x2 -> ${mergedName} | grid=${state.grid.length}/63 | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.MERGE, 1, this);
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
    executeSpawn(state, launcherCol, launcherRow, expectedSequence) {
        const sequence = state.spawn_sequence ?? 0;
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
            let roll = (0, spawn_rng_1.deterministicSpawnRoll)(state.spawn_seed ?? 1, sequence, launcherItem.uid ?? 0, totalWeight);
            rolledId = spawns[0].id;
            for (const s of spawns) {
                if (roll < s.weight) {
                    rolledId = s.id;
                    break;
                }
                roll -= s.weight;
            }
        }
        // Cost check: skip for no_cost launchers, else qi/stamina
        const isBattle = state.board_type === 1;
        if (!launcherData.no_cost) {
            if (isBattle) {
                if (state.cultivation.current_qi < 1) {
                    return { ok: false, reason: "insufficient_qi" };
                }
            }
            else {
                if (state.stamina < this.staminaConfig.spawnCost) {
                    return { ok: false, reason: "insufficient_stamina" };
                }
            }
        }
        const spawnResult = this.getItemData(rolledId);
        if (!spawnResult)
            return { ok: false, reason: "spawn_failed" };
        const target = this.findNearestEmpty(map, launcherCol, launcherRow);
        if (!target)
            return { ok: false, reason: "no_empty_cell" };
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
            }
            else {
                state.stamina = Math.max(0, state.stamina - this.staminaConfig.spawnCost);
            }
        }
        launcherItem.charges = charges - 1;
        launcherItem.last_charge_time = Date.now();
        // Remove launcher if charges depleted and no recharge
        if (launcherItem.charges <= 0 && (launcherData.recharge_time ?? -1) <= 0) {
            state.grid = state.grid.filter((g) => !(g.col === launcherCol && g.row === launcherRow));
            console.log(`[engine] launcher #${launcherItem.id} at (${launcherCol},${launcherRow}) depleted and removed`);
        }
        const newItem = { uid: this._nextUid(state), id: spawnResult.id, col: target.col, row: target.row };
        if (spawnResult.type === 1 || this.isLauncher(spawnResult)) {
            newItem.charges = this.getMaxCharges(spawnResult.id);
            newItem.last_charge_time = Date.now();
        }
        if (launcherData.effect_type === 7) {
            const stage = this.cultivationStages[state.cultivation.current_level - 1];
            const stageAtk = stage?.atk ?? 0;
            newItem.atk_base = stageAtk + (launcherData.value ?? 0);
            console.log(`[engine] spawn: atk_base=${newItem.atk_base} (stageAtk=${stageAtk} + swordValue=${launcherData.value}) effect_type=${launcherData.effect_type}`);
        }
        else {
            console.log(`[engine] spawn: launcher #${launcherItem.id} effect_type=${launcherData.effect_type} — NOT atk boost`);
        }
        state.grid.push(newItem);
        this.registerProductionUnlock(state, newItem.id);
        state.spawn_sequence = sequence + 1;
        state.version += 1;
        console.log(`[engine] spawn: launcher #${launcherItem.id} -> ${spawnResult.name}(#${spawnResult.id}) at (${target.col},${target.row}) | effect_value=${spawnResult.effect_value} atk_base=${newItem.atk_base ?? 0} | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.SPAWN, 1, this);
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
            sequenceUsed: sequence,
            spawnSequence: state.spawn_sequence,
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
        const craftUid = this._nextUid(state);
        if (target) {
            state.grid.push({ uid: craftUid, id: resultId, col: target.col, row: target.row });
            this.registerProductionUnlock(state, resultId);
        }
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
    getStoredItemId(entry) {
        if (typeof entry === "number")
            return entry;
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
        state.meridian_acupoints = [];
        const rewardId = this.getStageBreakthroughReward(level);
        const rewards = rewardId > 0 ? this.applyRewards(state, rewardId) : { tokens: [], items: [] };
        this.generateMeridianRequirements(state);
        state.version += 1;
        const stageName = nextStage?.name ?? `stage_${nextLevel}`;
        console.log(`[engine] breakthrough: -> ${stageName} | consumed=${JSON.stringify([...requiredCounts])} | qi=${newCultivation.max_qi} | v${state.version}`);
        this.questEngine.incrementQuestProgress(state, interface_1.QuestType.BREAKTHROUGH, 1, this);
        return { ok: true, newCultivation, rewards };
    }
    executeTryBreakthrough(state, uid, level, exp) {
        console.log(`[engine] tryBreakthrough: uid=${uid} level=${level} exp=${exp}`);
        if (!this.isBreakthroughReady(level, exp)) {
            console.log(`[engine] tryBreakthrough: not ready (need exp=${this.getExpToNextLevel(level)} have=${exp})`);
            return { ok: false, reason: "not_ready" };
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
        for (const item of state.grid) {
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
    pouchDeposit(state, uid) {
        const idx = state.grid.findIndex((g) => g.uid === uid);
        if (idx < 0)
            return { ok: false, reason: "item_not_found" };
        const itemId = state.grid[idx].id;
        state.grid.splice(idx, 1);
        state.pouch.push({ uid, id: itemId });
        state.version += 1;
        console.log(`[engine] pouch deposit: #${itemId} (uid=${uid}) | pouch=${state.pouch.length} items | v${state.version}`);
        return { ok: true, pouch: state.pouch };
    }
    pouchWithdraw(state, itemId, col, row) {
        const idx = state.pouch.findIndex((p) => p.id === itemId);
        if (idx < 0)
            return { ok: false, reason: "item_not_in_pouch" };
        if (!this.isInBounds(col, row))
            return { ok: false, reason: "invalid_position" };
        if (state.grid.some((g) => g.col === col && g.row === row))
            return { ok: false, reason: "cell_occupied" };
        const entry = state.pouch[idx];
        state.pouch.splice(idx, 1);
        state.grid.push({ uid: entry.uid, id: itemId, col, row });
        state.version += 1;
        console.log(`[engine] pouch withdraw: #${itemId} uid=${entry.uid} at (${col},${row}) | pouch=${state.pouch.length} items | v${state.version}`);
        return { ok: true, pouch: state.pouch, col, row };
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
        state.stamina += amount;
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
    completeMeridianAcupoint(state, index, itemIds) {
        if (!state.meridian_acupoints || index < 0 || index >= state.meridian_acupoints.length) {
            return { ok: false, reason: "invalid_index" };
        }
        const req = state.meridian_acupoints[index];
        if (req.completed)
            return { ok: false, reason: "already_completed" };
        if (req.breakthrough_order === true) {
            return { ok: false, reason: "breakthrough_confirmation_required" };
        }
        // Consume one of each required item from grid
        const toRemove = [];
        for (const reqItemId of itemIds) {
            let found = false;
            for (let i = 0; i < state.grid.length; i++) {
                if (!toRemove.includes(i) && state.grid[i].id === reqItemId && state.grid[i].immovable !== true) {
                    toRemove.push(i);
                    found = true;
                    break;
                }
            }
            if (!found)
                return { ok: false, reason: "insufficient_items" };
        }
        if (state.cultivation.current_qi >= state.cultivation.max_qi) {
            return { ok: false, reason: "qi_full" };
        }
        // Remove consumed items
        for (const idx of toRemove.sort((a, b) => b - a)) {
            state.grid.splice(idx, 1);
        }
        req.completed = true;
        state.version += 1;
        // Order reward — scale by total item value
        const threshold = this.meridianThresholds[state.meridian_threshold_idx ?? 0];
        const totalValue = req.total_value ?? 0;
        let qiGained = 0;
        let qiFull = false;
        let rewardsApplied = { tokens: [], items: [] };
        const orderRewards = req.fixed_order_rewards
            ? this._copyRewardConfig(req.rewards || {})
            : (totalValue > 0 && threshold?.acupoint_rewards
                ? this._scaleRewardConfig(threshold.acupoint_rewards, totalValue)
                : undefined);
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
            const newPool = this.getUnlockedOrderPool(state);
            if (newPool.length > 0) {
                const newTypeMin = newThreshold?.count_min ?? 1;
                const newTypeMax = newThreshold?.count_max ?? 3;
                const newOrder = this._genOneAcupoint(newPool, newTypeMin, newTypeMax);
                if (newThreshold?.acupoint_rewards && newOrder.total_value > 0) {
                    newOrder.rewards = this._scaleRewardConfig(newThreshold.acupoint_rewards, newOrder.total_value);
                }
                state.meridian_acupoints.push(newOrder);
                console.log(`[engine] meridian order #${index} completed, new random order generated`);
            }
            else {
                console.log(`[engine] meridian order #${index} completed, no craftable replacement available`);
            }
        }
        else {
            const revealed = this._tryRevealFixedOrders(state, newThreshold);
            console.log(`[engine] meridian fixed order #${index} completed, next wave revealed: ${revealed}`);
        }
        return { ok: true, newVersion: state.version, meridian_acupoints: state.meridian_acupoints, qi_gained: qiGained, qi_full: qiFull, grid: state.grid, cultivation: state.cultivation, spirit_stones: state.spirit_stones, stamina: state.stamina };
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
        return { ok: true, stones: state.spirit_stones };
    }
    buyItem(state, itemId, targetCol, targetRow) {
        if (!this.isInBounds(targetCol, targetRow))
            return { ok: false, reason: "out_of_bounds" };
        const targetKey = this.posKey(targetCol, targetRow);
        if (state.grid.some(i => this.posKey(i.col, i.row) === targetKey))
            return { ok: false, reason: "target_occupied" };
        const price = this.getBuyPrice(itemId);
        if (price <= 0)
            return { ok: false, reason: "cannot_buy" };
        if (!this.shopConfig.shopItems.some((s) => s.id === itemId))
            return { ok: false, reason: "not_in_shop" };
        if (state.spirit_stones < price)
            return { ok: false, reason: "insufficient_stones" };
        const itemData = this.getItemData(itemId);
        if (!itemData)
            return { ok: false, reason: "item_data_not_found" };
        state.spirit_stones -= price;
        const buyUid = this._nextUid(state);
        state.grid.push({ uid: buyUid, id: itemId, col: targetCol, row: targetRow });
        this.registerProductionUnlock(state, itemId);
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
