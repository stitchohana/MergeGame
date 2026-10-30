"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GoldenFingerService = void 0;
const reset_period_1 = require("./reset_period");
const fail = (reason) => ({ ok: false, reason });
// All dependent state is restored together, including automatically granted quest rewards.
// These monotonic fields must survive an undo, so retries cannot mint items or reroll entropy.
const protectedKeys = new Set(["golden_finger", "version", "storage_revision", "uid_counter",
    "spawn_seed", "spawn_sequence", "spawn_history"]);
function canonical(value) {
    if (Array.isArray(value))
        return value.map(canonical);
    if (value && typeof value === "object")
        return Object.fromEntries(Object.keys(value).sort()
            .filter(key => !["_recharge_remaining", "_craft_progress"].includes(key))
            .map(key => [key, canonical(value[key])]));
    return value;
}
class GoldenFingerService {
    engine;
    artifacts;
    realms;
    resetHour;
    rewindSeconds;
    constructor(config, engine) {
        this.engine = engine;
        if (!config) {
            this.artifacts = [];
            this.realms = [];
            this.resetHour = 5;
            this.rewindSeconds = 60;
            return;
        }
        this.artifacts = config.artifacts;
        this.realms = config.realms;
        this.resetHour = config.settings?.[0]?.reset_hour;
        this.rewindSeconds = config.settings?.[0]?.rewind_seconds;
        if (!Array.isArray(this.artifacts) || this.artifacts.length !== 3
            || new Set(this.artifacts.map(a => a.id)).size !== 3
            || !["basin", "furnace", "sand"].every(id => this.artifacts.some(a => a.id === id))
            || this.artifacts.some(a => ![a.unlock_level, a.daily_free, a.daily_buy_limit, a.base_cost, a.cost_increment]
                .every(n => Number.isSafeInteger(n) && n > 0))
            || this.artifacts.some(a => engine.cultivationStages[a.unlock_level - 1]?.name !== a.unlock_label)
            || !Number.isInteger(this.resetHour) || this.resetHour < 0 || this.resetHour > 23
            || !Number.isSafeInteger(this.rewindSeconds) || this.rewindSeconds <= 0
            || !Array.isArray(this.realms) || !this.realms.length
            || this.realms[this.realms.length - 1].cultivation_max < engine.cultivationStages.length
            || this.realms.some((r, index) => ![r.cultivation_min, r.cultivation_max, r.level_cap].every(n => Number.isSafeInteger(n) && n > 0)
                || r.cultivation_max < r.cultivation_min || r.cultivation_min !== (index ? this.realms[index - 1].cultivation_max + 1 : 1))) {
            throw new Error("invalid_golden_finger_config");
        }
    }
    progress(state, id, now) {
        const period = (0, reset_period_1.getResetPeriod)(now, this.resetHour).day;
        const p = state.golden_finger?.progress[id];
        return p?.period === period ? { ...p } : { period, free_used: 0, bought: 0, paid_used: 0 };
    }
    data(state) {
        return state.golden_finger ??= { progress: {}, receipts: [] };
    }
    levelCap(state) {
        return this.realms.find(r => state.cultivation.current_level >= r.cultivation_min
            && state.cultivation.current_level <= r.cultivation_max)?.level_cap ?? 0;
    }
    plain(item) {
        return !!item && item.type === 0 && !item.effect_type && !(item.spawns?.length)
            && !(item.max_charges > 0) && Number.isSafeInteger(item.value) && item.value > 0;
    }
    materialPool(state) {
        const cap = this.levelCap(state);
        const productionIds = [...(state.unlocked_production_item_ids ?? []), ...state.grid.map(i => i.id)];
        const groups = new Set();
        for (const id of productionIds) {
            const production = this.engine.getItemData(id);
            for (const source of [...(production?.spawns ?? []).map(s => s.id), ...(production?.fixed_spawns ?? [])]) {
                const item = this.engine.getItemData(source);
                if (this.plain(item))
                    groups.add(item.group_id);
            }
        }
        return this.engine.getAllItemDefs().filter(item => this.plain(item) && groups.has(item.group_id)
            && item.level <= cap);
    }
    fingerprint(state) {
        const copy = { ...state };
        for (const key of ["golden_finger", "storage_revision", "spawn_history", "last_stamina_tick"])
            delete copy[key];
        if (copy.cultivation) {
            copy.cultivation = { ...copy.cultivation };
            delete copy.cultivation.last_tick_time;
        }
        return JSON.stringify(canonical(copy));
    }
    snapshot(state) {
        if (state.board_type === 1 || state.cultivation.current_level < 6 || !this.artifacts.length)
            return {};
        const out = {};
        for (const [key, value] of Object.entries(state))
            if (!protectedKeys.has(key))
                out[key] = structuredClone(value);
        return out;
    }
    capture(state, before, label, now = Date.now()) {
        if (state.board_type === 1 || state.cultivation.current_level < 6 || !this.artifacts.length || !Object.keys(before).length)
            return;
        this.data(state).rewind = { at: now, label, before, version: state.version, after: this.fingerprint(state) };
    }
    rewindValid(state, now) {
        const r = state.golden_finger?.rewind;
        return !!r && now >= r.at && now - r.at <= this.rewindSeconds * 1000
            && r.version === state.version && r.after === this.fingerprint(state);
    }
    view(state, now = Date.now()) {
        const pool = this.materialPool(state);
        const net = Math.max(0, ...pool.map(item => {
            const top = pool.filter(i => i.group_id === item.group_id).sort((a, b) => b.level - a.level)[0];
            return top.level > item.level ? 2 * (top.sell_price ?? 0) - (item.sell_price ?? 0) : 0;
        }));
        return { period_key: (0, reset_period_1.getResetPeriod)(now, this.resetHour).day, reset_hour: this.resetHour,
            next_reset_at: (Math.floor((now + (8 - this.resetHour) * 3600000) / 86400000) + 1) * 86400000 - (8 - this.resetHour) * 3600000,
            level_cap: this.levelCap(state), rewind: { available: this.rewindValid(state, now),
                label: state.golden_finger?.rewind?.label ?? "", expires_at: (state.golden_finger?.rewind?.at ?? 0) + this.rewindSeconds * 1000 },
            artifacts: this.artifacts.map(a => {
                const p = this.progress(state, a.id, now);
                const base = a.id === "basin" ? Math.max(a.base_cost, Math.ceil(net * 1.1)) : a.base_cost;
                return { ...a, unlocked: state.cultivation.current_level >= a.unlock_level,
                    free_remaining: a.daily_free - p.free_used, paid_remaining: p.bought - p.paid_used,
                    remaining: a.daily_free - p.free_used + p.bought - p.paid_used,
                    purchase_count: p.bought, purchases_remaining: a.daily_buy_limit - p.bought,
                    next_cost: base + p.bought * Math.max(a.cost_increment, a.id === "basin" ? base : 0) };
            }) };
    }
    preview(state, selection, now = Date.now()) {
        const a = this.view(state, now).artifacts.find(a => a.id === selection.artifact);
        if (!a)
            return fail("invalid_artifact");
        if (!a.unlocked)
            return fail("artifact_locked");
        if (state.board_type === 1)
            return fail("main_board_only");
        const pool = this.materialPool(state);
        if (a.id === "sand") {
            if (selection.mode === "rewind") {
                if (!this.rewindValid(state, now))
                    return fail("rewind_unavailable");
                const rewind = state.golden_finger.rewind;
                const before = rewind.before;
                return { ok: true, mode: "rewind", label: state.golden_finger.rewind.label,
                    operation_at: rewind.at,
                    stone_delta: (before.spirit_stones ?? 0) - state.spirit_stones,
                    stamina_delta: (before.stamina ?? 0) - state.stamina,
                    qi_delta: (before.cultivation?.current_qi ?? 0) - state.cultivation.current_qi,
                    expires_at: state.golden_finger.rewind.at + this.rewindSeconds * 1000 };
            }
            if (selection.mode !== "accelerate" || !Number.isSafeInteger(selection.uid))
                return fail("invalid_params");
            const item = state.grid.find(i => i.uid === selection.uid);
            if (!item)
                return fail("item_not_found");
            const def = this.engine.getItemData(item.id);
            const craft = item.craft;
            if (def?.type === 2 && craft?._craft_state === 2) {
                const remaining = Math.ceil((craft._craft_recipe?.craft_time * 1000 + craft._craft_start_time - now) / 1000);
                if (!(remaining > 0))
                    return fail("already_ready");
                return { ok: true, mode: "accelerate", kind: "craft", uid: item.uid, name: def.name,
                    remaining_seconds: remaining, original_cost: Math.ceil(remaining / 60) * this.engine.speedupConfig.craftStoneCostPerMinute };
            }
            const maxCharges = def?.max_charges ?? 0;
            if (def && maxCharges > 0 && (def.recharge_time ?? 0) > 0 && (item.charges ?? maxCharges) < maxCharges) {
                const remaining = Math.ceil(((item.last_charge_time ?? now) + def.recharge_time * 1000 - now) / 1000);
                if (!(remaining > 0))
                    return fail("already_ready");
                return { ok: true, mode: "accelerate", kind: "launcher", uid: item.uid, name: def.name,
                    remaining_seconds: remaining, original_cost: Math.ceil(remaining / 60) * this.engine.speedupConfig.launcherStoneCostPerMinute };
            }
            return fail("not_waiting");
        }
        if (!Array.isArray(selection.uids) || selection.uids.length !== 1
            || !selection.uids.every(n => Number.isSafeInteger(n) && n > 0)
            || new Set(selection.uids).size !== selection.uids.length)
            return fail("invalid_materials");
        const inputs = [];
        for (const uid of selection.uids) {
            const item = state.grid.find(i => i.uid === uid);
            if (!item || item.immovable || item.craft || item.storage || item.charges !== undefined || item.atk_base
                || !pool.some(d => d.id === item.id))
                return fail("invalid_materials");
            inputs.push(item);
        }
        const first = this.engine.getItemData(inputs[0].id);
        const target = a.id === "basin" ? pool.filter(i => i.group_id === first.group_id).sort((a, b) => b.level - a.level)[0]
            : pool.find(i => i.id === selection.target_id);
        if (!target)
            return fail("invalid_target");
        if (a.id === "basin" && first.level >= target.level)
            return fail("requires_lower_level");
        if (a.id === "furnace" && (first.level !== target.level || first.id === target.id))
            return fail("same_level_other_item");
        const inputValue = inputs.reduce((sum, i) => sum + this.engine.getItemData(i.id).value, 0);
        if (!Number.isSafeInteger(inputValue))
            return fail("invalid_materials");
        return { ok: true, output_id: target.id, output_name: target.name, output_count: a.id === "basin" ? 2 : 1,
            input_value: inputValue, output_value: target.value, excess_value: 0 };
    }
    transact(state, action, body, now = Date.now()) {
        if (!["use", "buy"].includes(action) || !body || typeof body.request_id !== "string"
            || !/^[A-Za-z0-9._:-]{1,96}$/.test(body.request_id) || !Number.isSafeInteger(body.version)
            || typeof body.period_key !== "string")
            return fail("invalid_params");
        const signature = JSON.stringify(canonical({ ...body, action, request_id: undefined }));
        const previous = state.golden_finger?.receipts.find(r => r.request_id === body.request_id);
        if (previous)
            return previous.signature === signature ? { ...previous.result, replayed: true } : fail("state_conflict");
        const view = this.view(state, now);
        const a = view.artifacts.find(a => a.id === body.artifact);
        if (!a)
            return fail("invalid_artifact");
        if (!a.unlocked)
            return fail("artifact_locked");
        if (body.version !== state.version || body.period_key !== view.period_key)
            return fail("state_conflict");
        const p = this.progress(state, a.id, now);
        let result;
        let delivery = {};
        if (action === "buy") {
            if (body.expected_cost !== a.next_cost || body.expected_purchase_count !== p.bought)
                return fail("state_conflict");
            if (a.purchases_remaining <= 0)
                return fail("daily_limit");
            if (state.spirit_stones < a.next_cost)
                return fail("insufficient_stones");
            // A purchase invalidates an old rewind rather than restoring a pre-purchase balance.
            state.spirit_stones -= a.next_cost;
            p.bought++;
            result = { ok: true, action, artifact: a.id, cost: a.next_cost };
        }
        else {
            if (a.remaining <= 0)
                return fail("no_uses");
            const preview = this.preview(state, body, now);
            if (!preview.ok)
                return preview;
            if (!body.quote || JSON.stringify(canonical(body.quote)) !== JSON.stringify(canonical(this.quoteKey(preview))))
                return fail("state_conflict");
            if (a.id !== "sand") {
                const source = state.grid.find(i => i.uid === body.uids[0]);
                state.grid = state.grid.filter(i => !body.uids.includes(i.uid));
                const spawnedItems = [];
                const pendingItems = [];
                const occupied = new Map(state.grid.map(i => [this.engine.posKey(i.col, i.row), i]));
                for (let n = 0; n < preview.output_count; n++) {
                    const reward = { uid: this.engine._nextUid(state), id: preview.output_id, name: preview.output_name };
                    const pos = this.engine.findNearestEmpty(occupied, source.col, source.row);
                    if (pos) {
                        const item = { uid: reward.uid, id: reward.id, ...pos };
                        state.grid.push(item);
                        occupied.set(this.engine.posKey(pos.col, pos.row), item);
                        spawnedItems.push(item);
                    }
                    else {
                        state.pending_rewards.push(reward);
                        pendingItems.push(reward);
                    }
                }
                delivery = { spawned_items: spawnedItems, pending_items: pendingItems, pending_rewards_added: pendingItems.length };
                this.engine.recordItemDiscovery(state, preview.output_id);
            }
            else if (body.mode === "rewind") {
                const revertedVersion = state.golden_finger.rewind.version;
                const before = state.golden_finger.rewind.before;
                for (const key of Object.keys(state))
                    if (!protectedKeys.has(key))
                        delete state[key];
                Object.assign(state, structuredClone(before));
                for (const entry of state.spawn_history) {
                    if (entry.result.newVersion === revertedVersion)
                        entry.result.reverted = true;
                }
            }
            else {
                const item = state.grid.find(i => i.uid === body.uid);
                if (preview.kind === "craft") {
                    item.craft._craft_state = 3;
                    item.craft._craft_progress = 1;
                }
                else {
                    item.charges = this.engine.getItemData(item.id).max_charges;
                    item.last_charge_time = now;
                }
            }
            if (p.free_used < a.daily_free)
                p.free_used++;
            else
                p.paid_used++;
            result = { ok: true, action, artifact: a.id, ...preview, ...delivery };
        }
        const data = this.data(state);
        delete data.rewind;
        data.progress[a.id] = p;
        // Bound receipt storage; old requests still fail the monotonically increasing version check.
        data.receipts = [...data.receipts, { request_id: body.request_id, signature, result }].slice(-128);
        state.version++;
        return result;
    }
    quoteKey(preview) {
        const { remaining_seconds, original_cost, ...key } = preview;
        return key;
    }
}
exports.GoldenFingerService = GoldenFingerService;
