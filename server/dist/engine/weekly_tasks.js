"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WeeklyTaskService = void 0;
const activity_access_1 = require("./activity_access");
const reset_period_1 = require("./reset_period");
class WeeklyTaskService {
    activities;
    resetHour;
    definitions;
    constructor(data, activities, resetHour, quests) {
        this.activities = activities;
        this.resetHour = resetHour;
        this.definitions = structuredClone(data.weekly_tasks);
        const activityIds = new Set();
        const questIds = new Set();
        for (const def of this.definitions) {
            if (activityIds.has(def.activity_id) || !activities.some(a => a.id === def.activity_id))
                throw new Error("weekly_invalid_activity");
            activityIds.add(def.activity_id);
            if (!Number.isSafeInteger(def.points_per_task) || def.points_per_task <= 0)
                throw new Error("weekly_invalid_points");
            const ids = def.daily_quests.flat();
            if (def.daily_quests.length !== 7 || new Set(ids).size !== ids.length
                || ids.some(id => questIds.has(id) || !quests.some(q => q.id === id && q.reset_cycle === 2)))
                throw new Error("weekly_invalid_quests");
            ids.forEach(id => questIds.add(id));
            let previous = 0;
            const stages = new Set();
            for (const milestone of def.milestones) {
                if (!Number.isSafeInteger(milestone.stage) || milestone.stage <= 0 || stages.has(milestone.stage)
                    || !Number.isSafeInteger(milestone.required_points) || milestone.required_points <= previous
                    || milestone.required_points > ids.length * def.points_per_task)
                    throw new Error("weekly_invalid_milestone");
                stages.add(milestone.stage);
                previous = milestone.required_points;
                const reward = milestone.rewards;
                if (!reward || !(reward.tokens?.length || reward.items?.length)
                    || reward.tokens?.some(t => t.token !== 3 || !Number.isSafeInteger(t.amount) || t.amount <= 0)
                    || reward.items?.some(i => !Number.isSafeInteger(i.id) || i.id <= 0 || !Number.isSafeInteger(i.count) || i.count <= 0))
                    throw new Error("weekly_invalid_reward");
            }
            if (!def.milestones.length)
                throw new Error("weekly_missing_milestones");
        }
    }
    periodKey(now = Date.now()) { return (0, reset_period_1.getResetPeriod)(now, this.resetHour).week; }
    ensureProgress(state) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return false;
        // This feature starts at zero on first unlock; completed tasks are never backfilled.
        let changed = false;
        if (!state.weekly_task_progress) {
            state.weekly_task_progress = {};
            changed = true;
        }
        const period = this.periodKey();
        for (const def of this.definitions) {
            const progress = state.weekly_task_progress[def.activity_id];
            if (!progress || period > progress.period_key) {
                state.weekly_task_progress[def.activity_id] = { period_key: period, points: 0, scored_quest_ids: [], claimed_stages: [] };
                changed = true;
            }
        }
        return changed;
    }
    questPoints(questId) {
        return this.definitions.find(d => d.daily_quests.some(day => day.includes(questId)))?.points_per_task ?? 0;
    }
    awardTaskReward(state, questId) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return;
        this.ensureProgress(state);
        for (const def of this.definitions) {
            if (!this.active(def.activity_id) || !def.daily_quests.some(day => day.includes(questId)))
                continue;
            const progress = state.weekly_task_progress[def.activity_id];
            if (progress.scored_quest_ids.includes(questId))
                continue;
            progress.scored_quest_ids.push(questId);
            progress.points += def.points_per_task;
        }
    }
    claim(state, activityId, stage, periodKey, apply) {
        if (!(0, activity_access_1.activitiesUnlocked)(state))
            return { ok: false, reason: "activity_locked" };
        const def = this.definitions.find(d => d.activity_id === activityId);
        const milestone = def?.milestones.find(m => m.stage === stage);
        if (!milestone)
            return { ok: false, reason: "invalid_stage" };
        if (!this.active(activityId))
            return { ok: false, reason: "activity_inactive" };
        this.ensureProgress(state);
        const progress = state.weekly_task_progress[activityId];
        if (periodKey !== progress.period_key)
            return { ok: false, reason: "state_conflict" };
        if (progress.claimed_stages.includes(stage))
            return { ok: false, reason: "already_claimed" };
        if (progress.points < milestone.required_points)
            return { ok: false, reason: "insufficient_points" };
        const rewards = apply(milestone.rewards);
        progress.claimed_stages.push(stage);
        return { ok: true, rewards };
    }
    publicProgress(state) {
        return (0, activity_access_1.activitiesUnlocked)(state) ? state.weekly_task_progress ?? {} : {};
    }
    active(id) {
        const activity = this.activities.find(a => a.id === id);
        if (!activity || activity.enabled === false)
            return false;
        const now = Date.now();
        return activity.cycle !== 0 || ((!activity.start_time || now >= Date.parse(activity.start_time))
            && (!activity.end_time || now < Date.parse(activity.end_time)));
    }
}
exports.WeeklyTaskService = WeeklyTaskService;
