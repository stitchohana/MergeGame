"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BattlePassService = void 0;
const interface_1 = require("../storage/interface");
const activity_access_1 = require("./activity_access");
const newProgress = (periodKey) => ({
    points: 0,
    premium_unlocked: false,
    free_claimed_levels: [],
    premium_claimed_levels: [],
    ...(periodKey ? { period_key: periodKey } : {}),
});
class BattlePassService {
    passes = new Map();
    activities = new Map();
    premiumUnlockCost;
    pointsPerValue;
    constructor(config, activitiesData, tokensData, gameConfig) {
        this.premiumUnlockCost = Number(gameConfig?.battle_pass?.premium_unlock_cost);
        this.pointsPerValue = Number(gameConfig?.battle_pass?.points_per_value);
        if (!Number.isInteger(this.premiumUnlockCost) || this.premiumUnlockCost < 0) {
            throw new Error("battle_pass_invalid_unlock_cost");
        }
        if (!Number.isFinite(this.pointsPerValue) || this.pointsPerValue <= 0) {
            throw new Error("battle_pass_invalid_points_per_value");
        }
        const activities = Array.isArray(activitiesData?.activities) ? activitiesData.activities : [];
        const tokens = Array.isArray(tokensData?.tokens) ? tokensData.tokens : [];
        const tokenIds = new Set(tokens.map(token => Number(token.id)));
        for (const activity of activities)
            this.activities.set(Number(activity.id), activity);
        const definitions = Array.isArray(config?.passes) ? config.passes : [];
        if (definitions.length > 1)
            throw new Error("battle_pass_only_one_enabled_pass_supported");
        for (const definition of definitions) {
            if (!Number.isInteger(definition.activity_id) || this.passes.has(definition.activity_id)) {
                throw new Error("battle_pass_invalid_or_duplicate_activity_id");
            }
            const activity = this.activities.get(definition.activity_id);
            if (!activity)
                throw new Error("battle_pass_activity_not_found");
            if (definition.start_time !== undefined || definition.end_time !== undefined) {
                throw new Error("battle_pass_time_must_come_from_activity");
            }
            if (!tokenIds.has(definition.points_token_id))
                throw new Error("battle_pass_points_token_not_found");
            if (activity.enabled === true && activity.cycle === interface_1.ActivityCycle.ONCE) {
                const start = activity.start_time ? Date.parse(activity.start_time) : Number.NaN;
                const end = activity.end_time ? Date.parse(activity.end_time) : Number.NaN;
                if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end) {
                    throw new Error("battle_pass_enabled_activity_requires_valid_dates");
                }
            }
            if (!Array.isArray(definition.tiers) || definition.tiers.length === 0) {
                throw new Error("battle_pass_tiers_required");
            }
            let previousLevel = 0;
            let previousPoints = -1;
            for (const tier of definition.tiers) {
                if (!Number.isInteger(tier.level) || tier.level <= previousLevel
                    || !Number.isInteger(tier.required_points) || tier.required_points < 0
                    || tier.required_points < previousPoints) {
                    throw new Error("battle_pass_invalid_tier_order");
                }
                this.validateRewards(tier.free_rewards, tokenIds);
                this.validateRewards(tier.premium_rewards, tokenIds);
                previousLevel = tier.level;
                previousPoints = tier.required_points;
            }
            this.passes.set(definition.activity_id, definition);
        }
    }
    validateRewards(rewards, tokenIds) {
        if (!rewards || typeof rewards !== "object")
            throw new Error("battle_pass_invalid_rewards");
        for (const token of rewards.tokens ?? []) {
            if (!tokenIds.has(token.token) || !Number.isFinite(token.amount) || token.amount < 0) {
                throw new Error("battle_pass_invalid_token_reward");
            }
        }
        for (const item of rewards.items ?? []) {
            if (!Number.isInteger(item.id) || item.id <= 0 || !Number.isInteger(item.count) || item.count < 0) {
                throw new Error("battle_pass_invalid_item_reward");
            }
        }
    }
    getDefinitions() {
        return [...this.passes.values()];
    }
    getDefinition(activityId) {
        return this.passes.get(activityId);
    }
    getPeriodKey(now = Date.now()) {
        // Battle pass seasons follow China Standard Time calendar months.
        const chinaNow = new Date(now + 8 * 60 * 60 * 1000);
        return `${chinaNow.getUTCFullYear()}-${String(chinaNow.getUTCMonth() + 1).padStart(2, "0")}`;
    }
    isMonthly(activityId) {
        return this.activities.get(activityId)?.cycle === interface_1.ActivityCycle.MONTHLY;
    }
    ensureProgress(state, now = Date.now()) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return {};
        state.battle_pass_progress ??= {};
        const periodKey = this.getPeriodKey(now);
        for (const activityId of this.passes.keys()) {
            const current = state.battle_pass_progress[activityId];
            if (!current)
                state.battle_pass_progress[activityId] = newProgress(this.isMonthly(activityId) ? periodKey : undefined);
            else {
                if (this.isMonthly(activityId) && current.period_key !== periodKey) {
                    state.battle_pass_progress[activityId] = newProgress(periodKey);
                    continue;
                }
            }
        }
        return state.battle_pass_progress;
    }
    isActive(activityId, now = Date.now()) {
        const activity = this.activities.get(activityId);
        if (!activity || activity.enabled !== true)
            return false;
        if (activity.cycle === interface_1.ActivityCycle.MONTHLY)
            return true;
        const start = Date.parse(activity.start_time ?? "");
        const end = Date.parse(activity.end_time ?? "");
        return Number.isFinite(start) && Number.isFinite(end) && now >= start && now < end;
    }
    awardOrderPoints(state, totalValue, requestId = "", now = Date.now()) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return false;
        state.battle_pass_order_requests ??= [];
        if (requestId && state.battle_pass_order_requests.includes(requestId))
            return false;
        if (requestId) {
            state.battle_pass_order_requests.push(requestId);
            if (state.battle_pass_order_requests.length > 1000)
                state.battle_pass_order_requests.splice(0, state.battle_pass_order_requests.length - 1000);
        }
        if (!Number.isFinite(totalValue) || totalValue <= 0)
            return false;
        let changed = false;
        const progress = this.ensureProgress(state, now);
        for (const pass of this.passes.values()) {
            if (!this.isActive(pass.activity_id, now))
                continue;
            const points = Math.floor(totalValue * this.pointsPerValue);
            if (points <= 0)
                continue;
            progress[pass.activity_id].points += points;
            changed = true;
        }
        return changed;
    }
    unlock(state, activityId, now = Date.now()) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return { ok: false, reason: "activity_locked" };
        const pass = this.passes.get(activityId);
        if (!pass)
            return { ok: false, reason: "invalid_activity" };
        if (!this.isActive(activityId, now))
            return { ok: false, reason: "activity_inactive" };
        const progress = this.ensureProgress(state, now)[activityId];
        if (progress.premium_unlocked)
            return { ok: true, progress: this.ensureProgress(state, now) };
        if (state.spirit_stones < this.premiumUnlockCost)
            return { ok: false, reason: "insufficient_spirit_stones" };
        state.spirit_stones -= this.premiumUnlockCost;
        progress.premium_unlocked = true;
        return { ok: true, progress: this.ensureProgress(state, now) };
    }
    claim(state, activityId, level, track, applyRewards, now = Date.now()) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return { ok: false, reason: "activity_locked" };
        const pass = this.passes.get(activityId);
        if (!pass)
            return { ok: false, reason: "invalid_activity" };
        if (!this.isActive(activityId, now))
            return { ok: false, reason: "activity_inactive" };
        if (track !== "free" && track !== "premium")
            return { ok: false, reason: "invalid_track" };
        const tier = pass.tiers.find(entry => entry.level === level);
        if (!tier)
            return { ok: false, reason: "invalid_level" };
        const progress = this.ensureProgress(state, now)[activityId];
        if (progress.points < tier.required_points)
            return { ok: false, reason: "insufficient_points" };
        if (track === "premium" && !progress.premium_unlocked)
            return { ok: false, reason: "premium_not_unlocked" };
        const claimed = track === "free" ? progress.free_claimed_levels : progress.premium_claimed_levels;
        if (claimed.includes(level))
            return { ok: false, reason: "already_claimed" };
        const rewards = applyRewards(track === "free" ? tier.free_rewards : tier.premium_rewards);
        claimed.push(level);
        return { ok: true, progress: this.ensureProgress(state, now), rewards };
    }
    settleExpired(state, applyRewards, now = Date.now()) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return false;
        let changed = false;
        const progress = this.ensureProgress(state, now);
        for (const pass of this.passes.values()) {
            const activity = this.activities.get(pass.activity_id);
            if (activity?.cycle === interface_1.ActivityCycle.MONTHLY)
                continue;
            const end = activity?.end_time ? Date.parse(activity.end_time) : Number.NaN;
            if (activity?.enabled !== true || !Number.isFinite(end) || now < end)
                continue;
            const passProgress = progress[pass.activity_id];
            for (const tier of pass.tiers) {
                if (passProgress.points < tier.required_points)
                    continue;
                if (!passProgress.free_claimed_levels.includes(tier.level)) {
                    applyRewards(tier.free_rewards);
                    passProgress.free_claimed_levels.push(tier.level);
                    changed = true;
                }
                if (passProgress.premium_unlocked && !passProgress.premium_claimed_levels.includes(tier.level)) {
                    applyRewards(tier.premium_rewards);
                    passProgress.premium_claimed_levels.push(tier.level);
                    changed = true;
                }
            }
        }
        return changed;
    }
}
exports.BattlePassService = BattlePassService;
