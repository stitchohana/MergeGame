"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createGameRouter = createGameRouter;
const http_1 = require("../worker/http");
const auth_1 = require("../middleware/auth");
const queue_1 = require("./queue");
const activity_access_1 = require("../engine/activity_access");
// Operation wrapper: validates params, queues user op, handles errors
function op(handler) {
    return async (req, res) => {
        try {
            const userId = req.auth.userId;
            await (0, queue_1.enqueue)(userId, () => handler(req, res, userId));
        }
        catch (err) {
            console.error("[game] op error:", err);
            if (!res.headersSent) {
                const conflict = err instanceof Error && err.message === "state_conflict";
                res.status(conflict ? 409 : 500).json({ error: conflict ? "state_conflict" : "internal_error" });
            }
        }
    };
}
function createGameRouter(storage, engine, jwtSecret) {
    const router = new http_1.Router();
    router.use((0, auth_1.createAuthRequired)(jwtSecret));
    router.get("/secret_realm", op(async (_req, res, userId) => {
        const state = structuredClone(await getOrCreateState(userId));
        if (engine.secretRealmService.initialize(state))
            await storage.saveState(userId, state);
        res.json({ ok: true, secret_realm: engine.secretRealmService.view(state), storage_revision: state.storage_revision });
    }));
    router.post("/secret_realm/action", op(async (req, res, userId) => {
        const state = structuredClone(await getOrCreateState(userId));
        const result = engine.secretRealmService.transact(state, req.body);
        if (!result.ok) {
            res.status(result.reason === "state_conflict" ? 409 : 400).json({ error: result.reason });
            return;
        }
        if (!result.replayed)
            await storage.saveState(userId, state);
        res.json({ ...result, secret_realm: engine.secretRealmService.view(state), storage_revision: state.storage_revision,
            stamina: state.stamina, max_stamina: state.max_stamina, spirit_stones: state.spirit_stones,
            regen_remaining_ms: engine.getRegenRemainingMs(state), ...staminaMultiplierResponse(state) });
    }));
    router.post("/secret_realm/merge_preview", op(async (req, res, userId) => {
        const state = await getOrCreateState(userId);
        const result = engine.secretRealmService.previewMerge(state, req.body);
        if (!result.ok) {
            res.status(result.reason === "state_conflict" ? 409 : 400).json({ error: result.reason });
            return;
        }
        res.json(result);
    }));
    router.get("/golden_finger", op(async (_req, res, userId) => {
        const state = await getOrCreateState(userId);
        res.json({ ok: true, version: state.version, storage_revision: state.storage_revision,
            golden_finger: engine.goldenFingerService.view(state),
            secret_realm: engine.secretRealmService.view(state),
            materials: engine.goldenFingerService.materialPool(state).map(i => ({ id: i.id, name: i.name, level: i.level, value: i.value })),
            grid: state.grid });
    }));
    router.post("/golden_finger/preview", op(async (req, res, userId) => {
        const state = await getOrCreateState(userId);
        const result = engine.goldenFingerService.preview(state, req.body ?? {});
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        res.json({ ...result, quote: engine.goldenFingerService.quoteKey(result),
            version: state.version, storage_revision: state.storage_revision, golden_finger: engine.goldenFingerService.view(state) });
    }));
    for (const action of ["use", "buy"])
        router.post(`/golden_finger/${action}`, op(async (req, res, userId) => {
            const state = structuredClone(await getOrCreateState(userId));
            const result = engine.goldenFingerService.transact(state, action, req.body);
            if (!result.ok) {
                res.status(result.reason === "state_conflict" ? 409 : 400).json({ error: result.reason });
                return;
            }
            if (!result.replayed)
                await storage.saveState(userId, state);
            engine.enrichGridWithRechargeRemaining(state.grid);
            res.json({ ...result, ...buildStateResponse(state, engine, engine.getRegenRemainingMs(state)) });
        }));
    router.post("/stamina/refresh", op(async (_req, res, userId) => {
        const state = await getOrCreateState(userId);
        res.json({ ok: true, stamina: state.stamina, max_stamina: state.max_stamina,
            regen_remaining_ms: engine.getRegenRemainingMs(state), storage_revision: state.storage_revision,
            ...staminaMultiplierResponse(state) });
    }));
    router.get("/resources/purchase-info", op(async (_req, res, userId) => {
        const state = await getOrCreateState(userId);
        res.json({ ok: true, resource_purchase: engine.resourcePurchaseService.offers(state) });
    }));
    router.post("/resources/buy", op(async (req, res, userId) => {
        const { resource, expected_purchase_count, period_key, request_id } = req.body ?? {};
        if ((resource !== "stamina" && resource !== "qi") || !Number.isSafeInteger(expected_purchase_count)
            || expected_purchase_count < 0 || typeof period_key !== "string" || typeof request_id !== "string") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const updated = structuredClone(await getOrCreateState(userId));
        const result = engine.resourcePurchaseService.buy(updated, resource, expected_purchase_count, period_key, request_id);
        if (!result.ok) {
            res.status(result.reason === "state_conflict" ? 409 : 400).json({ error: result.reason });
            return;
        }
        if (!result.already_purchased)
            await storage.saveState(userId, updated);
        res.json({ ...result, spirit_stones: updated.spirit_stones, stamina: updated.stamina,
            max_stamina: updated.max_stamina, cultivation: updated.cultivation,
            regen_remaining_ms: engine.getRegenRemainingMs(updated), storage_revision: updated.storage_revision,
            ...staminaMultiplierResponse(updated), resource_purchase: engine.resourcePurchaseService.offers(updated) });
    }));
    router.post("/item_catalog/claim", op(async (req, res, userId) => {
        const itemId = req.body?.item_id;
        if (!Number.isSafeInteger(itemId) || itemId <= 0) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const updated = structuredClone(await getOrCreateState(userId));
        const result = engine.claimItemCatalogReward(updated, itemId);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        if (!result.already_claimed) {
            try {
                await storage.saveState(userId, updated);
            }
            catch (error) {
                const conflict = error instanceof Error && error.message === "state_conflict";
                res.status(conflict ? 409 : 500).json({ error: conflict ? "state_conflict" : "save_failed" });
                return;
            }
        }
        res.json({ ...result, item_id: itemId, stamina: updated.stamina, max_stamina: updated.max_stamina,
            regen_remaining_ms: engine.getRegenRemainingMs(updated),
            crafted_item_ids: updated.crafted_item_ids, item_catalog_claimed_ids: updated.item_catalog_claimed_ids,
            storage_revision: updated.storage_revision, ...staminaMultiplierResponse(updated) });
    }));
    router.get("/stair_climb", op(async (_req, res, userId) => {
        const state = await getOrCreateState(userId);
        res.json({ ok: true, stair_climb: await engine.stairClimbService.view(storage, userId, state),
            stamina: state.stamina, spirit_stones: state.spirit_stones, stair_climb_progress: state.stair_climb_progress ?? {},
            ...staminaMultiplierResponse(state), storage_revision: state.storage_revision });
    }));
    function duelResponse(res, state, view) {
        if (view.error) {
            res.status(view.error === "state_conflict" ? 409 : 400).json({ error: view.error });
            return;
        }
        res.json({ ok: true, order_duel: view, stamina: state.stamina, max_stamina: state.max_stamina,
            spirit_stones: state.spirit_stones, storage_revision: state.storage_revision,
            regen_remaining_ms: engine.getRegenRemainingMs(state), ...staminaMultiplierResponse(state) });
    }
    router.get("/order_duel", op(async (_req, res, userId) => {
        const state = await getOrCreateState(userId);
        const view = await engine.orderDuelService.refresh(storage, userId, state, r => engine.applyRewards(state, r));
        duelResponse(res, state, view);
    }));
    for (const action of ["start", "rest", "claim"]) {
        router.post(`/order_duel/${action}`, op(async (req, res, userId) => {
            const value = action === "claim" ? req.body?.tier : req.body?.expected_round;
            if (!Number.isSafeInteger(value) || value < (action === "claim" ? 1 : 0)) {
                res.status(400).json({ error: "invalid_params" });
                return;
            }
            const state = await getOrCreateState(userId);
            const apply = (r) => engine.applyRewards(state, r);
            const service = engine.orderDuelService;
            await service.refresh(storage, userId, state, apply);
            const view = action === "start" ? await service.start(storage, userId, state, value, apply)
                : action === "rest" ? await service.rest(storage, userId, state, value)
                    : await service.claim(storage, userId, state, value, apply);
            duelResponse(res, state, view);
        }));
    }
    for (const action of ["open", "exchange"]) {
        router.post(`/card_collection/${action}`, op(async (req, res, userId) => {
            const { collection_id, pack_uid, open_all = false, request_id, expected_opened_count, expected_exchange_count } = req.body ?? {};
            if (!Number.isSafeInteger(collection_id) || collection_id <= 0 || (action !== "exchange" && (!Number.isSafeInteger(pack_uid) || pack_uid <= 0)) || typeof request_id !== "string" || !request_id.trim() || request_id.length > 100 ||
                (action === "exchange" && (!Number.isSafeInteger(expected_exchange_count) || expected_exchange_count < 0)) ||
                (action === "open" && (typeof open_all !== "boolean" || !Number.isSafeInteger(expected_opened_count) || expected_opened_count < 0))) {
                res.status(400).json({ error: "invalid_params" });
                return;
            }
            const updated = structuredClone(await getOrCreateState(userId));
            const service = engine.cardCollectionService;
            const result = action === "open"
                ? service.openPending(updated, collection_id, pack_uid, open_all, request_id, expected_opened_count)
                : service.exchange(updated, collection_id, request_id, expected_exchange_count);
            if (!result.ok) {
                res.status(result.reason === "state_conflict" ? 409 : 400).json({ error: result.reason });
                return;
            }
            try {
                await storage.saveState(userId, updated);
            }
            catch (error) {
                const conflict = error instanceof Error && error.message === "state_conflict";
                res.status(conflict ? 409 : 500).json({ error: conflict ? "state_conflict" : "save_failed" });
                return;
            }
            res.json({ ...result, spirit_stones: updated.spirit_stones, stamina: updated.stamina, storage_revision: updated.storage_revision, pending_rewards: updated.pending_rewards, card_collection_progress: engine.cardCollectionService.publicProgress(updated), ...staminaMultiplierResponse(updated) });
        }));
    }
    function staminaMultiplierResponse(state) {
        const multiplier = engine.getStaminaMultiplierState(state);
        return {
            stamina_multiplier_max: multiplier.maxMultiplier,
            stamina_multiplier_expires_at: multiplier.expiresAt,
            stamina_multiplier_remaining_seconds: multiplier.remainingSeconds,
        };
    }
    async function getOrCreateState(userId) {
        let state = await storage.loadState(userId);
        if (!state) {
            state = engine.createInitialState();
            await storage.saveState(userId, state);
            console.log(`[game] new player ${userId}, init with ${state.grid.length} items | v0`);
        }
        else {
            const craftingChanged = engine.tickCraftingState(state);
            const staminaChanged = engine.tickStamina(state);
            const multiplierChanged = engine.tickStaminaMultiplier(state);
            engine.tickLauncherRecharge(state);
            if (craftingChanged || staminaChanged || multiplierChanged) {
                await storage.saveState(userId, state);
            }
        }
        if ((0, activity_access_1.activitiesUnlocked)(state)) {
            const battlePassBefore = JSON.stringify(state.battle_pass_progress ?? {});
            const battlePassState = structuredClone(state);
            engine.battlePassService.ensureProgress(battlePassState);
            const battlePassSettled = engine.battlePassService.settleExpired(battlePassState, rewards => engine.applyRewards(battlePassState, rewards));
            if (battlePassBefore !== JSON.stringify(battlePassState.battle_pass_progress) || battlePassSettled) {
                await storage.saveState(userId, battlePassState);
                state = battlePassState;
            }
            const stair = engine.stairClimbService;
            const enrolled = await stair.enroll(storage, userId, state);
            const settled = await stair.settlePlayer(storage, userId, state, reward => engine.applyRewards(state, reward));
            if (enrolled || settled)
                await storage.saveState(userId, state);
            const questInitModified = engine.questEngine.initQuestProgress(state);
            const questResetOccurred = engine.questEngine.checkAndResetQuests(state, engine.questResetHour);
            const weeklyChanged = engine.weeklyTaskService.ensureProgress(state);
            const activitiesBefore = JSON.stringify(state.activity_progress ?? {});
            engine.activityEngine.initProgress(state);
            engine.activityEngine.checkAndReset(state, engine.questResetHour);
            if (questInitModified || questResetOccurred || weeklyChanged || activitiesBefore !== JSON.stringify(state.activity_progress)) {
                await storage.saveState(userId, state);
            }
        }
        return state;
    }
    function buildStateResponse(state, engine, regenRemainingMs) {
        const isBattle = state.board_type === 1;
        const mainGrid = isBattle ? (state.saved_grid) : state.grid;
        const battleGrid = isBattle ? state.grid : (state.battle_grid?.length ? state.battle_grid : []);
        console.log(`[game] buildStateResponse: board_type=${state.board_type} isBattle=${isBattle} saved_grid=${state.saved_grid?.length ?? 0} battle_grid_cache=${state.battle_grid?.length ?? 0} mainGrid=${mainGrid.length} battleGrid=${battleGrid.length} grid=${state.grid.length}`);
        return {
            grid: state.grid,
            golden_finger: engine.goldenFingerService.view(state),
            secret_realm: engine.secretRealmService.view(state),
            version: state.version,
            main_grid: mainGrid,
            battle_grid: battleGrid,
            pouch: state.pouch,
            ...engine.getPouchState(state),
            cultivation: state.cultivation,
            stamina: state.stamina,
            max_stamina: state.max_stamina,
            ...staminaMultiplierResponse(state),
            spirit_stones: state.spirit_stones,
            regen_remaining_ms: regenRemainingMs,
            battle_map_id: state.battle_map_id,
            battle_stage: state.battle_stage,
            meridian_acupoints: state.meridian_acupoints,
            meridian_circulations: state.meridian_circulations,
            meridian_threshold_idx: state.meridian_threshold_idx,
            quest_progress: (0, activity_access_1.activitiesUnlocked)(state) ? state.quest_progress : {}, weekly_task_progress: engine.weeklyTaskService.publicProgress(state), card_collection_progress: (0, activity_access_1.activitiesUnlocked)(state) ? engine.cardCollectionService.publicProgress(state) : {},
            quest_defs: (0, activity_access_1.activitiesUnlocked)(state) ? engine.questEngine.getResolvedQuestDefs(engine) : [], home_meridian_defs: engine.getHomeMeridianDefs(),
            weekly_task_defs: (0, activity_access_1.activitiesUnlocked)(state) ? engine.weeklyTaskService.definitions : [],
            activity_defs: (0, activity_access_1.activitiesUnlocked)(state) ? engine.activityEngine.getActivities().map(a => ({ ...a, active: engine.activityEngine.isActive(a),
                result_available: (a.widget === "StairClimb" && !!engine.stairClimbService.score(state)) ||
                    (a.widget === "OrderDuel" && (state.order_duel_progress?.victory_points ?? 0) > 0) })) : [],
            stair_climb_progress: (0, activity_access_1.activitiesUnlocked)(state) ? state.stair_climb_progress ?? {} : {},
            activity_progress: (0, activity_access_1.activitiesUnlocked)(state) ? state.activity_progress : {},
            card_collection_config: (0, activity_access_1.activitiesUnlocked)(state) ? engine.cardCollectionService.config : { collections: [], card_sets: [], cards: [], packs: [], source_rewards: [] },
            battle_pass_progress: (0, activity_access_1.activitiesUnlocked)(state) ? engine.battlePassService.ensureProgress(state) : {},
            activities_unlocked: (0, activity_access_1.activitiesUnlocked)(state),
            spawn_seed: state.spawn_seed,
            spawn_sequence: state.spawn_sequence,
            crafted_item_ids: state.crafted_item_ids,
            item_catalog_claimed_ids: state.item_catalog_claimed_ids,
            unlocked_production_item_ids: state.unlocked_production_item_ids,
            activity_current_day: (() => {
                if (!(0, activity_access_1.activitiesUnlocked)(state))
                    return 0;
                const active = engine.activityEngine.getActivities().find((a) => engine.activityEngine.isActive(a) && engine.activityEngine.hasWeeklyTasks(a.id));
                return active ? engine.activityEngine.getCurrentDay(active.id, engine.questResetHour) : 0;
            })(),
            storage_revision: state.storage_revision, pending_rewards: state.pending_rewards, home_meridian_progress: state.home_meridian_progress
        };
    }
    // GET /api/game/state
    router.get("/state", async (req, res) => {
        try {
            const userId = req.auth.userId;
            await (0, queue_1.enqueue)(userId, async () => {
                const state = await getOrCreateState(userId);
                // Keep the entire read/settlement/save inside the user queue, so a
                // concurrent action cannot overwrite a weekly reset or its timestamp.
                if (state.board_type !== 1 && state.saved_grid) {
                    state.grid = state.saved_grid;
                    state.saved_grid = undefined;
                    await storage.saveState(userId, state);
                    console.log(`[game] restored main grid for ${userId}: ${state.grid.length} items`);
                }
                const regenRemainingMs = engine.getRegenRemainingMs(state);
                engine.enrichGridWithRechargeRemaining(state.grid);
                console.log(`[game] state response: grid=${state.grid.length} items, first uid=${state.grid[0]?.uid ?? "missing"}`);
                const order_duel = await engine.orderDuelService.refresh(storage, userId, state, r => engine.applyRewards(state, r));
                res.json({ ...buildStateResponse(state, engine, regenRemainingMs), order_duel });
            });
        }
        catch (err) {
            console.error("[game] state error:", err);
            res.status(500).json({ error: "internal_error" });
        }
    });
    // POST /api/game/merge
    router.post("/merge", op(async (req, res, userId) => {
        const { from, to } = req.body;
        if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.executeMerge(state, from[0], from[1], to[0], to[1]);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, result_uid: result.resultUid, result_id: result.resultId, atk_base: result.atkBase ?? 0, from_col: result.fromCol, from_row: result.fromRow, to_col: result.toCol, to_row: result.toRow, regen_remaining_ms: engine.getRegenRemainingMs(state), quest_progress: state.quest_progress, weekly_task_progress: engine.weeklyTaskService.publicProgress(state), card_collection_progress: engine.cardCollectionService.publicProgress(state), crafted_item_ids: state.crafted_item_ids, storage_revision: state.storage_revision, pending_rewards: state.pending_rewards, activity_progress: state.activity_progress });
    }));
    // POST /api/game/actions/batch
    router.post("/actions/batch", op(async (req, res, userId) => {
        const { operations } = req.body;
        if (!Array.isArray(operations) || operations.length < 1 || operations.length > 32) {
            res.status(400).json({ error: "invalid_operations" });
            return;
        }
        const state = await getOrCreateState(userId);
        const workingState = structuredClone(state);
        const results = [];
        for (let index = 0; index < operations.length; index++) {
            const operation = operations[index];
            const from = operation?.from;
            const to = operation?.to;
            if (!operation || !["move", "merge", "push_place", "craft_add", "craft_remove"].includes(operation.type)
                || !Array.isArray(from) || from.length !== 2
                || !Array.isArray(to) || to.length !== 2
                || !from.every(Number.isInteger) || !to.every(Number.isInteger)) {
                res.status(400).json({ error: "invalid_operation", failed_index: index, grid: state.grid });
                return;
            }
            if (operation.type === "move") {
                const result = engine.executeMove(workingState, from[0], from[1], to[0], to[1]);
                if (!result.ok) {
                    res.status(409).json({ error: result.reason, failed_index: index, grid: state.grid });
                    return;
                }
                results.push({ type: "move", from, to, new_version: result.newVersion });
                continue;
            }
            if (operation.type === "push_place") {
                const result = engine.pushAndPlace(workingState, from[0], from[1], to[0], to[1]);
                if (!result.ok) {
                    res.status(409).json({ error: result.reason, failed_index: index, grid: state.grid });
                    return;
                }
                results.push({
                    type: "push_place",
                    from,
                    to,
                    pushed_col: result.pushed_col,
                    pushed_row: result.pushed_row,
                    new_version: result.newVersion,
                });
                continue;
            }
            if (operation.type === "craft_add") {
                if (!Number.isInteger(operation.ingredient_id)) {
                    res.status(400).json({ error: "invalid_operation", failed_index: index, grid: state.grid });
                    return;
                }
                const result = engine.addIngredientToTable(workingState, to[0], to[1], operation.ingredient_id, from[0], from[1]);
                if (!result.ok) {
                    res.status(409).json({ error: result.reason, failed_index: index, grid: state.grid });
                    return;
                }
                results.push({ type: "craft_add", from, to, ingredient_id: operation.ingredient_id, new_version: result.newVersion });
                continue;
            }
            if (operation.type === "craft_remove") {
                if (!Number.isInteger(operation.ingredient_id)) {
                    res.status(400).json({ error: "invalid_operation", failed_index: index, grid: state.grid });
                    return;
                }
                const result = engine.removeIngredientFromTable(workingState, from[0], from[1], operation.ingredient_id, to[0], to[1]);
                if (!result.ok) {
                    res.status(409).json({ error: result.reason, failed_index: index, grid: state.grid });
                    return;
                }
                results.push({
                    type: "craft_remove", from, to, ingredient_id: operation.ingredient_id,
                    removed_uid: result.removed_uid, new_version: result.newVersion,
                });
                continue;
            }
            const result = engine.executeMerge(workingState, from[0], from[1], to[0], to[1]);
            if (!result.ok) {
                res.status(409).json({ error: result.reason, failed_index: index, grid: state.grid });
                return;
            }
            results.push({
                type: "merge",
                from,
                to,
                result_uid: result.resultUid,
                result_id: result.resultId,
                atk_base: result.atkBase ?? 0,
                new_version: result.newVersion,
            });
        }
        await storage.saveState(userId, workingState);
        res.json({
            ok: true,
            results,
            grid: workingState.grid,
            stamina: workingState.stamina,
            cultivation: workingState.cultivation,
            regen_remaining_ms: engine.getRegenRemainingMs(workingState),
            quest_progress: workingState.quest_progress, weekly_task_progress: engine.weeklyTaskService.publicProgress(workingState),
            activity_progress: workingState.activity_progress,
            card_collection_progress: engine.cardCollectionService.publicProgress(workingState),
            crafted_item_ids: workingState.crafted_item_ids,
            storage_revision: workingState.storage_revision, pending_rewards: workingState.pending_rewards,
        });
    }));
    // POST /api/game/spawn
    router.post("/spawn", op(async (req, res, userId) => {
        const { launcher_pos, request_id, expected_sequence, predicted_id, predicted_target, predicted_items, stamina_multiplier } = req.body;
        if (!Array.isArray(launcher_pos) || launcher_pos.length !== 2) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        if (!engine.isInBounds(launcher_pos[0], launcher_pos[1])) {
            res.status(400).json({ error: "out_of_bounds" });
            return;
        }
        if (request_id !== undefined && (typeof request_id !== "string" || !/^[A-Za-z0-9._:-]{1,96}$/.test(request_id))) {
            res.status(400).json({ error: "invalid_request_id" });
            return;
        }
        if (expected_sequence !== undefined && (!Number.isInteger(expected_sequence) || expected_sequence < 0)) {
            res.status(400).json({ error: "invalid_spawn_sequence" });
            return;
        }
        if (stamina_multiplier !== undefined && (!Number.isInteger(stamina_multiplier) || stamina_multiplier < 1)) {
            res.status(400).json({ error: "invalid_stamina_multiplier" });
            return;
        }
        const state = await getOrCreateState(userId);
        const cached = request_id ? state.spawn_history.find(entry => entry.request_id === request_id) : undefined;
        if (cached?.result.reverted) {
            res.status(409).json({ error: "operation_reverted", request_id });
            return;
        }
        const result = cached?.result ?? engine.executeSpawn(state, launcher_pos[0], launcher_pos[1], expected_sequence, stamina_multiplier ?? 1);
        if (!result.ok) {
            res.status(result.reason === "spawn_sequence_mismatch" ? 409 : 400).json({
                error: result.reason,
                request_id,
                spawn_seed: state.spawn_seed,
                spawn_sequence: state.spawn_sequence,
            });
            return;
        }
        if (!cached && request_id) {
            state.spawn_history.push({ request_id, result: { ...result } });
            if (state.spawn_history.length > 32)
                state.spawn_history.splice(0, state.spawn_history.length - 32);
        }
        const hasBatchPrediction = Array.isArray(predicted_items);
        const hasSinglePrediction = Number.isInteger(predicted_id)
            && Array.isArray(predicted_target)
            && predicted_target.length === 2;
        const predictionMatches = hasBatchPrediction
            ? predicted_items.length === result.spawnedItems.length
                && predicted_items.every((prediction, index) => {
                    const spawned = result.spawnedItems[index];
                    return Number(prediction?.id) === spawned.id
                        && Array.isArray(prediction?.target)
                        && prediction.target[0] === spawned.targetCol
                        && prediction.target[1] === spawned.targetRow;
                })
            : !hasSinglePrediction || (result.spawnedItems.length === 1
                && predicted_id === result.spawnedId
                && predicted_target[0] === result.targetCol
                && predicted_target[1] === result.targetRow);
        await storage.saveState(userId, state);
        const staminaMultiplierState = engine.getStaminaMultiplierState(state);
        res.json({
            ok: true,
            request_id,
            replayed: Boolean(cached),
            prediction_matches: predictionMatches,
            spawned_uid: result.spawnedUid,
            spawned_id: result.spawnedId,
            spawned_name: result.spawnedName,
            spawned_items: result.spawnedItems.map((item) => ({
                uid: item.uid,
                id: item.id,
                name: item.name,
                target_col: item.targetCol,
                target_row: item.targetRow,
                atk_base: item.atkBase,
                stamina_units: item.staminaUnits,
            })),
            target_col: result.targetCol,
            target_row: result.targetRow,
            stamina: state.stamina,
            max_stamina: state.max_stamina,
            stamina_cost: result.staminaCost,
            stamina_multiplier: result.staminaMultiplier,
            requested_stamina_multiplier: result.requestedStaminaMultiplier,
            stamina_refund: result.staminaRefund,
            order_priority: result.orderPriority,
            stamina_multiplier_max: staminaMultiplierState.maxMultiplier,
            stamina_multiplier_expires_at: staminaMultiplierState.expiresAt,
            stamina_multiplier_remaining_seconds: staminaMultiplierState.remainingSeconds,
            charges: result.charges,
            max_charges: result.maxCharges,
            recharge_time: result.rechargeTime,
            atk_base: result.atkBase,
            cultivation: state.cultivation,
            regen_remaining_ms: engine.getRegenRemainingMs(state),
            quest_progress: state.quest_progress, weekly_task_progress: engine.weeklyTaskService.publicProgress(state), card_collection_progress: engine.cardCollectionService.publicProgress(state),
            spawn_seed: state.spawn_seed,
            spawn_sequence: state.spawn_sequence,
            sequence_used: result.sequenceUsed,
            activity_progress: state.activity_progress,
            storage_revision: state.storage_revision, pending_rewards: state.pending_rewards,
            ...(predictionMatches ? {} : { grid: state.grid }),
        });
    }));
    // POST /api/game/craft/add
    router.post("/craft/add", op(async (req, res, userId) => {
        const { table_col, table_row, ingredient_id, from_col, from_row } = req.body;
        if (typeof table_col !== "number" || typeof table_row !== "number" || typeof ingredient_id !== "number" || typeof from_col !== "number" || typeof from_row !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.addIngredientToTable(state, table_col, table_row, ingredient_id, from_col, from_row);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, matched: result.matched });
    }));
    // POST /api/game/craft/start
    router.post("/craft/start", op(async (req, res, userId) => {
        const { table_col, table_row } = req.body;
        if (typeof table_col !== "number" || typeof table_row !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.executeCraftStart(state, table_col, table_row);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, recipe_id: result.recipe.id, craft_time: result.recipe.craft_time,
            activity_progress: state.activity_progress, storage_revision: state.storage_revision });
    }));
    // POST /api/game/craft/speedup
    router.post("/craft/speedup", op(async (req, res, userId) => {
        const { table_col, table_row } = req.body;
        if (typeof table_col !== "number" || typeof table_row !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.executeCraftSpeedup(state, table_col, table_row);
        if (!result.ok) {
            res.status(400).json({
                error: result.reason,
                required_stones: result.cost,
                remaining_seconds: result.remainingSeconds,
                spirit_stones: result.spiritStones,
            });
            return;
        }
        await storage.saveState(userId, state);
        engine.enrichGridWithRechargeRemaining(state.grid);
        res.json({ ok: true, table_col, table_row, cost: result.cost, remaining_seconds: result.remainingSeconds, spirit_stones: state.spirit_stones, grid: state.grid });
    }));
    // POST /api/game/craft/retrieve
    router.post("/craft/retrieve", op(async (req, res, userId) => {
        const { table_col, table_row } = req.body;
        if (typeof table_col !== "number" || typeof table_row !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.executeCraftRetrieve(state, table_col, table_row);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, result_uid: result.resultUid, result_id: result.resultId, quest_progress: state.quest_progress, weekly_task_progress: engine.weeklyTaskService.publicProgress(state), card_collection_progress: engine.cardCollectionService.publicProgress(state), storage_revision: state.storage_revision, pending_rewards: state.pending_rewards });
    }));
    // POST /api/game/craft/remove
    router.post("/craft/remove", op(async (req, res, userId) => {
        const { table_col, table_row, uid, target_col, target_row } = req.body;
        if (typeof table_col !== "number" || typeof table_row !== "number" || typeof uid !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.removeIngredientFromTable(state, table_col, table_row, uid, target_col, target_row);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        engine.enrichGridWithRechargeRemaining(state.grid);
        res.json({ ok: true, removed_id: result.removed_id, removed_uid: result.removed_uid, table_col: result.table_col, table_row: result.table_row, target_col: result.target_col, target_row: result.target_row, grid: state.grid });
    }));
    // POST /api/game/launcher/speedup
    router.post("/launcher/speedup", op(async (req, res, userId) => {
        const { uid } = req.body;
        if (typeof uid !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.executeLauncherSpeedup(state, uid);
        if (!result.ok) {
            res.status(400).json({
                error: result.reason,
                required_stones: result.cost,
                remaining_seconds: result.remainingSeconds,
                spirit_stones: result.spiritStones,
            });
            return;
        }
        await storage.saveState(userId, state);
        engine.enrichGridWithRechargeRemaining(state.grid);
        res.json({ ok: true, uid, cost: result.cost, remaining_seconds: result.remainingSeconds, charges: result.charges, max_charges: result.maxCharges, spirit_stones: state.spirit_stones, grid: state.grid });
    }));
    // POST /api/game/push_place
    router.post("/push_place", op(async (req, res, userId) => {
        const { from, to } = req.body;
        if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        console.log(`[game] push_place: from=(${from[0]},${from[1]}) to=(${to[0]},${to[1]})`);
        const result = engine.pushAndPlace(state, from[0], from[1], to[0], to[1]);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, pushed_col: result.pushed_col, pushed_row: result.pushed_row, from_col: result.from_col, from_row: result.from_row, to_col: result.to_col, to_row: result.to_row });
    }));
    // POST /api/game/move
    router.post("/move", op(async (req, res, userId) => {
        const { from, to } = req.body;
        if (!Array.isArray(from) || from.length !== 2 || !Array.isArray(to) || to.length !== 2) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.executeMove(state, from[0], from[1], to[0], to[1]);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, grid: state.grid });
    }));
    // POST /api/game/shop/sell
    router.post("/shop/sell", op(async (req, res, userId) => {
        const { uid } = req.body;
        if (typeof uid !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.sellItem(state, uid);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, spirit_stones: result.stones, quest_progress: state.quest_progress, weekly_task_progress: engine.weeklyTaskService.publicProgress(state), card_collection_progress: engine.cardCollectionService.publicProgress(state), storage_revision: state.storage_revision, pending_rewards: state.pending_rewards });
    }));
    // POST /api/game/shop/buy
    router.post("/shop/buy", op(async (req, res, userId) => {
        const { item_id, target_col, target_row, shop_revision } = req.body;
        if (!Number.isSafeInteger(item_id) || !Number.isSafeInteger(target_col) || !Number.isSafeInteger(target_row)
            || (shop_revision !== undefined && !Number.isSafeInteger(shop_revision))) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = structuredClone(await getOrCreateState(userId));
        const now = Date.now();
        const result = engine.buyItem(state, item_id, target_col, target_row, shop_revision, now);
        if (!result.ok) {
            res.status(result.reason === "shop_changed" ? 409 : 400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, uid: result.uid, item_id, target_col, target_row, spirit_stones: result.stones,
            shop: engine.shopService.view(state, now) });
    }));
    // GET /api/game/shop/items
    router.get("/shop/items", op(async (_req, res, userId) => {
        const state = structuredClone(await getOrCreateState(userId));
        const now = Date.now();
        if (engine.shopService.ensure(state, now))
            await storage.saveState(userId, state);
        res.json({ ok: true, spirit_stones: state.spirit_stones, ...engine.shopService.view(state, now) });
    }));
    router.post("/shop/refresh", op(async (req, res, userId) => {
        const revision = req.body?.shop_revision;
        if (!Number.isSafeInteger(revision) || revision < 1) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = structuredClone(await getOrCreateState(userId));
        const now = Date.now();
        const result = engine.shopService.refresh(state, revision, now);
        if (!result.ok) {
            res.status(result.reason === "shop_changed" ? 409 : 400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, spirit_stones: state.spirit_stones, ...engine.shopService.view(state, now) });
    }));
    // POST /api/game/storage/deposit
    router.post("/storage/deposit", op(async (req, res, userId) => {
        const { storage_col, storage_row, uid, from_col, from_row } = req.body;
        if (typeof storage_col !== "number" || typeof storage_row !== "number" || typeof uid !== "number" || typeof from_col !== "number" || typeof from_row !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.depositItem(state, storage_col, storage_row, uid, from_col, from_row);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        engine.enrichGridWithRechargeRemaining(state.grid);
        res.json({ ok: true, grid: state.grid });
    }));
    // POST /api/game/storage/withdraw
    router.post("/storage/withdraw", op(async (req, res, userId) => {
        const { storage_col, storage_row, uid, target_col, target_row } = req.body;
        if (typeof storage_col !== "number" || typeof storage_row !== "number" || typeof uid !== "number" || typeof target_col !== "number" || typeof target_row !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.withdrawItem(state, storage_col, storage_row, uid, target_col, target_row);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        const storageItem = state.grid.find(i => i.col === storage_col && i.row === storage_row);
        engine.enrichGridWithRechargeRemaining(state.grid);
        res.json({ ok: true, storage: storageItem?.storage ?? null, uid: result.uid, col: result.col, row: result.row });
    }));
    // POST /api/game/meridian/refresh
    router.post("/meridian/refresh", op(async (req, res, userId) => {
        const state = await getOrCreateState(userId);
        const result = engine.generateMeridianRequirements(state);
        await storage.saveState(userId, state);
        res.json({ ok: true, acupoints: result.acupoints, threshold_idx: state.meridian_threshold_idx });
    }));
    // POST /api/game/meridian/complete
    router.post("/meridian/complete", op(async (req, res, userId) => {
        const { index, item_ids, request_id } = req.body;
        if (typeof index !== "number" || !Array.isArray(item_ids)) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        if (request_id !== undefined && (typeof request_id !== "string" || request_id.length > 100)) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        let state = await getOrCreateState(userId);
        // Reconcile the previous round before scoring this order; its points cannot leak into the next round.
        await engine.orderDuelService.refresh(storage, userId, state, r => engine.applyRewards(state, r));
        state = structuredClone(state);
        const result = engine.completeMeridianAcupoint(state, index, item_ids, request_id ?? "");
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        const order_duel = await engine.orderDuelService.refresh(storage, userId, state, r => engine.applyRewards(state, r));
        res.json({ ...result, secret_realm: engine.secretRealmService.view(state), stamina: state.stamina, spirit_stones: state.spirit_stones, order_duel,
            activity_progress: state.activity_progress, stair_climb_progress: state.stair_climb_progress ?? {}, quest_progress: state.quest_progress, weekly_task_progress: engine.weeklyTaskService.publicProgress(state), storage_revision: state.storage_revision, pending_rewards: state.pending_rewards, card_collection_progress: engine.cardCollectionService.publicProgress(state), ...staminaMultiplierResponse(state) });
    }));
    // POST /api/game/board/switch
    router.post("/board/switch", op(async (req, res, userId) => {
        const { board_type } = req.body;
        if (typeof board_type !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.switchBoard(state, board_type, req.body.map_id, req.body.stage);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        if (board_type === 1)
            engine.initBattleMonsters(state);
        engine.enrichGridWithRechargeRemaining(state.grid);
        res.json({ ok: true, board_type: board_type, grid: state.grid, monsters: state.battle_monsters, battle_map_id: state.battle_map_id, battle_stage: state.battle_stage });
    }));
    // POST /api/game/pouch/unlock
    router.post("/pouch/unlock", op(async (req, res, userId) => {
        const expectedCapacity = req.body?.expected_capacity;
        if (!Number.isSafeInteger(expectedCapacity) || expectedCapacity <= 0) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = structuredClone(await getOrCreateState(userId));
        const result = engine.pouchUnlock(state, expectedCapacity);
        if (!result.ok) {
            res.status(result.reason === "state_conflict" ? 409 : 400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ...result, ...engine.getPouchState(state), spirit_stones: state.spirit_stones, storage_revision: state.storage_revision });
    }));
    // POST /api/game/pouch/deposit
    router.post("/pouch/deposit", op(async (req, res, userId) => {
        const { uid } = req.body;
        if (typeof uid !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.pouchDeposit(state, uid);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, pouch: result.pouch, ...engine.getPouchState(state) });
    }));
    // POST /api/game/pouch/withdraw
    router.post("/pouch/withdraw", op(async (req, res, userId) => {
        const { uid } = req.body;
        if (typeof uid !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const pouchEntry = state.pouch.find((p) => p.uid === uid);
        if (!pouchEntry) {
            res.status(400).json({ error: "item_not_in_pouch" });
            return;
        }
        const empty = engine.findEmptyPos(state.grid);
        if (!empty) {
            res.status(400).json({ error: "grid_full" });
            return;
        }
        const result = engine.pouchWithdraw(state, uid, empty.col, empty.row);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        engine.enrichGridWithRechargeRemaining([result.item]);
        res.json({ ok: true, pouch: result.pouch, ...engine.getPouchState(state), item: result.item, col: result.col, row: result.row });
    }));
    // POST /api/battle/attack
    router.post("/battle/heal", op(async (req, res, userId) => {
        const { item_id, effect_id, uid } = req.body;
        if (typeof item_id !== "number" || typeof effect_id !== "number" || typeof uid !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.battleHeal(state, item_id, uid, effect_id);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, grid: result.grid });
    }));
    router.post("/battle/attack", op(async (req, res, userId) => {
        const { item_id, effect_id, uid, col, row } = req.body;
        if (typeof item_id !== "number" || typeof effect_id !== "number" || typeof uid !== "number" || typeof col !== "number" || typeof row !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.battleAttack(state, item_id, effect_id, uid, col, row);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ok: true, grid: result.grid, monsters: result.monsters, stage_complete: result.stage_complete, loot: result.loot, battle_stage: state.battle_stage, quest_progress: state.quest_progress, weekly_task_progress: engine.weeklyTaskService.publicProgress(state), card_collection_progress: engine.cardCollectionService.publicProgress(state), cultivation: state.cultivation, spirit_stones: state.spirit_stones, stamina: state.stamina, storage_revision: state.storage_revision, pending_rewards: state.pending_rewards, ...staminaMultiplierResponse(state) });
    }));
    // POST /api/game/weekly_tasks/claim
    router.post("/weekly_tasks/claim", op(async (req, res, userId) => {
        const { activity_id, stage, period_key } = req.body ?? {};
        if (!Number.isSafeInteger(activity_id) || activity_id <= 0 || !Number.isSafeInteger(stage) || stage <= 0
            || typeof period_key !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(period_key)) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const updated = structuredClone(await getOrCreateState(userId));
        const result = engine.weeklyTaskService.claim(updated, activity_id, stage, period_key, rewards => engine.applyRewards(updated, rewards));
        if (!result.ok) {
            res.status(result.reason === "state_conflict" ? 409 : 400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, updated);
        res.json({ ...result, activity_id, stage, stamina: updated.stamina, max_stamina: updated.max_stamina,
            regen_remaining_ms: engine.getRegenRemainingMs(updated), storage_revision: updated.storage_revision,
            weekly_task_progress: engine.weeklyTaskService.publicProgress(updated), pending_rewards: updated.pending_rewards,
            ...staminaMultiplierResponse(updated) });
    }));
    // POST /api/game/quest_claim
    router.post("/quest_claim", op(async (req, res, userId) => {
        const { quest_id } = req.body;
        if (typeof quest_id !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.questEngine.claimQuestReward(state, quest_id, engine);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        engine.enrichGridWithRechargeRemaining(state.grid);
        res.json({ ok: true, quest_id, rewards: result.rewards, cultivation: state.cultivation, spirit_stones: state.spirit_stones, stamina: state.stamina, grid: state.grid, pouch: state.pouch, quest_progress: state.quest_progress, weekly_task_progress: engine.weeklyTaskService.publicProgress(state), card_collection_progress: engine.cardCollectionService.publicProgress(state), storage_revision: state.storage_revision, pending_rewards: state.pending_rewards, ...staminaMultiplierResponse(state) });
    }));
    // POST /api/game/claim_pending_reward
    router.post("/claim_pending_reward", op(async (req, res, userId) => {
        const { uid } = req.body;
        if (typeof uid !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.questEngine.claimPendingReward(state, uid, engine);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        engine.enrichGridWithRechargeRemaining(state.grid);
        res.json({ ok: true, col: result.col, row: result.row, grid: state.grid, storage_revision: state.storage_revision, pending_rewards: state.pending_rewards, });
    }));
    // POST /api/game/home_meridian/light
    router.post("/home_meridian/light", op(async (req, res, userId) => {
        const { stage, index } = req.body;
        if (typeof stage !== "number" || typeof index !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.lightHomeAcupoint(state, stage, index);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ...result, card_collection_progress: engine.cardCollectionService.publicProgress(state), storage_revision: state.storage_revision, ...staminaMultiplierResponse(state) });
    }));
    router.post("/activity/order_supply/claim", op(async (req, res, userId) => {
        const { activity_id, expected_claim_count } = req.body ?? {};
        if (!Number.isSafeInteger(activity_id) || activity_id <= 0 || !Number.isSafeInteger(expected_claim_count) || expected_claim_count < 0) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const updated = structuredClone(await getOrCreateState(userId));
        const result = engine.activityEngine.claimOrderSupply(updated, activity_id, expected_claim_count, engine);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, updated);
        engine.enrichGridWithRechargeRemaining(updated.grid);
        res.json({ ...result, activity_id, activity_progress: updated.activity_progress, grid: updated.grid,
            pending_rewards: updated.pending_rewards, newVersion: updated.version, storage_revision: updated.storage_revision });
    }));
    router.post("/battle_pass/unlock", op(async (req, res, userId) => {
        const activityId = Number(req.body.activity_id);
        if (!Number.isInteger(activityId) || activityId <= 0) {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const updatedState = structuredClone(state);
        const result = engine.battlePassService.unlock(updatedState, activityId);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        try {
            await storage.saveState(userId, updatedState);
        }
        catch {
            res.status(500).json({ error: "save_failed" });
            return;
        }
        res.json({ ok: true, battle_pass_progress: result.progress, spirit_stones: updatedState.spirit_stones });
    }));
    router.post("/battle_pass/claim", op(async (req, res, userId) => {
        const activityId = Number(req.body.activity_id);
        const level = Number(req.body.level);
        const track = req.body.track;
        if (!Number.isInteger(activityId) || !Number.isInteger(level) || typeof track !== "string") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const updatedState = structuredClone(state);
        const result = engine.battlePassService.claim(updatedState, activityId, level, track, rewards => engine.applyRewards(updatedState, rewards));
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        try {
            await storage.saveState(userId, updatedState);
        }
        catch {
            res.status(500).json({ error: "save_failed" });
            return;
        }
        res.json({
            ok: true,
            battle_pass_progress: result.progress,
            rewards: result.rewards,
            spirit_stones: updatedState.spirit_stones,
            stamina: updatedState.stamina,
            ...staminaMultiplierResponse(updatedState),
            cultivation: updatedState.cultivation,
            storage_revision: updatedState.storage_revision, pending_rewards: updatedState.pending_rewards,
        });
    }));
    // POST /api/game/home_meridian/run
    router.post("/home_meridian/run", op(async (req, res, userId) => {
        const { stage } = req.body;
        if (typeof stage !== "number") {
            res.status(400).json({ error: "invalid_params" });
            return;
        }
        const state = await getOrCreateState(userId);
        const result = engine.runHomeMeridianCirculation(state, stage);
        if (!result.ok) {
            res.status(400).json({ error: result.reason });
            return;
        }
        await storage.saveState(userId, state);
        res.json({ ...result, card_collection_progress: engine.cardCollectionService.publicProgress(state), storage_revision: state.storage_revision, ...staminaMultiplierResponse(state) });
    }));
    // GET /api/leaderboard
    router.get("/leaderboard", async (_req, res) => {
        try {
            const limit = Math.min(parseInt(_req.query.limit) || 50, 100);
            const entries = await storage.getLeaderboard(limit);
            res.json({ entries });
        }
        catch (err) {
            console.error("[game] leaderboard error:", err);
            res.status(500).json({ error: "internal_error" });
        }
    });
    return router;
}
